# GNU coreutils 5.0, built by our make with seed-cc from the pristine
# tarball.  Run in the unpacked source tree with
# plumbing/coreutils-5.0/config.h copied in.
#
# lib/libfetish.a is lib/Makefile.am's libfetish_a_SOURCES plus the
# LIBOBJS configure picks for this runtime: the C alloca and the GNU
# functions the runtime does not have.  The headers configure would copy
# for those replacements (fnmatch.h, ftw.h, search.h) are copied here.
#
# Programs are src/Makefile.am's bin_PROGRAMS, plus chroot, nice, stty and
# uname from EXTRA_PROGRAMS.  Left out: df and stat (need statfs and a
# mount list), hostid (gethostid), pinky, users, who and uptime (utmp),
# su (crypt), and the scripts groups and nohup.

CC = ../../../seed-cc/seed-cc
AR = ../../../seed-cc/seed-ar
CP = ../../bin/cp
CFLAGS = -Werror=implicit-function-declaration -DHAVE_CONFIG_H -I. -Ilib -Isrc

LIB_FIXED = acl getdate posixtm posixver strftime getopt getopt1 hash hash-pjw addext argmatch backupfile basename canon-host closeout cycle-check diacrit dirname dup-safer exclude exitfail filemode file-type fopen-safer full-read full-write getstr gettime getugroups hard-locale human idcache isdir imaxtostr linebuffer localcharset long-options makepath mbswidth md5 memcasecmp memcoll modechange offtostr path-concat physmem quote quotearg readtokens safe-read safe-write same save-cwd savedir settime sha stripslash umaxtostr unicodeio userspec version-etc xgetcwd xgethostname xmalloc xmemcoll xnanosleep xreadlink xstrdup xstrtod xstrtol xstrtoul xstrtoimax xstrtoumax yesno
LIB_REPLACE = alloca canonicalize error euidaccess fnmatch __fpending ftw group-member memrchr obstack regex rpmatch sig2str strverscmp tsearch
LIB_OBJ = $(patsubst %,lib/%.o,$(LIB_FIXED) $(LIB_REPLACE))
LIB = lib/libfetish.a

# Programs made from one source file of the same name.
SINGLE = chmod dd dircolors du link ln mkdir mkfifo mknod readlink rmdir shred sync touch unlink cat cksum comm csplit cut expand fmt fold head join nl od paste pr ptx sort split sum tac tail tr tsort unexpand uniq wc basename date dirname echo env expr factor false hostname id kill logname pathchk printenv printf pwd seq sleep tee test true tty whoami yes chroot nice stty uname
MULTI = cp ginstall mv rm ls dir vdir chown chgrp md5sum sha1sum
PROGRAMS = $(addprefix src/,$(SINGLE) $(MULTI))

.SUFFIXES:

all: $(PROGRAMS)

lib/fnmatch.h: lib/fnmatch_.h
	$(CP) lib/fnmatch_.h lib/fnmatch.h

lib/ftw.h: lib/ftw_.h
	$(CP) lib/ftw_.h lib/ftw.h

lib/search.h: lib/search_.h
	$(CP) lib/search_.h lib/search.h

GENERATED_H = lib/fnmatch.h lib/ftw.h lib/search.h

$(LIB_OBJ) $(patsubst %,src/%.o,$(SINGLE)): config.h $(GENERATED_H)
src/cp.o src/copy.o src/cp-hash.o src/install.o src/mv.o src/remove.o src/rm.o src/ls.o src/ls-ls.o src/ls-dir.o src/ls-vdir.o src/chown.o src/chgrp.o src/chown-core.o src/md5sum.o src/md5.o src/sha1sum.o: config.h $(GENERATED_H)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(LIB): $(LIB_OBJ)
	$(AR) cr $@ $(LIB_OBJ)

$(addprefix src/,$(SINGLE)): src/%: src/%.o $(LIB)
	$(CC) -static -o $@ $< $(LIB) -lm

src/cp: src/cp.o src/copy.o src/cp-hash.o $(LIB)
	$(CC) -static -o $@ src/cp.o src/copy.o src/cp-hash.o $(LIB) -lm

src/ginstall: src/install.o src/copy.o src/cp-hash.o $(LIB)
	$(CC) -static -o $@ src/install.o src/copy.o src/cp-hash.o $(LIB) -lm

src/mv: src/mv.o src/copy.o src/cp-hash.o src/remove.o $(LIB)
	$(CC) -static -o $@ src/mv.o src/copy.o src/cp-hash.o src/remove.o $(LIB) -lm

src/rm: src/rm.o src/remove.o $(LIB)
	$(CC) -static -o $@ src/rm.o src/remove.o $(LIB) -lm

src/ls: src/ls.o src/ls-ls.o $(LIB)
	$(CC) -static -o $@ src/ls.o src/ls-ls.o $(LIB) -lm

src/dir: src/ls.o src/ls-dir.o $(LIB)
	$(CC) -static -o $@ src/ls.o src/ls-dir.o $(LIB) -lm

src/vdir: src/ls.o src/ls-vdir.o $(LIB)
	$(CC) -static -o $@ src/ls.o src/ls-vdir.o $(LIB) -lm

src/chown: src/chown.o src/chown-core.o $(LIB)
	$(CC) -static -o $@ src/chown.o src/chown-core.o $(LIB) -lm

src/chgrp: src/chgrp.o src/chown-core.o $(LIB)
	$(CC) -static -o $@ src/chgrp.o src/chown-core.o $(LIB) -lm

src/md5sum: src/md5sum.o src/md5.o $(LIB)
	$(CC) -static -o $@ src/md5sum.o src/md5.o $(LIB) -lm

src/sha1sum: src/md5sum.o src/sha1sum.o $(LIB)
	$(CC) -static -o $@ src/md5sum.o src/sha1sum.o $(LIB) -lm
