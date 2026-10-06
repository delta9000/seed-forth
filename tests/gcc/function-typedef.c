/* Typedefs of function types, as bash 2.05b and readline declare
   Function, VFunction, CPFunction, sh_builtin_func_t and
   rl_command_func_t: the typedef names the function type itself, not a
   pointer to it. */
int printf (const char *, ...);

typedef int Function ();
typedef void VFunction (int);
typedef char *CPFunction ();
typedef int sh_fn_t (char *);
typedef Function Function2;

/* Each declares a function; the definitions follow later. */
Function seven;
sh_fn_t count_chars;
CPFunction fn_high;

char fn_buffer[16] = "buffer";

static int last_seen;

static void remember (int x)
{
  last_seen = x;
}

static char *buffer_of (void)
{
  return fn_buffer;
}

static Function *pick (int which)
{
  return which ? seven : 0;
}

/* A parameter of function type adjusts to a pointer to that function. */
static int apply (sh_fn_t f, char *s)
{
  return f (s);
}

/* So does an identifier-list definition's declared parameter. */
static int apply_old (f, s)
     sh_fn_t f;
     char *s;
{
  return f (s) * 10;
}

/* A block-scope declaration through the typedef, without extern. */
static int local_seven (void)
{
  Function seven;
  return seven ();
}

struct command
{
  const char *name;
  VFunction *callback;
  sh_fn_t *count;
};

static struct command commands[2] = {
  {"remember", remember, count_chars},
  {"none", 0, 0}
};

int main (void)
{
  Function *p = seven;
  Function2 *q = p;
  sh_fn_t *counter = count_chars;
  CPFunction *table[3];
  int failures = 0;
  table[0] = buffer_of;
  table[1] = fn_high;
  table[2] = 0;
  {
    extern CPFunction getenv;
    char *value = getenv ("FUNCTION_TYPEDEF_VALUE");
    printf ("getenv %s above-4GiB %d\n", value ? value : "(null)",
            value ? (unsigned long) value >> 32 != 0 : -1);
    failures += value == 0;
  }
  printf ("seven %d %d %d\n", p (), q (), pick (1) ());
  printf ("count %d apply %d %d local %d\n", counter ("abcd"),
          apply (count_chars, "xy"), apply_old (count_chars, "xyz"),
          local_seven ());
  printf ("table %s %lx %d\n", table[0] (), (unsigned long) table[1] (),
          table[2] == 0);
  commands[0].callback (commands[0].count ("hello"));
  printf ("callback %s %d none %d\n", commands[0].name, last_seen,
          commands[1].callback == 0);
  printf ("sizes %d %d\n", (int) sizeof (Function *), (int) sizeof table);
  printf ("cast %d\n", (Function *) 0 == pick (0));
  failures += p () != 7 || counter ("abcd") != 4 || last_seen != 5;
  failures += table[0] () != fn_buffer;
  failures += (unsigned long) table[1] () != 0x123456789a0UL;
  printf ("failures %d\n", failures);
  return failures != 0;
}

int seven ()
{
  return 7;
}

int count_chars (char *s)
{
  int n = 0;
  while (s[n])
    n++;
  return n;
}

char *fn_high ()
{
  return (char *) 0x123456789a0UL;
}
