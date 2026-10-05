/* Original seed-forth fixture, MIT license. Output is raw binary64 bits;
 * no floating formatting, host libm, tables, or expected results are used. */
#include <math.h>
#include <errno.h>
#include <stdio.h>
union sample_bits { unsigned long bits; double number; };
static void sample(int operation, double x, int count)
{
    union sample_bits input;
    union sample_bits output;
    double (*function)(double);
    int saved_errno;
    input.number = x;
    errno = 123;
    if (operation == 0) {
        function = log;
        output.number = function(x);
    } else if (operation == 1) {
        function = exp;
        output.number = function(x);
    } else output.number = exp(log(x) / count);
    saved_errno = errno;
    printf("%d %016lx %d %016lx %d\n", operation, input.bits, count,
           output.bits, saved_errno);
}
int main(void)
{
    union sample_bits x;
    unsigned long random;
    unsigned long fraction;
    unsigned long power;
    int exponent;
    int i;
    int j;
    int count;
    int divisors[6];
    double cycles[5];
    unsigned long special[18];
    special[0] = 0;
    special[1] = 0x8000000000000000UL;
    special[2] = 1;
    special[3] = 0x8000000000000001UL;
    special[4] = 0x000fffffffffffffUL;
    special[5] = 0x0010000000000000UL;
    special[6] = 0x3fefffffffffffffUL;
    special[7] = 0x3ff0000000000000UL;
    special[8] = 0x3ff0000000000001UL;
    special[9] = 0x7fefffffffffffffUL;
    special[10] = 0xffefffffffffffffUL;
    special[11] = 0x7ff0000000000000UL;
    special[12] = 0xfff0000000000000UL;
    special[13] = 0x7ff8000000012345UL;
    special[14] = 0xfff8000000012345UL;
    special[15] = 0x7ff0000000012345UL;
    special[16] = 0x40862e42fefa39efUL;
    special[17] = 0xc0874910d52d3052UL;
    for (i = 0; i < 18; i++) {
        x.bits = special[i];
        sample(0, x.number, 1);
        sample(1, x.number, 1);
    }
    /* Every binade: first, next, both sides of reduction at 1.5, last. */
    for (exponent = 0; exponent < 2047; exponent++) {
        for (i = 0; i < 5; i++) {
            fraction = 0;
            if (i == 1) fraction = 1;
            if (i == 2) fraction = 0x0007ffffffffffffUL;
            if (i == 3) fraction = 0x0008000000000000UL;
            if (i == 4) fraction = 0x000fffffffffffffUL;
            x.bits = ((unsigned long)exponent << 52) | fraction;
            sample(0, x.number, 1);
        }
    }
    /* Every subnormal power of two, with adjacent representable inputs. */
    for (exponent = 0; exponent < 52; exponent++) {
        x.bits = (1UL << exponent) - 1;
        for (i = 0; i < 3; i++) {
            sample(0, x.number, 1);
            x.bits++;
        }
    }
    /* Both sides of exp range reduction boundaries and exponent limits. */
    for (exponent = -1075; exponent <= 1024; exponent++) {
        x.number = (exponent + 0.5) * 0.69314718055994530942;
        x.bits--;
        for (i = 0; i < 3; i++) {
            sample(1, x.number, 1);
            x.bits++;
        }
    }
    for (i = 16; i < 18; i++) {
        x.bits = special[i] - 8;
        for (j = 0; j < 17; j++) {
            sample(1, x.number, 1);
            x.bits++;
        }
    }
    random = 0x90404;
    for (i = 0; i < 4096; i++) {
        random = random * 6364136223846793005UL + 1442695040888963407UL;
        x.bits = random & 0x7fefffffffffffffUL;
        sample(0, x.number, 1);
        x.number = (int)(random >> 32) / 2000000.0;
        sample(1, x.number, 1);
    }
    /* Exact integer perfect powers and adjacent integer cycle counts. */
    for (i = 2; i <= 128; i++) {
        power = i;
        for (count = 1; count <= 31; count++) {
            for (j = -1; j <= 1; j++) {
                x.number = (double)((long)power + j);
                sample(2, x.number, count);
            }
            if (power > 2147483647UL / i) break;
            power = power * i;
        }
    }
    /* Positive large automata counts and the full safe integer span. */
    divisors[0] = 2; divisors[1] = 31; divisors[2] = 127;
    divisors[3] = 1024; divisors[4] = 65535; divisors[5] = 2147483647;
    cycles[0] = 1.0; cycles[1] = 2.0; cycles[2] = 3.0;
    cycles[3] = 2147483647.0; cycles[4] = 2147483648.0;
    for (i = 0; i < 5; i++)
        for (j = 0; j < 6; j++) sample(2, cycles[i], divisors[j]);
    return 0;
}
