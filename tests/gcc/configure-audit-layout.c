/* Independent observations for a frozen original-GCC configure audit. */
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>

struct audit_short { char prefix; short value; };
struct audit_int { char prefix; int value; };
struct audit_long { char prefix; long value; };
struct audit_long_long { char prefix; long long value; };
struct audit_pointer { char prefix; void *value; };
struct audit_stat { char prefix; struct stat value; };

int main(void)
{
    unsigned long word = 1;
    unsigned char *bytes = (unsigned char *)&word;
#if defined(__GNUC__) || defined(__STDC_VERSION__) || defined(__cplusplus)
    return 91;
#else
    if (__STDC__ != 1 || __STDC_HOSTED__ != 0 || __SEED_FORTH__ != 1)
        return 92;
    if (__linux__ != 1 || __x86_64__ != 1 || __LP64__ != 1)
        return 93;
#endif
    printf("sizes %lu %lu %lu %lu %lu %lu\n", (unsigned long)sizeof(char),
           (unsigned long)sizeof(short), (unsigned long)sizeof(int),
           (unsigned long)sizeof(long), (unsigned long)sizeof(long long),
           (unsigned long)sizeof(void *));
    printf("alignments %lu %lu %lu %lu %lu\n",
           (unsigned long)offsetof(struct audit_short, value),
           (unsigned long)offsetof(struct audit_int, value),
           (unsigned long)offsetof(struct audit_long, value),
           (unsigned long)offsetof(struct audit_long_long, value),
           (unsigned long)offsetof(struct audit_pointer, value));
    printf("bytes %d %d %d %d\n", CHAR_BIT, (char)-1 < 0,
           bytes[0], bytes[sizeof(word) - 1]);
    printf("stat %lu %lu %lu %lu %lu\n", (unsigned long)sizeof(struct stat),
           (unsigned long)offsetof(struct audit_stat, value),
           (unsigned long)offsetof(struct stat, st_mode),
           (unsigned long)offsetof(struct stat, st_size),
           (unsigned long)offsetof(struct stat, st_atime));
    printf("types %lu %d %lu %d %lu %d\n", (unsigned long)sizeof(gid_t),
           (gid_t)-1 < (gid_t)0, (unsigned long)sizeof(ssize_t),
           (ssize_t)-1 < (ssize_t)0, (unsigned long)sizeof(pid_t),
           (pid_t)-1 < (pid_t)0);
    return 0;
}
