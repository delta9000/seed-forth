/* Independent C90 scope/fixup fixture. Every implicit call returns int. */
struct review_implicit_tag { int member; };

int review_first(void)
{
  int result;
  int (*function)(int);
  result = review_external(4);
  function = review_external;
  return result + function(5);
}

int review_second(void)
{
  int result;
  result = 0;
  {
    int reused;
    reused = 7;
    result = review_external(reused);
  }
  {
    int review_external;
    review_external = 3;
    result = result + review_external;
  }
  {
    int reused;
    reused = 8;
    result = result + review_external(reused);
  }
  return result;
}

int review_third(void)
{
  int a;
  int b;
  a = review_negative();
  b = review_eight(1, 2, 3, 4, 5, 6, 7, 8);
  return a + b;
}

int review_fourth(void)
{
  unsigned char promoted;
  promoted = 253;
  return review_oldstyle(promoted) + review_implicit_tag(9);
}

int review_fifth(void)
{
  return review_eight(8, 7, 6, 5, 4, 3, 2, 1) + review_negative();
}

int main(void)
{
  if (review_first() != 23) return 1;
  if (review_second() != 32) return 2;
  if (review_third() != 1) return 3;
  if (review_fourth() != 271) return 4;
  if (review_fifth() != -83) return 5;
  return 0;
}
