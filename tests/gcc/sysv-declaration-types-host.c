#include <stdint.h>
struct Item { int first; long double second; double third; };
int host_addresses(float *f,double *d,long double *ld,struct Item *item) {
 if((uintptr_t)ld%16 || (uintptr_t)item%16) return 4;
 *f=1.5f; *d=2.5; *ld=3.5L; item->second=4.5L;
 return *f!=1.5f || *d!=2.5 || *ld!=3.5L || item->second!=4.5L;
}
int check(void);
int main(void){return check();}
