/* System V INTEGER-class long long interfaces shared by both object sides. */
#ifndef LONG_LONG_CHECK_H
#define LONG_LONG_CHECK_H

__extension__ typedef long long ll_t;
__extension__ typedef unsigned long long ull_t;

struct ll_pair { char tag; long long a; unsigned long long b; };
struct ll_bits { unsigned long long low : 24; long long high : 20; int rest; };

extern long long ll_table[4];
extern unsigned long long ull_global;
extern const char ll_layout[];

long long ll_add(long long a, long long b);
unsigned long long ull_mix(long a, unsigned long long b);
unsigned long long ll_mix(long long a, unsigned long b);
long long ll_div(long long a, long long b);
long long ll_mod(long long a, long long b);
unsigned long long ull_div(unsigned long long a, unsigned long long b);
unsigned long long ull_mod(unsigned long long a, unsigned long long b);
long long ll_shl(long long a, int s);
long long ll_sar(long long a, int s);
unsigned long long ull_shr(unsigned long long a, int s);
int ll_less(long long a, long long b);
int ull_less(unsigned long long a, unsigned long long b);
long long ll_sum(int count, ...);
unsigned long long ull_xor(int count, ...);
long long ll_many(long long a, long long b, long long c, long long d,
                  long long e, long long f, long long g, long long h);
long long ll_pair_total(const struct ll_pair *p);
struct ll_pair ll_pair_make(long long a, unsigned long long b);
unsigned long long ll_double_bits(long long a);
unsigned long long ull_double_bits(unsigned long long a);
long long ll_from_double(double d);
unsigned long long ull_from_double(double d);
long long ll_narrow(long long a);
long long ll_widen(int i, unsigned u, short s, unsigned char c);
long long ll_bits_read(struct ll_bits *b, unsigned long long low, long long high);
int ll_switch(long long a);
#endif
