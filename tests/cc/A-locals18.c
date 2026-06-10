/* Callee with 31 scalar locals: slots 16..30 exceed disp8 range, so their
   stores wrap to positive rbp offsets and land in the caller's frame —
   slot 30 wraps to [rbp+8], the return address, so the callee crashes on
   return.  main's 20 guard locals (slots 16..19 also past the cliff) must
   survive intact; main returns 100 only if every guard still reads 5. */
int callee() {
  int a0;int a1;int a2;int a3;int a4;int a5;int a6;int a7;int a8;
  int a9;int a10;int a11;int a12;int a13;int a14;int a15;int a16;int a17;
  int a18;int a19;int a20;int a21;int a22;int a23;int a24;int a25;int a26;
  int a27;int a28;int a29;int a30;
  a0=1;a1=1;a2=1;a3=1;a4=1;a5=1;a6=1;a7=1;a8=1;
  a9=1;a10=1;a11=1;a12=1;a13=1;a14=1;a15=1;a16=1;a17=1;
  a18=1;a19=1;a20=1;a21=1;a22=1;a23=1;a24=1;a25=1;a26=1;
  a27=1;a28=1;a29=1;a30=1;
  return a29 + a30;
}
int main() {
  int b0;int b1;int b2;int b3;int b4;int b5;int b6;int b7;int b8;int b9;
  int b10;int b11;int b12;int b13;int b14;int b15;int b16;int b17;int b18;int b19;
  b0=5;b1=5;b2=5;b3=5;b4=5;b5=5;b6=5;b7=5;b8=5;b9=5;
  b10=5;b11=5;b12=5;b13=5;b14=5;b15=5;b16=5;b17=5;b18=5;b19=5;
  callee();
  return b0+b1+b2+b3+b4+b5+b6+b7+b8+b9+b10+b11+b12+b13+b14+b15+b16+b17+b18+b19;
}
