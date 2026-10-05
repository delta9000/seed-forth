/* Qualified arrays decay like any other array: the qualifier moves onto
   the pointed-to type.  Built by the Forth driver and by host GCC; the two
   programs must print the same lines.  */
#include <stdio.h>

typedef unsigned int word_t;

/* binutils elflink.c reads a relocation's offset through a const record.  */
typedef struct { unsigned char r_offset[4]; unsigned char r_info[4]; } ext_rel;

static const long matrix[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } };
static volatile long vmatrix[2][3] = { { 7, 8, 9 }, { 10, 11, 12 } };
static const unsigned char cube[2][3][2] = {
  { { 1, 2 }, { 3, 4 }, { 5, 6 } },
  { { 7, 8 }, { 9, 10 }, { 11, 12 } }
};
static const char text[] = "qualified";
static const word_t words[4] = { 10, 20, 30, 40 };

struct holder {
  long row[3];
  long grid[2][3];
  struct { short inner[2]; } nest;
};
static const struct holder held = { { 21, 22, 23 }, { { 31, 32, 33 }, { 34, 35, 36 } }, { { 41, 42 } } };

/* Static initializers: decay, element addresses, offsets, array addresses.  */
static const long *first_row = &matrix[0][0];
static const long (*rows)[3] = matrix;
static const long (*second_row)[3] = matrix + 1;
static const long (*row_address)[3] = &matrix[1];
static const long *cell = &matrix[1][2];
static const char *text_pointer = text;
static const char (*text_address)[10] = &text;
static const long (*held_row)[3] = &held.row;
static const long (*held_grid)[3] = &held.grid[0];
static const word_t *word_cast = (const word_t *)words;
static const void *opaque = matrix;

static long sum_row(const long *p, int n)
{
  long s = 0;
  int i;
  for (i = 0; i < n; i++)
    s += p[i];
  return s;
}

static long sum_rows(const long (*p)[3], int n)
{
  long s = 0;
  int i;
  for (i = 0; i < n; i++)
    s += sum_row(p[i], 3);
  return s;
}

static long sum_volatile(volatile long (*p)[3])
{
  return p[0][0] + p[1][2];
}

static unsigned long offset32(const void *p)
{
  union aligned32 { word_t v; unsigned char c[4]; };
  const union aligned32 *a = (const union aligned32 *) &((const ext_rel *) p)->r_offset;
  return a->c[0] | (a->c[1] << 8) | ((unsigned long) a->c[2] << 16) | ((unsigned long) a->c[3] << 24);
}

static int same_offset(const ext_rel *p)
{
  return (const unsigned char *) &p->r_offset == p->r_offset;
}

int main(void)
{
  ext_rel rel = { { 0x78, 0x56, 0x34, 0x12 }, { 1, 0, 0, 0 } };
  const ext_rel *rp = &rel;
  const struct holder *hp = &held;
  const long local[2][3] = { { 51, 52, 53 }, { 54, 55, 56 } };
  const long (*lp)[3] = local;
  const long *ep = &local[1][0];
  const long (*whole)[2][3] = &local;
  const unsigned char (*plane)[3][2] = cube;
  const unsigned char (*pair)[2] = cube[1];
  const void *v;

  printf("elflink %lx %d %d\n", offset32(rp), same_offset(rp),
         (unsigned char *) &rp->r_offset != rel.r_offset);
  printf("decay %ld %ld %ld\n", sum_rows(matrix, 2), sum_row(matrix[1], 3),
         sum_rows(lp, 2));
  printf("address %ld %ld %ld\n", (*whole)[1][2], (*rows)[2], (*row_address)[0]);
  printf("element %ld %ld %d\n", *ep, *cell, &matrix[0] == matrix);
  printf("arithmetic %ld %ld %d %d\n", (matrix + 1)[0][1], *(*(local + 1) + 2),
         (int) ((matrix + 2) - matrix), (int) (&local[1][2] - &local[0][0]));
  printf("compare %d %d %d %d\n", matrix + 1 == second_row, lp < lp + 1,
         first_row == &matrix[0][0], held_grid + 1 > held_grid);
  printf("cube %d %d %d %d\n", plane[1][2][1], pair[2][0], (*(cube + 1))[0][1],
         (int) (&cube[1][0] - &cube[0][0]));
  printf("volatile %ld %ld\n", sum_volatile(vmatrix), vmatrix[1][0]);
  printf("member %ld %ld %ld %d\n", sum_row(hp->row, 3), sum_rows(hp->grid, 2),
         (*held_row)[1], hp->nest.inner[1]);
  printf("member-address %d %d %d\n", (const long *) &hp->row == hp->row,
         &hp->grid[1] == hp->grid + 1, (const short *) &hp->nest.inner == hp->nest.inner);
  printf("static %s %c %c %u %d\n", text_pointer, (*text_address)[1], text[2],
         word_cast[3], opaque == (const void *) matrix);
  printf("sizeof %d %d %d %d %d %d %d\n", (int) sizeof matrix, (int) sizeof matrix[0],
         (int) sizeof *rows, (int) sizeof &matrix, (int) sizeof hp->grid,
         (int) sizeof *whole, (int) sizeof (const long (*)[3]));
  v = local;
  printf("void %ld %d\n", ((const long *) v)[4], (const void *) &local == v);
  v = (void *) (matrix + 1);
  printf("cast %ld %ld\n", *(const long *) v, ((const long (*)[3]) matrix)[1][1]);
  return 0;
}
