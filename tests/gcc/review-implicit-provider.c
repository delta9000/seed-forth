/* Definitions agree with the default-promoted arguments in the caller. */
int review_external(int value) { return value + 7; }
int review_negative(void) { return -203; }
int review_eight(int a, int b, int c, int d, int e, int f, int g, int h)
{
  return a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*h;
}
int review_oldstyle(value) unsigned char value; { return value; }
int review_implicit_tag(int value) { return 2*value; }
