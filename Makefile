IMAGE=ruby-compiler-buildenv
DR=docker run -t -i -v ${PWD}:/app ${IMAGE}
all: compiler

clean:
	@rm -f *~ *.o *.s *\#
	@rm -rf doc/

compiler: *.rb
	./compile compiler.rb -I . -g

push:
	git push origin master

.PHONY: selftest

selftest: buildc
	./compile test/selftest.rb -I . -g
	${DR} ./out/selftest

buildc:
	docker build -t ${IMAGE} .

cli: buildc
	${DR} /bin/bash -l
