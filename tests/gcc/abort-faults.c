/* Host-only syscall double; real production paths use the Forth bridge. */
#include <unistd.h>
#include <stdlib.h>

void seed_abort(void);
static int step;
long __seed_syscall6(long number, long a1, long a2, long a3,
                     long a4, long a5, long a6)
{
    unsigned long *words;
    int valid = 0;
    if (a5 || a6) _exit(85);
    if (step == 0) valid = number == 39 && !a1 && !a2 && !a3 && !a4;
    if (step == 1) valid = number == 186 && !a1 && !a2 && !a3 && !a4;
    if (step == 2 || step == 5) {
        words = (unsigned long *)a2;
        valid = number == 14 && a1 == 1 && a2 && !a3 && a4 == 8 && *words == 32;
    }
    if (step == 3 || step == 6)
        valid = number == 234 && a1 == 101 && a2 == 103 && a3 == 6 && !a4;
    if (step == 4) {
        words = (unsigned long *)a2;
        valid = number == 13 && a1 == 6 && a2 && !a3 && a4 == 8 &&
                !words[0] && !words[1] && !words[2] && !words[3];
    }
    if (step == 7) {
        if (number == 60 && a1 == 134 && !a2 && !a3 && !a4)
            _exit(134);
        _exit(86);
    }
    if (!valid) _exit(87);
    step++;
    if (number == 39) return 101;
    if (number == 186) return 103;
    return -1;
}
int main(void) { seed_abort(); return 88; }
