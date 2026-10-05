typedef long row[3];
long descriptor_gp(int,...);
long descriptor_stack(long,long,long,long,long,long,...);
long descriptor_array(int,...);
long descriptor_sse(int,...);
/* Deliberately unprototyped in this translation unit: C90 promotions apply. */
long descriptor_unspecified();
static long triple(long n){return n*3;}
int main(void){row values[2]={{4,5,6},{7,8,9}};
 if(descriptor_gp(0,triple,14L)!=42)return 1;
 if(descriptor_stack(1,2,3,4,5,6,&triple,7L)!=42)return 2;
 if(descriptor_array(0,values)!=13)return 3;
 if(descriptor_sse(0,2.5,triple,14L)!=42)return 4;
 if(descriptor_unspecified(triple,3L,values)!=14)return 5;
 return 0;
}
