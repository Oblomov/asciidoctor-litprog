README.html: README.adoc lib/lp-bootstrap.rb
	asciidoctor --trace -Ilib -rlp-bootstrap.rb README.adoc -o README.html

lib/litprog.rb: README.html

MAKE_BOOTSTRAP_ARGS= -a 'litprog-file-map=litprog.rb>lp-bootstrap.rb' \
                     -a litprog-line-template= \
                     -a litprog-line-template-css=
update-bootstrap: test
	asciidoctor --trace -Ilib -rlitprog.rb ${MAKE_BOOTSTRAP_ARGS} README.adoc -o README.html

self-check: lib/litprog.rb
	mv lib/litprog.rb lib/lp-test.rb && \
	asciidoctor --trace -Ilib -rlp-test.rb README.adoc -o README.html && \
	diff -u lib/lp-test.rb lib/litprog.rb && \
	rm lib/lp-test.rb

aweb-check: lib/litprog.rb test/aweb-alike.adoc test/aweb.reference
	asciidoctor --trace -Ilib -rlitprog.rb test/aweb-alike.adoc -o /dev/null > test/aweb.stdout && \
		diff -u test/aweb.reference test/aweb.result && \
		diff -u test/aweb.stdout.reference test/aweb.stdout

noweb-check: lib/litprog.rb test/noweb-alike.adoc # TODO
	asciidoctor --trace -Ilib -rlitprog.rb test/noweb-alike.adoc -o /dev/null

test: self-check aweb-check

update-bootstrap: lib/lp-bootstrap.rb

clean:
	rm -rf README.html README.litprog.dot lib/litprog.rb lib/lp-test.rb css test/aweb.result test/aweb.stdout

.PHONY: self-check test update-bootstrap clean

.NOTPARALLEL:
