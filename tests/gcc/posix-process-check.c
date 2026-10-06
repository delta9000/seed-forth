/* POSIX process fixture: Forth runtime versus host glibc. main returns 5
   after registering exit handlers, which must then run in reverse order. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/resource.h>

#define CALL(label, expression) do { long value_; errno = 0; value_ = (long)(expression); int error_ = errno; \
    printf("%s %ld errno %d\n", label, value_, error_); errno = 0; } while (0)

static void report(const char *label, int status)
{
    printf("%s exited %d status %d signaled %d signal %d\n", label, WIFEXITED(status),
           WIFEXITED(status) ? WEXITSTATUS(status) : -1, WIFSIGNALED(status),
           WIFSIGNALED(status) ? WTERMSIG(status) : -1);
}

static int child_status(pid_t child)
{
    int status = -1;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
    }
    return status;
}

static void executing(void)
{
    char *environment[3];
    pid_t child;
    child = fork();
    if (child == 0) {
        execl("/bin/sh", "sh", "-c", "echo execl \"$0\" \"$1\" \"$#\"", "zero", "one", (char *)NULL);
        _exit(99);
    }
    report("execl", child_status(child));
    child = fork();
    if (child == 0) {
        execlp("sh", "sh", "-c", "echo execlp \"$SEED_POSIX\"", (char *)NULL);
        _exit(99);
    }
    report("execlp", child_status(child));
    child = fork();
    if (child == 0) {
        environment[0] = "SEED_POSIX=replaced";
        environment[1] = "PATH=/usr/bin:/bin";
        environment[2] = NULL;
        execle("/bin/sh", "sh", "-c", "echo execle \"$SEED_POSIX\"; env | wc -l", (char *)NULL, environment);
        _exit(99);
    }
    report("execle", child_status(child));
    CALL("execl missing", execl("/no/such/program", "x", (char *)NULL));
    CALL("execlp missing", execlp("no-such-seed-program", "x", (char *)NULL));
    CALL("execlp directory", execl("/", "x", (char *)NULL));
}

static volatile sig_atomic_t interrupts;
static void interrupt_handler(int number)
{
    (void)number;
    interrupts++;
}

static void shells(void)
{
    struct sigaction action;
    sigset_t mask;
    printf("system null %d\n", system(NULL) != 0);
    report("system exit 3", system("exit 3"));
    report("system echo", system("echo from system"));
    report("system term", system("kill -TERM $$"));
    report("system missing", system("no-such-seed-program 2>/dev/null"));
    memset(&action, 0, sizeof(action));
    action.sa_handler = interrupt_handler;
    sigemptyset(&action.sa_mask);
    sigaction(SIGINT, &action, NULL);
    report("system interrupt", system("kill -INT $PPID; sleep 0"));
    printf("interrupts during system %d\n", (int)interrupts);
    sigaction(SIGINT, NULL, &action);
    printf("handler restored %d\n", action.sa_handler == interrupt_handler);
    sigprocmask(SIG_BLOCK, NULL, &mask);
    printf("sigchld blocked after %d\n", sigismember(&mask, SIGCHLD));
    raise(SIGINT);
    printf("interrupts after %d\n", (int)interrupts);
    signal(SIGINT, SIG_DFL);
}

static void pipes(void)
{
    FILE *stream, *other;
    char line[256];
    stream = popen("echo one; echo two; exit 0", "r");
    printf("popen r %d\n", stream != NULL);
    while (fgets(line, sizeof(line), stream)) printf("read %s", line);
    report("pclose r", pclose(stream));
    stream = popen("exit 4", "r");
    report("pclose exit", pclose(stream));
    stream = popen("cat > written.txt", "w");
    fputs("through the pipe\n", stream);
    report("pclose w", pclose(stream));
    stream = fopen("written.txt", "r");
    if (fgets(line, sizeof(line), stream)) printf("file %s", line);
    fclose(stream);
    /* The second shell must not hold the first stream's descriptor. */
    other = popen("cat > held.txt", "w");
    stream = popen("ls /proc/$$/fd | sort -n | tr '\\n' ' '", "r");
    if (fgets(line, sizeof(line), stream)) printf("second shell fds %s\n", line);
    report("pclose second", pclose(stream));
    report("pclose first", pclose(other));
    stream = popen("echo cloexec", "re");
    printf("re cloexec %d\n", (fcntl(fileno(stream), F_GETFD) & FD_CLOEXEC) != 0);
    pclose(stream);
    stream = popen("true", "r");
    printf("r cloexec %d\n", (fcntl(fileno(stream), F_GETFD) & FD_CLOEXEC) != 0);
    pclose(stream);
    errno = 0;
    stream = popen("true", "x");
    printf("bad mode %d errno %d\n", stream == NULL, errno);
#ifndef __GLIBC__
    errno = 0;
    if (pclose(stdin) != -1 || errno != ECHILD) printf("pclose of a plain stream accepted\n");
#endif
}

static void waiting(void)
{
    struct rusage usage;
    pid_t child, result;
    int status;
    child = fork();
    if (child == 0) _exit(6);
    result = wait4(child, &status, 0, &usage);
    printf("wait4 %d usage %d\n", result == child, usage.ru_utime.tv_sec >= 0);
    report("wait4", status);
    child = fork();
    if (child == 0) {
        pause();
        _exit(0);
    }
    CALL("wait3 running", wait3(&status, WNOHANG, NULL));
    kill(child, SIGKILL);
    result = wait3(&status, 0, &usage);
    printf("wait3 %d\n", result == child);
    report("wait3", status);
    CALL("wait3 none", wait3(&status, WNOHANG, NULL));
    printf("macros %d %d %d %d\n", WCOREDUMP(0x8b), WCOREDUMP(0x0b), WIFCONTINUED(0xffff), WIFCONTINUED(0x0b));
    printf("constants %d %d %d\n", WNOHANG, WUNTRACED, WCONTINUED);
}

static void first_handler(void) { puts("atexit first (runs last)"); }
static void third_handler(void) { puts("atexit third (runs first)"); }
static void status_handler(int status, void *argument)
{
    printf("on_exit status %d argument %s\n", status, (const char *)argument);
}

static void terminating(void)
{
    pid_t child;
    child = fork();
    if (child == 0) {
        atexit(first_handler);
        exit(9);
    }
    report("exit child", child_status(child));
    child = fork();
    if (child == 0) {
        atexit(first_handler);
        _Exit(10);
    }
    report("_Exit child", child_status(child));
    child = fork();
    if (child == 0) {
        int count;
        for (count = 0; count < 32; count++)
            if (atexit(first_handler) != 0) _exit(1);
        _exit(0);
    }
    report("32 handlers", child_status(child));
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    executing();
    shells();
    pipes();
    waiting();
    terminating();
    atexit(first_handler);
    on_exit(status_handler, "kept");
    atexit(third_handler);
    puts("returning 5");
    return 5;
}
