# GNU coreutils 9.5

This fixed recipe builds 102 programs from the default Linux coreutils 9.5
program set with no external ACL, xattr, SELinux, SMACK, GMP, OpenSSL or NLS
libraries. Four programs and the stdbuf helper are skipped as described below.
No configure, autoconf, automake, source edits or host parser generator are
involved. It does not replace the coreutils build in ladder.

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
  object list if used. This recipe is not a completed gnulib behavior-probe
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

## Default Linux program coverage

The set comes from upstream `src/cu-progs.mk`, `m4/cu-progs.m4` and the
program-selection conditions in `configure.ac`, read without executing
configure: 96 default programs plus chroot, df, hostid, nice, pinky, stdbuf,
stty, timeout, users and who on Linux (106 commands total). No optional
libraries remove chcon or runcon from that list: they build with upstream's
disabled-security behavior. arch, hostname and the single-binary coreutils
wrapper are explicitly not installed by default and are outside this target.
The upstream PROGRAMS name ginstall is exposed here as `src/install`, matching
upstream's installation name transform. There is still no install target.

The 102 built commands are also recorded one per line in `programs.txt`, and
listed explicitly in the Makefile's PROGRAMS variable:

```text
[ b2sum base32 base64 basename basenc cat chcon chgrp chmod chown chroot cksum
comm cp csplit cut date dd df dir dircolors dirname du echo env expand expr
factor false fmt fold groups head hostid id install join kill link ln logname
ls md5sum mkdir mkfifo mknod mktemp mv nice nl nohup nproc numfmt od paste
pathchk pr printenv printf ptx pwd readlink realpath rm rmdir runcon seq
sha1sum sha224sum sha256sum sha384sum sha512sum shred shuf sleep sort split
stat stty sum sync tac tail tee test timeout touch tr true truncate tsort tty
uname unexpand uniq unlink uptime vdir wc whoami yes
```

| Skipped output | Reason |
| --- | --- |
| pinky | musl 1.1.24 has utmp headers but no working session-record iterator: getutxent is a stub that always returns null. Building would yield empty session results. |
| users | Same missing utmp session-record iteration. |
| who | Same missing utmp session-record iteration. |
| stdbuf | Requires LD_PRELOAD and the libstdbuf.so helper. This sysroot supplies static libc.a only, no shared libc; preload cannot affect the static outputs. |
| libstdbuf.so (helper) | The shared helper for stdbuf requires the unavailable shared runtime. It is not included in the 106-command count. |

Disassembly of the supplied libc.a confirms getutxent returns zero and
setutxent simply returns. These are functional skips, even though the three
session programs can compile against musl's declarations. uptime remains:
gnulib readutmp has an upstream Linux boot-time fallback, and its runtime
check passed. Its user count remains zero with musl's stub iterator.

## Additional fixed inputs

`feature-answers.json` records the added feature answers and evidence.
Mount-list reading selects MOUNTED_GETMNTENT1, with musl's mntent functions;
filesystem usage selects STAT_STATVFS, and stat uses native Linux statfs.
A compiler/link/runtime probe confirmed mount entries from /proc/mounts and
successful statfs/statvfs calls. The statfs type, name-length and fragment-size
members, utmpx members and GNU ut_exit aliases were checked against the
supplied sysroot, not host headers. Linux link does not follow symlinks;
major_t/minor_t use upstream's unsigned-int fallback and makedev is declared
by sys/sysmacros.h.

No external GMP is linked. `lib/gmp.h` is the gnulib.mk mini-GMP wrapper,
and mini-gmp-gnulib.c includes the bundled mini-gmp implementation. expr and
factor therefore work without libgmp. The wider links also need bundled
regex, chdir-long, fsusage, mountlist, sig2str, memset_explicit and isapipe
objects. The shipped regex.h is used unmodified with the bundled regex.c.

Special source lists and compile definitions follow src/local.mk: separate
HASH_ALGO_* objects for sum and all digest variants (including cksum and
BLAKE2), BASE_TYPE objects for base32/base64/basenc, and shared sources for
listing, ownership, file operations, signals and text tools. Generated
filesystem/dircolors/primes headers are already shipped in this tarball.
All new commands retain the existing explicit compile/archive/static-link
style, tool paths and GNU99 flags, with no shell operators in recipe lines.

TIME_H_DEFINES_STRUCT_TIMESPEC=1 retains musl's native timespec. The earlier
header answer of 0 generated a distinct rpl_timespec that conflicted with
native itimerspec.it_value in timeout's initializer. Correcting the generated
header fixes the type mismatch without upstream edits. Native POSIX timers
remain enabled; timeout was checked with both integral and fractional durations.

## Results and limits

A fresh extraction compiled and linked all 102 programs in **35.54 seconds**
with **four jobs**, excluding extraction and checks. Evidence is in
`build-out/modern-work/coreutils-full-clean.log`, `coreutils-full-check.log`,
`coreutils-full-extra-check.log` and `coreutils-full-audit.json`.

`plumbing-modern/check.sh coreutils` passes the original eight-program checks
plus head/tail/cut/tr/uniq/join/paste/comm/od, known MD5 and SHA-256 digests,
basename/dirname, true and false test predicates, [, expr arithmetic and regex,
factor, seq, env/printenv, install mode, ln link count, mv, touch timestamps,
stat, du byte size, df and rm. Pipelines stage outputs so an earlier failure
cannot be hidden by a later command's exit status. Additional development
checks compared every digest variant against host results, round-tripped
base32/base64, checked basenc, csplit/nl/tac, and exercised timeout and uptime.
The combined make/bash/coreutils smoke check also passed.

All 102 ELF files have neither an interpreter nor a dynamic segment. Version
checks passed for 101 programs (false correctly returns status 1); test treats
--version as a POSIX string operand and was verified with predicates instead.
All 1,559 shipped C/header members compare byte for byte against the pinned
tarball. No upstream sources were patched.

This is broad default-command coverage with the explicit skips above, not a
complete configure-result or GNU behavior-test equivalence claim. The
upstream regression suite, documentation and installation are not supplied;
optional services and the full gnulib behavior-probe matrix remain untested.
