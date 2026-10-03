int old();
int old(a,b,c) register int c; signed char a; unsigned short b; {
  return a + b + c;
}
int proto(int,int);
int proto(a,b) signed char b; unsigned short a; { return a+b; }
int defaults(a,b) int b; { return a+b; }
int reordered(a,b,c) int c,a,b; { return 100*a+10*b+c; }
int again(int x) { return x; }
int again();
static implicit_helper(x) int x; { return x+1; }
implicit_forward(int);
implicit_forward(x) int x; { return implicit_helper(x); }
main() {
  signed char c; unsigned short s;
  c=-1; s=65535;
  if(old(c,s,8)!=65542) return 1;
  if(proto(65535,255)!=65534) return 2;
  if(defaults(19,23)!=42) return 3;
  if(reordered(1,2,3)!=123) return 4;
  if(again(42)!=42) return 5;
  if(implicit_forward(41)!=42) return 6;
  return 0;
}
