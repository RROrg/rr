
CFLAGS = -Wall -pedantic
LDFLAGS =
LIBS = /lib/x86_64-linux-gnu/libelf.a /lib/x86_64-linux-gnu/libz.a

all: kpatch

kpatch: main.o
	cc $(LDFLAGS) -o $@ $^ $(LIBS)

clean:
	rm -f kpatch *.o
