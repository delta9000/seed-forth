# Chapter 5 — Talking to Linux: `syscall6` Wrappers

```text
Missing capability: the Forth code has no way to reach the OS.
New pattern: five wrappers on top of one syscall6 primitive, each pinning its number and padding unused args.
Artifact after this chapter: open, read, write, close, die.
Proof link: the Stage-A driver writes its output via write; the compiler reads stdin via read.
```

Everything the library can do so far happens inside one process.
It can add, subtract, and write bytes into its own memory, but it
cannot open a `.c` file, and it cannot write out the bytes that
Stage-A compares against GCC's.  A compiler that can't
read its input or write its output is a calculator.

There is also no libc to call.  Nothing sits between this compiler
and the Linux kernel except code you can read in this book, which is
the point: a trusting-trust attack needs somewhere to hide, and an
unaudited C library is a large place.  The seed provides one way in, the primitive `syscall6`, which loads
seven registers from the data stack and traps.  On top of it,
`010-lib.fth` (lines 40–62) defines five wrappers: `open`, `read`,
`write`, `close`, and `die`.  Each one pins its syscall number and
pads the argument slots it doesn't use with `[lit] 0`.  Have
`man 2 syscall` handy if you want to check signatures.  The machine
code of `syscall6_code` is Ch 16, and the compiler's file-loading
machinery in `030-cc-io.fth` is Ch 21.

## 1. A sidebar on the syscall ABI

When user code on x86-64 Linux wants the kernel to do something, it
loads registers in a fixed way and executes the `syscall` instruction.
The convention is:

| register | meaning                            |
|----------|------------------------------------|
| `rax`    | syscall number (e.g. `1` for write) |
| `rdi`    | argument 1                          |
| `rsi`    | argument 2                          |
| `rdx`    | argument 3                          |
| `r10`    | argument 4                          |
| `r8`     | argument 5                          |
| `r9`     | argument 6                          |
| `rax`    | return value (overwrites the number) |

Six argument registers is enough for every Linux syscall that exists
(the kernel doesn't ship one that needs seven), so the seed's
`syscall6` primitive accepts a uniform 6-argument signature and lets
the caller pass zeros for the slots a particular syscall doesn't use.

The one quirk in that table is the 4th argument: *function* calls
use `rcx`, but syscalls use `r10`, because the `syscall` instruction
itself clobbers `rcx` (it stashes the return address there).  The
primitive handles this; at the Forth level you never name either
register.

The full Forth-side signature is:

```
syscall6 ( a b c d e f n -- rax )
```

Stack effect: pop seven values.  `n` is the syscall number (loaded
into `rax`).  `a..f` are arguments 1–6.  Since Forth stack notation lists
top-of-stack on the right, `a` is the *deepest* of the six and `f` is the topmost.
The primitive arranges them into the right registers and executes
`syscall`.

## 2. `open`: three real args, three padding zeros

The Linux `open(2)` syscall is `SYS_open = 2`.  It takes a path
pointer, an integer flags mask (e.g. `O_RDONLY`, `O_WRONLY|O_CREAT`),
and a mode (only consulted when creating a file).  Three real
arguments.

```forth
\ open ( path flags mode -- fd )    SYS_open=2
: open   [lit] 0 [lit] 0 [lit] 0 [lit]  2 syscall6 ;
```

Trace it on input `( path flags mode -- )`:

| token       | stack                       |
|-------------|-----------------------------|
| (in)        | `path flags mode`           |
| `[lit] 0`   | `path flags mode 0`         |
| `[lit] 0`   | `path flags mode 0 0`       |
| `[lit] 0`   | `path flags mode 0 0 0`     |
| `[lit] 2`   | `path flags mode 0 0 0 2`   |
| `syscall6`  | `fd`                        |

The three trailing zeros become `r10`, `r8`, `r9`: argument slots 4,
5, 6, which `open` ignores.  Reading the `( a b c d e f n -- )`
signature back onto our stack: `a=path`, `b=flags`, `c=mode`, `d=e=f=0`,
`n=2`.  So `rdi=path`, `rsi=flags`, `rdx=mode`, `rax=2`.  That's
exactly the Linux ABI for `open`.

The parameter order in the wrapper matches the C signature,
`open(path, flags, mode)`, which is the natural reading order, even though it
means the path sits deeper on the stack than mode.  When you call
`open` from Forth, push the arguments in C-source order; the wrapper
handles the rest.

## 3. `read` and `write`: a symmetric pair

These are the I/O syscalls every program uses sooner or later.
`SYS_read = 0`, `SYS_write = 1`.  Both take the same three arguments
(file descriptor, buffer address, byte count) and return the actual
number of bytes transferred.

```forth
\ read  ( fd buf count -- n )        SYS_read=0
: read   [lit] 0 [lit] 0 [lit] 0 [lit]  0 syscall6 ;

\ write ( fd buf count -- n )        SYS_write=1
: write  [lit] 0 [lit] 0 [lit] 0 [lit]  1 syscall6 ;
```

The wrappers are structurally identical; only the syscall number
differs.  Both pad three zeros for the unused 4th/5th/6th argument
slots.

Two subtleties.  First, `n` can be less than `count`: a `read`
from a pipe may return before all bytes arrive, and a `write` to a
full disk may stop short.  The wrappers do not retry.  The C
compiler's output path (`cc-write-output`, Ch 21) makes one `write`
of its whole buffer and drops the count.  Second, a negative `n` is
an error, its magnitude a Linux errno (e.g. `-9` for `EBADF`); the
call site decides what to do with it.

## 4. `close`: one real arg, five padding zeros

```forth
\ close ( fd -- err )                SYS_close=3
: close  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit]  3 syscall6 ;
```

`close` takes only an `fd`, so we pad five zeros: 13 tokens to
make a one-argument syscall.  The kernel ignores `rsi..r9` for
`close`, but `syscall6` loads all six registers regardless, and
zeros are the cheapest filler.

Why not specialise, with `syscall1`, `syscall2`, ..., `syscall6` so
each wrapper has exactly the right arity?  Every specialisation costs
a primitive slot (the Ch 3 trade again), while `[lit] 0` is two
tokens and there are at most five of them per wrapper.

## 5. `die`: exit unconditionally

```forth
\ die ( n -- )  Exit with status n via SYS_exit=60.
: die  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 60 syscall6 ;
```

`die` is the C compiler's only error path.  No exceptions, no
`longjmp`, no error-return convention bubbling up through every
caller.  When something goes wrong (an unexpected token, a missing
file, a malformed type), the offending word prints a brief message
(or doesn't) and calls `die` with an exit status.  The kernel reaps
the process.

Structurally it's a `close`-shaped wrapper: one real argument (the
exit status), five padding zeros, syscall number 60.  The signature
says `( n -- )` rather than `( n -- err )` because `die` never
returns; control transfers to the kernel and the Forth interpreter is
gone.

A typical error path in Part III's C compiler, written with the
control-flow combinators of Ch 11, reads like

```
unexpected? if, [lit] 1 die then,
```

meaning "if the unexpected? predicate is true, push exit status 1
and die."  No cleanup, no resource release; the OS handles that when the process
exits.  This is a deliberate simplification: the C compiler is a
one-shot tool that runs, produces an ELF binary, and exits.  Nothing
it allocates needs to live past its own lifetime.

## Canonical source

```forth file=010-lib.fth
\ ===== Linux syscall wrappers (via syscall6 primitive) =====
\ syscall6 ( a b c d e f n -- rax )  loads a..f into rdi/rsi/rdx/r10/r8/r9
\ and n into rax.  We pad with zeros for unused argument slots.
\
\ Linux x86-64 syscall numbers:
\   read=0  write=1  open=2  close=3  exit=60  brk=12  mmap=9

\ open  ( path flags mode -- fd )    SYS_open=2
: open   [lit] 0 [lit] 0 [lit] 0 [lit]  2 syscall6 ;

\ read  ( fd buf count -- n )        SYS_read=0
: read   [lit] 0 [lit] 0 [lit] 0 [lit]  0 syscall6 ;

\ write ( fd buf count -- n )        SYS_write=1
: write  [lit] 0 [lit] 0 [lit] 0 [lit]  1 syscall6 ;

\ close ( fd -- err )                SYS_close=3
\ Pads 5 zero args + syscall #.
: close  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit]  3 syscall6 ;

\ die ( n -- )  Exit with status n via SYS_exit=60.
\ Used by the C compiler's error paths instead of inlining the full syscall.
: die  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 60 syscall6 ;

```

## Try it

These wrappers require a built seed-forth; `syscall6` is a seed
primitive that the gforth playground does not expose.

```sh
./build.sh && ./test.sh
```

Look for the line:

```
PASS: lib: open/write/close round-trip writes correct bytes
```

The test (in `test.sh` around lines 74–98) builds a path string and a
3-byte payload `"OK\n"` at HERE using `c,`, then calls
`open path 577 420` (flags = `O_WRONLY|O_CREAT|O_TRUNC` = 577, mode =
`0644` = 420), writes 3 bytes, closes the fd, and exits.  The shell
script then reads the file back and confirms the contents.

If you want to watch a wrapper run in isolation, drop into the seed
and emit a byte through `write` directly:

```sh
{ cat 010-lib.fth
  echo 'here [lit] 65 c,'
  echo '[lit] 1  here [lit] 1 -  [lit] 1  write drop'
} | ./seed-forth
```

This stores byte `65` (`A`) at HERE, then calls
`write(fd=1, buf=here-1, count=1)`.  The seed prints `A`.

Unlike `emit`, which Chs 2–4 used, that `A` left through a syscall
the library assembled itself: number 1 in `rax`, three real
arguments, three zeros.  Point the same `write` at an `fd` from
`open` and you have file output; that is how the C compiler's output
reaches disk.

## Exercises

1. **★★ Extend.** Add `lseek ( fd offset whence -- pos )` as `SYS_lseek=8`.  How many
   `[lit] 0` padding tokens does it need?

2. **★★ Trace.** Why does the seed expose `syscall6` rather than `syscall0`,
   `syscall1`, ..., `syscall6` separately?  (Hint: dictionary size.)

3. **★★★ Trace.** The `die` wrapper passes its argument as the *first* syscall arg
   (`rdi`).  Look up `_exit(2)` — does that match?  What does the
   second arg do?

4. **★★★ Extend.** Why does `write` *not* check whether its return value equals
   `count`?  (Hint: trace a partial-write scenario and decide who
   should retry.)  How would you build a `write-all` wrapper?

## Takeaways

- A Linux x86-64 syscall is a register-loading convention (number in
  `rax`, arguments in `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`) plus
  the `syscall` instruction.
- One primitive, `syscall6`, plus zero-padded wrappers reaches every
  syscall the compiler needs without `libc`.
- `die` is the compiler's entire error-handling story: exit with a
  status and let the kernel clean up.

**Part I tally.**  Built so far: byte emission, Boolean logic,
subtraction, **file I/O and exit**.  Still missing: character tests,
`<`, `if,`, `variable`.

Next: Chapter 6 — Character Classification.  With `read` the
compiler can pull source bytes in, and the first thing a lexer asks
of each one is "is this a digit?"  In C that is `c >= '0' && c <=
'9'`.  The library has no `>=`, no `&&`, and no `if,` yet.
