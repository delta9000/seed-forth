/* C90 source: grouped pointer returns, callback arrays and empty for steps. */
struct handler_table {
    struct handler_table *next;
    int ind;
    void (*fns[4])(void);
};
struct int_table { int (*fns[3])(int); };
static int value;
static int calls;
static int order;
static char letter;
static char *letters;
char (**grouped_object);
int (*value_location());
int *value_location(void);
int (*value_location(void)) { ++calls; return &value; }
char *(*letters_location(void)) { return &letters; }
static int plus_one(int x) { return x + 1; }
static int plus_two(int x) { return x + 2; }
static void first(void) { order = order * 10 + 1; }
static void second(void) { order = order * 10 + 2; }
int declarator_edges(void) {
    struct handler_table handlers;
    struct int_table table;
    int (*local[2])(int);
    int (*grouped_integer);
    char buf[5];
    char *t;
    int i;
    int sum;
    int oldcalls;
    handlers.next = 0;
    handlers.ind = 2;
    handlers.fns[0] = first;
    handlers.fns[1] = second;
    order = 0;
    i = 0;
    handlers.fns[i++]();
    (*handlers.fns[i++])();
    if (i != 2 || order != 12 || sizeof(handlers.fns) != 32) return 1;
    if (sizeof(handlers) != 48) return 2;
    table.fns[0] = plus_one;
    table.fns[1] = plus_two;
    local[0] = table.fns[1];
    local[1] = table.fns[0];
    i = 2;
    if (local[--i](40) != 41 || i != 1) return 3;
    if ((*local[--i])(40) != 42 || i != 0) return 4;
    value = 12;
    calls = 0;
    grouped_integer = value_location();
    if (grouped_integer != &value || calls != 1) return 5;
    oldcalls = calls;
    if (--*value_location() != 11 || calls != oldcalls + 1) return 6;
    letters = &letter;
    grouped_object = letters_location();
    if (grouped_object != &letters || *grouped_object != &letter) return 7;
    for (t = buf + 4; t != buf; ) { *--t = ' '; }
    for (i = 4; --i >= 0; /* omitted step with parentheses: () */ ) {
        if (buf[i] != ' ') return 8;
    }
    sum = 0;
    for (i = 4; i > 0; --i) sum += i;
    if (sum != 10) return 9;
    for (i = 0; i < 3;
         /* a newline and comment are still an empty step */
        ) {
        int j;
        for (j = 0; j < 2; /* nested */ ) { sum += j; ++j; }
        ++i;
    }
    if (sum != 13 || i != 3) return 10;
    for (;;) { break; }
    for ( ; ; /* empty clauses */ ) { break; }
    return 0;
}
#ifndef DECLARATOR_EDGES_NO_MAIN
int main(void) { return declarator_edges(); }
#endif
