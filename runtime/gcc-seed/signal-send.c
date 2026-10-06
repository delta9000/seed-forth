/* Original seed-forth implementation; see LICENSE and SIGNALS.md.
   Sending signals to the caller or a process group, alarm and pause. */
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

static long seed_send_call(long number, long a1, long a2, long a3)
{
    long result = __seed_syscall6(number, a1, a2, a3, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return result;
}

int raise(int number)
{
    /* getpid and gettid cannot fail; tgkill delivers to this thread before
       returning when the signal is unblocked. */
    long process = __seed_syscall6(39, 0, 0, 0, 0, 0, 0);
    long thread = __seed_syscall6(186, 0, 0, 0, 0, 0, 0);
    return (int)seed_send_call(234, process, thread, number);
}

int killpg(pid_t group, int number)
{
    /* As glibc: 0 means the caller's own group (kill(0, ...)); only a
       negative group is rejected. POSIX leaves 0 and 1 undefined. */
    if (group < 0) {
        errno = EINVAL;
        return -1;
    }
    return (int)seed_send_call(62, -(long)group, number, 0);
}

unsigned int alarm(unsigned int seconds)
{
    /* Cannot fail; returns the whole seconds left on the previous alarm. */
    return (unsigned int)__seed_syscall6(37, (long)seconds, 0, 0, 0, 0, 0);
}

int pause(void)
{
    return (int)seed_send_call(34, 0, 0, 0);
}
