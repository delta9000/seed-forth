/* Functions taking and returning _Bool; built by Forth and by host GCC. */
#include "bool.h"

_Bool bool_from_long(long v) { return v; }
_Bool bool_from_double(double v) { return v; }
_Bool bool_from_pointer(const void *p) { return p; }
int bool_take(_Bool a, _Bool b, int c, _Bool d) { return a * 100 + b * 10 + c + d * 1000; }
int bool_flags(struct flags f) { return f.c + f.b * 2 + f.s + f.t * 8 + (int)f.l + f.u * 32; }

struct bits bool_bits(int seed)
{
    struct bits r;
    r.a = seed;
    r.b = seed & 6;
    r.c = seed * 3;
    r.d = !seed;
    r.e = seed > 2;
    return r;
}

int bool_store(_Bool *out, long v)
{
    *out = v;
    return *out;
}
