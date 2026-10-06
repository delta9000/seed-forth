/* Original seed-forth fixture, MIT license. Reads 24-byte records
 * (int operation, pad, binary64 x, binary64 y) from stdin and writes 24-byte
 * results (result bits, auxiliary integer, errno) to stdout. The same source
 * is built by the Forth compiler against the seed runtime and, separately,
 * by host GCC against host glibc as an oracle. No formatting, tables or
 * expected values live here. */
#include <math.h>
#include <errno.h>
#include <unistd.h>

#define BATCH 2048

union fixture_bits { double number; unsigned long bits; long integer; };

static unsigned char input[24 * BATCH];
static unsigned char output[24 * BATCH];

static unsigned long load(const unsigned char *p)
{
    unsigned long value = 0;
    int i;
    for (i = 7; i >= 0; i--) value = (value << 8) | p[i];
    return value;
}

static void store(unsigned char *p, unsigned long value)
{
    int i;
    for (i = 0; i < 8; i++) {
        p[i] = (unsigned char)(value & 255);
        value >>= 8;
    }
}

static int fill(long want)
{
    long have = 0;
    long got;
    while (have < want) {
        got = read(0, input + have, want - have);
        if (got < 0) return -1;
        if (got == 0) break;
        have += got;
    }
    return (int)have;
}

static int flush(long size)
{
    long done = 0;
    long put;
    while (done < size) {
        put = write(1, output + done, size - done);
        if (put <= 0) return -1;
        done += put;
    }
    return 0;
}

static void evaluate(int operation, double x, double y, unsigned long ybits,
                     union fixture_bits *result, long *aux)
{
    double part;
    int exponent;
    *aux = 0;
    switch (operation) {
    case 0: result->number = exp(x); break;
    case 1: result->number = exp2(x); break;
    case 2: result->number = expm1(x); break;
    case 3: result->number = log(x); break;
    case 4: result->number = log2(x); break;
    case 5: result->number = log10(x); break;
    case 6: result->number = log1p(x); break;
    case 7: result->number = pow(x, y); break;
    case 8: result->number = cbrt(x); break;
    case 9: result->number = hypot(x, y); break;
    case 10: result->number = sin(x); break;
    case 11: result->number = cos(x); break;
    case 12: result->number = tan(x); break;
    case 13: result->number = asin(x); break;
    case 14: result->number = acos(x); break;
    case 15: result->number = atan(x); break;
    case 16: result->number = atan2(x, y); break;
    case 17: result->number = sinh(x); break;
    case 18: result->number = cosh(x); break;
    case 19: result->number = tanh(x); break;
    case 20: result->number = sqrt(x); break;
    case 21: result->number = fabs(x); break;
    case 22: result->number = floor(x); break;
    case 23: result->number = ceil(x); break;
    case 24: result->number = trunc(x); break;
    case 25: result->number = round(x); break;
    case 26: result->number = rint(x); break;
    case 27: result->number = nearbyint(x); break;
    case 28: *aux = lround(x); break;
    case 29: *aux = lrint(x); break;
    case 30: *aux = (long)llround(x); break;
    case 31: *aux = (long)llrint(x); break;
    case 32: result->number = fmod(x, y); break;
    case 33: result->number = remainder(x, y); break;
    case 34: result->number = fmin(x, y); break;
    case 35: result->number = fmax(x, y); break;
    case 36: result->number = fdim(x, y); break;
    case 37:
        result->number = frexp(x, &exponent);
        *aux = exponent;
        break;
    case 38: result->number = ldexp(x, (int)(long)ybits); break;
    case 39: result->number = scalbn(x, (int)(long)ybits); break;
    case 40: {
        union fixture_bits whole;
        result->number = modf(x, &part);
        whole.number = part;
        *aux = whole.integer;
        break;
    }
    case 41: result->number = copysign(x, y); break;
    case 42:
        *aux = fpclassify(x) | (signbit(x) != 0) << 4 | (isnan(x) != 0) << 5
            | (isinf(x) != 0) << 6 | (isfinite(x) != 0) << 7 | (isnormal(x) != 0) << 8
            | (isunordered(x, y) != 0) << 9 | (islessgreater(x, y) != 0) << 10
            | (isgreater(x, y) != 0) << 11 | (isless(x, y) != 0) << 12;
        break;
    default: result->bits = 0xdeadUL; break;
    }
}

int main(void)
{
    union fixture_bits x;
    union fixture_bits y;
    union fixture_bits result;
    long aux;
    int have;
    int count;
    int i;
    for (;;) {
        have = fill(24L * BATCH);
        if (have < 0 || have % 24) return 1;
        if (have == 0) return 0;
        count = have / 24;
        for (i = 0; i < count; i++) {
            x.bits = load(input + 24 * i + 8);
            y.bits = load(input + 24 * i + 16);
            result.bits = 0;
            errno = 123;
            evaluate((int)(load(input + 24 * i) & 0xffff), x.number, y.number, y.bits, &result, &aux);
            store(output + 24 * i, result.bits);
            store(output + 24 * i + 8, (unsigned long)aux);
            store(output + 24 * i + 16, (unsigned long)errno);
        }
        if (flush(24L * count)) return 1;
    }
}
