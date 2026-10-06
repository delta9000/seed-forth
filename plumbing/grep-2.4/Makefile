# GNU grep 2.4 (grep, egrep, fgrep), built by our make with seed-cc from the
# pristine tarball.  Run in the unpacked source tree with
# plumbing/grep-2.4/config.h copied in.  The object lists are
# src/Makefile.in's, with ALLOCA = alloca.o and no LIBOBJS for this runtime.

CC = ../../../seed-cc/seed-cc
CFLAGS = -Werror=implicit-function-declaration -DHAVE_CONFIG_H -I. -Isrc

BASE_OBJ = src/grep.o src/dfa.o src/kwset.o src/obstack.o src/regex.o src/savedir.o src/getopt.o src/getopt1.o src/search.o src/alloca.o

.SUFFIXES:

all: src/grep src/egrep src/fgrep

$(BASE_OBJ) src/grepmat.o src/egrepmat.o src/fgrepmat.o: config.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

src/grep: $(BASE_OBJ) src/grepmat.o
	$(CC) -static -o $@ $(BASE_OBJ) src/grepmat.o

src/egrep: $(BASE_OBJ) src/egrepmat.o
	$(CC) -static -o $@ $(BASE_OBJ) src/egrepmat.o

src/fgrep: $(BASE_OBJ) src/fgrepmat.o
	$(CC) -static -o $@ $(BASE_OBJ) src/fgrepmat.o
