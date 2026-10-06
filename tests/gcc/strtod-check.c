/* Differential fixture for strtod, strtof, strtold and atof. Built by the
   Forth compiler against runtime/gcc-seed (production) and by host GCC
   against glibc (oracle only); strtod-check.py requires identical output.
   Inputs are generated here from a seeded generator with an independent
   exact decimal expander, so both builds convert the same text.
   Usage: prog SECTION SEED COUNT. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static unsigned long state;
static char text[13000];

static unsigned long next(void)
{
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    return state * 2685821657736338717UL;
}

static unsigned long below(unsigned long limit) { return next() % limit; }

/* Convert TEXT with every function; print bits, errno and end offsets. */
static void check(const char *input, int which)
{
    char *end;
    double d;
    float f;
    long double l;
    unsigned long dbits;
    unsigned int fbits;
    unsigned char lbytes[16];
    size_t length = strlen(input);
    int index;
    if (length > 70) printf("%.40s...%s(%d)", input, input + length - 20, (int)length);
    else printf("%s", input);
    if (which & 1) {
        errno = 0;
        d = strtod(input, &end);
        memcpy(&dbits, &d, 8);
        printf("|d %016lx %d %d", dbits, errno, (int)(end - input));
        errno = 0;
        d = atof(input);
        memcpy(&dbits, &d, 8);
        printf(" a %016lx", dbits);
    }
    if (which & 2) {
        errno = 0;
        f = strtof(input, &end);
        memcpy(&fbits, &f, 4);
        printf("|f %08x %d %d", fbits, errno, (int)(end - input));
    }
    if (which & 4) {
        errno = 0;
        l = strtold(input, &end);
        memset(lbytes, 0, 16);
        memcpy(lbytes, &l, 10);
        printf("|l ");
        for (index = 9; index >= 0; index--) printf("%02x", lbytes[index]);
        printf(" %d %d", errno, (int)(end - input));
    }
    printf("\n");
}

/* Exact decimal digits of (2*m + odd) * 2^power, as an integer digit
   string and a count of fraction digits: an independent expander. */
static unsigned int limb[2200];
static int expand(unsigned long m, int odd, int power, char *digits, int *fraction)
{
    int used = 0;
    int index;
    int count = 0;
    unsigned long carry;
    unsigned long top;
    char reversed[12];
    int length;
    /* start with 2*m + odd as up to 65 bits: (m*2 + odd) via two limbs */
    top = m >> 63;
    m = (m << 1) | (unsigned long)odd;
    limb[used++] = (unsigned int)(m % 1000000000UL);
    carry = m / 1000000000UL;
    while (carry) {
        limb[used++] = (unsigned int)(carry % 1000000000UL);
        carry /= 1000000000UL;
    }
    if (top) {
        /* add 2^64 = 18446744073709551616 */
        static const unsigned int two64[3] = { 709551616U, 446744073U, 18U };
        unsigned long sum = 0;
        for (index = 0; index < 3 || sum; index++) {
            if (index >= used) limb[used++] = 0;
            sum += limb[index] + (index < 3 ? two64[index] : 0);
            limb[index] = (unsigned int)(sum % 1000000000UL);
            sum /= 1000000000UL;
        }
    }
    *fraction = 0;
    while (power != 0) {
        /* multiply by 2^k (k <= 30) or 5^k (k <= 13) */
        unsigned long factor = 1;
        int k = 0;
        while (power > 0 && k < 30) { factor *= 2; power--; k++; }
        while (power < 0 && k < 13) { factor *= 5; power++; k++; (*fraction)++; }
        carry = 0;
        for (index = 0; index < used; index++) {
            carry += (unsigned long)limb[index] * factor;
            limb[index] = (unsigned int)(carry % 1000000000UL);
            carry /= 1000000000UL;
        }
        while (carry) {
            limb[used++] = (unsigned int)(carry % 1000000000UL);
            carry /= 1000000000UL;
        }
    }
    length = 0;
    carry = limb[used - 1];
    do {
        reversed[length++] = (char)('0' + carry % 10);
        carry /= 10;
    } while (carry);
    while (length) digits[count++] = reversed[--length];
    for (index = used - 2; index >= 0; index--) {
        int place;
        carry = limb[index];
        for (place = 8; place >= 0; place--) {
            digits[count + place] = (char)('0' + carry % 10);
            carry /= 10;
        }
        count += 9;
    }
    digits[count] = 0;
    return count;
}

/* Write digits D (count n, f fraction digits) as scientific text with an
   optional edit: 0 exact, 1 truncate to K digits, 2 append "0...01". */
static void scientific(const char *digits, int count, int fraction, int edit, int keep)
{
    int length = 0;
    int exponent = count - 1 - fraction;
    int used = count;
    int index;
    if (edit == 1 && keep < count) used = keep;
    text[length++] = digits[0];
    text[length++] = '.';
    for (index = 1; index < used; index++) text[length++] = digits[index];
    if (edit == 2) {
        int zeros = (int)below(30);
        while (zeros--) text[length++] = '0';
        text[length++] = '1';
    }
    if (edit == 3 && used > 1) {
        /* one unit less in the last place: just below the halfway point */
        index = length - 1;
        while (text[index] == '0') text[index--] = '9';
        if (text[index] != '.') text[index] = (char)(text[index] - 1);
    }
    length += sprintf(text + length, "e%d", exponent);
    text[length] = 0;
}

/* Halfway points between adjacent values of each format, and neighbours. */
static void section_halfway(long count)
{
    static char digits[13000];
    long index;
    for (index = 0; index < count; index++) {
        int format = (int)below(3);
        unsigned long m;
        int power;
        int fraction;
        int n;
        int edit;
        if (format == 0) {
            /* binary64: m in [2^52, 2^53) at exponent e, or subnormal */
            m = (next() >> 11) | (1UL << 52);
            power = (int)below(2100) - 1074 - 53;
            if (below(5) == 0) { m = next() >> (12 + below(52)); power = -1075; }
        } else if (format == 1) {
            m = (next() >> 40) | (1UL << 23);
            power = (int)below(300) - 149 - 24;
            if (below(5) == 0) { m = next() >> (41 + below(23)); power = -150; }
        } else {
            m = next() | (1UL << 63);
            power = (int)below(2000) - 1000 - 64;
            if (below(10) == 0) power = (int)below(32760) - 16445 - 64;
            if (below(20) == 0) { m = next() >> below(64); power = -16446; }
        }
        n = expand(m, 1, power, digits, &fraction);
        edit = (int)below(4);
        scientific(digits, n, fraction, edit, 1 + (int)below(40));
        check(text, format == 0 ? 1 : format == 1 ? 2 : 4);
    }
}

/* Random decimal text of varied length and exponent. */
static void section_decimal(long count)
{
    long index;
    for (index = 0; index < count; index++) {
        int length = 0;
        int digits;
        int point;
        int place;
        int which = 1 | 2;
        if (below(10) == 0) text[length++] = ' ';
        if (below(4) == 0) text[length++] = below(2) ? '-' : '+';
        switch (below(8)) {
        case 0: digits = 1 + (int)below(3); break;
        case 1: digits = 17; break;
        case 2: digits = 19 + (int)below(3); break;
        case 3: digits = 1 + (int)below(40); break;
        case 4: digits = 1 + (int)below(800); break;
        default: digits = 1 + (int)below(25); break;
        }
        point = below(2) ? (int)below((unsigned long)digits + 1) : -1;
        for (place = 0; place < digits; place++) {
            if (place == point) text[length++] = '.';
            text[length++] = (char)('0' + below(10));
        }
        if (point == digits) text[length++] = '.';
        if (below(5)) {
            int exponent = (int)below(700) - 350;
            if (below(10) == 0) exponent = (int)below(10000) - 5000;
            length += sprintf(text + length, "%c%d", below(2) ? 'e' : 'E', exponent);
            if (below(10) == 0) which = 4;
        }
        if (below(10) == 0) text[length++] = 'x';
        text[length] = 0;
        if (below(20) == 0) which = 4;
        check(text, which);
    }
}

/* Random hexadecimal floating text. */
static void section_hex(long count)
{
    static const char hex[] = "0123456789abcdefABCDEF";
    long index;
    for (index = 0; index < count; index++) {
        int length = 0;
        int digits = 1 + (int)below(below(3) ? 17 : 45);
        int point = below(2) ? (int)below((unsigned long)digits + 1) : -1;
        int place;
        if (below(4) == 0) text[length++] = '-';
        text[length++] = '0';
        text[length++] = below(2) ? 'x' : 'X';
        for (place = 0; place < digits; place++) {
            if (place == point) text[length++] = '.';
            text[length++] = hex[below(22)];
        }
        if (point == digits) text[length++] = '.';
        if (below(6)) {
            int exponent = (int)below(2400) - 1200;
            if (below(5) == 0) exponent = (int)below(33000) - 16500;
            if (below(5) == 0) exponent = (int)below(320) - 160;
            length += sprintf(text + length, "%c%d", below(2) ? 'p' : 'P', exponent);
        }
        text[length] = 0;
        check(text, 7);
    }
}

static void section_special(void)
{
    static const char *inputs[] = {
        "0", "-0", "+0.000", "1", "-1", "0.1", "1e23", "8.98846567431158e307",
        "1.7976931348623157e308", "1.7976931348623158e308", "1.7976931348623159e308",
        "2.2250738585072011e-308", "2.2250738585072012e-308", "2.2250738585072014e-308",
        "4.9406564584124654e-324", "2.4703282292062327e-324", "2.4703282292062328e-324",
        "1e-400", "-1e400", "9007199254740993", "9007199254740992.5", "  +12.5e+3x",
        "\t-.5", "5.", "e5", ".e5", "1e", "1e+", "1e-", "-", "+", "", " ", ".", "-.", "0x",
        "0X", "0xg", "0x.", "0x.p1", "0x1p", "0x1p+", "0x1.8P+3", "0x.8p1", "0X1.FFFFFFFFFFFFFP1023",
        "0x1p-1074", "0x1p-1075", "0x1.0000000000001p-1075", "0x1.00000000000008p-1022",
        "0x0.fffffffffffff8p-1022", "0x1.ffffffffffffffp-1023", "0x1p1024", "0x1p-149",
        "0x1.8p-150", "0x1p-16445", "0x1p-16446", "0x1.8p-16446", "0x1p16384",
        "0xffffffffffffffffffffffffffffffffffffffffffffffff", "0x123456789abcdef0123456789p-200",
        "inf", "INF", "-inf", "+Inf", "infinity", "INFINITY", "infinit", "infinityx", "in", "i",
        "nan", "NaN", "-nan", "nan(", "nan()", "nan(0x123)", "nan(123)", "nan(0123)", "nan(abc)",
        "-nan(abc)", "nan(0x7ffffffffffff)", "nan(0x8000000000000)", "nan(0xfffffffffffff)",
        "nan(0xffffffffffffffff)", "nan(99999999999999999999999)", "nan(_)", "nan( 1)", "nan(1 )",
        "nan(0x)", "nan(08)", "nan(0x3fffff)", "nan(0x400000)", "nanx", "na",
        "1e00000000000000000003", "1e-99999999999999", "1e+99999999999999", "0e99999999999",
        "0.000001e6", "100e-2", "0000000000000000000000000000001", "-0.0e-5",
        "3.4028235e38", "3.40282356779733661637539395458142568448e38",
        "3.40282366920938463463374607431768211456e38", "1.17549435e-38", "1.1754942e-38",
        "1.4e-45", "7.006492321624085e-46", "7.006492321624086e-46", "1e-46",
        "1.18973149535723176502e+4932", "1.18973149535723176508e+4932", "1.2e4932",
        "3.36210314311209350626e-4932", "3.6451995318824746025e-4951", "1.8225997659412373012e-4951",
        "1.8225997659412373013e-4951", "1e-4951", "1e-5000", "\v\f\r\n 42", "12abc", "1.2.3",
        "+-1", "--1", "0.e", "00x1p1", 0
    };
    int index;
    char big[2100];
    for (index = 0; inputs[index]; index++) check(inputs[index], 7);
    memset(big, '9', 2000);
    big[2000] = 0;
    check(big, 7);
    big[0] = '.';
    check(big, 7);
    memset(big, '0', 2000);
    big[1999] = '1';
    big[0] = '.';
    check(big, 7);
    strcpy(big + 1990, "1e2000");
    check(big, 7);
}

int main(int argc, char **argv)
{
    long count;
    if (argc != 4) return 2;
    state = strtoul(argv[2], NULL, 10) * 2 + 0x9e3779b97f4a7c15UL;
    count = (long)strtoul(argv[3], NULL, 10);
    if (!strcmp(argv[1], "halfway")) section_halfway(count);
    else if (!strcmp(argv[1], "decimal")) section_decimal(count);
    else if (!strcmp(argv[1], "hex")) section_hex(count);
    else if (!strcmp(argv[1], "special")) section_special();
    else return 2;
    return fflush(stdout) != 0;
}
