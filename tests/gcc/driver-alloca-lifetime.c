#include <stddef.h>
void *C_alloca(size_t);

static void fill(char *p, int value)
{
  int i;
  for (i = 0; i < 64; i++) p[i] = (char)value;
}

static int check(char *p, int value)
{
  int i;
  for (i = 0; i < 64; i++) if (p[i] != (char)value) return 1;
  return 0;
}

static void *second(int tag, void *pointer)
{
  if (tag != 17) return 0;
  return pointer;
}

static int child(char *outer)
{
  char *p = C_alloca(64);
  fill(p, 31);
  return check(outer, 11) || check(p, 31);
}

static int invoke(int (*callback)(char *), char *outer)
{
  return callback(outer);
}

static int recursive(int depth)
{
  char *p = C_alloca(64);
  fill(p, depth + 41);
  if (depth && recursive(depth - 1)) return 1;
  C_alloca(0);
  return check(p, depth + 41);
}

static int same_frame(void)
{
  char *a = C_alloca(64);
  char *b;
  int i;
  fill(a, 11);
  b = second(17, C_alloca(64));
  fill(b, 23);
  C_alloca(0);
  if (check(a, 11) || check(b, 23)) return 1;
  for (i = 0; i < 3; i++) {
    if (child(a)) return 2;
    C_alloca(0);
    if (check(a, 11) || check(b, 23)) return 3;
    if (invoke(child, a)) return 4;
    C_alloca(0);
    if (check(a, 11) || check(b, 23)) return 5;
  }
  return 0;
}

int main(void)
{
  if (same_frame()) return 1;
  C_alloca(0);
  if (recursive(4)) return 2;
  C_alloca(0);
#ifdef OBSERVE_FREES
  {
    extern int observed_allocations, observed_frees, observed_fault;
    if (observed_fault) return 3;
    if (observed_allocations != 13 || observed_frees != observed_allocations) return 4;
  }
#endif
  return 0;
}
