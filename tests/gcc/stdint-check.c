/* Prints <stdint.h>/<inttypes.h> facts; the Forth build (runtime headers)
   must match host GCC with host glibc headers byte for byte. Host GCC also
   compiles this file against the runtime headers, where the pointer
   initializers prove exact type identity with the expected C types. */
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

#define TYPE(t) show(#t, (int)sizeof(t), (t)-1 > 0 ? 'u' : 's', 0L, 0UL)
#define VALUE(x) show(#x, (int)sizeof(x), (x) - (x) - 1 > 0 ? 'u' : 's', (long)(x), (unsigned long)(x))
#define SAME(t, u) { t *pointer = (u *)0; if (pointer) return 99; }

#if INT64_MAX != 9223372036854775807L || UINT8_MAX != 255 || INT8_MIN != -128
#error integer limit preprocessing
#endif
#if UINTMAX_MAX != 18446744073709551615UL || SIZE_MAX != UINT64_MAX || INTMAX_C(1) << 40 != 1099511627776L
#error unsigned limit preprocessing
#endif
#if !defined(INT_FAST16_MAX) || INT_FAST16_MAX != INT64_MAX || INT32_MIN >= 0 || UINT32_MAX < 0
#error fast limit preprocessing
#endif

static int anchor;

static void show(const char *name, int size, char sign, long value, unsigned long bits)
{
    printf("%s size=%d %c value=%ld bits=%lu\n", name, size, sign, value, bits);
}

int main(void)
{
    SAME(int8_t, signed char) SAME(int16_t, short) SAME(int32_t, int) SAME(int64_t, long)
    SAME(uint8_t, unsigned char) SAME(uint16_t, unsigned short)
    SAME(uint32_t, unsigned int) SAME(uint64_t, unsigned long)
    SAME(int_least8_t, signed char) SAME(int_least16_t, short)
    SAME(int_least32_t, int) SAME(int_least64_t, long)
    SAME(uint_least8_t, unsigned char) SAME(uint_least16_t, unsigned short)
    SAME(uint_least32_t, unsigned int) SAME(uint_least64_t, unsigned long)
    SAME(int_fast8_t, signed char) SAME(int_fast16_t, long)
    SAME(int_fast32_t, long) SAME(int_fast64_t, long)
    SAME(uint_fast8_t, unsigned char) SAME(uint_fast16_t, unsigned long)
    SAME(uint_fast32_t, unsigned long) SAME(uint_fast64_t, unsigned long)
    SAME(intptr_t, long) SAME(uintptr_t, unsigned long)
    SAME(intmax_t, long) SAME(uintmax_t, unsigned long)
    TYPE(int8_t); TYPE(int16_t); TYPE(int32_t); TYPE(int64_t);
    TYPE(uint8_t); TYPE(uint16_t); TYPE(uint32_t); TYPE(uint64_t);
    TYPE(int_least8_t); TYPE(int_least16_t); TYPE(int_least32_t); TYPE(int_least64_t);
    TYPE(uint_least8_t); TYPE(uint_least16_t); TYPE(uint_least32_t); TYPE(uint_least64_t);
    TYPE(int_fast8_t); TYPE(int_fast16_t); TYPE(int_fast32_t); TYPE(int_fast64_t);
    TYPE(uint_fast8_t); TYPE(uint_fast16_t); TYPE(uint_fast32_t); TYPE(uint_fast64_t);
    TYPE(intptr_t); TYPE(uintptr_t); TYPE(intmax_t); TYPE(uintmax_t);
    VALUE(INT8_MIN); VALUE(INT16_MIN); VALUE(INT32_MIN); VALUE(INT64_MIN);
    VALUE(INT8_MAX); VALUE(INT16_MAX); VALUE(INT32_MAX); VALUE(INT64_MAX);
    VALUE(UINT8_MAX); VALUE(UINT16_MAX); VALUE(UINT32_MAX); VALUE(UINT64_MAX);
    VALUE(INT_LEAST8_MIN); VALUE(INT_LEAST16_MIN); VALUE(INT_LEAST32_MIN); VALUE(INT_LEAST64_MIN);
    VALUE(INT_LEAST8_MAX); VALUE(INT_LEAST16_MAX); VALUE(INT_LEAST32_MAX); VALUE(INT_LEAST64_MAX);
    VALUE(UINT_LEAST8_MAX); VALUE(UINT_LEAST16_MAX); VALUE(UINT_LEAST32_MAX); VALUE(UINT_LEAST64_MAX);
    VALUE(INT_FAST8_MIN); VALUE(INT_FAST16_MIN); VALUE(INT_FAST32_MIN); VALUE(INT_FAST64_MIN);
    VALUE(INT_FAST8_MAX); VALUE(INT_FAST16_MAX); VALUE(INT_FAST32_MAX); VALUE(INT_FAST64_MAX);
    VALUE(UINT_FAST8_MAX); VALUE(UINT_FAST16_MAX); VALUE(UINT_FAST32_MAX); VALUE(UINT_FAST64_MAX);
    VALUE(INTPTR_MIN); VALUE(INTPTR_MAX); VALUE(UINTPTR_MAX);
    VALUE(INTMAX_MIN); VALUE(INTMAX_MAX); VALUE(UINTMAX_MAX);
    VALUE(PTRDIFF_MIN); VALUE(PTRDIFF_MAX); VALUE(SIZE_MAX);
    VALUE(SIG_ATOMIC_MIN); VALUE(SIG_ATOMIC_MAX);
    VALUE(WCHAR_MIN); VALUE(WCHAR_MAX); VALUE(WINT_MIN); VALUE(WINT_MAX);
    VALUE(INT8_C(-128)); VALUE(INT16_C(-32768)); VALUE(INT32_C(2147483647));
    VALUE(INT64_C(-9223372036854775807)); VALUE(INT64_C(5));
    VALUE(UINT8_C(255)); VALUE(UINT16_C(65535)); VALUE(UINT32_C(4294967295));
    VALUE(UINT64_C(18446744073709551615)); VALUE(UINT64_C(1));
    VALUE(INTMAX_C(-9223372036854775807)); VALUE(UINTMAX_C(18446744073709551615));
    VALUE(INT64_C(1) << 62); VALUE(UINT64_C(1) << 63); VALUE(UINT32_C(0) - 1);
    VALUE(sizeof(void *) == sizeof(intptr_t)); VALUE((uintptr_t)(void *)&anchor != 0);
    return 0;
}
