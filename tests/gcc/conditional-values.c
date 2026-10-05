#include "conditional-values.h"
double choose_di(int c,double x,int y) { return c?x:y; }
double choose_id(int c,int x,double y) { return c?x:y; }
double choose_fd(int c,float x,double y) { return c?x:y; }
double choose_df(int c,double x,float y) { return c?x:y; }
float choose_fi(int c,float x,int y) { return c?x:y; }
float choose_if(int c,int x,float y) { return c?x:y; }
float choose_fu(int c,float x,unsigned long y) { return c?x:y; }
float choose_uf(int c,unsigned long x,float y) { return c?x:y; }
double choose_du(int c,double x,unsigned long y) { return c?x:y; }
double choose_ud(int c,unsigned long x,double y) { return c?x:y; }
unsigned long choose_iu(int c,int x,unsigned int y) { return c?x:y; }
long choose_li(int c,long x,unsigned int y) { return c?x:y; }
double choose_nested(int a,int b,float x,int y,double z) { return a ? (b?x:y) : (b?y:z); }
int conditional_lazy(void) {
  int c; int yes; int no; int *bad; double d;
  c=0; yes=0; no=0; bad=0;
  d=(++c ? (++yes,4.5) : (++no,*bad));
  if(c!=1 || yes!=1 || no!=0 || d!=4.5) return 1;
  d=(c++==0 ? (++yes,*bad) : (++no,42));
  if(c!=2 || yes!=1 || no!=1 || d!=42.0) return 2;
  d=(0 ? *bad : (1 ? 42 : *bad));
  if(d!=42.0) return 3;
  c=0; c ? (void)++yes : (void)++no;
  return yes==1 && no==2 ? 0 : 4;
}
static int conditional_identity(int n) { return n; }
int conditional_pointers(void) {
  struct conditional_record s; struct conditional_record *p; void *v;
  int c; int a[2][3]; int (*row)[3]; int i; int (*fp)(int);
  s.value=42; s.guard=99; p=&s; c=0; v=0;
  if((c?(void*)0:p)->value!=42) return 1;
  if((c?p:(void*)0)!=0) return 2;
  if((c?0L:p)->guard!=99) return 3;
  if((c?p:(int)0)!=0) return 4;
  if((c?(void*)(long)0:p)->value!=42) return 5;
  if((c?p:(void*)(unsigned int)0)!=0) return 6;
  if((c?(void*)0:(c?0:p))->value!=42) return 7;
  if((c?p:v)!=0 || (c?v:p)!=(void*)p) return 8;
  if((1?p:v)!=(void*)p || (1?v:p)!=0) return 9;
  row=a; a[1][2]=42;
  if((c?(void*)0:row)[1][2]!=42) return 10;
  if((c?row:(void*)0)!=0) return 11;
  i=42; if(*(c?0:&i)!=42 || *(c?&i:&i)!=42) return 12;
  if(sizeof(*(c?(void*)0:p))!=sizeof(s)) return 15;
  if((c?'\0':p)->value!=42 || (c?p:0UL)!=0) return 16;
  fp=c?(void*)0:conditional_identity; if(fp(42)!=42) return 13;
  fp=c?conditional_identity:(void*)0; if(fp!=0) return 14;
  return 0;
}
int conditional_aggregates(void) {
  struct conditional_record a; struct conditional_record b;
  int c;
  a.value=42; a.guard=99; b.value=12; b.guard=33; c=1;
  if((c?a:b).value!=42 || (0?a:b).guard!=33) return 1;
  if((c?(0?a:b):a).value!=12) return 2;
  return 0;
}
