#include <stdlib.h>
#include "obstack.h"
struct counts { long allocations; long releases; };
long plain_allocations;
long plain_releases;
struct _obstack_chunk *allocate_plain(long n) {
    plain_allocations++;
    return malloc(n);
}
void release_plain(void *p) { plain_releases++; free(p); }
struct _obstack_chunk *allocate_extra(void *context, long n) {
    struct counts *c = context;
    c->allocations++;
    return malloc(n);
}
void release_extra(void *context, struct _obstack_chunk *p) {
    struct counts *c = context;
    c->releases++;
    free(p);
}
int exercise(struct obstack *h) {
    int i;
    for (i = 0; i < 12; i++) h->object_base[i] = i + 41;
    h->next_free = h->object_base + 12;
    _obstack_newchunk(h, 400);
    if (h->next_free - h->object_base != 12) return 1;
    for (i = 0; i < 12; i++) if (h->object_base[i] != i + 41) return 2;
    if (_obstack_memory_used(h) < 412) return 3;
    _obstack_free(h, 0);
    return 0;
}
int main(void) {
    struct obstack plain;
    struct obstack extra;
    struct counts counts;
    counts.allocations = 0;
    counts.releases = 0;
    /* These boundary conversions are only storage. obstack restores the
       callbacks' actual types before calls in both dispatch branches. */
    if (!_obstack_begin(&plain, 128, 8, (void *(*)(long))allocate_plain, release_plain)) return 10;
    if (plain.use_extra_arg || plain.maybe_empty_object || plain.alloc_failed) return 11;
    if (exercise(&plain)) return 12;
    if (plain_allocations != 2 || plain_releases != 2) return 13;
    if (!_obstack_begin_1(&extra, 128, 8, (void *(*)(void *, long))allocate_extra,
                         (void (*)(void *, void *))release_extra, &counts)) return 20;
    if (!extra.use_extra_arg || extra.maybe_empty_object || extra.alloc_failed) return 21;
    if (exercise(&extra)) return 22;
    if (counts.allocations != 2 || counts.releases != 2) return 23;
    return 0;
}
