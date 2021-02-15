README.html: README.adoc lib/lp-bootstrap.rb
	asciidoctor --trace -Ilib -rlp-bootstrap.rb README.adoc -o README.html

lib/litprog.rb: README.html

update-bootstrap: lib/litprog.rb
	grep -v '^#line' $< > lib/lp-bootstrap.rb

self-check: lib/litprog.rb
	mv lib/litprog.rb lib/lp-test.rb && \
	asciidoctor --trace -Ilib -rlp-test.rb README.adoc -o README.html && \
	diff lib/lp-test.rb lib/litprog.rb && \
	rm lib/lp-test.rb

test: self-check
	asciidoctor --trace -Ilib -rlitprog.rb test/noweb-alike.adoc -o /dev/null

update-bootstrap: lib/lp-bootstrap.rb

clean:
	rm -rf README.html lib/litprog.rb lib/lp-test.rb css

.PHONY: self-check test update-bootstrap clean
