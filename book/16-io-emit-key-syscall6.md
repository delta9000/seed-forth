# Chapter 16 — I/O: `emit`, `key`, `syscall6`

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read the `emit_code` and `key_code` primitives byte for byte,
  including their `write(2)` and `read(2)` syscalls;
- read the `syscall6_code` primitive that bridges Forth's six-arg
  convention to the x86-64 syscall ABI;
- explain the single-byte I/O scratch page at `0x412000` and why
  the seed uses one shared buffer instead of per-call allocation.

## Source coverage

`000-seed.hex0` lines roughly 67–96 (`emit`, `key`) plus the
`syscall6_code` body (further down, near the dictionary entries).

## Concepts introduced

- **The I/O scratch page at `0x412000`.**  A single byte that
  `emit` writes to before calling `write(1, scratch, 1)`, and that
  `key` reads into via `read(0, scratch, 1)`.
- **EOF handling in `key`.**  When `read` returns 0, `key` pushes
  `0` (a sentinel the REPL recognises as EOF).
- **`syscall6`'s register marshalling.**  The seed pops seven values
  off the data stack (six args + syscall number), loads them into
  `rdi`/`rsi`/`rdx`/`r10`/`r8`/`r9`/`rax`, executes `syscall`, and
  pushes `rax` as the new TOS.

## Concepts carried in

- The data-stack convention from Ch 14.
- The syscall ABI sketched in Ch 5.

## Concepts deferred

- The token reader `read_word` that uses `key` to assemble a
  whitespace-delimited token — Ch 17.

## Section plan

1. **`emit_code` in 47 bytes.**  Walk it: write TOS's low byte to
   `[0x412000]`; load syscall args (1=stdout, scratch addr, 1=count);
   `syscall`; restore TOS from `[rbp]`; advance `rbp`.
2. **`key_code` in 46 bytes.**  Read one byte from fd 0 into the
   scratch byte; if `rax == 0` (EOF), push `0`; else push the byte.
   Push-shape: `sub rbp, 8; mov [rbp], rdi; mov rdi, value`.
3. **The single-byte scratch.**  Why not a 4 KiB buffer?  Because we
   never need more than one byte at a time at this layer, and a
   shared scratch avoids any stack/heap question.
4. **`syscall6_code`'s register dance.**  Read each `pop` and `mov`.
   Note the order matters: pop the syscall number last (so it lands
   in `rax`), pop arguments in reverse so the deepest stack slot
   ends up in `r9`.

## Canonical chunks

- `<<emit-code>>` — `emit_code @ 0x0DE`, ~47 bytes.
- `<<key-code>>` — `key_code @ 0x10C`, ~46 bytes.
- `<<syscall6-code>>` — the seven-arg syscall wrapper.

## Try it

```sh
./build.sh
echo "[lit] 72 emit [lit] 105 emit bye" | ./seed-forth
# prints "Hi"

# key reads bytes one at a time:
echo "ABC" | ./seed-forth -e 'key emit key emit key emit bye'
# (depending on REPL behaviour, prints "ABC")
```

## Exercises

1. `emit` writes to fd `1` (stdout) hard-coded.  Sketch the changes
   needed to make `emit-to-fd ( c fd -- )` that takes the file
   descriptor from the stack.

2. The scratch byte at `0x412000` is shared between `emit` and `key`.
   Could a multithreaded program corrupt itself?  (Hint: this Forth
   is single-threaded — see if any chapter mentions threads.)

3. Why does `key`'s push-shape look slightly different from the
   shape in Ch 14's table?  Trace `sub rbp, 8 ; mov [rbp], rdi ; mov
   rdi, ...` vs. `mov [rbp+0], rdi; sub rbp, 8` — which is more
   natural for "no input yet, push a value"?

4. Implement a `keys ( c-addr u -- u-actually-read )` primitive in
   hex that calls `read(0, c-addr, u)` directly.  Why doesn't the
   seed expose it?

## Takeaways

- I/O at the seed level is one byte at a time.  Higher layers
  (`010-lib.fth` and especially `030-cc-io.fth`) build their own
  buffered I/O on top of `syscall6`.
- The scratch page is a single byte; the seed doesn't have a
  buffered-I/O concept.
- `syscall6` is the universal kernel-call bridge — every wrapper in
  Ch 5 reduces to "push your args, push the syscall number, call
  `syscall6`."

Next: Chapter 17 — The Dictionary.
