/* hello.c -- tcc-boot2 builds a static hello world (sf-pnut-amd64-check.sh).
   Exit status 7; stdout must equal hello.out. */
#include <stdio.h>
int main(int argc, char **argv) {
  long long x = 1;
  long l = 1;
  x = x << 40; l = l << 40;
  printf("hello from tcc-boot2, argc=%d\n", argc);
  printf("lld %lld ld %ld sizeof(long)=%d ptr=%d\n", x, l, (int)sizeof(long), (int)sizeof(void*));
  printf("c=%c x=%x s=%s\n", 'Z', 255, argv[1]);
  return 7;
}
