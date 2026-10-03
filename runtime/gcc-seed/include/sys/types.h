#ifndef SEED_GCC_SYS_TYPES_H
#define SEED_GCC_SYS_TYPES_H
/* Original seed-forth ABI declarations; see LICENSE and ../../CONFIGURE.md.
   Linux AMD64 LP64 only. These types do not imply other POSIX interfaces. */
#include <stddef.h>
typedef long ssize_t;
typedef long off_t;
typedef long time_t;
typedef long blksize_t;
typedef long blkcnt_t;
typedef unsigned long dev_t;
typedef unsigned long ino_t;
typedef unsigned long nlink_t;
typedef unsigned int mode_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
typedef int pid_t;
#endif
