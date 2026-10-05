/* `sizeof (expr)` followed by postfix operators.  A parenthesised
   expression is only the primary of sizeof's unary operand, so
   `sizeof (a)[0]` is sizeof ((a)[0]), not (sizeof (a))[0].  The first
   loop is the shape of binutils 2.30 bfd/peicode.h's jump-table scan
   (`ARRAY_SIZE (jtab)` expands to `sizeof (jtab) / sizeof (jtab)[0]`).  */
#include <stdio.h>

struct jump { unsigned int size; const unsigned char *data; unsigned int offset; };
static const unsigned char x86[] = { 0xff, 0x25, 0, 0, 0, 0, 0x90, 0x90 };
static const struct jump jtab[] = {
  { 0, 0, 0 }, { 8, x86, 2 }, { 0, 0, 0 }
};
struct node { struct node *next; char tag[5]; long n; };
static struct node chain[2] = { { &chain[1], "abc", 1 }, { 0, "de", 2 } };
static int matrix[3][7];

/* Constant-expression contexts take the same route. */
static char sized[sizeof (jtab)[0]];
static int count = sizeof (jtab) / sizeof (jtab)[0];
enum { ROW = sizeof (matrix)[1] / sizeof (matrix)[0][0] };

static long f(long v) { return v * 2; }

int main(void)
{
  int i, found = -1;
  struct node *p = chain;
  long (*fp)(long) = f;
  for (i = (sizeof (jtab) / sizeof (jtab)[0]); i--;)
    {
      if (jtab[i].size == 0)
        continue;
      found = i;
    }
  printf("%d %d %d %d\n", found, (int)sizeof sized, count, (int)ROW);
  printf("%d %d %d %d %d\n", (int)sizeof (p)->tag, (int)sizeof (p)->next->n,
         (int)sizeof (chain[0]).tag[0], (int)sizeof (matrix)[2],
         (int)sizeof (matrix[1])[0]);
  printf("%d %d %d\n", (int)sizeof (fp)(3), (int)sizeof (chain), (int)sizeof (int));
  /* The operand is not evaluated, even through postfix ++. */
  i = 4;
  printf("%d %d\n", (int)sizeof (i)++, i);
  return found != 1 || count != 3;
}
