/* Conditional compilation: #if with arithmetic and defined(), #ifdef,
   #ifndef, #elif, #else, nesting, a dropped group holding text that is
   not C, and #undef.  Only the kept groups add to r: exit 1+2+4+8+16+32. */
#define ONE 1
#define TWO (ONE + ONE)
#define EMPTY
int main() {
  int r = 0;
#if TWO == 2 && defined(ONE) && !defined(NOPE)
  r = r + 1;
#else
  r = r + 100;
#endif
#ifdef EMPTY
  r = r + 2;
#endif
#ifndef NOPE
  r = r + 4;
#endif
#if 0
  this isn't C, and neither is "this
#elif defined NOPE
  r = r + 100;
#elif TWO > ONE
  r = r + 8;
#  if 0
  r = r + 100;
#  else
  r = r + 16;
#  endif
#else
  r = r + 100;
#endif
#undef ONE
#ifdef ONE
  r = r + 100;
#else
  r = r + 32;
#endif
  return r;
}
