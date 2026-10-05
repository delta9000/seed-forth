/* Independent C90 runtime review. Every saved function remains active;
   changed automatic scalars are volatile, and the two crossing buffers are
   static so neither becomes indeterminate after the earlier longjmp. */
#include <setjmp.h>
#include <errno.h>

static jmp_buf early;
static jmp_buf later;
static int route;
static int wrong_path;
static jmp_buf levels[12];
static int visits[12];

static int two_live_contexts(void) {
    volatile long changed=0;
    long unchanged=234567890123456L;
    route=0;
    switch (setjmp(early)) {
    case 0: break;
    case 11:
        if (route!=1 || changed!=1 || errno!=EINVAL) return 11;
        route=2; changed=2; errno=ENOSPC;
        longjmp(later,-17);
        return 12;
    case 23:
        if (route!=3 || changed!=3 || errno!=EDOM) return 13;
        if (unchanged!=234567890123456L) return 14;
        return 0;
    default: return 15;
    }
    switch (setjmp(later)) {
    case 0:
        route=1; changed=1; errno=EINVAL;
        longjmp(early,11);
        return 16;
    case -17:
        if (route!=2 || changed!=2 || errno!=ENOSPC) return 17;
        route=3; changed=3; errno=EDOM;
        longjmp(early,23);
        return 18;
    default: return 19;
    }
}

static int expression_statements(void) {
    jmp_buf state;
    volatile int resumed=0;
    route=0;
    setjmp(state);
    resumed++;
    if (route<80) { route++; longjmp(state,route); }
    if (resumed!=81) return 21;
    route=0;
    (void)setjmp(state);
    resumed++;
    if (route<80) { route++; longjmp(state,-route); }
    return resumed==162 ? 0 : 22;
}

static int skip_frames(int depth) {
    volatile int changed=0;
    int stable=depth;
    if (setjmp(levels[depth])==0) {
        changed=71+depth;
        visits[depth]++;
        if (depth==11) longjmp(levels[3],9);
        if (skip_frames(depth+1)) return 31;
        if (depth>2) return 32;
    } else {
        if (depth!=3 || changed!=74 || stable!=3) return 33;
        visits[depth]++;
    }
    return 0;
}

struct Wide { long a; long b; long c; long d; };
static void record_jump(long a,long b,long c,long d,long e,long f,
                        struct Wide packet,long tail) {
    if (a!=1 || b!=2 || c!=3 || d!=4 || e!=5 || f!=6 ||
        packet.a!=123 || packet.b!=234 || packet.c!=345 ||
        packet.d!=456 || tail!=7) wrong_path=1;
    longjmp(early,-2147483647-1);
}
static int abandoned_record_call(void) {
    struct Wide packet={123,234,345,456};
    volatile int changed=0;
    switch (setjmp(early)) {
    case 0:
        changed=99;
        record_jump(1,2,3,4,5,6,packet,7);
        return 41;
    case -2147483647-1:
        if (changed!=99 || packet.c!=345 || wrong_path) return 42;
        return 0;
    default: return 43;
    }
}

int main(void) {
    int i;
    int r;
    for (i=0; i<80; i++) {
        r=two_live_contexts(); if(r) return r;
        r=expression_statements(); if(r) return r;
        r=abandoned_record_call(); if(r) return r;
    }
    r=skip_frames(0); if(r) return r;
    for(i=0;i<12;i++) if(visits[i]!=(i==3 ? 2 : 1)) return 51;
    return 0;
}
