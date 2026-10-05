#include <stdio.h>
#include "multidimensional-record.h"
int main(void) {
    struct matrix x,y;
    struct tiny t={{{1,2,3},{4,5,6}}},tr;
    struct pair p={{{11,12}}},pr;
    struct nested n;
    long want[13];
    int i;
    want[0]=sizeof(x);want[1]=(char *)&x.scalar-(char *)&x;
    want[2]=(char *)&x.records-(char *)&x;want[3]=(char *)&x.text-(char *)&x;
    want[4]=(char *)&x.alias-(char *)&x;want[5]=(char *)&x.tail-(char *)&x;
    want[6]=sizeof(x.scalar);want[7]=sizeof(x.scalar[0]);
    want[8]=sizeof(x.records);want[9]=sizeof(x.records[0]);
    want[10]=sizeof(x.records[0][0]);want[11]=sizeof(n);want[12]=sizeof(union matrix_union);
    for(i=0;i<13;i++)if(matrix_layout(i)!=want[i])return 10+i;
    matrix_fill(&x);
    if(matrix_read(&x,1,2)!=1116||x.lead!=31||x.tail!=47||x.bits!=3||x.more!=19)return 30;
    if(x.scalar[0][1]!=1||x.records[0][1].value!=1||x.text[1][3]!='z')return 31;
    y=matrix_roundtrip(x);
    if(y.scalar[1][2]!=17||y.records[1][2].value!=111||x.scalar[1][2]!=12)return 32;
    tr=tiny_roundtrip(t);pr=pair_roundtrip(p);
    if(tr.values[1][2]!=9||t.values[1][2]!=6||pr.values[0][1]!=19||p.values[0][1]!=12)return 33;
    i=matrix_checks();if(i)return 40+i;
    printf("matrix: %ld %ld %ld %ld %ld %ld; mixed ABI and execution passed\n",want[0],want[1],want[2],want[3],want[4],want[5]);
    return 0;
}
