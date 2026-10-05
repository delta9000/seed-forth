typedef int A[3];
A values[2]={{1,2,3},{4,5,6}};
A *p=values;
A *next=values+1;
A *choose=1?values:values+1;
A *choose_next=0?values:values+1;
A *nil=0?values:0;
int raw[2][3]={{7,8,9},{10,11,12}};
A *rawp=raw;
extern A incomplete[];
A *outer_unknown=incomplete;
A incomplete[2]={{13,14,15},{16,17,18}};
typedef A *slots[2];
slots pointers={values,values+1};
A **slotp=pointers;
int review(void){return sizeof(*p)==12 && p[1][2]==6 && (p+1)-p==1 ? 0 : 1;}
int main(void){
 if(review())return 1;
 if(next[0][2]!=6 || choose[1][0]!=4 || choose_next[0][1]!=5 || nil!=0)return 2;
 if(rawp[1][2]!=12 || outer_unknown[1][1]!=17)return 3;
 if((*slotp)[0][1]!=2 || slotp[1][0][2]!=6)return 4;
 return 0;
}
