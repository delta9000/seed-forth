/* Host C90 oracle linked with the actual Forth-produced runtime objects. */
#include <setjmp.h>
#include <stdio.h>
int seed_nonlocal_abi_guard(int value);
int seed_nonlocal_alignment(void);
long sysv_jump_guard(long (*fn)(long),long);
long check_nonlocal(long);
int sysv_jump_bad_registers;
static int bad_alignment;
void host_jump_callback(long *state,int depth,void (*callback)(long *,int)) {
    volatile long perturb[40];
    int i;
    bad_alignment+=seed_nonlocal_alignment();
    for (i=0;i<40;i++) perturb[i]=depth*100+i;
    callback(state,depth);
    if (perturb[0]<0) sysv_jump_bad_registers=1;
}
int main(void) {
    int values[6];
    int i;
    long result;
    values[0]=0; values[1]=1; values[2]=-1;
    values[3]=-2147483647-1; values[4]=2147483647; values[5]=305419896;
    if (sizeof(jmp_buf)!=64) return 1;
    for (i=0;i<6;i++) if (seed_nonlocal_abi_guard(values[i])) return 2;
    result=sysv_jump_guard(check_nonlocal,7);
    if (result || sysv_jump_bad_registers || bad_alignment) {
        fprintf(stderr,"nonlocal result=%ld registers=%d alignment=%d\n",
                result,sysv_jump_bad_registers,bad_alignment);
        return 3;
    }
    puts("PASS: Forth nonlocal objects, exact int values, six full-width registers, RSP and alignment");
    return 0;
}
