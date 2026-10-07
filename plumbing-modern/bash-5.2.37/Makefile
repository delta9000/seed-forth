# Fixed native GCC 4.0.4 / musl 1.1.24 build. No configure or source patches.
# Invoke from the pristine unpacked package tree; see ../README.md.
# Configured headers are copied automatically from this recipe directory.

CC = /home/ben/code/sf-qsort/build-out/stage-c-qsort/gcc/install/bin/gcc
AR = /home/ben/code/sf-qsort/build-out/stage-c-qsort/toolchain/ar
RANLIB = /home/ben/code/sf-qsort/build-out/stage-c-qsort/toolchain/ranlib
RECIPE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CFLAGS = -O2 -std=gnu89 -Werror-implicit-function-declaration -DHAVE_CONFIG_H -DSHELL -I. -Iinclude -Ilib -Ilib/glob -Ibuiltins
.SUFFIXES:

all: bash

config.h: $(RECIPE_DIR)/config.h
	cp $< $@

pathnames.h: $(RECIPE_DIR)/pathnames.h
	cp $< $@

version.h: $(RECIPE_DIR)/version.h
	cp $< $@

builtins/pipesize.h: $(RECIPE_DIR)/pipesize.h
	cp $< $@

mkbuiltins: builtins/mkbuiltins.c config.h
	$(CC) $(CFLAGS) -static builtins/mkbuiltins.c -o $@

builtins/builtext.h: mkbuiltins builtins/alias.def builtins/bind.def builtins/break.def builtins/builtin.def builtins/caller.def builtins/cd.def builtins/colon.def builtins/command.def builtins/complete.def builtins/declare.def builtins/echo.def builtins/enable.def builtins/eval.def builtins/exec.def builtins/exit.def builtins/fc.def builtins/fg_bg.def builtins/getopts.def builtins/hash.def builtins/help.def builtins/history.def builtins/jobs.def builtins/kill.def builtins/let.def builtins/mapfile.def builtins/printf.def builtins/pushd.def builtins/read.def builtins/reserved.def builtins/return.def builtins/set.def builtins/setattr.def builtins/shift.def builtins/shopt.def builtins/source.def builtins/suspend.def builtins/test.def builtins/times.def builtins/trap.def builtins/type.def builtins/ulimit.def builtins/umask.def builtins/wait.def
	./mkbuiltins -externfile builtins/builtext.h -structfile builtins/builtins.c -noproduction builtins/alias.def builtins/bind.def builtins/break.def builtins/builtin.def builtins/caller.def builtins/cd.def builtins/colon.def builtins/command.def builtins/complete.def builtins/declare.def builtins/echo.def builtins/enable.def builtins/eval.def builtins/exec.def builtins/exit.def builtins/fc.def builtins/fg_bg.def builtins/getopts.def builtins/hash.def builtins/help.def builtins/history.def builtins/jobs.def builtins/kill.def builtins/let.def builtins/mapfile.def builtins/printf.def builtins/pushd.def builtins/read.def builtins/reserved.def builtins/return.def builtins/set.def builtins/setattr.def builtins/shift.def builtins/shopt.def builtins/source.def builtins/suspend.def builtins/test.def builtins/times.def builtins/trap.def builtins/type.def builtins/ulimit.def builtins/umask.def builtins/wait.def

builtins/builtins.c: builtins/builtext.h

mksyntax: mksyntax.c config.h
	$(CC) $(CFLAGS) -static mksyntax.c -o $@

syntax.c: mksyntax
	./mksyntax -o $@

mksignames: support/mksignames.c support/signames.c config.h
	$(CC) $(CFLAGS) -static support/mksignames.c support/signames.c -o $@

signames.h: mksignames
	./mksignames $@

shell.o: shell.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c shell.c -o shell.o

eval.o: eval.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c eval.c -o eval.o

y.tab.o: y.tab.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c y.tab.c -o y.tab.o

general.o: general.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c general.c -o general.o

make_cmd.o: make_cmd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c make_cmd.c -o make_cmd.o

print_cmd.o: print_cmd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c print_cmd.c -o print_cmd.o

dispose_cmd.o: dispose_cmd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c dispose_cmd.c -o dispose_cmd.o

execute_cmd.o: execute_cmd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c execute_cmd.c -o execute_cmd.o

variables.o: variables.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c variables.c -o variables.o

copy_cmd.o: copy_cmd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c copy_cmd.c -o copy_cmd.o

error.o: error.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c error.c -o error.o

expr.o: expr.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c expr.c -o expr.o

flags.o: flags.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c flags.c -o flags.o

jobs.o: jobs.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c jobs.c -o jobs.o

subst.o: subst.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c subst.c -o subst.o

hashcmd.o: hashcmd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c hashcmd.c -o hashcmd.o

hashlib.o: hashlib.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c hashlib.c -o hashlib.o

mailcheck.o: mailcheck.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c mailcheck.c -o mailcheck.o

trap.o: trap.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c trap.c -o trap.o

input.o: input.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c input.c -o input.o

unwind_prot.o: unwind_prot.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c unwind_prot.c -o unwind_prot.o

pathexp.o: pathexp.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c pathexp.c -o pathexp.o

sig.o: sig.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c sig.c -o sig.o

test.o: test.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c test.c -o test.o

version.o: version.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c version.c -o version.o

alias.o: alias.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c alias.c -o alias.o

array.o: array.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c array.c -o array.o

arrayfunc.o: arrayfunc.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c arrayfunc.c -o arrayfunc.o

assoc.o: assoc.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c assoc.c -o assoc.o

braces.o: braces.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c braces.c -o braces.o

bracecomp.o: bracecomp.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c bracecomp.c -o bracecomp.o

bashhist.o: bashhist.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c bashhist.c -o bashhist.o

bashline.o: bashline.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c bashline.c -o bashline.o

siglist.o: siglist.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c siglist.c -o siglist.o

list.o: list.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c list.c -o list.o

stringlib.o: stringlib.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c stringlib.c -o stringlib.o

locale.o: locale.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c locale.c -o locale.o

findcmd.o: findcmd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c findcmd.c -o findcmd.o

redir.o: redir.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c redir.c -o redir.o

pcomplete.o: pcomplete.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c pcomplete.c -o pcomplete.o

pcomplib.o: pcomplib.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c pcomplib.c -o pcomplib.o

syntax.o: syntax.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c syntax.c -o syntax.o

xmalloc.o: xmalloc.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c xmalloc.c -o xmalloc.o

lib/sh/clktck.o: lib/sh/clktck.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/clktck.c -o lib/sh/clktck.o

lib/sh/clock.o: lib/sh/clock.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/clock.c -o lib/sh/clock.o

lib/sh/getenv.o: lib/sh/getenv.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/getenv.c -o lib/sh/getenv.o

lib/sh/oslib.o: lib/sh/oslib.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/oslib.c -o lib/sh/oslib.o

lib/sh/setlinebuf.o: lib/sh/setlinebuf.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/setlinebuf.c -o lib/sh/setlinebuf.o

lib/sh/strnlen.o: lib/sh/strnlen.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/strnlen.c -o lib/sh/strnlen.o

lib/sh/itos.o: lib/sh/itos.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/itos.c -o lib/sh/itos.o

lib/sh/zread.o: lib/sh/zread.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/zread.c -o lib/sh/zread.o

lib/sh/zwrite.o: lib/sh/zwrite.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/zwrite.c -o lib/sh/zwrite.o

lib/sh/shtty.o: lib/sh/shtty.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/shtty.c -o lib/sh/shtty.o

lib/sh/shmatch.o: lib/sh/shmatch.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/shmatch.c -o lib/sh/shmatch.o

lib/sh/eaccess.o: lib/sh/eaccess.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/eaccess.c -o lib/sh/eaccess.o

lib/sh/netconn.o: lib/sh/netconn.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/netconn.c -o lib/sh/netconn.o

lib/sh/netopen.o: lib/sh/netopen.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/netopen.c -o lib/sh/netopen.o

lib/sh/timeval.o: lib/sh/timeval.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/timeval.c -o lib/sh/timeval.o

lib/sh/makepath.o: lib/sh/makepath.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/makepath.c -o lib/sh/makepath.o

lib/sh/pathcanon.o: lib/sh/pathcanon.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/pathcanon.c -o lib/sh/pathcanon.o

lib/sh/pathphys.o: lib/sh/pathphys.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/pathphys.c -o lib/sh/pathphys.o

lib/sh/tmpfile.o: lib/sh/tmpfile.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/tmpfile.c -o lib/sh/tmpfile.o

lib/sh/stringlist.o: lib/sh/stringlist.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/stringlist.c -o lib/sh/stringlist.o

lib/sh/stringvec.o: lib/sh/stringvec.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/stringvec.c -o lib/sh/stringvec.o

lib/sh/spell.o: lib/sh/spell.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/spell.c -o lib/sh/spell.o

lib/sh/shquote.o: lib/sh/shquote.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/shquote.c -o lib/sh/shquote.o

lib/sh/strtrans.o: lib/sh/strtrans.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/strtrans.c -o lib/sh/strtrans.o

lib/sh/snprintf.o: lib/sh/snprintf.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/snprintf.c -o lib/sh/snprintf.o

lib/sh/mailstat.o: lib/sh/mailstat.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/mailstat.c -o lib/sh/mailstat.o

lib/sh/fmtulong.o: lib/sh/fmtulong.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/fmtulong.c -o lib/sh/fmtulong.o

lib/sh/fmtullong.o: lib/sh/fmtullong.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/fmtullong.c -o lib/sh/fmtullong.o

lib/sh/fmtumax.o: lib/sh/fmtumax.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/fmtumax.c -o lib/sh/fmtumax.o

lib/sh/zcatfd.o: lib/sh/zcatfd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/zcatfd.c -o lib/sh/zcatfd.o

lib/sh/zmapfd.o: lib/sh/zmapfd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/zmapfd.c -o lib/sh/zmapfd.o

lib/sh/winsize.o: lib/sh/winsize.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/winsize.c -o lib/sh/winsize.o

lib/sh/wcsdup.o: lib/sh/wcsdup.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/wcsdup.c -o lib/sh/wcsdup.o

lib/sh/fpurge.o: lib/sh/fpurge.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/fpurge.c -o lib/sh/fpurge.o

lib/sh/zgetline.o: lib/sh/zgetline.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/zgetline.c -o lib/sh/zgetline.o

lib/sh/mbscmp.o: lib/sh/mbscmp.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/mbscmp.c -o lib/sh/mbscmp.o

lib/sh/uconvert.o: lib/sh/uconvert.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/uconvert.c -o lib/sh/uconvert.o

lib/sh/ufuncs.o: lib/sh/ufuncs.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/ufuncs.c -o lib/sh/ufuncs.o

lib/sh/casemod.o: lib/sh/casemod.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/casemod.c -o lib/sh/casemod.o

lib/sh/input_avail.o: lib/sh/input_avail.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/input_avail.c -o lib/sh/input_avail.o

lib/sh/mbscasecmp.o: lib/sh/mbscasecmp.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/mbscasecmp.c -o lib/sh/mbscasecmp.o

lib/sh/fnxform.o: lib/sh/fnxform.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/fnxform.c -o lib/sh/fnxform.o

lib/sh/unicode.o: lib/sh/unicode.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/unicode.c -o lib/sh/unicode.o

lib/sh/shmbchar.o: lib/sh/shmbchar.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/shmbchar.c -o lib/sh/shmbchar.o

lib/sh/strvis.o: lib/sh/strvis.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/strvis.c -o lib/sh/strvis.o

lib/sh/utf8.o: lib/sh/utf8.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/utf8.c -o lib/sh/utf8.o

lib/sh/random.o: lib/sh/random.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/random.c -o lib/sh/random.o

lib/sh/gettimeofday.o: lib/sh/gettimeofday.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/gettimeofday.c -o lib/sh/gettimeofday.o

lib/sh/timers.o: lib/sh/timers.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/timers.c -o lib/sh/timers.o

lib/sh/wcsnwidth.o: lib/sh/wcsnwidth.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/wcsnwidth.c -o lib/sh/wcsnwidth.o

lib/sh/mbschr.o: lib/sh/mbschr.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/sh/mbschr.c -o lib/sh/mbschr.o

lib/glob/glob.o: lib/glob/glob.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/glob/glob.c -o lib/glob/glob.o

lib/glob/strmatch.o: lib/glob/strmatch.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/glob/strmatch.c -o lib/glob/strmatch.o

lib/glob/smatch.o: lib/glob/smatch.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/glob/smatch.c -o lib/glob/smatch.o

lib/glob/xmbsrtowcs.o: lib/glob/xmbsrtowcs.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/glob/xmbsrtowcs.c -o lib/glob/xmbsrtowcs.o

lib/glob/gmisc.o: lib/glob/gmisc.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/glob/gmisc.c -o lib/glob/gmisc.o

lib/tilde/tilde.o: lib/tilde/tilde.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c lib/tilde/tilde.c -o lib/tilde/tilde.o

builtins/builtins.o: builtins/builtins.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/builtins.c -o builtins/builtins.o

builtins/alias.c: builtins/alias.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk alias.c

builtins/alias.o: builtins/alias.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/alias.c -o builtins/alias.o

builtins/bind.c: builtins/bind.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk bind.c

builtins/bind.o: builtins/bind.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/bind.c -o builtins/bind.o

builtins/break.c: builtins/break.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk break.c

builtins/break.o: builtins/break.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/break.c -o builtins/break.o

builtins/builtin.c: builtins/builtin.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk builtin.c

builtins/builtin.o: builtins/builtin.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/builtin.c -o builtins/builtin.o

builtins/caller.c: builtins/caller.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk caller.c

builtins/caller.o: builtins/caller.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/caller.c -o builtins/caller.o

builtins/cd.c: builtins/cd.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk cd.c

builtins/cd.o: builtins/cd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/cd.c -o builtins/cd.o

builtins/colon.c: builtins/colon.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk colon.c

builtins/colon.o: builtins/colon.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/colon.c -o builtins/colon.o

builtins/command.c: builtins/command.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk command.c

builtins/command.o: builtins/command.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/command.c -o builtins/command.o

builtins/common.o: builtins/common.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/common.c -o builtins/common.o

builtins/declare.c: builtins/declare.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk declare.c

builtins/declare.o: builtins/declare.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/declare.c -o builtins/declare.o

builtins/echo.c: builtins/echo.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk echo.c

builtins/echo.o: builtins/echo.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/echo.c -o builtins/echo.o

builtins/enable.c: builtins/enable.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk enable.c

builtins/enable.o: builtins/enable.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/enable.c -o builtins/enable.o

builtins/eval.c: builtins/eval.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk eval.c

builtins/eval.o: builtins/eval.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/eval.c -o builtins/eval.o

builtins/evalfile.o: builtins/evalfile.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/evalfile.c -o builtins/evalfile.o

builtins/evalstring.o: builtins/evalstring.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/evalstring.c -o builtins/evalstring.o

builtins/exec.c: builtins/exec.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk exec.c

builtins/exec.o: builtins/exec.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/exec.c -o builtins/exec.o

builtins/exit.c: builtins/exit.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk exit.c

builtins/exit.o: builtins/exit.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/exit.c -o builtins/exit.o

builtins/fc.c: builtins/fc.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk fc.c

builtins/fc.o: builtins/fc.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/fc.c -o builtins/fc.o

builtins/fg_bg.c: builtins/fg_bg.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk fg_bg.c

builtins/fg_bg.o: builtins/fg_bg.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/fg_bg.c -o builtins/fg_bg.o

builtins/hash.c: builtins/hash.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk hash.c

builtins/hash.o: builtins/hash.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/hash.c -o builtins/hash.o

builtins/help.c: builtins/help.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk help.c

builtins/help.o: builtins/help.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/help.c -o builtins/help.o

builtins/history.c: builtins/history.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk history.c

builtins/history.o: builtins/history.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/history.c -o builtins/history.o

builtins/jobs.c: builtins/jobs.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk jobs.c

builtins/jobs.o: builtins/jobs.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/jobs.c -o builtins/jobs.o

builtins/kill.c: builtins/kill.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk kill.c

builtins/kill.o: builtins/kill.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/kill.c -o builtins/kill.o

builtins/let.c: builtins/let.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk let.c

builtins/let.o: builtins/let.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/let.c -o builtins/let.o

builtins/mapfile.c: builtins/mapfile.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk mapfile.c

builtins/mapfile.o: builtins/mapfile.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/mapfile.c -o builtins/mapfile.o

builtins/pushd.c: builtins/pushd.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk pushd.c

builtins/pushd.o: builtins/pushd.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/pushd.c -o builtins/pushd.o

builtins/read.c: builtins/read.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk read.c

builtins/read.o: builtins/read.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/read.c -o builtins/read.o

builtins/return.c: builtins/return.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk return.c

builtins/return.o: builtins/return.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/return.c -o builtins/return.o

builtins/set.c: builtins/set.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk set.c

builtins/set.o: builtins/set.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/set.c -o builtins/set.o

builtins/setattr.c: builtins/setattr.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk setattr.c

builtins/setattr.o: builtins/setattr.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/setattr.c -o builtins/setattr.o

builtins/shift.c: builtins/shift.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk shift.c

builtins/shift.o: builtins/shift.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/shift.c -o builtins/shift.o

builtins/source.c: builtins/source.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk source.c

builtins/source.o: builtins/source.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/source.c -o builtins/source.o

builtins/suspend.c: builtins/suspend.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk suspend.c

builtins/suspend.o: builtins/suspend.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/suspend.c -o builtins/suspend.o

builtins/test.c: builtins/test.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk test.c

builtins/test.o: builtins/test.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/test.c -o builtins/test.o

builtins/times.c: builtins/times.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk times.c

builtins/times.o: builtins/times.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/times.c -o builtins/times.o

builtins/trap.c: builtins/trap.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk trap.c

builtins/trap.o: builtins/trap.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/trap.c -o builtins/trap.o

builtins/type.c: builtins/type.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk type.c

builtins/type.o: builtins/type.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/type.c -o builtins/type.o

builtins/ulimit.c: builtins/ulimit.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk ulimit.c

builtins/ulimit.o: builtins/ulimit.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/ulimit.c -o builtins/ulimit.o

builtins/umask.c: builtins/umask.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk umask.c

builtins/umask.o: builtins/umask.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/umask.c -o builtins/umask.o

builtins/wait.c: builtins/wait.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk wait.c

builtins/wait.o: builtins/wait.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/wait.c -o builtins/wait.o

builtins/getopts.c: builtins/getopts.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk getopts.c

builtins/getopts.o: builtins/getopts.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/getopts.c -o builtins/getopts.o

builtins/shopt.c: builtins/shopt.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk shopt.c

builtins/shopt.o: builtins/shopt.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/shopt.c -o builtins/shopt.o

builtins/printf.c: builtins/printf.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk printf.c

builtins/printf.o: builtins/printf.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/printf.c -o builtins/printf.o

builtins/getopt.o: builtins/getopt.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/getopt.c -o builtins/getopt.o

builtins/bashgetopt.o: builtins/bashgetopt.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/bashgetopt.c -o builtins/bashgetopt.o

builtins/complete.c: builtins/complete.def mkbuiltins config.h
	$(MAKE) -C builtins -f $(RECIPE_DIR)/builtins.mk complete.c

builtins/complete.o: builtins/complete.c config.h pathnames.h version.h signames.h builtins/builtext.h builtins/pipesize.h
	$(CC) $(CFLAGS) -c builtins/complete.c -o builtins/complete.o

libsh.a: lib/sh/clktck.o lib/sh/clock.o lib/sh/getenv.o lib/sh/oslib.o lib/sh/setlinebuf.o lib/sh/strnlen.o lib/sh/itos.o lib/sh/zread.o lib/sh/zwrite.o lib/sh/shtty.o lib/sh/shmatch.o lib/sh/eaccess.o lib/sh/netconn.o lib/sh/netopen.o lib/sh/timeval.o lib/sh/makepath.o lib/sh/pathcanon.o lib/sh/pathphys.o lib/sh/tmpfile.o lib/sh/stringlist.o lib/sh/stringvec.o lib/sh/spell.o lib/sh/shquote.o lib/sh/strtrans.o lib/sh/snprintf.o lib/sh/mailstat.o lib/sh/fmtulong.o lib/sh/fmtullong.o lib/sh/fmtumax.o lib/sh/zcatfd.o lib/sh/zmapfd.o lib/sh/winsize.o lib/sh/wcsdup.o lib/sh/fpurge.o lib/sh/zgetline.o lib/sh/mbscmp.o lib/sh/uconvert.o lib/sh/ufuncs.o lib/sh/casemod.o lib/sh/input_avail.o lib/sh/mbscasecmp.o lib/sh/fnxform.o lib/sh/unicode.o lib/sh/shmbchar.o lib/sh/strvis.o lib/sh/utf8.o lib/sh/random.o lib/sh/gettimeofday.o lib/sh/timers.o lib/sh/wcsnwidth.o lib/sh/mbschr.o
	$(AR) cr libsh.a lib/sh/clktck.o lib/sh/clock.o lib/sh/getenv.o lib/sh/oslib.o lib/sh/setlinebuf.o lib/sh/strnlen.o lib/sh/itos.o lib/sh/zread.o lib/sh/zwrite.o lib/sh/shtty.o lib/sh/shmatch.o lib/sh/eaccess.o lib/sh/netconn.o lib/sh/netopen.o lib/sh/timeval.o lib/sh/makepath.o lib/sh/pathcanon.o lib/sh/pathphys.o lib/sh/tmpfile.o lib/sh/stringlist.o lib/sh/stringvec.o lib/sh/spell.o lib/sh/shquote.o lib/sh/strtrans.o lib/sh/snprintf.o lib/sh/mailstat.o lib/sh/fmtulong.o lib/sh/fmtullong.o lib/sh/fmtumax.o lib/sh/zcatfd.o lib/sh/zmapfd.o lib/sh/winsize.o lib/sh/wcsdup.o lib/sh/fpurge.o lib/sh/zgetline.o lib/sh/mbscmp.o lib/sh/uconvert.o lib/sh/ufuncs.o lib/sh/casemod.o lib/sh/input_avail.o lib/sh/mbscasecmp.o lib/sh/fnxform.o lib/sh/unicode.o lib/sh/shmbchar.o lib/sh/strvis.o lib/sh/utf8.o lib/sh/random.o lib/sh/gettimeofday.o lib/sh/timers.o lib/sh/wcsnwidth.o lib/sh/mbschr.o
	$(RANLIB) libsh.a

libglob.a: lib/glob/glob.o lib/glob/strmatch.o lib/glob/smatch.o lib/glob/xmbsrtowcs.o lib/glob/gmisc.o
	$(AR) cr libglob.a lib/glob/glob.o lib/glob/strmatch.o lib/glob/smatch.o lib/glob/xmbsrtowcs.o lib/glob/gmisc.o
	$(RANLIB) libglob.a

libtilde.a: lib/tilde/tilde.o
	$(AR) cr libtilde.a lib/tilde/tilde.o
	$(RANLIB) libtilde.a

builtins/libbuiltins.a: builtins/builtins.o builtins/alias.o builtins/bind.o builtins/break.o builtins/builtin.o builtins/caller.o builtins/cd.o builtins/colon.o builtins/command.o builtins/common.o builtins/declare.o builtins/echo.o builtins/enable.o builtins/eval.o builtins/evalfile.o builtins/evalstring.o builtins/exec.o builtins/exit.o builtins/fc.o builtins/fg_bg.o builtins/hash.o builtins/help.o builtins/history.o builtins/jobs.o builtins/kill.o builtins/let.o builtins/mapfile.o builtins/pushd.o builtins/read.o builtins/return.o builtins/set.o builtins/setattr.o builtins/shift.o builtins/source.o builtins/suspend.o builtins/test.o builtins/times.o builtins/trap.o builtins/type.o builtins/ulimit.o builtins/umask.o builtins/wait.o builtins/getopts.o builtins/shopt.o builtins/printf.o builtins/getopt.o builtins/bashgetopt.o builtins/complete.o
	$(AR) cr builtins/libbuiltins.a builtins/builtins.o builtins/alias.o builtins/bind.o builtins/break.o builtins/builtin.o builtins/caller.o builtins/cd.o builtins/colon.o builtins/command.o builtins/common.o builtins/declare.o builtins/echo.o builtins/enable.o builtins/eval.o builtins/evalfile.o builtins/evalstring.o builtins/exec.o builtins/exit.o builtins/fc.o builtins/fg_bg.o builtins/hash.o builtins/help.o builtins/history.o builtins/jobs.o builtins/kill.o builtins/let.o builtins/mapfile.o builtins/pushd.o builtins/read.o builtins/return.o builtins/set.o builtins/setattr.o builtins/shift.o builtins/source.o builtins/suspend.o builtins/test.o builtins/times.o builtins/trap.o builtins/type.o builtins/ulimit.o builtins/umask.o builtins/wait.o builtins/getopts.o builtins/shopt.o builtins/printf.o builtins/getopt.o builtins/bashgetopt.o builtins/complete.o
	$(RANLIB) builtins/libbuiltins.a

bash: shell.o eval.o y.tab.o general.o make_cmd.o print_cmd.o dispose_cmd.o execute_cmd.o variables.o copy_cmd.o error.o expr.o flags.o jobs.o subst.o hashcmd.o hashlib.o mailcheck.o trap.o input.o unwind_prot.o pathexp.o sig.o test.o version.o alias.o array.o arrayfunc.o assoc.o braces.o bracecomp.o bashhist.o bashline.o siglist.o list.o stringlib.o locale.o findcmd.o redir.o pcomplete.o pcomplib.o syntax.o xmalloc.o libsh.a libglob.a libtilde.a builtins/libbuiltins.a
	$(CC) -static -o bash shell.o eval.o y.tab.o general.o make_cmd.o print_cmd.o dispose_cmd.o execute_cmd.o variables.o copy_cmd.o error.o expr.o flags.o jobs.o subst.o hashcmd.o hashlib.o mailcheck.o trap.o input.o unwind_prot.o pathexp.o sig.o test.o version.o alias.o array.o arrayfunc.o assoc.o braces.o bracecomp.o bashhist.o bashline.o siglist.o list.o stringlib.o locale.o findcmd.o redir.o pcomplete.o pcomplib.o syntax.o xmalloc.o builtins/libbuiltins.a libsh.a libglob.a libtilde.a builtins/libbuiltins.a libsh.a libglob.a -lm
