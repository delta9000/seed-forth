#include "binary64-arguments.h"
int main(void){
 double (*fp)(double)=seed_one;
 struct pair p={23,29};struct triple q={31,37,41};struct triple t;
 if(seed_mix(1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 10.25)!=3166.75)return 21;
 if(fp(-0.25)!=0.0)return 22;
 if(seed_var(1L,2.5,3L,4.5,1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 28L, 10.25, 29L)!=313.5)return 23;
 if(seed_over(1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 10.25,11.5,101L,13.5)!=3292.75)return 24;
 if(seed_rollback(1,2.5,3,5,7,11,p,13.5,17,19.5)!=959.5)return 25;
 t=seed_memory(3.5,p,q,5.5,7);if(t.a!=57||t.b!=71||t.c!=48)return 26;
 {
  union {double d;unsigned long u;} a,b;
  a.u=0x8000000000000000UL;b.d=seed_echo(a.d);if(a.u!=b.u)return 27;
  a.u=0x7ff8123456789abcUL;b.d=seed_echo(a.d);if(a.u!=b.u)return 28;
  a.u=1;b.d=seed_echo(a.d);if(a.u!=b.u)return 29;
  a.u=0x7ff8123456789abcUL;b.d=seed_stack_echo(1,2,3,4,5,6,7,8,9,a.d);if(a.u!=b.u)return 30;
 }
 if(seed_fp_first(1.25, 2.25, 3.25, 4.25, 5.25, 6.25, 7.25, 8.25, 9.25, 10.25,17,19)!=813.75)return 36;
 if(seed_al_calls())return seed_al_calls();
 return seed_outbound();
}
