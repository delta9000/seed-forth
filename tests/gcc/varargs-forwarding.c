/* These Forth-built wrappers never evaluate a floating C expression. */
#include "varargs-fixture.h"

long host_reenter(int depth);
long host_vsequence(int depth, va_list list);
long host_vnamed7(va_list list);

long seed_forward_reenter(int depth, ...)
{
    va_list original;
    va_list copied;
    long nested = 0;
    long left;
    long right;
    va_start(original, depth);
    va_copy(copied, original);
    if (depth > 0) nested = host_reenter(depth - 1);
    left = host_vsequence(depth, original);
    right = host_vsequence(depth, copied);
    va_end(copied);
    va_end(original);
    if (left < 0 || right != left || nested < 0) return -1;
    return nested + left;
}

long seed_forward_named7(long a, long b, long c, long d,
                         long e, long f, long g, ...)
{
    va_list list;
    long result;
    va_start(list, g);
    result = host_vnamed7(list);
    va_end(list);
    return result + a + b + c + d + e + f + g;
}
