# GNU diffutils 2.7 (cmp, diff, diff3, sdiff), built by our make with seed-cc
# from the pristine tarball.  Run in the unpacked source tree with
# plumbing/diffutils-2.7/config.h copied in.  The object lists are
# Makefile.in's, with ALLOCA = alloca.o and no LIBOBJS for this runtime.

CC = ../../../seed-cc/seed-cc
CFLAGS = -Werror=implicit-function-declaration -DHAVE_CONFIG_H -I.

DIFF_OBJ = diff.o analyze.o cmpbuf.o dir.o io.o util.o context.o ed.o ifdef.o normal.o side.o fnmatch.o getopt.o getopt1.o regex.o version.o alloca.o
DIFF3_OBJ = diff3.o getopt.o getopt1.o version.o
SDIFF_OBJ = sdiff.o getopt.o getopt1.o version.o
CMP_OBJ = cmp.o cmpbuf.o error.o getopt.o getopt1.o xmalloc.o version.o

.SUFFIXES:

all: cmp diff diff3 sdiff

$(DIFF_OBJ) $(DIFF3_OBJ) $(SDIFF_OBJ) $(CMP_OBJ): config.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

diff: $(DIFF_OBJ)
	$(CC) -static -o $@ $(DIFF_OBJ)

diff3: $(DIFF3_OBJ)
	$(CC) -static -o $@ $(DIFF3_OBJ)

sdiff: $(SDIFF_OBJ)
	$(CC) -static -o $@ $(SDIFF_OBJ)

cmp: $(CMP_OBJ)
	$(CC) -static -o $@ $(CMP_OBJ)
