extern double floating_return(void);
void floating_parameter(double x);
struct Item { int first; long double second; double third; };
struct Item aggregate_return(void);
void aggregate_parameter(struct Item x);
int host_addresses(float *f, double *d, long double *ld, struct Item *item);
int check(void) {
 float f; double d; long double ld; struct Item item;
 if(sizeof(float)!=4 || sizeof(double)!=8 || sizeof(long double)!=16) return 1;
 if(sizeof(struct Item)!=48) return 2;
 if(sizeof(floating_return())!=8 || sizeof(aggregate_return())!=48) return 3;
 return host_addresses(&f,&d,&ld,&item);
}
