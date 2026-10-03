#include <string.h>
#include <stdio.h>
#include "bitfield-layout.h"
int main(void){int i;long v;double d=12.75;struct A a,pa;struct B b,pb;struct C c,pc;union U u,pu;struct N n,pn;
 if(prod_layout()!=sizeof(struct A)+sizeof(struct B)*100+sizeof(struct C)*10000+sizeof(struct D)*1000000+sizeof(struct E)*10000000){printf("layout %d expected %ld A%ld B%ld C%ld D%ld E%ld\n",prod_layout(),sizeof(struct A)+sizeof(struct B)*100+sizeof(struct C)*10000+sizeof(struct D)*1000000+sizeof(struct E)*10000000,sizeof(a),sizeof(b),sizeof(c),sizeof(struct D),sizeof(struct E));return 1;}
 if(!prod_typed(&d)){puts("typed");return 9;}
 if(!prod_init()){puts("init");return 2;}
 for(i=0;i<1000;i++){v=(i*1234567L+421)*32768-12982173;
 memset(&a,i,sizeof a);pa=a;DO_A(&a,v);prod_a(&pa,v);if(memcmp(&a,&pa,sizeof a)){printf("A %d\n",i);return 3;}
 memset(&b,i,sizeof b);pb=b;DO_B(&b,v);prod_b(&pb,v);if(memcmp(&b,&pb,sizeof b)){printf("B %d\n",i);return 4;}
 memset(&c,i,sizeof c);pc=c;DO_C(&c,v);prod_c(&pc,v);if(memcmp(&c,&pc,sizeof c)){printf("C %d\n",i);return 5;}
 memset(&u,i,sizeof u);pu=u;DO_U(&u,v);prod_u(&pu,v);if(memcmp(&u,&pu,sizeof u)){printf("U %d\n",i);return 6;}
 memset(&n,i,sizeof n);pn=n;DO_N(&n,v);prod_n(&pn,v);if(memcmp(&n,&pn,sizeof n)){printf("N %d\n",i);return 7;}
 }
 a.a=7;a.b=-2;c.c=-999;
 if(prod_read(&a,&c)!=7-2-999+23+29+37||a.a!=0||a.b!=-1){puts("read");return 8;}
 puts("PASS: bitfield ABI/layout/neighbor preservation across 5000 mutations, local/static initializers and value promotions");return 0;}
