#include "binary64-arguments.h"
long seed_outbound(void){
 double (*fp)(double)=host_one;
 double (*vp)(long,double,long,double,...)=host_var;
 struct pair p={23,29};struct triple q={31,37,41};struct triple t;
 double x; long dynamic[5];
 if(host_mix(1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 10.25)!=3166.75)return 1;
 if(host_one(7)!=14.5)return 2;
 if(host_var(1L,2.5,3L,4.5,1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 28L, 10.25, 29L)!=313.5)return 3;
 if(vp(1L,2.5,3L,4.5,1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 28L, 10.25, 29L)!=313.5)return 4;
 if(host_over(1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 10.25,11.5,101L,13.5)!=3292.75)return 5;
 if(host_rollback(1,2.5,3,5,7,11,p,13.5,17,19.5)!=959.5)return 6;
 t=host_memory(3.5,p,q,5.5,7);if(t.a!=57||t.b!=71||t.c!=48)return 7;
 x=1.25+host_one(host_one(2.25))+fp(host_one(3.25));
 if(x!=26.25)return 8;
 if(host_one((int)fp(2.25))!=10.5)return 9;
 *dynamic=103;
 switch(*dynamic){case 103:if(1.5+host_mix(1.25, 20L, 2.25, 21L, 3.25, 22L, 4.25, 23L, 5.25, 24L, 6.25, 25L, 7.25, 26L, 8.25, 27L, 9.25, 10.25)!=3168.25)return 10;break;default:return 11;}
 if(*dynamic!=103)return 12;
 if(host_apply(seed_one,2.25)!=12.0)return 13;
 if(seed_knr(2.25)!=2.5)return 14;
 if(host_fp_first(1.25, 2.25, 3.25, 4.25, 5.25, 6.25, 7.25, 8.25, 9.25, 10.25,17,19)!=813.75)return 15;
 if(host_integer(7.75)!=7)return 16;
 return 0;
}

long seed_al_calls(void){
 long (*p)(long,...)=host_al;
 if(host_al(0)!=0)return 31;
 if(host_al(1,1.25)!=1)return 32;
 if(host_al(8,1.25,2.25,3.25,4.25,5.25,6.25,7.25,8.25)!=8)return 33;
 if(host_al(8,1.25,2.25,3.25,4.25,5.25,6.25,7.25,8.25,9.25,10.25)!=8)return 34;
 if(p(3,1.25,7L,2.25,3.25)!=3)return 35;
 return 0;
}
