int sum(int a,int b,int c,int d,int e,int f,int g,int h) { return a+b+c+d+e+f+g+h; }
int add(int a,int b) { return a+b; }
int main(void) { int (*fp)(int,int)=add; return sum(1,2,3,4,5,6,7,8) + fp(19,23) - 78; }
