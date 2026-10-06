# GNU patch 2.5.9, built by our make with seed-cc from the pristine tarball.
# Run in the unpacked source tree with plumbing/patch-2.5.9/config.h copied
# in.  OBJS is Makefile.in's list plus the LIBOBJS configure picks for this
# runtime: error.o (the runtime has no error()); malloc, realloc, memchr,
# mkdir, rmdir and strncasecmp come from the runtime.

CC = ../../../seed-cc/seed-cc
CFLAGS = -Werror=implicit-function-declaration -DHAVE_CONFIG_H -I.

OBJS = error.o addext.o argmatch.o backupfile.o basename.o dirname.o getopt.o getopt1.o inp.o maketime.o partime.o patch.o pch.o quote.o quotearg.o quotesys.o util.o version.o xmalloc.o

.SUFFIXES:

all: patch

$(OBJS): config.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

patch: $(OBJS)
	$(CC) -static -o $@ $(OBJS)
