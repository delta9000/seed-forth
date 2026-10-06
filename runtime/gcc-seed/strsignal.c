/* Original seed-forth implementation; see LICENSE and SIGNALS.md.
   Signal descriptions in glibc's C-locale wording. */
#include <signal.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

/* sys_siglist[0] and the unnamed 32..64 entries are NULL. */
const char *const sys_siglist[NSIG] = {
    0,
    "Hangup",
    "Interrupt",
    "Quit",
    "Illegal instruction",
    "Trace/breakpoint trap",
    "Aborted",
    "Bus error",
    "Floating point exception",
    "Killed",
    "User defined signal 1",
    "Segmentation fault",
    "User defined signal 2",
    "Broken pipe",
    "Alarm clock",
    "Terminated",
    "Stack fault",
    "Child exited",
    "Continued",
    "Stopped (signal)",
    "Stopped",
    "Stopped (tty input)",
    "Stopped (tty output)",
    "Urgent I/O condition",
    "CPU time limit exceeded",
    "File size limit exceeded",
    "Virtual timer expired",
    "Profiling timer expired",
    "Window changed",
    "I/O possible",
    "Power failure",
    "Bad system call",
};

char *strsignal(int number)
{
    /* Single-threaded: numbered texts share one static buffer. */
    static char text[32];
    if (number > 0 && number < 32) return (char *)sys_siglist[number];
    if (number >= SIGRTMIN && number <= SIGRTMAX)
        snprintf(text, sizeof(text), "Real-time signal %d", number - SIGRTMIN);
    else
        snprintf(text, sizeof(text), "Unknown signal %d", number);
    return text;
}

void psignal(int number, const char *prefix)
{
    /* As glibc: only the named signals have text here; real-time and
       other numbers print "Unknown signal N" (unlike strsignal). */
    int saved = errno;
    if (prefix != NULL && *prefix) fprintf(stderr, "%s: ", prefix);
    if (number > 0 && number < 32) fprintf(stderr, "%s\n", sys_siglist[number]);
    else fprintf(stderr, "Unknown signal %d\n", number);
    errno = saved;
}
