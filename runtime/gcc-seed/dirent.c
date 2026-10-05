/* Original seed-forth implementation; see LICENSE. Linux AMD64 only. */
#include <dirent.h>
#include <stdlib.h>
#include <errno.h>
#include <seed-syscall.h>

/* A long array gives every kernel record its required eight-byte alignment. */
struct seed_directory {
    int descriptor;
    int ended;
    unsigned long position;
    unsigned long available;
    long buffer[4096];
};

DIR *opendir(const char *path)
{
    DIR *directory;
    long descriptor;
    /* O_RDONLY | O_DIRECTORY | O_CLOEXEC: no regular-file descriptors and
       no descriptor inherited by exec. Raw syscalls do not modify errno. */
    do {
        descriptor = __seed_syscall6(2, (long)path, 0200000 | 02000000,
                                     0, 0, 0, 0);
    } while (descriptor == -EINTR);
    if (descriptor < 0) {
        errno = (int)-descriptor;
        return NULL;
    }
    directory = malloc(sizeof(DIR));
    if (directory == NULL) {
        __seed_syscall6(3, descriptor, 0, 0, 0, 0, 0);
        return NULL;
    }
    directory->descriptor = (int)descriptor;
    directory->ended = 0;
    directory->position = 0;
    directory->available = 0;
    return directory;
}

struct dirent *readdir(DIR *directory)
{
    long result;
    unsigned long remaining, length, index;
    unsigned char *record;
    if (directory == NULL) {
        errno = EBADF;
        return NULL;
    }
    if (directory->ended < 0) { errno = EIO; return NULL; }
    if (directory->ended) return NULL;
    if (directory->position == directory->available) {
        do {
            result = __seed_syscall6(217, directory->descriptor,
                        (long)directory->buffer, sizeof(directory->buffer),
                        0, 0, 0);
        } while (result == -EINTR);
        if (result < 0) { errno = (int)-result; return NULL; }
        if (result == 0) { directory->ended = 1; return NULL; }
        if ((unsigned long)result > sizeof(directory->buffer)) {
            directory->ended = -1; errno = EIO; return NULL;
        }
        directory->position = 0;
        directory->available = (unsigned long)result;
    }
    remaining = directory->available - directory->position;
    record = (unsigned char *)directory->buffer + directory->position;
    /* Header is 19 bytes; require a nonempty terminated name and padding
       to an eight-byte boundary. Read reclen bytes only after bounds check. */
    if (remaining < 24) {
        directory->ended = -1; errno = EIO; return NULL;
    }
    length = (unsigned long)record[16] + (unsigned long)record[17] * 256;
    if (length < 24 || length > remaining || length % 8 != 0) {
        directory->ended = -1; errno = EIO; return NULL;
    }
    index = 19;
    while (index < length && record[index] != 0) index++;
    if (index == 19 || index == length) {
        directory->ended = -1; errno = EIO; return NULL;
    }
    directory->position += length;
    return (struct dirent *)record;
}

int closedir(DIR *directory)
{
    long result;
    if (directory == NULL) { errno = EBADF; return -1; }
    /* Linux releases the descriptor even when close reports EINTR. Never
       retry and risk closing an unrelated descriptor reused by the caller. */
    result = __seed_syscall6(3, directory->descriptor, 0, 0, 0, 0, 0);
    free(directory);
    if (result < 0) { errno = (int)-result; return -1; }
    return 0;
}
