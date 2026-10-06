# GNU awk 3.0.4, built by our make with seed-cc from the pristine tarball.
# Run in the unpacked source tree with plumbing/gawk-3.0.4/config.h copied
# in.  The object lists are Makefile.in's ALLOBJS and LIBOBJS, with
# ALLOCA = alloca.o.  awktab.c is the parser shipped in the tarball.

CC = ../../../seed-cc/seed-cc
CFLAGS = -Werror=implicit-function-declaration -DHAVE_CONFIG_H -I.

ALLOBJS = array.o builtin.o eval.o field.o gawkmisc.o io.o main.o missing.o msg.o node.o re.o version.o awktab.o
LIBOBJS = getopt.o getopt1.o regex.o dfa.o random.o alloca.o

.SUFFIXES:

all: gawk

$(ALLOBJS) $(LIBOBJS): config.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

gawk: $(ALLOBJS) $(LIBOBJS)
	$(CC) -static -o $@ $(ALLOBJS) $(LIBOBJS) -lm
