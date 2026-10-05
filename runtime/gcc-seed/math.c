/* Original seed-forth implementation, MIT license (see LICENSE).
 * Only the exp/log surface measured in GCC 4.0.4 genautomata.c.
 * Assumes IEEE binary64, LP64 unsigned long, round-to-nearest/ties-even,
 * gradual underflow, and no contraction or excess precision. See MATH.md.
 */
#include <math.h>
#include <errno.h>

/* ln(2) rounded to binary64, then its low 21 fraction bits cleared;
 * ln(2)-that value rounded separately. The high product with |k|<=1075
 * is exact. Constants and polynomial remainders are independently derived
 * in tests/gcc/math-oracle-check.py, not borrowed from a libm. */
#define SEED_LN2_HI 6.93147180369123816490e-01
#define SEED_LN2_LO 1.90821492927058770002e-10
#define SEED_INV_LN2 1.44269504088896338700e+00

/* Reading the other union member is the specified AMD64 representation
 * operation of this bounded runtime, not an aliasing pointer cast. */
union seed_math_bits { double number; unsigned long bits; };

double log(double x)
{
    union seed_math_bits value;
    unsigned long magnitude;
    int exponent;
    int divisor;
    double z;
    double square;
    double term;
    double series;
    value.number = x;
    magnitude = value.bits & 0x7fffffffffffffffUL;
    if (magnitude > 0x7ff0000000000000UL) return x + x;
    if (magnitude == 0) {
        errno = ERANGE;
        value.bits = 0xfff0000000000000UL;
        return value.number;
    }
    if (value.bits & 0x8000000000000000UL) {
        errno = EDOM;
        value.bits = 0x7ff8000000000000UL;
        return value.number;
    }
    if (magnitude == 0x7ff0000000000000UL) return x;
    exponent = 0;
    if (magnitude < 0x0010000000000000UL) {
        /* Multiplication by 2^52 normalizes every positive subnormal. */
        value.number = x * 4503599627370496.0;
        exponent = -52;
    }
    exponent += (int)((value.bits >> 52) & 2047UL) - 1023;
    value.bits = (value.bits & 0x000fffffffffffffUL) | 0x3ff0000000000000UL;
    /* This exact 1.5 boundary keeps z in [-1/7,1/5). No sqrt constant. */
    if (value.number >= 1.5) {
        value.number = value.number * 0.5;
        exponent++;
    }
    z = (value.number - 1.0) / (value.number + 1.0);
    square = z * z;
    term = z;
    series = z;
    for (divisor = 3; divisor <= 33; divisor += 2) {
        term = term * square;
        series = series + term / divisor;
    }
    return exponent * SEED_LN2_HI + (2.0 * series + exponent * SEED_LN2_LO);
}

double exp(double x)
{
    union seed_math_bits value;
    union seed_math_bits scale;
    unsigned long magnitude;
    int exponent;
    int divisor;
    double reduced;
    double polynomial;
    value.number = x;
    magnitude = value.bits & 0x7fffffffffffffffUL;
    if (magnitude > 0x7ff0000000000000UL) return x + x;
    if (magnitude == 0x7ff0000000000000UL) {
        if (value.bits & 0x8000000000000000UL) return 0.0;
        return x;
    }
    /* Adjacent representable arguments straddle the true range limits.
     * These are rounded ln(DBL_MAX) and -1075*ln(2), derived in the test. */
    if (x > 7.09782712893383973096e+02) {
        errno = ERANGE;
        value.bits = 0x7ff0000000000000UL;
        return value.number;
    }
    if (x <= -7.45133219101941222107e+02) {
        errno = ERANGE;
        return 0.0;
    }
    if (x < 0.0) exponent = (int)(x * SEED_INV_LN2 - 0.5);
    else exponent = (int)(x * SEED_INV_LN2 + 0.5);
    reduced = (x - exponent * SEED_LN2_HI) - exponent * SEED_LN2_LO;
    /* Horner form of sum(r^j/j!,j=0..18). The recurrence uses only
     * exact integer divisors and has an explicitly bounded tail. */
    polynomial = 1.0;
    for (divisor = 18; divisor > 0; divisor--)
        polynomial = 1.0 + reduced * polynomial / divisor;
    if (exponent > 1023) {
        scale.bits = 0x7fe0000000000000UL;
        value.number = (polynomial * 2.0) * scale.number;
    } else if (exponent < -1022) {
        /* Avoid an underflowing intermediate scale and perform the final
         * rounding into the subnormal lattice only at the last multiply. */
        scale.bits = (unsigned long)(exponent + 1077) << 52;
        value.number = (polynomial * scale.number) * 5.55111512312578270212e-17;
    } else {
        scale.bits = (unsigned long)(exponent + 1023) << 52;
        value.number = polynomial * scale.number;
    }
    if ((value.bits & 0x7ff0000000000000UL) == 0
        || value.bits == 0x7ff0000000000000UL)
        errno = ERANGE;
    return value.number;
}
