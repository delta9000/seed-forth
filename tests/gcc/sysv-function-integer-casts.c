/* Linux AMD64 LP64 representation checks. Numeric sentinels are never called.
   Calls through integer round trips restore the function's actual type. */
typedef void (*handler)(int);
typedef long (*narrow_callback)(signed char, unsigned short, long);
typedef handler (*handler_factory)(int);
handler static_default = (handler)0;
handler static_ignore = (void (*)(int))1;
handler static_error = (handler)-1;
handler static_unsigned = (handler)(unsigned int)-1;
handler static_narrow_signed = (handler)(signed char)255;
handler static_narrow_unsigned = (handler)(unsigned char)255;
handler from_char(signed char n) { return (handler)n; }
handler from_uchar(unsigned char n) { return (handler)n; }
handler from_short(short n) { return (handler)n; }
handler from_ushort(unsigned short n) { return (handler)n; }
handler from_int(int n) { return (handler)n; }
handler from_uint(unsigned int n) { return (handler)n; }
handler from_long(long n) { return (handler)n; }
handler from_ulong(unsigned long n) { return (handler)n; }
unsigned long to_bits(handler h) { return (unsigned long)h; }
long to_signed(handler h) { return (long)h; }
int effect_count;
int one_effect(void) { effect_count = effect_count + 1; return -1; }
long actual_narrow(signed char a, unsigned short b, long c) { return a + b + c; }
int handled;
void actual_handler(int n) { handled = n; }
unsigned long static_handler_bits = (unsigned long)actual_handler;
handler static_restored = (handler)(unsigned long)actual_handler;
narrow_callback static_typed = (narrow_callback)(long)actual_narrow;
handler select_handler(int n) { if (n) return actual_handler; return (handler)0; }
handler identity_handler(handler h) { return h; }
int function_integer_checks(void) {
    handler h;
    int zero;
    unsigned long bits;
    long signed_bits;
    narrow_callback callback;
    handler_factory factory;
    zero = 0;
    h = (void (*)(int))0;
    if (h != 0 || (handler)zero != h || static_default != h) return 1;
    if ((int (*)(void))0 != 0) return 2;
    if (to_bits(static_ignore) != 1UL || to_signed(static_error) != -1L) return 3;
    if (static_unsigned != (handler)4294967295UL) return 4;
    if (static_narrow_signed != static_error || to_bits(static_narrow_unsigned) != 255UL) return 5;
    if (to_signed(from_char(-1)) != -1L || to_signed(from_char(-128)) != -128L) return 6;
    if (to_bits(from_uchar(255)) != 255UL) return 7;
    if (to_signed(from_short(-32768)) != -32768L || to_signed(from_short(-1)) != -1L) return 8;
    if (to_bits(from_ushort(65535)) != 65535UL) return 9;
    if (to_signed(from_int(-2147483647 - 1)) != -2147483647L - 1L) return 10;
    if (to_signed(from_int(-1)) != -1L) return 11;
    if (to_bits(from_uint(4294967295U)) != 4294967295UL) return 12;
    if (to_bits(from_uint(2147483648U)) != 2147483648UL) return 13;
    if (to_signed(from_long(-1L)) != -1L || to_signed(from_long(-9223372036854775807L - 1L)) != -9223372036854775807L - 1L) return 14;
    if (to_bits(from_ulong(18446744073709551615UL)) != 18446744073709551615UL) return 15;
    if (to_bits(from_ulong(9223372036854775808UL)) != 9223372036854775808UL) return 16;
    if ((handler)(signed char)255 != static_error) return 17;
    if ((handler)(unsigned char)-1 != (handler)255UL) return 18;
    if ((handler)(short)65535 != static_error || (handler)(unsigned short)-1 != (handler)65535UL) return 19;
    if ((handler)(int)4294967295UL != static_error) return 20;
    if ((handler)(unsigned int)-1 != (handler)4294967295UL) return 21;
    h = (handler)one_effect();
    if (effect_count != 1 || h != static_error) return 22;
    if (identity_handler((void (*)(int))1) != static_ignore) return 23;
    bits = (unsigned long)actual_handler;
    h = (handler)bits;
    if (h != actual_handler) return 24;
    h(41);
    if (handled != 41) return 25;
    signed_bits = (long)actual_handler;
    ((void (*)(int))signed_bits)(42);
    if (handled != 42) return 26;
    callback = (narrow_callback)(unsigned long)actual_narrow;
    if (callback((signed char)255, (unsigned short)65537, 9) != 9) return 27;
    factory = (handler_factory)(long)select_handler;
    factory(1)(43);
    if (handled != 43 || factory(0) != 0) return 28;
    if ((handler)(unsigned long)(handler)-1 != static_error) return 29;
    if ((unsigned long)(handler)0 != 0 || (long)(handler)1 != 1) return 30;
    if (static_handler_bits != bits || static_restored != actual_handler) return 31;
    static_restored(44);
    if (handled != 44 || static_typed((signed char)255, (unsigned short)65537, 9) != 9) return 32;
    return 0;
}
#ifndef SF_FUNCTION_INTEGER_NO_MAIN
int main(void) { return function_integer_checks(); }
#endif
