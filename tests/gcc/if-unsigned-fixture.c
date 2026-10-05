#define PRESENT 1
#define UINTMAX_MAX 0xffffffffffffffff
#define INTMAX_MAX 9223372036854775807
#define INTMAX_MIN (-9223372036854775807-1)
#if -1ULL < 0
yes
#else
no
#endif
#if 0xFFFFFFFFFFFFFFFF > 0
yes
#else
no
#endif
#if (0u - 1) > 0
yes
#else
no
#endif
#if -1 < 0u
yes
#else
no
#endif
#if -1 < 0u
yes
#else
no
#endif
#if -1 > 0u
yes
#else
no
#endif
#if -1 <= 0u
yes
#else
no
#endif
#if -1 >= 0u
yes
#else
no
#endif
#if -1 == 0u
yes
#else
no
#endif
#if -1 != 0u
yes
#else
no
#endif
#if 0u < -1
yes
#else
no
#endif
#if 0u > -1
yes
#else
no
#endif
#if 0u <= -1
yes
#else
no
#endif
#if 0u >= -1
yes
#else
no
#endif
#if 0u == -1
yes
#else
no
#endif
#if 0u != -1
yes
#else
no
#endif
#if UINTMAX_MAX < 1
yes
#else
no
#endif
#if UINTMAX_MAX > 1
yes
#else
no
#endif
#if UINTMAX_MAX <= 1
yes
#else
no
#endif
#if UINTMAX_MAX >= 1
yes
#else
no
#endif
#if UINTMAX_MAX == 1
yes
#else
no
#endif
#if UINTMAX_MAX != 1
yes
#else
no
#endif
#if 1 < UINTMAX_MAX
yes
#else
no
#endif
#if 1 > UINTMAX_MAX
yes
#else
no
#endif
#if 1 <= UINTMAX_MAX
yes
#else
no
#endif
#if 1 >= UINTMAX_MAX
yes
#else
no
#endif
#if 1 == UINTMAX_MAX
yes
#else
no
#endif
#if 1 != UINTMAX_MAX
yes
#else
no
#endif
#if INTMAX_MIN < 0
yes
#else
no
#endif
#if INTMAX_MIN > 0
yes
#else
no
#endif
#if INTMAX_MIN <= 0
yes
#else
no
#endif
#if INTMAX_MIN >= 0
yes
#else
no
#endif
#if INTMAX_MIN == 0
yes
#else
no
#endif
#if INTMAX_MIN != 0
yes
#else
no
#endif
#if 0 < INTMAX_MIN
yes
#else
no
#endif
#if 0 > INTMAX_MIN
yes
#else
no
#endif
#if 0 <= INTMAX_MIN
yes
#else
no
#endif
#if 0 >= INTMAX_MIN
yes
#else
no
#endif
#if 0 == INTMAX_MIN
yes
#else
no
#endif
#if 0 != INTMAX_MIN
yes
#else
no
#endif
#if INTMAX_MAX < -1
yes
#else
no
#endif
#if INTMAX_MAX > -1
yes
#else
no
#endif
#if INTMAX_MAX <= -1
yes
#else
no
#endif
#if INTMAX_MAX >= -1
yes
#else
no
#endif
#if INTMAX_MAX == -1
yes
#else
no
#endif
#if INTMAX_MAX != -1
yes
#else
no
#endif
#if -1 < INTMAX_MAX
yes
#else
no
#endif
#if -1 > INTMAX_MAX
yes
#else
no
#endif
#if -1 <= INTMAX_MAX
yes
#else
no
#endif
#if -1 >= INTMAX_MAX
yes
#else
no
#endif
#if -1 == INTMAX_MAX
yes
#else
no
#endif
#if -1 != INTMAX_MAX
yes
#else
no
#endif
#if UINTMAX_MAX / 2 == INTMAX_MAX
yes
#else
no
#endif
#if UINTMAX_MAX % 2 == 1
yes
#else
no
#endif
#if -1 / 2u == INTMAX_MAX
yes
#else
no
#endif
#if -1 % 2u == 1
yes
#else
no
#endif
#if -7 / 2 == -3
yes
#else
no
#endif
#if -7 % 2 == -1
yes
#else
no
#endif
#if 7u / -2 == 0
yes
#else
no
#endif
#if 7u % -2 == 7
yes
#else
no
#endif
#if (1u << 63) == 0x8000000000000000
yes
#else
no
#endif
#if (UINTMAX_MAX >> 63) == 1
yes
#else
no
#endif
#if (-1 >> 63) == -1
yes
#else
no
#endif
#if (-1 >> 63u) == -1
yes
#else
no
#endif
#if (1 ? -1 : 0u) > 0
yes
#else
no
#endif
#if (0 ? 0u : -1) > 0
yes
#else
no
#endif
#if (1 ? -1 : (1u / 0)) > 0
yes
#else
no
#endif
#if (0 ? (1u / 0) : -1) > 0
yes
#else
no
#endif
#if 0 && (1u / 0)
yes
#else
no
#endif
#if 1 || (1u % 0)
yes
#else
no
#endif
#if (1 ? 3 : (1 / 0)) == 3
yes
#else
no
#endif
#if (0 ? (1 % 0) : 3) == 3
yes
#else
no
#endif
#if (~0u) == UINTMAX_MAX
yes
#else
no
#endif
#if (-1u) == UINTMAX_MAX
yes
#else
no
#endif
#if (+0u - 1) > 0
yes
#else
no
#endif
#if ((UINTMAX_MAX > 0) - 2) < 0
yes
#else
no
#endif
#if ((!0u) - 2) < 0
yes
#else
no
#endif
#if ((1u && 2u) - 2) < 0
yes
#else
no
#endif
#if ((0u || 2u) - 2) < 0
yes
#else
no
#endif
#if ('A' - 66) < 0
yes
#else
no
#endif
#if (defined(PRESENT) - 2) < 0
yes
#else
no
#endif
#if (UNKNOWN - 1) < 0
yes
#else
no
#endif
#if (0xffffffff - 0x100000000) < 0
yes
#else
no
#endif
#if (UINTMAX_MAX & 1) == 1
yes
#else
no
#endif
#if (UINTMAX_MAX ^ 0) > 0
yes
#else
no
#endif
#if (0 | UINTMAX_MAX) > 0
yes
#else
no
#endif
#if ((0u - 1) + 1) == 0
yes
#else
no
#endif
#if ((0u - 1) * 2) == (UINTMAX_MAX - 1)
yes
#else
no
#endif
#if (1 ? (0 ? -1 : 0u) : -1) == 0
yes
#else
no
#endif
