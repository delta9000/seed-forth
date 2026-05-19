# Chapter 5 — Talking to Linux: `syscall6` Wrappers

> **Status:** ✅ complete.  Prose covers every section-plan beat; the
> Try-it path runs through `./test.sh`.  Canonical blocks cover
> `010-lib.fth` lines 39–62.

## Goal

By the end of this chapter the reader can:

- name and call the Linux x86-64 system-call ABI from Forth;
- explain why every wrapper pads with `[lit] 0` even when the
  syscall ignores those arguments;
- write a new syscall wrapper (e.g. `lseek`, `dup2`) by reading the
  Linux manpages and one existing wrapper.

## Source coverage

`010-lib.fth` lines 39–62.  Five definitions plus the section header:
`open`, `read`, `write`, `close`, `die`.

## Concepts introduced

- **The Linux x86-64 syscall ABI.**  Arguments in `rdi`, `rsi`, `rdx`,
  `r10`, `r8`, `r9`; syscall number in `rax`; result in `rax`; trap via
  `syscall`.
- **`syscall6` as a uniform wrapper.**  One primitive handles every
  syscall; user-facing words just pad zeros and pin the syscall number.
- **Syscall numbers as constants.**  `read=0  write=1  open=2  close=3
  exit=60`.  These are amd64-Linux-specific.
- **`die` as the universal error path.**  No exceptions, no
  longjmp — every error in the C compiler is a `die`.

## Concepts carried in

- `[lit]` and the multi-argument calling convention from Ch 1.
- `syscall6` primitive from the seed.

## Concepts deferred

- The `syscall6_code` x86-64 implementation in the seed — Part II,
  Ch 16.
- Reading and writing files end-to-end (we use `open`/`read`/`write`
  here but the file-loading machinery sits in Part III's
  `030-cc-io.fth`, Ch 22).

---

Forth can stand entirely above the OS — push numbers, run colon
definitions, never touch a file.  But the seed-forth project's whole
point is to bootstrap a C compiler, and that means reading source
files, writing object files, and exiting with a status code.  All of
those go through Linux system calls.  This chapter shows the
Forth-level wrappers that connect `010-lib.fth` to the kernel.  The
machine-code primitive `syscall6` does the register-loading; the
wrappers in this chapter just supply the arguments.

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

The one quirk in that table is the 4th argument: most x86-64
*function* calls use `rcx`, but syscalls use `r10`.  The reason is
mechanical — the `syscall` instruction itself clobbers `rcx` (it
stashes the return address there).  The kernel ABI had to pick a
different register for argument 4, and `r10` was the obvious choice
because it's caller-saved and not used by the function ABI for
anything else.  This is irrelevant to us at the Forth level (we never
write `rcx` or `r10` by name; the primitive handles it), but it's the
kind of detail that bites if you ever try to make a syscall from
inline assembly.

The full Forth-side signature is:

```
syscall6 ( a b c d e f n -- rax )
```

Stack effect: pop seven values.  `n` is the syscall number (loaded
into `rax`).  `a..f` are arguments 1–6, popped in that order from the
top of the stack — but since Forth stack notation lists top-of-stack
on the right, `a` is the *deepest* of the six and `f` is the topmost.
The primitive arranges them into the right registers and executes
`syscall`.

## 2. `open` — three real args, three padding zeros

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

The three trailing zeros become `r10`, `r8`, `r9` — argument slots 4,
5, 6 that `open` ignores.  Reading the `( a b c d e f n -- )`
signature back onto our stack: `a=path`, `b=flags`, `c=mode`, `d=e=f=0`,
`n=2`.  So `rdi=path`, `rsi=flags`, `rdx=mode`, `rax=2`.  That's
exactly the Linux ABI for `open`.

The parameter order in the wrapper matches the C signature — `open(path,
flags, mode)` — which is the natural reading order, even though it
means the path sits deeper on the stack than mode.  When you call
`open` from Forth, push the arguments in C-source order; the wrapper
handles the rest.

## 3. `read` and `write` — a symmetric pair

These are the I/O syscalls every program uses sooner or later.
`SYS_read = 0`, `SYS_write = 1`.  Both take the same three arguments —
file descriptor, buffer address, byte count — and return the actual
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

Two subtleties worth flagging:

- The return value `n` can be less than `count`.  A `read` from a pipe
  may return fewer bytes than requested if more haven't arrived yet;
  a `write` to a full disk may return fewer than requested because the
  kernel ran out of room.  The wrappers do not retry.  Code that
  needs reliable transfer (the C compiler's output path, for
  instance) wraps `write` in a loop or treats short writes as fatal
  via `die`.

- A negative `n` indicates an error, with the magnitude being a Linux
  errno code (e.g. `-9` for `EBADF`).  The seed does not distinguish
  errors from short reads in Forth — that decision is made at the
  call site, usually by a "did we get the bytes we expected?" check.

## 4. `close` — one real arg, five padding zeros

```forth
\ close ( fd -- err )                SYS_close=3
: close  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit]  3 syscall6 ;
```

`close` takes only an `fd`, so we pad five zeros.  The wrapper looks
disproportionately wide for the work it does — 14 tokens to call a
syscall that takes one argument — but `syscall6` doesn't know which
argument slots matter.  The kernel happily ignores `rsi..r9` when the
syscall doesn't reference them, but the primitive still has to put
*something* in those registers.  Padding with zeros is the cheapest
choice.

Why not specialise — make `syscall1`, `syscall2`, ..., `syscall6` so
each wrapper has exactly the right arity?  Two reasons.  First, every
specialisation costs a primitive slot (dictionary header + machine
body), the same calculation we walked in Ch 3 and Ch 4.  Second, the
"pad with zeros" pattern is fine because zeros are free — `[lit] 0` is
two tokens, and there are at most five of them per wrapper.  Cheaper
than another primitive.

## 5. `die` — exit unconditionally

```forth
\ die ( n -- )  Exit with status n via SYS_exit=60.
: die  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 60 syscall6 ;
```

`die` is the C compiler's only error path.  No exceptions, no
`longjmp`, no error-return convention bubbling up through every
caller.  When something goes wrong — an unexpected token, a missing
file, a malformed type — the offending word prints a brief message
(or doesn't) and calls `die` with an exit status.  The kernel reaps
the process.

Structurally it's a `close`-shaped wrapper: one real argument (the
exit status), five padding zeros, syscall number 60.  The signature
says `( n -- )` rather than `( n -- err )` because `die` never
returns; control transfers to the kernel and the Forth interpreter is
gone.

A typical error path in Part III's C compiler looks like:

```
unexpected? if, [lit] 1 die then,
```

Read it as: "if the unexpected? predicate is true, push exit status 1
and die."  No cleanup, no resource release — the OS handles that when
the process exits.  This is a deliberate simplification: the C
compiler is a one-shot tool that runs, produces an ELF binary, and
exits.  Nothing it allocates needs to live past its own lifetime.

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
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo 'here [lit] 65 c,'
  echo '[lit] 1  here [lit] 1 -  [lit] 1  write drop'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

This stores byte `65` (`A`) at HERE, then calls
`write(fd=1, buf=here-1, count=1)`.  The seed prints `A`.

## Exercises

1. Add `lseek ( fd offset whence -- pos )` as `SYS_lseek=8`.  How many
   `[lit] 0` padding tokens does it need?

2. Why does the seed expose `syscall6` rather than `syscall0`,
   `syscall1`, ..., `syscall6` separately?  (Hint: dictionary size.)

3. The `die` wrapper passes its argument as the *first* syscall arg
   (`rdi`).  Look up `_exit(2)` — does that match?  What does the
   second arg do?

4. Why does `write` *not* check whether its return value equals
   `count`?  (Hint: trace a partial-write scenario and decide who
   should retry.)  How would you build a `write-all` wrapper?

## Takeaways

- The Linux x86-64 syscall ABI is one register-loading convention
  away from being just another function call.
- One primitive (`syscall6`) plus per-syscall wrappers is enough to
  reach all of Linux from Forth.  No `libc`, no `mmap`-magic; just
  CPU registers and a `syscall` instruction.
- `die` is the entire error-handling story.  We will see it in
  every codepath from Part III onwards.

Next: Chapter 6 — Character Classification.
