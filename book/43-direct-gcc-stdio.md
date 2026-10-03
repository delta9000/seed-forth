# 43. Generator streams and integer formatting

## Goal

Give original GCC generators real output streams and formatted integer,
pointer, and string output. Compile the implementation from C using Forth,
link it with the Forth syscall runtime, and test its bytes and failure paths.
This chapter supplies a bounded stdio surface; it does not establish a
complete libc or a rebuilt GCC.

**Source coverage:** the original project implementation in
[`runtime/gcc-seed/stdio.c`](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/runtime/gcc-seed/stdio.c),
its public [`stdio.h`](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/runtime/gcc-seed/include/stdio.h),
and the `tests/gcc/stdio-*` checks. These nested C files are checked-in
source rather than root-level Forth tangler outputs. They use the project
MIT license and do not copy or adapt another libc.

**Concepts carried in:** System V calls and objects from chapters 35–37,
the Linux syscall and errno bridge from chapter 38, memory and allocation
from chapter 39, and genuine System V `va_list` traversal from chapter 42.

**Concepts introduced:** opaque unbuffered streams, sticky stream state,
partial transfer accounting, a shared counting formatter, and deterministic
fault tests separate from real-kernel production evidence.

**Deferred:** buffering, threading, locale, wide characters, floating-point
formatting, scanning, positional arguments, process/environment support,
and interfaces without a measured generator consumer.

## 1. Start with the original consumers

The pinned GCC source is commit
`944765863eec87a9f37e297994fd2af960397138`. Its `gcc/gencheck.c` needs
`puts`, `fputs` to `stderr`, and a `printf` containing two `%s` arguments.
Its generated names come from the original definition files. There is no
reason to replace those names or the generator with precomputed output.

Nearby consumers explain each expansion of the surface. `genflags.c`
needs `putchar` and dynamic left-aligned string width. `genconstants.c`
and `genflags.c` check `ferror`, `fflush`, and `fclose` on standard output.
`genmodes.c` uses `snprintf`, `%u`, dynamic width, and `%n` to align its
generated comments. `errors.c` forwards a real `va_list` to `vfprintf`.

Input is justified by `gensupport.c`, which opens and closes machine
description files and calls `perror` on failure. `read-rtl.c` consumes
characters through `getc`, pushes a character back with `ungetc`, and
reports a position through `ftell`. Counted read and write functions make
the common transfer semantics explicit and directly testable. We do not
declare every interface that a full system `stdio.h` happens to expose.

## 2. A FILE is state, not a disguised descriptor

The public header declares an incomplete `FILE` structure. Callers receive
a pointer from `fopen` or from the standard-stream macros; they cannot
assume its layout or exchange it with host libc. The private object holds
the descriptor, allowed access, ownership, error and end-of-file indicators,
and one byte of pushback. Standard streams use stable static objects;
`fopen` owns a separately allocated object.

All streams are unbuffered. A successful write has already reached Linux,
so `fflush` has no pending output to drain, and `fflush(NULL)` succeeds.
This is an actual storage contract, not a successful placeholder for a
missing buffer. On a readable seekable stream, flushing a pushed-back byte
uses `lseek` to restore the underlying offset before clearing pushback.

The opening modes are `r`, `w`, and `a`, optionally with one `b` and one
`+` in either order. Linux treats text and binary bytes identically here.
Creation requests mode `0666`, which remains subject to the process umask;
append uses the kernel's append flag. Unsupported or repeated mode letters
fail with `EINVAL`. This is deliberately narrower than libc extensions
such as close-on-exec mode letters.

`ungetc(EOF, stream)` fails without changing stream state. A successful
pushback clears the end-of-file indicator and returns the unsigned byte.
One pending byte is supported, as required by the standard guarantee.
`ftell` subtracts that pending byte from the kernel offset. The stream
error and end-of-file indicators remain distinct, and `clearerr` clears
both without changing the file position.

## 3. Count progress, including incomplete objects

Read and write loops advance after every positive kernel result. An
interrupted call is retried; a short successful transfer continues from
the remaining bytes. Reads stop on end-of-file, and real errors preserve
completed bytes while setting errno and the stream's error indicator.
A zero-result write is treated as `EIO`, preventing an infinite retry.

`fread` and `fwrite` return complete object counts. If four bytes of a
six-byte request are transferred with an object size of three, one whole
object is reported even though a byte of the next object was transferred.
Zero-sized requests do nothing. Multiplication overflow is rejected
before a syscall with the Linux `EOVERFLOW` value, 75.

Closing is different from reading and writing. Linux releases a descriptor
even when `close` reports `EINTR`. Retrying could close a new file that
reused the descriptor number. `fclose` therefore attempts close once,
invalidates the stream, frees owned storage, and reports the original
failure. Standard-stream storage persists but a closed stream is never
silently reopened by its accessor.

## 4. One formatter, two destinations

The formatter carries a destination stream or buffer, a capacity, a count,
and a failure flag. Literal spans, converted digits, prefixes, and padding
all pass through this small output interface. For streams, the count
advances only after successful writes. For bounded buffers, the count
tracks the full required length while copying only the bytes that fit.

`snprintf` reserves one byte for the terminator when capacity is nonzero.
A zero-capacity call may use a null buffer and still obtains the required
length. Embedded zero characters count as output bytes. Width and output
counts that cannot fit in an `int` fail with `EOVERFLOW`; large truncated
padding is counted without iterating billions of times.

Supported conversions are `d`, `i`, `u`, `o`, `x`, `X`, `p`, `c`, `s`,
`n`, and `%%`. Integer flags include `-`, `+`, space, `#`, and `0`;
width and precision may be numeric or supplied with `*`. The integer
lengths are `hh`, `h`, `l`, `ll`, `j`, `z`, and `t` on this LP64 target.
Narrow integers are fetched using their promoted type and then narrowed.
The most-negative signed value is converted through unsigned subtraction,
avoiding signed negation overflow.

`%p` uses lowercase hexadecimal with a `0x` prefix, including `0x0` for
null. A null `%s` is accepted as the extension `(null)`. Neither spelling
is a promise to match another libc's implementation-defined choices.
`%n` stores the full count so far, including bytes truncated by `snprintf`.
Floating, wide, positional, and unknown conversions fail with `EINVAL`
instead of consuming an argument through the wrong ABI class.

All variadic entry points use chapter 42's real System V array-of-record
`va_list`. `printf` forwards that cursor through `vfprintf` into the
formatter. No private Forth stack supplies the argument values. The
production test copies a cursor and sends both copies across the register
and overflow-stack boundary, proving independent traversal.

`perror` prints a prefix and a bounded English error description, with a
numeric fallback for other errno values, and preserves the original errno.
There is no locale or full system error-message catalog.

## 5. Keep the evidence boundaries visible

`stdio-check.py` Forth-compiles the stream implementation, existing memory,
string and allocation runtime, and two fixtures. Forth emits the syscall,
errno, and process-entry objects; Forth also links the executables. The
real-kernel fixture creates, appends and rereads a file, checks pushback and
positions, encounters `/dev/full`, verifies formatted bytes and diagnostics,
and confirms stream-close behavior. A protected-page string checks that a
precision-limited `%s` never reads past its allowed boundary.

A separate executable links a Forth-compiled scripted syscall double.
It forces `EINTR`, short transfers, partial-object failure, end-of-file,
`EAGAIN`, a zero-progress write, and close interruption. This executable
tests hard-to-schedule control flow; it is not used as evidence that those
particular syscall outcomes occurred naturally in the real-kernel run.

The optional oracle compiles a separately named copy of stdio with Forth,
then links a host-GCC harness against it and host libc. At both `-O0` and
`-O2`, 695 comparisons cover formatting, lengths, truncation and argument
forwarding, followed by a truncated `%n` check. Its host compiler, linker,
and libc make it an independent oracle, never a production bootstrap
artifact. The production check retains objects, executables and source
and artifact hashes for inspection.

## Try it

Run the Forth-only reconstruction from the repository root:

```sh
python3 tests/gcc/stdio-check.py
```

Run the independent host-libc oracle separately:

```sh
python3 tests/gcc/stdio-oracle-check.py
```

Both checks passed on 2026-10-03. A missing host GCC skips only the optional
oracle; the production check does not call a host compiler or linker.

## Exercises

- **★** Explain why a stream needs separate error and end-of-file indicators
- **★★** Add a scripted partial read that ends between two complete objects
- **★★** Explain why `%n` after truncated output sees more bytes than the buffer holds
- **★★★** Add buffering while preserving every existing error and count test

## Takeaways

- Original generator calls determine the bounded runtime surface
- Partial progress and sticky errors are observable parts of real stdio
- Real-kernel reconstruction, scripted faults, and host oracles establish distinct facts

Next, compile original generator translation units against these contracts
and let their remaining source requirements determine the next extension.
