#ifndef SEED_GCC_FCNTL_H
#define SEED_GCC_FCNTL_H
/* Linux AMD64 flags/commands used by the source-built stream/tempfile code.
   No public open/fcntl wrapper is declared by this bounded header. */
#define O_ACCMODE 3
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 64
#define O_EXCL 128
#define O_TRUNC 512
#define O_APPEND 1024
#define F_GETFL 3
#define F_SETFL 4
#endif
