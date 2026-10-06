/* Original seed-forth implementation; see LICENSE and FILE-CALLS.md.
   Single Linux AMD64 file-system calls; kernel errors set errno. */
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <seed-syscall.h>

static long seed_file_call(long number, long a1, long a2, long a3)
{
    long result = __seed_syscall6(number, a1, a2, a3, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return result;
}

int symlink(const char *target, const char *path)
{
    return (int)seed_file_call(88, (long)target, (long)path, 0);
}

ssize_t readlink(const char *path, char *buffer, size_t size)
{
    return (ssize_t)seed_file_call(89, (long)path, (long)buffer, (long)size);
}

int fchdir(int descriptor) { return (int)seed_file_call(81, descriptor, 0, 0); }
int fchmod(int descriptor, mode_t mode) { return (int)seed_file_call(91, descriptor, (long)mode, 0); }

int fchown(int descriptor, uid_t owner, gid_t group)
{
    return (int)seed_file_call(93, descriptor, (long)owner, (long)group);
}

int lchown(const char *path, uid_t owner, gid_t group)
{
    return (int)seed_file_call(94, (long)path, (long)owner, (long)group);
}

int truncate(const char *path, off_t length)
{
    return (int)seed_file_call(76, (long)path, (long)length, 0);
}

int fsync(int descriptor) { return (int)seed_file_call(74, descriptor, 0, 0); }
int fdatasync(int descriptor) { return (int)seed_file_call(75, descriptor, 0, 0); }

int mknod(const char *path, mode_t mode, dev_t device)
{
    /* The kernel takes the 32-bit "new" encoding, which fits makedev's
       64-bit value for majors below 4096 and minors below 2^20. */
    return (int)seed_file_call(133, (long)path, (long)mode, (long)device);
}

int chroot(const char *path) { return (int)seed_file_call(161, (long)path, 0, 0); }

void sync(void)
{
    /* Linux sync always succeeds. */
    __seed_syscall6(162, 0, 0, 0, 0, 0, 0);
}
