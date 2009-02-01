

all: step8

step8: step8.o runtime.o

step8.o: step8.s

step8.s: compiler.rb
	ruby compiler.rb >step8.s

clean:
	rm -f *~ *.o *.s step8

