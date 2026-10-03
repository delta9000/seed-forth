/* Test double only: observe the original reclamation algorithm separately
   from its production run using the actual mmap allocator. */
#include <stddef.h>
#include <seed-syscall.h>
static unsigned char arena[8192];
static size_t cursor;
static void *allocations[32];
static size_t lengths[32];
static int released[32];
int observed_allocations;
int observed_frees;
int observed_fault;

void abort(void)
{
  for (;;) __seed_syscall6(60, 99, 0, 0, 0, 0, 0);
}

void *xmalloc(size_t size)
{
  void *p;
  if (observed_allocations == 32 || cursor + size > sizeof(arena)) abort();
  p = arena + cursor;
  cursor = (cursor + size + 15) & ~15UL;
  allocations[observed_allocations] = p;
  lengths[observed_allocations] = size;
  observed_allocations++;
  return p;
}

void free(void *pointer)
{
  int i;
  size_t j;
  unsigned char *bytes = pointer;
  for (i = 0; i < observed_allocations; i++) {
    if (allocations[i] == pointer) {
      if (released[i]) observed_fault = 1;
      released[i] = 1;
      observed_frees++;
      for (j = 0; j < lengths[i]; j++) bytes[j] = 221;
      return;
    }
  }
  observed_fault = 1;
}
