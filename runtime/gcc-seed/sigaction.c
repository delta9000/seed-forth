/* Original seed-forth implementation; see LICENSE and SIGNALS.md.
   POSIX signal dispositions and masks over Linux AMD64 rt_sig* calls. */
#include <signal.h>
#include <errno.h>
#include <seed-syscall.h>

extern void __seed_sigreturn(void);
/* The kernel's AMD64 rt_sigaction record and its eight-byte mask. */
struct seed_kernel_action {
    __seed_sighandler_t handler;
    unsigned long flags;
    void (*restorer)(void);
    unsigned long mask;
};
#define SEED_SA_RESTORER 0x04000000UL
#define SEED_SIGSET_BYTES 8

static long seed_signal_call(long number, long a1, long a2, long a3, long a4)
{
    long result = __seed_syscall6(number, a1, a2, a3, a4, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return result;
}

static void seed_set_from_word(sigset_t *set, unsigned long word)
{
    int index;
    for (index = 0; index < 16; index++) set->__seed_bits[index] = 0;
    set->__seed_bits[0] = word;
}

int sigaction(int number, const struct sigaction *action, struct sigaction *previous)
{
    struct seed_kernel_action next;
    struct seed_kernel_action old;
    if (number <= 0 || number >= NSIG) {
        errno = EINVAL;
        return -1;
    }
    if (action) {
        /* Every handler returns through the runtime's rt_sigreturn. */
        next.handler = action->sa_handler;
        next.flags = (unsigned long)(unsigned int)action->sa_flags | SEED_SA_RESTORER;
        next.restorer = __seed_sigreturn;
        next.mask = action->sa_mask.__seed_bits[0];
    }
    old.handler = 0;
    old.flags = 0;
    old.restorer = 0;
    old.mask = 0;
    if (seed_signal_call(13, number, action ? (long)&next : 0,
                         previous ? (long)&old : 0, SEED_SIGSET_BYTES) < 0)
        return -1;
    if (previous) {
        previous->sa_handler = old.handler;
        previous->sa_flags = (int)old.flags;
        previous->sa_restorer = old.restorer;
        seed_set_from_word(&previous->sa_mask, old.mask);
    }
    return 0;
}

int sigprocmask(int how, const sigset_t *set, sigset_t *previous)
{
    unsigned long old = 0;
    if (seed_signal_call(14, how, set ? (long)&set->__seed_bits[0] : 0,
                         previous ? (long)&old : 0, SEED_SIGSET_BYTES) < 0)
        return -1;
    if (previous) seed_set_from_word(previous, old);
    return 0;
}

int sigsuspend(const sigset_t *mask)
{
    return (int)seed_signal_call(130, (long)&mask->__seed_bits[0], SEED_SIGSET_BYTES, 0, 0);
}

int sigpending(sigset_t *set)
{
    unsigned long word = 0;
    if (seed_signal_call(127, (long)&word, SEED_SIGSET_BYTES, 0, 0) < 0) return -1;
    seed_set_from_word(set, word);
    return 0;
}

int siginterrupt(int number, int flag)
{
    struct sigaction action;
    if (sigaction(number, 0, &action) < 0) return -1;
    if (flag) action.sa_flags &= ~SA_RESTART;
    else action.sa_flags |= SA_RESTART;
    return sigaction(number, &action, 0);
}
