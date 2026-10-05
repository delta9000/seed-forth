/* Host-only guard setup; provider is libc, host source, or a Forth object. */
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#ifdef DIRECTORY_INTEROP
extern char *tested_getcwd(char *, size_t);
#define getcwd tested_getcwd
#endif
int main(int argc, char **argv)
{
    long page = sysconf(_SC_PAGESIZE);
    size_t length;
    char *mapping;
    char *buffer;
    if (argc != 2 || page < 4096) return 10;
    length = strlen(argv[1]) + 1;
    mapping = mmap(NULL, page * 3, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED || mprotect(mapping + page, page, PROT_READ | PROT_WRITE)) return 11;
    buffer = mapping + 2 * page - length;
    memset(mapping + page, 85, page);
    errno = 97;
    if (getcwd(buffer, length) != buffer || strcmp(buffer, argv[1]) || errno != 97 || buffer[-1] != 85) return 12;
    memset(mapping + page, 85, page);
    if (getcwd(buffer + 1, length - 1) != NULL || errno != ERANGE || buffer[0] != 85) return 13;
    buffer = mapping + page;
    if (getcwd(buffer, length) != buffer || strcmp(buffer, argv[1]) || buffer[length] != 85) return 14;
    if (mprotect(mapping + page, page, PROT_READ)) return 15;
    if (getcwd(buffer, length) != NULL || errno != EFAULT) return 16;
    if (getcwd(mapping, length) != NULL || errno != EFAULT) return 17;
    if (getcwd((char *)1, length) != NULL || errno != EFAULT) return 18;
    if (munmap(mapping, page * 3)) return 19;
    puts("cwd guarded storage passed");
    return 0;
}
