#include "varargs-fixture.h"

int vsnprintf(char *buffer, unsigned long capacity, const char *format, va_list list);
long host_sum(int count, ...);

int seed_format(char *buffer, unsigned long capacity, const char *format, ...)
{
    va_list list;
    int result;
    va_start(list, format);
    result = vsnprintf(buffer, capacity, format, list);
    va_end(list);
    return result;
}

long seed_call_host(void)
{
    long (*call)(int, ...) = host_sum;
    return call(10, -1L, 2L, -3L, 4L, -5L, 6L, -7L, 8L, -9L, 10L);
}
