

all: compiler testargs testarray

clean:
	@rm -f *~ *.o *.s testarray testargs
	@rm -rf doc/

doc:
	rdoc --all *.rb

compiler.s: *.rb
	ruby compiler.rb <compiler.rb >compiler.s

compiler: compiler.s runtime.o
	gcc -o compiler compiler.s runtime.o

testarray.s: testarray.l
	ruby compiler.rb <testarray.l >testarray.s

testarray.o: testarray.s 

testarray: testarray.o runtime.o
	gcc -o testarray testarray.o runtime.o

testargs.s: testargs.rb
	ruby compiler.rb <testargs.rb >testargs.s

testargs.o: testargs.s

testargs: testargs.o runtime.o
