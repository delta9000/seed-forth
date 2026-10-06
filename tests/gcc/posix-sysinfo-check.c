/* POSIX identity and system-information fixture: Forth runtime versus
   host glibc. Values that depend on the machine are printed only where both
   implementations must read the same kernel state. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/times.h>
#include <sys/resource.h>
#include <sys/utsname.h>
#include <grp.h>

#define SHOW(name) printf("%s %ld\n", #name, (long)(name))
#define CALL(label, expression) do { long value_; errno = 0; value_ = (long)(expression); int error_ = errno; \
    printf("%s %ld errno %d\n", label, value_, error_); } while (0)

static void identity(void)
{
    gid_t groups[256];
    int count, index;
    pid_t child;
    int status;
    printf("ids %u %u %u %u\n", (unsigned)getuid(), (unsigned)geteuid(), (unsigned)getgid(), (unsigned)getegid());
    printf("ppid matches %d\n", getppid() > 1);
    count = getgroups(0, NULL);
    printf("groups %d\n", count);
    if (count > 0 && count <= 256) {
        count = getgroups(256, groups);
        for (index = 0; index < count; index++) printf(" group %u\n", (unsigned)groups[index]);
    }
    errno = 0;
    CALL("getgroups too small", count > 0 ? getgroups(count > 1 ? 1 : -1, groups) : -1);
    printf("pgrp %d\n", getpgrp() == getpgid(0));
    printf("sid %d\n", getsid(0) == getsid(getpid()));
    errno = 0;
    CALL("getpgid bad", getpgid(-5));
    CALL("setuid same", setuid(getuid()));
    CALL("setgid same", setgid(getgid()));
    CALL("seteuid same", seteuid(geteuid()));
    CALL("setegid same", setegid(getegid()));
    CALL("setreuid none", setreuid((uid_t)-1, (uid_t)-1));
    CALL("setregid none", setregid((gid_t)-1, (gid_t)-1));
    errno = 0;
    CALL("seteuid -1", seteuid((uid_t)-1));
    if (geteuid() != 0) {
        errno = 0;
        CALL("setuid root", setuid(0));
        errno = 0;
        CALL("setgroups", setgroups(0, NULL));
    }
    child = fork();
    if (child == 0) {
        pid_t session = setsid();
        if (session != getpid() || getsid(0) != session || getpgrp() != session) _exit(1);
        errno = 0;
        if (setsid() != -1 || errno != EPERM) _exit(2);
        _exit(0);
    }
    waitpid(child, &status, 0);
    printf("setsid child %d\n", WEXITSTATUS(status));
    child = fork();
    if (child == 0) {
        if (setpgid(0, 0) != 0 || getpgrp() != getpid()) _exit(1);
        _exit(0);
    }
    waitpid(child, &status, 0);
    printf("setpgid child %d\n", WEXITSTATUS(status));
}

static void system_names(void)
{
    struct utsname name, other;
    char host[256], tiny[2];
    printf("uname %d\n", uname(&name));
    printf("sysname %s machine %s\n", name.sysname, name.machine);
    printf("release %s\n", name.release);
    printf("version %s\n", name.version);
    printf("nodename %s domain %s\n", name.nodename, name.domainname);
    uname(&other);
    printf("sizes %lu\n", (unsigned long)sizeof(name));
    printf("gethostname %d %s\n", gethostname(host, sizeof(host)), host);
    printf("matches %d\n", strcmp(host, name.nodename) == 0);
    errno = 0;
    CALL("gethostname tiny", gethostname(tiny, 1));
}

static void configuration(void)
{
    long physical, available;
    SHOW(_POSIX_VERSION); SHOW(_POSIX2_VERSION); SHOW(_POSIX_JOB_CONTROL);
    SHOW(_POSIX_SAVED_IDS); SHOW(_POSIX_NO_TRUNC); SHOW(_POSIX_VDISABLE);
    SHOW(PATH_MAX); SHOW(NAME_MAX); SHOW(PIPE_BUF); SHOW(NGROUPS_MAX);
    SHOW(LINE_MAX); SHOW(RE_DUP_MAX); SHOW(HOST_NAME_MAX); SHOW(LOGIN_NAME_MAX);
    SHOW(TTY_NAME_MAX); SHOW(IOV_MAX); SHOW(CHARCLASS_NAME_MAX); SHOW(COLL_WEIGHTS_MAX);
    SHOW(EXPR_NEST_MAX); SHOW(BC_BASE_MAX); SHOW(BC_DIM_MAX); SHOW(BC_SCALE_MAX);
    SHOW(BC_STRING_MAX); SHOW(_POSIX_ARG_MAX); SHOW(_POSIX_PATH_MAX);
    SHOW(_POSIX_OPEN_MAX); SHOW(_POSIX2_LINE_MAX);
    SHOW(sysconf(_SC_ARG_MAX)); SHOW(sysconf(_SC_CHILD_MAX)); SHOW(sysconf(_SC_CLK_TCK));
    SHOW(sysconf(_SC_NGROUPS_MAX)); SHOW(sysconf(_SC_OPEN_MAX)); SHOW(sysconf(_SC_STREAM_MAX));
    SHOW(sysconf(_SC_TZNAME_MAX)); SHOW(sysconf(_SC_JOB_CONTROL)); SHOW(sysconf(_SC_SAVED_IDS));
    SHOW(sysconf(_SC_VERSION)); SHOW(sysconf(_SC_PAGESIZE)); SHOW(sysconf(_SC_PAGE_SIZE));
    SHOW(sysconf(_SC_RTSIG_MAX)); SHOW(sysconf(_SC_BC_BASE_MAX)); SHOW(sysconf(_SC_BC_DIM_MAX));
    SHOW(sysconf(_SC_BC_SCALE_MAX)); SHOW(sysconf(_SC_BC_STRING_MAX));
    SHOW(sysconf(_SC_COLL_WEIGHTS_MAX)); SHOW(sysconf(_SC_EXPR_NEST_MAX));
    SHOW(sysconf(_SC_LINE_MAX)); SHOW(sysconf(_SC_RE_DUP_MAX)); SHOW(sysconf(_SC_2_VERSION));
    SHOW(sysconf(_SC_IOV_MAX)); SHOW(sysconf(_SC_GETGR_R_SIZE_MAX));
    SHOW(sysconf(_SC_GETPW_R_SIZE_MAX)); SHOW(sysconf(_SC_LOGIN_NAME_MAX));
    SHOW(sysconf(_SC_TTY_NAME_MAX)); SHOW(sysconf(_SC_NPROCESSORS_CONF));
    SHOW(sysconf(_SC_NPROCESSORS_ONLN)); SHOW(sysconf(_SC_SYMLOOP_MAX));
    SHOW(sysconf(_SC_HOST_NAME_MAX)); SHOW(sysconf(_SC_PHYS_PAGES));
    physical = sysconf(_SC_PHYS_PAGES);
    available = sysconf(_SC_AVPHYS_PAGES);
    printf("available pages in range %d\n", available > 0 && available <= physical);
    errno = 0;
    CALL("sysconf -1", sysconf(-1));
    errno = 0;
    CALL("sysconf 9999", sysconf(9999));
    SHOW(getpagesize());
    SHOW(getdtablesize());
}

static void path_configuration(const char *path)
{
    int names[12], index, descriptor;
    names[0] = _PC_LINK_MAX; names[1] = _PC_MAX_CANON; names[2] = _PC_MAX_INPUT;
    names[3] = _PC_NAME_MAX; names[4] = _PC_PATH_MAX; names[5] = _PC_PIPE_BUF;
    names[6] = _PC_CHOWN_RESTRICTED; names[7] = _PC_NO_TRUNC; names[8] = _PC_VDISABLE;
    names[9] = _PC_FILESIZEBITS; names[10] = _PC_SYMLINK_MAX; names[11] = _PC_2_SYMLINKS;
    descriptor = open(path, O_RDONLY);
    for (index = 0; index < 12; index++) {
        errno = 0;
        printf("pathconf %s %d %ld", path, names[index], pathconf(path, names[index]));
        printf(" errno %d", errno);
        errno = 0;
        printf(" fpathconf %ld", fpathconf(descriptor, names[index]));
        printf(" errno %d\n", errno);
    }
    close(descriptor);
}

static void paths(void)
{
    path_configuration(".");
    path_configuration("/");
    path_configuration("/proc");
    path_configuration("/dev");
    path_configuration("/tmp");
    errno = 0;
    CALL("pathconf missing", pathconf("no-such-file", _PC_NAME_MAX));
    errno = 0;
    CALL("pathconf bad name", pathconf(".", 9999));
    errno = 0;
    CALL("fpathconf bad fd", fpathconf(-1, _PC_NAME_MAX));
}

static void resources(void)
{
    struct rlimit limit;
    struct rusage usage;
    struct tms ticks;
    int resource;
    SHOW(RLIM_INFINITY == (rlim_t)-1);
    for (resource = 0; resource < RLIMIT_NLIMITS; resource++) {
        getrlimit(resource, &limit);
        printf("rlimit %d %lu %lu\n", resource, (unsigned long)limit.rlim_cur, (unsigned long)limit.rlim_max);
    }
    errno = 0;
    CALL("getrlimit bad", getrlimit(99, &limit));
    getrlimit(RLIMIT_NOFILE, &limit);
    limit.rlim_cur = 64;
    CALL("setrlimit nofile", setrlimit(RLIMIT_NOFILE, &limit));
    getrlimit(RLIMIT_NOFILE, &limit);
    printf("nofile now %lu sysconf %ld dtablesize %d\n", (unsigned long)limit.rlim_cur,
           sysconf(_SC_OPEN_MAX), getdtablesize());
    limit.rlim_cur = limit.rlim_max + 1;
    errno = 0;
    if (limit.rlim_max != RLIM_INFINITY) CALL("setrlimit above max", setrlimit(RLIMIT_NOFILE, &limit));
    CALL("getrusage", getrusage(RUSAGE_SELF, &usage));
    printf("maxrss positive %d\n", usage.ru_maxrss > 0);
    CALL("getrusage children", getrusage(RUSAGE_CHILDREN, &usage));
    errno = 0;
    CALL("getrusage bad", getrusage(5, &usage));
    printf("times positive %d\n", (long)times(&ticks) > 0);
    printf("ticks %d\n", ticks.tms_utime >= 0 && ticks.tms_stime >= 0);
    SHOW(PRIO_PROCESS); SHOW(PRIO_PGRP); SHOW(PRIO_USER);
    errno = 0;
    CALL("getpriority", getpriority(PRIO_PROCESS, 0));
    CALL("nice 0", nice(0));
    CALL("nice 1", nice(1));
    CALL("getpriority after", getpriority(PRIO_PROCESS, 0));
    CALL("setpriority 5", setpriority(PRIO_PROCESS, 0, 5));
    CALL("getpriority 5", getpriority(PRIO_PROCESS, 0));
    if (geteuid() != 0) {
        errno = 0;
        CALL("nice -10", nice(-10));
        errno = 0;
        CALL("setpriority -10", setpriority(PRIO_PROCESS, 0, -10));
    }
    errno = 0;
    CALL("getpriority bad", getpriority(7, 0));
}

static void clocks(void)
{
    struct timespec now, later, resolution, request, remaining;
    struct timeval moment;
    time_t seconds;
    CALL("realtime", clock_gettime(CLOCK_REALTIME, &now));
    seconds = time(NULL);
    printf("realtime near time() %d\n", seconds - now.tv_sec >= 0 && seconds - now.tv_sec <= 2);
    printf("nanoseconds in range %d\n", now.tv_nsec >= 0 && now.tv_nsec < 1000000000L);
    clock_gettime(CLOCK_MONOTONIC, &now);
    request.tv_sec = 0;
    request.tv_nsec = 20000000L;
    CALL("nanosleep", nanosleep(&request, &remaining));
    clock_gettime(CLOCK_MONOTONIC, &later);
    printf("slept %d\n", (later.tv_sec - now.tv_sec) * 1000000000L + (later.tv_nsec - now.tv_nsec) >= 20000000L);
    CALL("usleep", usleep(10000));
    CALL("getres", clock_getres(CLOCK_MONOTONIC, &resolution));
    printf("resolution %ld %ld\n", (long)resolution.tv_sec, resolution.tv_nsec);
    CALL("process clock", clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now));
    errno = 0;
    CALL("bad clock", clock_gettime(99, &now));
    request.tv_nsec = 1000000000L;
    errno = 0;
    CALL("bad nanosleep", nanosleep(&request, NULL));
    gettimeofday(&moment, NULL);
    if (geteuid() != 0) {
        errno = 0;
        CALL("settimeofday", settimeofday(&moment, NULL));
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    identity();
    system_names();
    configuration();
    paths();
    resources();
    clocks();
    puts("done");
    return 0;
}
