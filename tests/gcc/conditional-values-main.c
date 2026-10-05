#include "conditional-values.h"
int main(void) {
  int c;
  union { double d; unsigned long u; } in64,out64;
  union { float f; unsigned int u; } in32,out32;
  if(sizeof(1?(float)1.25:3)!=4) return 28;
  if(sizeof(0?(float)1.25:3.0)!=8) return 29;
  if(sizeof(1?-1:1U)!=4) return 30;
  for(c=0;c<2;c++) {
    if(choose_di(c,4.5,-3)!=(c?4.5:-3.0)) return 1;
    if(choose_id(c,-3,4.5)!=(c?-3.0:4.5)) return 2;
    if(choose_fd(c,1.25,4.5)!=(c?1.25:4.5)) return 3;
    if(choose_df(c,4.5,1.25)!=(c?4.5:1.25)) return 4;
    if(choose_fi(c,1.25,16777217)!=(c?1.25:16777216.0)) return 5;
    if(choose_if(c,-16777217,1.25)!=(c?-16777216.0:1.25)) return 6;
    if(choose_du(c,4.5,18446744073709551615UL)!=(c?4.5:18446744073709551616.0)) return 7;
    if(choose_ud(c,18446744073709551615UL,4.5)!=(c?18446744073709551616.0:4.5)) return 8;
    if(choose_fu(c,1.25,18446744073709551615UL)!=(c?1.25:18446744073709551616.0)) return 18;
    if(choose_uf(c,18446744073709551615UL,1.25)!=(c?18446744073709551616.0:1.25)) return 19;
    if(choose_iu(c,-1,1U)!=(c?4294967295UL:1UL)) return 9;
    if(choose_li(c,-1L,4294967295U)!=(c?-1L:4294967295L)) return 10;
  }
  if(choose_nested(1,1,1.25,16777217,4.5)!=1.25) return 11;
  if(choose_nested(1,0,1.25,16777217,4.5)!=16777216.0) return 12;
  if(choose_nested(0,1,1.25,16777217,4.5)!=16777217.0) return 13;
  if(choose_nested(0,0,1.25,16777217,4.5)!=4.5) return 14;
  in64.u=0x8000000000000000UL; out64.d=choose_di(1,in64.d,0);
  if(out64.u!=in64.u) return 20;
  out64.d=choose_id(0,0,in64.d); if(out64.u!=in64.u) return 21;
  in64.u=0x7ff8000000000042UL; out64.d=choose_di(1,in64.d,0);
  if(out64.u!=in64.u) return 22;
  out64.d=choose_id(0,0,in64.d); if(out64.u!=in64.u) return 23;
  in32.u=0x80000000U; out32.f=choose_fi(1,in32.f,0);
  if(out32.u!=in32.u) return 24;
  out32.f=choose_if(0,0,in32.f); if(out32.u!=in32.u) return 25;
  in32.u=0x7fc00042U; out32.f=choose_fi(1,in32.f,0);
  if(out32.u!=in32.u) return 26;
  out32.f=choose_if(0,0,in32.f); if(out32.u!=in32.u) return 27;
  if(conditional_lazy()) return 15;
  if(conditional_pointers()) return 16;
  if(conditional_aggregates()) return 17;
  return 42;
}
