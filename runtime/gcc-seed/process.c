/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <stdlib.h>
#include <seed-syscall.h>

void exit(int status)
{
    /* This runtime is single-threaded and every stdio write is unbuffered.
       There are no atexit callbacks or tmpfile registrations to discharge.
       Linux closes process descriptors; only the low status byte survives.
       A denied syscall must never turn exit into a returning function. */
    for (;;) {
        __seed_syscall6(60, (long)(status & 255), 0, 0, 0, 0, 0);
    }
}

void abort(void)
{
    unsigned long mask = 32;
    unsigned long action[4];
    long process = __seed_syscall6(39, 0, 0, 0, 0, 0, 0);
    long thread = __seed_syscall6(186, 0, 0, 0, 0, 0, 0);

    /* The first delivery honors an installed handler. It may leave through
       a nonreturning action; otherwise abort must still terminate. */
    __seed_syscall6(14, 1, (long)&mask, 0, 8, 0, 0);
    __seed_syscall6(234, process, thread, 6, 0, 0, 0);

    /* AMD64 kernel sigaction: handler, flags, restorer, eight-byte mask.
       Default disposition needs no restorer. Override SIG_IGN or a handler
       that returned, including one that changed the blocked-signal mask. */
    action[0] = 0;
    action[1] = 0;
    action[2] = 0;
    action[3] = 0;
    __seed_syscall6(13, 6, (long)action, 0, 8, 0, 0);
    __seed_syscall6(14, 1, (long)&mask, 0, 8, 0, 0);
    __seed_syscall6(234, process, thread, 6, 0, 0, 0);

    /* A kernel/filter refusal cannot make abort return. Normal operation
       dies from SIGABRT; only failed signal delivery reaches this fallback. */
    exit(134);
}
