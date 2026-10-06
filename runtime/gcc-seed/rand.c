/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md.
   The additive lagged-Fibonacci generator r[i] = r[i-3] + r[i-31] that
   glibc's random() uses (degree 31), seeded by the same Lehmer sequence,
   so a given seed yields glibc's sequence. rand and random share it. */
#include <stdlib.h>

static unsigned int seed_state[34];
static int seed_front;
static int seed_ready;

void srandom(unsigned int seed)
{
    int index;
    long word;
    if (seed == 0) seed = 1;
    seed_state[0] = seed;
    for (index = 1; index < 31; index++) {
        /* 16807 * previous mod (2^31 - 1), by Schrage's method. */
        word = (long)(int)seed_state[index - 1];
        word = 16807 * (word % 127773) - 2836 * (word / 127773);
        if (word < 0) word += 2147483647;
        seed_state[index] = (unsigned int)word;
    }
    /* Ring of 34: entry i holds r[i]; discard the first 310 outputs. */
    for (index = 31; index < 34; index++) seed_state[index] = seed_state[index - 31];
    seed_front = 34;
    seed_ready = 1;
    for (index = 0; index < 310; index++) random();
}

long random(void)
{
    unsigned int value;
    if (!seed_ready) srandom(1);
    value = seed_state[(seed_front - 31) % 34] + seed_state[(seed_front - 3) % 34];
    seed_state[seed_front % 34] = value;
    seed_front++;
    if (seed_front >= 68) seed_front -= 34;
    return (long)(value >> 1);
}

void srand(unsigned int seed) { srandom(seed); }
int rand(void) { return (int)random(); }
