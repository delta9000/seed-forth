#ifndef SEED_GCC_SYSCALL_H
#define SEED_GCC_SYSCALL_H
/* Raw Linux AMD64 result: -4095 through -1 encode errno values. */
long __seed_syscall6(long number, long a1, long a2, long a3,
                     long a4, long a5, long a6);
#endif
