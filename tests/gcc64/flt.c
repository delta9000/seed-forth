#include <stdio.h>
#include <math.h>
int main(void){ volatile double x=2.0; volatile float f=1.5f; volatile long double l=1.0L;
  double s=sqrt(x), e=exp(1.0), p=atan(1.0)*4; long double t=l/3;
  printf("%.15f %.15f %.15f %.6f %.20Lf\n",s,e,p,(double)(f*f),t);
  return !(fabs(s*s-2)<1e-15 && fabs(p-3.141592653589793)<1e-15 && f*f==2.25f && t>0.3333L && t<0.3334L); }
