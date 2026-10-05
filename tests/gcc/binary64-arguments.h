#ifndef BINARY64_ARGUMENTS_H
#define BINARY64_ARGUMENTS_H
struct pair { long a,b; };
struct triple { long a,b,c; };
double seed_mix(double d0, long g0, double d1, long g1, double d2, long g2, double d3, long g3, double d4, long g4, double d5, long g5, double d6, long g6, double d7, long g7, double d8, double d9);
double host_mix(double d0, long g0, double d1, long g1, double d2, long g2, double d3, long g3, double d4, long g4, double d5, long g5, double d6, long g6, double d7, long g7, double d8, double d9);
double seed_one(double);
double host_one(double);
double seed_var(long,double,long,double,...);
double host_var(long,double,long,double,...);
double seed_over(double d0, long g0, double d1, long g1, double d2, long g2, double d3, long g3, double d4, long g4, double d5, long g5, double d6, long g6, double d7, long g7, double d8, double d9,...);
double host_over(double d0, long g0, double d1, long g1, double d2, long g2, double d3, long g3, double d4, long g4, double d5, long g5, double d6, long g6, double d7, long g7, double d8, double d9,...);
double seed_rollback(long,double,long,long,long,long,struct pair,double,long,double);
double host_rollback(long,double,long,long,long,long,struct pair,double,long,double);
struct triple seed_memory(double,struct pair,struct triple,double,long);
struct triple host_memory(double,struct pair,struct triple,double,long);
double seed_echo(double);
double seed_knr();
double host_apply(double (*)(double),double);
long host_al(long,...);
long seed_al_calls(void);
double seed_fp_first(double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9,long,long);
double host_fp_first(double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9,long,long);
double seed_stack_echo(double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9);
long host_integer(long);
long seed_outbound(void);
#endif
