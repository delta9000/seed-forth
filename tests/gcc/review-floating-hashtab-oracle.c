/* Host-only oracle for the untouched GCC 4.0.4 translation unit. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "hashtab.h"

void *xcalloc(size_t count,size_t size) {
  void *p=calloc(count,size); if(!p) abort(); return p;
}
/* The seed runtime uses an accessor for stderr. This host-only definition
   satisfies the otherwise unused hashtab allocation-failure path. */
FILE *__seed_stderr(void) { return stderr; }
static uint64_t bits(double x) { uint64_t u; memcpy(&u,&x,8); return u; }
int main(void) {
  const unsigned int edges[]={0,1,2,3,7,16777215U,16777216U,16777217U,
      2147483647U,2147483648U,4294967294U,4294967295U};
  struct htab table;
  unsigned checks=0;
  memset(&table,0,sizeof(table));
  for(unsigned i=0;i<sizeof(edges)/sizeof(edges[0]);i++)
    for(unsigned j=0;j<sizeof(edges)/sizeof(edges[0]);j++) {
      table.searches=edges[i]; table.collisions=edges[j];
      volatile unsigned int searches=table.searches,collisions=table.collisions;
      double expected=searches ? (double)collisions/(double)searches : 0.0;
      double result=htab_collisions(&table);
      if(bits(result)!=bits(expected)) {
        fprintf(stderr,"htab_collisions(%u,%u): %.17g != %.17g\n",
                table.searches,table.collisions,result,expected);
        return 1;
      }
      checks++;
    }
  printf("PASS: untouched hashtab.c htab_collisions %u checks\n",checks);
  return 0;
}
