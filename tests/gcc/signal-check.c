#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#ifdef SIGNAL_HOST_ORACLE
#include <unistd.h>
static long __seed_syscall6(long n, long a, long b, long c, long d, long e, long f)
{
    long result = syscall(n, a, b, c, d, e, f);
    return result == -1 ? -errno : result;
}
#else
#include <seed-syscall.h>
extern void __seed_sigreturn(void);
#endif

typedef void (*handler_t)(int);
struct kernel_action { handler_t handler; unsigned long flags;
    void (*restorer)(void); unsigned long mask; };
static volatile sig_atomic_t count;
static volatile sig_atomic_t depth;
static volatile sig_atomic_t max_depth;
static volatile sig_atomic_t same_signal_blocked;
static volatile sig_atomic_t recurse_once;
static volatile sig_atomic_t handler_error;
static volatile sig_atomic_t report_handler;
static long process;
static long thread;

static void deliver(int number)
{
    if (__seed_syscall6(234, process, thread, number, 0, 0, 0) != 0)
        handler_error = 1;
}

static void handler(int number)
{
    unsigned long current_mask = 0;
    depth++;
    if (depth > max_depth) max_depth = depth;
    if (number != SIGUSR1) handler_error = 2;
    count++;
    if (__seed_syscall6(14, 0, 0, (long)&current_mask, 8, 0, 0) != 0)
        handler_error = 3;
    if (current_mask & (1UL << (SIGUSR1 - 1))) same_signal_blocked = 1;
    if (recurse_once) {
        recurse_once = 0;
        deliver(SIGUSR1);
    }
    if (report_handler) __seed_syscall6(1, 1, (long)"handled\n", 8, 0, 0, 0);
    depth--;
}

static int ordinary(void)
{
    unsigned long original_mask = 0;
    unsigned long before_mask = 0;
    unsigned long after_mask = 0;
    unsigned long bit = 1UL << (SIGUSR1 - 1);
    struct kernel_action action;
    int invalid[5] = {0, -1, 65, SIGKILL, SIGSTOP};
    int i;
    if (sizeof(sig_atomic_t) != 4 || sizeof(action) != 32
        || (char *)&action.flags - (char *)&action != 8
        || (char *)&action.restorer - (char *)&action != 16
        || (char *)&action.mask - (char *)&action != 24) return 1;
    for (i = 0; i < 5; i++) {
        errno = 0;
        if (signal(invalid[i], SIG_IGN) != SIG_ERR || errno != EINVAL) return 2;
    }
    if (__seed_syscall6(14, 1, (long)&bit, (long)&original_mask, 8, 0, 0)) return 3;
    signal(SIGUSR1, SIG_DFL);
    errno = EDOM;
    if (signal(SIGUSR1, handler) != SIG_DFL || errno != EDOM) return 4;
    if (__seed_syscall6(13, SIGUSR1, 0, (long)&action, 8, 0, 0)) return 5;
    if (action.handler != handler
        || (action.flags & 0x14000000UL) != 0x14000000UL
        || (action.flags & 0xC0000000UL) != 0 || action.restorer == 0) return 6;
#ifndef SIGNAL_HOST_ORACLE
    if (action.mask != 0 || action.restorer != __seed_sigreturn) return 7;
#else
    /* Host BSD signal may explicitly add the same bit the kernel blocks. */
    if (action.mask & ~bit) return 7;
#endif
    deliver(SIGUSR1);
    deliver(SIGUSR1);
    if (count != 2 || max_depth != 1 || !same_signal_blocked || handler_error) return 8;
    if (signal(SIGUSR1, SIG_IGN) != handler) return 9;
    deliver(SIGUSR1);
    if (count != 2 || signal(SIGUSR1, handler) != SIG_IGN) return 10;
    if (__seed_syscall6(14, 0, (long)&bit, (long)&before_mask, 8, 0, 0)) return 11;
    deliver(SIGUSR1);
    if (count != 2) return 12;
    if (__seed_syscall6(14, 2, (long)&before_mask, 0, 8, 0, 0)) return 13;
    if (count != 3) return 14;
    recurse_once = 1;
    deliver(SIGUSR1);
    if (count != 5 || depth != 0 || max_depth != 1 || handler_error) return 15;
    if (__seed_syscall6(14, 0, 0, (long)&after_mask, 8, 0, 0)) return 16;
    if (after_mask != before_mask) return 17;
    if (signal(SIGUSR1, SIG_DFL) != handler) return 18;
    if (__seed_syscall6(14, 2, (long)&original_mask, 0, 8, 0, 0)) return 19;
    puts("signal contracts passed");
    return 0;
}

int main(int argc, char **argv)
{
    int fd = 0;
    char byte = 0;
    const char *text;
    unsigned long bit = 1UL << (SIGUSR1 - 1);
    long result;
    process = __seed_syscall6(39, 0, 0, 0, 0, 0, 0);
    thread = __seed_syscall6(186, 0, 0, 0, 0, 0, 0);
    if (argc < 2) return ordinary();
    if (__seed_syscall6(14, 1, (long)&bit, 0, 8, 0, 0)) return 20;
    if (strcmp(argv[1], "default") == 0) {
        signal(SIGUSR1, SIG_DFL);
        deliver(SIGUSR1);
        return 21;
    }
    if (argc != 3 || strcmp(argv[1], "restart")) return 22;
    text = argv[2];
    while (*text) fd = fd * 10 + *text++ - '0';
    if (signal(SIGUSR1, handler) == SIG_ERR) return 23;
    report_handler = 1;
    puts("ready");
    fflush(stdout);
    result = __seed_syscall6(0, fd, (long)&byte, 1, 0, 0, 0);
    if (result != 1 || byte != 'R' || count != 1 || handler_error) return 24;
    puts("restart passed");
    return 0;
}
