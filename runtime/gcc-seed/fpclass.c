/* Original seed-forth implementation, MIT license (see LICENSE).
 * The binary64 operations a C program may use without -lm: classification
 * helpers behind the math.h macros, and the exact frexp, ldexp, scalbn, modf
 * and copysign that glibc also exports from libc. Every result is exact
 * except ldexp/scalbn, which round once (ties to even) into the subnormal
 * range. Assumes IEEE binary64 and LP64 unsigned long. See MATH.md.
 */
#include <math.h>
#include <errno.h>

union seed_fp_bits { double number; unsigned long bits; };

#define SEED_FP_SIGN 0x8000000000000000UL
#define SEED_FP_ABS 0x7fffffffffffffffUL
#define SEED_FP_INF 0x7ff0000000000000UL
#define SEED_FP_FRAC 0x000fffffffffffffUL
#define SEED_FP_HIDDEN 0x0010000000000000UL

static unsigned long seed_fp_to_bits(double x)
{
    union seed_fp_bits value;
    value.number = x;
    return value.bits;
}

static double seed_fp_from_bits(unsigned long bits)
{
    union seed_fp_bits value;
    value.bits = bits;
    return value.number;
}

int __seed_fpclassify(double x)
{
    unsigned long magnitude = seed_fp_to_bits(x) & SEED_FP_ABS;
    if (magnitude > SEED_FP_INF) return FP_NAN;
    if (magnitude == SEED_FP_INF) return FP_INFINITE;
    if (magnitude == 0) return FP_ZERO;
    if (magnitude < SEED_FP_HIDDEN) return FP_SUBNORMAL;
    return FP_NORMAL;
}

int __seed_signbit(double x)
{
    return (seed_fp_to_bits(x) & SEED_FP_SIGN) != 0;
}

int __seed_isunordered(double x, double y)
{
    return (seed_fp_to_bits(x) & SEED_FP_ABS) > SEED_FP_INF
        || (seed_fp_to_bits(y) & SEED_FP_ABS) > SEED_FP_INF;
}

int __seed_islessgreater(double x, double y)
{
    return x < y || x > y;
}

double copysign(double x, double y)
{
    return seed_fp_from_bits((seed_fp_to_bits(x) & SEED_FP_ABS)
                             | (seed_fp_to_bits(y) & SEED_FP_SIGN));
}

double frexp(double x, int *exponent)
{
    unsigned long bits = seed_fp_to_bits(x);
    int field = (int)((bits >> 52) & 2047);
    int adjust = 0;
    if (field == 2047 || (bits & SEED_FP_ABS) == 0) {
        *exponent = 0;
        return x + x;
    }
    if (field == 0) {
        /* Multiplication by 2^54 normalizes every subnormal exactly. */
        bits = seed_fp_to_bits(x * 18014398509481984.0);
        field = (int)((bits >> 52) & 2047);
        adjust = -54;
    }
    *exponent = field - 1022 + adjust;
    return seed_fp_from_bits((bits & ~(2047UL << 52)) | (1022UL << 52));
}

double scalbn(double x, int n)
{
    unsigned long bits = seed_fp_to_bits(x);
    unsigned long sign = bits & SEED_FP_SIGN;
    unsigned long mantissa;
    unsigned long dropped;
    unsigned long half;
    int field = (int)((bits >> 52) & 2047);
    int exponent;
    int shift;
    if (field == 2047 || (bits & SEED_FP_ABS) == 0) return x + x;
    mantissa = bits & SEED_FP_FRAC;
    if (field == 0) {
        exponent = -1074;
        while (mantissa < SEED_FP_HIDDEN) {
            mantissa <<= 1;
            exponent--;
        }
    } else {
        mantissa |= SEED_FP_HIDDEN;
        exponent = field - 1075;
    }
    /* x = mantissa * 2^exponent with 2^52 <= mantissa < 2^53. Clamping n
     * keeps the int sum exact without changing any result. */
    if (n > 4200) n = 4200;
    if (n < -4200) n = -4200;
    exponent += n;
    if (exponent > 1023 - 52) {
        errno = ERANGE;
        return seed_fp_from_bits(sign | SEED_FP_INF);
    }
    if (exponent >= -1074) {
        return seed_fp_from_bits(sign | ((unsigned long)(exponent + 1075) << 52)
                                 | (mantissa & SEED_FP_FRAC));
    }
    shift = -1074 - exponent;
    if (shift > 54) {
        errno = ERANGE;
        return seed_fp_from_bits(sign);
    }
    dropped = mantissa & ((1UL << shift) - 1);
    half = 1UL << (shift - 1);
    mantissa >>= shift;
    if (dropped > half || (dropped == half && (mantissa & 1))) mantissa++;
    if (mantissa == 0) errno = ERANGE;
    /* A carry to 2^52 becomes the smallest normal encoding. */
    return seed_fp_from_bits(sign | mantissa);
}

double ldexp(double x, int n)
{
    return scalbn(x, n);
}

double modf(double x, double *integral)
{
    unsigned long bits = seed_fp_to_bits(x);
    unsigned long fraction;
    int exponent = (int)((bits >> 52) & 2047) - 1023;
    if (exponent == 1024) {
        if ((bits & SEED_FP_ABS) > SEED_FP_INF) {
            *integral = x + x;
            return x + x;
        }
        *integral = x;
        return seed_fp_from_bits(bits & SEED_FP_SIGN);
    }
    if (exponent >= 52) {
        *integral = x;
        return seed_fp_from_bits(bits & SEED_FP_SIGN);
    }
    if (exponent < 0) {
        *integral = seed_fp_from_bits(bits & SEED_FP_SIGN);
        return x;
    }
    fraction = SEED_FP_FRAC >> exponent;
    if ((bits & fraction) == 0) {
        *integral = x;
        return seed_fp_from_bits(bits & SEED_FP_SIGN);
    }
    *integral = seed_fp_from_bits(bits & ~fraction);
    return x - *integral;
}
