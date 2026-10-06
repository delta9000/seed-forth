/* Original seed-forth fixture, also compiled against independent host headers. */
#include <stddef.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>

#define TYPE_INFO(type) printf(#type " %lu %d\n", (unsigned long)sizeof(type), (type)-1 < (type)0)
#define OFFSET(member) printf(#member " %lu\n", (unsigned long)offsetof(struct stat, member))
struct stat_alignment { char prefix; struct stat value; };

int main(int argc, char **argv)
{
    struct stat status;
    TYPE_INFO(size_t);
    TYPE_INFO(ssize_t);
    TYPE_INFO(off_t);
    TYPE_INFO(time_t);
    TYPE_INFO(blksize_t);
    TYPE_INFO(blkcnt_t);
    TYPE_INFO(dev_t);
    TYPE_INFO(ino_t);
    TYPE_INFO(nlink_t);
    TYPE_INFO(mode_t);
    TYPE_INFO(uid_t);
    TYPE_INFO(gid_t);
    TYPE_INFO(pid_t);
    printf("stat %lu %lu\n", (unsigned long)sizeof(struct stat),
           (unsigned long)offsetof(struct stat_alignment, value));
    OFFSET(st_dev);
    OFFSET(st_ino);
    OFFSET(st_nlink);
    OFFSET(st_mode);
    OFFSET(st_uid);
    OFFSET(st_gid);
    OFFSET(st_rdev);
    OFFSET(st_size);
    OFFSET(st_blksize);
    OFFSET(st_blocks);
    OFFSET(st_atime);
    OFFSET(st_mtime);
    OFFSET(st_ctime);
#ifdef __SEED_FORTH__
    printf("nanoseconds %lu %lu %lu\n",
           (unsigned long)offsetof(struct stat, st_atime_nsec),
           (unsigned long)offsetof(struct stat, st_mtime_nsec),
           (unsigned long)offsetof(struct stat, st_ctime_nsec));
#else
    printf("nanoseconds %lu %lu %lu\n",
           (unsigned long)offsetof(struct stat, st_atim.tv_nsec),
           (unsigned long)offsetof(struct stat, st_mtim.tv_nsec),
           (unsigned long)offsetof(struct stat, st_ctim.tv_nsec));
#endif
    printf("modes %u %u %u %u %u %u %u %u\n", S_IFMT, S_IFSOCK,
           S_IFLNK, S_IFREG, S_IFBLK, S_IFDIR, S_IFCHR, S_IFIFO);
    if (argc != 2 || stat(argv[1], &status)) return 1;
    printf("file %lu %lu %lu %u %u %u %lu %ld %ld %ld %ld %ld %ld\n",
           (unsigned long)status.st_dev, (unsigned long)status.st_ino,
           (unsigned long)status.st_nlink, status.st_mode, status.st_uid,
           status.st_gid, (unsigned long)status.st_rdev, (long)status.st_size,
           (long)status.st_blksize, (long)status.st_blocks,
           (long)status.st_atime, (long)status.st_mtime, (long)status.st_ctime);
#ifdef __SEED_FORTH__
    printf("file-ns %lu %lu %lu\n", status.st_atime_nsec,
           status.st_mtime_nsec, status.st_ctime_nsec);
#else
    printf("file-ns %lu %lu %lu\n", (unsigned long)status.st_atim.tv_nsec,
           (unsigned long)status.st_mtim.tv_nsec, (unsigned long)status.st_ctim.tv_nsec);
#endif
    /* The test links the raw entry, which exits without C exit's flush. */
    return fflush(stdout) != 0;
}
