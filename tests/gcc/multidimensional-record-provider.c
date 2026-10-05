#include "multidimensional-record.h"
struct matrix matrix_global = {
    11, {{1,2,3},{4,5,6}},
    {{{1,101},{2,102},{3,103}},{{4,104},{5,105},{6,106}}},
    {"abc","xyz"}, {{7,8,9},{10,11,12}}, 5, 17, 29
};
static int (*scalar_row)[3] = &matrix_global.scalar[1];
static struct cell (*record_row)[3] = &matrix_global.records[1];
static struct cell (*record_matrix)[2][3] = &matrix_global.records;
static long *last_value = &matrix_global.records[1][2].value;
static char *last_char = &matrix_global.text[1][2];
long matrix_layout(int n) {
    struct matrix *p = &matrix_global;
    if(n==0)return sizeof(struct matrix);
    if(n==1)return (char *)&p->scalar-(char *)p;
    if(n==2)return (char *)&p->records-(char *)p;
    if(n==3)return (char *)&p->text-(char *)p;
    if(n==4)return (char *)&p->alias-(char *)p;
    if(n==5)return (char *)&p->tail-(char *)p;
    if(n==6)return sizeof(p->scalar);
    if(n==7)return sizeof(p->scalar[0]);
    if(n==8)return sizeof(p->records);
    if(n==9)return sizeof(p->records[0]);
    if(n==10)return sizeof(p->records[0][0]);
    if(n==11)return sizeof(struct nested);
    return sizeof(union matrix_union);
}
long matrix_read(struct matrix *p,int i,int j) {
    return p->scalar[i][j]+p->records[i][j].value+p->alias[i][j];
}
void matrix_fill(struct matrix *p) {
    int i,j;
    for(i=0;i<2;i++)for(j=0;j<3;j++) {
        p->scalar[i][j]=i*10+j;
        p->records[i][j].tag=i*3+j;
        p->records[i][j].value=i*100+j;
        p->alias[i][j]=i*1000+j;
    }
    p->lead=31;p->tail=47;p->bits=3;p->more=19;
    p->text[0][0]='a';p->text[1][3]='z';
}
struct tiny tiny_roundtrip(struct tiny p){p.values[1][2]+=3;return p;}
struct pair pair_roundtrip(struct pair p){p.values[0][1]+=7;return p;}
struct matrix matrix_roundtrip(struct matrix p){p.scalar[1][2]+=5;p.records[1][2].value+=9;return p;}
int matrix_checks(void) {
    struct matrix p = {1,{2,3,4,5,6,7},{{{8,9}},{{10,11}}},{"ab","cd"},{{12},{13}},2,4,6};
    struct matrix copy;
    struct nested n;
    union matrix_union u;
    const struct matrix *qualified = &matrix_global;
    struct { char before; struct { int values[2][3]; }; char after; } promoted;
    int (*row)[3] = p.scalar;
    struct cell (*records)[3] = p.records;
    int i=0;
    if(sizeof(p.scalar[i++])!=12||i!=0)return 1;
    if(sizeof(qualified->records)!=96||sizeof(qualified->records[1])!=48)return 2;
    if(qualified->records[1][2].value!=106)return 3;
    if((*scalar_row)[2]!=6||(*record_row)[2].value!=106)return 4;
    if((*record_matrix)[1][2].value!=106||*last_value!=106||*last_char!='z')return 5;
    if(p.records[0]->value!=9||p.records[1]->value!=11)return 15;
    if(p.scalar[1][2]!=7||p.records[0][0].value!=9||p.records[1][0].value!=11)return 6;
    if(p.records[0][2].value||p.records[1][2].value||p.alias[1][2])return 7;
    if(p.text[0][2]||p.text[1][2]||p.tail!=6||p.bits!=2||p.more!=4)return 8;
    if((char *)(row+1)-(char *)row!=12||(row+2)-row!=2)return 9;
    if((char *)(records+1)-(char *)records!=48||(records+2)-records!=2)return 10;
    row[1][2]=71;records[1][2].value=83;
    copy=p;copy.scalar[1][2]=91;
    if(p.records[0]->value!=9||p.records[1]->value!=11)return 15;
    if(p.scalar[1][2]!=71||p.records[1][2].value!=83||copy.scalar[1][2]!=91)return 11;
    n.matrix=p;n.matrix.scalar[1][1]=44;n.tail=39;
    if(n.matrix.scalar[1][1]!=44||n.matrix.records[1][2].value!=83||n.tail!=39)return 12;
    u.records[1][2].value=117;
    if(u.records[1][2].value!=117||sizeof(u)!=96)return 13;
    promoted.before=3;promoted.values[1][2]=51;promoted.after=7;
    if(promoted.values[1][2]!=51||promoted.before!=3||promoted.after!=7)return 14;
    return 0;
}
