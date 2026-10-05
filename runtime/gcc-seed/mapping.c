/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <sys/mman.h>
#include <errno.h>
#include <seed-syscall.h>

void *mmap(void *address, size_t length, int protection, int flags,
           int descriptor, off_t offset)
{
    long result;
    /* A hint never replaces an existing mapping. Reject every unsupported
       flag, including MAP_FIXED, before entering the kernel. */
    if ((protection & ~(PROT_READ | PROT_WRITE)) != 0 ||
        (flags != MAP_PRIVATE && flags != (MAP_PRIVATE | MAP_ANONYMOUS)) ||
        offset < 0 || (offset & 4095) != 0) {
        errno = EINVAL;
        return MAP_FAILED;
    }
    /* Linux validates and page-rounds the full unsigned length. LP64 casts
       preserve every argument bit; off_t is signed and already validated. */
    result = __seed_syscall6(9, (long)address, (long)length,
                             (long)protection, (long)flags,
                             (long)descriptor, (long)offset);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return MAP_FAILED;
    }
    return (void *)result;
}

int munmap(void *address, size_t length)
{
    long result = __seed_syscall6(11, (long)address, (long)length, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (int)result;
}
