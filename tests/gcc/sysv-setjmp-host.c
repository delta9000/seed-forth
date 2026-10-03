/* Independent host-only nonlocal-return and callee-save oracle. */
#include <setjmp.h>
#include <stdio.h>
#include <stdalign.h>
_Static_assert(sizeof(jmp_buf)<=64*sizeof(long), "target scratch holds host jmp_buf");
_Static_assert(alignof(jmp_buf)<=alignof(long), "target scratch meets host alignment");
long check_nonlocal(long);
long sysv_jump_guard(long (*fn)(long),long);
int sysv_jump_bad_registers;
void host_jump_callback(long *state,int depth,void (*callback)(long *,int)) {
  volatile long perturb[40];
  for(int i=0;i<40;i++) perturb[i]=depth*100+i;
  callback(state,depth);
  if(perturb[0]<0) sysv_jump_bad_registers=1;
}
int main(void) {
  long result=sysv_jump_guard(check_nonlocal,7);
  if(result || sysv_jump_bad_registers) {
    fprintf(stderr,"nonlocal result=%ld register_failure=%d\n",result,sysv_jump_bad_registers);
    return 1;
  }
  puts("PASS: nonlocal returns, both operand orders, callbacks, repeated returns, loops and registers");
  return 0;
}
