SHELL = /bin/sh
CC = cc
LD = cc

INSTALL_DIR = /usr/local/bin

#CFLAGS = -c -O2 -mips4 -xansi -woff all -DDEBUG
CFLAGS = -c -O2 -mips4 -xansi -woff all

.c.o: corr.h matrix.h
	$(CC) $(CFLAGS) $<

all : autocorrelate install clean

autocorrelate: corr.o list.o corr.h matrix.h matrix.o
	$(CC) corr.o list.o matrix.o -o $@ -lm
	@strip $@

install:
	cp autocorrelate /usr/local/bin
	chmod a+x /usr/local/bin/autocorrelate

# clean up all rubbish
clean:
	-rm -f *.o core a.out

