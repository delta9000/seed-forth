/* helper is declared and called but never defined.  Its call's rel32 would
   stay 0 and fall through to the next instruction; the compiler dies at
   the end of the program instead, when no body has turned up. */
int helper(int x);
int main() {
  return helper(41);
}
