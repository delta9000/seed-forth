/* C99 _Bool across translation units and the System V boundary. */
#include <stdbool.h>
struct flags { char c; _Bool b; short s; bool t; long l; bool u; };
struct bits { int a : 3; _Bool b : 1; unsigned c : 4; _Bool d : 1; _Bool : 0; _Bool e : 1; };
_Bool bool_from_long(long v);
_Bool bool_from_double(double v);
_Bool bool_from_pointer(const void *p);
int bool_take(_Bool a, _Bool b, int c, _Bool d);
int bool_flags(struct flags f);
struct bits bool_bits(int seed);
int bool_store(_Bool *out, long v);
