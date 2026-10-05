/* Host is only an ABI oracle; the all-Forth run compiles this source too. */
struct ParameterRecord { long bias; };
enum ParameterKind { PARAMETER_KIND = 9 };
char *copy_string(const char *);
int character(const char *);
unsigned long ordered(unsigned long);
int narrow(unsigned char);
int signed_narrow(signed char);
long record(const struct ParameterRecord *);
long after_tag(const struct ParameterRecord *);
long after_typedef(long);
int after_enum(enum ParameterKind);
int row(const unsigned char *);
int callback(int (*)(const char *), const char *);
int route(int (*)(int (*)(const char *), const char *), int (*)(const char *), const char *);
int old_style(const char *, int);
int production_calls_host(const char *);
int abstract_cast(const char *);
int host_character(const char *s) { return s[2]; }
int main(void)
{
    const char *s = "abc";
    unsigned char bytes[3] = { 200, 0, 33 };
    struct ParameterRecord p = { 0x123456789L };
    if (copy_string(s) != s || character(s) != 'b') return 1;
    if (ordered(0x123456789UL) != 0x12345678cUL) return 2;
    if (narrow(255) != 255 || signed_narrow(-17) != -17) return 3;
    if (record(&p) != p.bias || after_tag(&p) != p.bias + 1) return 4;
    if (after_typedef(p.bias) != p.bias + 2 || after_enum(PARAMETER_KIND) != 9) return 5;
    if (row(bytes) != 233 || callback(character, s) != 'b' + 1) return 6;
    if (route(callback, character, s) != 'b' + 3) return 7;
    if (old_style(s, 255) != 'a' + 255) return 8;
    if (production_calls_host(s) != 'c' + 4) return 9;
    if (abstract_cast(s) != 'b') return 10;
    return 0;
}
