/* Array sizes are constant expressions (local, global and static), and
   global arrays far past the old 4 KiB globals area live in the bss:
   the ELF's file stays small.  Exit 42. */
#define N 10
enum { M = 3 };
int big[250000];
char text[100000];
int small[N * M];
int main() {
  int loc[2 + 2];
  big[249999] = 30;
  text[99999] = 5;
  small[N * M - 1] = 3;
  loc[3] = 4;
  return big[249999] + text[99999] + small[29] + loc[3];
}
