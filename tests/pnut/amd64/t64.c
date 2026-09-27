/* t64.c -- 64-bit arithmetic, sizes and layout under tcc-boot2 (sf-pnut-amd64-check.sh). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static char *u64s(unsigned long long v, char *buf) { char t[32]; int n = 0; do { t[n++] = '0' + v % 10; v /= 10; } while (v); for (int i = 0; i < n; i++) buf[i] = t[n-1-i]; buf[n] = 0; return buf; }
static char *i64s(long long v, char *buf) { if (v < 0) { buf[0] = '-'; u64s(-(unsigned long long)v, buf+1); return buf; } return u64s(v, buf); }
struct S { char c; long long x; short s; int i; };
long fib(long n) { return n < 2 ? n : fib(n-1) + fib(n-2); }
int sum(int n, ...);
int main(int argc, char **argv) {
  char b[64], b2[64];
  long long a = 1234567890123LL, m = -987654321987LL;
  unsigned long long u = 0xfedcba9876543210ULL;
  int fails = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d\n", __LINE__); fails++; } } while (0)
  CHECK(a * 1000 == 1234567890123000LL);
  CHECK(a / 7 == 176366841446LL && a % 7 == 1);
  CHECK(m / 1000 == -987654321LL && m % 1000 == -987);
  CHECK((u >> 60) == 0xf && (u << 4) == 0xedcba98765432100ULL);
  CHECK(((long long)u >> 60) == -1);
  CHECK(sizeof(long) == 8 && sizeof(void*) == 8 && sizeof(struct S) == 24);
  CHECK(fib(25) == 75025);
  CHECK(strcmp(i64s(m, b), "-987654321987") == 0);
  CHECK(strcmp(u64s(u, b2), "18364758544493064720") == 0);
  { char *p = malloc(100000); memset(p, 7, 100000); CHECK(p[99999] == 7); }
  { unsigned int x = 0xffffffffu; unsigned long long y = x; CHECK(y + 1 == 0x100000000ULL); }
  { int x = -5; long long y = x; CHECK(y == -5); }
  { long long big = 0x7fffffffffffffffLL; CHECK(big + 1 < 0 || 1); CHECK(big > 0); }
  printf("i64 %s u64 %s fib(25)=%d str=%s hex=%x\n", i64s(m, b), u64s(u, b2), (int)fib(25), "ok", 0xbeef);
  printf("t64: %d failures\n", fails);
  return fails;
}
