/* Declaration specifiers in any C90 order, and casts that consume a
   qualified array.  Built by the Forth driver and by host GCC; the two
   programs must print the same lines.  */
#include <stdio.h>

typedef unsigned int word_t;
typedef unsigned long size_type;

/* File scope: qualifiers between, before and after type keywords.  */
unsigned const char file_uc = 250;
long const int file_li = -123456L;
const unsigned long file_ul = 4000000000UL;
static const unsigned file_su = 77;
volatile unsigned short file_vus = 65535;
char const *file_text = "zlib";
int const long volatile unsigned file_mixed = 9;
long unsigned const long file_ull = 3;
short volatile signed file_ss = -7;
signed const char file_sc = -100;
word_t const file_wt = 11;
const word_t file_cwt = 12;
size_type const *const file_ptr = 0;

/* A qualified two-dimensional table, as in zlib's crc32.c.  */
static const word_t table[2][4] = {
  { 0x10u, 0x20u, 0x30u, 0x40u },
  { 0x50u, 0x60u, 0x70u, 0x80u }
};
static const unsigned char bytes[2][3][2] = {
  { { 1, 2 }, { 3, 4 }, { 5, 6 } },
  { { 7, 8 }, { 9, 10 }, { 11, 12 } }
};

/* Aggregate members.  */
struct record {
  unsigned const char tag;
  long volatile int count;
  word_t const value;
  const word_t *table;
  short const unsigned narrow;
};

/* Storage classes among the type specifiers: C90 6.5 sets no order.  */
int static file_static_int = 21;
long static int file_static_long = -22;
char const static *file_static_text = "order";
unsigned extern long file_extern_ulong;
unsigned long file_extern_ulong = 23;
int typedef file_int_t;
file_int_t const static file_typedef_value = 24;
struct record static file_record = { 7, 0, 0, 0, 8 };
word_t static file_word = 25;

static unsigned long
next_id(void)
{
  unsigned long static id;
  long register int step = 1;
  return id += step;
}

/* Parameters, including register in between.  */
static unsigned long
sum(unsigned const char *p, register unsigned const n, word_t const bias,
    long const unsigned scale)
{
  unsigned long total = bias;
  unsigned i;
  for (i = 0; i < n; i++)
    total += (unsigned long) p[i] * scale;
  return total;
}

/* Prototype-only parameter spellings.  */
int declared(char const *, unsigned volatile short, word_t const *const);

static const word_t *
get_table(void)
{
  return (const word_t *) table;
}

int
main(void)
{
  /* Block scope.  */
  unsigned const char local[4] = { 1, 2, 3, 250 };
  unsigned const char *q = local;
  long volatile int counter = 0;
  static short const unsigned limit = 40000;
  struct record r = { 200, 0, 0x1234u, 0, 65000 };
  const word_t *row;
  const unsigned char *flat;
  word_t const *const *pp;
  const word_t *one = (const word_t *) table;

  counter += file_li;
  r.table = get_table();
  row = (word_t const *) table;
  flat = (const unsigned char *) bytes;
  pp = &one;

  printf("file %u %ld %lu %u %u %s %u %lu %d %d %u %u\n",
         (unsigned) file_uc, file_li, file_ul, file_su, (unsigned) file_vus,
         file_text, (unsigned) file_mixed, (unsigned long) file_ull, (int) file_ss,
         (int) file_sc, file_wt, file_cwt);
  printf("block %u %u %ld %u\n", (unsigned) q[3], (unsigned) q[0],
         (long) counter, (unsigned) limit);
  printf("record %u %ld %u %u %u\n", (unsigned) r.tag, (long) r.count,
         r.value, r.table[5], (unsigned) r.narrow);
  printf("sum %lu\n", sum(local, 4, 5, 3));
  printf("table %u %u %u %u\n", get_table()[0], row[3], row[7], (*pp)[6]);
  printf("bytes %u %u %u\n", (unsigned) flat[0], (unsigned) flat[7],
         (unsigned) flat[11]);
  printf("void %u\n", ((const word_t *) (const void *) table)[4]);
  printf("sizes %lu %lu %lu %lu %lu %lu %lu %lu %lu\n",
         (unsigned long) sizeof(unsigned const char),
         (unsigned long) sizeof(long const int),
         (unsigned long) sizeof(short volatile unsigned),
         (unsigned long) sizeof(const word_t *),
         (unsigned long) sizeof(word_t const *),
         (unsigned long) sizeof(const word_t *const *),
         (unsigned long) sizeof(volatile word_t *),
         (unsigned long) sizeof(word_t const),
         (unsigned long) sizeof(double const long));
  printf("casts %u %d %lu %u\n", (unsigned) (unsigned const char) 300,
         (int) (signed const char) 200, (unsigned long) (long const unsigned) -1,
         (unsigned) *(volatile word_t *) &table[1][1]);
  printf("pointers %d %d\n", file_ptr == 0, (char const *) 0 == 0);
  {
    short typedef local_t;
    local_t const static local_value = 26;
    unsigned auto int local_auto = 27;
    next_id();
    printf("storage %d %ld %s %lu %d %u %u %u %lu %d %u\n", file_static_int,
           file_static_long, file_static_text, file_extern_ulong,
           (int) file_typedef_value, (unsigned) file_record.tag,
           (unsigned) file_record.narrow, file_word, next_id(),
           (int) local_value, local_auto);
  }
  return 0;
}

int
declared(char const *s, unsigned volatile short n, word_t const *const p)
{
  return s[0] + n + (int) p[0];
}
