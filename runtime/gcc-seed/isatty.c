/* Original seed-forth implementation; see LICENSE. Linux AMD64 TCGETS. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>
struct seed_kernel_termios {
    unsigned int input_flags;
    unsigned int output_flags;
    unsigned int control_flags;
    unsigned int local_flags;
    unsigned char line;
    unsigned char characters[19];
};
int isatty(int descriptor)
{
    struct seed_kernel_termios terminal;
    long result = __seed_syscall6(16,descriptor,0x5401,(long)&terminal,0,0,0);
    if (result < 0) { errno = (int)-result; return 0; }
    return result == 0;
}
