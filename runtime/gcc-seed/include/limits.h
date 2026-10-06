#ifndef SEED_GCC_LIMITS_H
#define SEED_GCC_LIMITS_H
/* Linux AMD64: eight-bit bytes, signed plain char, LP64 integers. */
#define CHAR_BIT 8
/* The only supported character encoding is stateless ASCII C/POSIX. */
#define MB_LEN_MAX 1
#define SCHAR_MIN (-127 - 1)
#define SCHAR_MAX 127
#define UCHAR_MAX 255
#define CHAR_MIN SCHAR_MIN
#define CHAR_MAX SCHAR_MAX
#define SHRT_MIN (-32767 - 1)
#define SHRT_MAX 32767
#define USHRT_MAX 65535
#define INT_MIN (-2147483647 - 1)
#define INT_MAX 2147483647
#define UINT_MAX 4294967295U
#define LONG_MIN (-9223372036854775807L - 1L)
#define LONG_MAX 9223372036854775807L
/* ssize_t is signed long on this Linux AMD64 target. */
#define SSIZE_MAX LONG_MAX
#define ULONG_MAX 18446744073709551615UL
#define LLONG_MIN (-9223372036854775807LL - 1LL)
#define LLONG_MAX 9223372036854775807LL
#define ULLONG_MAX 18446744073709551615ULL
/* Linux kernel and glibc limits; see ../SYSINFO.md. Values that vary at
   run time (open files, argument bytes) are left to sysconf. */
#define PATH_MAX 4096
#define NAME_MAX 255
#define PIPE_BUF 4096
#define NGROUPS_MAX 65536
#define LINE_MAX 2048
#define RE_DUP_MAX 0x7fff
#define HOST_NAME_MAX 64
#define LOGIN_NAME_MAX 256
#define TTY_NAME_MAX 32
#define IOV_MAX 1024
#define CHARCLASS_NAME_MAX 2048
#define COLL_WEIGHTS_MAX 255
#define EXPR_NEST_MAX 32
#define BC_BASE_MAX 99
#define BC_DIM_MAX 2048
#define BC_SCALE_MAX 99
#define BC_STRING_MAX 1000
#define _POSIX_ARG_MAX 4096
#define _POSIX_CHILD_MAX 25
#define _POSIX_LINK_MAX 8
#define _POSIX_MAX_CANON 255
#define _POSIX_MAX_INPUT 255
#define _POSIX_NAME_MAX 14
#define _POSIX_NGROUPS_MAX 8
#define _POSIX_OPEN_MAX 20
#define _POSIX_PATH_MAX 256
#define _POSIX_PIPE_BUF 512
#define _POSIX_SSIZE_MAX 32767
#define _POSIX_STREAM_MAX 8
#define _POSIX_TZNAME_MAX 6
#define _POSIX2_LINE_MAX 2048
#define _POSIX2_RE_DUP_MAX 255
#endif
