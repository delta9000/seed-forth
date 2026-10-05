typedef long row[3];
row a={4,5,6};row *p=&a;
long bytes=(long)&((row*)0)[2];
long *q=&((row*)0)[2][1];
int main(void){if((*p)[1]!=5)return 1;if(bytes!=48)return 2;if((long)q!=56)return 3;return 0;}
