/* Bootstrap's private call ABI: >6 args, nested args, function pointers. */
int plus(int x, int y) { return x + y; }
int many(int a, int b, int c, int d, int e, int f, int g, int h) {
  return a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*h;
}
int *same(int *p) { return p; }
struct ops { int (*f)(int x, int y); };
int main() {
  int (*fp)(int x, int y);
  struct ops op;
  int a[2];
  fp = plus;
  op.f = plus;
  a[0] = 41; a[1] = 42;
  if (many(1, 2, 3, 4, 5, 6, 7, 8) != 204) return 1;
  if (many(plus(0,1), 2, 3, 4, 5, 6, 7, plus(4,4)) != 204) return 2;
  if (fp(5, 6) != 11 || (*fp)(7, 8) != 15 || op.f(9, 10) != 19) return 3;
  if (same(a)[1] != 42 || *(same(a) + 1) != 42) return 4;
  return 0;
}
