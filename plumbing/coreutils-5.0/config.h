/* config.h for GNU coreutils 5.0 built by seed-cc against runtime/gcc-seed.
   No configure script runs.  Each answer below is true for this runtime;
   features left undefined (NLS, multibyte widths, mount lists, utmp,
   ACLs) make coreutils use its own portable code or leave the program out.
   Functions the runtime lacks come from lib/ (the LIBOBJS in the Makefile),
   as configure would arrange.  The quoted -D options src/Makefile.in
   passes (LOCALEDIR, SHAREDIR) are here too, so that make runs every
   compile without a shell; they are the values a build with prefix /usr
   gives.  _GNU_SOURCE is left undefined: with it the runtime would declare
   POSIX getline, which conflicts with lib/getline.h's int getline on a C
   library other than glibc.  */

#define PACKAGE "coreutils"
#define PACKAGE_NAME "GNU coreutils"
#define PACKAGE_TARNAME "coreutils"
#define PACKAGE_VERSION "5.0"
#define PACKAGE_STRING "GNU coreutils 5.0"
#define PACKAGE_BUGREPORT "bug-coreutils@gnu.org"
#define GNU_PACKAGE "GNU coreutils"
#define VERSION "5.0"
#define HOST_OPERATING_SYSTEM "GNU/Linux"
#define LOCALEDIR "/usr/share/locale"
#define SHAREDIR "/usr/share"
#define LIBDIR "/usr/lib"

#define STDC_HEADERS 1
#define PROTOTYPES 1
#define __PROTOTYPES 1
#define RETSIGTYPE void
#define CLOSEDIR_VOID 0
#define HAVE_LONG_FILE_NAMES 1
#define HAVE_VPRINTF 1
#define HAVE_C_BACKSLASH_A 1
#define ARGMATCH_DIE usage (1)
#define ARGMATCH_DIE_DECL extern void usage ()

/* Headers.  */
#define HAVE_DIRENT_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_FLOAT_H 1
#define HAVE_GRP_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_PATHS_H 1
#define HAVE_PWD_H 1
#define HAVE_STDBOOL_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_SYSMACROS_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_TERMIOS_H 1
#define HAVE_UNISTD_H 1
#define HAVE_UTIME_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1
#define TIME_WITH_SYS_TIME 1
#define GWINSZ_IN_SYS_IOCTL 1

/* Types and structure members.  */
#define HAVE_LONG_LONG 1
#define HAVE_UNSIGNED_LONG_LONG 1
#define HAVE_MBSTATE_T 1
#define GETGROUPS_T gid_t
/* The runtime has no major_t or minor_t; configure defines them.  */
#define major_t unsigned int
#define minor_t unsigned int
#define HAVE_STRUCT_TIMESPEC 1
#define HAVE_STRUCT_UTIMBUF 1
#define HAVE_STRUCT_DIRENT_D_TYPE 1
#define D_INO_IN_DIRENT 1
#define HAVE_STRUCT_STAT_ST_BLKSIZE 1
#define HAVE_STRUCT_STAT_ST_BLOCKS 1
#define HAVE_ST_BLOCKS 1
#define ST_MTIM_NSEC tv_nsec
#define HAVE_TZNAME 1

/* Declarations.  */
#define HAVE_DECL_DIRFD 1
#define HAVE_DECL_EUIDACCESS 0
#define HAVE_DECL_FREE 1
#define HAVE_DECL_GETCWD 1
#define HAVE_DECL_GETENV 1
#define HAVE_DECL_GETEUID 1
#define HAVE_DECL_GETGRGID 1
#define HAVE_DECL_GETLOGIN 1
#define HAVE_DECL_GETPWUID 1
#define HAVE_DECL_GETUID 1
#define HAVE_DECL_GETUTENT 0
#define HAVE_DECL_LSEEK 1
#define HAVE_DECL_MALLOC 1
#define HAVE_DECL_MEMCHR 1
#define HAVE_DECL_MEMRCHR 0
#define HAVE_DECL_NANOSLEEP 1
#define HAVE_DECL_REALLOC 1
#define HAVE_DECL_STPCPY 1
#define HAVE_DECL_STRERROR 1
#define HAVE_DECL_STRERROR_R 0
#define HAVE_DECL_STRNDUP 1
#define HAVE_DECL_STRNLEN 1
#define HAVE_DECL_STRSIGNAL 1
#define HAVE_DECL_STRSTR 1
#define HAVE_DECL_STRTOIMAX 1
#define HAVE_DECL_STRTOL 1
#define HAVE_DECL_STRTOLL 1
#define HAVE_DECL_STRTOUL 1
#define HAVE_DECL_STRTOULL 1
#define HAVE_DECL_STRTOUMAX 1
#define HAVE_DECL_SYS_SIGLIST 1
#define HAVE_DECL_TTYNAME 1
#define HAVE_DECL_WCWIDTH 0
#define HAVE_DECL__SYS_SIGLIST 0
#define HAVE_DECL___FPENDING 0
#define HAVE_DECL_CLEARERR_UNLOCKED 0
#define HAVE_DECL_FEOF_UNLOCKED 0
#define HAVE_DECL_FERROR_UNLOCKED 0
#define HAVE_DECL_FFLUSH_UNLOCKED 0
#define HAVE_DECL_FGETS_UNLOCKED 0
#define HAVE_DECL_FPUTC_UNLOCKED 0
#define HAVE_DECL_FPUTS_UNLOCKED 0
#define HAVE_DECL_FREAD_UNLOCKED 0
#define HAVE_DECL_FWRITE_UNLOCKED 0
#define HAVE_DECL_GETCHAR_UNLOCKED 0
#define HAVE_DECL_GETC_UNLOCKED 0
#define HAVE_DECL_PUTCHAR_UNLOCKED 0
#define HAVE_DECL_PUTC_UNLOCKED 0

/* Functions in the runtime.  */
#define HAVE_ALARM 1
#define HAVE_ATEXIT 1
/* HAVE_BTOWC is left undefined although the runtime has btowc: with it,
   lib/fnmatch.c and lib/regex.c switch to wide-character matching, which
   needs wctype_t, wctype and iswctype, and the runtime's <wctype.h> has
   only the iswXXX classifiers.  */
#define HAVE_CHROOT 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_DIRFD 1
#define HAVE_DUP2 1
#define HAVE_ENDGRENT 1
#define HAVE_ENDPWENT 1
#define HAVE_FCHDIR 1
#define HAVE_FDATASYNC 1
#define HAVE_FLOOR 1
#define HAVE_FTRUNCATE 1
#define HAVE_GETCWD 1
#define HAVE_GETDELIM 1
#define HAVE_GETGROUPS 1
#define HAVE_GETHOSTNAME 1
#define HAVE_GETPAGESIZE 1
#define HAVE_GETTIMEOFDAY 1
#define HAVE_ISASCII 1
#define HAVE_ISWPRINT 1
#define HAVE_ISWSPACE 1
#define HAVE_LCHOWN 1
#define HAVE_LOCALECONV 1
#define HAVE_LOCALTIME_R 1
#define HAVE_MALLOC 1
#define HAVE_MBLEN 1
#define HAVE_MBRLEN 1
#define HAVE_MBRTOWC 1
#define HAVE_MBSINIT 1
#define HAVE_MEMCHR 1
#define HAVE_MEMCMP 1
#define HAVE_MEMCPY 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_MKFIFO 1
#define HAVE_MKSTEMP 1
#define HAVE_MODF 1
#define HAVE_PATHCONF 1
#define HAVE_RAISE 1
#define HAVE_REALLOC 1
#define HAVE_REALPATH 1
#define HAVE_RINT 1
#define HAVE_RMDIR 1
#define HAVE_SETLOCALE 1
#define HAVE_SETREGID 1
#define HAVE_SETREUID 1
#define HAVE_SQRT 1
#define HAVE_STPCPY 1
#define HAVE_STRCASECMP 1
#define HAVE_STRCHR 1
#define HAVE_STRCSPN 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRFTIME 1
#define HAVE_STRNCASECMP 1
#define HAVE_STRNDUP 1
#define HAVE_STRPBRK 1
#define HAVE_STRRCHR 1
#define HAVE_STRSTR 1
#define HAVE_STRTOIMAX 1
#define HAVE_STRTOL 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOUL 1
#define HAVE_STRTOULL 1
#define HAVE_STRTOUMAX 1
#define HAVE_TZSET 1
#define HAVE_UNAME 1
#define HAVE_UTIME 1
#define HAVE_UTIME_NULL 1
#define HAVE_UTIMES_NULL 1
#define HAVE_WCRTOMB 1

/* Linux behaviour.  */
#define LSTAT_FOLLOWS_SLASHED_SYMLINK 1
#define RMDIR_ERRNO_NOT_EMPTY 39
#define UTILS_OPEN_MAX 1024
#define FILESYSTEM_ACCEPTS_DRIVE_LETTER_PREFIX 0
#define FILESYSTEM_BACKSLASH_IS_FILE_NAME_SEPARATOR 0
/* The FILE structure matches none of the layouts fpending.m4 probes for,
   so configure gives this answer (lib/__fpending.c).  */
#define PENDING_OUTPUT_N_BYTES 1

/* lib/strftime.c provides nstrftime, as configure always arranges.  */
#define my_strftime nstrftime

/* The compiler has no builtin alloca; lib/alloca.c is the C alloca, and
   <alloca.h> declares it.  */
#define C_ALLOCA 1
#define STACK_DIRECTION -1
#define HAVE_ALLOCA_H 1

/* lib/ftw.c uses ISSLASH and FILESYSTEM_PREFIX_LEN without including
   dirname.h, which defines them (GNU libc has its own ftw, so the file is
   never compiled there).  These are dirname.h's own POSIX definitions.  */
#define ISSLASH(C) ((C) == '/')
#define FILESYSTEM_PREFIX_LEN(Filename) 0
/* lib/ftw.c calls tdestroy, which lib/search.h declares only under GNU
   libc's __USE_GNU; lib/tsearch.c defines it.  */
void tdestroy (void *root, void (*freefct) (void *));

/* Two sources rely on GNU libc headers declaring more than POSIX asks:
   src/dd.c calls ioctl after including only <sys/mtio.h>, and
   src/dircolors.c calls strcasecmp after including only <string.h>.
   Declare both from the real headers so the build keeps
   -Werror=implicit-function-declaration.  */
#include <sys/ioctl.h>
#include <strings.h>
