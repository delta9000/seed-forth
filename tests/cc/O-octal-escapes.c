/* Octal literals (010 is 8), octal and hex escapes in character and string
   literals, and integer suffixes.  Exit 8 + 65 + 66 + 27 + 10 + 3 = 179. */
int main() {
  char* s = "\x41\102\033";
  int n = 010;
  if (s[0] != 'A') return 1;
  if (s[1] != 66) return 2;
  if ('\x1b' != 27) return 3;
  if ('\0' != 0) return 4;
  if (s[3] != 0) return 5;
  if (10UL != 10) return 6;
  return n + s[0] + s[1] + s[2] + 012 + 3L;
}
