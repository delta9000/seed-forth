/* Original seed-forth implementation; see LICENSE and PROCESS-POSIX.md.
   POSIX system(): one "sh -c" child, waited for synchronously. */
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <paths.h>
#include <errno.h>

int system(const char *command)
{
    struct sigaction ignore, old_interrupt, old_quit;
    sigset_t block, old_mask;
    pid_t child;
    int status, saved;
    char *arguments[4];
    if (command == NULL) return access(_PATH_BSHELL, X_OK) == 0;
    /* The caller ignores SIGINT/SIGQUIT and holds SIGCHLD while it waits. */
    sigemptyset(&ignore.sa_mask);
    ignore.sa_flags = 0;
    ignore.sa_handler = SIG_IGN;
    sigaction(SIGINT, &ignore, &old_interrupt);
    sigaction(SIGQUIT, &ignore, &old_quit);
    sigemptyset(&block);
    sigaddset(&block, SIGCHLD);
    sigprocmask(SIG_BLOCK, &block, &old_mask);
    child = fork();
    if (child == 0) {
        /* The child gets back the caller's dispositions and mask. */
        sigaction(SIGINT, &old_interrupt, NULL);
        sigaction(SIGQUIT, &old_quit, NULL);
        sigprocmask(SIG_SETMASK, &old_mask, NULL);
        arguments[0] = "sh";
        arguments[1] = "-c";
        arguments[2] = (char *)command;
        arguments[3] = NULL;
        execve(_PATH_BSHELL, arguments, environ);
        _exit(127);
    }
    if (child < 0) {
        status = -1;
    } else {
        while (waitpid(child, &status, 0) < 0) {
            if (errno != EINTR) {
                status = -1;
                break;
            }
        }
    }
    saved = errno;
    sigaction(SIGINT, &old_interrupt, NULL);
    sigaction(SIGQUIT, &old_quit, NULL);
    sigprocmask(SIG_SETMASK, &old_mask, NULL);
    errno = saved;
    return status;
}
