/* Forth-only driver: no long double arithmetic, values from explicit bytes. */
#include <stdio.h>
#include <string.h>
#include "long-double.h"
#include "long-double-values.h"

static int failures;
#define CHECK(c, what) do { if (!(c)) { printf("FAIL %s\n", what); failures++; } } while (0)
/* GCC's x86-64 LP64 layout, as host-checked by long-double-main.c. */
static const long expect[18] = {16, 16, 16, 32, 48, 16, 32, 16, 16, 32, 16, 80, 16, 32, 64, 16, 48, 8};

int main(void)
{
  long double v[LD_VALUES], out[8], r;
  long layout[32], i;
  union ld_bfd_args args[9];
  struct ld_pad p, q;
  struct ld_one o;
  union ld_mix m;
  struct ld_pair pr;
  struct ld_nest nest;
  int dummy;

  ld_values(v);
  CHECK(seed_layout(layout) == 18, "layout count");
  for (i = 0; i < 18; i++) CHECK(layout[i] == expect[i], "layout value");
  for (i = 0; i < LD_VALUES; i++) {
    r = seed_id(v[i]); CHECK(host_same(&r, &v[i]), "seed_id");
    r = seed_cast(v[i]); CHECK(host_same(&r, &v[i]), "seed_cast");
    r = seed_ternary(1, v[i], v[0]); CHECK(host_same(&r, &v[i]), "seed_ternary true");
    r = seed_ternary(0, v[0], v[i]); CHECK(host_same(&r, &v[i]), "seed_ternary false");
  }
  for (i = 0; i < 3; i++) { r = seed_array(v, i); CHECK(host_same(&r, &v[i]), "seed_array"); }
  r = seed_pick(3, v[0], 2.5, v[1], 77, v[2]); CHECK(host_same(&r, &v[0]), "pick named double/long");
  r = seed_many(1, 2, 3, 4, 5, 6, v[5], 7, v[6]); CHECK(host_same(&r, &v[5]), "many x");
  r = seed_va(4, v[0], v[1], v[2], v[3], v[4], v[5], v[6]); CHECK(host_same(&r, &v[4]), "va 4");
  r = seed_va_named(v[3], 0); CHECK(host_same(&r, &v[3]), "va named only");
  r = seed_va_named(v[3], 7, 0, v[1], 1, v[2], 2, v[3], 3, v[4], 4, v[5], 5, v[6], 6, v[0]);
  CHECK(host_same(&r, &v[0]), "va after named long double");
  memset(out, 0, sizeof out);
  seed_va_list(out, 16, 0, 0, 2, v[0], 1, 2.5, 2, v[1], 3, 4000L, 1, 5.5, 1, 6.5, 2, v[2],
               1, 8.5, 1, 9.5, 1, 10.5, 2, v[5], 1, 12.5, 1, 13.5, 0, 14, 2, v[6]);
  CHECK(host_same(&out[0], &v[0]) && host_same(&out[1], &v[1]) && host_same(&out[2], &v[2])
        && host_same(&out[3], &v[5]) && host_same(&out[4], &v[6]), "tagged va_list");
  memset(args, 0, sizeof args);
  seed_bfd("iDlLdDpD", args, -7, v[0], 123456789012L, -5LL, 0.25, v[5], &dummy, v[6]);
  CHECK(args[0].i == -7 && host_same(&args[1].ld, &v[0]) && args[2].l == 123456789012L
        && args[3].ll == -5 && args[4].d == 0.25 && host_same(&args[5].ld, &v[5])
        && args[6].p == &dummy && host_same(&args[7].ld, &v[6]), "bfd union va_arg");
  p.c = 'q'; p.x = v[0]; p.k = 9;
  q = seed_pad(p, v[6]); CHECK(q.c == 'q' && q.k == 10 && host_same(&q.x, &v[6]), "pad");
  o.x = v[1]; o = seed_one(o); CHECK(host_same(&o.x, &v[1]), "X87 record return");
  m.x = v[2]; m = seed_mix(m); CHECK(host_same(&m.x, &v[2]), "mixed union MEMORY");
  pr.a = v[3]; pr.b = v[4];
  pr = seed_pair(v[0], pr, v[5]); CHECK(host_same(&pr.a, &v[5]) && host_same(&pr.b, &v[3]), "pair");
  memset(&nest, 0, sizeof nest);
  nest.o.x = v[1]; nest.m[0].x = v[5]; nest.m[1].x = v[6];
  r = seed_nest(&nest, 1); CHECK(host_same(&r, &v[6]), "nest m[1]");
  r = seed_nest(&nest, 2); CHECK(host_same(&r, &v[5]), "nest m[0]");
  r = seed_knr(v[3], 1); CHECK(host_same(&r, &v[3]), "identifier-list definition");
  i = seed_init(v); if (i) { printf("FAIL init %ld\n", i); failures++; }
  i = seed_outbound(v); if (i) { printf("FAIL outbound %ld\n", i); failures++; }
  if (failures) return 1;
  puts("long double Forth-only ok");
  return 0;
}
