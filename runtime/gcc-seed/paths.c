/* Original seed-forth implementation; see LICENSE and DRIVER-RUNTIME.md.
   Linux AMD64 working-directory and name operations used by GCC's driver. */
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <seed-syscall.h>

/* One raw call: kernel errors in [-4095, -1] become errno and -1. */
static int seed_path_call(long number, const char *first, const char *second)
{
    long result = __seed_syscall6(number, (long)first, (long)second, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return 0;
}

int chdir(const char *path)
{
    return seed_path_call(80, path, 0);
}

int link(const char *existing, const char *name)
{
    /* Hard link only; no symlink following flag (linkat) is exposed. */
    return seed_path_call(86, existing, name);
}

int rename(const char *old, const char *new)
{
    /* The kernel replaces an existing target atomically; no link/unlink
       emulation, so a crash never leaves both or neither name. */
    return seed_path_call(82, old, new);
}
