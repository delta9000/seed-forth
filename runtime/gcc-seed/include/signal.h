#ifndef SEED_GCC_SIGNAL_H
#define SEED_GCC_SIGNAL_H
/* Original seed-forth interface; see LICENSE. Linux AMD64, single-threaded.
   signal() uses persistent BSD-style handlers, blocks the delivered signal
   during the handler, and requests restart of eligible interrupted calls.
   The POSIX sigaction/sigset interfaces are described in ../SIGNALS.md. */
#include <sys/types.h>
typedef int sig_atomic_t;
typedef void (*__seed_sighandler_t)(int);
#define SIG_DFL ((__seed_sighandler_t)0)
#define SIG_IGN ((__seed_sighandler_t)1)
#define SIG_ERR ((__seed_sighandler_t)-1)
/* The complete Linux AMD64 signal numbers. */
#define SIGHUP 1
#define SIGINT 2
#define SIGQUIT 3
#define SIGILL 4
#define SIGTRAP 5
#define SIGABRT 6
#define SIGIOT SIGABRT
#define SIGBUS 7
#define SIGFPE 8
#define SIGKILL 9
#define SIGUSR1 10
#define SIGSEGV 11
#define SIGUSR2 12
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGSTKFLT 16
#define SIGCHLD 17
#define SIGCLD SIGCHLD
#define SIGCONT 18
#define SIGSTOP 19
#define SIGTSTP 20
#define SIGTTIN 21
#define SIGTTOU 22
#define SIGURG 23
#define SIGXCPU 24
#define SIGXFSZ 25
#define SIGVTALRM 26
#define SIGPROF 27
#define SIGWINCH 28
#define SIGIO 29
#define SIGPOLL SIGIO
#define SIGPWR 30
#define SIGSYS 31
/* Kernel signals run 1..64. As in glibc, 32 and 33 are left unnamed and
   the real-time range is reported as 34..64; these are constants here. */
#define SIGRTMIN 34
#define SIGRTMAX 64
#define NSIG 65
#define _NSIG NSIG
__seed_sighandler_t signal(int number, __seed_sighandler_t handler);
/* A single Linux kill call; see ../PROCESS-API.md. */
int kill(pid_t process, int number);

/* glibc-sized set; the kernel reads only the first word (signals 1..64). */
typedef struct {
    unsigned long __seed_bits[16];
} sigset_t;

union sigval {
    int sival_int;
    void *sival_ptr;
};

/* Linux AMD64 siginfo layout: 128 bytes, variant fields from offset 16. */
typedef struct {
    int si_signo;
    int si_errno;
    int si_code;
    int __seed_si_pad;
    union {
        int __seed_si_words[28];
        struct {
            pid_t __seed_pid;
            uid_t __seed_uid;
            union {
                int __seed_status;
                union sigval __seed_value;
            } __seed_data;
            long __seed_utime;
            long __seed_stime;
        } __seed_process;
        struct {
            void *__seed_addr;
        } __seed_fault;
        struct {
            long __seed_band;
            int __seed_fd;
        } __seed_poll;
    } __seed_fields;
} siginfo_t;
#define si_pid __seed_fields.__seed_process.__seed_pid
#define si_uid __seed_fields.__seed_process.__seed_uid
#define si_status __seed_fields.__seed_process.__seed_data.__seed_status
#define si_value __seed_fields.__seed_process.__seed_data.__seed_value
#define si_utime __seed_fields.__seed_process.__seed_utime
#define si_stime __seed_fields.__seed_process.__seed_stime
#define si_addr __seed_fields.__seed_fault.__seed_addr
#define si_band __seed_fields.__seed_poll.__seed_band
#define si_fd __seed_fields.__seed_poll.__seed_fd
/* si_code values used for kill, sigqueue and SIGCHLD reports. */
#define SI_USER 0
#define SI_KERNEL 0x80
#define SI_QUEUE (-1)
#define SI_TKILL (-6)
#define CLD_EXITED 1
#define CLD_KILLED 2
#define CLD_DUMPED 3
#define CLD_TRAPPED 4
#define CLD_STOPPED 5
#define CLD_CONTINUED 6

/* glibc-compatible layout (152 bytes). sa_restorer is ignored on input:
   the runtime always installs its own rt_sigreturn trampoline. */
struct sigaction {
    union {
        __seed_sighandler_t __seed_handler;
        void (*__seed_action)(int, siginfo_t *, void *);
    } __seed_sigaction_handler;
    sigset_t sa_mask;
    int sa_flags;
    void (*sa_restorer)(void);
};
#define sa_handler __seed_sigaction_handler.__seed_handler
#define sa_sigaction __seed_sigaction_handler.__seed_action
#define SA_NOCLDSTOP 1
#define SA_NOCLDWAIT 2
#define SA_SIGINFO 4
#define SA_ONSTACK 0x08000000
#define SA_RESTART 0x10000000
#define SA_INTERRUPT 0x20000000
#define SA_NODEFER 0x40000000
#define SA_RESETHAND 0x80000000
#define SA_NOMASK SA_NODEFER
#define SA_ONESHOT SA_RESETHAND
#define SIG_BLOCK 0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2

int sigaction(int number, const struct sigaction *action, struct sigaction *previous);
int sigprocmask(int how, const sigset_t *set, sigset_t *previous);
/* Always returns -1 with EINTR after a handler ran. */
int sigsuspend(const sigset_t *mask);
int sigpending(sigset_t *set);
/* Numbers outside 1..64 fail with EINVAL. sigfillset sets all 64. */
int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int number);
int sigdelset(sigset_t *set, int number);
int sigismember(const sigset_t *set, int number);
/* Clear (flag 0) or set SA_RESTART on an installed disposition. */
int siginterrupt(int number, int flag);
/* tgkill to the calling thread; returns after any handler has run. */
int raise(int number);
/* kill(-group, number); a negative group fails with EINVAL. */
int killpg(pid_t group, int number);
/* "PREFIX: description\n" on stderr, like perror. */
void psignal(int number, const char *prefix);
/* glibc-style descriptions indexed by signal number; NULL when unnamed. */
extern const char *const sys_siglist[NSIG];
#endif
