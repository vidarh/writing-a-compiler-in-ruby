

all: parser

parser: parser.o runtime.o

parser.o: parser.s

parser.s: parser.l
	ruby compiler.rb <parser.l >parser.s

clean:
	@rm -f *~ *.o *.s parser testarray testargs

testarray.s: testarray.l
	ruby compiler.rb <testarray.l >testarray.s

testarray.o: testarray.s 

testarray: testarray.o runtime.o
	gcc -o testarray testarray.o runtime.o

testargs.s: testargs.l
	ruby compiler.rb <testargs.l >testargs.s

testargs.o: testargs.s

testargs: testargs.o runtime.o
