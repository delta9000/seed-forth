/* POSIX errno and signal fixture: built by the Forth compiler against
   runtime/gcc-seed and by host GCC against glibc; outputs must match. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#define SHOW(name) printf("%s %d\n", #name, (int)(name))
/* Evaluate the call before reading errno or counters: printf arguments
   have no defined evaluation order. */
#define CALL(label, expression) do { int value_; errno = 0; value_ = (int)(expression); int error_ = errno; \
    printf("%s %d errno %d hits %d\n", label, value_, error_, (int)hits); } while (0)
static volatile sig_atomic_t hits;

static void errno_values(void)
{
    SHOW(EPERM); SHOW(ENOENT); SHOW(ESRCH); SHOW(EINTR); SHOW(EIO); SHOW(ENXIO);
    SHOW(E2BIG); SHOW(ENOEXEC); SHOW(EBADF); SHOW(ECHILD); SHOW(EAGAIN);
    SHOW(EWOULDBLOCK); SHOW(ENOMEM); SHOW(EACCES); SHOW(EFAULT); SHOW(ENOTBLK);
    SHOW(EBUSY); SHOW(EEXIST); SHOW(EXDEV); SHOW(ENODEV); SHOW(ENOTDIR);
    SHOW(EISDIR); SHOW(EINVAL); SHOW(ENFILE); SHOW(EMFILE); SHOW(ENOTTY);
    SHOW(ETXTBSY); SHOW(EFBIG); SHOW(ENOSPC); SHOW(ESPIPE); SHOW(EROFS);
    SHOW(EMLINK); SHOW(EPIPE); SHOW(EDOM); SHOW(ERANGE); SHOW(EDEADLK);
    SHOW(EDEADLOCK); SHOW(ENAMETOOLONG); SHOW(ENOLCK); SHOW(ENOSYS);
    SHOW(ENOTEMPTY); SHOW(ELOOP); SHOW(ENOMSG); SHOW(EIDRM); SHOW(ECHRNG);
    SHOW(EL2NSYNC); SHOW(EL3HLT); SHOW(EL3RST); SHOW(ELNRNG); SHOW(EUNATCH);
    SHOW(ENOCSI); SHOW(EL2HLT); SHOW(EBADE); SHOW(EBADR); SHOW(EXFULL);
    SHOW(ENOANO); SHOW(EBADRQC); SHOW(EBADSLT); SHOW(EBFONT); SHOW(ENOSTR);
    SHOW(ENODATA); SHOW(ETIME); SHOW(ENOSR); SHOW(ENONET); SHOW(ENOPKG);
    SHOW(EREMOTE); SHOW(ENOLINK); SHOW(EADV); SHOW(ESRMNT); SHOW(ECOMM);
    SHOW(EPROTO); SHOW(EMULTIHOP); SHOW(EDOTDOT); SHOW(EBADMSG); SHOW(EOVERFLOW);
    SHOW(ENOTUNIQ); SHOW(EBADFD); SHOW(EREMCHG); SHOW(ELIBACC); SHOW(ELIBBAD);
    SHOW(ELIBSCN); SHOW(ELIBMAX); SHOW(ELIBEXEC); SHOW(EILSEQ); SHOW(ERESTART);
    SHOW(ESTRPIPE); SHOW(EUSERS); SHOW(ENOTSOCK); SHOW(EDESTADDRREQ);
    SHOW(EMSGSIZE); SHOW(EPROTOTYPE); SHOW(ENOPROTOOPT); SHOW(EPROTONOSUPPORT);
    SHOW(ESOCKTNOSUPPORT); SHOW(EOPNOTSUPP); SHOW(ENOTSUP); SHOW(EPFNOSUPPORT);
    SHOW(EAFNOSUPPORT); SHOW(EADDRINUSE); SHOW(EADDRNOTAVAIL); SHOW(ENETDOWN);
    SHOW(ENETUNREACH); SHOW(ENETRESET); SHOW(ECONNABORTED); SHOW(ECONNRESET);
    SHOW(ENOBUFS); SHOW(EISCONN); SHOW(ENOTCONN); SHOW(ESHUTDOWN);
    SHOW(ETOOMANYREFS); SHOW(ETIMEDOUT); SHOW(ECONNREFUSED); SHOW(EHOSTDOWN);
    SHOW(EHOSTUNREACH); SHOW(EALREADY); SHOW(EINPROGRESS); SHOW(ESTALE);
    SHOW(EUCLEAN); SHOW(ENOTNAM); SHOW(ENAVAIL); SHOW(EISNAM); SHOW(EREMOTEIO);
    SHOW(EDQUOT); SHOW(ENOMEDIUM); SHOW(EMEDIUMTYPE); SHOW(ECANCELED);
    SHOW(ENOKEY); SHOW(EKEYEXPIRED); SHOW(EKEYREVOKED); SHOW(EKEYREJECTED);
    SHOW(EOWNERDEAD); SHOW(ENOTRECOVERABLE); SHOW(ERFKILL); SHOW(EHWPOISON);
}

static void error_texts(void)
{
    int number;
    for (number = -2; number <= 136; number++) {
        errno = 1234;
        printf("strerror %d %s", number, strerror(number));
        printf(" errno-kept %d\n", errno == 1234);
    }
    errno = EXDEV;
    perror("perror");
    errno = ENOTSUP;
    perror("");
    errno = 0;
    perror(NULL);
    printf("perror errno %d\n", errno);
}

static void signal_values(void)
{
    SHOW(SIGHUP); SHOW(SIGINT); SHOW(SIGQUIT); SHOW(SIGILL); SHOW(SIGTRAP);
    SHOW(SIGABRT); SHOW(SIGIOT); SHOW(SIGBUS); SHOW(SIGFPE); SHOW(SIGKILL);
    SHOW(SIGUSR1); SHOW(SIGSEGV); SHOW(SIGUSR2); SHOW(SIGPIPE); SHOW(SIGALRM);
    SHOW(SIGTERM); SHOW(SIGSTKFLT); SHOW(SIGCHLD); SHOW(SIGCONT); SHOW(SIGSTOP);
    SHOW(SIGTSTP); SHOW(SIGTTIN); SHOW(SIGTTOU); SHOW(SIGURG); SHOW(SIGXCPU);
    SHOW(SIGXFSZ); SHOW(SIGVTALRM); SHOW(SIGPROF); SHOW(SIGWINCH); SHOW(SIGIO);
    SHOW(SIGPOLL); SHOW(SIGPWR); SHOW(SIGSYS); SHOW(SIGRTMIN); SHOW(SIGRTMAX);
    SHOW(NSIG); SHOW(SA_NOCLDSTOP); SHOW(SA_NOCLDWAIT); SHOW(SA_SIGINFO);
    SHOW(SA_ONSTACK); SHOW(SA_RESTART); SHOW(SA_NODEFER); SHOW(SA_RESETHAND);
    SHOW(SIG_BLOCK); SHOW(SIG_UNBLOCK); SHOW(SIG_SETMASK); SHOW(SI_USER);
    SHOW(SI_TKILL); SHOW(SI_QUEUE); SHOW(CLD_EXITED); SHOW(CLD_KILLED);
    SHOW(CLD_STOPPED); SHOW(CLD_CONTINUED);
    printf("sizes %lu %lu\n", (unsigned long)sizeof(siginfo_t), (unsigned long)sizeof(struct sigaction));
}

static void signal_texts(void)
{
    int number;
    for (number = -1; number <= 66; number++) printf("strsignal %d %s\n", number, strsignal(number));
    psignal(SIGINT, "psignal");
    psignal(SIGRTMIN + 2, NULL);
    psignal(99, "");
#ifndef __GLIBC__
    for (number = 1; number < 32; number++)
        if (strcmp(sys_siglist[number], strsignal(number)) != 0) printf("sys_siglist %d differs\n", number);
    for (number = 32; number < NSIG; number++)
        if (sys_siglist[number] != NULL) printf("sys_siglist %d not NULL\n", number);
#endif
}

static void set_operations(void)
{
    sigset_t set;
    int number;
    sigemptyset(&set);
    sigaddset(&set, SIGINT);
    sigaddset(&set, SIGRTMAX);
    sigaddset(&set, SIGHUP);
    sigdelset(&set, SIGHUP);
    for (number = 1; number <= 64; number++)
        if (number != 32 && number != 33 && sigismember(&set, number)) printf("member %d\n", number);
    errno = 0;
    CALL("add 0", sigaddset(&set, 0));
    errno = 0;
    CALL("add 65", sigaddset(&set, 65));
    errno = 0;
    CALL("del -1", sigdelset(&set, -1));
    errno = 0;
    CALL("member 65", sigismember(&set, 65));
    sigfillset(&set);
    for (number = 1; number <= 64; number++)
        if (number != 32 && number != 33 && !sigismember(&set, number)) printf("not full %d\n", number);
#ifndef __GLIBC__
    /* glibc reserves 32 and 33 for its threads; this runtime does not. */
    if (sigaddset(&set, 32) != 0 || sigismember(&set, 33) != 1) printf("32/33 rejected\n");
#endif
}

static volatile int last_signal;
static volatile int blocked_inside;
static volatile int info_signo, info_code, info_pid_matches, info_status;

static void count_handler(int number)
{
    sigset_t now;
    hits++;
    last_signal = number;
    sigprocmask(SIG_BLOCK, NULL, &now);
    blocked_inside = sigismember(&now, SIGUSR2) * 2 + sigismember(&now, number);
}

static void info_handler(int number, siginfo_t *info, void *context)
{
    (void)context;
    hits++;
    info_signo = info->si_signo;
    info_code = info->si_code;
    info_pid_matches = info->si_pid == getpid();
    info_status = number == SIGCHLD ? info->si_status : -1;
}

static void dispositions(void)
{
    struct sigaction action, old;
    memset(&action, 0, sizeof(action));
    action.sa_handler = count_handler;
    sigemptyset(&action.sa_mask);
    sigaddset(&action.sa_mask, SIGUSR2);
    action.sa_flags = SA_RESTART;
    printf("install %d\n", sigaction(SIGUSR1, &action, &old));
    printf("old default %d\n", old.sa_handler == SIG_DFL);
    printf("query %d\n", sigaction(SIGUSR1, NULL, &old));
    printf("query handler %d restart %d mask %d %d\n", old.sa_handler == count_handler,
           (old.sa_flags & SA_RESTART) != 0, sigismember(&old.sa_mask, SIGUSR2),
           sigismember(&old.sa_mask, SIGINT));
    hits = 0;
    CALL("raise", raise(SIGUSR1));
    printf("last %d blocked %d\n", last_signal, blocked_inside);
    CALL("kill", kill(getpid(), SIGUSR1));
    action.sa_flags = SA_NODEFER;
    sigaction(SIGUSR1, &action, NULL);
    raise(SIGUSR1);
    printf("nodefer blocked %d\n", blocked_inside);
    action.sa_flags = SA_RESETHAND;
    sigaction(SIGUSR1, &action, NULL);
    raise(SIGUSR1);
    sigaction(SIGUSR1, NULL, &old);
    printf("resethand hits %d now default %d\n", (int)hits, old.sa_handler == SIG_DFL);
    action.sa_handler = SIG_IGN;
    action.sa_flags = 0;
    sigaction(SIGUSR1, &action, NULL);
    CALL("ignored raise", raise(SIGUSR1));
    errno = 0;
    CALL("kill handler", sigaction(SIGKILL, &action, NULL));
    errno = 0;
    CALL("bad number 0", sigaction(0, &action, NULL));
    errno = 0;
    CALL("bad number NSIG", sigaction(NSIG, &action, NULL));
    printf("signal() old ignored %d\n", signal(SIGUSR1, SIG_DFL) == SIG_IGN);
    action.sa_handler = SIG_DFL;
    action.sa_sigaction = info_handler;
    action.sa_flags = SA_SIGINFO;
    sigaction(SIGUSR2, &action, NULL);
    raise(SIGUSR2);
    printf("siginfo %d code %d pid %d\n", info_signo, info_code, info_pid_matches);
    kill(getpid(), SIGUSR2);
    printf("siginfo %d code %d pid %d\n", info_signo, info_code, info_pid_matches);
}

static void masks(void)
{
    sigset_t block, previous, pending, empty;
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = count_handler;
    sigemptyset(&action.sa_mask);
    sigaction(SIGUSR1, &action, NULL);
    sigemptyset(&block);
    sigaddset(&block, SIGUSR1);
    printf("block %d\n", sigprocmask(SIG_BLOCK, &block, &previous));
    printf("previous had usr1 %d\n", sigismember(&previous, SIGUSR1));
    hits = 0;
    raise(SIGUSR1);
    sigpending(&pending);
    printf("while blocked hits %d pending %d %d\n", (int)hits, sigismember(&pending, SIGUSR1),
           sigismember(&pending, SIGUSR2));
    sigemptyset(&empty);
    errno = 0;
    CALL("sigsuspend", sigsuspend(&empty));
    sigprocmask(SIG_SETMASK, NULL, &previous);
    printf("restored mask has usr1 %d\n", sigismember(&previous, SIGUSR1));
    errno = 0;
    CALL("bad how", sigprocmask(99, &block, NULL));
    printf("unblock %d\n", sigprocmask(SIG_UNBLOCK, &block, NULL));
}

static void alarms(void)
{
    struct sigaction action;
    int ends[2];
    char byte;
    memset(&action, 0, sizeof(action));
    action.sa_handler = count_handler;
    sigemptyset(&action.sa_mask);
    sigaction(SIGALRM, &action, NULL);
    printf("alarm %u\n", alarm(30));
    printf("alarm again %u\n", alarm(0));
    hits = 0;
    alarm(1);
    errno = 0;
    CALL("pause", pause());
    printf("last %d\n", last_signal);
    printf("siginterrupt %d\n", siginterrupt(SIGALRM, 0));
    sigaction(SIGALRM, NULL, &action);
    printf("restart after 0: %d\n", (action.sa_flags & SA_RESTART) != 0);
    printf("siginterrupt %d\n", siginterrupt(SIGALRM, 1));
    sigaction(SIGALRM, NULL, &action);
    printf("restart after 1: %d\n", (action.sa_flags & SA_RESTART) != 0);
    if (pipe(ends) != 0) return;
    alarm(1);
    errno = 0;
    CALL("interrupted read", read(ends[0], &byte, 1));
    close(ends[0]);
    close(ends[1]);
}

static void children(void)
{
    struct sigaction action;
    sigset_t block, empty;
    pid_t child;
    int status;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = info_handler;
    action.sa_flags = SA_SIGINFO | SA_NOCLDSTOP;
    sigemptyset(&action.sa_mask);
    sigaction(SIGCHLD, &action, NULL);
    sigemptyset(&block);
    sigaddset(&block, SIGCHLD);
    sigemptyset(&empty);
    sigprocmask(SIG_BLOCK, &block, NULL);
    hits = 0;
    child = fork();
    if (child == 0) _exit(7);
    while (hits == 0) sigsuspend(&empty);
    sigprocmask(SIG_UNBLOCK, &block, NULL);
    waitpid(child, &status, 0);
    printf("sigchld %d code %d status %d exit %d\n", info_signo, info_code, info_status, WEXITSTATUS(status));
    signal(SIGCHLD, SIG_DFL);
    child = fork();
    if (child == 0) {
        /* A new process group; killpg reaches only this child. */
        setpgid(0, 0);
        signal(SIGUSR1, count_handler);
        hits = 0;
        if (killpg(getpgrp(), SIGUSR1) != 0 || hits != 1) _exit(1);
        errno = 0;
        if (killpg(-1, SIGUSR1) != -1 || errno != EINVAL) _exit(2);
        _exit(0);
    }
    waitpid(child, &status, 0);
    printf("killpg child %d\n", WEXITSTATUS(status));
    child = fork();
    if (child == 0) {
        signal(SIGTERM, SIG_DFL);
        raise(SIGTERM);
        _exit(3);
    }
    waitpid(child, &status, 0);
    printf("raised termination %d %d\n", WIFSIGNALED(status), WTERMSIG(status));
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    errno_values();
    error_texts();
    signal_values();
    signal_texts();
    set_operations();
    dispositions();
    masks();
    alarms();
    children();
    puts("done");
    return 0;
}
