README.html: README.adoc lib/lp-bootstrap.rb
	asciidoctor --trace -Ilib -rlp-bootstrap.rb README.adoc -o README.html

lib/literate-programming.rb: README.html

update-bootstrap: lib/literate-programming.rb
	grep -v '^#line' $< > lib/lp-bootstrap.rb

self-check: lib/literate-programming.rb
	mv lib/literate-programming.rb lib/lp-test.rb && \
	asciidoctor --trace -Ilib -rlp-test.rb README.adoc -o README.html && \
	diff lib/lp-test.rb lib/literate-programming.rb && \
	rm lib/lp-test.rb

test: self-check
	asciidoctor --trace -Ilib -rliterate-programming.rb test/noweb-alike.adoc -o /dev/null

update-bootstrap: lib/lp-bootstrap.rb

clean:
	rm -f README.html literate-programming.rb lp-test.rb

.PHONY: self-check test update-bootstrap clean
