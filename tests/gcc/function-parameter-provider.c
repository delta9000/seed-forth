/* Function declarations in parameter lists adjust to function pointers. */
struct graph { int value; };
struct edge { int value; };
void fp_each(struct graph *, void (*)(struct graph *, struct edge *));
void fp_each(struct graph *g, void (callback)(struct graph *, struct edge *))
{
    struct edge e;
    e.value = 7;
    callback(g, &e);
}
int fp_apply(int (*)(int), int);
int fp_apply(int callback(int), int value) { return callback(value); }
int fp_group(int (*)(int), int);
int fp_group(int (callback)(int), int value)
{
    int (*copy)(int) = callback;
    if (sizeof callback != sizeof copy) return -1;
    if (sizeof &callback != sizeof &copy) return -2;
    return copy(value);
}
int fp_register(int (*)(int), int);
int fp_register(register int callback(register const int), int value)
{ return callback(value); }
int fp_old(int (*)(int), int);
int fp_old(callback, value) int callback(int); int value;
{ return callback(value); }
int fp_unspecified(int callback(), int value) { return callback(value); }
int fp_nested(int (*)(int (*)(int), int), int (*)(int), int);
int fp_nested(int callback(int nested(int), int), int nested(int), int value)
{ return callback(nested, value); }
char *fp_pointer(char *callback(char *), char *value)
{ return callback(value); }
double fp_double(double callback(double), double value)
{ return callback(value); }
long fp_many(long callback(long,long,long,long,long,long,long,long))
{ return callback(1,2,3,4,5,6,7,8); }
