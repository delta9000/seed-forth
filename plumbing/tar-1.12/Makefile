# GNU tar 1.12, built by our make with seed-cc from the pristine tarball.
# Run in the unpacked source tree with plumbing/tar-1.12/config.h copied in.
# The file lists are lib/Makefile.in's libtar_a_OBJECTS plus the LIBOBJS
# configure picks for this runtime (alloca, fnmatch), and src/Makefile.in's
# tar_OBJECTS.  lib/getdate.c is the parser shipped in the tarball.

CC = ../../../seed-cc/seed-cc
AR = ../../../seed-cc/seed-ar
CFLAGS = -Werror=implicit-function-declaration -DHAVE_CONFIG_H -I. -Ilib

LIB_OBJ = lib/argmatch.o lib/backupfile.o lib/error.o lib/getdate.o lib/getopt.o lib/getopt1.o lib/getversion.o lib/modechange.o lib/msleep.o lib/xgetcwd.o lib/xmalloc.o lib/xstrdup.o lib/alloca.o lib/fnmatch.o
TAR_OBJ = src/arith.o src/buffer.o src/compare.o src/create.o src/delete.o src/extract.o src/incremen.o src/list.o src/mangle.o src/misc.o src/names.o src/open3.o src/rtapelib.o src/tar.o src/update.o

.SUFFIXES:

all: src/tar

$(LIB_OBJ) $(TAR_OBJ): config.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

lib/libtar.a: $(LIB_OBJ)
	$(AR) cr $@ $(LIB_OBJ)

src/tar: $(TAR_OBJ) lib/libtar.a
	$(CC) -static -o $@ $(TAR_OBJ) lib/libtar.a
