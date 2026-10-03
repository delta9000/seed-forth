#ifndef SEED_GCC_SIGNAL_H
#define SEED_GCC_SIGNAL_H
/* Original seed-forth interface; see LICENSE. Linux AMD64, single-threaded.
   signal() uses persistent BSD-style handlers, blocks the delivered signal
   during the handler, and requests restart of eligible interrupted calls. */
typedef int sig_atomic_t;
typedef void (*__seed_sighandler_t)(int);
#define SIG_DFL ((__seed_sighandler_t)0)
#define SIG_IGN ((__seed_sighandler_t)1)
#define SIG_ERR ((__seed_sighandler_t)-1)
#define SIGHUP 1
#define SIGINT 2
#define SIGILL 4
#define SIGABRT 6
#define SIGFPE 8
#define SIGKILL 9
#define SIGUSR1 10
#define SIGSEGV 11
#define SIGUSR2 12
#define SIGTERM 15
#define SIGSTOP 19
__seed_sighandler_t signal(int number, __seed_sighandler_t handler);
#endif
