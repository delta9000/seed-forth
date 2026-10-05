struct graph { int value; };
struct edge { int value; };
void fp_each(struct graph *, void (*)(struct graph *, struct edge *));
int fp_apply(int (*)(int), int);
int fp_group(int (*)(int), int);
int fp_register(int (*)(int), int);
int fp_old(int (*)(int), int);
int fp_unspecified(int (*)(), int);
int fp_nested(int (*)(int (*)(int), int), int (*)(int), int);
char *fp_pointer(char *(*)(char *), char *);
double fp_double(double (*)(double), double);
long fp_many(long (*)(long,long,long,long,long,long,long,long));
void visit(struct graph *g, struct edge *e) { g->value += e->value; }
int add(int value) { return value + 3; }
char *next(char *value) { return value + 1; }
double half(double value) { return value / 2.0; }
long sum(long a,long b,long c,long d,long e,long f,long g,long h)
{ return a+b+c+d+e+f+g+h; }
int main(void)
{
    struct graph g;
    char text[3];
    g.value=5; fp_each(&g,visit);
    if(g.value!=12) return 1;
    if(fp_apply(add,4)!=7) return 2;
    if(fp_group(add,5)!=8) return 3;
    if(fp_register(add,6)!=9) return 4;
    if(fp_old(add,7)!=10) return 5;
    if(fp_unspecified(add,8)!=11) return 6;
    if(fp_nested(fp_apply,add,9)!=12) return 7;
    if(fp_pointer(next,text)!=text+1) return 8;
    if(fp_double(half,7.0)!=3.5) return 9;
    if(fp_many(sum)!=36) return 10;
    return 0;
}
