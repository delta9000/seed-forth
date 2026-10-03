/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <stdlib.h>

/* Swap through character lvalues: elements need no extra alignment, and
   their complete object representations (including padding) are retained. */
static void sort_swap(unsigned char *a, unsigned char *b, size_t size)
{
    size_t i;
    unsigned char byte;
    for (i = 0; i < size; i = i + 1) {
        byte = a[i];
        a[i] = b[i];
        b[i] = byte;
    }
}

/* Restore a maximum heap whose two subtrees already satisfy the invariant.
   Testing root < count / 2 first keeps 2 * root + 1 within the array and
   prevents index arithmetic overflow, even for very large valid arrays. */
static void sort_sift(unsigned char *base, size_t root, size_t count,
                      size_t size, int (*compare)(const void *, const void *))
{
    size_t child;
    while (root < count / 2) {
        child = root * 2 + 1;
        if (child + 1 < count &&
            compare(base + child * size, base + (child + 1) * size) < 0)
            child = child + 1;
        if (compare(base + root * size, base + child * size) >= 0)
            return;
        sort_swap(base + root * size, base + child * size, size);
        root = child;
    }
}

void qsort(void *array, size_t count, size_t size,
           int (*compare)(const void *, const void *))
{
    unsigned char *base = array;
    size_t root;
    size_t end;
    if (count < 2 || size == 0)
        return;
    root = count / 2;
    while (root != 0) {
        root = root - 1;
        sort_sift(base, root, count, size, compare);
    }
    end = count;
    while (end > 1) {
        end = end - 1;
        sort_swap(base, base + end * size, size);
        sort_sift(base, 0, end, size, compare);
    }
}
