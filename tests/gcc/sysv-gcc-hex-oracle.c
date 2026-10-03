/* Both proof routes compile this against the unchanged GCC header. */
#include "libiberty.h"
int main(void) {
  int i;
  int expected;
  hex_init();
  for(i=0;i<_hex_array_size;i++) {
    expected=_hex_bad;
    if(i>='0' && i<='9') expected=i-'0';
    else if(i>='A' && i<='F') expected=i-'A'+10;
    else if(i>='a' && i<='f') expected=i-'a'+10;
    if(hex_value(i)!=(unsigned int)expected) return 1;
    if(hex_p(i)!=(expected!=_hex_bad)) return 2;
  }
  i='A';
  if(hex_value(i++)!=10 || i!='B') return 3;
  return 0;
}
