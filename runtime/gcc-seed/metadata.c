/* Original seed-forth implementation; see LICENSE and FILE-METADATA.md.
   Linux AMD64 file metadata calls used by original binutils 2.30. */
#include <sys/stat.h>
#include <unistd.h>
#include <utime.h>
#include <errno.h>
#include <seed-syscall.h>

/* One raw call: kernel errors in [-4095, -1] become errno and -1. */
static int seed_metadata_call(long number, long first, long second, long third)
{
    long result = __seed_syscall6(number, first, second, third, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return 0;
}

int lstat(const char *path, struct stat *status)
{
    return seed_metadata_call(6, (long)path, (long)status, 0);
}

int chmod(const char *path, mode_t mode)
{
    return seed_metadata_call(90, (long)path, (long)mode, 0);
}

int chown(const char *path, uid_t owner, gid_t group)
{
    /* The kernel takes 32-bit IDs; (uid_t)-1 means unchanged. */
    return seed_metadata_call(92, (long)path, (long)owner, (long)group);
}

int mkdir(const char *path, mode_t mode)
{
    return seed_metadata_call(83, (long)path, (long)mode, 0);
}

int rmdir(const char *path)
{
    return seed_metadata_call(84, (long)path, 0, 0);
}

int utime(const char *path, const struct utimbuf *times)
{
    /* struct utimbuf has the kernel's two-long layout. */
    return seed_metadata_call(132, (long)path, (long)times, 0);
}

mode_t umask(mode_t mask)
{
    /* Always succeeds; the kernel keeps only the 0777 permission bits. */
    return (mode_t)__seed_syscall6(95, (long)mask, 0, 0, 0, 0, 0);
}
