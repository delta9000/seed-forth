/* A function's parameters and locals share one frame of 32 eight-byte
   slots (cc-frame-slots).  Two parameters and int[30] fill it exactly;
   the next local would sit below the frame, where pushes overwrite it.
   The compiler dies on its declaration instead. */
int f(int a, int b) {
  int full[30];
  int one_too_many;
  full[0] = a;
  one_too_many = b;
  return full[0] + one_too_many;
}
int main() {
  return f(1, 2);
}
