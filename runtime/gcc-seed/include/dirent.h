#ifndef SEED_GCC_DIRENT_H
#define SEED_GCC_DIRENT_H
#include <sys/types.h>
/* Linux AMD64 getdents64 layout. d_name is a variable-length NUL-terminated
   tail, not a limit of one character; never copy using sizeof(struct dirent).
   The pointer remains valid until the next readdir or closedir on this DIR. */
struct dirent {
    ino_t d_ino;
    off_t d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[1];
};
typedef struct seed_directory DIR;
DIR *opendir(const char *path);
struct dirent *readdir(DIR *directory);
int closedir(DIR *directory);
#endif
