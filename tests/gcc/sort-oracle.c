/* Optional independent host GCC/libc differential oracle, never production. */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>

typedef int (*comparison)(const void *, const void *);
typedef void (*sort_function)(void *, size_t, size_t, comparison);
void seed_qsort(void *, size_t, size_t, comparison);
void host_seed_qsort(void *, size_t, size_t, comparison);
static size_t width;
static sort_function active_sort;
static int depth;
static int nested_failure;

static int byte_order(const void *a, const void *b)
{
    int result = memcmp(a, b, width);
    return result < 0 ? INT_MIN : result > 0 ? INT_MAX : 0;
}

static int integer_order(const void *a, const void *b)
{
    int x = *(const int *)a;
    int y = *(const int *)b;
    return x < y ? INT_MIN : x > y ? INT_MAX : 0;
}

static int nested_order(const void *a, const void *b)
{
    int inner[] = {19, 0, -1, INT_MAX, 19, INT_MIN, 3};
    int expected[] = {INT_MIN, -1, 0, 3, 19, 19, INT_MAX};
    if (depth < 3) {
        ++depth;
        active_sort(inner, 7, sizeof(*inner), nested_order);
        if (memcmp(inner, expected, sizeof(inner))) nested_failure = 1;
        --depth;
    }
    return integer_order(a, b);
}

static int byte_cases(sort_function sort)
{
    const size_t widths[] = {1, 2, 3, 7, 8, 15, 17, 31, 257};
    const size_t counts[] = {0, 1, 2, 3, 7, 8, 31, 32, 33, 97, 257, 1024};
    size_t w, n, i, j, offset;
    unsigned int random;
    for (w = 0; w < sizeof(widths) / sizeof(*widths); ++w) {
        width = widths[w];
        for (n = 0; n < sizeof(counts) / sizeof(*counts); ++n) {
            size_t count = counts[n], bytes = count * width, storage = bytes + 32;
            unsigned char *array = malloc(storage);
            unsigned char *expected = malloc(storage);
            unsigned char *original = malloc(storage);
            if (!array || !expected || !original) return 10;
            for (offset = 1; offset <= 8; ++offset) {
                random = 81237;
                memset(original, 0xD7, storage);
                for (i = 0; i < bytes; ++i) {
                    random = random * 1664525U + 1013904223U;
                    original[offset + i] = (unsigned char)(random >> 19);
                }
                for (i = 1; i < count; i += 4)
                    for (j = 0; j < width; ++j)
                        original[offset + i * width + j] = original[offset + j];
                memcpy(array, original, storage);
                memcpy(expected, original, storage);
                qsort(expected + offset, count, width, byte_order);
                sort(array + offset, count, width, byte_order);
                if (memcmp(array, expected, storage)) return 11;
                /* An already sorted and then a reversed copy exercise other
                   input shapes against a retained complete byte oracle. */
                sort(array + offset, count, width, byte_order);
                if (memcmp(array, expected, storage)) return 12;
                for (i = 0; i < count; ++i)
                    memcpy(array + offset + i * width,
                           expected + offset + (count - 1 - i) * width, width);
                sort(array + offset, count, width, byte_order);
                if (memcmp(array, expected, storage)) return 13;
            }
            free(array); free(expected); free(original);
        }
    }
    return 0;
}

struct record { int precision; int bytes; unsigned long id; unsigned char payload[19]; };

static int pointer_order(const void *a, const void *b)
{
    const struct record *x = *(struct record *const *)a;
    const struct record *y = *(struct record *const *)b;
    if (x->precision != y->precision) return x->precision < y->precision ? -1 : 1;
    if (x->bytes != y->bytes) return x->bytes < y->bytes ? -1 : 1;
    return 0;
}

static int pointer_cases(sort_function sort)
{
    struct record records[193], original[193];
    struct record *array[195], *expected[193];
    unsigned char seen[193] = {0};
    size_t i, j;
    memset(records, 0, sizeof(records));
    for (i = 0; i < 193; ++i) {
        records[i].precision = (int)(i * 11 % 13);
        records[i].bytes = (int)(i * 17 % 5);
        records[i].id = i;
        for (j = 0; j < 19; ++j) records[i].payload[j] = (unsigned char)(i + j);
        array[i + 1] = expected[i] = records + 192 - i;
    }
    memcpy(original, records, sizeof(records));
    array[0] = records + 19; array[194] = records + 37;
    qsort(expected, 193, sizeof(*expected), pointer_order);
    sort(array + 1, 193, sizeof(*array), pointer_order);
    if (array[0] != records + 19 || array[194] != records + 37) return 21;
    if (memcmp(records, original, sizeof(records))) return 22;
    for (i = 0; i < 193; ++i) {
        for (j = 0; j < 193 && array[i + 1] != records + j; ++j) {}
        if (j == 193 || seen[j]) return 23;
        seen[j] = 1;
        if (pointer_order(array + i + 1, expected + i)) return 24;
    }
    return 0;
}

int main(void)
{
    sort_function sorts[] = {seed_qsort, host_seed_qsort};
    size_t implementation;
    for (implementation = 0; implementation < 2; ++implementation) {
        int result, array[] = {5, 4, 3, 2, 1, 0};
        const int expected[] = {0, 1, 2, 3, 4, 5};
        active_sort = sorts[implementation];
        result = byte_cases(active_sort);
        if (!result) result = pointer_cases(active_sort);
        active_sort(array, 6, sizeof(*array), nested_order);
        if (depth || nested_failure || memcmp(array, expected, sizeof(array))) result = 31;
        if (result) {
            fprintf(stderr, "sort oracle implementation %zu failure %d\n", implementation, result);
            return result;
        }
    }
    puts("PASS: Forth qsort and host-compiled source match independent host libc");
    return 0;
}
