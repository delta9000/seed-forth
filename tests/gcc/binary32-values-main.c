/* Executed after Forth-only compilation and linking of separate objects. */
#include <stdarg.h>
float seed_ten(float,float,float,float,float,float,float,float,float,float);
float seed_outbound(float);
double seed_varout(float);
double seed_unproto(float);
double seed_varin(float,float,float,float,float,float,float,float,float,int,...);
float seed_callback(float (*)(float),float);
float seed_narrow(double);
double seed_widen(float);
float seed_from_ul(unsigned long);
unsigned long seed_to_ul(float);
float host_return32(float x){return x+3;}
float host_ten32(float a,float b,float c,float d,float e,float f,float g,float h,float i,float j){return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j;}
double host_var32(int n,...){va_list ap;double sum=0;int i;va_start(ap,n);for(i=0;i<n;i++)sum+=va_arg(ap,double);va_end(ap);return sum;}
double host_unproto32(double x){return x+3;}
int main(void){float a=(float)1.000000059604644775390625;float b=(float)1.000000059604645;float c;
 if(sizeof(float)!=4 || sizeof(double)!=8)return 1;
 if(a!=1 || b!=(float)1.00000011920928955078125)return 2;
 if(seed_ten(1,2,3,4,5,6,7,8,9,10)!=385)return 3;
 if(seed_outbound(1)!=389)return 4;
 if(seed_varout(1)!=55 || seed_unproto(1)!=4)return 5;
 if(seed_varin(1,2,3,4,5,6,7,8,9,2,10.0,11.0)!=66)return 6;
 if(seed_callback(host_return32,1)!=9)return 7;
 if(seed_widen(seed_narrow(1.5))!=1.5)return 8;
 c=seed_from_ul(9223372036854775808UL);if(seed_to_ul(c)!=9223372036854775808UL)return 9;
 return 0;
}
