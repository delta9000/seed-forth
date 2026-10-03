#ifndef AGGREGATE_LAYOUT_H
#define AGGREGATE_LAYOUT_H
struct One {signed char a;};
struct Three {char a[3];};
struct Pad {char a; int b;};
struct Pair {long a; long b;};
struct Tail {long a;char b;};
struct Large {long a;long b;long c;};
struct Nested {struct Pad p; short a[3];};
struct Bits {unsigned a:3; int b:9; unsigned long c:32;};
union Either {struct Pair p;char bytes[16];};
struct One agg_one(struct One,long);
struct Three agg_three(struct Three);
struct Pad agg_pad(struct Pad);
struct Pair agg_pair(struct Pair,long);
struct Tail agg_tail(struct Tail);
struct Large agg_large(struct Large,long);
struct Nested agg_nested(struct Nested);
struct Bits agg_bits(struct Bits);
union Either agg_union(union Either);
long agg_rollback(long,long,long,long,long,struct Pair,long,struct Three,long);
struct Large agg_shift(long,long,long,long,long,struct Pair,long,struct Large);
long agg_caller(void);
struct Pair host_pair(struct Pair,long);
struct Large host_large(struct Large,long);
long host_rollback(long,long,long,long,long,struct Pair,long,struct Three,long);
/* The following records have no natural requirement for eight-byte alignment. */
struct Nine {char a[9];};
struct Three agg_read_three(struct Three *);
struct Nine agg_read_nine(struct Nine *);
double agg_double(struct Pair);
#endif
