#ifndef SEED_GCC_SETJMP_H
#define SEED_GCC_SETJMP_H
/* Linux AMD64 LP64: six preserved GPRs, caller RSP, continuation RIP.
   Private layout: never exchange these buffers with a host libc. */
typedef long jmp_buf[8];
#if defined(__GNUC__) && !defined(__SEED_FORTH__)
int setjmp(jmp_buf state) __attribute__((__returns_twice__));
void longjmp(jmp_buf state, int value) __attribute__((__noreturn__));
#else
int setjmp(jmp_buf state);
void longjmp(jmp_buf state, int value);
#endif
/* Self suppression keeps a real macro without adding an intervening frame. */
#define setjmp(state) setjmp(state)
#endif
