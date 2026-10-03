/* Independent host ABI oracle for the Forth-compiled conversion functions. */
typedef void (*handler)(int);
handler from_char(signed char);
handler from_uchar(unsigned char);
handler from_short(short);
handler from_ushort(unsigned short);
handler from_int(int);
handler from_uint(unsigned int);
handler from_long(long);
handler from_ulong(unsigned long);
unsigned long to_bits(handler);
long to_signed(handler);
int function_integer_checks(void);
static int seen;
static void host_handler(int n) { seen = n; }
int main(void) {
    handler h;
    if (function_integer_checks()) return 1;
    if (from_char(-128) != (handler)-128L) return 2;
    if (from_uchar(255) != (handler)255UL) return 3;
    if (from_short(-32768) != (handler)-32768L) return 4;
    if (from_ushort(65535) != (handler)65535UL) return 5;
    if (from_int(-2147483647 - 1) != (handler)(-2147483647L - 1)) return 6;
    if (from_uint(4294967295U) != (handler)4294967295UL) return 7;
    if (from_long(-1L) != (handler)-1L) return 8;
    if (from_ulong(9223372036854775808UL) != (handler)9223372036854775808UL) return 9;
    if (to_bits((handler)18446744073709551615UL) != 18446744073709551615UL) return 10;
    if (to_signed((handler)-1L) != -1L) return 11;
    h = from_ulong((unsigned long)host_handler);
    if (h != host_handler || to_bits(h) != (unsigned long)host_handler) return 12;
    h(47);
    return seen != 47;
}
