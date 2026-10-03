/* Host-only ABI/storage oracle; never a bootstrap artifact. */
#include <stdio.h>
long host_value=40;
int host_function(int x) { return x+2; }
int check_storage(void);
extern char banner[4];
extern int tentative[3];
extern int zeroed[4];
int main(void) {
  int result=check_storage();
  if(result) { printf("storage failure %d\n",result); return result; }
  if(host_value!=42 || banner[3]!=0 || tentative[2]!=42 || zeroed[3]!=0) return 20;
  puts("PASS: ELF globals, arrays, strings, address relocations and static-local identity");
  return 0;
}
