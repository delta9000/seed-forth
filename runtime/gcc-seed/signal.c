/* Original seed-forth implementation; see LICENSE. Linux AMD64 syscall ABI. */
#include <signal.h>
#include <errno.h>
#include <seed-syscall.h>

extern void __seed_sigreturn(void);
struct seed_kernel_sigaction {
    __seed_sighandler_t handler;
    unsigned long flags;
    void (*restorer)(void);
    unsigned long mask;
};

__seed_sighandler_t signal(int number, __seed_sighandler_t handler)
{
    struct seed_kernel_sigaction action;
    struct seed_kernel_sigaction previous;
    long result;
    if (number <= 0 || number > 64) {
        errno = EINVAL;
        return SIG_ERR;
    }
    action.handler = handler;
    action.flags = 0x14000000UL; /* SA_RESTART | SA_RESTORER */
    action.restorer = __seed_sigreturn;
    action.mask = 0;
    result = __seed_syscall6(13, number, (long)&action, (long)&previous, 8, 0, 0);
    if (result < 0) {
        errno = (int)-result;
        return SIG_ERR;
    }
    return previous.handler;
}
