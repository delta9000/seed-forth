/* config.h for GNU tar 1.12 built by seed-cc against runtime/gcc-seed.
   No configure script runs.  Each answer below is true for this runtime;
   features left undefined (NLS, remote tape through rsh) make tar use its
   own portable code.  The list started from live-bootstrap's tar-1.12
   recipe and adds what runtime/gcc-seed now provides.  */

#define PACKAGE "tar"
#define VERSION "1.12"
#define _GNU_SOURCE 1

#define STDC_HEADERS 1
#define PROTOTYPES 1
#define RETSIGTYPE void
#define HAVE_VPRINTF 1
#define HAVE_ST_BLKSIZE 1
#define HAVE_ST_BLOCKS 1
#define SIZEOF_LONG_LONG 8
#define SIZEOF_UNSIGNED_LONG 8

#define HAVE_DIRENT_H 1
#define HAVE_FCNTL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STRING_H 1
#define HAVE_UNISTD_H 1
#define HAVE_UTIME_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_TIME_H 1
#define TIME_WITH_SYS_TIME 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_SYS_MTIO_H 1
#define MTIO_CHECK_FIELD mt_type

#define HAVE_EXECLP 1
#define HAVE_FSYNC 1
#define HAVE_FTRUNCATE 1
#define HAVE_GETCWD 1
#define HAVE_GETGRGID 1
#define HAVE_GETPWUID 1
#define HAVE_ISASCII 1
#define HAVE_LCHOWN 1
#define HAVE_MEMSET 1
#define HAVE_MKDIR 1
#define HAVE_MKFIFO 1
#define HAVE_MKNOD 1
#define HAVE_PUTENV 1
#define HAVE_RENAME 1
#define HAVE_RMDIR 1
#define HAVE_STRCHR 1
#define HAVE_STRERROR 1
#define HAVE_STRSTR 1

/* tar's own defaults, as configure sets them on GNU/Linux.  */
#define DEFAULT_ARCHIVE "-"
#define DEFAULT_BLOCKING 20
#define DENSITY_LETTER 1
#define DEVICE_PREFIX "/dev/rmt"

/* The compiler has no builtin alloca; lib/alloca.c is the C alloca.  */
#define C_ALLOCA 1
#define STACK_DIRECTION -1

/* getdate.c is bison output whose skeleton calls alloca without a
   declaration on compilers other than GCC; getdate.y offers this switch
   to include <alloca.h> instead.  */
#define FORCE_ALLOCA_H 1

/* lib/getopt.c includes <string.h> only for the GNU C library, and
   lib/alloca.c includes <stdlib.h> only under HAVE_STDLIB_H, which tar's
   configure never defines; both then call strcmp or free undeclared.
   Declare them from the real headers so the build keeps
   -Werror=implicit-function-declaration.  */
#include <stdlib.h>
#include <string.h>
