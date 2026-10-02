/* Only the rebuilt full TCC is expected to implement genuine floats/bitfields/VLAs. */
struct B {unsigned short x:5,y:1,z:2;};
int work(int n){enum Local {A=3,B=5};int a[n];int i;for(i=0;i<n;i++)a[i]=i+A;return a[n-1]+B;}
int main(void){double one=1.0;double zero=0.0;double x=one+one;float f=one;long double ld=one;struct B b;b.x=31;b.y=1;b.z=2;if(x!=2||f+f!=2||ld+ld!=2||zero!=0)return 1;if(b.x!=31||b.y!=1||b.z!=2)return 2;if(work(9)!=16)return 3;return 0;}
