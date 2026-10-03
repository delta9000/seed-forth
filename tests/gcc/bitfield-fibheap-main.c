#include <stdlib.h>
#include <stdio.h>
#include "ansidecl.h"
#include "fibheap.h"
void *xcalloc(size_t n,size_t size) { void *p=calloc(n,size);if (!p) abort();return p; }
int main(void) {
  fibheap_t h; fibheap_t other; fibnode_t nodes[144];
  long keys[144]; int live[144]; int i; int j; int best; long count;
  h=fibheap_new();other=fibheap_new();
  for(i=0;i<144;i++){ keys[i]=1000+(i*73)%144;live[i]=1;
    nodes[i]=fibheap_insert(i<128?h:other,keys[i],(void *)(long)(i+1)); }
  h=fibheap_union(h,other);
  for(j=0;j<5;j++) {
    best=-1;for(i=0;i<144;i++)if(live[i]&&(best<0||keys[i]<keys[best]))best=i;
    if ((long)fibheap_extract_min(h)!=best+1) return 1;live[best]=0;
  }
  for(i=0;i<144;i++)if(live[i]&&i%5==0) {
    if(fibheap_replace_key(h,nodes[i],-100-i)!=keys[i]) return 2;
    keys[i]=-100-i;
  }
  for(i=0;i<144;i++)if(live[i]&&i%17==0) {
    if((long)fibheap_delete_node(h,nodes[i])!=i+1) return 3;live[i]=0;
  }
  count=0;
  for(;;) {
    best=-1;for(i=0;i<144;i++)if(live[i]&&(best<0||keys[i]<keys[best]))best=i;
    if(best<0)break;
    if(fibheap_empty(h))return 4;
    if(fibheap_min_key(h)!=keys[best])return 5;
    if((long)fibheap_min(h)!=best+1)return 6;
    if((long)fibheap_extract_min(h)!=best+1)return 7;
    live[best]=0;count++;
  }
  if(!fibheap_empty(h)||fibheap_extract_min(h)!=0)return 8;
  fibheap_delete(h);
  printf("fibheap: %ld ordered extractions after union, decreases and deletions\n",count);
  return 0;
}
