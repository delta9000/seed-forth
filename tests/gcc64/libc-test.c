#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <math.h>
#include <errno.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <ctype.h>
#include <time.h>
#include <locale.h>
static jmp_buf jb; static int depth;
static void deep(int n){ if(n==0) longjmp(jb, 42); deep(n-1); }
static int cmp(const void*a,const void*b){ return *(int*)a-*(int*)b; }
static int vsum(int n, ...){ va_list ap; int s=0,i; va_start(ap,n); for(i=0;i<n;i++){ if(i==3) s+=(int)va_arg(ap,double); else s+=va_arg(ap,int);} va_end(ap); return s; }
static char *fmt(const char *f, ...){ static char b[256]; va_list ap; va_start(ap,f); vsnprintf(b,sizeof b,f,ap); va_end(ap); return b; }
int main(int argc, char **argv){
  int fails=0, r; char buf[256]; int a[8]={5,3,9,1,7,2,8,0}; char *p; double d; long double ld; FILE *f; pid_t pid; int st;
#define CHECK(c,msg) do{ if(!(c)){ printf("FAIL %s\n",msg); fails++; } else printf("ok   %s\n",msg);}while(0)
  printf("hello, musl (argc=%d)\n", argc);
  snprintf(buf,sizeof buf,"%lld %llu %lx %d %5.2f %e %g %s %c %%", -1234567890123LL, 18446744073709551615ULL, 0xdeadbeefcafeL, -7, 3.14159, 6.02214076e23, 0.0001, "str", 'x');
  CHECK(!strcmp(buf,"-1234567890123 18446744073709551615 deadbeefcafe -7  3.14 6.022141e+23 0.0001 str x %"), buf);
  p=malloc(1<<20); CHECK(p!=0,"malloc 1MiB"); memset(p,'a',1<<20); p=realloc(p,1<<22); CHECK(p && p[12345]=='a',"realloc 4MiB"); free(p);
  { int i; void *v[1000]; for(i=0;i<1000;i++) v[i]=malloc(i*37+1); for(i=0;i<1000;i+=2) free(v[i]); for(i=1;i<1000;i+=2) free(v[i]); CHECK(1,"malloc/free 1000 blocks"); }
  if((r=setjmp(jb))==0){ deep(100); CHECK(0,"longjmp"); } else CHECK(r==42,"setjmp/longjmp 42");
  qsort(a,8,sizeof(int),cmp); CHECK(a[0]==0&&a[7]==9&&a[3]==3,"qsort");
  d=strtod("2.5e-3",&p); CHECK(d==0.0025 && *p==0,"strtod 2.5e-3");
  d=strtod("0x1.8p1",0); CHECK(d==3.0,"strtod hex");
  CHECK(strtod("1e400",0)==HUGE_VAL && errno==ERANGE,"strtod overflow ERANGE");
  CHECK(!strcmp(fmt("%.17g",0.1),"0.10000000000000001"),"printf %.17g 0.1");
  CHECK(!strcmp(fmt("%.20Lg",1.0L/3),"0.33333333333333333334"),"long double 1/3 %.20Lg");
  CHECK(fabs(sqrt(2.0)*sqrt(2.0)-2.0)<1e-15,"sqrt");
  CHECK(fabs(sin(1.0)-0.8414709848078965)<1e-15,"sin");
  CHECK(fabs(exp(1.0)-2.718281828459045)<1e-15,"exp");
  CHECK(fabs(pow(2.0,0.5)-1.4142135623730951)<1e-15,"pow");
  ld=expl(1.0L); CHECK(fabsl(ld-2.718281828459045235360L)<1e-18L,"expl (x87 asm)");
  CHECK(vsum(5,1,2,3,4.9,5)==15,"varargs mixed int/double");
  CHECK(strtol("-0x7f",0,16)==-127 && strtoull("777",0,8)==511,"strtol/strtoull");
  CHECK(atoi("  42abc")==42,"atoi");
  CHECK(!strcmp(strrchr("a/b/c",'/'),"/c") && strstr("hello","ll") && !memcmp("abc","abd",2),"string fns");
  f=fopen("/tmp/gcc64-libc-test.txt","w"); fprintf(f,"line1\nline2 %d\n",99); fclose(f);
  f=fopen("/tmp/gcc64-libc-test.txt","r"); fgets(buf,sizeof buf,f); fgets(buf,sizeof buf,f); fclose(f); unlink("/tmp/gcc64-libc-test.txt");
  CHECK(!strcmp(buf,"line2 99\n"),"stdio file round trip");
  pid=fork(); if(pid==0){ execl("/bin/sh","sh","-c","exit 3",(char*)0); _exit(127);} waitpid(pid,&st,0); CHECK(WIFEXITED(st)&&WEXITSTATUS(st)==3,"fork/exec/wait");
  CHECK(getenv("PATH")!=0,"getenv");
  CHECK(time(0)>1600000000,"time");
  { char *s=0; CHECK(sscanf("12 3.5 xyz","%d %lf %s",&r,&d,buf)==3 && r==12 && d==3.5 && !strcmp(buf,"xyz"),"sscanf"); (void)s; }
  CHECK(isalpha('q') && !isdigit('q') && toupper('q')=='Q',"ctype");
  printf("%s: %d failures\n", fails?"FAILED":"PASSED", fails);
  return fails!=0;
}
