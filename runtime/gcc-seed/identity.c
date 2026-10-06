/* Original seed-forth implementation; see LICENSE and IDENTITY.md.
   Linux AMD64 user, group, process-group and session calls. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

static long seed_identity_call(long number, long a1, long a2, long a3)
{
    long result = __seed_syscall6(number, a1, a2, a3, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return result;
}

/* These five cannot fail and leave errno unchanged. */
uid_t getuid(void) { return (uid_t)__seed_syscall6(102, 0, 0, 0, 0, 0, 0); }
gid_t getgid(void) { return (gid_t)__seed_syscall6(104, 0, 0, 0, 0, 0, 0); }
uid_t geteuid(void) { return (uid_t)__seed_syscall6(107, 0, 0, 0, 0, 0, 0); }
gid_t getegid(void) { return (gid_t)__seed_syscall6(108, 0, 0, 0, 0, 0, 0); }
pid_t getppid(void) { return (pid_t)__seed_syscall6(110, 0, 0, 0, 0, 0, 0); }
pid_t getpgrp(void) { return (pid_t)__seed_syscall6(111, 0, 0, 0, 0, 0, 0); }

pid_t getpgid(pid_t process) { return (pid_t)seed_identity_call(121, process, 0, 0); }
int setpgid(pid_t process, pid_t group) { return (int)seed_identity_call(109, process, group, 0); }
pid_t setsid(void) { return (pid_t)seed_identity_call(112, 0, 0, 0); }
pid_t getsid(pid_t process) { return (pid_t)seed_identity_call(124, process, 0, 0); }

/* IDs travel as unsigned 32-bit values; (uid_t)-1 means "unchanged" where
   the kernel allows it. */
int setuid(uid_t user) { return (int)seed_identity_call(105, (long)user, 0, 0); }
int setgid(gid_t group) { return (int)seed_identity_call(106, (long)group, 0, 0); }
int setreuid(uid_t real, uid_t effective)
{
    return (int)seed_identity_call(113, (long)real, (long)effective, 0);
}
int setregid(gid_t real, gid_t effective)
{
    return (int)seed_identity_call(114, (long)real, (long)effective, 0);
}

/* As glibc: change only the effective ID with setresuid/setresgid. */
int seteuid(uid_t user)
{
    if (user == (uid_t)-1) { errno = EINVAL; return -1; }
    return (int)seed_identity_call(117, (long)(uid_t)-1, (long)user, (long)(uid_t)-1);
}
int setegid(gid_t group)
{
    if (group == (gid_t)-1) { errno = EINVAL; return -1; }
    return (int)seed_identity_call(119, (long)(gid_t)-1, (long)group, (long)(gid_t)-1);
}

int getgroups(int size, gid_t list[])
{
    return (int)seed_identity_call(115, size, (long)list, 0);
}
