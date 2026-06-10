/* A store through a char* must write exactly one byte.  The buggy codegen
   emits a qword `mov [rcx], rdi` for the unary-`*` deref (it only set
   byte-width for the `p[i]` subscript form), so `*p = 1` writes 8 bytes and
   zeroes buf[1..7].  buf is filled with 2; after `*p = 1` only buf[0] should
   change, so buf[0..4] sum to 1+2+2+2+2 = 9.  The buggy qword store makes
   them 1+0+0+0+0 = 1. */
char buf[8];
int main() {
  char *p;
  int i;
  i = 0;
  while (i < 8) { buf[i] = 2; i = i + 1; }
  p = buf;
  *p = 1;
  return buf[0] + buf[1] + buf[2] + buf[3] + buf[4];
}
