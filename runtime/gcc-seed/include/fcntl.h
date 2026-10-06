#ifndef SEED_GCC_FCNTL_H
#define SEED_GCC_FCNTL_H
#include <sys/types.h>
/* Bounded Linux AMD64 open flags; see ../DESCRIPTOR-IO.md. Unsupported flag
   bits fail with EINVAL. O_CREAT or the full O_TMPFILE requires a mode_t
   argument (unsigned int on this target); other calls need no third argument.
   fcntl supports only the commands below; see ../FCNTL.md. */
#define O_ACCMODE 3
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 64
#define O_EXCL 128
#define O_NOCTTY 256
#define O_TRUNC 512
#define O_APPEND 1024
#define O_NONBLOCK 2048
#define O_NDELAY O_NONBLOCK
#define O_DSYNC 4096
#define O_ASYNC 8192
#define FASYNC O_ASYNC
#define O_DIRECT 16384
/* Every open is large-file capable on LP64 Linux. */
#define O_LARGEFILE 0
#define O_DIRECTORY 65536
#define O_NOFOLLOW 131072
#define O_NOATIME 262144
#define O_CLOEXEC 524288
#define O_SYNC 1052672
#define O_RSYNC O_SYNC
#define O_PATH 2097152
#define O_TMPFILE 4259840
#define F_DUPFD 0
#define F_GETFD 1
#define F_SETFD 2
#define F_GETFL 3
#define F_SETFL 4
#define F_DUPFD_CLOEXEC 1030
#define FD_CLOEXEC 1
int open(const char *path, int flags, ...);
/* F_DUPFD, F_DUPFD_CLOEXEC, F_SETFD and F_SETFL read one int argument;
   F_GETFD and F_GETFL read none. Other commands fail with EINVAL. */
int fcntl(int descriptor, int command, ...);
/* open(PATH, O_WRONLY | O_CREAT | O_TRUNC, MODE); see ../FILE-CALLS.md. */
int creat(const char *path, mode_t mode);
#endif
