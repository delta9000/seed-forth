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
#endif
