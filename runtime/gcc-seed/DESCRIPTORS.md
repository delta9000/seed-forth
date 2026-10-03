# Bounded descriptor and temporary-file contracts

Original oyacc main.c requires fdopen, mkstemp, unlink and _exit. fdopen accepts
the existing r/w/a syntax with optional b and +, validates descriptor access
through real fcntl, rejects incompatible or Linux O_PATH descriptors, and
preserves the offset. A w mode never truncates; append mode sets O_APPEND.
Only success transfers close ownership to fclose. Allocation precedes append
changes. Failure leaves the descriptor open and frees only stream storage.
The common mode parser preserves fopen's existing create/truncate behavior.
See the [fdopen contract](https://man7.org/linux/man-pages/man3/fdopen.3p.html).

mkstemp replaces the final six Xs of a writable pathname. It obtains eight
bytes through Linux getrandom and opens a 0600 read/write file with O_CREAT
and O_EXCL. It completes short entropy reads, retries interrupted calls, and
selects another candidate on collision, failing after 128 collisions. There
is no predictable entropy fallback. Failure restores the final six Xs; invalid
input is unchanged. Existing files cannot be truncated. The caller owns the
new descriptor and pathname cleanup. See [mkstemp](https://man7.org/linux/man-pages/man3/mkstemp.3.html)
and [getrandom](https://man7.org/linux/man-pages/man2/getrandom.2.html).

unlink makes the real Linux unlink call and preserves open descriptors to the
file. _exit terminates the supported single-threaded process with the low eight
status bits and no cleanup callbacks. Existing streams are unbuffered. The
headers expose only implemented calls and actual Linux flag/command constants;
paths.h deliberately selects /tmp/ as source policy. No general POSIX or full
libc claim is made. ABI constants follow [Linux v6.12](https://github.com/torvalds/linux/blob/v6.12/include/uapi/asm-generic/fcntl.h).

The Forth-only tests cover modes, access, offsets, non-truncation, append,
ownership, 32 simultaneously existing unique 0600 files, unlink while open,
cleanup and _exit output/status. Separate Forth-compiled fault copies force
allocation and syscall errors, partial entropy, exact pointer progression,
interruption, collisions and exhaustion. They are never production inputs.
Host C90/libc builds at O0/O2 independently check shared public behavior;
host mode/O_PATH extensions, failed-template bytes, and buffered _exit output
are kept separate from this runtime's explicit bounded choices. Fresh replay
reports supersede all artifacts lost in the workspace replacement.
