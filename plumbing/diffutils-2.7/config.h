/* config.h for GNU diffutils 2.7 built by seed-cc against runtime/gcc-seed.
   No configure script runs.  Each answer below is true for this runtime.
   The program paths Makefile.in passes as quoted -D options are here too,
   so that make runs every compile without a shell; they are the values a
   build with prefix /usr gives, as in live-bootstrap.  */

#define NULL_DEVICE "/dev/null"
#define PR_PROGRAM "/bin/pr"
#define DIFF_PROGRAM "/usr/bin/diff"
#define DEFAULT_EDITOR_PROGRAM "ed"

#define STDC_HEADERS 1
#define RETSIGTYPE void
#define HAVE_ST_BLKSIZE 1
#define HAVE_VPRINTF 1

#define HAVE_DIRENT_H 1
#define HAVE_FCNTL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_FILE_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1

#define HAVE_DUP2 1
#define HAVE_MEMCHR 1
#define HAVE_SIGACTION 1
#define HAVE_STRCHR 1
#define HAVE_STRERROR 1

/* The runtime has fork but no vfork; configure's AC_FUNC_VFORK maps it.  */
#define vfork fork

/* The compiler has no builtin alloca; alloca.c is the C alloca, and regex.c
   declares it itself.  */
#define C_ALLOCA 1
#define STACK_DIRECTION -1

/* getopt.c includes <string.h> only for the GNU C library, and alloca.c
   never includes <stdlib.h>; both then call strcmp or free undeclared.
   Declare them from the real headers so the build keeps
   -Werror=implicit-function-declaration.  */
#include <stdlib.h>
#include <string.h>
