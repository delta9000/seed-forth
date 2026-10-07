# GNU coreutils 9.5

This draft targets the eight requested programs: ls, cat, sort, cp, mkdir,
date, printf and wc. It does not yet replace the complete coreutils build in
ladder. No configure, autoconf, automake, source edits or host parser generator
are involved. All eight programs build and pass the requested smoke checks. See
../README.md for measured times and the remaining package-coverage limit.

The configuration is fixed for Linux x86-64, musl 1.1.24 and GCC 4.0.4.
`config.h` preserves upstream lib/config.hin's compiler portability macros.
The recipes use `-std=gnu99`: GCC 4.0.4 supports C99 loop declarations, which
coreutils uses. This does not enable C11/C23 features that GCC lacks.

## Configuration choices

- Use libc's headers and available POSIX functions. Header existence and
  function declarations were checked with the supplied compiler, never the
  host compiler. GNU extensions are enabled. Linux stat has st_blocks,
  st_blksize and st_[amc]tim.tv_nsec; directory entries have d_type/d_ino.
- Use the real libc sigset_t, siginfo_t, timeval, timespec, pthread_t,
  sockaddr_storage, sched_param, wctype_t and wctrans_t. LP64 integers and
  offsets are 64 bits; wchar_t is signed 32-bit and wint_t unsigned 32-bit.
  `GNULIB_OVERRIDES_STRUCT_STAT=0` is crucial: selecting the Windows
  replacement on Linux gives an incompatible struct stat without st_blocks.
- Leave C23 bool and compiler C11 assertions unavailable. bool comes from
  musl's stdbool.h; the generated assert.h incorporates upstream verify.h's
  portable static_assert implementation. FLEXIBLE_ARRAY_MEMBER is empty
  (native C99 flexible arrays). stdckdint.h uses gnulib's checked
  arithmetic fallback. No invented `_Generic` or compiler builtins are added.
- No ACL, SELinux, Smack, xattr, NLS, libcap, crypto acceleration or external
  Unicode library dependencies are enabled. Gnulib's configured SELinux
  stub headers are installed under lib/selinux (not their se-*.in.h names).
  Unicode DLL decoration substitutions are empty on Linux.
- Keep native malloc/realloc/free and most native POSIX functions:
  REPLACE_* switches default to zero. Missing optional libc functions are
  declared by wrappers; their required implementations must be added to the
  object list if used. This draft is not a completed gnulib behavior-probe
  matrix, and symbol availability alone does not establish GNU semantics.
- The bundled GNU getopt implementation is selected with `__GETOPT_PREFIX=rpl`
  and the wrapper's `HAVE_GETOPT_H=0`, even though libc has getopt.h. That
  avoids mixing libc's struct option with the bundled struct option.
- POSIX pthreads are selected, C11 and Windows threads disabled. Program links
  use -static -lm -pthread. Paths use a /usr prefix in configmake.h; version.c
  and version.h are fixed outputs of upstream's version-generation rules.

## Generated inputs and objects

`lib/*.h` contains configured *.in.h results, including gnulib's c++defs,
arg-nonnull and warn-on-use snippets. `header-answers.json` records the token
substitutions. The comments in c++defs.h contain illustrative @FOO@ text;
those are comments, not unexpanded configuration directives.

The upstream generation rules also require malloc/dynarray.gl.h,
malloc/dynarray-skeleton.gl.h and malloc/scratch_buffer.gl.h. These contain
only the transformations specified by lib/gnulib.mk: remove libc_hidden_proto,
replace GNU libc attributes/branch macros, and point at dynarray.gl.h.
The original malloc sources remain untouched.

The library object list begins with unconditional lib/gnulib.mk sources,
plus error, fts, obstack, GNU getopt, the shipped parse-datetime.c and the
additional replacements established by link evidence below. Every
object has an explicit compile command; configured headers are copied from
this recipe directory. All recipe commands are free of shell metacharacters.

The math wrapper uses INCLUDE_NEXT_AS_FIRST_DIRECTIVE=include_next and
NEXT_AS_FIRST_DIRECTIVE_MATH_H=<math.h>, in addition to ordinary include-next
answers. These are distinct substitutions, not numeric feature switches.

USE_XATTR is undefined, rather than defined to 0: qcopy-acl.c uses both
`#if USE_XATTR` and `#ifdef USE_XATTR`, so defining 0 enables calls to
libattr without its declarations. USE_ACL is a numeric 0.

DIR_HAS_FD_MEMBER=1 follows m4/dirent_h.m4: the name means dirfd works,
not that DIR exposes a public member. It is 1 on Linux/musl. The native
stdint.h is C99-complete (HAVE_C99_STDINT_H=1); the integer-literal suffix
answers are l/ul/empty/empty/u for ptrdiff_t/size_t/sig_atomic_t/wchar_t/wint_t.
Using the fallback stdint branch with numeric suffix 0 produced incorrect
limit constants and failed randperm.c's SIZE_WIDTH assertion.

Link evidence selected time_rz, getprogname, reallocarray, rawmemchr,
setlocale-lock, unistr/u8-uctomb and qsort objects. musl 1.1.24 has no
qsort_r; gnulib's qsort.c supplies it. qsort_r.c adapts an existing BSD
signature and is not the correct replacement on this sysroot.

A fresh build compiled and linked all eight programs in 15.893 seconds with
four jobs. Their smoke checks passed, all eight ELF files are static, and
all shipped C/header files compare byte for byte with the pinned tarball.
