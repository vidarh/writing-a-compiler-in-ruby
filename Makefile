

all: parser

parser: parser.o runtime.o

parser.o: parser.s

parser.s: parser.rb
	ruby parser.rb >parser.s


parser2: parser2.o runtime.o

parser2.o: parser2.s

parser2.s: parser2.rb parser
	ruby parser2.rb >parser2.s

parser2.rb: parser.l parser
	@./parser <parser.l >parser2.rb

clean:
	@rm -f *~ *.o *.s parser parser2

testarray.s: testarray.rb
	ruby testarray.rb >testarray.s

testarray.o: testarray.s 

testarray: testarray.o runtime.o
	gcc -o testarray testarray.o runtime.o

