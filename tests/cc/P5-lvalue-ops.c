/* Compound assignment, ++ and -- on every kind of lvalue: a global, an
   array element, a struct field through a pointer, a char through a char*
   and a pointer target.  Exit 15 + 9 + 6 + 8 + 4 + 4 = 46 (the char
   holds 260 mod 256 = 4). */
struct box { int n; };
int g = 10;
int arr[4];
int main() {
  struct box* b = calloc(1, sizeof(struct box));
  char* s = calloc(4, 1);
  int* p = calloc(1, 8);
  int old;
  g += 5; g -= 1; g *= 2; g /= 4; g <<= 2; g >>= 1; g |= 1; g ^= 2;
  arr[1] = 3; arr[1] += 4; arr[1]++; ++arr[1];
  b->n = 1; b->n <<= 3; old = b->n--; --b->n;
  s[0] = 250; s[0] += 10;
  *p = 7; *p %= 4; (*p)++;
  g++; ++g;
  return g + arr[1] + b->n + old + s[0] + *p;
}
