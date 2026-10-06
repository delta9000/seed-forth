/* Original seed-forth implementation; see LICENSE and FILE-CALLS.md.
   realpath: resolve every component, following symbolic links, without
   the kernel's /proc help. Each component must exist. */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <sys/stat.h>
#include <errno.h>

#define SEED_SYMLINK_LIMIT 40

char *realpath(const char *path, char *resolved)
{
    char result[PATH_MAX];
    char pending[2 * PATH_MAX];
    char target[PATH_MAX];
    char *cursor, *start, *copy;
    size_t used, length, rest;
    ssize_t count;
    int links = 0;
    struct stat status;
    if (path == NULL) { errno = EINVAL; return NULL; }
    if (*path == '\0') { errno = ENOENT; return NULL; }
    length = strlen(path);
    if (length >= sizeof(pending)) { errno = ENAMETOOLONG; return NULL; }
    memcpy(pending, path, length + 1);
    if (path[0] == '/') {
        result[0] = '\0';
    } else if (getcwd(result, sizeof(result)) == NULL) {
        return NULL;
    }
    if (strcmp(result, "/") == 0) result[0] = '\0';
    used = strlen(result);
    cursor = pending;
    for (;;) {
        while (*cursor == '/') cursor++;
        if (*cursor == '\0') break;
        start = cursor;
        while (*cursor && *cursor != '/') cursor++;
        length = (size_t)(cursor - start);
        if (length == 1 && start[0] == '.') continue;
        if (length == 2 && start[0] == '.' && start[1] == '.') {
            while (used > 0 && result[used - 1] != '/') used--;
            if (used > 0) used--;
            result[used] = '\0';
            continue;
        }
        if (used + 1 + length >= sizeof(result)) { errno = ENAMETOOLONG; return NULL; }
        result[used] = '/';
        memcpy(result + used + 1, start, length);
        result[used + 1 + length] = '\0';
        if (lstat(result, &status) < 0) return NULL;
        if (S_ISLNK(status.st_mode)) {
            if (++links > SEED_SYMLINK_LIMIT) { errno = ELOOP; return NULL; }
            count = readlink(result, target, sizeof(target));
            if (count < 0) return NULL;
            if ((size_t)count >= sizeof(target)) { errno = ENAMETOOLONG; return NULL; }
            /* New pending text: the link target, then the unread rest. */
            rest = strlen(cursor);
            if ((size_t)count + rest >= sizeof(pending)) { errno = ENAMETOOLONG; return NULL; }
            memmove(pending + count, cursor, rest + 1);
            memcpy(pending, target, (size_t)count);
            cursor = pending;
            if (count > 0 && target[0] == '/') {
                used = 0;
            }
            /* A relative target is read from the link's own directory. */
            result[used] = '\0';
            continue;
        }
        used += 1 + length;
        /* Further components (or a trailing slash) need a directory. */
        if (*cursor == '/' && !S_ISDIR(status.st_mode)) { errno = ENOTDIR; return NULL; }
    }
    if (used == 0) {
        result[0] = '/';
        result[1] = '\0';
        used = 1;
    }
    if (resolved == NULL) {
        copy = malloc(used + 1);
        if (copy == NULL) return NULL;
        resolved = copy;
    }
    memcpy(resolved, result, used + 1);
    return resolved;
}
