/* Error 127: a parenthesised constant expression with no ')'. */
enum { A = (1 + 2 };
int main() {
  return 0;
}
