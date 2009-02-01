

all: step9

step9: step9.o runtime.o

step9.o: step9.s

step9.s: compiler.rb
	ruby compiler.rb >step9.s

clean:
	rm -f *~ *.o *.s step9

