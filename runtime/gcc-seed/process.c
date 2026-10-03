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
