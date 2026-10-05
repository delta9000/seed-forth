/* The same public process-API program is built by Forth and by host GCC/libc.
   Usage: process-api-check CHILD DIRECTORY. CHILD is the Forth-built
   process-api-child; DIRECTORY holds denied/seedchild (mode 0644) and
   allowed/seedchild (a copy of CHILD), prepared by the Python gate. */
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static char *child_path;
static char *directory;
static volatile sig_atomic_t interrupted;

static void on_signal(int number)
{
    if (number == SIGUSR1) interrupted = 1;
}

/* Fork, run CHILD with ARGV, wait, return the raw status (or -1). */
static int run_child(char **arguments)
{
    int status = -1;
    pid_t process = fork();
    if (process == 0) {
        execv(child_path, arguments);
        _exit(120);
    }
    if (process < 0 || waitpid(process, &status, 0) != process) return -1;
    return status;
}

static ssize_t read_all(int descriptor, char *buffer, size_t size)
{
    size_t total = 0;
    ssize_t count;
    while (total < size && (count = read(descriptor, buffer + total, size - total)) > 0)
        total += (size_t)count;
    return (ssize_t)total;
}

/* In a child: set PATH (or remove it) and execvp NAME; exit with errno. */
static int search_status(const char *path, const char *name, char **arguments)
{
    static char entry[1024];
    char *environment[2];
    int status = -1;
    pid_t process;
    environment[0] = NULL;
    environment[1] = NULL;
    if (path) {
        if (snprintf(entry, sizeof(entry), "PATH=%s", path) < 0) return -1;
        environment[0] = entry;
    }
    process = fork();
    if (process == 0) {
        environ = environment;
        execvp(name, arguments);
        _exit(errno == ENOENT ? 60 : errno == EACCES ? 61 : errno == ENOEXEC ? 62 : 63);
    }
    if (process < 0 || waitpid(process, &status, 0) != process) return -1;
    return status;
}

int main(int argc, char **argv)
{
    static char upper[] = "upper", exit_word[] = "exit", signal_word[] = "signal";
    static char env_word[] = "env", name[] = "SEED_PROCESS", seen[] = "SEED_PROCESS=seen";
    static char fortytwo[] = "42", fifteen[] = "15", sh[] = "/bin/sh", dash_c[] = "-c";
    static char seedchild[] = "seedchild", shell_name[] = "sh", seven[] = "exit 7", echo[] = "echo redirected";
    char *arguments[5], *environment[2], buffer[256], path[512], allowed[512], denied[512];
    int to_child[2], from_child[2], status, file, value = 1;
    pid_t process, parent;
    unsigned int left;
    if (argc != 3) return 1;
    child_path = argv[1];
    directory = argv[2];
    if (WNOHANG != 1 || WUNTRACED != 2 || SIGKILL != 9 || SIGTERM != 15) return 2;

    /* Pipes in both directions between parent and a forked child. */
    if (pipe(to_child) || pipe(from_child)) return 3;
    process = fork();
    if (process == 0) {
        char byte;
        close(to_child[1]);
        close(from_child[0]);
        while (read(to_child[0], &byte, 1) == 1) {
            byte = (char)(byte + 1);
            if (write(from_child[1], &byte, 1) != 1) _exit(2);
        }
        _exit(0);
    }
    if (process < 0) return 4;
    close(to_child[0]);
    close(from_child[1]);
    if (write(to_child[1], "HAL", 3) != 3 || close(to_child[1])) return 5;
    if (read_all(from_child[0], buffer, sizeof(buffer)) != 3 || memcmp(buffer, "IBM", 3)) return 6;
    if (close(from_child[0]) || waitpid(process, &status, 0) != process
        || !WIFEXITED(status) || WEXITSTATUS(status) != 0) return 7;

    /* dup2 places pipes on the exec'd child's stdin and stdout. */
    if (pipe(to_child) || pipe(from_child)) return 8;
    process = fork();
    if (process == 0) {
        arguments[0] = child_path; arguments[1] = upper; arguments[2] = NULL;
        if (dup2(to_child[0], 0) != 0 || dup2(from_child[1], 1) != 1) _exit(121);
        close(to_child[0]); close(to_child[1]); close(from_child[0]); close(from_child[1]);
        execv(child_path, arguments);
        _exit(120);
    }
    close(to_child[0]);
    close(from_child[1]);
    if (write(to_child[1], "hello, pipe", 11) != 11 || close(to_child[1])) return 9;
    if (read_all(from_child[0], buffer, sizeof(buffer)) != 11 || memcmp(buffer, "HELLO, PIPE", 11)) return 10;
    if (close(from_child[0]) || waitpid(process, &status, 0) != process
        || !WIFEXITED(status) || WEXITSTATUS(status) != 0 || WIFSIGNALED(status)) return 11;

    /* dup2 redirects an exec'd shell's stdout into a file. */
    if (snprintf(path, sizeof(path), "%s/redirected", directory) < 0) return 12;
    file = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
    if (file < 0) return 13;
    process = fork();
    if (process == 0) {
        arguments[0] = sh; arguments[1] = dash_c; arguments[2] = echo; arguments[3] = NULL;
        if (dup2(file, 1) != 1) _exit(121);
        execv(sh, arguments);
        _exit(120);
    }
    if (waitpid(process, &status, 0) != process || status != 0) return 14;
    if (lseek(file, 0, SEEK_SET) != 0 || read_all(file, buffer, sizeof(buffer)) != 11
        || memcmp(buffer, "redirected\n", 11) || close(file) || unlink(path)) return 15;
    if (dup2(-1, 20) != -1 || errno != EBADF) return 16;
    if (dup2(1, 1) != 1) return 17;

    /* Exit statuses and signal deaths, decoded by the W* macros. */
    arguments[0] = child_path; arguments[1] = exit_word; arguments[2] = fortytwo; arguments[3] = NULL;
    status = run_child(arguments);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 42 || WIFSIGNALED(status) || WIFSTOPPED(status)) return 18;
    arguments[1] = signal_word; arguments[2] = fifteen;
    status = run_child(arguments);
    if (WIFEXITED(status) || !WIFSIGNALED(status) || WTERMSIG(status) != SIGTERM) return 19;

    /* execve passes exactly the given environment; execv passes environ. */
    arguments[1] = env_word; arguments[2] = name; arguments[3] = NULL;
    environment[0] = seen; environment[1] = NULL;
    process = fork();
    if (process == 0) { execve(child_path, arguments, environment); _exit(120); }
    if (waitpid(process, &status, 0) != process || status != 0) return 20;
    if (run_child(arguments) != 104 << 8) return 21;
    process = fork();
    if (process == 0) { environ = environment; execv(child_path, arguments); _exit(120); }
    if (waitpid(process, &status, 0) != process || status != 0) return 22;
    errno = 0;
    if (execve("/nonexistent/seed-process", arguments, environment) != -1 || errno != ENOENT) return 23;

    /* execvp PATH search: skip a non-executable match, then succeed. */
    if (snprintf(allowed, sizeof(allowed), "%s/allowed", directory) < 0
        || snprintf(denied, sizeof(denied), "%s/denied", directory) < 0
        || snprintf(path, sizeof(path), "/nonexistent-seed:%s:%s", denied, allowed) < 0) return 24;
    arguments[0] = seedchild; arguments[1] = exit_word; arguments[2] = fortytwo; arguments[3] = NULL;
    status = search_status(path, seedchild, arguments);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 42) return 25;
    if (snprintf(path, sizeof(path), "/nonexistent-seed:%s", denied) < 0) return 26;
    if (search_status(path, seedchild, arguments) != 61 << 8) return 27;
    if (search_status("/nonexistent-seed:/nonexistent-too", seedchild, arguments) != 60 << 8) return 28;
    if (search_status(allowed, "", arguments) != 60 << 8) return 29;
    /* A name containing a slash is not searched. */
    if (search_status(allowed, "./seedchild", arguments) != 60 << 8) return 30;
    /* Without PATH the default path finds sh. */
    arguments[0] = shell_name; arguments[1] = dash_c; arguments[2] = seven; arguments[3] = NULL;
    if (search_status(NULL, "sh", arguments) != 7 << 8) return 31;

    /* vfork behaves as a fork whose child may exec or _exit. */
    process = vfork();
    if (process == 0) _exit(3);
    if (process < 0 || waitpid(process, &status, 0) != process || WEXITSTATUS(status) != 3) return 32;
#ifndef PROCESS_API_HOST_ORACLE
    /* The runtime's vfork child has private memory (host vfork shares). */
    process = vfork();
    if (process == 0) { value = 2; _exit(0); }
    if (process < 0 || waitpid(process, &status, 0) != process || value != 1) return 33;
#else
    (void)value;
#endif

    /* WNOHANG, WUNTRACED stop reports, kill, and SIGKILL deaths. */
    if (pipe(to_child)) return 34;
    process = fork();
    if (process == 0) {
        close(to_child[1]);
        read(to_child[0], buffer, 1);
        _exit(9);
    }
    close(to_child[0]);
    if (waitpid(process, &status, WNOHANG) != 0) return 35;
    if (kill(process, 0) != 0) return 36;
    if (kill(process, SIGSTOP) || waitpid(process, &status, WUNTRACED) != process
        || !WIFSTOPPED(status) || WSTOPSIG(status) != SIGSTOP || WIFEXITED(status)
        || WIFSIGNALED(status)) return 37;
    if (kill(process, SIGKILL) || waitpid(process, &status, 0) != process
        || !WIFSIGNALED(status) || WTERMSIG(status) != SIGKILL) return 38;
    close(to_child[1]);
    if (kill(process, 0) != -1 || errno != ESRCH) return 39;
    if (kill(getpid(), 1000) != -1 || errno != EINVAL) return 40;
    if (waitpid(-1, &status, 0) != -1 || errno != ECHILD) return 41;
    if (wait(&status) != -1 || errno != ECHILD) return 42;
    process = fork();
    if (process == 0) _exit(5);
    if (wait(&status) != process || WEXITSTATUS(status) != 5) return 43;
    if (waitpid(process, &status, WNOHANG) != -1 || errno != ECHILD) return 44;

    /* sleep: zero, a full second, and EINTR with unslept seconds. */
    errno = 777;
    if (sleep(0) != 0 || errno != 777) return 45;
    if (sleep(1) != 0) return 46;
    if (signal(SIGUSR1, on_signal) == SIG_ERR) return 47;
    parent = getpid();
    process = fork();
    if (process == 0) {
        sleep(1);
        kill(parent, SIGUSR1);
        _exit(0);
    }
    left = sleep(20);
    if (!interrupted || left < 10 || left > 19) return 48;
    if (waitpid(process, &status, 0) != process || status != 0) return 49;
    printf("process API contracts passed\n");
    return 0;
}
