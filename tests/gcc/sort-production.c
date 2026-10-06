/* Entire test and qsort implementation are compiled by Forth. */
#include <stdlib.h>
#include <limits.h>
#include <seed-syscall.h>

static unsigned long comparisons;
static int nested_depth;
static int nested_failure;
static size_t record_width;

static int compare_int(const void *a, const void *b)
{
    int left = *(const int *)a;
    int right = *(const int *)b;
    comparisons = comparisons + 1;
    /* qsort may use the sign, but must not negate INT_MIN. */
    if (left < right) return INT_MIN;
    if (left > right) return INT_MAX;
    return 0;
}

static int integer_cases(void)
{
    int array[4098];
    int before[65];
    int after[65];
    int pattern;
    int n;
    int i;
    int value;
    unsigned int random;
    unsigned long bound;
    int log;
    for (pattern = 0; pattern < 7; pattern = pattern + 1) {
        for (n = 0; n <= 4096;
             n = n < 130 ? n + 1 : n < 2048 ? n * 2 : n == 4096 ? 4097 : 4096) {
            random = 3919;
            for (i = 0; i < 65; i = i + 1) {
                before[i] = 0;
                after[i] = 0;
            }
            array[0] = INT_MIN;
            array[n + 1] = INT_MAX;
            for (i = 0; i < n; i = i + 1) {
                random = random * 1664525U + 1013904223U;
                value = (i * 65) / n;
                if (pattern == 1) value = 64 - value;
                if (pattern == 2) value = 32;
                if (pattern == 3) value = (i < n / 2 ? i : n - i) % 65;
                if (pattern == 4) value = (i % 2 == 0 ? 0 : 64);
                if (pattern == 5) value = (int)(random % 65);
                if (pattern == 6) value = (i * 31) % 65;
                array[i + 1] = value - 32;
                before[value] = before[value] + 1;
            }
            comparisons = 0;
            qsort(array + 1, (size_t)n, sizeof(int), compare_int);
            if (array[0] != INT_MIN || array[n + 1] != INT_MAX) return 11;
            if (n < 2 && comparisons != 0) return 12;
            log = 0;
            for (i = n; i > 0; i = i / 2) log = log + 1;
            bound = 4 * (unsigned long)n * (unsigned long)(log + 1);
            if (comparisons > bound) return 13;
            for (i = 0; i < n; i = i + 1) {
                value = array[i + 1] + 32;
                if (value < 0 || value >= 65) return 14;
                after[value] = after[value] + 1;
                if (i > 0 && array[i] > array[i + 1]) return 15;
            }
            for (i = 0; i < 65; i = i + 1) {
                if (before[i] != after[i]) return 16;
            }
        }
    }
    array[0] = INT_MAX; array[1] = 0; array[2] = INT_MIN;
    qsort(array, 3, sizeof(int), compare_int);
    if (array[0] != INT_MIN || array[1] != 0 || array[2] != INT_MAX) return 17;
    return 0;
}

static int permutation_cases(void)
{
    int input[8];
    int array[10];
    int n;
    int i;
    int j;
    int k;
    int tmp;
    for (n = 0; n <= 8; n = n + 1) {
        for (i = 0; i < n; i = i + 1) input[i] = i;
        while (1) {
            array[0] = 813;
            array[n + 1] = 719;
            for (i = 0; i < n; i = i + 1) array[i + 1] = input[i];
            qsort(array + 1, (size_t)n, sizeof(int), compare_int);
            if (array[0] != 813 || array[n + 1] != 719) return 21;
            for (i = 0; i < n; i = i + 1) {
                if (array[i + 1] != i) return 22;
            }
            /* Enumerate every permutation with an independent successor. */
            i = n - 2;
            while (i >= 0 && input[i] >= input[i + 1]) i = i - 1;
            if (i < 0) break;
            j = n - 1;
            while (input[j] <= input[i]) j = j - 1;
            tmp = input[i]; input[i] = input[j]; input[j] = tmp;
            j = i + 1; k = n - 1;
            while (j < k) {
                tmp = input[j]; input[j] = input[k]; input[k] = tmp;
                j = j + 1; k = k - 1;
            }
        }
    }
    return 0;
}

static int compare_bytes(const void *a, const void *b)
{
    const unsigned char *left = a;
    const unsigned char *right = b;
    size_t i;
    for (i = 0; i < record_width; i = i + 1) {
        if (left[i] < right[i]) return -91;
        if (left[i] > right[i]) return 73;
    }
    return 0;
}

/* Independent selection sort provides the complete expected permutation.
   Its bytewise total order makes equal records byte-identical, so no test
   incorrectly requires stable ordering from qsort. */
static void reference_bytes(unsigned char *array, size_t count, size_t size)
{
    size_t i;
    size_t j;
    size_t k;
    size_t least;
    unsigned char byte;
    for (i = 0; i < count; i = i + 1) {
        least = i;
        for (j = i + 1; j < count; j = j + 1) {
            if (compare_bytes(array + j * size, array + least * size) < 0)
                least = j;
        }
        for (k = 0; k < size; k = k + 1) {
            byte = array[i * size + k];
            array[i * size + k] = array[least * size + k];
            array[least * size + k] = byte;
        }
    }
}

static int byte_cases(void)
{
    unsigned char array[8499];
    unsigned char expected[8481];
    unsigned int random;
    size_t width;
    size_t offset;
    size_t i;
    size_t count;
    size_t bytes;
    for (width = 1; width <= 257; width = width < 33 ? width + 1 : 257) {
        record_width = width;
        count = 33;
        bytes = width * count;
        for (offset = 1; offset <= 8; offset = offset + 1) {
            random = 371;
            for (i = 0; i < sizeof(array); i = i + 1) array[i] = 0xA7;
            for (i = 0; i < bytes; i = i + 1) {
                random = random * 1664525U + 1013904223U;
                array[offset + i] = (unsigned char)(random >> 17);
                expected[i] = array[offset + i];
            }
            /* Retain duplicate records as well as arbitrary payload bytes. */
            for (i = 0; i < width; i = i + 1) {
                array[offset + width + i] = array[offset + i];
                expected[width + i] = expected[i];
            }
            reference_bytes(expected, count, width);
            qsort(array + offset, count, width, compare_bytes);
            for (i = 0; i < bytes; i = i + 1) {
                if (array[offset + i] != expected[i]) return 31;
            }
            for (i = 0; i < offset; i = i + 1) {
                if (array[i] != 0xA7) return 32;
            }
            for (i = offset + bytes; i < sizeof(array); i = i + 1) {
                if (array[i] != 0xA7) return 33;
            }
        }
        if (width == 257) break;
    }
    return 0;
}

struct mode_record {
    int precision;
    int size;
    unsigned long identity;
    unsigned char payload[7];
};

static int compare_modes(const void *a, const void *b)
{
    const struct mode_record *left = *(struct mode_record *const *)a;
    const struct mode_record *right = *(struct mode_record *const *)b;
    if (left->precision != right->precision)
        return left->precision < right->precision ? -1 : 1;
    if (left->size != right->size)
        return left->size < right->size ? -1 : 1;
    return 0;
}

static int pointer_cases(void)
{
    struct mode_record records[97];
    struct mode_record *array[99];
    int seen[97];
    int i;
    int j;
    unsigned long id;
    for (i = 0; i < 97; i = i + 1) {
        records[i].precision = (i * 19) % 13;
        records[i].size = (i * 11) % 7;
        records[i].identity = (unsigned long)i;
        for (j = 0; j < 7; j = j + 1)
            records[i].payload[j] = (unsigned char)(i + j * 3);
        array[i + 1] = records + 96 - i;
        seen[i] = 0;
    }
    array[0] = records + 13; array[98] = records + 17;
    qsort(array + 1, 97, sizeof(struct mode_record *), compare_modes);
    if (array[0] != records + 13 || array[98] != records + 17) return 41;
    for (i = 1; i <= 97; i = i + 1) {
        /* Find pointer identity before dereferencing the sort result. */
        j = 0;
        while (j < 97 && array[i] != records + j) j = j + 1;
        if (j == 97 || seen[j] != 0) return 42;
        seen[j] = 1;
        id = array[i]->identity;
        if (id != (unsigned long)j || array[i]->precision != (j * 19) % 13 ||
            array[i]->size != (j * 11) % 7) return 43;
        for (j = 0; j < 7; j = j + 1) {
            if (array[i]->payload[j] != (unsigned char)(id + j * 3)) return 44;
        }
        if (i > 1 && compare_modes(array + i - 1, array + i) > 0) return 45;
    }
    return 0;
}

static int compare_nested(const void *a, const void *b)
{
    int inner[7];
    int i;
    if (nested_depth < 3) {
        nested_depth = nested_depth + 1;
        inner[0] = 718; inner[6] = 319;
        for (i = 0; i < 5; i = i + 1) inner[i + 1] = 4 - i;
        qsort(inner + 1, 5, sizeof(int), compare_nested);
        for (i = 0; i < 5; i = i + 1) {
            if (inner[i + 1] != i) nested_failure = 1;
        }
        if (inner[0] != 718 || inner[6] != 319) nested_failure = 1;
        nested_depth = nested_depth - 1;
    }
    return compare_int(a, b);
}

static int nested_cases(void)
{
    int array[19];
    int i;
    for (i = 0; i < 19; i = i + 1) array[i] = 18 - i;
    qsort(array, 19, sizeof(int), compare_nested);
    for (i = 0; i < 19; i = i + 1) {
        if (array[i] != i) return 51;
    }
    if (nested_depth != 0 || nested_failure != 0) return 52;
    return 0;
}

static int boundary_cases(void)
{
    long mapped;
    unsigned char *page;
    unsigned char *array;
    size_t i;
    int edge;
    mapped = __seed_syscall6(9, 0, 12288, 3, 34, -1, 0);
    if (mapped < 0) return 61;
    page = (unsigned char *)mapped + 4096;
    if (__seed_syscall6(10, mapped, 4096, 0, 0, 0, 0) != 0) return 62;
    if (__seed_syscall6(10, (long)(page + 4096), 4096, 0, 0, 0, 0) != 0) return 63;
    record_width = 257;
    for (edge = 0; edge < 2; edge = edge + 1) {
        array = edge == 0 ? page : page + 4096 - 15 * 257;
        for (i = 0; i < 15 * 257; i = i + 1) array[i] = (unsigned char)(i * 19);
        qsort(array, 15, 257, compare_bytes);
        for (i = 1; i < 15; i = i + 1) {
            if (compare_bytes(array + (i - 1) * 257, array + i * 257) > 0) return 64;
        }
    }
    /* A valid one-past pointer and comparator, with no elements to access. */
    comparisons = 0;
    qsort(page + 4096, 0, sizeof(int), compare_int);
    if (comparisons != 0) return 65;
    if (__seed_syscall6(11, mapped, 12288, 0, 0, 0, 0) != 0) return 66;
    return 0;
}

/* GCC 4.0.4 sorts with comparators that tie (simplify_plus_minus orders two
   registers of equal precedence), so cc1's output depends on where qsort
   leaves equal elements.  musl's smoothsort, used here, leaves a run of
   equal keys in input order; a heapsort would exchange them. */
static int compare_key(const void *a, const void *b)
{
    int left = *(const int *)a / 1000;
    int right = *(const int *)b / 1000;
    if (left < right) return -1;
    if (left > right) return 1;
    return 0;
}

static int tie_cases(void)
{
    int array[64];
    int n;
    int i;
    for (n = 2; n <= 64; n = n + 1) {
        for (i = 0; i < n; i = i + 1)
            array[i] = 7000 + i;
        qsort(array, (size_t)n, sizeof(int), compare_key);
        for (i = 0; i < n; i = i + 1)
            if (array[i] != 7000 + i) return 80;
    }
    return 0;
}

int main(void)
{
    int result;
    result = integer_cases(); if (result != 0) return result;
    result = permutation_cases(); if (result != 0) return result;
    result = byte_cases(); if (result != 0) return result;
    result = pointer_cases(); if (result != 0) return result;
    result = nested_cases(); if (result != 0) return result;
    result = tie_cases(); if (result != 0) return result;
    return boundary_cases();
}
