# Stream operations measured from original Flex

Flex2.5.11 main.c redirects stdout with freopen(path,"w+",stdout), seeks back
to generate a header, and reads it through fgets. misc.c reads skeleton lines;
the generated scanner asks fileno for its input descriptor. This stage adds
those operations to the existing single-threaded, unbuffered Linux AMD64 FILE.

fgets preserves embedded NUL bytes, retains a newline, limits reads to n-1,
terminates successful reads, and leaves the buffer unchanged on immediate EOF.
A new I/O error returns NULL and sets the error indicator. A previous sticky
error remains set without falsely turning a later successful read into failure.
The explicit n=1 contract returns an empty string without reading; n<=0 fails
with EINVAL. These small-count choices are checked separately from portability.

fseek accepts the real Linux SEEK_SET/CUR/END values. Relative seeks account
for one pushed byte, detect LONG_MIN subtraction overflow, and discard pushback
and EOF only after a successful seek. Existing error indicators remain set.
Interrupted seeks retry; errors preserve errno and leave pushback/EOF intact.
fileno returns the actual owned descriptor without changing stream indicators.

freopen closes the previous descriptor first, ignoring close errors, and reuses
the same FILE on success. It preserves the original descriptor number through
real dup2 when necessary, preserving stdout descriptor1 even when stdin is
closed. It clears stream state and preserves FILE allocation ownership. Open or
duplication failure closes all acquired descriptors, releases a heap-owned
FILE, and returns the original operation's errno. Linux close is never retried.
Filename-null mode changes are not supported: the old file is closed and EINVAL
is returned. Invalid mode syntax is rejected before changing the stream.

stream-flex-check.py compares889 independently calculated binary line segments
and actual reopen/seek/append/error cases with separate host C90 O0/O2 builds.
The filename-null choice and n<=0 errno are target-only. The companion fault
suite checks six scenarios including syscall arguments, EINTR, seek overflow,
nonseekable errors, failed open/dup2, and error-indicator ownership. Existing
stdio production, syscall-fault,695-format host comparisons and456 wide-format
checks all pass. Production objects and executables use only Forth tools.

Language behavior references: ISO C committee draft N1570 sections7.21.5.4,
7.21.7.2 and7.21.9.2:
https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf
