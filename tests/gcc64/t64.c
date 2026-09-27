#include <stdio.h>
#include <stdint.h>
int main(void){ volatile uint64_t a=0x123456789abcdef0ULL, b=0xfedcba9876543210ULL; volatile int64_t c=-5;
  uint64_t m=a*b, q=b/(a>>32), r=b%1000003; int64_t d=c*1000000000000LL/7;
  printf("%llx %llu %llu %lld %d\n",(unsigned long long)m,(unsigned long long)q,(unsigned long long)r,(long long)d,(int)sizeof(void*));
  return !(m==0x236d88fe5618cf00ULL && q==60129542263ULL && r==713574 && sizeof(void*)==8 && d==-714285714285LL); }
