/* Original seed-forth implementation; see LICENSE and TERMIOS.md.
   Terminal attributes and control over Linux AMD64 tty ioctls. */
#include <termios.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <seed-syscall.h>

/* The kernel's TCGETS/TCSETS record: 19 control characters. */
#define SEED_KERNEL_NCCS 19
struct seed_kernel_termios {
    tcflag_t c_iflag;
    tcflag_t c_oflag;
    tcflag_t c_cflag;
    tcflag_t c_lflag;
    cc_t c_line;
    cc_t c_cc[SEED_KERNEL_NCCS];
};

static int seed_tty_call(int descriptor, unsigned long request, long argument)
{
    long result = __seed_syscall6(16, descriptor, (long)request, argument, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (int)result;
}

int tcgetattr(int descriptor, struct termios *attributes)
{
    struct seed_kernel_termios kernel;
    if (seed_tty_call(descriptor, TCGETS, (long)&kernel) < 0) return -1;
    attributes->c_iflag = kernel.c_iflag;
    attributes->c_oflag = kernel.c_oflag;
    attributes->c_cflag = kernel.c_cflag;
    attributes->c_lflag = kernel.c_lflag;
    attributes->c_line = kernel.c_line;
    memcpy(attributes->c_cc, kernel.c_cc, SEED_KERNEL_NCCS);
    memset(attributes->c_cc + SEED_KERNEL_NCCS, _POSIX_VDISABLE, NCCS - SEED_KERNEL_NCCS);
    attributes->c_ispeed = kernel.c_cflag & CBAUD;
    attributes->c_ospeed = kernel.c_cflag & CBAUD;
    return 0;
}

int tcsetattr(int descriptor, int action, const struct termios *attributes)
{
    struct seed_kernel_termios kernel;
    unsigned long request;
    switch (action) {
    case TCSANOW: request = TCSETS; break;
    case TCSADRAIN: request = TCSETSW; break;
    case TCSAFLUSH: request = TCSETSF; break;
    default:
        errno = EINVAL;
        return -1;
    }
    kernel.c_iflag = attributes->c_iflag;
    kernel.c_oflag = attributes->c_oflag;
    kernel.c_cflag = attributes->c_cflag;
    kernel.c_lflag = attributes->c_lflag;
    kernel.c_line = attributes->c_line;
    memcpy(kernel.c_cc, attributes->c_cc, SEED_KERNEL_NCCS);
    return seed_tty_call(descriptor, request, (long)&kernel) < 0 ? -1 : 0;
}

speed_t cfgetospeed(const struct termios *attributes)
{
    return attributes->c_cflag & CBAUD;
}

speed_t cfgetispeed(const struct termios *attributes)
{
    return cfgetospeed(attributes);
}

int cfsetospeed(struct termios *attributes, speed_t speed)
{
    if (speed & ~(speed_t)CBAUD) {
        errno = EINVAL;
        return -1;
    }
    attributes->c_cflag = (attributes->c_cflag & ~(tcflag_t)CBAUD) | speed;
    attributes->c_ospeed = speed;
    attributes->c_ispeed = speed;
    return 0;
}

int cfsetispeed(struct termios *attributes, speed_t speed)
{
    return speed ? cfsetospeed(attributes, speed) : 0;
}

int cfsetspeed(struct termios *attributes, speed_t speed)
{
    return cfsetospeed(attributes, speed);
}

void cfmakeraw(struct termios *attributes)
{
    attributes->c_iflag &= ~(tcflag_t)(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    attributes->c_oflag &= ~(tcflag_t)OPOST;
    attributes->c_lflag &= ~(tcflag_t)(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    attributes->c_cflag &= ~(tcflag_t)(CSIZE | PARENB);
    attributes->c_cflag |= CS8;
    attributes->c_cc[VMIN] = 1;
    attributes->c_cc[VTIME] = 0;
}

int tcdrain(int descriptor) { return seed_tty_call(descriptor, TCSBRK, 1); }
int tcflow(int descriptor, int action) { return seed_tty_call(descriptor, TCXONC, action); }
int tcflush(int descriptor, int queue) { return seed_tty_call(descriptor, TCFLSH, queue); }

int tcsendbreak(int descriptor, int duration)
{
    /* Zero: the standard quarter to half second. Otherwise round the
       duration in milliseconds up to tenths of a second, as glibc. */
    if (duration <= 0) return seed_tty_call(descriptor, TCSBRK, 0);
    return seed_tty_call(descriptor, TCSBRKP, (duration + 99) / 100);
}

pid_t tcgetsid(int descriptor)
{
    pid_t session;
    if (seed_tty_call(descriptor, TIOCGSID, (long)&session) < 0) return -1;
    return session;
}

pid_t tcgetpgrp(int descriptor)
{
    pid_t group;
    if (seed_tty_call(descriptor, TIOCGPGRP, (long)&group) < 0) return -1;
    return group;
}

int tcsetpgrp(int descriptor, pid_t group)
{
    return seed_tty_call(descriptor, TIOCSPGRP, (long)&group) < 0 ? -1 : 0;
}
