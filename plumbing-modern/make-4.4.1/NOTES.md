# GNU make 4.4.1

Fixed answers for native Linux x86-64, GCC 4.0.4 and musl 1.1.24.
No configure, autoconf, automake, or source patches are used.

- `config.h` retains upstream `src/config.h.in`'s portability macros and
  `mkcustom.h` include. Header/function declarations were checked by compiling
  small programs with the supplied compiler and static linking against its
  sysroot; absent headers are undefined, not defined to zero (some source
  tests use `#ifdef`). `HAVE_DECL_*` answers are numeric.
- GNU extensions expose musl's POSIX/GNU declarations. The LP64 integer types,
  `sig_atomic_t`, `dirent.d_type`, `SA_RESTART`, working fork/vfork, and
  `st_mtim.tv_nsec` are available. High resolution file timestamps are enabled.
- NLS, Guile and dynamic module loading are disabled; `/usr/lib` and
  `/usr/share/locale` are written as strings in config.h, avoiding quoted
  compiler arguments. Shell launching uses fork/exec (`USE_POSIX_SPAWN` is
  intentionally undefined), even though musl supplies posix_spawn.
- Jobserver and symlink timestamp support are enabled. The upstream bundled
  fnmatch/glob implementations are used; their configured headers are literal
  copies of `lib/{fnmatch,glob}.in.h`, as the upstream header rules specify.
  This avoids relying on glibc-specific glob behavior.
- Sources follow `make_SRCS`, adding posixos.c, remote-stub.c and four library
  objects. Guile's disabled translation unit does not need gmk-default.h.
  Every object has an explicit command, and every recipe line is shell-free.
- GCC 4.0.4 uses `-Werror-implicit-function-declaration`; it predates the
  `-Werror=implicit-function-declaration` option used by newer GCC versions.

See ../README.md for measured build and smoke-check results.
