#include <stdlib.h>
static int compare(const void *a,const void *b){return *(const long*)a>*(const long*)b?1:-1;}
int main(void){long values[3]={3,1,2};qsort(values,3,sizeof(long),&compare);return values[0]!=1||values[1]!=2||values[2]!=3;}
