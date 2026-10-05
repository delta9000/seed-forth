# Linux AMD64 directories

`dirent.c` implements `opendir`, `readdir` and `closedir` through the existing
raw syscall bridge. It supplies the directory traversal used by unmodified
GCC 4.0.4 `libcpp/files.c` when scanning precompiled-header directories. The
production objects are compiled and linked by Forth; host libc is not used.

Each stream owns one directory descriptor and 32,792 bytes of state, including
a 32 KiB record buffer aligned to eight bytes. The existing allocator adds a
16-byte header and rounds the mapping to nine 4 KiB pages. Opening uses
`O_DIRECTORY | O_CLOEXEC`, so a regular file fails and exec does not inherit
the descriptor. Allocation failure closes the descriptor and retains ENOMEM.

`readdir` exposes the Linux AMD64 getdents64 layout directly. The header has a
one-byte `d_name` declaration marking a variable-length tail; callers use the
NUL-terminated name, not sizeof the structure. No 255-byte truncation occurs.
The pointer belongs to the stream and may be overwritten by the next call.
The runtime validates the record length, eight-byte alignment, nonempty name,
and terminating NUL before returning it. Malformed input produces sticky EIO,
never a pointer outside the returned kernel buffer. Unrepresentably large
records may produce the kernel's EINVAL; the buffer does not grow silently.

End of directory returns NULL without changing errno, including repeated calls.
System-call errors return NULL and expose the kernel errno; a subsequent call
may retry. EINTR is retried for open and getdents64. Close is attempted once,
including when it reports EINTR, and stream memory is released on either
success or failure. NULL streams are rejected with EBADF. Other invalid or
already-closed pointers, concurrent access and directory seeking are outside
this bounded interface. An exhausted stream stays exhausted if entries are
added later; reopening starts a new traversal.

Run `python3 tests/gcc/dirent-check.py`. It compares 3,003 real directory entries
(including a 255-byte name), traverses multiple buffer refills, checks repeated
EOF and 200 partial-open/close cycles, and tests missing paths and regular files.
A separate injected syscall boundary tests interrupted calls, allocation failure,
close failure, invalid/truncated/unterminated records, multiple records per
buffer, and a 492-byte synthetic name. Production runs through Forth. Independent
GCC O0/O2 executables verify the real directory interface and the same injected
boundary cases; only the directory and syscall headers are copied into the
oracle include directory, leaving host libc headers intact.

This resolves the missing dirent.h include in the retained original files.c
invocation. Compilation subsequently stops at error 238 on the separate
pointer-to-array/va_list declaration limitation. It does not establish a complete
libcpp or GCC generator build.
