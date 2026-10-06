/* config.h for GNU grep 2.4 built by seed-cc against runtime/gcc-seed.
   No configure script runs.  Each answer below is true for this runtime;
   features left undefined (NLS, mmap, wide characters) make grep use its
   own portable code.  */

#define PACKAGE "grep"
#define VERSION "2.4"

#define STDC_HEADERS 1
#define PROTOTYPES 1
#define HAVE_DIRENT_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_UNISTD_H 1

#define HAVE_GETCWD 1
#define HAVE_GETPAGESIZE 1
#define HAVE_ISASCII 1
#define HAVE_MEMCHR 1
#define HAVE_MEMMOVE 1
#define HAVE_PUTENV 1
#define HAVE_SETENV 1
#define HAVE_SETLOCALE 1
#define HAVE_STPCPY 1
#define HAVE_STRCASECMP 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1

/* The compiler has no builtin alloca; src/alloca.c is the C alloca, and
   <alloca.h> declares it (regex.c otherwise calls it undeclared).  */
#define C_ALLOCA 1
#define STACK_DIRECTION -1
#define HAVE_ALLOCA_H 1

/* src/getopt.c includes <string.h> only for the GNU C library, then calls
   strcmp undeclared.  Declare it from the real header so the build keeps
   -Werror=implicit-function-declaration.  */
#include <string.h>
