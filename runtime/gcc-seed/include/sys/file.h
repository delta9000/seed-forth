#ifndef SEED_GCC_SYS_FILE_H
#define SEED_GCC_SYS_FILE_H
/* Original seed-forth interface; see LICENSE and ../../FILE-CALLS.md.
   BSD whole-file advisory locks (Linux flock, syscall 73). */
#include <fcntl.h>
#define LOCK_SH 1
#define LOCK_EX 2
#define LOCK_NB 4
#define LOCK_UN 8
/* Old lseek whence names. */
#define L_SET 0
#define L_INCR 1
#define L_XTND 2
int flock(int descriptor, int operation);
#endif
