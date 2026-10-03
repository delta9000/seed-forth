/* Exercise the unchanged GCC 4 obstack header's non-GNU macro branch. */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#undef __GNUC__
#include "obstack.h"

#ifdef REVIEW_OBSTACK_EXTERNAL
long review_obstack_finish(struct obstack *, int);
long review_obstack_size(void);
#else
long review_obstack_finish(struct obstack *h, int n) {
  int i;
  char *start;
  for (i = 0; i < n; i++) obstack_1grow_fast(h, 33+i);
  start = (char *)obstack_finish(h);
  return start - (char *)h->chunk;
}

long review_obstack_size(void) { return sizeof(struct obstack); }
#endif

#ifdef REVIEW_OBSTACK_MAIN
int main(void) {
  struct obstack h;
  char *bytes;
  char *base;
  int flags;
  int n;
  int i;
  long got;
  bytes = (char *)malloc(4096);
  if (!bytes) return 1;
  for (flags = 0; flags < 8; flags++) {
    for (n = 0; n < 32; n++) {
      memset(&h, 0, sizeof h);
      memset(bytes, 0x5A, 4096);
      h.chunk_size = 4096;
      h.chunk = (struct _obstack_chunk *)bytes;
      h.chunk->prev = 0;
      h.chunk->limit = bytes + 4096;
      base = bytes + 32;
      h.object_base = base;
      h.next_free = base;
      h.chunk_limit = bytes + 4096;
      h.alignment_mask = 7;
      h.extra_arg = bytes + 4000;
      h.use_extra_arg = flags & 1;
      h.maybe_empty_object = (flags >> 1) & 1;
      h.alloc_failed = (flags >> 2) & 1;
      got = review_obstack_finish(&h, n);
      if (review_obstack_size() != sizeof h || got != 32) return 2;
      if (h.object_base != base + ((n+7)&~7) || h.next_free != h.object_base) return 3;
      if (h.maybe_empty_object != (((flags>>1)&1) || n==0)) return 4;
      if (h.use_extra_arg != (flags&1) || h.alloc_failed != ((flags>>2)&1)) return 5;
      if (h.chunk_size != 4096 || h.chunk != (struct _obstack_chunk *)bytes ||
          h.chunk_limit != bytes+4096 || h.extra_arg != bytes+4000) return 6;
      for (i = 0; i < n; i++) if (base[i] != 33+i) return 7;
      if (base[n] != 0x5A || base[-1] != 0x5A) return 8;
    }
  }
  free(bytes);
  puts("PASS: original obstack header, 256 finish/grow/flag-preservation cases");
  return 0;
}
#endif
