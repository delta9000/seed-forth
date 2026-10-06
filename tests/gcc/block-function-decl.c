/* Block-scope function declarations, as GNU make 3.82, bash and coreutils
   write them.  Nothing at file scope declares getenv, open, close or the
   provider functions: each call goes through a declaration in a block. */
int printf (const char *, ...);
extern char **environ;
extern char block_fn_shared[];
long block_fn_add (long, long);

/* getenv's result, found independently by scanning environ. */
static char *expected_value (const char *name)
{
  char **entry;
  for (entry = environ; *entry; entry++)
    {
      char *text = *entry;
      const char *want = name;
      while (*want && *text == *want)
        text++, want++;
      if (*want == 0 && *text == '=')
        return text + 1;
    }
  return 0;
}

static int check_extern (void)
{
  extern char *getenv ();
  char *value = getenv ("BLOCK_FN_VALUE");
  if (value == 0 || value != expected_value ("BLOCK_FN_VALUE"))
    return 1;
  printf ("extern getenv %s above-4GiB %d\n", value,
          (unsigned long) value >> 32 != 0);
  return 0;
}

static int check_plain (void)
{
  int a[3];
  char *getenv ();
  char *value;
  a[0] = 7;
  value = getenv ("BLOCK_FN_VALUE");
  if (value != expected_value ("BLOCK_FN_VALUE"))
    return 1;
  printf ("plain getenv %s %d\n", value, a[0]);
  return 0;
}

static int check_switch (int x)
{
  switch (x)
    {
    case 1:
      {
        extern char *getenv ();
        return getenv ("BLOCK_FN_MISSING") == 0;
      }
    }
  return 0;
}

static int check_provider (void)
{
  extern char *block_fn_buffer ();
  extern char *block_fn_high ();
  char *buffer = block_fn_buffer ();
  char *high = block_fn_high ();
  printf ("provider %s same %d high %lx\n", buffer, buffer == block_fn_shared,
          (unsigned long) high);
  return buffer == block_fn_shared && (unsigned long) high == 0x123456789a0UL ? 0 : 1;
}

static long check_redeclared (void)
{
  extern long block_fn_add ();
  return block_fn_add (40L, 2L);
}

static int check_prototyped (void)
{
  extern int open (const char *, int, ...);
  extern int close (int);
  int fd = open ("/dev/null", 0);
  printf ("open %d close %d\n", fd >= 0, fd >= 0 ? close (fd) : -1);
  return fd >= 0 ? 0 : 1;
}

static int check_pointer (void)
{
  extern char *getenv ();
  char *(*lookup) () = getenv;
  char *(*copy) () = lookup;
  return copy ("BLOCK_FN_VALUE") == getenv ("BLOCK_FN_VALUE") ? 0 : 1;
}

static int check_later (void)
{
  extern int block_fn_later (int);
  return block_fn_later (5);
}

/* Each declaration ends with its block; the name may then be reused. */
static int check_scope (void)
{
  {
    extern char *block_fn_buffer ();
    if (block_fn_buffer () != block_fn_shared)
      return 1;
  }
  {
    int block_fn_buffer = 3;
    return block_fn_buffer - 3;
  }
}

int main (void)
{
  int failures = 0;
  failures += check_extern ();
  failures += check_plain ();
  failures += check_switch (1) != 1;
  failures += check_switch (2) != 0;
  failures += check_provider ();
  printf ("redeclared %ld\n", check_redeclared ());
  failures += check_redeclared () != 42;
  failures += check_prototyped ();
  failures += check_pointer ();
  printf ("later %d\n", check_later ());
  failures += check_later () != 15;
  failures += check_scope ();
  printf ("failures %d\n", failures);
  return failures != 0;
}

int block_fn_later (int x)
{
  return x * 3;
}
