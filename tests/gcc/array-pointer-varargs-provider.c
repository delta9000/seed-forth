#include <stdarg.h>
typedef long row[3];
typedef long (*action)(long);
long descriptor_gp(int last,...){va_list ap;action f;long n;va_start(ap,last);f=va_arg(ap,action);n=va_arg(ap,long);va_end(ap);return f(n);}
long descriptor_stack(long a,long b,long c,long d,long e,long last,...){va_list ap;action f;long n;va_start(ap,last);f=va_arg(ap,action);n=va_arg(ap,long);va_end(ap);return f(n)+a+b+c+d+e+last;}
long descriptor_array(int last,...){va_list ap;row *p;va_start(ap,last);p=va_arg(ap,row*);va_end(ap);return (*p)[2]+p[1][0];}
long descriptor_sse(int last,...){va_list ap;double x;action f;long n;va_start(ap,last);x=va_arg(ap,double);f=va_arg(ap,action);n=va_arg(ap,long);va_end(ap);return x==2.5?f(n):-1;}
long descriptor_unspecified(action f,long n,row *p){return f(n)+(*p)[1];}
