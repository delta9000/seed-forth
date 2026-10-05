/* Independent allocator review: host-compiled syscall fault/accounting harness.
   Run from repository root:
   cc -std=c11 -O2 -Wall -Wextra -Werror -idirafter runtime/gcc-seed/include \
      tests/gcc/compact-alloc-review.c -o /tmp/compact-alloc-review
   This uses fixed storage, never actual mmap, and never replaces host malloc. */
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static long review_syscall(long, long, long, long, long, long, long);
#define malloc review_malloc
#define free review_free
#define calloc review_calloc
#define realloc review_realloc
#define __seed_syscall6 review_syscall
#include "../../runtime/gcc-seed/alloc.c"
#undef malloc
#undef free
#undef calloc
#undef realloc
#undef __seed_syscall6

#define SLAB 65536u
#define ARENA (8u * 1024u * 1024u)
static unsigned char arena_store[ARENA + 4096];
static unsigned char *arena;
static size_t cursor, attempts, maps, unmaps, mapped_bytes;
static int reject_maps;
struct mapping { void *base; size_t length; int live; };
static struct mapping records[512];

static long review_syscall(long number, long a1, long a2, long a3,
                           long a4, long a5, long a6)
{
    size_t i, rounded;
    if (number == 9) {
        ++attempts;
        assert(a1 == 0 && a2 > 0 && a3 == 3 && a4 == 34 && a5 == -1 && a6 == 0);
        if (reject_maps) return -ENOMEM;
        rounded = ((size_t)a2 + 4095) & ~(size_t)4095;
        assert(rounded <= ARENA - cursor && maps < 512);
        records[maps].base = arena + cursor;
        records[maps].length = (size_t)a2;
        records[maps].live = 1;
        memset(arena + cursor, 0, rounded); /* Linux anonymous mmap guarantee. */
        cursor += rounded;
        mapped_bytes += rounded;
        return (long)records[maps++].base;
    }
    assert(number == 11 && a3 == 0 && a4 == 0 && a5 == 0 && a6 == 0);
    for (i = 0; i < maps; ++i) {
        if (records[i].base == (void *)a1 && records[i].live) {
            assert(records[i].length == (size_t)a2);
            records[i].live = 0;
            ++unmaps;
            return 0;
        }
    }
    assert(!"munmap did not match a live mapping");
    return -EINVAL;
}

static void check_bytes(const void *pointer, size_t n, unsigned char value)
{
    const unsigned char *p = pointer;
    size_t i;
    for (i = 0; i < n; ++i) assert(p[i] == value);
}

int main(void)
{
    void *blocks[4097], *p, *q, *r;
    size_t payload, count, i, before, before_bytes, before_unmaps;
    arena = (unsigned char *)(((size_t)arena_store + 4095) & ~(size_t)4095);
    /* Reject impossible objects before issuing a syscall. */
    before = attempts;
    errno = 0;
    assert(review_malloc((size_t)-1) == NULL && errno == ENOMEM);
    assert(review_malloc((size_t)LONG_MAX) == NULL && errno == ENOMEM);
    assert(review_calloc((size_t)-1 / 3 + 1, 3) == NULL && errno == ENOMEM);
    assert(attempts == before);
    errno = EDOM;
    review_free(NULL);
    assert(errno == EDOM && unmaps == 0);

    /* First slab acquisition must propagate errors and remain retryable. */
    reject_maps = 1;
    assert(review_malloc(7) == NULL && errno == ENOMEM);
    reject_maps = 0;
    p = review_malloc(0);
    assert(p && (size_t)p % 16 == 0);
    review_free(p);
    p = review_calloc(0, (size_t)-1);
    assert(p);
    review_free(p);

    /* Force rollover in every class, preserving all live payloads. */
    for (payload = 16; payload <= 2048; payload *= 2) {
        count = SLAB / (payload + 16) + 1;
        before = maps;
        before_unmaps = unmaps;
        for (i = 0; i < count; ++i) {
            size_t request = (i & 1) ? payload : payload / 2 + 1;
            blocks[i] = review_malloc(request);
            assert(blocks[i] && (size_t)blocks[i] % 16 == 0);
            memset(blocks[i], (unsigned char)(i % 251 + 1), request);
        }
        assert(maps - before <= 2);
        for (i = 0; i < count; ++i) {
            size_t request = (i & 1) ? payload : payload / 2 + 1;
            check_bytes(blocks[i], request, (unsigned char)(i % 251 + 1));
            errno = EDOM;
            review_free(blocks[i]);
            assert(errno == EDOM);
        }
        assert(unmaps == before_unmaps); /* Retained slab contract. */
        before = maps;
        reject_maps = 1;
        for (i = 0; i < count; ++i) {
            blocks[i] = review_calloc(1, payload);
            assert(blocks[i]);
            check_bytes(blocks[i], payload, 0);
        }
        assert(maps == before);
        for (i = 0; i < count; ++i) review_free(blocks[i]);
        reject_maps = 0;
    }
    assert(mapped_bytes <= 16u * SLAB);

    /* The first request above the small limit uses its own mapping. */
    before = maps;
    before_bytes = mapped_bytes;
    before_unmaps = unmaps;
    p = review_malloc(2049);
    assert(p && (size_t)p % 16 == 0 && maps == before + 1);
    assert(mapped_bytes == before_bytes + 4096);
    memset(p, 0x71, 2049);
    errno = ERANGE;
    review_free(p);
    assert(unmaps == before_unmaps + 1 && errno == ERANGE);

    p = review_realloc(NULL, 31);
    assert(p);
    memset(p, 0xa3, 31);
    q = review_realloc(p, 17);
    assert(q == p);
    check_bytes(q, 17, 0xa3);
    r = review_realloc(q, 2000);
    assert(r);
    check_bytes(r, 17, 0xa3);
    memset(r, 0x4b, 2000);
    before = maps;
    reject_maps = 1;
    assert(review_realloc(r, 8192) == NULL && errno == ENOMEM);
    check_bytes(r, 2000, 0x4b);
    assert(maps == before);
    assert(review_realloc(r, (size_t)-1) == NULL && errno == ENOMEM);
    check_bytes(r, 2000, 0x4b);
    reject_maps = 0;
    p = review_realloc(r, 8192);
    assert(p);
    check_bytes(p, 2000, 0x4b);
    memset(p, 0x5c, 8192);
    reject_maps = 1;
    assert(review_realloc(p, 16384) == NULL && errno == ENOMEM);
    check_bytes(p, 8192, 0x5c);
    reject_maps = 0;
    before_unmaps = unmaps;
    assert(review_realloc(p, 0) == NULL && unmaps == before_unmaps + 1);
    p = review_malloc(32);
    assert(p && review_realloc(p, 0) == NULL);
    puts("compact allocator independent review: PASS");
    printf("maps=%zu unmaps=%zu total page-rounded mapped bytes=%zu\n",
           maps, unmaps, mapped_bytes);
    return 0;
}
