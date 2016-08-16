IMAGE=ruby-compiler-buildenv
DR=docker run -t -i -v ${PWD}:/app ${IMAGE}
all: compiler

clean:
	@rm -f *~ *.o *.s
	@rm -rf doc/

compiler.s: *.rb
	ruby compiler.rb compiler.rb >compiler.s

compiler: compiler.s runtime.o
	gcc -gstabs -o compiler compiler.s

push:
	git push origin master

.PHONY: selftest

selftest:
	${DR} ./compile test/selftest.rb -I . -g
	${DR} ./selftest

buildc:
	docker build -t ${IMAGE} .

cli:
	${DR} /bin/bash -l
