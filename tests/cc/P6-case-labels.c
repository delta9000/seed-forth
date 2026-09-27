/* Case labels are constant expressions: enum constants, character
   literals, negative numbers, macros and arithmetic.  Exit 1+2+4+8+16. */
enum kind { K_A = 3, K_B };
#define BASE 100
int classify(int v) {
  switch (v) {
    case K_B: return 1;
    case 'x': return 2;
    case -1: return 4;
    case BASE + 1: return 8;
    case (1 << 4) * 2 - 1: return 16;
    default: return 0;
  }
}
int main() {
  return classify(4) + classify(120) + classify(0 - 1) + classify(101) + classify(31);
}
