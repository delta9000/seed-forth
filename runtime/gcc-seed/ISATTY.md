# Real terminal detection for generated Flex scanners

isatty performs Linux AMD64 ioctl syscall 16 with TCGETS (0x5401) and a real
36-byte kernel termios structure. It returns one only when that request
succeeds, otherwise zero with the kernel's errno. Success preserves errno.
Interrupted requests return EINTR to the caller; no terminal settings change.
The public interface adds only isatty, not a general ioctl or termios API.

The kernel ABI is pinned to these Linux v6.12 primary sources:
- https://raw.githubusercontent.com/torvalds/linux/v6.12/arch/x86/entry/syscalls/syscall_64.tbl
- https://raw.githubusercontent.com/torvalds/linux/v6.12/include/uapi/asm-generic/ioctls.h
- https://raw.githubusercontent.com/torvalds/linux/v6.12/include/uapi/asm-generic/termbits.h

isatty-check.py executes against a real pseudo-terminal master and slave,
both ends of a pipe, an ordinary file and an invalid descriptor. Independent
host C90 O0/O2 executables agree on results and errno. A separate Forth-built
syscall double validates all arguments, writes the complete 36-byte result
and checks success, EINTR, ENOTTY and EBADF. It is never linked into production.
