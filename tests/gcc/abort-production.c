#include <stdlib.h>
#include <seed-syscall.h>

int main(int argc, char **argv)
{
    unsigned long mask = 32;
    unsigned long action[4];
    if (argc > 1 && argv[1][0] == 'b')
        if (__seed_syscall6(14, 0, (long)&mask, 0, 8, 0, 0) != 0)
            return 90;
    if (argc > 1 && argv[1][0] == 'i') {
        action[0] = 1;
        action[1] = 0;
        action[2] = 0;
        action[3] = 0;
        if (__seed_syscall6(13, 6, (long)action, 0, 8, 0, 0) != 0)
            return 91;
    }
    __seed_syscall6(1, 1, (long)"before abort\n", 13, 0, 0, 0);
    abort();
    __seed_syscall6(1, 1, (long)"returned\n", 9, 0, 0, 0);
    return 92;
}
