#ifndef SEED_GCC_SYS_MMAN_H
#define SEED_GCC_SYS_MMAN_H
/* Original seed-forth declarations; Linux AMD64 LP64, 4096-byte pages.
   Only private mappings and these protection bits are implemented.
   See ../../MAPPING.md for bounds and ownership. */
#include <sys/types.h>
#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 32
#define MAP_ANON MAP_ANONYMOUS
#define MAP_FAILED ((void *)-1)
void *mmap(void *address, size_t length, int protection, int flags,
           int descriptor, off_t offset);
int munmap(void *address, size_t length);
#endif
