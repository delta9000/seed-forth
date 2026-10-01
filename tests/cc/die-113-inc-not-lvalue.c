/* Error 113: prefix ++ / -- on something that isn't an lvalue. */
int main() {
  int x = 1;
  return ++(x + 1);
}
