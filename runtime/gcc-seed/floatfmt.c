/* Original seed-forth implementation; see LICENSE and PRINTF-FLOAT.md.
   Exact printf conversions %e %E %f %F %g %G %a %A of binary64 and x87
   extended80 values. A finite value M*2^E is expanded to every one of its
   decimal digits with base-10^9 integers, then rounded once on those exact
   digits, ties to even: the result glibc gives in round-to-nearest. */
#include <string.h>
#include <seed-float.h>

/* The longest expansion is the smallest extended80 subnormal:
   2^-16445 = 5^16445 / 10^16445 has 11,495 significant digits. */
#define SEED_FMT_LIMBS 1300
#define SEED_FMT_DIGITS (SEED_FMT_LIMBS * 9 + 32)
#define SEED_FMT_BASE 1000000000UL

static unsigned int seed_fmt_limb[SEED_FMT_LIMBS];
static char seed_fmt_digit[SEED_FMT_DIGITS];
static char seed_fmt_copy[SEED_FMT_DIGITS];
static char seed_fmt_hex[24];
static const char seed_fmt_zero[] = "0";

/* Every significant digit of MANTISSA * 2^EXPONENT (MANTISSA nonzero) into
   seed_fmt_digit, without leading or trailing zeros. Returns the digit
   count n; the value is 0.d1...dn * 10^*POINT. */
static int seed_fmt_expand(unsigned long mantissa, int exponent, int *point)
{
    unsigned long carry;
    unsigned long product;
    unsigned int value;
    int used;
    int index;
    int step;
    int scale = 0;
    int count;
    int place;
    while (!(mantissa & 1UL)) {
        mantissa >>= 1;
        exponent++;
    }
    used = 0;
    while (mantissa) {
        seed_fmt_limb[used++] = (unsigned int)(mantissa % SEED_FMT_BASE);
        mantissa /= SEED_FMT_BASE;
    }
    if (exponent > 0) {
        /* Limbs stay below 2^30, so a 32-bit shift fits in 64 bits. */
        while (exponent > 0) {
            step = exponent > 32 ? 32 : exponent;
            carry = 0;
            for (index = 0; index < used; index++) {
                product = ((unsigned long)seed_fmt_limb[index] << step) + carry;
                seed_fmt_limb[index] = (unsigned int)(product % SEED_FMT_BASE);
                carry = product / SEED_FMT_BASE;
            }
            while (carry) {
                seed_fmt_limb[used++] = (unsigned int)(carry % SEED_FMT_BASE);
                carry /= SEED_FMT_BASE;
            }
            exponent -= step;
        }
    } else if (exponent < 0) {
        /* M * 2^-s = M * 5^s / 10^s; 5^13 < 2^31 keeps products in 64 bits. */
        scale = -exponent;
        while (exponent < 0) {
            unsigned long factor = 1;
            step = 0;
            while (step < 13 && exponent < 0) {
                factor *= 5;
                step++;
                exponent++;
            }
            carry = 0;
            for (index = 0; index < used; index++) {
                product = (unsigned long)seed_fmt_limb[index] * factor + carry;
                seed_fmt_limb[index] = (unsigned int)(product % SEED_FMT_BASE);
                carry = product / SEED_FMT_BASE;
            }
            while (carry) {
                seed_fmt_limb[used++] = (unsigned int)(carry % SEED_FMT_BASE);
                carry /= SEED_FMT_BASE;
            }
        }
    }
    count = 0;
    value = seed_fmt_limb[used - 1];
    {
        char top[10];
        int length = 0;
        while (value) {
            top[length++] = (char)('0' + value % 10);
            value /= 10;
        }
        while (length > 0) seed_fmt_digit[count++] = top[--length];
    }
    for (index = used - 2; index >= 0; index--) {
        value = seed_fmt_limb[index];
        for (place = 8; place >= 0; place--) {
            seed_fmt_digit[count + place] = (char)('0' + value % 10);
            value /= 10;
        }
        count += 9;
    }
    *point = count - scale;
    while (count > 1 && seed_fmt_digit[count - 1] == '0') count--;
    return count;
}

/* Round the N digits of 0.D * 10^*POINT to KEEP leading digits, ties to
   even. Returns the new count (0 when the value rounds to zero); trailing
   zeros are removed and a carry out of the first digit raises *POINT. */
static int seed_fmt_round(char *digit, int count, int keep, int *point)
{
    int up;
    int index;
    if (keep >= count) return count;
    if (keep < 0) return 0;
    if (keep == 0) {
        /* The kept digit is an implicit even 0 before d1. */
        if (digit[0] > '5' || (digit[0] == '5' && count > 1)) {
            digit[0] = '1';
            *point = *point + 1;
            return 1;
        }
        return 0;
    }
    if (digit[keep] > '5') up = 1;
    else if (digit[keep] < '5') up = 0;
    else if (keep + 1 < count) up = 1; /* digits never end in 0 */
    else up = (digit[keep - 1] - '0') & 1;
    count = keep;
    if (up) {
        index = keep - 1;
        while (index >= 0 && digit[index] == '9') index--;
        if (index < 0) {
            digit[0] = '1';
            *point = *point + 1;
            return 1;
        }
        digit[index] = (char)(digit[index] + 1);
        count = index + 1;
    }
    while (count > 1 && digit[count - 1] == '0') count--;
    return count;
}

static void seed_fmt_exponent(struct __seed_float_text *out, int letter, int value, int minimum)
{
    char reversed[12];
    int length = 0;
    out->suffix_len = 0;
    out->suffix[out->suffix_len++] = (char)letter;
    out->suffix[out->suffix_len++] = value < 0 ? '-' : '+';
    if (value < 0) value = -value;
    do {
        reversed[length++] = (char)('0' + value % 10);
        value /= 10;
    } while (value);
    while (length < minimum) reversed[length++] = '0';
    while (length > 0) out->suffix[out->suffix_len++] = reversed[--length];
}

/* %e: one digit, PRECISION fraction digits, exponent. */
static void seed_fmt_e(struct __seed_float_text *out, char *digit, int count, int point,
                       int precision, int upper)
{
    int exponent = 0;
    if (count == 0) {
        out->lead = seed_fmt_zero;
        out->lead_len = 1;
        out->trail_zeros = precision;
    } else {
        count = seed_fmt_round(digit, count, precision + 1, &point);
        exponent = point - 1;
        out->lead = digit;
        out->lead_len = 1;
        out->frac = digit + 1;
        out->frac_len = count - 1;
        out->trail_zeros = precision - (count - 1);
    }
    out->point = precision > 0;
    seed_fmt_exponent(out, upper ? 'E' : 'e', exponent, 2);
}

/* %f: all integer digits and PRECISION fraction digits. */
static void seed_fmt_f(struct __seed_float_text *out, char *digit, int count, int point,
                       int precision)
{
    int start;
    out->point = precision > 0;
    if (count > 0) {
        /* point + precision cannot overflow: |point| < 5000. */
        count = seed_fmt_round(digit, count, point + precision, &point);
    }
    if (count == 0) {
        out->lead = seed_fmt_zero;
        out->lead_len = 1;
        out->trail_zeros = precision;
        return;
    }
    if (point <= 0) {
        out->lead = seed_fmt_zero;
        out->lead_len = 1;
        out->frac_zeros = -point;
        start = 0;
    } else {
        out->lead = digit;
        out->lead_len = point < count ? point : count;
        out->lead_zeros = point > count ? point - count : 0;
        start = point;
    }
    if (start < count) {
        out->frac = digit + start;
        out->frac_len = count - start;
    }
    out->trail_zeros = precision - out->frac_zeros - out->frac_len;
}

static void seed_fmt_hex_digits(struct __seed_float_text *out, unsigned long lead,
                                unsigned long fraction, int nibbles, int exponent,
                                int precision, int upper)
{
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int length = 0;
    int index;
    if (precision >= 0 && precision < nibbles) {
        int drop = (nibbles - precision) * 4;
        unsigned long rest;
        unsigned long half;
        int up;
        /* drop <= 60: at most 15 fraction nibbles exist. */
        rest = fraction & ((1UL << drop) - 1);
        half = 1UL << (drop - 1);
        fraction >>= drop;
        up = rest > half || (rest == half && ((precision ? fraction : lead) & 1));
        if (up) {
            fraction++;
            if (fraction >> (precision * 4)) {
                fraction = 0;
                lead++;
            }
        }
        nibbles = precision;
    }
    /* An extended80 leading nibble f that rounds up becomes 0x1p(e+4),
       as glibc prints it; a binary64 leading 1 may become 2. */
    if (lead >= 16) {
        lead = 1;
        exponent += 4;
    }
    seed_fmt_hex[length++] = digits[lead & 15];
    out->lead = seed_fmt_hex;
    out->lead_len = length;
    for (index = nibbles - 1; index >= 0; index--)
        seed_fmt_hex[length++] = digits[(fraction >> (index * 4)) & 15];
    if (precision < 0) {
        while (length > out->lead_len && seed_fmt_hex[length - 1] == '0') length--;
    }
    out->frac = seed_fmt_hex + out->lead_len;
    out->frac_len = length - out->lead_len;
    if (precision > nibbles) out->trail_zeros = precision - nibbles;
    out->point = out->frac_len + out->trail_zeros > 0;
    out->prefix = upper ? "0X" : "0x";
    seed_fmt_exponent(out, upper ? 'P' : 'p', exponent, 1);
}

void __seed_float_format(struct __seed_float_text *out, const unsigned char *bytes,
                         int is_long, int conversion, int precision,
                         int alternate, int plus, int blank)
{
    unsigned long mantissa = 0;
    unsigned long low;
    int biased;
    int negative;
    int exponent;
    int kind; /* 0 zero, 1 finite, 2 infinity, 3 NaN */
    int upper = conversion == 'E' || conversion == 'F' || conversion == 'G' || conversion == 'A';
    int lower = conversion | 32;
    int count = 0;
    int point = 0;
    int index;
    for (index = 7; index >= 0; index--) mantissa = (mantissa << 8) | bytes[index];
    out->sign = 0;
    out->prefix = "";
    out->lead = seed_fmt_zero;
    out->lead_len = 0;
    out->lead_zeros = 0;
    out->point = 0;
    out->frac_zeros = 0;
    out->frac = seed_fmt_zero;
    out->frac_len = 0;
    out->trail_zeros = 0;
    out->suffix_len = 0;
    out->special = 0;
    if (is_long) {
        biased = (bytes[9] & 127) << 8 | bytes[8];
        negative = bytes[9] >> 7;
        if (biased == 32767) {
            /* Pseudo-infinities and pseudo-NaNs (integer bit clear) are
               invalid operands; like glibc, print them as NaN. */
            kind = (mantissa << 1) == 0 && (mantissa >> 63) ? 2 : 3;
        } else if (biased != 0 && !(mantissa >> 63)) {
            kind = 3; /* unnormal: invalid operand */
        } else {
            kind = mantissa ? 1 : 0;
        }
        exponent = (biased ? biased : 1) - 16383 - 63;
    } else {
        biased = (int)((mantissa >> 52) & 2047UL);
        negative = (int)(mantissa >> 63);
        low = mantissa & 0xfffffffffffffUL;
        if (biased == 2047) kind = low ? 3 : 2;
        else kind = biased || low ? 1 : 0;
        mantissa = biased ? low | (1UL << 52) : low;
        exponent = (biased ? biased : 1) - 1075;
    }
    if (negative) out->sign = '-';
    else if (plus) out->sign = '+';
    else if (blank) out->sign = ' ';
    if (kind >= 2) {
        out->special = 1;
        if (kind == 2) out->lead = upper ? "INF" : "inf";
        else out->lead = upper ? "NAN" : "nan";
        out->lead_len = 3;
        return;
    }
    if (lower == 'a') {
        if (kind == 0) {
            seed_fmt_hex_digits(out, 0, 0, 0, 0, precision, upper);
        } else if (is_long) {
            seed_fmt_hex_digits(out, mantissa >> 60, mantissa & 0x0fffffffffffffffUL, 15,
                                exponent + 60, precision, upper);
        } else {
            seed_fmt_hex_digits(out, mantissa >> 52, mantissa & 0xfffffffffffffUL, 13,
                                exponent + 52, precision, upper);
        }
        if (alternate) out->point = 1;
        return;
    }
    if (precision < 0) precision = 6;
    if (kind == 1) count = seed_fmt_expand(mantissa, exponent, &point);
    if (lower == 'e') {
        seed_fmt_e(out, seed_fmt_digit, count, point, precision, upper);
        if (alternate) out->point = 1;
    } else if (lower == 'f') {
        seed_fmt_f(out, seed_fmt_digit, count, point, precision);
        if (alternate) out->point = 1;
    } else {
        int style_exponent = 0;
        if (precision == 0) precision = 1;
        if (count > 0) {
            int rounded_point = point;
            memcpy(seed_fmt_copy, seed_fmt_digit, (unsigned long)count);
            seed_fmt_round(seed_fmt_copy, count, precision, &rounded_point);
            style_exponent = rounded_point - 1;
        }
        if (style_exponent < precision && style_exponent >= -4)
            seed_fmt_f(out, seed_fmt_digit, count, point, precision - 1 - style_exponent);
        else if (alternate && count > 0 && point == precision && style_exponent == precision)
            /* glibc quirk, reproduced for byte equality: when the exact
               exponent selects style f with no fraction digits and rounding
               carries into one more integer digit, glibc prints style e
               with that zero fraction-digit count ("%#g" of 999999.5 is
               "1.e+06", not "1.00000e+06"). Without '#' both agree. */
            seed_fmt_e(out, seed_fmt_digit, count, point, 0, upper);
        else
            seed_fmt_e(out, seed_fmt_digit, count, point, precision - 1, upper);
        if (alternate) {
            out->point = 1;
        } else {
            out->trail_zeros = 0;
            if (out->frac_len == 0) out->frac_zeros = 0;
            out->point = out->frac_len > 0;
        }
    }
}
