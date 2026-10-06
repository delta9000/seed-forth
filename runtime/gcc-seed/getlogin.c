/* Original seed-forth implementation; see LICENSE and PASSWD.md.
   The login name of the session: the kernel's audit login uid mapped
   through /etc/passwd (glibc's first method; there is no utmp fallback). */
#include <unistd.h>
#include <pwd.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>

static char seed_login_name[256];

static int seed_getlogin(char *buffer, size_t size)
{
    char text[32];
    ssize_t count;
    unsigned long user = 0;
    int descriptor, index;
    struct passwd *entry;
    size_t length;
    descriptor = open("/proc/self/loginuid", O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) return errno;
    count = read(descriptor, text, sizeof(text) - 1);
    close(descriptor);
    if (count <= 0) return count < 0 ? errno : ENXIO;
    for (index = 0; index < count && text[index] >= '0' && text[index] <= '9'; index++)
        user = user * 10 + (unsigned long)(text[index] - '0');
    /* (uid_t)-1: no login session (a daemon or a container). */
    if (index == 0 || user >= 4294967295UL) return ENXIO;
    errno = 0;
    entry = getpwuid((uid_t)user);
    if (entry == NULL) return errno ? errno : ENOENT;
    length = strlen(entry->pw_name) + 1;
    if (length > size) return ERANGE;
    memcpy(buffer, entry->pw_name, length);
    return 0;
}

/* The error number is returned; errno is left as the caller had it. */
int getlogin_r(char *buffer, size_t size)
{
    int saved = errno;
    int error = seed_getlogin(buffer, size);
    errno = saved;
    return error;
}

char *getlogin(void)
{
    int saved = errno, error;
    error = getlogin_r(seed_login_name, sizeof(seed_login_name));
    if (error) {
        errno = error;
        return NULL;
    }
    errno = saved;
    return seed_login_name;
}
