/* config.h for GNU make 3.82 built by seed-cc against runtime/gcc-seed.
   No configure script runs: these are the answers configure would give for
   this runtime, following live-bootstrap's make-3.82 recipe (which passes
   them as -D options) plus the headers our runtime provides.  */

#define STDC_HEADERS 1
#define HAVE_STRING_H 1
#define HAVE_STDLIB_H 1
#define HAVE_LIMITS_H 1
#define HAVE_FCNTL_H 1
#define HAVE_UNISTD_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_DIRENT_H 1
#define HAVE_SA_RESTART 1
#define HAVE_DUP2 1
/* waitpid and a jobserver pipe, as configure finds them on Linux.  Without
   HAVE_WAITPID, make falls back to counting SIGCHLDs and in practice runs
   one job at a time even with -j; without MAKE_JOBSERVER, recursive makes
   would ignore -j.  */
#define HAVE_SYS_WAIT_H 1
#define HAVE_WAITPID 1
#define MAKE_JOBSERVER 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_VPRINTF 1
#define HAVE_ANSI_COMPILER 1
#define HAVE_STDARG_H 1
#define HAVE_MKTEMP 1
#define HAVE_GETCWD 1

#define FILE_TIMESTAMP_HI_RES 0
#define SCCS_GET "/nullop"
#define LOCALEDIR "/fake-locale"
#define PACKAGE "make"
#define VERSION "3.82"
#define INCLUDEDIR "/usr/include"
#define LIBDIR "/usr/lib"

/* The compiler has no builtin alloca; make links its own C alloca.c.  */
#define STACK_DIRECTION -1

/* vfork is not provided; fork has the semantics make needs.  */
#define vfork fork
