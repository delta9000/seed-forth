/* Original seed-forth implementation; see LICENSE and DECIMAL-INPUT.md.
   Correctly rounded strtod, strtof, strtold and atof: C99 decimal and
   hexadecimal syntax, infinities and NaNs, end pointer and ERANGE. */
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* Little-endian base-2^32 natural numbers. The largest operand is an
   extended80 denominator: 11,600 kept digits plus 4,952 more powers of ten
   (about 55,300 bits) and a 64-bit scaling margin. */
#define SEED_BIG_LIMBS 1800

struct seed_big {
    int used;
    unsigned int limb[SEED_BIG_LIMBS];
};

static struct seed_big seed_num;
static struct seed_big seed_den;
static struct seed_big seed_tmp;

/* One binary format: P significand bits (with the integer bit), normal
   exponents EMIN..EMAX, and the decimal-digit and decimal-exponent limits
   past which a value is certainly infinite or zero. */
struct seed_format {
    int precision;
    int emin;
    int emax;
    int keep_digits;
    long ten_max;
    long ten_min;
};

static const struct seed_format seed_binary32 = { 24, -126, 127, 120, 40, -47 };
static const struct seed_format seed_binary64 = { 53, -1022, 1023, 800, 310, -326 };
static const struct seed_format seed_extended = { 64, -16382, 16383, 11600, 4934, -4953 };

/* The rounded result: kind 0 zero, 1 finite, 2 infinity; a finite value
   is mantissa * 2^(exponent - precision + 1) with exponent >= emin for a
   normal mantissa (top bit set), or a subnormal mantissa at emin. */
struct seed_result {
    int kind;
    unsigned long mantissa;
    long exponent;
    int range_error;
};

static void seed_big_set(struct seed_big *big, unsigned int value)
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
    if (big->used == 0 || bits <= 0) return;
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

static void seed_big_copy(struct seed_big *to, const struct seed_big *from)
{
    to->used = from->used;
    memcpy(to->limb, from->limb, (size_t)from->used * sizeof(unsigned int));
}

/* Compare num * 2^shift with den, without changing either. */
static int seed_big_compare_shifted(long shift)
{
    seed_big_copy(&seed_tmp, shift >= 0 ? &seed_num : &seed_den);
    seed_big_shift_left(&seed_tmp, shift >= 0 ? shift : -shift);
    return shift >= 0 ? seed_big_compare(&seed_tmp, &seed_den)
                      : seed_big_compare(&seed_num, &seed_tmp);
}

/* Round the exact positive value seed_num / seed_den to FORMAT, ties to
   even. Both numbers are consumed. ERANGE is reported for overflow, and
   for an inexact result that is tiny after rounding (glibc's rule). */
static void seed_round(const struct seed_format *format, struct seed_result *result)
{
    long estimate = seed_big_bits(&seed_num) - seed_big_bits(&seed_den);
    long exponent;
    long scale;
    long index;
    int precision;
    int up;
    int half;
    int inexact;
    unsigned long quotient = 0;
    result->range_error = 0;
    /* num/den lies in [2^(estimate-1), 2^(estimate+1)). */
    exponent = seed_big_compare_shifted(-estimate) >= 0 ? estimate : estimate - 1;
    if (exponent > format->emax) {
        result->kind = 2;
        result->range_error = 1;
        return;
    }
    precision = format->precision;
    if (exponent < format->emin) {
        long available = (long)precision - (format->emin - exponent);
        if (available <= 0) {
            /* Below the smallest subnormal's half, or in [half, smallest):
               only a value above that half rounds up to the smallest. */
            result->range_error = 1;
            result->exponent = format->emin;
            if (available == 0 && seed_big_compare_shifted(-exponent) > 0) {
                result->kind = 1;
                result->mantissa = 1;
            } else {
                result->kind = 0;
            }
            return;
        }
        precision = (int)available;
    }
    /* Scale so that num/den is in [2^(precision-1), 2^precision). */
    scale = precision - 1 - exponent;
    if (scale > 0) seed_big_shift_left(&seed_num, scale);
    else seed_big_shift_left(&seed_den, -scale);
    seed_big_shift_left(&seed_den, precision - 1);
    for (index = precision - 1; ; index--) {
        if (seed_big_compare(&seed_num, &seed_den) >= 0) {
            seed_big_subtract(&seed_num, &seed_den);
            quotient |= 1UL << index;
        }
        if (index == 0) break;
        seed_big_shift_right1(&seed_den);
    }
    /* Shifting den back right was exact: it had precision-1 zero bits.
       Compare twice the remainder with den: round up above one half. */
    inexact = seed_num.used != 0;
    seed_big_shift_left(&seed_num, 1);
    half = seed_big_compare(&seed_num, &seed_den);
    up = half > 0 || (half == 0 && (quotient & 1));
    if (inexact && exponent < format->emin) result->range_error = 1;
    if (inexact && exponent == format->emin - 1 && precision == format->precision - 1) {
        /* Tiny after rounding unless rounding to the full precision with an
           unbounded exponent reaches 2^emin: quotient all ones and the
           remainder at least three quarters of den. */
        if (quotient == (1UL << precision) - 1) {
            seed_big_shift_left(&seed_num, 1);
            seed_big_copy(&seed_tmp, &seed_den);
            seed_big_mul_add(&seed_tmp, 3, 0);
            if (seed_big_compare(&seed_num, &seed_tmp) >= 0) result->range_error = 0;
        }
    }
    if (up) {
        quotient++;
        /* A carry into the next binade gives 2^precision; at precision 64
           the sum wraps to zero instead. */
        if (precision == 64 ? quotient == 0 : (quotient >> precision) != 0) {
            exponent++;
            if (precision == format->precision) quotient = 1UL << (precision - 1);
        }
    }
    if (exponent > format->emax) {
        result->kind = 2;
        result->range_error = 1;
        return;
    }
    result->kind = 1;
    result->mantissa = quotient;
    result->exponent = exponent < format->emin ? format->emin : exponent;
    /* A subnormal quotient keeps its value scale: mantissa * 2^(emin-P+1). */
}

static int seed_lower(int c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static int seed_word(const char *text, const char *word)
{
    while (*word) {
        if (seed_lower((unsigned char)*text) != *word) return 0;
        text++;
        word++;
    }
    return 1;
}

static int seed_hex_value(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    c = seed_lower(c);
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

/* Parsed text: kind 0 zero, 1 finite (seed_num/seed_den hold the value),
   2 infinity, 3 NaN with payload; end is past the consumed text or NULL
   when there is no conversion. */
struct seed_parse {
    int kind;
    int negative;
    unsigned long payload;
    int has_payload;
    const char *end;
};

/* The exponent text saturates far beyond every format's range. */
static const char *seed_exponent(const char *text, long *value)
{
    int negative = 0;
    const char *start = text;
    *value = 0;
    if (*text == '+' || *text == '-') {
        negative = *text == '-';
        text++;
    }
    if (*text < '0' || *text > '9') return start;
    for (; *text >= '0' && *text <= '9'; text++)
        if (*value < 100000000L) *value = *value * 10 + (*text - '0');
    if (negative) *value = -*value;
    return text;
}

static void seed_parse_nan(const char *text, struct seed_parse *parsed)
{
    const char *cursor = text + 3;
    parsed->kind = 3;
    parsed->end = cursor;
    if (*cursor != '(') return;
    cursor++;
    while ((*cursor >= '0' && *cursor <= '9') || (*cursor >= 'a' && *cursor <= 'z')
           || (*cursor >= 'A' && *cursor <= 'Z') || *cursor == '_')
        cursor++;
    if (*cursor != ')') return;
    parsed->end = cursor + 1;
    {
        /* Like glibc, a sequence that is wholly one strtoull(base 0)
           number gives the payload; any other sequence gives none. */
        char *number_end;
        int saved = errno;
        unsigned long payload = strtoul(text + 4, &number_end, 0);
        errno = saved;
        if (number_end == cursor) {
            parsed->payload = payload;
            parsed->has_payload = 1;
        }
    }
}

static void seed_parse_number(const char *text, const struct seed_format *format,
                              struct seed_parse *parsed)
{
    const char *start = text;
    long exponent = 0;
    long scale = 0;
    long count = 0;
    int sticky = 0;
    int seen = 0;
    int digit;
    unsigned int chunk = 0;
    int chunk_size = 0;
    parsed->kind = 0;
    parsed->negative = 0;
    parsed->has_payload = 0;
    parsed->payload = 0;
    parsed->end = NULL;
    while (*text == ' ' || (*text >= '\t' && *text <= '\r')) text++;
    if (*text == '+' || *text == '-') {
        parsed->negative = *text == '-';
        text++;
    }
    if (seed_word(text, "inf")) {
        parsed->kind = 2;
        parsed->end = text + (seed_word(text, "infinity") ? 8 : 3);
        return;
    }
    if (seed_word(text, "nan")) {
        seed_parse_nan(text, parsed);
        return;
    }
    seed_big_set(&seed_num, 0);
    if (text[0] == '0' && (text[1] == 'x' || text[1] == 'X')
        && (seed_hex_value((unsigned char)text[2]) >= 0
            || (text[2] == '.' && seed_hex_value((unsigned char)text[3]) >= 0))) {
        /* Hexadecimal: up to 40 significant hex digits (160 bits) are
           kept; a further nonzero digit becomes a sticky low bit. */
        long binary = 0;
        int point = 0;
        text += 2;
        for (;; text++) {
            if (*text == '.' && !point) {
                point = 1;
                continue;
            }
            digit = seed_hex_value((unsigned char)*text);
            if (digit < 0) break;
            if (count == 0 && digit == 0) {
                if (point) binary -= 4;
                continue;
            }
            if (count < 40) {
                if (seed_num.used == 0) seed_big_set(&seed_num, (unsigned int)digit);
                else seed_big_mul_add(&seed_num, 16, (unsigned int)digit);
                count++;
                if (point) binary -= 4;
            } else {
                if (digit) sticky = 1;
                if (!point) binary += 4;
            }
        }
        if (*text == 'p' || *text == 'P') {
            const char *after = seed_exponent(text + 1, &exponent);
            if (after != text + 1) text = after;
            else exponent = 0;
        }
        parsed->end = text;
        if (count == 0) return;
        if (sticky) {
            seed_big_mul_add(&seed_num, 2, 1);
            binary -= 1;
        }
        binary += exponent;
        /* value = num * 2^binary, with num < 2^161. */
        if (binary + seed_big_bits(&seed_num) > format->emax + 2) {
            parsed->kind = 2;
            parsed->has_payload = -1; /* overflowing finite input */
            return;
        }
        if (binary + seed_big_bits(&seed_num) < format->emin - format->precision - 2) {
            parsed->kind = 0;
            parsed->has_payload = -1; /* underflowing nonzero input */
            return;
        }
        seed_big_set(&seed_den, 1);
        if (binary > 0) seed_big_shift_left(&seed_num, binary);
        else seed_big_shift_left(&seed_den, -binary);
        parsed->kind = 1;
        return;
    }
    for (; *text >= '0' && *text <= '9'; text++) {
        seen = 1;
        if (count == 0 && *text == '0') continue;
        if (count < format->keep_digits) {
            chunk = chunk * 10 + (unsigned int)(*text - '0');
            if (++chunk_size == 9) {
                seed_big_mul_add(&seed_num, 1000000000U, chunk);
                chunk = 0;
                chunk_size = 0;
            }
            count++;
        } else {
            scale++;
            if (*text != '0') sticky = 1;
        }
    }
    if (*text == '.') {
        const char *point = text;
        for (text++; *text >= '0' && *text <= '9'; text++) {
            seen = 1;
            if (count == 0 && *text == '0') {
                scale--;
                continue;
            }
            if (count < format->keep_digits) {
                chunk = chunk * 10 + (unsigned int)(*text - '0');
                if (++chunk_size == 9) {
                    seed_big_mul_add(&seed_num, 1000000000U, chunk);
                    chunk = 0;
                    chunk_size = 0;
                }
                count++;
                scale--;
            } else if (*text != '0') {
                sticky = 1;
            }
        }
        if (!seen) text = point;
    }
    if (!seen) return;
    if (*text == 'e' || *text == 'E') {
        const char *after = seed_exponent(text + 1, &exponent);
        if (after != text + 1) text = after;
        else exponent = 0;
    }
    parsed->end = text;
    if (chunk_size) {
        static const unsigned int powers[9] = {
            1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000
        };
        seed_big_mul_add(&seed_num, powers[chunk_size], chunk);
    }
    if (seed_num.used == 0) return;
    /* Dropped nonzero digits only break ties: one more nonzero digit beyond
       every half-way point's significant digits has the same effect. */
    if (sticky) {
        seed_big_mul_add(&seed_num, 10, 1);
        count++;
        scale--;
    }
    scale += exponent;
    /* value < 10^(count + scale) and >= 10^(count + scale - 1). */
    if (count + scale > format->ten_max) {
        parsed->kind = 2;
        parsed->has_payload = -1;
        return;
    }
    if (count + scale < format->ten_min) {
        parsed->kind = 0;
        parsed->has_payload = -1;
        return;
    }
    seed_big_set(&seed_den, 1);
    if (scale > 0) seed_big_pow10(&seed_num, scale);
    else seed_big_pow10(&seed_den, -scale);
    parsed->kind = 1;
    (void)start;
}

/* Parse and round TEXT; returns the result, sets *END and errno. */
static void seed_convert(const char *text, char **end, const struct seed_format *format,
                         struct seed_parse *parsed, struct seed_result *result)
{
    seed_parse_number(text, format, parsed);
    if (!parsed->end) parsed->negative = 0; /* no conversion: +0 */
    if (end) *end = (char *)(parsed->end ? parsed->end : text);
    result->kind = 0;
    result->mantissa = 0;
    result->exponent = 0;
    result->range_error = 0;
    if (parsed->kind == 1) {
        seed_round(format, result);
    } else if (parsed->kind == 2) {
        result->kind = 2;
        result->range_error = parsed->has_payload == -1;
    } else if (parsed->kind == 0) {
        result->range_error = parsed->has_payload == -1;
    }
    if (result->range_error) errno = ERANGE;
}

double strtod(const char *text, char **end)
{
    struct seed_parse parsed;
    struct seed_result result;
    unsigned long bits = 0;
    double value;
    seed_convert(text, end, &seed_binary64, &parsed, &result);
    if (parsed.kind == 3) {
        bits = 0x7ff8000000000000UL;
        if (parsed.has_payload == 1) bits |= parsed.payload & 0x7ffffffffffffUL;
    } else if (result.kind == 2) {
        bits = 0x7ff0000000000000UL;
    } else if (result.kind == 1) {
        if (result.mantissa >> 52)
            bits = ((unsigned long)(result.exponent + 1023) << 52) | (result.mantissa & 0xfffffffffffffUL);
        else
            bits = result.mantissa;
    }
    if (parsed.negative) bits |= 0x8000000000000000UL;
    memcpy(&value, &bits, sizeof value);
    return value;
}

float strtof(const char *text, char **end)
{
    struct seed_parse parsed;
    struct seed_result result;
    unsigned int bits = 0;
    float value;
    seed_convert(text, end, &seed_binary32, &parsed, &result);
    if (parsed.kind == 3) {
        bits = 0x7fc00000U;
        if (parsed.has_payload == 1) bits |= (unsigned int)(parsed.payload & 0x3fffffUL);
    } else if (result.kind == 2) {
        bits = 0x7f800000U;
    } else if (result.kind == 1) {
        if (result.mantissa >> 23)
            bits = ((unsigned int)(result.exponent + 127) << 23) | (unsigned int)(result.mantissa & 0x7fffffUL);
        else
            bits = (unsigned int)result.mantissa;
    }
    if (parsed.negative) bits |= 0x80000000U;
    memcpy(&value, &bits, sizeof value);
    return value;
}

long double strtold(const char *text, char **end)
{
    struct seed_parse parsed;
    struct seed_result result;
    unsigned char bytes[16];
    unsigned long mantissa = 0;
    unsigned int top = 0;
    long double value;
    seed_convert(text, end, &seed_extended, &parsed, &result);
    if (parsed.kind == 3) {
        mantissa = 0xc000000000000000UL;
        if (parsed.has_payload == 1) mantissa |= parsed.payload & 0x3fffffffffffffffUL;
        top = 32767;
    } else if (result.kind == 2) {
        mantissa = 0x8000000000000000UL;
        top = 32767;
    } else if (result.kind == 1) {
        mantissa = result.mantissa;
        /* The integer bit is explicit; a subnormal that rounded up to
           2^63 is the smallest normal, with biased exponent 1. */
        top = mantissa >> 63 ? (unsigned int)(result.exponent + 16383) : 0;
    }
    if (parsed.negative) top |= 32768;
    memset(bytes, 0, sizeof bytes);
    memcpy(bytes, &mantissa, 8);
    bytes[8] = (unsigned char)(top & 255);
    bytes[9] = (unsigned char)(top >> 8);
    memcpy(&value, bytes, sizeof value);
    return value;
}

double atof(const char *text)
{
    /* Like glibc's strtod(text, NULL): errno may be set to ERANGE. */
    return strtod(text, NULL);
}
