IMAGE=ruby-compiler-buildenv
DR=docker run --rm -i --privileged -v ${PWD}:/app ${IMAGE}
CFLAGS=-g
all: compiler

clean:
	@rm -f *~ *.o *.s *\#
	@rm -rf doc/

out/driver: *.rb lib/core/*.rb *.c
	./compile driver.rb -I . -g

out/driver2: *.rb lib/core/*.rb *.c out/driver
	./compile2 driver.rb -I . -g

compiler: out/driver


compiler-nodebug: *.rb lib/core/*.rb *.c
	./compile driver.rb -I .

out/driver.l: *.rb
	ruby -I. driver.rb -I. --parsetree driver.rb >out/driver.l

hello: compiler
	./out/driver examples/hello.rb >out/hello5.s
	${DR} gcc -m32 -o out/hello5 out/hello5.s out/tgc.o

push:
	git push origin master

.PHONY: selftest

# To validate that the test completes under MRI.
# failures under MRI implies the code does something wrong,
selftest-mri:
	@echo "== Selftest with MRI:"
	ruby -I. test/selftest.rb

selftest:
	./compile test/selftest.rb -I. -g
	@echo "== Compiled:"
	out/selftest

out/selftest.l: test/selftest.rb *.rb lib/*.rb
	ruby -I. ./driver.rb -I. -g --parsetree test/selftest.rb >out/selftest.l

out/selftest2.l: out/driver test/selftest.rb lib/*.rb
	out/driver -I. -g --parsetree test/selftest.rb >out/selftest2.l

selftest-c: compiler
	./compile2 test/selftest.rb -I. -g
#	./out/driver -I. test/selftest.rb >out/selftest2.s
#	gcc -m32 -o out/selftest2 out/selftest2.s out/tgc.o
	out/selftest2
#	ruby -I. driver.rb --parsetree -I. test/selftest.rb >out/selftest.l
#	./out/driver --parsetree -I. test/selftest.rb >out/selftest2.l
#	diff -u out/selftest.l out/selftest2.l | less

selftest-c2: out/driver2
	./out/driver2 -I. test/selftest.rb >out/selftest3.s
	${DR} gcc -m32 -o out/selftest3 out/selftest3.s out/tgc.o
	out/selftest3

valgrind: selftest
	${DR} valgrind --track-origins=yes ./out/selftest 2>&1

buildc: Dockerfile
	docker build -t ${IMAGE} .

buildc-nocache: Dockerfile
	docker build --no-cache -t ${IMAGE} .

cli:
	${DR} /bin/bash -l

bundle:
	${DR} bundle install

rspec:
	bundle exec rspec --format=doc ./spec/*.rb

.PHONY: features
features:
	${DR} /bin/bash -l -c 'cd features; bundle exec cucumber -r. -e inputs -e outputs *.feature'

tests: rspec features selftest
