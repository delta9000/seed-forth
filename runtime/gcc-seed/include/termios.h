#ifndef SEED_GCC_TERMIOS_H
#define SEED_GCC_TERMIOS_H
/* Original seed-forth interface; see LICENSE and ../TERMIOS.md.
   Linux AMD64 terminal attributes. struct termios has glibc's 60-byte
   layout; the runtime converts to the kernel's 36-byte TCGETS record.
   Speeds use the traditional Linux Bnnn codes (B9600 is 015), not the
   numeric speed_t of glibc 2.42 and later. */
#include <sys/types.h>
typedef unsigned char cc_t;
typedef unsigned int speed_t;
typedef unsigned int tcflag_t;
#define NCCS 32
struct termios {
    tcflag_t c_iflag;
    tcflag_t c_oflag;
    tcflag_t c_cflag;
    tcflag_t c_lflag;
    cc_t c_line;
    cc_t c_cc[NCCS];
    speed_t c_ispeed;
    speed_t c_ospeed;
};
#define IGNBRK 0x001
#define BRKINT 0x002
#define IGNPAR 0x004
#define PARMRK 0x008
#define INPCK 0x010
#define ISTRIP 0x020
#define INLCR 0x040
#define IGNCR 0x080
#define ICRNL 0x100
#define IXANY 0x800
#define OPOST 0x01
#define OCRNL 0x08
#define ONOCR 0x10
#define ONLRET 0x20
#define OFILL 0x40
#define OFDEL 0x80
#define B0 0x00000000
#define B50 0x00000001
#define B75 0x00000002
#define B110 0x00000003
#define B134 0x00000004
#define B150 0x00000005
#define B200 0x00000006
#define B300 0x00000007
#define B600 0x00000008
#define B1200 0x00000009
#define B1800 0x0000000a
#define B2400 0x0000000b
#define B4800 0x0000000c
#define B9600 0x0000000d
#define B19200 0x0000000e
#define B38400 0x0000000f
#define EXTA B19200
#define EXTB B38400
#define ADDRB 0x20000000
#define CMSPAR 0x40000000
#define CRTSCTS 0x80000000
#define IBSHIFT 16
#define TCOOFF 0
#define TCOON 1
#define TCIOFF 2
#define TCION 3
#define TCIFLUSH 0
#define TCOFLUSH 1
#define TCIOFLUSH 2
#define VINTR 0
#define VQUIT 1
#define VERASE 2
#define VKILL 3
#define VEOF 4
#define VTIME 5
#define VMIN 6
#define VSWTC 7
#define VSTART 8
#define VSTOP 9
#define VSUSP 10
#define VEOL 11
#define VREPRINT 12
#define VDISCARD 13
#define VWERASE 14
#define VLNEXT 15
#define VEOL2 16
#define IUCLC 0x0200
#define IXON 0x0400
#define IXOFF 0x1000
#define IMAXBEL 0x2000
#define IUTF8 0x4000
#define OLCUC 0x00002
#define ONLCR 0x00004
#define NLDLY 0x00100
#define NL0 0x00000
#define NL1 0x00100
#define CRDLY 0x00600
#define CR0 0x00000
#define CR1 0x00200
#define CR2 0x00400
#define CR3 0x00600
#define TABDLY 0x01800
#define TAB0 0x00000
#define TAB1 0x00800
#define TAB2 0x01000
#define TAB3 0x01800
#define XTABS 0x01800
#define BSDLY 0x02000
#define BS0 0x00000
#define BS1 0x02000
#define VTDLY 0x04000
#define VT0 0x00000
#define VT1 0x04000
#define FFDLY 0x08000
#define FF0 0x00000
#define FF1 0x08000
#define CBAUD 0x0000100f
#define CSIZE 0x00000030
#define CS5 0x00000000
#define CS6 0x00000010
#define CS7 0x00000020
#define CS8 0x00000030
#define CSTOPB 0x00000040
#define CREAD 0x00000080
#define PARENB 0x00000100
#define PARODD 0x00000200
#define HUPCL 0x00000400
#define CLOCAL 0x00000800
#define CBAUDEX 0x00001000
#define BOTHER 0x00001000
#define B57600 0x00001001
#define B115200 0x00001002
#define B230400 0x00001003
#define B460800 0x00001004
#define B500000 0x00001005
#define B576000 0x00001006
#define B921600 0x00001007
#define B1000000 0x00001008
#define B1152000 0x00001009
#define B1500000 0x0000100a
#define B2000000 0x0000100b
#define B2500000 0x0000100c
#define B3000000 0x0000100d
#define B3500000 0x0000100e
#define B4000000 0x0000100f
#define CIBAUD 0x100f0000
#define ISIG 0x00001
#define ICANON 0x00002
#define XCASE 0x00004
#define ECHO 0x00008
#define ECHOE 0x00010
#define ECHOK 0x00020
#define ECHONL 0x00040
#define NOFLSH 0x00080
#define TOSTOP 0x00100
#define ECHOCTL 0x00200
#define ECHOPRT 0x00400
#define ECHOKE 0x00800
#define FLUSHO 0x01000
#define PENDIN 0x04000
#define IEXTEN 0x08000
#define EXTPROC 0x10000
#define TCSANOW 0
#define TCSADRAIN 1
#define TCSAFLUSH 2
/* A disabled control character (no vdisable byte is otherwise reserved). */
#define _POSIX_VDISABLE '\0'
#define CEOF 004
#define CEOL 0
#define CERASE 0177
#define CINTR 003
#define CKILL 025
#define CMIN 1
#define CQUIT 034
#define CSTART 021
#define CSTOP 023
#define CSUSP 032
#define CTIME 0
int tcgetattr(int descriptor, struct termios *attributes);
/* ACTION is TCSANOW, TCSADRAIN or TCSAFLUSH; others fail with EINVAL.
   Success means at least one requested change was applied (as POSIX). */
int tcsetattr(int descriptor, int action, const struct termios *attributes);
/* Speeds live in the CBAUD bits of c_cflag; the input speed is always the
   output speed (cfsetispeed of 0 changes nothing). Invalid codes: EINVAL. */
speed_t cfgetospeed(const struct termios *attributes);
speed_t cfgetispeed(const struct termios *attributes);
int cfsetospeed(struct termios *attributes, speed_t speed);
int cfsetispeed(struct termios *attributes, speed_t speed);
int cfsetspeed(struct termios *attributes, speed_t speed);
/* The BSD raw mode: no echo, canonical input, signals or processing. */
void cfmakeraw(struct termios *attributes);
int tcdrain(int descriptor);
int tcflow(int descriptor, int action);
int tcflush(int descriptor, int queue);
int tcsendbreak(int descriptor, int duration);
pid_t tcgetsid(int descriptor);
/* Also declared by <unistd.h>. */
pid_t tcgetpgrp(int descriptor);
int tcsetpgrp(int descriptor, pid_t group);
#endif
