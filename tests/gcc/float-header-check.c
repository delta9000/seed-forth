/* Original seed-forth regression fixture; see LICENSE. */
#include <float.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
struct fcell { char byte; float number; };
struct dcell { char byte; double number; };
struct lcell { char byte; long double number; };
int main(void)
{
    double values[3];
    unsigned long bits;
    values[0] = DBL_MIN; values[1] = DBL_MAX; values[2] = DBL_EPSILON;
    memcpy(&bits, &values[0], 8);
    if (bits != 0x0010000000000000UL) return 1;
    memcpy(&bits, &values[1], 8);
    if (bits != 0x7fefffffffffffffUL) return 2;
    memcpy(&bits, &values[2], 8);
    if (bits != 0x3cb0000000000000UL) return 3;
    printf("%d\n",FLT_RADIX);
    printf("%d %d %d %d %d %d\n",FLT_MANT_DIG,FLT_DIG,FLT_MIN_EXP,FLT_MIN_10_EXP,FLT_MAX_EXP,FLT_MAX_10_EXP);
    printf("%d %d %d %d %d %d\n",DBL_MANT_DIG,DBL_DIG,DBL_MIN_EXP,DBL_MIN_10_EXP,DBL_MAX_EXP,DBL_MAX_10_EXP);
    printf("%d %d %d %d %d %d\n",LDBL_MANT_DIG,LDBL_DIG,LDBL_MIN_EXP,LDBL_MIN_10_EXP,LDBL_MAX_EXP,LDBL_MAX_10_EXP);
    printf("%lu %lu %lu %lu %lu %lu %lu %lu %lu\n",
       (unsigned long)sizeof(float),(unsigned long)offsetof(struct fcell,number),(unsigned long)sizeof(struct fcell),
       (unsigned long)sizeof(double),(unsigned long)offsetof(struct dcell,number),(unsigned long)sizeof(struct dcell),
       (unsigned long)sizeof(long double),(unsigned long)offsetof(struct lcell,number),(unsigned long)sizeof(struct lcell));
#ifndef FLOAT_HOST_ORACLE
    if (FLT_ROUNDS != -1) return 4;
#endif
    return 0;
}
