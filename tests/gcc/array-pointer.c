#include <stdarg.h>
#include <stddef.h>
typedef long row[3];
typedef row matrix[2];
struct callback { long (*consume)(va_list *); row *data; };
static long consume(va_list *list) {
    long first = va_arg(*list, long);
    long second = va_arg(*list, long);
    return first * 10 + second;
}
static long dispatch(struct callback *cb, int sentinel, ...) {
    va_list list;
    long answer;
    if (sentinel != 0) return -1;
    va_start(list, sentinel);
    answer = cb->consume(&list);
    answer += va_arg(list, long);
    va_end(list);
    return answer;
}
static long sum(row *p) { return (*p)[0] + p[0][1] + (*p)[2]; }
int main(void) {
    matrix values = {{1,2,3},{4,5,6}};
    row *p = &values[0];
    row **pp = &p;
    long (*typed)[3] = &values[0];
    struct callback cb;
    cb.consume = consume; cb.data = p;
    if (sizeof(long (*)[3]) != 8 || sizeof(*typed) != 24) return 7;
    if (sizeof(row) != 24 || sizeof(row *) != 8 || sizeof(*p) != 24) return 1;
    if (sizeof(matrix) != 48 || sizeof(*pp) != 8) return 2;
    if ((char *)(p+1) - (char *)p != 24 || (p+2)-p != 2) return 3;
    if (sum(*pp) != 6 || sum(++p) != 15 || sum(cb.data) != 6) return 4;
    (*p)[1] = 12;
    if (values[1][1] != 12) return 5;
    /* Callback advances the original list, rather than a record copy. */
    if (dispatch(&cb, 0, 7L, 8L, 9L) != 87) return 6;
    return 0;
}
