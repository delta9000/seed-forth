/* A static local keeps its value between calls.  It used to be an
   ordinary frame slot, so the count restarted (or picked up whatever the
   stack held).  bump() is called with other calls in between that reuse
   the stack; exit 3 only if the count survives them. */
int clobber(int a, int b, int c) { int x = 99; int y = 98; return a + b + c + x + y; }
int bump() {
  static int n = 0;
  static int hist[4];
  n = n + 1;
  hist[n] = n * 10;
  return n;
}
int main() {
  bump();
  clobber(7, 7, 7);
  bump();
  clobber(8, 8, 8);
  return bump();
}
