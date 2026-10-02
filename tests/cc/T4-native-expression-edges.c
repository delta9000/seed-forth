/* Native result types, promotion, unevaluated operands and array rows. */
int never_defined(int x);
enum sizes { ELEMENT = sizeof(int), ROW = sizeof(char[4]) };
int main() {
  int x = 0;
  int y = 3;
  char c = -5;
  unsigned int u = 0xffffffffU;
  unsigned long z;
  char rows[3][4];
  if (ELEMENT != 4 || ROW != 4) return 1;
  if (sizeof(x && y) != 4 || sizeof(x || y) != 4 || sizeof(!x) != 4) return 2;
  if (sizeof(+c) != 4 || sizeof(-c) != 4 || sizeof(~c) != 4) return 3;
  if (+c != -5 || -c != 5 || ~c != 4) return 4;
  if ((long)(x ? 0U : -1) != 4294967295L) return 5;
  if (u / 3 != 1431655765U || u >> 31 != 1 || u < 1) return 6;
  if (sizeof(never_defined(1)) != 4 || sizeof(x++) != 4 || x != 0) return 7;
  rows[0][0] = 11; rows[1][0] = 22; rows[2][3] = 33;
  if (rows[1][0] != 22 || rows[2][3] != 33) return 8;
  if ((rows + 1)[0][0] != 22 || (1 + rows)[1][3] != 33 || (rows + 2) - rows != 2) return 13;
  if ((x ? rows : rows + 1)[0][0] != 22) return 14;
  if (sizeof rows != 12 || sizeof rows[0] != 4) return 9;
  if ((x = 2, y = 4, x + y) != 6) return 10;
  for (x = 0, y = 0; x < 4; x++, y += 2) { }
  if (y != 8) return 11;
  z = (1 ? (x = 1, 5U) : 7U);
  if (z != 5 || x != 1) return 12;
  return 0;
}
