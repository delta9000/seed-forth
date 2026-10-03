/* Original seed-forth implementation; see LICENSE. */
#include <stdlib.h>

int abs(int value)
{
    /* C requires the mathematical result to be representable as int.
       INT_MIN is outside that domain; this does not extend its semantics. */
    return value < 0 ? -value : value;
}
