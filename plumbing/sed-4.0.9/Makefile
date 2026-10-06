# GNU sed 4.0.9, built by our make with seed-cc from the pristine tarball.
# Run in the unpacked source tree (build-out/plumbing/src/sed-4.0.9) with
# plumbing/sed-4.0.9/config.h copied in.  Every recipe line is a plain
# command (no shell metacharacters), so make runs it without a shell.
# The file list follows live-bootstrap's sed-4.0.9 main.mk; the runtime
# supplies getline and mkstemp, so lib/ adds only what the runtime lacks:
# regex, obstack, strverscmp, getopt_long and the C alloca.

CC = ../../../seed-cc/seed-cc
AR = ../../../seed-cc/seed-ar
CP = ../../bin/cp
CFLAGS = -Werror=implicit-function-declaration -DHAVE_CONFIG_H -I. -Ilib

LIB_OBJ = lib/alloca.o lib/getopt.o lib/getopt1.o lib/utils.o lib/regex.o lib/obstack.o lib/strverscmp.o
SED_OBJ = sed/compile.o sed/execute.o sed/regexp.o sed/fmt.o sed/sed.o

.SUFFIXES:

all: sed/sed

lib/regex.h: lib/regex_.h
	$(CP) lib/regex_.h lib/regex.h

$(LIB_OBJ) $(SED_OBJ): config.h lib/regex.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

lib/libsed.a: $(LIB_OBJ)
	$(AR) cr $@ $(LIB_OBJ)

sed/sed: $(SED_OBJ) lib/libsed.a
	$(CC) -static -o $@ $(SED_OBJ) lib/libsed.a
