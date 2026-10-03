int add(int a, int b) { return a + b; }
long eighth(long a, long b, long c, long d, long e, long f, long g, long h) {
  return a + b*2 + c*3 + d*4 + e*5 + f*6 + g*7 + h*8;
}
signed char narrow(signed char x) { return x; }
long recurse(long n) { if (n == 0) return 0; return n + recurse(n-1); }
int main(int argc, char **argv) {
  int (*fp)(int, int); fp = add;
  if (argc != 1 || argv[0] == 0) return 1;
  if (add(20, 22) != 42) return 2;
  if (eighth(1,2,3,4,5,6,7,8) != 204) return 3;
  if (eighth(add(1,2),2,3,4,5,6,7,add(3,5)) != 206) return 4;
  if (fp(20,22) != 42 || (*fp)(19,23) != 42) return 5;
  if (narrow(255) != -1) return 6;
  if (recurse(10) != 55) return 7;
  return 0;
}
