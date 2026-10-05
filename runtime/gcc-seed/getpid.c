/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <unistd.h>
#include <seed-syscall.h>

pid_t getpid(void)
{
    /* Linux getpid has no error return. Do not cache across process changes. */
    return (pid_t)__seed_syscall6(39, 0, 0, 0, 0, 0, 0);
}
