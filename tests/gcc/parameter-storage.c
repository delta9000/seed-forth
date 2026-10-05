/* Production source: compiled by Forth, including the original Flex spelling. */
extern char *copy_string(register const char *);
extern char *copy_string(const char *);
typedef unsigned char ByteRow[3];
typedef long Count;
struct ParameterRecord { long bias; };
enum ParameterKind { PARAMETER_KIND = 9 };
extern int host_character(register const char *);
/* A fresh member context must neither consume nor inherit outer register state. */
int nested_record(register const struct {
    int (*callback)(register const char *);
    const long marker;
} *);
int character(register const char *);
int callback(register int (* const)(register const char *), const register char *);
int route(register int (*)(register int (*)(register const char *), register const char *),
          register int (*)(register const char *), register const char *);

char *copy_string(register const char *s) { return (char *)s; }
int character(const char register *s) { return s[1]; }
unsigned long ordered(unsigned register const long value) { return value + 3; }
int narrow(register unsigned const char value) { return value; }
int signed_narrow(register const signed char value) { return value; }
long record(register const struct ParameterRecord *p) { return p->bias; }
long after_tag(struct ParameterRecord const register *p) { return p->bias + 1; }
long after_typedef(Count register const value) { return value + 2; }
int after_enum(enum ParameterKind volatile register value) { return value; }
int row(register const ByteRow bytes) { return bytes[0] + bytes[2]; }
int callback(register int (* const cb)(register const char *), register const char *s)
{ return cb(s) + 1; }
int route(register int (*cb)(register int (*)(register const char *), register const char *),
          register int (*f)(register const char *), register const char *s)
{ return cb(f, s) + 2; }
int old_style(s, value)
const char register *s;
unsigned const register char value;
{ return s[0] + value; }
int production_calls_host(register const char *s) { return host_character(s) + 4; }
int abstract_cast(register const char *s)
{
    int (*f)(const char *);
    f = character;
    return ((int (*)(register const char *))f)(s);
}
