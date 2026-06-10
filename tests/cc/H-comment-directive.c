/* A block comment after a directive's tokens can run past the newline.  The
   preprocessor elides the rest of a directive line, but it was not comment-
   aware: while eliding it swallowed the comment opener and left the comment
   closer on the next line as stray tokens, breaking the parse.  Skipping the
   whole comment keeps THREE defined and the value 3 reaching main. */
#define THREE 3 /* the value
   spans two lines */
int main() {
  return THREE;
}
