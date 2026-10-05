/* Original seed-forth implementation; see LICENSE and DECIMAL-INPUT.md.
   Correctly rounded decimal-to-binary64 conversion for atof. */
#include <stdlib.h>
#include <string.h>

/* Little-endian base-2^32 natural numbers, large enough for every value the
   range checks admit: 801 digits scaled by up to 10^1125, shifted 64 bits. */
#define SEED_DECIMAL_LIMBS 160
#define SEED_DECIMAL_DIGITS 800

struct seed_big {
    int used;
    unsigned int limb[SEED_DECIMAL_LIMBS];
};

static void seed_big_small(struct seed_big *big, unsigned int value)
{
    big->used = value != 0;
    big->limb[0] = value;
}

static void seed_big_mul_add(struct seed_big *big, unsigned int factor, unsigned int addend)
{
    unsigned long carry = addend;
    int index;
    for (index = 0; index < big->used; index++) {
        carry += (unsigned long)big->limb[index] * factor;
        big->limb[index] = (unsigned int)carry;
        carry >>= 32;
    }
    if (carry) big->limb[big->used++] = (unsigned int)carry;
}

static void seed_big_pow10(struct seed_big *big, long count)
{
    while (count >= 9) {
        seed_big_mul_add(big, 1000000000U, 0);
        count -= 9;
    }
    while (count-- > 0) seed_big_mul_add(big, 10U, 0);
}

static void seed_big_shift_left(struct seed_big *big, long bits)
{
    long words = bits / 32;
    int rest = (int)(bits % 32);
    int index;
    if (big->used == 0) return;
    if (rest) {
        unsigned int carry = 0;
        for (index = 0; index < big->used; index++) {
            unsigned int next = big->limb[index] >> (32 - rest);
            big->limb[index] = (big->limb[index] << rest) | carry;
            carry = next;
        }
        if (carry) big->limb[big->used++] = carry;
    }
    if (words) {
        for (index = big->used - 1; index >= 0; index--)
            big->limb[index + words] = big->limb[index];
        for (index = 0; index < words; index++) big->limb[index] = 0;
        big->used += (int)words;
    }
}

static void seed_big_shift_right1(struct seed_big *big)
{
    int index;
    for (index = 0; index < big->used; index++) {
        big->limb[index] >>= 1;
        if (index + 1 < big->used) big->limb[index] |= big->limb[index + 1] << 31;
    }
    while (big->used > 0 && big->limb[big->used - 1] == 0) big->used--;
}

static long seed_big_bits(const struct seed_big *big)
{
    unsigned int top;
    long bits;
    if (big->used == 0) return 0;
    top = big->limb[big->used - 1];
    bits = (long)(big->used - 1) * 32;
    while (top) {
        bits++;
        top >>= 1;
    }
    return bits;
}

static int seed_big_compare(const struct seed_big *left, const struct seed_big *right)
{
    int index;
    if (left->used != right->used) return left->used < right->used ? -1 : 1;
    for (index = left->used - 1; index >= 0; index--)
        if (left->limb[index] != right->limb[index])
            return left->limb[index] < right->limb[index] ? -1 : 1;
    return 0;
}

/* left -= right, where left >= right. */
static void seed_big_subtract(struct seed_big *left, const struct seed_big *right)
{
    unsigned long borrow = 0;
    int index;
    for (index = 0; index < left->used; index++) {
        unsigned long part = index < right->used ? right->limb[index] : 0;
        unsigned long value = (unsigned long)left->limb[index];
        unsigned long take = part + borrow;
        left->limb[index] = (unsigned int)(value - take);
        borrow = value < take;
    }
    while (left->used > 0 && left->limb[left->used - 1] == 0) left->used--;
}

static double seed_decimal_bits(unsigned long bits)
{
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static int seed_decimal_lower(int c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* Case-insensitive prefix test against a lowercase WORD. */
static int seed_decimal_word(const char *text, const char *word)
{
    while (*word) {
        if (seed_decimal_lower((unsigned char)*text) != *word) return 0;
        text++;
        word++;
    }
    return 1;
}

/* Round the exact value num/den (both nonzero) to binary64. */
static unsigned long seed_decimal_round(struct seed_big *num, struct seed_big *den)
{
    unsigned long quotient = 0;
    unsigned long mantissa;
    unsigned long remainder;
    unsigned long half;
    long scale;
    long exponent;
    int bits;
    int shift;
    int sticky;
    int index;
    /* num/den lies in [2^(b-1), 2^(b+1)) for b = bits(num) - bits(den);
       scaling by 2^scale puts the quotient in [2^62, 2^64). */
    scale = 63 - (seed_big_bits(num) - seed_big_bits(den));
    if (scale > 0) seed_big_shift_left(num, scale);
    else if (scale < 0) seed_big_shift_left(den, -scale);
    seed_big_shift_left(den, 63);
    for (index = 63; index >= 0; index--) {
        if (seed_big_compare(num, den) >= 0) {
            seed_big_subtract(num, den);
            quotient |= 1UL << index;
        }
        seed_big_shift_right1(den);
    }
    sticky = num->used != 0;
    bits = quotient >> 63 ? 64 : 63;
    /* value = (quotient + fraction) * 2^-scale, in [2^exponent, 2^(exponent+1)). */
    exponent = bits - 1 - scale;
    if (exponent > 1023) return 0x7ff0000000000000UL;
    shift = bits - 53;
    if (exponent < -1022) {
        if (-1022 - exponent > bits) return 0;
        shift += (int)(-1022 - exponent);
    }
    if (shift >= 64) {
        /* Only the half-way comparison remains: quotient < 2^63 <= half. */
        half = 1UL << 63;
        if (shift > 64 || quotient < half || (quotient == half && !sticky)) return 0;
        return 1;
    }
    mantissa = quotient >> shift;
    remainder = quotient & ((1UL << shift) - 1);
    half = 1UL << (shift - 1);
    if (remainder > half || (remainder == half && (sticky || (mantissa & 1))))
        mantissa++;
    if (exponent < -1022) {
        /* Subnormal; rounding up to 2^52 yields the smallest normal bits. */
        return mantissa;
    }
    if (mantissa >> 53) {
        mantissa >>= 1;
        exponent++;
        if (exponent > 1023) return 0x7ff0000000000000UL;
    }
    return ((unsigned long)(exponent + 1023) << 52) | (mantissa & 0xfffffffffffffUL);
}

double atof(const char *text)
{
    static struct seed_big num;
    static struct seed_big den;
    char digits[SEED_DECIMAL_DIGITS + 1];
    unsigned long sign = 0;
    unsigned long bits;
    long scale = 0;
    long exponent = 0;
    int count = 0;
    int seen = 0;
    int sticky = 0;
    int index;
    while (*text == ' ' || (*text >= '\t' && *text <= '\r')) text++;
    if (*text == '+' || *text == '-') {
        if (*text == '-') sign = 1UL << 63;
        text++;
    }
    if (seed_decimal_word(text, "inf")) return seed_decimal_bits(sign | 0x7ff0000000000000UL);
    if (seed_decimal_word(text, "nan")) return seed_decimal_bits(sign | 0x7ff8000000000000UL);
    for (; *text >= '0' && *text <= '9'; text++) {
        seen = 1;
        if (count == 0 && *text == '0') continue;
        if (count < SEED_DECIMAL_DIGITS) digits[count++] = *text;
        else {
            scale++;
            if (*text != '0') sticky = 1;
        }
    }
    if (*text == '.') {
        for (text++; *text >= '0' && *text <= '9'; text++) {
            seen = 1;
            if (count == 0 && *text == '0') { scale--; continue; }
            if (count < SEED_DECIMAL_DIGITS) {
                digits[count++] = *text;
                scale--;
            } else if (*text != '0') sticky = 1;
        }
    }
    if (!seen) return 0.0;
    if ((*text == 'e' || *text == 'E')
        && ((text[1] >= '0' && text[1] <= '9')
            || ((text[1] == '+' || text[1] == '-') && text[2] >= '0' && text[2] <= '9'))) {
        int negative = text[1] == '-';
        text += text[1] == '+' || text[1] == '-' ? 2 : 1;
        for (; *text >= '0' && *text <= '9'; text++)
            if (exponent < 1000000000L) exponent = exponent * 10 + (*text - '0');
        if (negative) exponent = -exponent;
    }
    /* Trailing zeros are dropped only when nothing nonzero follows them. */
    while (!sticky && count > 0 && digits[count - 1] == '0') {
        count--;
        scale++;
    }
    if (count == 0) return seed_decimal_bits(sign);
    /* Dropped nonzero digits only break ties: one more nonzero digit beyond
       every half-way point's 768 significant digits has the same effect. */
    if (sticky) {
        digits[count++] = '1';
        scale--;
    }
    scale += exponent;
    /* value < 10^(count + scale) and >= 10^(count + scale - 1). */
    if (count + scale > 310) return seed_decimal_bits(sign | 0x7ff0000000000000UL);
    if (count + scale < -324) return seed_decimal_bits(sign);
    seed_big_small(&num, 0);
    for (index = 0; index < count; index++) {
        if (num.used == 0) seed_big_small(&num, (unsigned int)(digits[index] - '0'));
        else seed_big_mul_add(&num, 10U, (unsigned int)(digits[index] - '0'));
    }
    seed_big_small(&den, 1);
    if (scale > 0) seed_big_pow10(&num, scale);
    else seed_big_pow10(&den, -scale);
    bits = seed_decimal_round(&num, &den);
    return seed_decimal_bits(sign | bits);
}
