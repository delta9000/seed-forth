/* Original seed-forth test; see LICENSE and grouped-declarator-README.md.
   Redundant parentheses around a starless direct declarator, as in the
   binutils 2.30 nm.c sorter table, compared with host GCC/glibc. */
#include <stdio.h>

static int forward(const void *x, const void *y) { return 1 + (x != y); }
static int reverse(const void *x, const void *y) { return 10 + (x == y); }
static int numeric(const void *x, const void *y) { return 100 + (x != 0) + (y != 0); }
static int other(const void *x, const void *y) { return 1000 + (x == 0) + (y == 0); }

/* The exact original binutils nm.c shape. */
static int (*(sorters[2][2])) (const void *, const void *) =
{
  { forward, reverse },
  { numeric, other }
};

int (*(single)) (const void *, const void *);
int (*(row[3])) (const void *, const void *) = { forward, reverse, other };
int ((plain));
int *(pointers[2]);
long ((matrix[2][3]));
typedef int (*(callback)) (int);
struct holder { int (*(operation)) (int); int ((value)); };

static int twice(int v) { return 2 * v; }
static int square(int v) { return v * v; }
/* Function returning pointer: *(name)(int) groups exactly as *name(int). */
static int *(locate)(int index) { return pointers[index]; }

static int apply(int (*(table[2])) (int), int index, int v) { return table[index](v); }

int main(void)
{
    int (*(local)) (int) = twice;
    int (*(pair[2])) (int);
    callback named = square;
    struct holder h;
    int a = 5, b = 7, i, j;
    pair[0] = twice;
    pair[1] = square;
    single = other;
    plain = 41;
    pointers[0] = &a;
    pointers[1] = &b;
    for (i = 0; i < 2; i++)
        for (j = 0; j < 3; j++)
            matrix[i][j] = 10L * i + j;
    h.operation = square;
    h.value = 9;
    for (i = 0; i < 2; i++)
        for (j = 0; j < 2; j++)
            printf("sorters[%d][%d] %d\n", i, j, sorters[i][j](&a, i ? (void *)0 : (void *)&b));
    for (i = 0; i < 3; i++)
        printf("row[%d] %d\n", i, row[i](&a, &a));
    printf("single %d\n", single(0, &a));
    printf("plain %d sizeof %d\n", plain + 1, (int)sizeof plain);
    printf("locate %d %d\n", *locate(0), *locate(1));
    printf("matrix %ld %d\n", matrix[1][2], (int)sizeof matrix);
    printf("sizes %d %d %d\n", (int)sizeof sorters, (int)sizeof row, (int)sizeof pair);
    printf("local %d named %d holder %d\n", local(4), named(6), h.operation(h.value));
    printf("apply %d %d\n", apply(pair, 0, 8), apply(pair, 1, 8));
    return 0;
}
