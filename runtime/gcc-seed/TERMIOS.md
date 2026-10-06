# Terminals: termios, ioctl, window size and terminal names

`bash` (line editing and job control), `stty`, `tty`, `ls` (`TIOCGWINSZ` for
the column count) and `more`-like code need terminal control. These are all
Linux tty ioctls.

## Headers

`termios.h` defines `struct termios` with glibc's 60-byte layout
(`c_iflag`, `c_oflag`, `c_cflag`, `c_lflag`, `c_line`, `c_cc[32]`,
`c_ispeed`, `c_ospeed`), `NCCS` 32, every Linux `V*` index, input, output,
control and local flag (from the kernel's asm-generic `termbits.h`),
`TCSANOW`/`TCSADRAIN`/`TCSAFLUSH`, the `TC*FLUSH` and `TCO*`/`TCI*` codes,
the `C*` default characters and `_POSIX_VDISABLE`.

Speeds are the traditional Linux `Bnnn` codes in the `CBAUD` bits (`B9600`
is `015`, `B38400` `017`, `B115200` `010002`). glibc 2.42 and later instead
make `speed_t` the numeric rate and also report the input speed in the
`CIBAUD` bits; programs that use the symbolic names behave the same either
way, but `stty -g` strings differ from a new glibc's in those bits.

`sys/ioctl.h` declares `ioctl`, `struct winsize`, the System V
`struct termio` (`NCC` 8), and the plain-numbered Linux requests (`TCGETS`
… `TIOCGICOUNT`, `FIONREAD`, `FIONBIO`, `FIOCLEX`, …) with the `TIOCPKT_*`
and `TIOCM_*` bits. `termio.h`, as in glibc, just includes `termios.h` and
`sys/ioctl.h`.

## Calls

- `ioctl(fd, request, ...)` passes one optional pointer-sized argument to
  syscall 16 unchanged (requests without an argument ignore it).
- `tcgetattr` reads the kernel's 36-byte `TCGETS` record, copies its 19
  control characters, fills the remaining 13 with `_POSIX_VDISABLE`, and
  sets `c_ispeed`/`c_ospeed` from `CBAUD`.
- `tcsetattr` maps `TCSANOW`, `TCSADRAIN` and `TCSAFLUSH` to `TCSETS`,
  `TCSETSW` and `TCSETSF` (any other action fails `EINVAL`) and writes the
  same 36 bytes. As POSIX allows, success means at least one change was
  applied; `stty` rereads the attributes to check.
- `cfgetospeed`/`cfgetispeed` return the `CBAUD` bits. `cfsetospeed` stores
  a valid code there (others fail `EINVAL`); `cfsetispeed` with a nonzero
  speed does the same (input and output speeds are always equal) and with 0
  changes nothing. `cfsetspeed` is `cfsetospeed`. `cfmakeraw` applies the
  BSD raw settings.
- `tcdrain` (`TCSBRK` 1), `tcflow` (`TCXONC`), `tcflush` (`TCFLSH`),
  `tcsendbreak` (`TCSBRK` 0, or `TCSBRKP` with the duration rounded up to
  tenths of a second, as glibc), `tcgetsid` (`TIOCGSID`), `tcgetpgrp`
  (`TIOCGPGRP`) and `tcsetpgrp` (`TIOCSPGRP`).
- `ttyname_r(fd, buffer, size)` first checks that `fd` is a terminal
  (`TCGETS`: `ENOTTY`/`EBADF`), reads the `/proc/self/fd/N` link, and
  accepts the name only if it `stat`s to the same device and inode (`ENODEV`
  otherwise, for example a pty from another mount namespace); a short buffer
  gives `ERANGE`. The error is returned and, as glibc does, also left in
  errno. `ttyname` uses one static `PATH_MAX` buffer. There is no `/dev`
  search fallback.

## Gate

`python3 tests/gcc/posix-termios-check.py` gives each build (Forth, host
GCC/glibc `-O0` and `-O2`) a fresh 33x101 pseudo-terminal as standard input
and as the controlling terminal of a new session, with standard output a
pipe, and requires identical output: every constant, `tcgetattr` on the pty,
`cfmakeraw`, `tcsetattr` with all three actions and an invalid one, the
reread attributes, symbolic speed round trips, window size get and set,
`ttyname`/`ttyname_r` (including `ERANGE`, a pipe and a closed descriptor),
`ENOTTY`/`EBADF` from `tcgetattr`, foreground group and session,
`tcsetpgrp`, `tcflush` (valid and invalid), `tcdrain`, `tcflow` and
`tcsendbreak`. `c_cflag` is printed without the `CIBAUD` bits, and the
runtime-only checks (speed codes, invalid speed) run under `#ifndef __GLIBC__`.
