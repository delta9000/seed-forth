# gzip 1.2.4, built by our make with seed-cc from the pristine tarball.
# gzip has no config.h: its configure passes plain -D options, and these
# need no quoting, so they are given here (the answers configure gives for
# runtime/gcc-seed: ANSI headers, unistd.h, dirent.h, void signal handlers).
# The C longest_match is used (match.S is i386 assembly).

CC = ../../../seed-cc/seed-cc
CFLAGS = -Werror=implicit-function-declaration -DSTDC_HEADERS -DHAVE_UNISTD_H -DDIRENT -DRETSIGTYPE=void -I.

OBJ = gzip.o zip.o deflate.o trees.o bits.o unzip.o inflate.o util.o crypt.o lzw.o unlzw.o unpack.o unlzh.o getopt.o

.SUFFIXES:

all: gzip

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

gzip: $(OBJ)
	$(CC) -static -o $@ $(OBJ)
