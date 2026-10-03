#include "aggregate-layout.h"
#include <sys/mman.h>
#include <unistd.h>
int main(void) {
  long page=sysconf(_SC_PAGESIZE);char *m=mmap(0,2*page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
  struct Three *t;struct Nine *n;struct Three r;struct Nine s;struct Pair p={7,2};int i;
  if(m==MAP_FAILED||mprotect(m+page,page,PROT_NONE))return 1;
  t=(struct Three *)(m+page-3);t->a[0]=11;t->a[1]=22;t->a[2]=33;
  r=agg_read_three(t);if(r.a[0]!=11||r.a[1]!=22||r.a[2]!=33)return 2;
  n=(struct Nine *)(m+page-9);for(i=0;i<9;i++)n->a[i]=i+17;
  s=agg_read_nine(n);for(i=0;i<9;i++)if(s.a[i]!=i+17)return 3;
  if(agg_double(p)!=3.5)return 4;
  return munmap(m,2*page)!=0;
}
