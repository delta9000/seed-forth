/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <seed-syscall.h>

/* mmap gives page alignment; this LP64 header leaves 16-byte alignment. */
struct seed_allocation {
    size_t extent;
    size_t requested;
};

/* Single-threaded size classes. Retain slabs until process exit so freed
   small blocks can be reused without another syscall. Each slot includes
   the same 16-byte header as a large mapping. */
#define SEED_SLAB_BYTES 65536
#define SEED_SMALL_MAX 2048
static void *seed_free[8];

static int seed_class(size_t size)
{
    int index = 0;
    size_t capacity = 16;
    while (capacity < size) {
        capacity = capacity * 2;
        index++;
    }
    return index;
}

static void *seed_small(size_t size)
{
    int index = seed_class(size);
    size_t capacity = (size_t)16 << index;
    size_t stride = capacity + sizeof(struct seed_allocation);
    size_t offset;
    long result;
    char *base;
    void *pointer;
    struct seed_allocation *header;
    if (seed_free[index] == NULL) {
        result = __seed_syscall6(9, 0, SEED_SLAB_BYTES, 3, 34, -1, 0);
        if (result < 0 && result >= -4095) {
            errno = (int)-result;
            return NULL;
        }
        base = (char *)result;
        for (offset = 0; offset <= SEED_SLAB_BYTES - stride; offset += stride) {
            header = (struct seed_allocation *)(base + offset);
            header->extent = stride;
            pointer = (void *)(header + 1);
            *(void **)pointer = seed_free[index];
            seed_free[index] = pointer;
        }
    }
    pointer = seed_free[index];
    seed_free[index] = *(void **)pointer;
    header = (struct seed_allocation *)pointer - 1;
    header->requested = size;
    return pointer;
}

void *malloc(size_t size)
{
    size_t payload = size;
    size_t extent;
    long result;
    struct seed_allocation *header;
    if (payload == 0)
        payload = 1;
    /* Reject overflow and objects too large for pointer differences. */
    if (payload > (size_t)LONG_MAX - sizeof(struct seed_allocation)) {
        errno = ENOMEM;
        return NULL;
    }
    if (payload <= SEED_SMALL_MAX)
        return seed_small(size);
    extent = payload + sizeof(struct seed_allocation);
    /* mmap(NULL, extent, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS,
       -1, 0). The kernel rounds the length to whole pages. */
    result = __seed_syscall6(9, 0, (long)extent, 3, 34, -1, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return NULL;
    }
    header = (struct seed_allocation *)result;
    header->extent = extent;
    header->requested = size;
    return (void *)(header + 1);
}

void free(void *pointer)
{
    struct seed_allocation *header;
    if (pointer == NULL)
        return;
    header = (struct seed_allocation *)pointer - 1;
    if (header->extent <= SEED_SMALL_MAX + sizeof(struct seed_allocation)) {
        int index = seed_class(header->extent - sizeof(struct seed_allocation));
        *(void **)pointer = seed_free[index];
        seed_free[index] = pointer;
        return;
    }
    /* A valid allocation always supplies an aligned address and length.
       The raw bridge does not touch errno, so free preserves errno. */
    __seed_syscall6(11, (long)header, (long)header->extent, 0, 0, 0, 0);
}

void *calloc(size_t count, size_t size)
{
    size_t total;
    void *pointer;
    if (count != 0 && size > (size_t)-1 / count) {
        errno = ENOMEM;
        return NULL;
    }
    total = count * size;
    pointer = malloc(total);
    if (pointer != NULL)
        memset(pointer, 0, total);
    return pointer;
}

void *realloc(void *pointer, size_t size)
{
    struct seed_allocation *header;
    void *replacement;
    size_t old_size;
    if (pointer == NULL)
        return malloc(size);
    if (size == 0) {
        free(pointer);
        return NULL;
    }
    header = (struct seed_allocation *)pointer - 1;
    old_size = header->requested;
    if (size <= old_size) {
        header->requested = size;
        return pointer;
    }
    replacement = malloc(size);
    if (replacement == NULL)
        return NULL;
    memcpy(replacement, pointer, old_size);
    free(pointer);
    return replacement;
}
