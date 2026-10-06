/* Definitions reached only through block-scope declarations in
   block-function-decl.c. */
char block_fn_shared[32] = "provider buffer";

char *block_fn_buffer (void)
{
  return block_fn_shared;
}

/* A pointer above 4 GiB: truncation to int would lose its high bits. */
char *block_fn_high (void)
{
  return (char *) 0x123456789a0UL;
}

long block_fn_add (long a, long b)
{
  return a + b;
}
