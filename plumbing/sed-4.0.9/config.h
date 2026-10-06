/* config.h for GNU sed 4.0.9 built by seed-cc against runtime/gcc-seed.
   No configure script runs.  Each answer below is true for this runtime;
   features left undefined (NLS, multibyte, mmap) make sed use its own
   portable code paths, as live-bootstrap's sed-4.0.9 recipe does.  */

#define PACKAGE "sed"
#define VERSION "4.0.9"
#define SED_FEATURE_VERSION "4.0"
#define ENABLE_NLS 0

/* configure's AC_GNU_SOURCE defines this everywhere; it declares getline.  */
#define _GNU_SOURCE 1

#define STDC_HEADERS 1
#define HAVE_STRING_H 1
#define HAVE_STDLIB_H 1
#define HAVE_LIMITS_H 1
#define HAVE_UNISTD_H 1
#define HAVE_FCNTL_H 1
#define HAVE_ERRNO_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_STDARG_H 1
#define HAVE_VPRINTF 1
#define HAVE_MEMCHR 1
#define HAVE_MEMCMP 1
#define HAVE_MEMCPY 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_MKSTEMP 1
#define HAVE_ISATTY 1

/* The compiler has no builtin alloca.  <alloca.h> declares it with a
   pointer result, and lib/alloca.c (the portable C alloca) defines it.  */
#define HAVE_ALLOCA_H 1
#define STACK_DIRECTION -1

/* sed/fmt.c calls strchr without including <string.h> (GCC accepts the
   implicit call as a builtin).  Declare it here, from the real header, so
   the build can keep -Werror=implicit-function-declaration.  */
#include <string.h>
