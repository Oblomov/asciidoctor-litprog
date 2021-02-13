# Copyright (C) 2021 Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# This software is licensed under the MIT license. See LICENSE for details

require 'asciidoctor/extensions'

class LiterateProgrammingTreeProcessor < Asciidoctor::Extensions::TreeProcessor
  def initialize config = {}
    super config
    @roots = Hash.new { |hash, key| hash[key] = [] }
    @chunks = Hash.new { |hash, key| hash[key] = [] }
    @chunk_names = Set.new
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

  def is_chunk_ref line
    if line.match /^(\s*)<<(.*)>>\s*$/
      return full_title($2), $1
    else
      return false
    end
  end

  def recursive_tangle file, chunk_name, indent, chunk, stack
    stack.add chunk_name
    chunk.each do |line|
      ref, new_indent = is_chunk_ref line
      if ref
        # must not be in the stack
        raise RuntimeError, "Recursive reference to #{ref} from #{chunk_name}" if stack.include? ref
        # must be defined
        raise ArgumentError, "Found reference to undefined chunk #{ref}" unless @chunks.has_key? ref
        recursive_tangle file, ref, indent + new_indent, @chunks[ref], stack
      else
        file.puts indent + line
      end
    end
    stack.delete chunk_name
  end

  def tangle
    @roots.each do |name, initial_chunk|
      File.open(name, 'w') do |f|
        recursive_tangle f, name, '', initial_chunk, Set[]
      end
    end
  end

  def process_block block
    chunk_hash = @chunks
    if block.style == "source"
      # is this a root chunk?
      if block.attributes.has_key? 'output'
        chunk_hash = @roots
        chunk_title = block.attributes['output']
        raise ArgumentError, "Duplicate root chunk for #{chunk_title}" if chunk_hash.has_key?(chunk_title)
      else
        # We use the block title (TODO up to the first full stop or colon) as chunk name
        title = block.attributes['title']
        chunk_title = full_title title
        block.title = chunk_title if title != chunk_title
      end
    else
      # TODO check if first line is <<title>>=
      return
    end

    @chunk_names.add chunk_title

    # append the lines TODO preprocessor directives for file and line
    chunk_hash[chunk_title] += block.lines
    block.lines.each do |line|
      mentioned, _ = is_chunk_ref line
      @chunk_names.add mentioned if mentioned
    end
  end

  def process doc
    doc.find_by context: :listing do |block|
      process_block block
    end
    tangle
    doc
  end

end

Asciidoctor::Extensions.register do
  tree_processor LiterateProgrammingTreeProcessor
end
