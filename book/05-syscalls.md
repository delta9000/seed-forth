# Chapter 5 — Talking to Linux: `syscall6` Wrappers

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 39–62.  Prose goes between them.

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

## Section plan

1. **A sidebar on the syscall ABI.**  Brief table mapping argument
   position to register: `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`,
   number in `rax`.  Why six arguments?  Why is the 4th register
   `r10` instead of `rcx`?
2. **`open` — three real args, three padding zeros.**  Read the
   wrapper.  Compare its parameter order `( path flags mode )` to the
   `open(2)` man page.
3. **`read` and `write` — symmetric pair.**  Both take `fd`, buf,
   count.  Both return a byte count (or `-1` on error, but we
   typically just propagate it).
4. **`close` — one real arg, five padding zeros.**  Why the wrapper
   bothers padding all six argument slots even when only the first is
   used.  (Hint: `syscall6` doesn't know which slots matter.)
5. **`die` — exit unconditionally.**  Used by the C compiler instead
   of any exception machinery.  Show how an error path looks: `if,
   ... die then,`.

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

These wrappers require a built seed-forth (or any Forth that exposes
`syscall6`); the gforth playground does not.  `./test.sh` exercises
them via `test-010-lib.fth` (look for `open`/`read`/`write` round-trip
assertions there).

A hands-on demo: build the seed, then write three bytes to a file:

```sh
./build.sh
./test.sh    # also runs the fileio test from test.sh
```

The fileio test in `test.sh` (lines ~62–86) opens `/tmp/forth-fwio-test`
with `O_WRONLY|O_CREAT|O_TRUNC` flags, writes `"OK\n"`, closes, and
checks the resulting file.  Trace its Forth source to see the wrappers
in real use.

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
