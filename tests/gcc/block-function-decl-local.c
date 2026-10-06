/* Block-scope function declarations within one program, for the
   whole-program System V target as well as objects: a declaration before
   the definition, one after it, the same name in two blocks, a prototype
   whose address is taken, and a name reused once its block has ended. */
static char store[8];

char *early (void)
{
  return store;
}

static int before_and_after (void)
{
  extern char *early ();
  extern char *late ();
  return (early () == store) + (late () == store + 1);
}

static int scoped (void)
{
  {
    extern char *late ();
    if (late () != store + 1)
      return 9;
  }
  {
    int late = 4;
    return late;
  }
}

static int in_switch (int x)
{
  switch (x)
    {
    case 1:
      {
        extern long sum (long, long);
        long (*f) (long, long) = sum;
        return (int) f (2L, 3L);
      }
    }
  return 0;
}

char *late (void)
{
  return store + 1;
}

long sum (long x, long y)
{
  return x + y;
}

int main (void)
{
  return before_and_after () * 100 + scoped () * 10 + in_switch (1) - 245;
}
