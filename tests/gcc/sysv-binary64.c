/* Executable binary64 value proof; all production bytes come from Forth. */
double ratio(unsigned long numerator, unsigned long denominator) {
    return (double)numerator / (double)denominator;
}
double unused_double_parameter(double);
int main(void) {
    double x;
    double y;
    union { double value; unsigned long bits; } payload;
    x = .5;
    y = 1e1;
    x += 1.5;
    x *= y;
    x /= 2.;
    x -= 9.75;
    if (x != 0.25 || ratio(1, 10) != .1) return 1;
    if (ratio(18446744073709551615UL, 1) != 18446744073709551616.0) return 2;
    payload.value = -0.0;
    if (payload.bits != 0x8000000000000000UL || payload.value || !(!payload.value)) return 3;
    if ((unsigned long)ratio(9223372036854775808UL, 1) != 9223372036854775808UL) return 4;
    if (sizeof(unused_double_parameter(1.0)) != 8 || sizeof(.5) != 8) return 5;
    return 0;
}
