/* No host headers or runtime: also compiled by Forth for the production proof. */
int ffs(int value);
static int expected(unsigned int value) {
  int bit;
  if (value == 0) return 0;
  bit = 1;
  while ((value & 1) == 0) { bit++; value >>= 1; }
  return bit;
}
int main(void) {
  unsigned int value;
  unsigned int i;
  for (i=0; i<100000; i++) {
    value = i * 2654435761U;
    if (ffs((int)value) != expected(value)) return 1;
  }
  for (i=0; i<32; i++) {
    value = 1U << i;
    if (ffs((int)value) != expected(value)) return 2;
  }
  return 0;
}
