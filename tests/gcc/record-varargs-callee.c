/* Definitions: K&R, empty-parenthesis, prototyped and variadic, with
   va_arg of every record class next to scalars and binary64. */
#include <stdarg.h>
#include "record-varargs.h"

long knr_sum(a, n, b, c)
    struct S1 a; int n; struct S2 b; struct Big c;
{
    return a.a * 3 + a.b + n * 7 + b.l * 11 + b.c + c.x * 13 + c.y + c.z * 17;
}

struct S2 knr_make(n)
    long n;
{
    struct S2 r;
    r.l = n * 2;
    r.c = (char)(n + 1);
    return r;
}

struct Big empty_make()
{
    struct Big r;
    r.x = 101;
    r.y = -202;
    r.z = 303;
    return r;
}

long proto_sum(struct S1 a, long x, struct Big b)
{
    return a.a - a.b + x * 5 + b.x + b.y * 2 + b.z * 3;
}

static long x87_bytes(struct X x)
{
    unsigned char *p = (unsigned char *)&x;
    long sum = 0;
    int i;
    for (i = 0; i < 10; i++)
        sum = sum * 3 + p[i];
    return sum;
}

static long take(const char *format, va_list ap)
{
    long sum = 0;
    for (; *format; format++) {
        long term = 0;
        switch (*format) {
        case 'i': term = va_arg(ap, int); break;
        case 'l': term = va_arg(ap, long); break;
        case 'p': term = *va_arg(ap, long *); break;
        case 'd': term = (long)(va_arg(ap, double) * 4.0); break;
        case '1': { struct S1 v = va_arg(ap, struct S1); term = v.a * 5 + v.b; break; }
        case '2': { struct S2 v = va_arg(ap, struct S2); term = v.l * 3 + v.c; break; }
        case '3': { struct S3 v = va_arg(ap, struct S3); term = v.c[0] + v.c[1] * 7 + v.c[2] * 49; break; }
        case 'b': { struct Big v = va_arg(ap, struct Big); term = v.x + v.y * 11 + v.z * 13; break; }
        case 'u': { union U v = va_arg(ap, union U); term = v.l + v.c[8] + v.c[11] * 17; break; }
        case 'x': term = x87_bytes(va_arg(ap, struct X)); break;
        default: return -1;
        }
        sum = sum * 31 + term;
    }
    return sum;
}

long vsum(const char *format, ...)
{
    va_list ap;
    long sum;
    va_start(ap, format);
    sum = take(format, ap);
    va_end(ap);
    return sum;
}

long vlist(const char *format, ...)
{
    va_list ap, copy;
    long first, second;
    va_start(ap, format);
    va_copy(copy, ap);
    first = take(format, ap);
    second = take(format, copy);
    va_end(copy);
    va_end(ap);
    return first == second ? first : -2;
}

struct Big vbig(int n, ...)
{
    va_list ap;
    struct Big r;
    struct S2 s;
    va_start(ap, n);
    r = va_arg(ap, struct Big);
    s = va_arg(ap, struct S2);
    r.x += n;
    r.y += s.l;
    r.z += s.c + va_arg(ap, long);
    va_end(ap);
    return r;
}

long vnamed(struct S2 s, int n, ...)
{
    va_list ap;
    long sum = s.l * 100 + s.c;
    va_start(ap, n);
    while (n-- > 0) {
        struct S1 v = va_arg(ap, struct S1);
        sum = sum * 7 + v.a - v.b;
    }
    sum += va_arg(ap, struct Big).z;
    va_end(ap);
    return sum;
}
