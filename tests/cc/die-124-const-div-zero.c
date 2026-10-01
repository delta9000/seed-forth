/* Error 124: a constant expression divides by zero. */
int table[8 / (2 - 2)];
int main() {
  return 0;
}
