/* const in every position, several declarators in one declaration (locals
   and globals, with and without initializers), types spelled with several
   keywords, empty statements, an empty loop body, and enum TAG as a type.
   Exit 1 + 0 + 2 + 10 + 3 + 4 + 6 + 10 + 4 + 5 + 7 - 10 = 42. */
enum color { RED, GREEN = 5, BLUE };
const int ga = 1, gb, *gp;
unsigned long gl = 7;
int sum(const int a, char * const s, const char *t) { return a + s[0] - t[0]; }
enum color pick(enum color c) { return c; }
unsigned int twice(unsigned long long x) { return x + x; }
int main() {
  int a = 2, b, c = 3;
  const int d = 4;
  enum color e = BLUE;
  unsigned char uc = 5;
  long long neg = -5;
  int i = 0;
  ;;
  b = 10;
  while (i < 5) i = i + 1;
  while (i++ < 9);
  for (;;) break;
  if (a) { ; }
  return ga + gb + a + b + c + d + pick(e) + i + sum(3, "b", "a") + uc + gl + twice(neg);
}
