#ifndef SEED_GCC_ERRNO_H
#define SEED_GCC_ERRNO_H
/* Single-threaded errno storage is supplied by the Forth runtime object. */
int *__errno_location(void);
#define errno (*__errno_location())
/* Linux AMD64 error numbers used by this runtime and its first clients. */
#define EPERM 1
#define ENOENT 2
#define EINTR 4
#define EIO 5
#define EBADF 9
#define EAGAIN 11
#define ENOMEM 12
#define EACCES 13
#define EFAULT 14
#define EEXIST 17
#define EINVAL 22
#define ENFILE 23
#define EMFILE 24
#define ENOSPC 28
#define EPIPE 32
#define EDOM 33
#define ERANGE 34
#define ENOSYS 38
#define EOVERFLOW 75
#endif
