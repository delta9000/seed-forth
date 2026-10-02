/* Every dead arm is parsed, but none of its arithmetic is evaluated. */
#if (0 && (1 / 0)) || !(1 || (1 % 0))
#error wrong short circuit
#endif
#if (1 ? 7 : (1 / 0)) != 7
#error wrong selected arm
#endif
#if (0 ? (1 / 0) : (0 ? (1 / 0) : 9)) != 9
#error wrong nested selected arm
#endif
#if 0 && ((1 / 0) ? (1 / 0) : (1 / 0))
#error wrong outer short circuit
#endif
enum values {
  A = 0 && (1 / 0),
  B = 1 || (1 / 0),
  C = 1 ? 11 : (1 / 0),
  D = 0 ? (1 / 0) : 13,
  E = (0 && (1 / 0)) || (1 ? 17 : (1 / 0)),
  F = (1 || (1 / 0)) && (0 ? (1 / 0) : 19)
};
int main() {
  int a[1 ? 3 : (1 / 0)];
  a[2] = 5;
  if (A != 0 || B != 1 || C != 11 || D != 13 || E != 1 || F != 1) return 1;
  return a[2] - 5;
}
