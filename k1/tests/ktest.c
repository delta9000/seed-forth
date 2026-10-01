/* ktest.c -- K1's syscall tests, built with the chain's tcc-musl.
 * Runs the same on Linux; the exit status is the number of failures. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <dirent.h>
#include <poll.h>
#include <spawn.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/utsname.h>

extern char **environ;
static int fails;
#define CHECK(c) do { if (c) printf("ok   %s\n", #c); \
    else { printf("FAIL %s (line %d, errno %d)\n", #c, __LINE__, errno); fails++; } } while (0)

static volatile int got_usr1, got_chld;
static void on_usr1(int s) { got_usr1++; }
static void on_chld(int s) { got_chld++; }

static void t_pipe_yes_head(void)
{
    /* writer floods a pipe; reader takes 10 bytes and closes; the writer
     * must then die of SIGPIPE (the `yes | head` case) */
    int p[2], st;
    pid_t w, r;
    CHECK(pipe(p) == 0);
    w = fork();
    if (w == 0) {
        char buf[4096];
        memset(buf, 'y', sizeof buf);
        close(p[0]);
        for (;;)
            write(p[1], buf, sizeof buf);
    }
    r = fork();
    if (r == 0) {
        char buf[10];
        int n = 0, k;
        close(p[1]);
        while (n < 10 && (k = read(p[0], buf + n, 10 - n)) > 0)
            n += k;
        _exit(n == 10 && buf[9] == 'y' ? 0 : 1);
    }
    close(p[0]);
    close(p[1]);
    CHECK(waitpid(r, &st, 0) == r && WIFEXITED(st) && WEXITSTATUS(st) == 0);
    CHECK(waitpid(w, &st, 0) == w && WIFSIGNALED(st) && WTERMSIG(st) == SIGPIPE);
}

static void t_fork_noexec(void)
{
    int st, x = 41;
    pid_t c = fork();
    if (c == 0) {
        x++;            /* private copy */
        _exit(x);
    }
    CHECK(waitpid(c, &st, 0) == c && WIFEXITED(st) && WEXITSTATUS(st) == 42);
    CHECK(x == 41);
}

static void t_signals(void)
{
    struct sigaction sa;
    sigset_t s, old;
    int st;
    pid_t c;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_usr1;
    CHECK(sigaction(SIGUSR1, &sa, NULL) == 0);
    kill(getpid(), SIGUSR1);
    CHECK(got_usr1 == 1);
    sigemptyset(&s);
    sigaddset(&s, SIGUSR1);
    sigprocmask(SIG_BLOCK, &s, &old);
    kill(getpid(), SIGUSR1);
    CHECK(got_usr1 == 1);           /* blocked */
    sigprocmask(SIG_SETMASK, &old, NULL);
    CHECK(got_usr1 == 2);           /* delivered on unblock */
    sa.sa_handler = on_chld;
    sa.sa_flags = SA_RESTART;
    sigaction(SIGCHLD, &sa, NULL);
    c = fork();
    if (c == 0)
        _exit(0);
    CHECK(waitpid(c, &st, 0) == c);
    CHECK(got_chld >= 1);
    signal(SIGCHLD, SIG_DFL);
    c = fork();
    if (c == 0) {
        pause();
        _exit(0);
    }
    usleep(1000);
    kill(c, SIGTERM);
    CHECK(waitpid(c, &st, 0) == c && WIFSIGNALED(st) && WTERMSIG(st) == SIGTERM);
    c = fork();
    if (c == 0) {
        *(volatile int *)8 = 1;     /* SIGSEGV */
        _exit(0);
    }
    CHECK(waitpid(c, &st, 0) == c && WIFSIGNALED(st) && WTERMSIG(st) == SIGSEGV);
}

static void t_files(void)
{
    struct stat a, b;
    struct timespec ts[2];
    char buf[256];
    int fd, n, found = 0;
    DIR *d;
    struct dirent *e;
    char old[256];
    getcwd(old, sizeof old);
    system("rm -rf /tmp/kt 2>/dev/null");
    mkdir("/tmp/kt", 0755);
    CHECK(mkdir("/tmp/kt", 0755) == -1 && errno == EEXIST);
    fd = open("/tmp/kt/f", O_CREAT | O_WRONLY | O_TRUNC, 0644);
    CHECK(fd >= 0);
    CHECK(write(fd, "hello\n", 6) == 6);
    CHECK(lseek(fd, 100, SEEK_SET) == 100);
    CHECK(write(fd, "x", 1) == 1);
    close(fd);
    CHECK(stat("/tmp/kt/f", &a) == 0 && a.st_size == 101 && S_ISREG(a.st_mode));
    CHECK(symlink("f", "/tmp/kt/l") == 0);
    CHECK(lstat("/tmp/kt/l", &b) == 0 && S_ISLNK(b.st_mode));
    CHECK(stat("/tmp/kt/l", &b) == 0 && b.st_ino == a.st_ino);
    n = readlink("/tmp/kt/l", buf, sizeof buf);
    CHECK(n == 1 && buf[0] == 'f');
    CHECK(link("/tmp/kt/f", "/tmp/kt/h") == 0);
    CHECK(stat("/tmp/kt/h", &b) == 0 && b.st_nlink == 2);
    ts[0].tv_sec = ts[1].tv_sec = 1000000000;
    ts[0].tv_nsec = ts[1].tv_nsec = 0;
    CHECK(utimensat(AT_FDCWD, "/tmp/kt/f", ts, 0) == 0);
    CHECK(stat("/tmp/kt/f", &b) == 0 && b.st_mtime == 1000000000);
    fd = open("/tmp/kt/g", O_CREAT | O_WRONLY, 0644);
    close(fd);
    CHECK(stat("/tmp/kt/g", &a) == 0 && a.st_mtime > b.st_mtime);
    CHECK(rename("/tmp/kt/g", "/tmp/kt/g2") == 0 && access("/tmp/kt/g", F_OK) != 0);
    CHECK(chmod("/tmp/kt/g2", 0755) == 0 && access("/tmp/kt/g2", X_OK) == 0);
    d = opendir("/tmp/kt");
    while (d && (e = readdir(d)))
        found += !strcmp(e->d_name, "g2") || !strcmp(e->d_name, "l");
    if (d)
        closedir(d);
    CHECK(found == 2);
    CHECK(chdir("/tmp/kt") == 0 && getcwd(buf, sizeof buf) && !strcmp(buf, "/tmp/kt"));
    CHECK(unlink("l") == 0 && unlink("h") == 0 && unlink("f") == 0 && unlink("g2") == 0);
    chdir(old);
    CHECK(rmdir("/tmp/kt") == 0);
    fd = open("/dev/null", O_WRONLY);
    CHECK(fd >= 0 && write(fd, "x", 1) == 1);
    CHECK(dup2(fd, 20) == 20 && fcntl(20, F_GETFD) == 0);
    CHECK(fcntl(fd, F_DUPFD_CLOEXEC, 30) == 30 && fcntl(30, F_GETFD) == FD_CLOEXEC);
    close(fd);
    close(20);
    close(30);
}

static void t_memory(void)
{
    char *p = malloc(10 << 20), *q;
    size_t i;
    CHECK(p != NULL);
    for (i = 0; i < (10 << 20); i += 4096)
        p[i] = (char)i;
    q = realloc(p, 40 << 20);
    CHECK(q != NULL && q[4096] == (char)4096);
    free(q);
    p = mmap(0, 1 << 20, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(p != MAP_FAILED && p[12345] == 0);
    p[0] = 1;
    CHECK(munmap(p, 1 << 20) == 0);
}

static void t_spawn_poll_time(void)
{
    pid_t c;
    int st, p[2];
    char *argv[] = { "/proc-not-there", NULL };
    struct pollfd pf;
    struct timespec t0, t1;
    struct utsname u;
    CHECK(posix_spawn(&c, "/no/such/prog", NULL, NULL, argv, environ) != 0);
    pipe(p);
    pf.fd = p[0];
    pf.events = POLLIN;
    CHECK(poll(&pf, 1, 0) == 0);
    write(p[1], "z", 1);
    CHECK(poll(&pf, 1, 0) == 1 && (pf.revents & POLLIN));
    close(p[0]);
    close(p[1]);
    clock_gettime(CLOCK_MONOTONIC, &t0);
    usleep(20000);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    CHECK((t1.tv_sec - t0.tv_sec) * 1000000000L + t1.tv_nsec - t0.tv_nsec >= 20000000L);
    CHECK(uname(&u) == 0 && !strcmp(u.sysname, "Linux"));
    c = vfork();
    if (c == 0)
        _exit(5);
    CHECK(waitpid(c, &st, 0) == c && WEXITSTATUS(st) == 5);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    t_fork_noexec();
    t_pipe_yes_head();
    t_signals();
    t_files();
    t_memory();
    t_spawn_poll_time();
    if (argc > 1) {         /* posix_spawn this program again, once */
        pid_t c;
        int st;
        char *av[] = { argv[0], NULL };
        CHECK(posix_spawn(&c, argv[0], NULL, NULL, av, environ) == 0);
        CHECK(waitpid(c, &st, 0) == c && WIFEXITED(st) && WEXITSTATUS(st) == 0);
    }
    printf("ktest: %d failures\n", fails);
    return fails;
}
