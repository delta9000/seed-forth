/* Same C90 fixture is compiled by Forth and by the independent host oracle. */
#include <setjmp.h>

long check_nonlocal(long);
static int callback_value;
static int callbacks;
static int continued;

typedef void (*JumpCallback)(long *, int);
void host_jump_callback(long *state, int depth, JumpCallback callback) {
    volatile long perturb[40];
    int i;
    for (i=0; i<40; i++) perturb[i]=depth*100+i;
    callbacks++;
    callback(state, depth);
    if (perturb[0]<0) continued++;
}
static void descend(jmp_buf state, int depth) {
    volatile long perturb[32];
    int i;
    for (i=0; i<32; i++) perturb[i]=depth+i;
    if (depth) descend(state, depth-1);
    else longjmp(state, callback_value);
    if (perturb[0]>=0) continued++;
}
static int exact_value(int value) {
    struct GuardedState { long before; jmp_buf state; long after; } guarded;
    volatile int changed=0;
    long stable=123456789012345L;
    guarded.before=234567890123456L;
    guarded.after=-345678901234567L;
    callback_value=value;
    switch (setjmp(guarded.state)) {
    case 0:
        changed=83;
        descend(guarded.state, 9);
        return 11;
    case 1: if (value!=0 && value!=1) return 12; break;
    case -1: if (value!=-1) return 13; break;
    case -2147483647-1: if (value!=-2147483647-1) return 14; break;
    case 2147483647: if (value!=2147483647) return 15; break;
    case 305419896: if (value!=305419896) return 16; break;
    default: return 17;
    }
    if (changed!=83 || stable!=123456789012345L) return 18;
    if (guarded.before!=234567890123456L || guarded.after!=-345678901234567L) return 19;
    return 0;
}
static int nested(int depth) {
    jmp_buf state;
    volatile int changed=0;
    int stable=depth+17;
    if (setjmp(state)==0) {
        changed=42;
        if (depth && nested(depth-1)) return 21;
        longjmp(state, 5);
        return 22;
    }
    if (changed!=42 || stable!=depth+17) return 23;
    return 0;
}
int main(void) {
    int values[6];
    int i;
    int r;
    values[0]=0; values[1]=1; values[2]=-1;
    values[3]=-2147483647-1; values[4]=2147483647; values[5]=305419896;
#ifndef NONLOCAL_HOST_LIBC
    if (sizeof(jmp_buf)!=8*sizeof(long)) return 1;
#endif
    for (i=0; i<6; i++) { r=exact_value(values[i]); if (r) return r; }
    r=nested(24); if (r) return r;
    for (i=0; i<64; i++) {
        r=(int)check_nonlocal(7);
        if (r) return 30+r;
    }
    if (callbacks!=64*6 || continued) return 41;
    return 0;
}
