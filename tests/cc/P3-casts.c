/* Casts: to int, to pointers of every kind, through a typedef, to a struct
   pointer (so -> finds the field), to char (keeps the low byte) and to
   void.  Exit 65 + 2 + 7 = 74. */
typedef int word;
struct pt { int x; int y; };
int main() {
  struct pt* p = calloc(1, sizeof(struct pt));
  int raw = (int) p;
  char* bytes = (char*) calloc(8, 1);
  bytes[0] = 65;
  ((struct pt*) raw)->y = 7;
  (void) 0;
  if ((word) 3 != 3) return 1;
  if ((char) 321 != 65) return 2;
  return *(char*) bytes + (int) (char) 258 + p->y;
}
