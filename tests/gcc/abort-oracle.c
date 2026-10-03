#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <setjmp.h>
#include <stdlib.h>
#include <unistd.h>

void seed_abort(void);
static sigjmp_buf jump;
static volatile sig_atomic_t calls;
static int mode;

static void handler(int number)
{
    sigset_t set;
    if (number != SIGABRT) _exit(80);
    calls++;
    if (write(1, "handler\n", 8) != 8) _exit(81);
    if (mode == 1) siglongjmp(jump, 1);
    if (mode == 2) _exit(42);
    if (mode == 3) {
        sigemptyset(&set);
        sigaddset(&set, SIGABRT);
        sigprocmask(SIG_BLOCK, &set, 0);
        signal(SIGABRT, SIG_IGN);
    }
}

int main(int argc, char **argv)
{
    struct sigaction action;
    mode = argc > 1 ? argv[1][0] - '0' : 0;
    action.sa_handler = handler;
    action.sa_flags = 0;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGABRT, &action, 0)) return 82;
    if (sigsetjmp(jump, 1) == 0)
        seed_abort();
    else
        return calls == 1 && mode == 1 ? 0 : 83;
    return 84;
}
