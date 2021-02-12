bootstrap: README.adoc lp-bootstrap.rb
	asciidoctor --trace -I. -rlp-bootstrap.rb README.adoc -o README.html

test: bootstrap
	mv literate-programming.rb lp-test.rb && \
	asciidoctor --trace -I. -rlp-test.rb README.adoc -o README.html && \
	diff lp-test.rb literate-programming.rb


README.html: bootstrap

clean:
	rm -f README.html literate-programming.rb lp-test.rb
