/* POSIX terminal fixture: Forth runtime versus host glibc. Standard input
   is a pseudo-terminal that is the controlling terminal of a new session;
   standard output is a pipe. Speeds are compared symbolically because
   glibc 2.42 and later use numeric Bnnn values (and report the input speed
   in the CIBAUD bits, which are masked out of the printed c_cflag). */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>

#define CALL(label, expression) do { long value_; errno = 0; value_ = (long)(expression); int error_ = errno; \
    printf("%s %ld errno %d\n", label, value_, error_); } while (0)
#define SHOW(name) printf("%s %ld\n", #name, (long)(name))

static void show(const char *label, const struct termios *mode)
{
    int index;
    printf("%s iflag %o oflag %o cflag %o lflag %o line %d cc", label, (unsigned)mode->c_iflag,
           (unsigned)mode->c_oflag, (unsigned)(mode->c_cflag & ~(tcflag_t)CIBAUD), (unsigned)mode->c_lflag,
           mode->c_line);
    for (index = 0; index < NCCS; index++) printf(" %d", mode->c_cc[index]);
    printf("\n");
}

int main(void)
{
    struct termios original, mode;
    struct winsize size;
    char name[64], small[4], *path;
    setvbuf(stdout, NULL, _IONBF, 0);
    SHOW(NCCS); SHOW(VINTR); SHOW(VQUIT); SHOW(VERASE); SHOW(VKILL); SHOW(VEOF);
    SHOW(VTIME); SHOW(VMIN); SHOW(VSTART); SHOW(VSTOP); SHOW(VSUSP); SHOW(VEOL);
    SHOW(VREPRINT); SHOW(VDISCARD); SHOW(VWERASE); SHOW(VLNEXT); SHOW(VEOL2);
    SHOW(IGNBRK); SHOW(BRKINT); SHOW(IGNPAR); SHOW(PARMRK); SHOW(INPCK); SHOW(ISTRIP);
    SHOW(INLCR); SHOW(IGNCR); SHOW(ICRNL); SHOW(IUCLC); SHOW(IXON); SHOW(IXANY);
    SHOW(IXOFF); SHOW(IMAXBEL); SHOW(IUTF8); SHOW(OPOST); SHOW(OLCUC); SHOW(ONLCR);
    SHOW(OCRNL); SHOW(ONOCR); SHOW(ONLRET); SHOW(OFILL); SHOW(OFDEL); SHOW(NLDLY);
    SHOW(CRDLY); SHOW(TABDLY); SHOW(BSDLY); SHOW(VTDLY); SHOW(FFDLY); SHOW(CSIZE);
    SHOW(CS5); SHOW(CS6); SHOW(CS7); SHOW(CS8); SHOW(CSTOPB); SHOW(CREAD); SHOW(PARENB);
    SHOW(PARODD); SHOW(HUPCL); SHOW(CLOCAL); SHOW(CRTSCTS); SHOW(ISIG); SHOW(ICANON);
    SHOW(ECHO); SHOW(ECHOE); SHOW(ECHOK); SHOW(ECHONL); SHOW(NOFLSH); SHOW(TOSTOP);
    SHOW(ECHOCTL); SHOW(ECHOPRT); SHOW(ECHOKE); SHOW(FLUSHO); SHOW(PENDIN); SHOW(IEXTEN);
    SHOW(TCSANOW); SHOW(TCSADRAIN); SHOW(TCSAFLUSH); SHOW(TCIFLUSH); SHOW(TCOFLUSH);
    SHOW(TCIOFLUSH); SHOW(TCOOFF); SHOW(TCOON); SHOW(TCIOFF); SHOW(TCION);
    SHOW(TCGETS); SHOW(TCSETS); SHOW(TIOCGWINSZ); SHOW(TIOCSWINSZ); SHOW(TIOCGPGRP);
    SHOW(TIOCSPGRP); SHOW(FIONREAD); SHOW(TIOCSCTTY); SHOW(TIOCNOTTY);
    printf("sizes %lu %lu\n", (unsigned long)sizeof(struct winsize), (unsigned long)sizeof(cc_t));
    printf("isatty %d %d\n", isatty(0), isatty(1));
    CALL("tcgetattr", tcgetattr(0, &original));
    show("original", &original);
    printf("speed 38400 %d %d\n", cfgetospeed(&original) == B38400, cfgetispeed(&original) == B38400);
    mode = original;
    cfmakeraw(&mode);
    show("raw", &mode);
    CALL("tcsetattr now", tcsetattr(0, TCSANOW, &mode));
    CALL("tcgetattr raw", tcgetattr(0, &mode));
    show("applied", &mode);
    mode.c_lflag |= ECHO | ICANON;
    mode.c_cc[VMIN] = 3;
    CALL("tcsetattr drain", tcsetattr(0, TCSADRAIN, &mode));
    tcgetattr(0, &mode);
    show("drained", &mode);
    CALL("tcsetattr bad", tcsetattr(0, 7, &mode));
    CALL("cfsetospeed", cfsetospeed(&mode, B9600));
    CALL("cfsetispeed", cfsetispeed(&mode, B9600));
    printf("speed 9600 %d %d\n", cfgetospeed(&mode) == B9600, cfgetispeed(&mode) == B9600);
    CALL("tcsetattr flush", tcsetattr(0, TCSAFLUSH, &original));
    tcgetattr(0, &mode);
    printf("restored %d\n", memcmp(mode.c_cc, original.c_cc, NCCS) == 0
           && mode.c_lflag == original.c_lflag && mode.c_iflag == original.c_iflag);
    CALL("TIOCGWINSZ", ioctl(0, TIOCGWINSZ, &size));
    printf("window %d %d %d %d\n", size.ws_row, size.ws_col, size.ws_xpixel, size.ws_ypixel);
    size.ws_row = 40;
    CALL("TIOCSWINSZ", ioctl(0, TIOCSWINSZ, &size));
    ioctl(0, TIOCGWINSZ, &size);
    printf("window now %d %d\n", size.ws_row, size.ws_col);
    path = ttyname(0);
    printf("ttyname %d\n", path != NULL && strncmp(path, "/dev/pts/", 9) == 0);
    CALL("ttyname_r", ttyname_r(0, name, sizeof(name)));
    printf("same %d\n", path != NULL && strcmp(path, name) == 0);
    CALL("ttyname_r small", ttyname_r(0, small, sizeof(small)));
    errno = 0;
    path = ttyname(1);
    printf("ttyname pipe %d errno %d\n", path == NULL, errno);
    CALL("ttyname_r closed", ttyname_r(99, name, sizeof(name)));
    CALL("tcgetattr pipe", tcgetattr(1, &mode));
    CALL("tcgetattr closed", tcgetattr(99, &mode));
    printf("foreground %d\n", tcgetpgrp(0) == getpgrp());
    printf("session %d\n", tcgetsid(0) == getsid(0));
    CALL("tcsetpgrp", tcsetpgrp(0, getpgrp()));
    CALL("tcgetpgrp pipe", tcgetpgrp(1));
    CALL("tcflush", tcflush(0, TCIOFLUSH));
    CALL("tcflush bad", tcflush(0, 9));
    CALL("tcdrain", tcdrain(0));
    CALL("tcflow", tcflow(0, TCOON));
    CALL("tcsendbreak", tcsendbreak(0, 0));
#ifndef __GLIBC__
    if (cfsetospeed(&mode, 0x8000) != -1 || errno != EINVAL) puts("bad speed accepted");
    if (B9600 != 015 || B38400 != 017 || B115200 != 010002) puts("speed codes differ from Linux");
#endif
    puts("done");
    return 0;
}
