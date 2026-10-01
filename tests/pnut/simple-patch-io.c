/* Test-only host wrappers. Never compiled or run on the bootstrap path. */
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
extern int output_fd;

ssize_t test_read(int fd, void *buffer, size_t size) {
    char *mode = getenv("SIMPLE_PATCH_TEST_IO");
    if (mode && strcmp(mode, "read-error") == 0) {
        errno = EIO;
        return -1;
    }
    if (mode && strcmp(mode, "short") == 0 && size > 3) size = 3;
    return read(fd, buffer, size);
}

ssize_t test_write(int fd, const void *buffer, size_t size) {
    char *mode = getenv("SIMPLE_PATCH_TEST_IO");
    if (mode && strcmp(mode, "zero-write") == 0) return 0;
    if (mode && strcmp(mode, "short") == 0 && size > 3) size = 3;
    return write(fd, buffer, size);
}

int test_close(int fd) {
    int result = close(fd);
    char *mode = getenv("SIMPLE_PATCH_TEST_IO");
    if (mode && strcmp(mode, "close-error") == 0 && fd == output_fd) {
        errno = EIO;
        return -1;
    }
    return result;
}

#define read test_read
#define write test_write
#define close test_close
#include "../../tools/simple-patch.c"
