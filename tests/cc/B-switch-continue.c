/* Each odd iteration takes `continue` out of the switch, leaking 8 bytes
   of stack. ~2M leaks (16MB) exhaust any default-sized stack -> SIGSEGV.
   With the pop balanced, the loop runs to completion and returns 0. */
int main() {
  int i;
  i = 0;
  while (i < 4000000) {
    switch (i - ((i / 2) * 2)) {   /* i & 1, using supported ops */
      case 0: break;
      default: i = i + 1; continue;
    }
    i = i + 1;
  }
  return 0;
}
