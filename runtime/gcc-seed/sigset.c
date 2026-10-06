/* Original seed-forth implementation; see LICENSE and SIGNALS.md.
   Signal-set operations on the 1..64 kernel range. */
#include <signal.h>
#include <errno.h>

static int seed_signal_valid(int number)
{
    if (number <= 0 || number >= NSIG) {
        errno = EINVAL;
        return 0;
    }
    return 1;
}

int sigemptyset(sigset_t *set)
{
    int index;
    for (index = 0; index < 16; index++) set->__seed_bits[index] = 0;
    return 0;
}

int sigfillset(sigset_t *set)
{
    int index;
    for (index = 0; index < 16; index++) set->__seed_bits[index] = 0;
    set->__seed_bits[0] = ~0UL;
    return 0;
}

int sigaddset(sigset_t *set, int number)
{
    if (!seed_signal_valid(number)) return -1;
    set->__seed_bits[0] |= 1UL << (number - 1);
    return 0;
}

int sigdelset(sigset_t *set, int number)
{
    if (!seed_signal_valid(number)) return -1;
    set->__seed_bits[0] &= ~(1UL << (number - 1));
    return 0;
}

int sigismember(const sigset_t *set, int number)
{
    if (!seed_signal_valid(number)) return -1;
    return (set->__seed_bits[0] >> (number - 1)) & 1UL ? 1 : 0;
}
