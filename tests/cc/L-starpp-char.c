/* *s++ on a char* loads one byte.  The postfix ++ dropped the operand's
   type, so the * loaded eight.  Also *++s and a (char*) pointer walk. */
int main() {
  char* s = "abc";
  int a = *s++;
  int b = *s++;
  int c = *++s;
  if (a != 97) return 1;
  if (b != 98) return 2;
  if (c != 0) return 3;
  return a + b - 150;
}
