# Copyright (C) 2021–2024 Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# This software is licensed under the MIT license. See LICENSE for details

require 'asciidoctor/extensions'
require 'fileutils'

class LitProgRouge < (Asciidoctor::SyntaxHighlighter.for 'rouge')
  register_for 'rouge'

  def create_lexer node, source, lang, opts
    lexer = super
    class << lexer
      def step state, stream
        if state == get_state(:root) or stream.beginning_of_line?
          if stream.scan /((?:^|[\r\n]+)\s*)(<<.*>>)(\s*)$/
            yield_token Text::Whitespace, stream.captures[0]
            yield_token Comment::Special, stream.captures[1]
            yield_token Text::Whitespace, stream.captures[2]
            return true
          end
        end
        super
      end
    end
    lexer
  end

  def create_formatter node, source, lang, opts
    formatter = super
    # make the document catalog accessible to the formatter
    formatter.instance_variable_set :@litprog_catalog, node.document.catalog[:lit_prog_chunks]

    class << formatter
      include Asciidoctor::Logging
      def litprog_link id, text
        target = '#' + id
        "<a class='litprog-nav' href='#{target}'>#{text}</a>"
      end
      def span tok, val
        special = tok.matches? ::Rouge::Token::Tokens::Comment::Special
        if special
          m = val.match /<<(.*)>>/
          if m
            title = m[1]
            pfx = title.chomp("...")
            if pfx != title
              fulltitle, hits = @litprog_catalog.find { |k, v| k.start_with? pfx }
              fulltitle = fulltitle.gsub("'", '&apos;')
              title = "<abbr title='#{fulltitle}'>#{escape_special_html_chars title}</abbr>"
            else
              hits = @litprog_catalog[title]
              title = escape_special_html_chars title
            end
            if hits.empty?
              logger.warn "Unresolved chunk reference #{title.inspect} found in special comment while formatting source"
            else
              first, *rest = *hits
              safe_val = "&lt;&lt;" + litprog_link(first, title)
              if rest.length > 0
                safe_val += "<sup> " + rest.each_with_index.map { |hit, index|
                  litprog_link(hit, index+2)
                }.join(' ') + "</sup>"
              end
              safe_val += "&gt;&gt;"
              return safe_span tok, safe_val
            end
          end
        end
        super
      end
    end
    formatter
  end
end

module Asciidoctor
  class Block
    def litprog_raw_title
      @title
    end
  end
end

class LiterateProgrammingTreeProcessor < Asciidoctor::Extensions::TreeProcessor
  include Asciidoctor::Logging

  VERSION = '2.3'
  def initialize config = {}
    super config
    @roots = Hash.new { |hash, key| hash[key] = [] }
    @chunks = Hash.new { |hash, key| hash[key] = [] }
    @chunk_names = Set.new
    @chunk_backrefs = Hash.new { |hash, key| hash[key] = [] }
    @line_directive_template = { }
    @active_line_directive_template = []
    @chunk_blocks = Hash.new { |hash, key| hash[key] = [] }
  end

  def full_title string
    pfx = string.chomp("...")
    # nothing to do if title was not shortened
    return string if string == pfx
    hits = @chunk_names.find_all { |s| s.start_with? pfx }
    raise ArgumentError, "No chunk #{string}" if hits.length == 0
    raise ArgumentError, "Chunk title #{string} is not unique" if hits.length > 1
    hits.first
  end
  def add_chunk_ref includer, includer_block_id, included
    @chunk_backrefs[included].push [includer, includer_block_id]
  end
  def output_line_directive file, fname, lineno
    template = @active_line_directive_template.last
    file.puts( template % { line: lineno, file: fname}) unless template.nil_or_empty?
  end
  def is_chunk_ref line
    if line.match /^(\s*)<<(.*)>>\s*$/
      return full_title($2), $1
    else
      return false
    end
  end
  def add_chunk_block_with_id chunk_title, block
    block_count = @chunk_blocks[chunk_title].append(block).size
    title_for_id = "_chunk_#{chunk_title}_block_#{block_count}"
    new_id = Asciidoctor::Section.generate_id title_for_id, block.document
    # TODO error handling
    block.document.register :refs, [new_id, block]
    block.id = new_id unless block.id
    block.document.catalog[:lit_prog_chunks][chunk_title] << new_id
    return new_id
  end
  def remap_chunk_block_id doc, chunk_block_id
    return doc.catalog[:refs][chunk_block_id].id
  end
  def apply_supported_subs block
    if block.subs.include? :attributes
       block.apply_subs block.lines, [:attributes]
    else
       block.lines
    end
  end
  def dot_chunk_id doc, chunk_name
    block_id = doc.catalog[:lit_prog_chunks][chunk_name].first
    return block_id.gsub(/_block_\d+$/,'')
  end
  def count_chunk_blocks doc, chunk_name
    doc.catalog[:lit_prog_chunks][chunk_name].length
  end
  def limit_line_length text, maxlen
    words = text.split ' '
    ret = []
    line = ''
    words.each { |word|
      if line.length > 0 and line.length + word.length > maxlen
        ret.push line
        line = ''
      end
      line += ' ' if line.length > 0
      line += word
    }
    ret.push line
    ret.join("\\n")
  end
  def quote_for_dot doc, chunk_name
    nblocks = count_chunk_blocks doc, chunk_name
    # start by escaping the name proper
    base = limit_line_length(chunk_name, 33).gsub('["<>|]', '\\\0')
    # add a <chunk> port to the base name
    base = "<chunk> #{base}"
    # add the other ports for multi-block chunks
    if nblocks > 1
      base += "| { " + 1.upto(nblocks).map { |i| "<block_#{i}> #{i}" }.join(' | ') + " }"
    end
    return '"' + base + '"'
  end
  def recursive_tangle file, chunk_name, indent, chunk, stack
    stack.add chunk_name
    fname = ''
    lineno = 0
    line_directive_template_push = 0
    chunk.each do |line|
      case line
      when Hash
        lang = line.fetch('language', '_')
        lang = '_' unless @line_directive_template.key? lang
        @active_line_directive_template.push @line_directive_template[lang]
        line_directive_template_push += 1
      when Asciidoctor::Reader::Cursor
        fname = line.file
        lineno = line.lineno + 1
        output_line_directive file, fname, lineno
      when String
        lineno += 1
        ref, new_indent = is_chunk_ref line
        if ref
          # must not be in the stack
          raise RuntimeError, "Recursive reference to #{ref} from #{chunk_name}" if stack.include? ref
          # must be defined
          raise ArgumentError, "Found reference to undefined chunk #{ref}" unless @chunks.has_key? ref
          # recurse and get line directive stack growth
          to_pop = recursive_tangle file, ref, indent + new_indent, @chunks[ref], stack
          output_line_directive file, fname, lineno
          # pop line directive stack
          @active_line_directive_template.pop to_pop
        else
          file.puts line.empty? ? line : indent + line
        end
      else
        raise TypeError, "Unknown chunk element #{line.inspect}"
      end
    end
    stack.delete chunk_name
    return line_directive_template_push
  end
  def tangle doc
    @line_directive_template['_'] = doc.attr('litprog-line-template').dup
    doc.attributes.each do |key, value|
      lang = key.dup
      if lang.delete_prefix! 'litprog-line-template-'
        @line_directive_template[lang] = value unless lang.empty?
      end
    end
    @active_line_directive_template.push @line_directive_template['_']
    docdir = doc.attributes['docdir']
    outdir = doc.attributes['litprog-outdir']
    if outdir and not outdir.empty?
      outdir = File.join(docdir, outdir)
      FileUtils.mkdir_p outdir
    else
      outdir = docdir
    end
    root_name_map = {}
    doc.attr('litprog-file-map').to_s.split ':' do |entry|
      entry.strip!
      cname, fname = entry.split '>', 2
      cname.strip!
      fname.strip!
      if cname.empty? or fname.empty?
        logger.warn 'empty chunk name in litprog-file-map ignored' if cname.empty?
        logger.warn 'empty file name in litprog-file-map ignored' if fname.empty?
        next
      end
      unless @roots.include? cname
        logger.warn "non-existent chunk #{cname} in litprog-file-map ignored"
        next
      end
      next if cname == fname # nothing to remap
      raise ArgumentError, "#{cname} remapped to existing #{fname}" if @roots.include? fname
      mapped_already = root_name_map.key fname
      raise ArgumentError, "#{cname} remapped to #{fname}, same as #{mapped_already}" if mapped_already
      root_name_map[cname] = fname
    end
    @roots.each do |name, initial_chunk|
      name = root_name_map.fetch name, name
      if name == '*'
        to_pop = recursive_tangle STDOUT, name, '', initial_chunk, Set[]
        @active_line_directive_template.pop to_pop
      else
        full_path = File.join(outdir, name)
        File.open(full_path, 'w') do |f|
          to_pop = recursive_tangle f, name, '', initial_chunk, Set[]
          @active_line_directive_template.pop to_pop
        end
      end
    end
  end
  def weave doc
    @chunk_blocks.each do |chunk_title, block_list|
      last_block_index = block_list.size - 1
      block_list.each_with_index do |block, i|
        links = []
        # link to previous block in this chunk
        links << "xref:\##{block_list[i-1].id}[⮝,role=prev]" if i > 0
        # link to next block in this chunk
        links << "xref:\##{block_list[i+1].id}[⮟,role=next]" if i != last_block_index
        # link to block(s) that include the chunk this block belongs to
        if @chunk_backrefs.key? chunk_title
          # uplinks are placed using unshift, so process them in reverse order
          @chunk_backrefs[chunk_title].reverse_each do |inc|
            includer, includer_block_id = inc
            if count_chunk_blocks(doc, includer) > 1
              includer_block_num = includer_block_id.split('_').last
              desc = "Used in: #{includer} [#{includer_block_num}]"
            else
              desc = "Used in: #{includer}"
            end
            # remap from the chunk-specific block ID to the Asciidoctor block ID
            includer_block_id = remap_chunk_block_id doc, includer_block_id
            links.unshift '|' if links.length > 0
            # TODO apparently AsciiDoc(tor) doesn't support anchor titles?
            # links.unshift "xref:\##{includer_block_id}[⏚,role=up,title=\"${desc}\"]"
            desc.gsub!("'",'&apos;')
            links.unshift "+++<a href='\##{includer_block_id}' class='up' title='#{desc}'>⏚</a>+++"
          end
        end
        if links.length > 0
          # protect against a nil title ---------v
          block.title = (block.litprog_raw_title || '') + ' [.litprog-nav]#' + (links * ' ') + '#'
        end
      end
    end
    if doc.attr('litprog-dot-graph')
      dotfile = doc.attr('docname') + '.litprog.dot'
      dotdir = doc.attr('outdir', '.', 'docdir')
      File.open(File.join(dotdir, dotfile), 'w') do |f|
        f.puts %(
      digraph {
        rankdir=LR;
        nodesep="1";
        overlap=false;
      )

        @chunk_backrefs.each { |chunk, refs|
          this_id = dot_chunk_id doc, chunk
          refs.each { |ref, block_id|
            ref_id = dot_chunk_id doc, ref
            port = count_chunk_blocks(doc, ref) == 1 ? "chunk" : block_id.match(/block_\d+$/)[0]
            f.puts "#{this_id}:chunk:e -> #{ref_id}:#{port}:w"
          }
        }
        @chunk_names.each { |chunk|
          chunk_id = dot_chunk_id doc, chunk
          quoted_chunk = quote_for_dot doc, chunk
          fontspec = @roots.key?(chunk) ? ",fontname=\"Monospace\"" : ""
          f.puts "#{chunk_id} [shape=record,label=#{quoted_chunk}#{fontspec}]"
        }

        f.puts '}'
      end
    end
  end
  def add_to_chunk chunk_hash, chunk_title, block_lines, block_id
    @chunk_names.add chunk_title
    chunk_hash[chunk_title] += block_lines

    block_lines.each do |line|
      mentioned, _ = is_chunk_ref line
      if mentioned
        @chunk_names.add mentioned
        add_chunk_ref chunk_title, block_id, mentioned
      end
    end
  end
  def process_source_block block
    chunk_hash = @chunks
    if block.attributes.has_key? 'output'
      chunk_hash = @roots
      chunk_title = block.attributes['output']
      raise ArgumentError, "Duplicate root chunk for #{chunk_title}" if @roots.has_key?(chunk_title)
    else
      # We use the block title (TODO up to the first full stop or colon) as chunk name
      title = block.litprog_raw_title
      chunk_title = full_title title
      block.title = chunk_title if title != chunk_title
    end
    chunk_hash[chunk_title].append block.attributes
    chunk_hash[chunk_title].append block.source_location
    block_lines = apply_supported_subs block
    block_id = add_chunk_block_with_id chunk_title, block
    add_to_chunk chunk_hash, chunk_title, block_lines, block_id
  end
  CHUNK_DEF_RX = /^<<(.*)>>=\s*$/
  def process_listing_block block
    return if block.lines.empty?
    return unless block.lines.first.match(CHUNK_DEF_RX)
    chunk_titles = [ full_title($1) ]
    block_location = block.source_location
    chunk_offset = 0
    block.lines.slice_when do |l1, l2|
      l2.match(CHUNK_DEF_RX) and chunk_titles.append(full_title $1)
    end.each do |lines|
      chunk_title = chunk_titles.shift
      block_lines = lines.drop 1
      chunk_hash = @chunks
      unless chunk_title.include? " "
        chunk_hash = @roots
        raise ArgumentError, "Duplicate root chunk for #{chunk_title}" if @roots.has_key?(chunk_title)
      end
      chunk_location = block_location.dup
      chunk_location.advance(chunk_offset + 1)
      chunk_hash[chunk_title].append(chunk_location)
      chunk_offset += lines.size
      block_id = add_chunk_block_with_id chunk_title, block
      add_to_chunk chunk_hash, chunk_title, block_lines, block_id
    end
  end
  def process doc
    doc.catalog[:lit_prog_chunks] = Hash.new { |h, k| h[k] = [] }
    doc.find_by context: :listing do |block|
      if block.style == 'source'
        process_source_block block
      else
        process_listing_block block
      end
    end
    tangle doc
    weave doc
    doc
  end
end
class LiterateProgrammingDocinfoProcessor < Asciidoctor::Extensions::DocinfoProcessor
  VERSION = '2.3'

  use_dsl
  at_location :head
  def process doc
%(<style>
span.litprog-nav {
  float: right;
  float: inline-end;
  font-style: normal;
}
span.litprog-nav a {
  text-decoration: none;
}
a.litprog-nav {
   text-decoration: none;
}
</style>)
  end
end

Asciidoctor::Extensions.register do
  preprocessor do
    process do |doc, reader|
      doc.sourcemap = true
      doc.set_attr 'litprog-line-template', '#line %{line} "%{file}"', false
      doc.set_attr 'litprog-line-template-css', '/* %{file}:%{line} */', false
      nil
    end
  end
  tree_processor LiterateProgrammingTreeProcessor
  docinfo_processor LiterateProgrammingDocinfoProcessor
end
