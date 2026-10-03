#ifndef SEED_GCC_SYS_STAT_H
#define SEED_GCC_SYS_STAT_H
/* Original seed-forth declarations; see LICENSE and ../../CONFIGURE.md.
   Field widths, offsets and padding match the Linux AMD64 stat syscall ABI.
   Signed seconds expose pre-epoch times; kernel words have identical bits.
   The nanosecond names below are seed extensions, not struct timespec. */
#include <sys/types.h>
struct stat {
    dev_t st_dev;
    ino_t st_ino;
    nlink_t st_nlink;
    mode_t st_mode;
    uid_t st_uid;
    gid_t st_gid;
    unsigned int __seed_stat_pad;
    dev_t st_rdev;
    off_t st_size;
    blksize_t st_blksize;
    blkcnt_t st_blocks;
    time_t st_atime;
    unsigned long st_atime_nsec;
    time_t st_mtime;
    unsigned long st_mtime_nsec;
    time_t st_ctime;
    unsigned long st_ctime_nsec;
    long __seed_stat_reserved[3];
};
#define S_IFMT 0170000
#define S_IFSOCK 0140000
#define S_IFLNK 0120000
#define S_IFREG 0100000
#define S_IFBLK 0060000
#define S_IFDIR 0040000
#define S_IFCHR 0020000
#define S_IFIFO 0010000
#define S_ISREG(mode) (((mode) & S_IFMT) == S_IFREG)
#define S_ISDIR(mode) (((mode) & S_IFMT) == S_IFDIR)
#define S_ISCHR(mode) (((mode) & S_IFMT) == S_IFCHR)
#define S_ISBLK(mode) (((mode) & S_IFMT) == S_IFBLK)
#define S_ISFIFO(mode) (((mode) & S_IFMT) == S_IFIFO)
#define S_ISLNK(mode) (((mode) & S_IFMT) == S_IFLNK)
#define S_ISSOCK(mode) (((mode) & S_IFMT) == S_IFSOCK)
int stat(const char *path, struct stat *status);
int fstat(int descriptor, struct stat *status);
#endif
