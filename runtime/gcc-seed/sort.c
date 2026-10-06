/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <stdlib.h>

/* Binary search over an ascending array.  The interval [low, high) always
   contains every element that could still match; computing the middle as
   low + (high - low) / 2 keeps the index arithmetic from overflowing.  The
   comparator receives the key first, as ISO C specifies. */
void *bsearch(const void *key, const void *array, size_t count, size_t size,
              int (*compare)(const void *, const void *))
{
    const unsigned char *base = array;
    size_t low = 0;
    size_t high = count;
    size_t middle;
    int order;
    while (low < high) {
        middle = low + (high - low) / 2;
        order = compare(key, base + middle * size);
        if (order == 0)
            return (void *)(base + middle * size);
        if (order < 0)
            high = middle;
        else
            low = middle + 1;
    }
    return 0;
}
