/* Independent strict C90 behavioral oracle. */
struct record { int value; long tail; };
typedef int (*leaf)(unsigned char);
typedef struct record *(*record_getter)(unsigned char);
struct callbacks {
    int (*narrow[2])(unsigned char);
    signed char (*small[2])(int);
    struct record *(*records[2])(unsigned char);
    record_getter aliases[2];
    leaf (*factories[2])(void);
};
static struct record records[3];
static int scalar;
static int *scalar_pointer;
static int hits;
extern int (*location());
extern int *location(void);
int (*location(void)) { ++hits; return &scalar; }
extern struct record (*record_location(unsigned char));
struct record *record_location(unsigned char v) { records[0].value = v; return &records[0]; }
extern int (**pointer_location(void));
int **pointer_location(void) { return &scalar_pointer; }
static int accept(unsigned char v) { ++hits; return v + 3; }
static int (*global_callbacks[2])(unsigned char) = { accept, accept };
struct initialized_callbacks { int tag; int (*fns[2])(unsigned char); };
static struct initialized_callbacks initialized = { 73, { accept, accept } };
static signed char small(int v) { return v == 1 ? -117 : 83; }
static leaf factory(void) { ++hits; return accept; }
static int check_calls(void) {
    struct callbacks c;
    int i;
    int (*local[2])(unsigned char);
    int (*plain);
    int (**double_pointer);
    c.narrow[0] = accept;
    c.narrow[1] = accept;
    c.small[0] = small;
    c.small[1] = small;
    c.records[0] = record_location;
    c.records[1] = record_location;
    c.aliases[0] = record_location;
    c.aliases[1] = record_location;
    c.factories[0] = factory;
    c.factories[1] = factory;
    local[0] = accept;
    local[1] = accept;
    scalar = 91;
    scalar_pointer = &scalar;
    hits = 0;
    plain = location();
    double_pointer = pointer_location();
    if (plain != &scalar || double_pointer != &scalar_pointer || **double_pointer != 91 || hits != 1) return 1;
    i = 0;
    if (c.narrow[i++](298) != 45 || i != 1 || hits != 2) return 2;
    if ((*c.narrow[i++])(456) != 203 || i != 2 || hits != 3) return 3;
    i = 0;
    if (local[i++](263) != 10 || i != 1 || hits != 4) return 4;
    if ((*local[i++])(355) != 102 || i != 2 || hits != 5) return 5;
    if (c.small[0](1) != -117 || (*c.small[1])(2) != 83) return 6;
    if (c.records[0](293)->value != 37 || (*c.records[1])(275)->value != 19) return 7;
    if (c.aliases[0](309)->value != 53 || (*c.aliases[1])(337)->value != 81) return 8;
    if (c.factories[0]()(268) != 15 || hits != 7) return 9;
    if ((*c.factories[1])()(289) != 36 || hits != 9) return 10;
    if (accept(257) != 4 || hits != 10 || record_location(329)->value != 73) return 12;
    if (global_callbacks[0](271) != 18 || (*initialized.fns[1])(273) != 20 || hits != 12 || initialized.tag != 73) return 13;
    if (sizeof(c.narrow) != 16 || sizeof(c.records) != 16 || sizeof(c.factories) != 16 || sizeof(c) != 80) return 11;
    return 0;
}
static int check_loops(void) {
    int i;
    int j;
    int sum;
    int steps;
    int bodies;
    int n;
    int a[5];
    int *p;
    double condition;
    for (i = 0; i != 5; ) { a[i] = i; ++i; }
    sum = 0;
    for (i = 0; i < 5; /* ((( whitespace )) */ ) {
        ++i;
        if (i == 2) continue;
        if (i == 5) break;
        sum += i;
    }
    if (i != 5 || sum != 8) return 21;
    sum = 0;
    for (i = 0; i < 3;
         /* empty step followed by whitespace */
        ) {
        ++i;
        for (j = 0; j < 3; /* nested */ ) { ++j; if (j == 2) continue; sum += j; }
    }
    if (i != 3 || sum != 12) return 22;
    p = a + 5;
    sum = 0;
    for (; p != a; /* original spaces shape */ ) sum += *--p;
    if (sum != 10 || p != a) return 23;
    sum = 0;
    for (i = 5; --i >= 0; ) sum += a[i];
    if (sum != 10 || i != -1) return 24;
    bodies = 0;
    steps = 0;
    for (i = 5; i > 0; --i, ++steps) { ++bodies; if (i == 4) continue; if (i == 2) break; }
    if (i != 2 || bodies != 4 || steps != 3) return 25;
    bodies = 0;
    steps = 0;
    for (i = 0; i < 5; ++i, ++steps) { ++bodies; if (i == 1) continue; if (i == 3) goto end_loop; }
    return 26;
end_loop:
    if (i != 3 || bodies != 4 || steps != 3) return 27;
    n = 0;
    for ( ; ; /* indefinite */ ) { ++n; if (n == 4) break; }
    if (n != 4) return 28;
    condition = -0.0;
    for (i = 0; condition; ) ++i;
    if (i != 0) return 29;
    condition = 0.5;
    for (i = 0; condition; /* double truth */ ) { ++i; condition = 0.0; }
    if (i != 1) return 30;
    return 0;
}
int review_declarator_checks(void) {
    int result;
    result = check_calls();
    if (result) return result;
    return check_loops();
}
#ifndef REVIEW_DECLARATOR_NO_MAIN
int main(void) { return review_declarator_checks(); }
#endif
