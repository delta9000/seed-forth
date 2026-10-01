/* Function-like and object-like macros with any body: arguments are
   expanded before they are substituted, the result is scanned again,
   a macro is not expanded inside itself, a call may span lines, and an
   argument can hold parentheses and commas inside them.  Exit
   6 + 6 + 3 + 5 + 12 - 2 = 30. */
#define ADD(a, b) ((a) + (b))
#define TWICE(x) ADD(x, x)
#define NEG -1
#define SELF SELF
#define PICK(c, t, f) (((c) != 0) * (t) + ((c) == 0) * (f))
#define STR "macro"
int SELF = 5;
int f(int a, int b) { return a * b; }
int main() {
  int x = TWICE(ADD(1, 2));
  int y = PICK(x == 6,
               f(2, 3),
               100);
  int z = 2-NEG;
  if (STR[0] != 'm') return 1;
  return x + y + z + SELF + ADD(f(3, 4), 0) - 2;
}
