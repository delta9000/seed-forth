/* Independently designed ABI fixture. Compiled by seed Forth for the target;
   host compilation of this same input is used only as a semantic oracle. */
typedef long (*review_callback8)(long,long,long,long,long,long,long,long);
typedef long (*review_variadic)(long,...);
typedef long (*review_narrow_callback)(signed char,unsigned char,short,unsigned short,int,unsigned int,long,unsigned long);
long review_zero(void) { return 42; }
long review_six(long a,long b,long c,long d,long e,long f) {
    return a+3*b+5*c+7*d+11*e+13*f;
}
long review_seven(long a,long b,long c,long d,long e,long f,long g) {
    return review_six(a,b,c,d,e,f)+17*g;
}
long review_eight(long a,long b,long c,long d,long e,long f,long g,long h) {
    return review_seven(a,b,c,d,e,f,g)+19*h;
}
long review_twelve(long a,long b,long c,long d,long e,long f,long g,long h,
                   long i,long j,long k,long l) {
    return review_eight(a,b,c,d,e,f,g,h)+23*i+29*j+31*k+37*l;
}
long review_recursion(long n) {
    if (n < 2) return n;
    return review_recursion(n-1)+review_recursion(n-2);
}
long review_operands(long x) {
    return (x*3+review_seven(1,2,3,4,5,6,7))*5
         + (review_eight(8,7,6,5,4,3,2,1)+x*7)*11
         + review_eight(review_zero(),review_recursion(8),3,4,
                        review_six(1,2,3,4,5,6),6,7,review_recursion(9));
}
long review_narrow(signed char a,unsigned char b,short c,unsigned short d,
                   int e,unsigned int f,long g,unsigned long h) {
    if (a != -128) return 1;
    if (b != 255) return 2;
    if (c != -32768) return 3;
    if (d != 65535) return 4;
    if (e != (-2147483647-1)) return 5;
    if (f != 4294967295U) return 6;
    if (g != -4294967297L) return 7;
    if (h != 18446744073709551615UL) return 8;
    return 0;
}
signed char review_return_char(long a) { return a; }
unsigned char review_return_uchar(long a) { return a; }
short review_return_short(long a) { return a; }
unsigned short review_return_ushort(long a) { return a; }
int review_return_int(long a) { return a; }
unsigned int review_return_uint(long a) { return a; }
long review_callback(review_callback8 f,long a,long b,long c,long d,
                     long e,long g,long h,long i) {
    long saved;
    saved = a*31 + i*37;
    return f(a,b,c,d,e,g,h,i) + 3*f(i,h,g,e,d,c,b,a) + saved;
}
long review_call_narrow(review_narrow_callback f) {
    return f(128,255,32768,65535,2147483648UL,4294967295UL,
             -4294967297L,18446744073709551615UL);
}
long review_call_variadic(review_variadic f) {
    signed char a; unsigned short b; unsigned int c;
    a=-1; b=65535; c=4294967295U;
    return f(8L,a,b,c,4L,5L,6L,7L,8L);
}
long review_control(long x) {
    long sum; long i;
    sum=0;
    for (i=0;i<x;i=i+1) {
        switch (i%3) {
        case 0: sum=sum+review_recursion(5); break;
        case 1: sum=review_zero()+sum; break;
        default: sum=sum+review_seven(1,2,3,4,5,6,7); break;
        }
        if (i==7) goto finish;
    }
finish:
    return sum;
}
/* Pointer export avoids giving the target a dependency on a host linker. */
long main(long which) {
    if (which==0) return (long)review_zero;
    if (which==1) return (long)review_six;
    if (which==2) return (long)review_seven;
    if (which==3) return (long)review_eight;
    if (which==4) return (long)review_twelve;
    if (which==5) return (long)review_recursion;
    if (which==6) return (long)review_operands;
    if (which==7) return (long)review_narrow;
    if (which==8) return (long)review_return_char;
    if (which==9) return (long)review_return_uchar;
    if (which==10) return (long)review_return_short;
    if (which==11) return (long)review_return_ushort;
    if (which==12) return (long)review_return_int;
    if (which==13) return (long)review_return_uint;
    if (which==14) return (long)review_callback;
    if (which==15) return (long)review_call_narrow;
    if (which==16) return (long)review_call_variadic;
    if (which==17) return (long)review_control;
    return 0;
}
