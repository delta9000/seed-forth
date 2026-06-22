/* int is 64-bit in this compiler, but integer literals were always loaded
   with `mov rdi, imm32`, which sign-extends a 32-bit field.  0x80000000
   (2147483648) has bit 31 set, so it loaded as the negative
   -2147483648 — and 2^32 truncated to 0.  Dividing the constant by
   306783378 should give 7 (306783378*7 = 2147483646 <= 2147483648); the
   sign-extended value gives -7, i.e. exit 249.  With imm64 widening it is 7. */
int main() {
  int x;
  x = 2147483648;
  return x / 306783378;
}
