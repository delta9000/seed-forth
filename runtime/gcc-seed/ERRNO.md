# Error numbers and their text

The GNU plumbing tools (make, bash, sed, grep, gawk, coreutils, tar, gzip,
patch, diffutils) test for and report error values that the earlier bounded
`errno.h` did not name: `EXDEV` from `mv`/`rename`, `ENXIO` from `getlogin`
and terminal code, `EBUSY`, `ETXTBSY`, `EFBIG`, `EROFS`, `EMLINK`, `ENOTSUP`
and others. Discovery builds had to define them in each `config.h`.

## The values

`errno.h` now defines every user-visible Linux AMD64 error number: the
asm-generic values 1 through 133 (`EPERM` to `EHWPOISON`), with glibc's
aliases `EWOULDBLOCK` (`EAGAIN`), `EDEADLOCK` (`EDEADLK`) and `ENOTSUP`
(`EOPNOTSUPP`, 95). Linux leaves 41 and 58 unused; the kernel-internal
`EFSBADCRC`/`EFSCORRUPTED` spellings are not user ABI and are omitted. The
numbers are the kernel's, so `errno = -raw_result` in every wrapper is
already correct for any of them.

## strerror and perror

`strerror.c` indexes a table of the glibc C-locale messages by number
("Operation not permitted" through "Memory page has hardware error"), so
every defined value has text. Numbers outside the table, the two unused
numbers and negative values produce `Unknown error N` in one static buffer,
overwritten by the next unknown lookup (the runtime is single-threaded).
`strerror` preserves errno.

`perror` in `stdio.c` now prints `strerror(errno)`, replacing its own list of
seventeen messages: `PREFIX: text` when the prefix is nonnull and nonempty,
otherwise just the text, and it preserves errno. Programs that use `perror`
therefore link `strerror.o`.

## Gate

`python3 tests/gcc/posix-signals-check.py` (shared with
[signals](SIGNALS.md)) prints every name's value, `strerror` for -2 through
136 with an errno-preservation check, and three `perror` forms. The output
must equal host glibc's at `-O0` and `-O2` byte for byte; see
`tests/gcc/posix_runtime_harness.py` for the common harness.
