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
/* d_type values: the file-type bits of st_mode shifted right by 12. A file
   system may report DT_UNKNOWN, after which the caller must use lstat. */
#define DT_UNKNOWN 0
#define DT_FIFO 1
#define DT_CHR 2
#define DT_DIR 4
#define DT_BLK 6
#define DT_REG 8
#define DT_LNK 10
#define DT_SOCK 12
#define DT_WHT 14
#define IFTODT(mode) (((mode) & 0170000) >> 12)
#define DTTOIF(type) ((type) << 12)
typedef struct seed_directory DIR;
DIR *opendir(const char *path);
struct dirent *readdir(DIR *directory);
int closedir(DIR *directory);
/* Restarts the stream from the first entry; see ../DIRECTORIES.md. */
void rewinddir(DIR *directory);
/* The descriptor the stream reads; closedir closes it. */
int dirfd(DIR *directory);
#endif
