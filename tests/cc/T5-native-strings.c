/* Decode each piece, concatenate without intermediate terminators, and retain
   the decoded array length for sizeof and direct postfix operations. */
#define ENDING "c" "d"
char *global_text = "a" "b" ENDING;
char *text(void) { return "a" "b" "cd"; }
int check(char *s, int marker) {
  if (marker != 7) return 1;
  if (s[0] != 'a' || s[1] != 'b' || s[2] != 'c' || s[3] != 'd') return 2;
  if (s[4] != 0) return 3;
  return 0;
}
int main(void) {
  char *s = "a\n" "\x42" "\103";
  if (check("a" "b" /* between pieces */ ENDING, 7)) return 1;
  if (check(global_text, 7) || check(text(), 7)) return 2;
  if (sizeof("a\n" "\x42" "\103") != 5) return 3;
  if (s[0] != 'a' || s[1] != '\n' || s[2] != 'B' || s[3] != 'C' || s[4]) return 4;
  if (("a" "bc")[2] != 'c' || "a" "bc"[1] != 'b') return 5;
  if (sizeof("x\0" "y") != 4 || "x\0" "y"[2] != 'y') return 6;
  if (sizeof("" "" "") != 1 || sizeof("" "z" "") != 2) return 7;
  if ("\1" "2"[0] != 1 || "\1" "2"[1] != '2') return 8;
  if ("\x4" "1"[0] != 4 || "\x4" "1"[1] != '1') return 9;
  return 0;
}
