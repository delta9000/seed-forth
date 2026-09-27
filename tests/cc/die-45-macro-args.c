/* Error 45: a function-like macro called with more arguments than it has
   parameters. */
#define ADD(a, b) ((a) + (b))
int main() {
  return ADD(1, 2, 3);
}
