/* Shared observable contract; host libc is an independent oracle. */
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#ifdef DIRECTORY_INTEROP
extern char *tested_getcwd(char *, size_t);
#define getcwd tested_getcwd
#endif

int main(int argc, char **argv)
{
    char bytes[8194];
    char *result;
    size_t length;
    size_t size;
    int index;
    if (argc != 3) return 10;
    memset(bytes, 85, sizeof(bytes));
    if (strcmp(argv[1], "deleted") == 0 || strcmp(argv[1], "long") == 0) {
        errno = 97;
        result = getcwd(bytes + 1, 8192);
#ifdef DIRECTORY_LIBC
        if (strcmp(argv[1], "long") == 0) {
            if (result != bytes + 1 || strcmp(result, argv[2]) != 0) return 11;
            puts("libc long-path fallback passed");
            return 0;
        }
#endif
        if (result != NULL) return 12;
        if (errno != (strcmp(argv[1], "deleted") == 0 ? ENOENT : ENAMETOOLONG)) return 13;
        for (index = 0; index < 8194; index++) if (bytes[index] != 85) return 14;
        puts("rejected cwd storage preserved");
        return 0;
    }
    length = strlen(argv[2]);
    for (size = 0; size <= length + 2; size++) {
        memset(bytes, 85, sizeof(bytes));
        errno = 97;
        result = getcwd(bytes + 1, size);
        if (size <= length) {
            if (result != NULL || errno != (size == 0 ? EINVAL : ERANGE)) return 15;
            for (index = 0; index < 8194; index++) if (bytes[index] != 85) return 16;
        } else {
            if (result != bytes + 1 || errno != 97 || strcmp(result, argv[2]) != 0) return 17;
            if (bytes[0] != 85 || bytes[length + 2] != 85) return 18;
        }
    }
#ifndef DIRECTORY_LIBC
    errno = 97;
    if (getcwd(NULL, 0) != NULL || errno != EINVAL) return 19;
    errno = 97;
    if (getcwd(NULL, 8192) != NULL || errno != EINVAL) return 20;
#endif
    puts("caller cwd contract passed");
    return 0;
}
