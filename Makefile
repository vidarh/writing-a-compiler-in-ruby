

all: compiler

clean:
	@rm -f *~ *.o *.s
	@rm -rf doc/

compiler.s: *.rb
	ruby compiler.rb compiler.rb >compiler.s

compiler: compiler.s runtime.o
	gcc -gstabs -o compiler compiler.s runtime.o

