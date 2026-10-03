#include <stdlib.h>
#include <limits.h>
int main(void)
{
    int (*call)(int) = abs;
    int i;
    int values[9] = {0,1,-1,127,-128,32767,-32768,INT_MAX,-INT_MAX};
    int expected[9] = {0,1,1,127,128,32767,32768,INT_MAX,INT_MAX};
    for (i=0; i<9; ++i) if (call(values[i]) != expected[i]) return i+1;
    return 0;
}
