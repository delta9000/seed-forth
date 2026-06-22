/* A preprocessor directive may have leading whitespace before the '#'.  The
   directive detector skips blanks to find the '#', but the handler assumed
   pos was already at '#' and consumed one blank instead — so an indented
   #define was elided without registering the macro, leaving ANSWER
   undefined.  With the handler skipping blanks first, ANSWER resolves to 42. */
  #define ANSWER 42
int main() {
  return ANSWER;
}
