/* Execute unchanged configured GCC 4.0.4 libiberty source. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ansidecl.h"
#include "libiberty.h"
#include "dyn-string.h"
#ifdef REVIEW_DECLARATOR_HOST_TARGET
/* Target stdio name is adapted only in this host interoperability oracle. */
FILE *__seed_stderr;
#endif
static int next_handler;
static int handler_count;
static void observe(int which) {
    if (next_handler < 0 || next_handler % 3 != which) exit(91);
    --next_handler;
    ++handler_count;
    if (next_handler == -1) {
        if (handler_count != 70) exit(92);
        puts("PASS: original spaces, dyn-string, xatexit and xexit; 70 LIFO handlers");
    }
}
static void handler0(void) { observe(0); }
static void handler1(void) { observe(1); }
static void handler2(void) { observe(2); }
static int check_spaces(void) {
    const char *s;
    int i;
    int n;
    for (n = 1; n < 140; ++n) {
        s = spaces(n);
        if (!s || strlen(s) != n) return 11;
        for (i = 0; i < n; ++i) if (s[i] != ' ') return 12;
    }
    for (n = 139; n >= 0; --n) {
        s = spaces(n);
        if (!s || strlen(s) != n) return 13;
        for (i = 0; i < n; ++i) if (s[i] != ' ') return 14;
    }
    return 0;
}
static int check_strings(void) {
    dyn_string_t a;
    dyn_string_t b;
    char *released;
    int i;
    a = dyn_string_new(0);
    b = dyn_string_new(1);
    if (!a || !b || a->length || b->length) return 21;
    if (!dyn_string_copy_cstr(a,"abcdef") || !dyn_string_substring(b,a,1,5)) return 22;
    if (strcmp(b->s,"bcde") || b->length != 4) return 23;
    if (!dyn_string_insert_cstr(b,2,"XY") || strcmp(b->s,"bcXYde")) return 24;
    if (!dyn_string_insert_char(b,1,'!') || strcmp(b->s,"b!cXYde")) return 25;
    if (!dyn_string_prepend_cstr(b,"START") || !dyn_string_append_cstr(b,"END")) return 26;
    if (strcmp(b->s,"STARTb!cXYdeEND")) return 27;
    if (!dyn_string_copy(a,b) || !dyn_string_eq(a,b)) return 28;
    dyn_string_clear(a);
    if (a->length || a->s[0]) return 29;
    for (i = 0; i < 100; ++i) if (!dyn_string_append_char(a,'a' + i % 26)) return 30;
    if (!dyn_string_substring(b,a,0,100) || !dyn_string_eq(a,b)) return 31;
    for (i = 0; i < 100; ++i) if (b->s[i] != 'a' + i % 26) return 32;
    if (!dyn_string_substring(b,a,30,30) || b->length || b->s[0]) return 33;
    if (!dyn_string_substring(b,a,99,100) || b->length != 1 || b->s[0] != 'v') return 34;
    released = dyn_string_release(a);
    if (strlen(released) != 100) return 35;
    free(released);
    dyn_string_delete(b);
    return 0;
}
int main(void) {
    int i;
    int result;
#ifdef REVIEW_DECLARATOR_HOST_TARGET
    __seed_stderr = stderr;
#endif
    result = check_spaces();
    if (result) return result;
    result = check_strings();
    if (result) return result;
    next_handler = 69;
    handler_count = 0;
    for (i = 0; i < 70; ++i) {
        if (i % 3 == 0) result = xatexit(handler0);
        else if (i % 3 == 1) result = xatexit(handler1);
        else result = xatexit(handler2);
        if (result) return 41;
    }
    xexit(0);
    return 42;
}
