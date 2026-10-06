#ifndef SEED_GCC_SYS_STAT_H
#define SEED_GCC_SYS_STAT_H
/* Original seed-forth declarations; see LICENSE and ../../CONFIGURE.md.
   Field widths, offsets and padding match the Linux AMD64 stat syscall ABI.
   Signed seconds expose pre-epoch times; kernel words have identical bits.
   Times are POSIX struct timespec members; st_atime etc. name their seconds
   (as in glibc) and the older st_atime_nsec names remain as aliases. */
#include <sys/types.h>
#include <seed-timespec.h>
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
    struct timespec st_atim;
    struct timespec st_mtim;
    struct timespec st_ctim;
    long __seed_stat_reserved[3];
};
#define st_atime st_atim.tv_sec
#define st_mtime st_mtim.tv_sec
#define st_ctime st_ctim.tv_sec
#define st_atime_nsec st_atim.tv_nsec
#define st_mtime_nsec st_mtim.tv_nsec
#define st_ctime_nsec st_ctim.tv_nsec
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
/* Permission bits; see ../../FILE-METADATA.md. */
#define S_ISUID 04000
#define S_ISGID 02000
#define S_ISVTX 01000
#define S_IRWXU 00700
#define S_IRUSR 00400
#define S_IWUSR 00200
#define S_IXUSR 00100
#define S_IRWXG 00070
#define S_IRGRP 00040
#define S_IWGRP 00020
#define S_IXGRP 00010
#define S_IRWXO 00007
#define S_IROTH 00004
#define S_IWOTH 00002
#define S_IXOTH 00001
#define S_IREAD S_IRUSR
#define S_IWRITE S_IWUSR
#define S_IEXEC S_IXUSR
#define ACCESSPERMS 0777
#define ALLPERMS 07777
#define DEFFILEMODE 0666
int stat(const char *path, struct stat *status);
int fstat(int descriptor, struct stat *status);
/* Single Linux calls: lstat does not follow a final symbolic link; umask
   cannot fail and returns the previous mask. */
int lstat(const char *path, struct stat *status);
int chmod(const char *path, mode_t mode);
int mkdir(const char *path, mode_t mode);
mode_t umask(mode_t mask);
/* Single Linux calls; see ../../FILE-CALLS.md. mkfifo is mknod with
   S_IFIFO; mknod passes DEVICE in the 64-bit encoding of makedev. */
int fchmod(int descriptor, mode_t mode);
int mknod(const char *path, mode_t mode, dev_t device);
int mkfifo(const char *path, mode_t mode);
#endif
