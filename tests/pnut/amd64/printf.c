/* printf.c -- portable_libc's printf length modifiers and puts
   (patches/amd64/libc/05-puts-newline.diff, 06-printf-length.diff).
   Built by tcc-boot2 and, without the `long` cases (long is int in pnut),
   by pnut-exe with libc64.  Exit status is the number of failures;
   stdout must equal printf.out. */
#include <stdio.h>
#include <string.h>

int fails;
char buf[128];

void eq(char *want, int line) {
  if (strcmp(buf, want) != 0) {
    printf("FAIL line %d: got \"%s\", want \"%s\"\n", line, buf, want);
    fails += 1;
  }
}

int main() {
  long long big = 1;
  long long min = 1;
  unsigned long long umax = 0;
  big = big << 40;
  min = -(min << 62) - (min << 62);          /* -2^63 */
  umax = umax - 1;

  sprintf(buf, "%d %d %d %i", 42, -42, 0, -7);      eq("42 -42 0 -7", __LINE__);
  sprintf(buf, "%u", 4294967295u);                  eq("4294967295", __LINE__);
  sprintf(buf, "%x %x %o", 0xdeadbeef, -1, 8);      eq("deadbeef ffffffff 10", __LINE__);
  sprintf(buf, "[%5d|%-5d|%05d|%+d]", 42, 42, -42, 5); eq("[   42|42   |-0042|+5]", __LINE__);
  sprintf(buf, "%lld", big);                        eq("1099511627776", __LINE__);
  sprintf(buf, "%lld", -big);                       eq("-1099511627776", __LINE__);
  sprintf(buf, "%lld", min);                        eq("-9223372036854775808", __LINE__);
  sprintf(buf, "%llu", umax);                       eq("18446744073709551615", __LINE__);
  sprintf(buf, "%llx", umax - 0x0123456789abcdefULL); eq("fedcba9876543210", __LINE__);
  sprintf(buf, "%llo", umax);                       eq("1777777777777777777777", __LINE__);
  sprintf(buf, "%020lld", -big);                    eq("-0000001099511627776", __LINE__);
  sprintf(buf, "%d %lld %s %c", 1, big, "s", 'c');  eq("1 1099511627776 s c", __LINE__);
  sprintf(buf, "%lld %d", min, 3);                  eq("-9223372036854775808 3", __LINE__);
  sprintf(buf, "100%%");                            eq("100%", __LINE__);
#ifdef __TINYC__
  {
    long l = 1;
    unsigned long ul = 0;
    l = l << 40;
    ul = ul - 1;
    sprintf(buf, "%ld %ld", l, -l);                 eq("1099511627776 -1099511627776", __LINE__);
    sprintf(buf, "%lu %lx", ul, ul);                eq("18446744073709551615 ffffffffffffffff", __LINE__);
    sprintf(buf, "%ld %d", l, 5);                   eq("1099511627776 5", __LINE__);
  }
#endif
  puts("puts adds a newline");
  puts("");
  printf("printf: %d failures\n", fails);
  return fails;
}
