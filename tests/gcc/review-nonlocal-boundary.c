/* Host-only protected-memory oracle linked to the Forth leaf objects.
   The jmp_buf allocation is exactly 64 bytes at either protected boundary. */
#define _GNU_SOURCE 1
#include <setjmp.h>
#include <errno.h>
#include <fenv.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static int boundary(int at_end) {
    long page=sysconf(_SC_PAGESIZE);
    unsigned char *region;
    unsigned char *live;
    unsigned char *buffer;
    long i;
    if(page<128 || sizeof(jmp_buf)!=64) return 1;
    region=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if(region==MAP_FAILED) return 2;
    live=region+page;
    if(mprotect(live,page,PROT_READ|PROT_WRITE)) return 3;
    memset(live,0xA7,page);
    buffer=at_end ? live+page-sizeof(jmp_buf) : live;
    switch(setjmp(*(jmp_buf *)buffer)) {
    case 0:
        /* longjmp must not write the saved context either. */
        if(mprotect(live,page,PROT_READ)) return 4;
        longjmp(*(jmp_buf *)buffer,-1);
        return 5;
    case -1: break;
    default: return 6;
    }
    for(i=0;i<page;i++)
        if((live+i<buffer || live+i>=buffer+sizeof(jmp_buf)) && live[i]!=0xA7)
            return 7;
    if(munmap(region,3*page)) return 8;
    return 0;
}

static int ambient_state(void) {
    jmp_buf state;
    fenv_t original;
    volatile int result=0;
    if(fegetenv(&original)) return 11;
    if(fesetround(FE_TONEAREST) || feclearexcept(FE_ALL_EXCEPT)) return 12;
    switch(setjmp(state)) {
    case 0:
        if(fesetround(FE_DOWNWARD) || feraiseexcept(FE_INEXACT)) return 13;
        errno=ERANGE;
        longjmp(state,5);
        return 14;
    case 5:
        if(fegetround()!=FE_DOWNWARD || !(fetestexcept(FE_INEXACT)) || errno!=ERANGE)
            result=15;
        break;
    default: result=16;
    }
    if(fesetenv(&original)) return 17;
    return result;
}
int main(void) {
    int r=boundary(0); if(r) return r;
    r=boundary(1); if(r) return r;
    return ambient_state();
}
