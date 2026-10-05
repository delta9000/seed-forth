/* bsearch and strerror cases; the same source runs on the Forth runtime and
   on host libc, and the two outputs must be identical. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static size_t element_size;

/* Order elements by their first byte, then their last byte. */
static int compare_bytes(const void *a, const void *b)
{
    const unsigned char *x = a;
    const unsigned char *y = b;
    if (x[0] != y[0])
        return x[0] < y[0] ? -1 : 1;
    if (x[element_size - 1] != y[element_size - 1])
        return x[element_size - 1] < y[element_size - 1] ? -1 : 1;
    return 0;
}

static int compare_extreme(const void *a, const void *b)
{
    long x = *(const long *)a;
    long y = *(const long *)b;
    return x < y ? -2147483647 - 1 : x > y ? 2147483647 : 0;
}

static void search_sizes(void)
{
    static unsigned char array[41 * 24];
    unsigned char key[24];
    static const size_t sizes[] = {1, 3, 8, 24};
    size_t s, count, i, k;
    for (s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
        element_size = sizes[s];
        for (count = 0; count <= 41; count++) {
            for (i = 0; i < count; i++) {
                memset(array + i * element_size, 0x5a, element_size);
                array[i * element_size] = (unsigned char)(2 * i + 1);
                array[i * element_size + element_size - 1] = (unsigned char)(2 * i + 1);
            }
            for (k = 0; k <= 2 * count + 2; k++) {
                const unsigned char *found;
                memset(key, 0x5a, sizeof key);
                key[0] = (unsigned char)k;
                key[element_size - 1] = (unsigned char)k;
                found = bsearch(key, array, count, element_size, compare_bytes);
                printf("size %lu count %lu key %lu -> %ld\n", (unsigned long)element_size,
                       (unsigned long)count, (unsigned long)k,
                       found ? (long)((found - array) / (long)element_size) : -1L);
            }
        }
    }
}

static void search_extreme(void)
{
    static const long values[] = {-1000000, -3, 0, 7, 99, 1000000};
    long key;
    const long *found;
    for (key = -1000001; key <= 1000001; key += 142857) {
        found = bsearch(&key, values, 6, sizeof values[0], compare_extreme);
        printf("extreme key %ld -> %ld\n", key, found ? (long)(found - values) : -1L);
    }
}

static void messages(void)
{
    static const int numbers[] = {
        0, EPERM, ENOENT, EINTR, EIO, E2BIG, EBADF, EAGAIN, ENOMEM, EACCES,
        EFAULT, EEXIST, ENOTDIR, EISDIR, EINVAL, ENFILE, EMFILE, ENOTTY,
        ENOSPC, ESPIPE, EPIPE, EDOM, ERANGE, ENAMETOOLONG, ENOSYS,
        ENOTEMPTY, ELOOP, EOVERFLOW, EILSEQ, 4095, 2147483647, -1,
        -2147483647 - 1
    };
    size_t i;
    for (i = 0; i < sizeof numbers / sizeof numbers[0]; i++)
        printf("strerror %d: %s\n", numbers[i], strerror(numbers[i]));
}

int main(void)
{
    search_sizes();
    search_extreme();
    messages();
    return 0;
}
