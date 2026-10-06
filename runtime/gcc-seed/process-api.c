/* Original seed-forth implementation; see LICENSE and PROCESS-API.md.
   Bounded Linux AMD64 process creation, replacement, waiting and signals. */
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <seed-syscall.h>

/* One raw call: kernel errors in [-4095, -1] become errno and -1. */
static long seed_process_call(long number, long a1, long a2, long a3, long a4)
{
    long result = __seed_syscall6(number, a1, a2, a3, a4, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return result;
}

int pipe(int descriptors[2])
{
    return (int)seed_process_call(22, (long)descriptors, 0, 0, 0);
}

int dup(int descriptor)
{
    /* The lowest free descriptor; close-on-exec is clear on the copy. */
    return (int)seed_process_call(32, descriptor, 0, 0, 0);
}

int dup2(int descriptor, int target)
{
    return (int)seed_process_call(33, descriptor, target, 0, 0);
}

pid_t fork(void)
{
    /* Every runtime stream is unbuffered, so no output is duplicated. */
    return (pid_t)seed_process_call(57, 0, 0, 0, 0);
}

pid_t vfork(void)
{
    /* A true vfork child would borrow the parent's stack frame; returning
       from this wrapper or calling functions would corrupt it. An ordinary
       fork gives the child a private copy, which POSIX permits. */
    return fork();
}

int execve(const char *path, char *const arguments[], char *const environment[])
{
    return (int)seed_process_call(59, (long)path, (long)arguments, (long)environment, 0);
}

int execv(const char *path, char *const arguments[])
{
    /* environ is read at call time: callers may replace it just before. */
    return execve(path, arguments, environ);
}

int execvp(const char *file, char *const arguments[])
{
    char candidate[4096];
    const char *search, *element, *end;
    size_t file_length, directory_length;
    int denied = 0, last = ENOENT;
    if (*file == '\0') {
        errno = ENOENT;
        return -1;
    }
    if (strchr(file, '/')) return execv(file, arguments);
    search = getenv("PATH");
    if (search == NULL) search = "/bin:/usr/bin";
    file_length = strlen(file);
    element = search;
    for (;;) {
        end = strchr(element, ':');
        if (end == NULL) end = element + strlen(element);
        directory_length = (size_t)(end - element);
        /* An empty element names the current directory. */
        if (directory_length + file_length + 2 > sizeof(candidate)) {
            last = ENAMETOOLONG;
        } else {
            memcpy(candidate, element, directory_length);
            if (directory_length) candidate[directory_length++] = '/';
            memcpy(candidate + directory_length, file, file_length + 1);
            execv(candidate, arguments);
            if (errno == EACCES) denied = 1;
            else if (errno != ENOENT && errno != ENOTDIR && errno != ESTALE
                     && errno != ENODEV && errno != ETIMEDOUT) return -1;
            last = errno;
        }
        if (*end == '\0') break;
        element = end + 1;
    }
    errno = denied ? EACCES : last;
    return -1;
}

pid_t waitpid(pid_t process, int *status, int options)
{
    return (pid_t)seed_process_call(61, process, (long)status, options, 0);
}

pid_t wait(int *status)
{
    return waitpid(-1, status, 0);
}

int kill(pid_t process, int number)
{
    return (int)seed_process_call(62, process, number, 0, 0);
}

unsigned int sleep(unsigned int seconds)
{
    long request[2], remaining[2];
    int saved = errno;
    request[0] = (long)seconds;
    request[1] = 0;
    remaining[0] = 0;
    remaining[1] = 0;
    if (seed_process_call(35, (long)request, (long)remaining, 0, 0) < 0) {
        /* Interrupted: report unslept time, rounding a partial second up. */
        if (errno == EINTR) return (unsigned int)(remaining[0] + (remaining[1] > 0));
        return seconds;
    }
    errno = saved;
    return 0;
}

pid_t wait4(pid_t process, int *status, int options, struct rusage *usage)
{
    return (pid_t)seed_process_call(61, process, (long)status, options, (long)usage);
}

pid_t wait3(int *status, int options, struct rusage *usage)
{
    return wait4(-1, status, options, usage);
}
