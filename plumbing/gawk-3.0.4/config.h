/* config.h for GNU awk 3.0.4 built by seed-cc against runtime/gcc-seed.
   No configure script runs.  Each answer below is true for this runtime.
   DEFPATH, which Makefile.in passes as a quoted -D option, is here too,
   so that make runs every compile without a shell; it is the value a
   build with prefix /usr gives.  */

#define DEFPATH ".:/usr/share/awk"

#define STDC_HEADERS 1
#define RETSIGTYPE void
#define SPRINTF_RET int
#define GETGROUPS_T gid_t
#define GETPGRP_VOID 1
#define HAVE_STRINGIZE 1
#define HAVE_ST_BLKSIZE 1
#define HAVE_VPRINTF 1
#define TIME_WITH_SYS_TIME 1
#define HAVE_TZNAME 1

#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STDARG_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_UNISTD_H 1
#define HAVE_LIBM 1

#define HAVE_FMOD 1
#define HAVE_GETPAGESIZE 1
#define HAVE_MEMCMP 1
#define HAVE_MEMCPY 1
#define HAVE_MEMSET 1
#define HAVE_SETLOCALE 1
#define HAVE_STRCHR 1
#define HAVE_STRERROR 1
#define HAVE_STRFTIME 1
#define HAVE_STRNCASECMP 1
#define HAVE_STRTOD 1
#define HAVE_SYSTEM 1
#define HAVE_TZSET 1

/* The compiler has no builtin alloca; alloca.c is the C alloca, and
   <alloca.h> declares it.  */
#define C_ALLOCA 1
#define STACK_DIRECTION -1
#define HAVE_ALLOCA_H 1

/* getopt.c includes <string.h> only for the GNU C library, and alloca.c
   includes <stdlib.h> only under HAVE_STDLIB_H, which gawk's configure
   never defines; both then call strcmp or free undeclared.  Declare them
   from the real headers so the build keeps
   -Werror=implicit-function-declaration.  */
#include <stdlib.h>
#include <string.h>

#include <custom.h>	/* overrides for stuff autoconf can't deal with */
