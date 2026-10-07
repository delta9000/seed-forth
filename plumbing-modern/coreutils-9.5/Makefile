# Fixed native GCC 4.0.4 / musl 1.1.24 build. No configure or source patches.
# Invoke from the pristine unpacked package tree; see ../README.md.
# Configured headers are copied automatically from this recipe directory.

CC = /home/ben/code/sf-qsort/build-out/stage-c-qsort/gcc/install/bin/gcc
AR = /home/ben/code/sf-qsort/build-out/stage-c-qsort/toolchain/ar
RANLIB = /home/ben/code/sf-qsort/build-out/stage-c-qsort/toolchain/ranlib
RECIPE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CFLAGS = -O2 -std=gnu99 -Werror-implicit-function-declaration -DHAVE_CONFIG_H -I. -Isrc -Ilib
.SUFFIXES:

all: src/ls src/cat src/sort src/cp src/mkdir src/date src/printf src/wc

config.h: $(RECIPE_DIR)/config.h
	cp $< $@

lib/sys lib/arpa lib/netinet lib/selinux:
	mkdir -p $@

lib/alloca.h: $(RECIPE_DIR)/lib/alloca.h
	cp $< $@

lib/arpa/inet.h: $(RECIPE_DIR)/lib/arpa/inet.h | lib/arpa
	cp $< $@

lib/assert.h: $(RECIPE_DIR)/lib/assert.h
	cp $< $@

lib/byteswap.h: $(RECIPE_DIR)/lib/byteswap.h
	cp $< $@

lib/ctype.h: $(RECIPE_DIR)/lib/ctype.h
	cp $< $@

lib/dirent.h: $(RECIPE_DIR)/lib/dirent.h
	cp $< $@

lib/errno.h: $(RECIPE_DIR)/lib/errno.h
	cp $< $@

lib/error.h: $(RECIPE_DIR)/lib/error.h
	cp $< $@

lib/fcntl.h: $(RECIPE_DIR)/lib/fcntl.h
	cp $< $@

lib/float.h: $(RECIPE_DIR)/lib/float.h
	cp $< $@

lib/fnmatch.h: $(RECIPE_DIR)/lib/fnmatch.h
	cp $< $@

lib/getopt-cdefs.h: $(RECIPE_DIR)/lib/getopt-cdefs.h
	cp $< $@

lib/getopt.h: $(RECIPE_DIR)/lib/getopt.h
	cp $< $@

lib/iconv.h: $(RECIPE_DIR)/lib/iconv.h
	cp $< $@

lib/inttypes.h: $(RECIPE_DIR)/lib/inttypes.h
	cp $< $@

lib/langinfo.h: $(RECIPE_DIR)/lib/langinfo.h
	cp $< $@

lib/limits.h: $(RECIPE_DIR)/lib/limits.h
	cp $< $@

lib/locale.h: $(RECIPE_DIR)/lib/locale.h
	cp $< $@

lib/math.h: $(RECIPE_DIR)/lib/math.h
	cp $< $@

lib/netdb.h: $(RECIPE_DIR)/lib/netdb.h
	cp $< $@

lib/netinet/in.h: $(RECIPE_DIR)/lib/netinet/in.h | lib/netinet
	cp $< $@

lib/obstack.h: $(RECIPE_DIR)/lib/obstack.h
	cp $< $@

lib/pthread.h: $(RECIPE_DIR)/lib/pthread.h
	cp $< $@

lib/sched.h: $(RECIPE_DIR)/lib/sched.h
	cp $< $@

lib/selinux/context.h: $(RECIPE_DIR)/lib/selinux/context.h | lib/selinux
	cp $< $@

lib/selinux/label.h: $(RECIPE_DIR)/lib/selinux/label.h | lib/selinux
	cp $< $@

lib/selinux/selinux.h: $(RECIPE_DIR)/lib/selinux/selinux.h | lib/selinux
	cp $< $@

lib/signal.h: $(RECIPE_DIR)/lib/signal.h
	cp $< $@

lib/stdarg.h: $(RECIPE_DIR)/lib/stdarg.h
	cp $< $@

lib/stdckdint.h: $(RECIPE_DIR)/lib/stdckdint.h
	cp $< $@

lib/stddef.h: $(RECIPE_DIR)/lib/stddef.h
	cp $< $@

lib/stdint.h: $(RECIPE_DIR)/lib/stdint.h
	cp $< $@

lib/stdio.h: $(RECIPE_DIR)/lib/stdio.h
	cp $< $@

lib/stdlib.h: $(RECIPE_DIR)/lib/stdlib.h
	cp $< $@

lib/string.h: $(RECIPE_DIR)/lib/string.h
	cp $< $@

lib/sys/ioctl.h: $(RECIPE_DIR)/lib/sys/ioctl.h | lib/sys
	cp $< $@

lib/sys/random.h: $(RECIPE_DIR)/lib/sys/random.h | lib/sys
	cp $< $@

lib/sys/resource.h: $(RECIPE_DIR)/lib/sys/resource.h | lib/sys
	cp $< $@

lib/sys/select.h: $(RECIPE_DIR)/lib/sys/select.h | lib/sys
	cp $< $@

lib/sys/socket.h: $(RECIPE_DIR)/lib/sys/socket.h | lib/sys
	cp $< $@

lib/sys/stat.h: $(RECIPE_DIR)/lib/sys/stat.h | lib/sys
	cp $< $@

lib/sys/time.h: $(RECIPE_DIR)/lib/sys/time.h | lib/sys
	cp $< $@

lib/sys/types.h: $(RECIPE_DIR)/lib/sys/types.h | lib/sys
	cp $< $@

lib/sys/uio.h: $(RECIPE_DIR)/lib/sys/uio.h | lib/sys
	cp $< $@

lib/sys/utsname.h: $(RECIPE_DIR)/lib/sys/utsname.h | lib/sys
	cp $< $@

lib/sys/wait.h: $(RECIPE_DIR)/lib/sys/wait.h | lib/sys
	cp $< $@

lib/termios.h: $(RECIPE_DIR)/lib/termios.h
	cp $< $@

lib/time.h: $(RECIPE_DIR)/lib/time.h
	cp $< $@

lib/uchar.h: $(RECIPE_DIR)/lib/uchar.h
	cp $< $@

lib/unicase.h: $(RECIPE_DIR)/lib/unicase.h
	cp $< $@

lib/unictype.h: $(RECIPE_DIR)/lib/unictype.h
	cp $< $@

lib/uninorm.h: $(RECIPE_DIR)/lib/uninorm.h
	cp $< $@

lib/unistd.h: $(RECIPE_DIR)/lib/unistd.h
	cp $< $@

lib/unistr.h: $(RECIPE_DIR)/lib/unistr.h
	cp $< $@

lib/unitypes.h: $(RECIPE_DIR)/lib/unitypes.h
	cp $< $@

lib/uniwidth.h: $(RECIPE_DIR)/lib/uniwidth.h
	cp $< $@

lib/utime.h: $(RECIPE_DIR)/lib/utime.h
	cp $< $@

lib/wchar.h: $(RECIPE_DIR)/lib/wchar.h
	cp $< $@

lib/wctype.h: $(RECIPE_DIR)/lib/wctype.h
	cp $< $@

HEADERS = lib/malloc/dynarray.gl.h lib/malloc/dynarray-skeleton.gl.h lib/malloc/scratch_buffer.gl.h lib/configmake.h lib/alloca.h lib/arpa/inet.h lib/assert.h lib/byteswap.h lib/ctype.h lib/dirent.h lib/errno.h lib/error.h lib/fcntl.h lib/float.h lib/fnmatch.h lib/getopt-cdefs.h lib/getopt.h lib/iconv.h lib/inttypes.h lib/langinfo.h lib/limits.h lib/locale.h lib/math.h lib/netdb.h lib/netinet/in.h lib/obstack.h lib/pthread.h lib/sched.h lib/selinux/context.h lib/selinux/label.h lib/selinux/selinux.h lib/signal.h lib/stdarg.h lib/stdckdint.h lib/stddef.h lib/stdint.h lib/stdio.h lib/stdlib.h lib/string.h lib/sys/ioctl.h lib/sys/random.h lib/sys/resource.h lib/sys/select.h lib/sys/socket.h lib/sys/stat.h lib/sys/time.h lib/sys/types.h lib/sys/uio.h lib/sys/utsname.h lib/sys/wait.h lib/termios.h lib/time.h lib/uchar.h lib/unicase.h lib/unictype.h lib/uninorm.h lib/unistd.h lib/unistr.h lib/unitypes.h lib/uniwidth.h lib/utime.h lib/wchar.h lib/wctype.h

lib/acl-errno-valid.o: lib/acl-errno-valid.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/acl-errno-valid.c -o lib/acl-errno-valid.o

lib/acl-internal.o: lib/acl-internal.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/acl-internal.c -o lib/acl-internal.o

lib/af_alg.o: lib/af_alg.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/af_alg.c -o lib/af_alg.o

lib/alignalloc.o: lib/alignalloc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/alignalloc.c -o lib/alignalloc.o

lib/allocator.o: lib/allocator.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/allocator.c -o lib/allocator.o

lib/areadlink-with-size.o: lib/areadlink-with-size.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/areadlink-with-size.c -o lib/areadlink-with-size.o

lib/areadlink.o: lib/areadlink.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/areadlink.c -o lib/areadlink.o

lib/areadlinkat-with-size.o: lib/areadlinkat-with-size.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/areadlinkat-with-size.c -o lib/areadlinkat-with-size.o

lib/areadlinkat.o: lib/areadlinkat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/areadlinkat.c -o lib/areadlinkat.o

lib/argmatch.o: lib/argmatch.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/argmatch.c -o lib/argmatch.o

lib/argv-iter.o: lib/argv-iter.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/argv-iter.c -o lib/argv-iter.o

lib/backup-find.o: lib/backup-find.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/backup-find.c -o lib/backup-find.o

lib/backup-rename.o: lib/backup-rename.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/backup-rename.c -o lib/backup-rename.o

lib/backupfile.o: lib/backupfile.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/backupfile.c -o lib/backupfile.o

lib/base32.o: lib/base32.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/base32.c -o lib/base32.o

lib/base64.o: lib/base64.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/base64.c -o lib/base64.o

lib/basename-lgpl.o: lib/basename-lgpl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/basename-lgpl.c -o lib/basename-lgpl.o

lib/basename.o: lib/basename.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/basename.c -o lib/basename.o

lib/binary-io.o: lib/binary-io.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/binary-io.c -o lib/binary-io.o

lib/bitrotate.o: lib/bitrotate.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/bitrotate.c -o lib/bitrotate.o

lib/btoc32.o: lib/btoc32.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/btoc32.c -o lib/btoc32.o

lib/buffer-lcm.o: lib/buffer-lcm.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/buffer-lcm.c -o lib/buffer-lcm.o

lib/c-ctype.o: lib/c-ctype.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c-ctype.c -o lib/c-ctype.o

lib/c-file-type.o: lib/c-file-type.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c-file-type.c -o lib/c-file-type.o

lib/c-strcasecmp.o: lib/c-strcasecmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c-strcasecmp.c -o lib/c-strcasecmp.o

lib/c-strncasecmp.o: lib/c-strncasecmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c-strncasecmp.c -o lib/c-strncasecmp.o

lib/c-strtod.o: lib/c-strtod.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c-strtod.c -o lib/c-strtod.o

lib/c-strtold.o: lib/c-strtold.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c-strtold.c -o lib/c-strtold.o

lib/c32_apply_type_test.o: lib/c32_apply_type_test.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32_apply_type_test.c -o lib/c32_apply_type_test.o

lib/c32_get_type_test.o: lib/c32_get_type_test.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32_get_type_test.c -o lib/c32_get_type_test.o

lib/c32isalnum.o: lib/c32isalnum.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isalnum.c -o lib/c32isalnum.o

lib/c32isalpha.o: lib/c32isalpha.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isalpha.c -o lib/c32isalpha.o

lib/c32isblank.o: lib/c32isblank.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isblank.c -o lib/c32isblank.o

lib/c32iscntrl.o: lib/c32iscntrl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32iscntrl.c -o lib/c32iscntrl.o

lib/c32isdigit.o: lib/c32isdigit.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isdigit.c -o lib/c32isdigit.o

lib/c32isgraph.o: lib/c32isgraph.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isgraph.c -o lib/c32isgraph.o

lib/c32islower.o: lib/c32islower.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32islower.c -o lib/c32islower.o

lib/c32isprint.o: lib/c32isprint.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isprint.c -o lib/c32isprint.o

lib/c32ispunct.o: lib/c32ispunct.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32ispunct.c -o lib/c32ispunct.o

lib/c32isspace.o: lib/c32isspace.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isspace.c -o lib/c32isspace.o

lib/c32isupper.o: lib/c32isupper.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isupper.c -o lib/c32isupper.o

lib/c32isxdigit.o: lib/c32isxdigit.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32isxdigit.c -o lib/c32isxdigit.o

lib/c32tolower.o: lib/c32tolower.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32tolower.c -o lib/c32tolower.o

lib/c32width.o: lib/c32width.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/c32width.c -o lib/c32width.o

lib/canon-host.o: lib/canon-host.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/canon-host.c -o lib/canon-host.o

lib/canonicalize.o: lib/canonicalize.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/canonicalize.c -o lib/canonicalize.o

lib/careadlinkat.o: lib/careadlinkat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/careadlinkat.c -o lib/careadlinkat.o

lib/chmodat.o: lib/chmodat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/chmodat.c -o lib/chmodat.o

lib/chownat.o: lib/chownat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/chownat.c -o lib/chownat.o

lib/cl-strtod.o: lib/cl-strtod.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/cl-strtod.c -o lib/cl-strtod.o

lib/cl-strtold.o: lib/cl-strtold.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/cl-strtold.c -o lib/cl-strtold.o

lib/cloexec.o: lib/cloexec.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/cloexec.c -o lib/cloexec.o

lib/close-stream.o: lib/close-stream.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/close-stream.c -o lib/close-stream.o

lib/closein.o: lib/closein.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/closein.c -o lib/closein.o

lib/closeout.o: lib/closeout.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/closeout.c -o lib/closeout.o

lib/copy-acl.o: lib/copy-acl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/copy-acl.c -o lib/copy-acl.o

lib/count-leading-zeros.o: lib/count-leading-zeros.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/count-leading-zeros.c -o lib/count-leading-zeros.o

lib/creat-safer.o: lib/creat-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/creat-safer.c -o lib/creat-safer.o

lib/cycle-check.o: lib/cycle-check.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/cycle-check.c -o lib/cycle-check.o

lib/di-set.o: lib/di-set.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/di-set.c -o lib/di-set.o

lib/dirchownmod.o: lib/dirchownmod.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/dirchownmod.c -o lib/dirchownmod.o

lib/dirname-lgpl.o: lib/dirname-lgpl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/dirname-lgpl.c -o lib/dirname-lgpl.o

lib/dirname.o: lib/dirname.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/dirname.c -o lib/dirname.o

lib/dtoastr.o: lib/dtoastr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/dtoastr.c -o lib/dtoastr.o

lib/dtotimespec.o: lib/dtotimespec.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/dtotimespec.c -o lib/dtotimespec.o

lib/dup-safer-flag.o: lib/dup-safer-flag.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/dup-safer-flag.c -o lib/dup-safer-flag.o

lib/dup-safer.o: lib/dup-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/dup-safer.c -o lib/dup-safer.o

lib/error.o: lib/error.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/error.c -o lib/error.o

lib/exclude.o: lib/exclude.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/exclude.c -o lib/exclude.o

lib/exitfail.o: lib/exitfail.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/exitfail.c -o lib/exitfail.o

lib/fadvise.o: lib/fadvise.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fadvise.c -o lib/fadvise.o

lib/fd-hook.o: lib/fd-hook.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fd-hook.c -o lib/fd-hook.o

lib/fd-reopen.o: lib/fd-reopen.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fd-reopen.c -o lib/fd-reopen.o

lib/fd-safer-flag.o: lib/fd-safer-flag.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fd-safer-flag.c -o lib/fd-safer-flag.o

lib/fd-safer.o: lib/fd-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fd-safer.c -o lib/fd-safer.o

lib/fdutimensat.o: lib/fdutimensat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fdutimensat.c -o lib/fdutimensat.o

lib/file-has-acl.o: lib/file-has-acl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/file-has-acl.c -o lib/file-has-acl.o

lib/file-set.o: lib/file-set.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/file-set.c -o lib/file-set.o

lib/file-type.o: lib/file-type.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/file-type.c -o lib/file-type.o

lib/filemode.o: lib/filemode.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/filemode.c -o lib/filemode.o

lib/filenamecat-lgpl.o: lib/filenamecat-lgpl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/filenamecat-lgpl.c -o lib/filenamecat-lgpl.o

lib/filenamecat.o: lib/filenamecat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/filenamecat.c -o lib/filenamecat.o

lib/filevercmp.o: lib/filevercmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/filevercmp.c -o lib/filevercmp.o

lib/fopen-safer.o: lib/fopen-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fopen-safer.c -o lib/fopen-safer.o

lib/fprintftime.o: lib/fprintftime.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fprintftime.c -o lib/fprintftime.o

lib/freading.o: lib/freading.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/freading.c -o lib/freading.o

lib/freadseek.o: lib/freadseek.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/freadseek.c -o lib/freadseek.o

lib/freopen-safer.o: lib/freopen-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/freopen-safer.c -o lib/freopen-safer.o

lib/ftoastr.o: lib/ftoastr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/ftoastr.c -o lib/ftoastr.o

lib/fts.o: lib/fts.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/fts.c -o lib/fts.o

lib/full-read.o: lib/full-read.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/full-read.c -o lib/full-read.o

lib/full-write.o: lib/full-write.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/full-write.c -o lib/full-write.o

lib/get-permissions.o: lib/get-permissions.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/get-permissions.c -o lib/get-permissions.o

lib/gethrxtime.o: lib/gethrxtime.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/gethrxtime.c -o lib/gethrxtime.o

lib/getndelim2.o: lib/getndelim2.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/getndelim2.c -o lib/getndelim2.o

lib/getopt.o: lib/getopt.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/getopt.c -o lib/getopt.o

lib/getopt1.o: lib/getopt1.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/getopt1.c -o lib/getopt1.o

lib/gettime-res.o: lib/gettime-res.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/gettime-res.c -o lib/gettime-res.o

lib/gettime.o: lib/gettime.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/gettime.c -o lib/gettime.o

lib/getugroups.o: lib/getugroups.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/getugroups.c -o lib/getugroups.o

lib/glthread/lock.o: lib/glthread/lock.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/glthread/lock.c -o lib/glthread/lock.o

lib/glthread/threadlib.o: lib/glthread/threadlib.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/glthread/threadlib.c -o lib/glthread/threadlib.o

lib/glthread/tls.o: lib/glthread/tls.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/glthread/tls.c -o lib/glthread/tls.o

lib/hard-locale.o: lib/hard-locale.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/hard-locale.c -o lib/hard-locale.o

lib/hash-pjw.o: lib/hash-pjw.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/hash-pjw.c -o lib/hash-pjw.o

lib/hash-triple-simple.o: lib/hash-triple-simple.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/hash-triple-simple.c -o lib/hash-triple-simple.o

lib/hash-triple.o: lib/hash-triple.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/hash-triple.c -o lib/hash-triple.o

lib/hash.o: lib/hash.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/hash.c -o lib/hash.o

lib/heap.o: lib/heap.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/heap.c -o lib/heap.o

lib/human.o: lib/human.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/human.c -o lib/human.o

lib/i-ring.o: lib/i-ring.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/i-ring.c -o lib/i-ring.o

lib/ialloc.o: lib/ialloc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/ialloc.c -o lib/ialloc.o

lib/idcache.o: lib/idcache.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/idcache.c -o lib/idcache.o

lib/imaxtostr.o: lib/imaxtostr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/imaxtostr.c -o lib/imaxtostr.o

lib/ino-map.o: lib/ino-map.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/ino-map.c -o lib/ino-map.o

lib/inttostr.o: lib/inttostr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/inttostr.c -o lib/inttostr.o

lib/ldtoastr.o: lib/ldtoastr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/ldtoastr.c -o lib/ldtoastr.o

lib/linebuffer.o: lib/linebuffer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/linebuffer.c -o lib/linebuffer.o

lib/localcharset.o: lib/localcharset.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/localcharset.c -o lib/localcharset.o

lib/long-options.o: lib/long-options.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/long-options.c -o lib/long-options.o

lib/malloc/dynarray_at_failure.o: lib/malloc/dynarray_at_failure.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/dynarray_at_failure.c -o lib/malloc/dynarray_at_failure.o

lib/malloc/dynarray_emplace_enlarge.o: lib/malloc/dynarray_emplace_enlarge.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/dynarray_emplace_enlarge.c -o lib/malloc/dynarray_emplace_enlarge.o

lib/malloc/dynarray_finalize.o: lib/malloc/dynarray_finalize.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/dynarray_finalize.c -o lib/malloc/dynarray_finalize.o

lib/malloc/dynarray_resize.o: lib/malloc/dynarray_resize.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/dynarray_resize.c -o lib/malloc/dynarray_resize.o

lib/malloc/dynarray_resize_clear.o: lib/malloc/dynarray_resize_clear.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/dynarray_resize_clear.c -o lib/malloc/dynarray_resize_clear.o

lib/malloc/scratch_buffer_grow.o: lib/malloc/scratch_buffer_grow.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/scratch_buffer_grow.c -o lib/malloc/scratch_buffer_grow.o

lib/malloc/scratch_buffer_grow_preserve.o: lib/malloc/scratch_buffer_grow_preserve.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/scratch_buffer_grow_preserve.c -o lib/malloc/scratch_buffer_grow_preserve.o

lib/malloc/scratch_buffer_set_array_size.o: lib/malloc/scratch_buffer_set_array_size.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloc/scratch_buffer_set_array_size.c -o lib/malloc/scratch_buffer_set_array_size.o

lib/malloca.o: lib/malloca.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/malloca.c -o lib/malloca.o

lib/math.o: lib/math.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/math.c -o lib/math.o

lib/mbscasecmp.o: lib/mbscasecmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mbscasecmp.c -o lib/mbscasecmp.o

lib/mbschr.o: lib/mbschr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mbschr.c -o lib/mbschr.o

lib/mbslen.o: lib/mbslen.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mbslen.c -o lib/mbslen.o

lib/mbsrtoc32s.o: lib/mbsrtoc32s.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mbsrtoc32s.c -o lib/mbsrtoc32s.o

lib/mbswidth.o: lib/mbswidth.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mbswidth.c -o lib/mbswidth.o

lib/mbszero.o: lib/mbszero.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mbszero.c -o lib/mbszero.o

lib/mcel.o: lib/mcel.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mcel.c -o lib/mcel.o

lib/md5-stream.o: lib/md5-stream.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/md5-stream.c -o lib/md5-stream.o

lib/md5.o: lib/md5.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/md5.c -o lib/md5.o

lib/memcasecmp.o: lib/memcasecmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/memcasecmp.c -o lib/memcasecmp.o

lib/memchr2.o: lib/memchr2.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/memchr2.c -o lib/memchr2.o

lib/memcmp2.o: lib/memcmp2.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/memcmp2.c -o lib/memcmp2.o

lib/memcoll.o: lib/memcoll.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/memcoll.c -o lib/memcoll.o

lib/mgetgroups.o: lib/mgetgroups.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mgetgroups.c -o lib/mgetgroups.o

lib/mkancesdirs.o: lib/mkancesdirs.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mkancesdirs.c -o lib/mkancesdirs.o

lib/mkdir-p.o: lib/mkdir-p.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mkdir-p.c -o lib/mkdir-p.o

lib/mkstemp-safer.o: lib/mkstemp-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mkstemp-safer.c -o lib/mkstemp-safer.o

lib/modechange.o: lib/modechange.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/modechange.c -o lib/modechange.o

lib/mpsort.o: lib/mpsort.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/mpsort.c -o lib/mpsort.o

lib/nproc.o: lib/nproc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/nproc.c -o lib/nproc.o

lib/nstrftime.o: lib/nstrftime.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/nstrftime.c -o lib/nstrftime.o

lib/obstack.o: lib/obstack.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/obstack.c -o lib/obstack.o

lib/offtostr.o: lib/offtostr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/offtostr.c -o lib/offtostr.o

lib/open-safer.o: lib/open-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/open-safer.c -o lib/open-safer.o

lib/openat-die.o: lib/openat-die.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/openat-die.c -o lib/openat-die.o

lib/openat-proc.o: lib/openat-proc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/openat-proc.c -o lib/openat-proc.o

lib/openat-safer.o: lib/openat-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/openat-safer.c -o lib/openat-safer.o

lib/opendir-safer.o: lib/opendir-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/opendir-safer.c -o lib/opendir-safer.o

lib/opendirat.o: lib/opendirat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/opendirat.c -o lib/opendirat.o

lib/physmem.o: lib/physmem.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/physmem.c -o lib/physmem.o

lib/pipe-safer.o: lib/pipe-safer.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/pipe-safer.c -o lib/pipe-safer.o

lib/pipe2.o: lib/pipe2.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/pipe2.c -o lib/pipe2.o

lib/posixtm.o: lib/posixtm.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/posixtm.c -o lib/posixtm.o

lib/posixver.o: lib/posixver.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/posixver.c -o lib/posixver.o

lib/printf-frexp.o: lib/printf-frexp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/printf-frexp.c -o lib/printf-frexp.o

lib/printf-frexpl.o: lib/printf-frexpl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/printf-frexpl.c -o lib/printf-frexpl.o

lib/priv-set.o: lib/priv-set.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/priv-set.c -o lib/priv-set.o

lib/progname.o: lib/progname.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/progname.c -o lib/progname.o

lib/propername-lite.o: lib/propername-lite.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/propername-lite.c -o lib/propername-lite.o

lib/qcopy-acl.o: lib/qcopy-acl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/qcopy-acl.c -o lib/qcopy-acl.o

lib/qset-acl.o: lib/qset-acl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/qset-acl.c -o lib/qset-acl.o

lib/quotearg.o: lib/quotearg.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/quotearg.c -o lib/quotearg.o

lib/rand-isaac.o: lib/rand-isaac.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/rand-isaac.c -o lib/rand-isaac.o

lib/randint.o: lib/randint.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/randint.c -o lib/randint.o

lib/randperm.o: lib/randperm.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/randperm.c -o lib/randperm.o

lib/randread.o: lib/randread.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/randread.c -o lib/randread.o

lib/read-file.o: lib/read-file.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/read-file.c -o lib/read-file.o

lib/readtokens.o: lib/readtokens.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/readtokens.c -o lib/readtokens.o

lib/readtokens0.o: lib/readtokens0.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/readtokens0.c -o lib/readtokens0.o

lib/readutmp.o: lib/readutmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/readutmp.c -o lib/readutmp.o

lib/renameatu.o: lib/renameatu.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/renameatu.c -o lib/renameatu.o

lib/root-dev-ino.o: lib/root-dev-ino.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/root-dev-ino.c -o lib/root-dev-ino.o

lib/safe-read.o: lib/safe-read.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/safe-read.c -o lib/safe-read.o

lib/safe-write.o: lib/safe-write.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/safe-write.c -o lib/safe-write.o

lib/same-inode.o: lib/same-inode.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/same-inode.c -o lib/same-inode.o

lib/same.o: lib/same.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/same.c -o lib/same.o

lib/save-cwd.o: lib/save-cwd.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/save-cwd.c -o lib/save-cwd.o

lib/savedir.o: lib/savedir.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/savedir.c -o lib/savedir.o

lib/savewd.o: lib/savewd.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/savewd.c -o lib/savewd.o

lib/se-context.o: lib/se-context.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/se-context.c -o lib/se-context.o

lib/se-label.o: lib/se-label.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/se-label.c -o lib/se-label.o

lib/se-selinux.o: lib/se-selinux.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/se-selinux.c -o lib/se-selinux.o

lib/selinux-at.o: lib/selinux-at.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/selinux-at.c -o lib/selinux-at.o

lib/set-acl.o: lib/set-acl.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/set-acl.c -o lib/set-acl.o

lib/set-permissions.o: lib/set-permissions.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/set-permissions.c -o lib/set-permissions.o

lib/setlocale_null-unlocked.o: lib/setlocale_null-unlocked.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/setlocale_null-unlocked.c -o lib/setlocale_null-unlocked.o

lib/setlocale_null.o: lib/setlocale_null.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/setlocale_null.c -o lib/setlocale_null.o

lib/settime.o: lib/settime.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/settime.c -o lib/settime.o

lib/sha1-stream.o: lib/sha1-stream.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sha1-stream.c -o lib/sha1-stream.o

lib/sha1.o: lib/sha1.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sha1.c -o lib/sha1.o

lib/sha256-stream.o: lib/sha256-stream.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sha256-stream.c -o lib/sha256-stream.o

lib/sha256.o: lib/sha256.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sha256.c -o lib/sha256.o

lib/sha512-stream.o: lib/sha512-stream.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sha512-stream.c -o lib/sha512-stream.o

lib/sha512.o: lib/sha512.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sha512.c -o lib/sha512.o

lib/sig-handler.o: lib/sig-handler.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sig-handler.c -o lib/sig-handler.o

lib/skipchars.o: lib/skipchars.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/skipchars.c -o lib/skipchars.o

lib/sm3-stream.o: lib/sm3-stream.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sm3-stream.c -o lib/sm3-stream.o

lib/sm3.o: lib/sm3.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sm3.c -o lib/sm3.o

lib/sockets.o: lib/sockets.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sockets.c -o lib/sockets.o

lib/stat-time.o: lib/stat-time.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/stat-time.c -o lib/stat-time.o

lib/strintcmp.o: lib/strintcmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/strintcmp.c -o lib/strintcmp.o

lib/stripslash.o: lib/stripslash.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/stripslash.c -o lib/stripslash.o

lib/strnlen1.o: lib/strnlen1.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/strnlen1.c -o lib/strnlen1.o

lib/strnumcmp.o: lib/strnumcmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/strnumcmp.c -o lib/strnumcmp.o

lib/sys_socket.o: lib/sys_socket.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/sys_socket.c -o lib/sys_socket.o

lib/targetdir.o: lib/targetdir.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/targetdir.c -o lib/targetdir.o

lib/tempname.o: lib/tempname.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/tempname.c -o lib/tempname.o

lib/timespec.o: lib/timespec.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/timespec.c -o lib/timespec.o

lib/tmpdir.o: lib/tmpdir.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/tmpdir.c -o lib/tmpdir.o

lib/u64.o: lib/u64.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/u64.c -o lib/u64.o

lib/uinttostr.o: lib/uinttostr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/uinttostr.c -o lib/uinttostr.o

lib/umaxtostr.o: lib/umaxtostr.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/umaxtostr.c -o lib/umaxtostr.o

lib/unicodeio.o: lib/unicodeio.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/unicodeio.c -o lib/unicodeio.o

lib/unistd.o: lib/unistd.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/unistd.c -o lib/unistd.o

lib/unlinkdir.o: lib/unlinkdir.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/unlinkdir.c -o lib/unlinkdir.o

lib/userspec.o: lib/userspec.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/userspec.c -o lib/userspec.o

lib/utimecmp.o: lib/utimecmp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/utimecmp.c -o lib/utimecmp.o

lib/utimens.o: lib/utimens.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/utimens.c -o lib/utimens.o

lib/verror.o: lib/verror.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/verror.c -o lib/verror.o

lib/version-etc-fsf.o: lib/version-etc-fsf.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/version-etc-fsf.c -o lib/version-etc-fsf.o

lib/version-etc.o: lib/version-etc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/version-etc.c -o lib/version-etc.o

lib/wctype-h.o: lib/wctype-h.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/wctype-h.c -o lib/wctype-h.o

lib/write-any-file.o: lib/write-any-file.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/write-any-file.c -o lib/write-any-file.o

lib/xalignalloc.o: lib/xalignalloc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xalignalloc.c -o lib/xalignalloc.o

lib/xalloc-die.o: lib/xalloc-die.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xalloc-die.c -o lib/xalloc-die.o

lib/xasprintf.o: lib/xasprintf.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xasprintf.c -o lib/xasprintf.o

lib/xbinary-io.o: lib/xbinary-io.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xbinary-io.c -o lib/xbinary-io.o

lib/xdectoimax.o: lib/xdectoimax.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xdectoimax.c -o lib/xdectoimax.o

lib/xdectoumax.o: lib/xdectoumax.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xdectoumax.c -o lib/xdectoumax.o

lib/xfts.o: lib/xfts.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xfts.c -o lib/xfts.o

lib/xgetcwd.o: lib/xgetcwd.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xgetcwd.c -o lib/xgetcwd.o

lib/xgetgroups.o: lib/xgetgroups.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xgetgroups.c -o lib/xgetgroups.o

lib/xgethostname.o: lib/xgethostname.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xgethostname.c -o lib/xgethostname.o

lib/xmalloc.o: lib/xmalloc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xmalloc.c -o lib/xmalloc.o

lib/xmemcoll.o: lib/xmemcoll.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xmemcoll.c -o lib/xmemcoll.o

lib/xnanosleep.o: lib/xnanosleep.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xnanosleep.c -o lib/xnanosleep.o

lib/xprintf.o: lib/xprintf.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xprintf.c -o lib/xprintf.o

lib/xreadlink.o: lib/xreadlink.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xreadlink.c -o lib/xreadlink.o

lib/xsize.o: lib/xsize.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xsize.c -o lib/xsize.o

lib/xstrtod.o: lib/xstrtod.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xstrtod.c -o lib/xstrtod.o

lib/xstrtoimax.o: lib/xstrtoimax.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xstrtoimax.c -o lib/xstrtoimax.o

lib/xstrtol-error.o: lib/xstrtol-error.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xstrtol-error.c -o lib/xstrtol-error.o

lib/xstrtol.o: lib/xstrtol.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xstrtol.c -o lib/xstrtol.o

lib/xstrtold.o: lib/xstrtold.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xstrtold.c -o lib/xstrtold.o

lib/xstrtoul.o: lib/xstrtoul.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xstrtoul.c -o lib/xstrtoul.o

lib/xstrtoumax.o: lib/xstrtoumax.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xstrtoumax.c -o lib/xstrtoumax.o

lib/xtime.o: lib/xtime.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xtime.c -o lib/xtime.o

lib/xvasprintf.o: lib/xvasprintf.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/xvasprintf.c -o lib/xvasprintf.o

lib/yesno.o: lib/yesno.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c lib/yesno.c -o lib/yesno.o

src/cat.o: src/cat.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/cat.c -o src/cat.o

src/copy.o: src/copy.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/copy.c -o src/copy.o

src/cp-hash.o: src/cp-hash.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/cp-hash.c -o src/cp-hash.o

src/cp.o: src/cp.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/cp.c -o src/cp.o

src/date.o: src/date.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/date.c -o src/date.o

src/force-link.o: src/force-link.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/force-link.c -o src/force-link.o

src/ls-ls.o: src/ls-ls.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/ls-ls.c -o src/ls-ls.o

src/ls.o: src/ls.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/ls.c -o src/ls.o

src/mkdir.o: src/mkdir.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/mkdir.c -o src/mkdir.o

src/printf.o: src/printf.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/printf.c -o src/printf.o

src/prog-fprintf.o: src/prog-fprintf.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/prog-fprintf.c -o src/prog-fprintf.o

src/selinux.o: src/selinux.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/selinux.c -o src/selinux.o

src/sort.o: src/sort.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/sort.c -o src/sort.o

src/wc.o: src/wc.c config.h $(HEADERS) src/version.h
	$(CC) $(CFLAGS) -c src/wc.c -o src/wc.o

lib/libcoreutils.a: lib/qsort.o lib/time_rz.o lib/getprogname.o lib/reallocarray.o lib/rawmemchr.o lib/setlocale-lock.o lib/unistr/u8-uctomb.o lib/parse-datetime.o src/version.o lib/acl-errno-valid.o lib/acl-internal.o lib/af_alg.o lib/alignalloc.o lib/allocator.o lib/areadlink-with-size.o lib/areadlink.o lib/areadlinkat-with-size.o lib/areadlinkat.o lib/argmatch.o lib/argv-iter.o lib/backup-find.o lib/backup-rename.o lib/backupfile.o lib/base32.o lib/base64.o lib/basename-lgpl.o lib/basename.o lib/binary-io.o lib/bitrotate.o lib/btoc32.o lib/buffer-lcm.o lib/c-ctype.o lib/c-file-type.o lib/c-strcasecmp.o lib/c-strncasecmp.o lib/c-strtod.o lib/c-strtold.o lib/c32_apply_type_test.o lib/c32_get_type_test.o lib/c32isalnum.o lib/c32isalpha.o lib/c32isblank.o lib/c32iscntrl.o lib/c32isdigit.o lib/c32isgraph.o lib/c32islower.o lib/c32isprint.o lib/c32ispunct.o lib/c32isspace.o lib/c32isupper.o lib/c32isxdigit.o lib/c32tolower.o lib/c32width.o lib/canon-host.o lib/canonicalize.o lib/careadlinkat.o lib/chmodat.o lib/chownat.o lib/cl-strtod.o lib/cl-strtold.o lib/cloexec.o lib/close-stream.o lib/closein.o lib/closeout.o lib/copy-acl.o lib/count-leading-zeros.o lib/creat-safer.o lib/cycle-check.o lib/di-set.o lib/dirchownmod.o lib/dirname-lgpl.o lib/dirname.o lib/dtoastr.o lib/dtotimespec.o lib/dup-safer-flag.o lib/dup-safer.o lib/error.o lib/exclude.o lib/exitfail.o lib/fadvise.o lib/fd-hook.o lib/fd-reopen.o lib/fd-safer-flag.o lib/fd-safer.o lib/fdutimensat.o lib/file-has-acl.o lib/file-set.o lib/file-type.o lib/filemode.o lib/filenamecat-lgpl.o lib/filenamecat.o lib/filevercmp.o lib/fopen-safer.o lib/fprintftime.o lib/freading.o lib/freadseek.o lib/freopen-safer.o lib/ftoastr.o lib/fts.o lib/full-read.o lib/full-write.o lib/get-permissions.o lib/gethrxtime.o lib/getndelim2.o lib/getopt.o lib/getopt1.o lib/gettime-res.o lib/gettime.o lib/getugroups.o lib/glthread/lock.o lib/glthread/threadlib.o lib/glthread/tls.o lib/hard-locale.o lib/hash-pjw.o lib/hash-triple-simple.o lib/hash-triple.o lib/hash.o lib/heap.o lib/human.o lib/i-ring.o lib/ialloc.o lib/idcache.o lib/imaxtostr.o lib/ino-map.o lib/inttostr.o lib/ldtoastr.o lib/linebuffer.o lib/localcharset.o lib/long-options.o lib/malloc/dynarray_at_failure.o lib/malloc/dynarray_emplace_enlarge.o lib/malloc/dynarray_finalize.o lib/malloc/dynarray_resize.o lib/malloc/dynarray_resize_clear.o lib/malloc/scratch_buffer_grow.o lib/malloc/scratch_buffer_grow_preserve.o lib/malloc/scratch_buffer_set_array_size.o lib/malloca.o lib/math.o lib/mbscasecmp.o lib/mbschr.o lib/mbslen.o lib/mbsrtoc32s.o lib/mbswidth.o lib/mbszero.o lib/mcel.o lib/md5-stream.o lib/md5.o lib/memcasecmp.o lib/memchr2.o lib/memcmp2.o lib/memcoll.o lib/mgetgroups.o lib/mkancesdirs.o lib/mkdir-p.o lib/mkstemp-safer.o lib/modechange.o lib/mpsort.o lib/nproc.o lib/nstrftime.o lib/obstack.o lib/offtostr.o lib/open-safer.o lib/openat-die.o lib/openat-proc.o lib/openat-safer.o lib/opendir-safer.o lib/opendirat.o lib/physmem.o lib/pipe-safer.o lib/pipe2.o lib/posixtm.o lib/posixver.o lib/printf-frexp.o lib/printf-frexpl.o lib/priv-set.o lib/progname.o lib/propername-lite.o lib/qcopy-acl.o lib/qset-acl.o lib/quotearg.o lib/rand-isaac.o lib/randint.o lib/randperm.o lib/randread.o lib/read-file.o lib/readtokens.o lib/readtokens0.o lib/readutmp.o lib/renameatu.o lib/root-dev-ino.o lib/safe-read.o lib/safe-write.o lib/same-inode.o lib/same.o lib/save-cwd.o lib/savedir.o lib/savewd.o lib/se-context.o lib/se-label.o lib/se-selinux.o lib/selinux-at.o lib/set-acl.o lib/set-permissions.o lib/setlocale_null-unlocked.o lib/setlocale_null.o lib/settime.o lib/sha1-stream.o lib/sha1.o lib/sha256-stream.o lib/sha256.o lib/sha512-stream.o lib/sha512.o lib/sig-handler.o lib/skipchars.o lib/sm3-stream.o lib/sm3.o lib/sockets.o lib/stat-time.o lib/strintcmp.o lib/stripslash.o lib/strnlen1.o lib/strnumcmp.o lib/sys_socket.o lib/targetdir.o lib/tempname.o lib/timespec.o lib/tmpdir.o lib/u64.o lib/uinttostr.o lib/umaxtostr.o lib/unicodeio.o lib/unistd.o lib/unlinkdir.o lib/userspec.o lib/utimecmp.o lib/utimens.o lib/verror.o lib/version-etc-fsf.o lib/version-etc.o lib/wctype-h.o lib/write-any-file.o lib/xalignalloc.o lib/xalloc-die.o lib/xasprintf.o lib/xbinary-io.o lib/xdectoimax.o lib/xdectoumax.o lib/xfts.o lib/xgetcwd.o lib/xgetgroups.o lib/xgethostname.o lib/xmalloc.o lib/xmemcoll.o lib/xnanosleep.o lib/xprintf.o lib/xreadlink.o lib/xsize.o lib/xstrtod.o lib/xstrtoimax.o lib/xstrtol-error.o lib/xstrtol.o lib/xstrtold.o lib/xstrtoul.o lib/xstrtoumax.o lib/xtime.o lib/xvasprintf.o lib/yesno.o
	$(AR) cr $@ lib/qsort.o lib/time_rz.o lib/getprogname.o lib/reallocarray.o lib/rawmemchr.o lib/setlocale-lock.o lib/unistr/u8-uctomb.o lib/parse-datetime.o src/version.o lib/acl-errno-valid.o lib/acl-internal.o lib/af_alg.o lib/alignalloc.o lib/allocator.o lib/areadlink-with-size.o lib/areadlink.o lib/areadlinkat-with-size.o lib/areadlinkat.o lib/argmatch.o lib/argv-iter.o lib/backup-find.o lib/backup-rename.o lib/backupfile.o lib/base32.o lib/base64.o lib/basename-lgpl.o lib/basename.o lib/binary-io.o lib/bitrotate.o lib/btoc32.o lib/buffer-lcm.o lib/c-ctype.o lib/c-file-type.o lib/c-strcasecmp.o lib/c-strncasecmp.o lib/c-strtod.o lib/c-strtold.o lib/c32_apply_type_test.o lib/c32_get_type_test.o lib/c32isalnum.o lib/c32isalpha.o lib/c32isblank.o lib/c32iscntrl.o lib/c32isdigit.o lib/c32isgraph.o lib/c32islower.o lib/c32isprint.o lib/c32ispunct.o lib/c32isspace.o lib/c32isupper.o lib/c32isxdigit.o lib/c32tolower.o lib/c32width.o lib/canon-host.o lib/canonicalize.o lib/careadlinkat.o lib/chmodat.o lib/chownat.o lib/cl-strtod.o lib/cl-strtold.o lib/cloexec.o lib/close-stream.o lib/closein.o lib/closeout.o lib/copy-acl.o lib/count-leading-zeros.o lib/creat-safer.o lib/cycle-check.o lib/di-set.o lib/dirchownmod.o lib/dirname-lgpl.o lib/dirname.o lib/dtoastr.o lib/dtotimespec.o lib/dup-safer-flag.o lib/dup-safer.o lib/error.o lib/exclude.o lib/exitfail.o lib/fadvise.o lib/fd-hook.o lib/fd-reopen.o lib/fd-safer-flag.o lib/fd-safer.o lib/fdutimensat.o lib/file-has-acl.o lib/file-set.o lib/file-type.o lib/filemode.o lib/filenamecat-lgpl.o lib/filenamecat.o lib/filevercmp.o lib/fopen-safer.o lib/fprintftime.o lib/freading.o lib/freadseek.o lib/freopen-safer.o lib/ftoastr.o lib/fts.o lib/full-read.o lib/full-write.o lib/get-permissions.o lib/gethrxtime.o lib/getndelim2.o lib/getopt.o lib/getopt1.o lib/gettime-res.o lib/gettime.o lib/getugroups.o lib/glthread/lock.o lib/glthread/threadlib.o lib/glthread/tls.o lib/hard-locale.o lib/hash-pjw.o lib/hash-triple-simple.o lib/hash-triple.o lib/hash.o lib/heap.o lib/human.o lib/i-ring.o lib/ialloc.o lib/idcache.o lib/imaxtostr.o lib/ino-map.o lib/inttostr.o lib/ldtoastr.o lib/linebuffer.o lib/localcharset.o lib/long-options.o lib/malloc/dynarray_at_failure.o lib/malloc/dynarray_emplace_enlarge.o lib/malloc/dynarray_finalize.o lib/malloc/dynarray_resize.o lib/malloc/dynarray_resize_clear.o lib/malloc/scratch_buffer_grow.o lib/malloc/scratch_buffer_grow_preserve.o lib/malloc/scratch_buffer_set_array_size.o lib/malloca.o lib/math.o lib/mbscasecmp.o lib/mbschr.o lib/mbslen.o lib/mbsrtoc32s.o lib/mbswidth.o lib/mbszero.o lib/mcel.o lib/md5-stream.o lib/md5.o lib/memcasecmp.o lib/memchr2.o lib/memcmp2.o lib/memcoll.o lib/mgetgroups.o lib/mkancesdirs.o lib/mkdir-p.o lib/mkstemp-safer.o lib/modechange.o lib/mpsort.o lib/nproc.o lib/nstrftime.o lib/obstack.o lib/offtostr.o lib/open-safer.o lib/openat-die.o lib/openat-proc.o lib/openat-safer.o lib/opendir-safer.o lib/opendirat.o lib/physmem.o lib/pipe-safer.o lib/pipe2.o lib/posixtm.o lib/posixver.o lib/printf-frexp.o lib/printf-frexpl.o lib/priv-set.o lib/progname.o lib/propername-lite.o lib/qcopy-acl.o lib/qset-acl.o lib/quotearg.o lib/rand-isaac.o lib/randint.o lib/randperm.o lib/randread.o lib/read-file.o lib/readtokens.o lib/readtokens0.o lib/readutmp.o lib/renameatu.o lib/root-dev-ino.o lib/safe-read.o lib/safe-write.o lib/same-inode.o lib/same.o lib/save-cwd.o lib/savedir.o lib/savewd.o lib/se-context.o lib/se-label.o lib/se-selinux.o lib/selinux-at.o lib/set-acl.o lib/set-permissions.o lib/setlocale_null-unlocked.o lib/setlocale_null.o lib/settime.o lib/sha1-stream.o lib/sha1.o lib/sha256-stream.o lib/sha256.o lib/sha512-stream.o lib/sha512.o lib/sig-handler.o lib/skipchars.o lib/sm3-stream.o lib/sm3.o lib/sockets.o lib/stat-time.o lib/strintcmp.o lib/stripslash.o lib/strnlen1.o lib/strnumcmp.o lib/sys_socket.o lib/targetdir.o lib/tempname.o lib/timespec.o lib/tmpdir.o lib/u64.o lib/uinttostr.o lib/umaxtostr.o lib/unicodeio.o lib/unistd.o lib/unlinkdir.o lib/userspec.o lib/utimecmp.o lib/utimens.o lib/verror.o lib/version-etc-fsf.o lib/version-etc.o lib/wctype-h.o lib/write-any-file.o lib/xalignalloc.o lib/xalloc-die.o lib/xasprintf.o lib/xbinary-io.o lib/xdectoimax.o lib/xdectoumax.o lib/xfts.o lib/xgetcwd.o lib/xgetgroups.o lib/xgethostname.o lib/xmalloc.o lib/xmemcoll.o lib/xnanosleep.o lib/xprintf.o lib/xreadlink.o lib/xsize.o lib/xstrtod.o lib/xstrtoimax.o lib/xstrtol-error.o lib/xstrtol.o lib/xstrtold.o lib/xstrtoul.o lib/xstrtoumax.o lib/xtime.o lib/xvasprintf.o lib/yesno.o
	$(RANLIB) $@

src/ls: src/ls.o src/ls-ls.o lib/libcoreutils.a
	$(CC) -static -o $@ src/ls.o src/ls-ls.o lib/libcoreutils.a -lm -pthread

src/cat: src/cat.o lib/libcoreutils.a
	$(CC) -static -o $@ src/cat.o lib/libcoreutils.a -lm -pthread

src/sort: src/sort.o lib/libcoreutils.a
	$(CC) -static -o $@ src/sort.o lib/libcoreutils.a -lm -pthread

src/cp: src/cp.o src/copy.o src/cp-hash.o src/force-link.o src/selinux.o lib/libcoreutils.a
	$(CC) -static -o $@ src/cp.o src/copy.o src/cp-hash.o src/force-link.o src/selinux.o lib/libcoreutils.a -lm -pthread

src/mkdir: src/mkdir.o src/prog-fprintf.o src/selinux.o lib/libcoreutils.a
	$(CC) -static -o $@ src/mkdir.o src/prog-fprintf.o src/selinux.o lib/libcoreutils.a -lm -pthread

src/date: src/date.o lib/libcoreutils.a
	$(CC) -static -o $@ src/date.o lib/libcoreutils.a -lm -pthread

src/printf: src/printf.o lib/libcoreutils.a
	$(CC) -static -o $@ src/printf.o lib/libcoreutils.a -lm -pthread

src/wc: src/wc.o lib/libcoreutils.a
	$(CC) -static -o $@ src/wc.o lib/libcoreutils.a -lm -pthread

src/version.h: $(RECIPE_DIR)/version.h
	cp $< $@

src/version.c: $(RECIPE_DIR)/version.c
	cp $< $@

src/version.o: src/version.c src/version.h config.h
	$(CC) $(CFLAGS) -c src/version.c -o $@

lib/parse-datetime.o: lib/parse-datetime.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/parse-datetime.c -o $@

lib/configmake.h: $(RECIPE_DIR)/lib/configmake.h
	cp $< $@

lib/malloc:
	mkdir -p $@

lib/malloc/dynarray.gl.h: $(RECIPE_DIR)/lib/malloc/dynarray.gl.h | lib/malloc
	cp $< $@

lib/malloc/dynarray-skeleton.gl.h: $(RECIPE_DIR)/lib/malloc/dynarray-skeleton.gl.h | lib/malloc
	cp $< $@

lib/malloc/scratch_buffer.gl.h: $(RECIPE_DIR)/lib/malloc/scratch_buffer.gl.h | lib/malloc
	cp $< $@

lib/time_rz.o: lib/time_rz.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/time_rz.c -o lib/time_rz.o

lib/getprogname.o: lib/getprogname.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/getprogname.c -o lib/getprogname.o

lib/reallocarray.o: lib/reallocarray.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/reallocarray.c -o lib/reallocarray.o

lib/rawmemchr.o: lib/rawmemchr.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/rawmemchr.c -o lib/rawmemchr.o

lib/setlocale-lock.o: lib/setlocale-lock.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/setlocale-lock.c -o lib/setlocale-lock.o

lib/unistr/u8-uctomb.o: lib/unistr/u8-uctomb.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/unistr/u8-uctomb.c -o lib/unistr/u8-uctomb.o

lib/qsort.o: lib/qsort.c config.h $(HEADERS)
	$(CC) $(CFLAGS) -c lib/qsort.c -o $@
