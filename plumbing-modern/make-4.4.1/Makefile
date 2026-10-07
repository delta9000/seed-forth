# Fixed native GCC 4.0.4 / musl 1.1.24 build. No configure or source patches.
# Invoke from the pristine unpacked package tree; see ../README.md.
# Configured headers are copied automatically from this recipe directory.

CC = /home/ben/code/sf-qsort/build-out/stage-c-qsort/gcc/install/bin/gcc
AR = /home/ben/code/sf-qsort/build-out/stage-c-qsort/toolchain/ar
RANLIB = /home/ben/code/sf-qsort/build-out/stage-c-qsort/toolchain/ranlib
RECIPE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CFLAGS = -O2 -std=gnu89 -Werror-implicit-function-declaration -DHAVE_CONFIG_H -I. -Isrc -Ilib
.SUFFIXES:

all: make

config.h: $(RECIPE_DIR)/config.h
	cp $< $@

src/config.h: config.h
	cp $< $@

lib/fnmatch.h: $(RECIPE_DIR)/lib/fnmatch.h
	cp $< $@

lib/glob.h: $(RECIPE_DIR)/lib/glob.h
	cp $< $@

src/ar.o: src/ar.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/ar.c -o src/ar.o

src/arscan.o: src/arscan.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/arscan.c -o src/arscan.o

src/commands.o: src/commands.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/commands.c -o src/commands.o

src/default.o: src/default.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/default.c -o src/default.o

src/dir.o: src/dir.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/dir.c -o src/dir.o

src/expand.o: src/expand.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/expand.c -o src/expand.o

src/file.o: src/file.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/file.c -o src/file.o

src/function.o: src/function.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/function.c -o src/function.o

src/getopt.o: src/getopt.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/getopt.c -o src/getopt.o

src/getopt1.o: src/getopt1.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/getopt1.c -o src/getopt1.o

src/guile.o: src/guile.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/guile.c -o src/guile.o

src/hash.o: src/hash.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/hash.c -o src/hash.o

src/implicit.o: src/implicit.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/implicit.c -o src/implicit.o

src/job.o: src/job.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/job.c -o src/job.o

src/load.o: src/load.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/load.c -o src/load.o

src/loadapi.o: src/loadapi.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/loadapi.c -o src/loadapi.o

src/main.o: src/main.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/main.c -o src/main.o

src/misc.o: src/misc.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/misc.c -o src/misc.o

src/output.o: src/output.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/output.c -o src/output.o

src/read.o: src/read.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/read.c -o src/read.o

src/remake.o: src/remake.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/remake.c -o src/remake.o

src/rule.o: src/rule.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/rule.c -o src/rule.o

src/shuffle.o: src/shuffle.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/shuffle.c -o src/shuffle.o

src/signame.o: src/signame.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/signame.c -o src/signame.o

src/strcache.o: src/strcache.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/strcache.c -o src/strcache.o

src/variable.o: src/variable.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/variable.c -o src/variable.o

src/version.o: src/version.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/version.c -o src/version.o

src/vpath.o: src/vpath.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/vpath.c -o src/vpath.o

src/posixos.o: src/posixos.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/posixos.c -o src/posixos.o

src/remote-stub.o: src/remote-stub.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c src/remote-stub.c -o src/remote-stub.o

lib/concat-filename.o: lib/concat-filename.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c lib/concat-filename.c -o lib/concat-filename.o

lib/findprog-in.o: lib/findprog-in.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c lib/findprog-in.c -o lib/findprog-in.o

lib/fnmatch.o: lib/fnmatch.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c lib/fnmatch.c -o lib/fnmatch.o

lib/glob.o: lib/glob.c src/config.h lib/fnmatch.h lib/glob.h
	$(CC) $(CFLAGS) -c lib/glob.c -o lib/glob.o

make: src/ar.o src/arscan.o src/commands.o src/default.o src/dir.o src/expand.o src/file.o src/function.o src/getopt.o src/getopt1.o src/guile.o src/hash.o src/implicit.o src/job.o src/load.o src/loadapi.o src/main.o src/misc.o src/output.o src/read.o src/remake.o src/rule.o src/shuffle.o src/signame.o src/strcache.o src/variable.o src/version.o src/vpath.o src/posixos.o src/remote-stub.o lib/concat-filename.o lib/findprog-in.o lib/fnmatch.o lib/glob.o
	$(CC) -static -o $@ src/ar.o src/arscan.o src/commands.o src/default.o src/dir.o src/expand.o src/file.o src/function.o src/getopt.o src/getopt1.o src/guile.o src/hash.o src/implicit.o src/job.o src/load.o src/loadapi.o src/main.o src/misc.o src/output.o src/read.o src/remake.o src/rule.o src/shuffle.o src/signame.o src/strcache.o src/variable.o src/version.o src/vpath.o src/posixos.o src/remote-stub.o lib/concat-filename.o lib/findprog-in.o lib/fnmatch.o lib/glob.o
