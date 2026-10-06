/* Original seed-forth implementation; see LICENSE and DIRECTORIES.md. */
#include <dirent.h>
#include <errno.h>
#include <seed-directory.h>

int dirfd(DIR *directory)
{
    if (directory == NULL) { errno = EINVAL; return -1; }
    return directory->descriptor;
}
