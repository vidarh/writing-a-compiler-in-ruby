

all:  testargs testarray

clean:
	@rm -f *~ *.o *.s testarray testargs

doc:
	rdoc --all *.rb

testarray.s: testarray.l
	ruby compiler.rb <testarray.l >testarray.s

testarray.o: testarray.s 

testarray: testarray.o runtime.o
	gcc -o testarray testarray.o runtime.o

testargs.s: testargs.rb
	ruby compiler.rb <testargs.rb >testargs.s

testargs.o: testargs.s

testargs: testargs.o runtime.o
