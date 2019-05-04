IMAGE=ruby-compiler-buildenv
DR=docker run --rm -ti --privileged -v ${PWD}:/app ${IMAGE}
all: compiler

clean:
	@rm -f *~ *.o *.s *\#
	@rm -rf doc/

compiler: *.rb
	./compile driver.rb -I . -g

push:
	git push origin master

.PHONY: selftest

selftest:
	./compile test/selftest.rb -I . -g
	${DR} ./out/selftest

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
	${DR} bundle exec rspec --format=doc ./spec/*.rb

.PHONY: features
features:
	${DR} /bin/bash -l -c 'cd features; bundle exec cucumber -r. -e inputs -e outputs *.feature'

tests: rspec features selftest
