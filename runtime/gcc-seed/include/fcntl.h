#ifndef SEED_GCC_FCNTL_H
#define SEED_GCC_FCNTL_H
#include <sys/types.h>
/* Bounded Linux AMD64 open flags; see ../DESCRIPTOR-IO.md. Unsupported flag
   bits fail with EINVAL. O_CREAT or the full O_TMPFILE requires a mode_t
   argument (unsigned int on this target); other calls need no third argument.
   fcntl commands remain constants only: no public fcntl wrapper is supplied. */
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
#define O_DIRECTORY 65536
#define O_NOFOLLOW 131072
#define O_CLOEXEC 524288
#define O_PATH 2097152
#define O_TMPFILE 4259840
#define F_GETFL 3
#define F_SETFL 4
int open(const char *path, int flags, ...);
#endif
