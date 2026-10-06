# Buffered streams

Until this stage every `FILE` operation was a system call: `getc` read one
byte with `read(2)` and `printf` issued one `write(2)` per directive. Tools
that read or write a character at a time (`cut`, `od`, `uniq`, `tr`, the
lexers, gawk's output) ran 10 to 40 times slower than with glibc. Streams
now have the standard ISO C buffering modes.

## Modes

| Stream | Mode on first use |
|---|---|
| `stdin`, `stdout`, files from `fopen`/`fdopen`/`freopen` | line buffered when the descriptor is a terminal (`TCGETS` succeeds), fully buffered otherwise |
| `stderr` | unbuffered |

The mode is chosen at the first read or write, so `setvbuf` after opening
and before I/O applies, as C requires. The default buffer is `BUFSIZ`
(8192) bytes from `malloc`; if allocation fails the stream is unbuffered.

- Fully buffered output is written when the buffer fills, on `fflush`,
  `fclose`, `fseek`, a switch to reading, and at exit. A request of at least
  one buffer with nothing pending is written directly.
- Line-buffered output is also written when a newline is stored.
- Unbuffered output goes straight to `write(2)`. Each `printf`-family call
  on an unbuffered stream formats into one temporary buffer first, so a
  diagnostic reaches the descriptor in one write (as glibc does).
- Input fills the buffer with one `read(2)` of up to the buffer size; reads
  of at least a buffer's worth go directly into the caller's memory.
  Unbuffered input reads into a one-byte area inside the `FILE`.
- Before a line-buffered or unbuffered input stream reads from its
  descriptor, every line-buffered output stream is flushed (ISO C 7.21.3),
  so a prompt written to a terminal appears before the program waits.

## Control

- `setvbuf(stream, buffer, mode, size)` accepts `_IOFBF`, `_IOLBF` and
  `_IONBF` (glibc's values 0, 1, 2). With a caller buffer larger than 16
  bytes the stream uses it, keeping its first 8 bytes for `ungetc`; a
  smaller caller buffer is replaced by an allocated one. Called after I/O,
  it first writes pending output and gives back unread input. An invalid
  mode returns `EOF` with `EINVAL`.
- `setbuf(stream, buffer)` is `setvbuf(stream, buffer, buffer ? _IOFBF :
  _IONBF, BUFSIZ)`. The BSD `setbuffer` and `setlinebuf` are provided too.
- `fflush(stream)` writes pending output. On an input stream it gives
  unread buffered bytes back by moving a seekable descriptor's offset to
  the stream position; on a pipe or terminal (`ESPIPE`) the buffer is kept
  and the call succeeds, as in glibc. `fflush(NULL)` writes every output
  stream.
- `exit` (and returning from `main`, whose result the startup code now
  passes to the C `exit`) writes every output stream's pending bytes before
  the Linux exit. `_exit` and `abort` do not. There is no `atexit` yet; when
  it exists, its handlers must run before this flush.
- `fclose` writes pending output, gives back unread input on a seekable
  descriptor (POSIX), closes the descriptor and releases the buffer.

The runtime does not flush before `fork`, `vfork` (an ordinary fork here) or
the `exec` family, just as glibc does not: a program that forks with output
pending should call `fflush` first. A child that leaves through `_exit`
never writes the parent's copied buffer.

## Positioning, update streams and pushback

A stream is reading, writing or idle. Switching from writing to reading
writes pending output first; switching from reading to writing gives back
unread input. ISO C requires `fflush` or a positioning call between output
and input on an update stream; the runtime also tolerates a missing one.

- `fseek` writes pending output, adjusts `SEEK_CUR` by the unread bytes,
  and only after a successful `lseek` discards the buffer and the
  end-of-file indicator. A failed seek leaves the buffer, pushback and
  indicators unchanged.
- `ftell` is the descriptor offset plus pending output, minus unread input.
  On an append stream pending output is written first, because its offset
  is only known after the write. `fseeko`/`ftello` are the same with
  `off_t` (long).
- `ungetc` stores into the buffer: every buffer has 8 bytes of headroom, so
  at least 8 bytes can be pushed back (C guarantees one; glibc allows
  several). Pushed bytes count as unread input for `ftell` and `fflush`.
  `ungetc(EOF)` fails, and a successful `ungetc` clears end of file.

End of file is sticky: once a read returns 0 bytes, later reads return EOF
without calling `read(2)` until `clearerr`, a seek, or `ungetc`.

## Errors

A failed write sets the error indicator and errno, and drops the bytes that
were not written; the call that triggered it (`fflush`, `fclose`, a `putc`
that filled the buffer, `printf`) reports failure. Data accepted into a
buffer is reported as written: `fprintf` to `/dev/full` returns its length
and the following `fflush` fails with `ENOSPC`, as with glibc. Interrupted
reads, writes, seeks and opens are retried; `close` is never retried.

## FILE

`FILE` is now a complete type, so programs may declare `FILE` objects
(coreutils `paste` uses `static FILE dummy;` as a sentinel). Its members
have reserved `__` names and no host-libc layout compatibility; programs
must use the functions. `getc`, `putc` and friends are functions with a
short in-buffer fast path. The `_unlocked` forms and `flockfile` are
trivial: the runtime is single-threaded.

## Tests

`tests/gcc/stdio-check.py` builds the production fixture and the scripted
syscall-fault fixture with Forth tools only. The fault fixture first makes
`stdin` and `stdout` unbuffered, so its original EINTR, short-write, error,
EOF and pushback scenarios still see every call; it then checks a caller's
fully buffered and line-buffered buffer (no write until `fflush` or a
newline, EINTR and short writes during the flush, `ENOSPC` reported by
`fflush`, `fclose` writing pending bytes). `tests/gcc/stdio-buffering-check.py`
checks the observable behaviour of a Forth-built program against the same
program built with host glibc (oracle only): the bytes and status for
stdout/stderr interleaving through a shared pipe, a shared file and a
pseudo-terminal,
flush at `exit` and return from `main`, nothing written after `_exit`,
`setvbuf` modes, update-stream switching, `ungetc`, `ftell`/`fseek` with
buffered data, `fflush` of input streams, and the number of `write(2)`
calls for 100,001 single-character `putchar` calls (13 with `strace`).
