# Chapter 14 — Stack Primitives in Machine Code

> **Status:** structural stub.  Section plan and chunk roster are in
> place; canonical hex chunks are added as you write.

## Goal

By the end of this chapter the reader can:

- read the x86-64 encoding of `dup`, `drop`, `swap`, `>r`, `r>`,
  `@`, `!`, `c@`, `c!` byte for byte;
- explain the "TOS in `rdi`, data stack in `rbp`" calling
  convention and trace what each primitive does to both;
- predict, given a stack picture, the bytes that will be in memory
  after executing a sequence of these primitives.

## Source coverage

`000-seed.hex0` lines 65–151 (approximately).  Nine primitive
bodies: `dup_code @ 0x13B`, `drop_code @ 0x144`, `swap_code @
0x14D`, `to_r_code @ 0x159`, `r_from_code @ 0x165`, `fetch_code @
0x171`, `store_code @ 0x175`, `cfetch_code @ 0x189`, `cstore_code
@ 0x18E`.

## Concepts introduced

- **`rbp` = data-stack pointer, `rdi` = TOS register cache.**  The
  seed's whole calling convention.  Every primitive that consumes /
  produces values manipulates these two registers.
- **`sub rbp, 8` = push slot; `add rbp, 8` = pop slot.**  Cells
  are 8 bytes; the stack grows down.
- **`mov [rbp+0], rdi`** spills TOS to memory before loading a new
  TOS.  This is the universal "make room for a new top" idiom.
- **`mov rdi, [rbp]`** brings the under-TOS value back to the
  register cache.

## Concepts carried in

- The data-stack model and the entry-point initialisation from Ch 13.

## Concepts deferred

- Arithmetic and logic primitives — Ch 15.
- I/O primitives that use `rsi` for buffer addresses — Ch 16.

## Section plan

1. **Conventions recap.**  Sketch the data-stack layout on paper:
   `rbp` points at the cell below TOS; `rdi` holds TOS; pushing means
   `sub rbp, 8 ; mov [rbp], rdi ; mov rdi, new-TOS`.
2. **`dup` in three bytes.**  `48 83 ED 08` (sub rbp, 8) and `48 89
   7D 00` (mov [rbp+0], rdi) and `C3` (ret).  9 bytes total.  Walk
   it: TOS stays in `rdi`; we just spill it.
3. **`drop` in three bytes.**  `48 8B 7D 00` (mov rdi, [rbp+0]) and
   `48 83 C5 08` (add rbp, 8) and `C3` (ret).  9 bytes.  Pop the
   under-TOS into `rdi`; advance `rbp`.
4. **`swap` in four bytes.**  Load under-TOS into temp (`rax`),
   write `rdi` to that slot, copy `rax` to `rdi`.  Trace the
   register dance.
5. **`>r` and `r>` are not data-stack ops at all.**  They move
   between the data stack (`rbp`) and the *return* stack (the x86
   call stack accessed by `push` / `pop`).  Read the bytes carefully
   — `pop rax ; push rdi ; pop rax`... explain each step.
6. **`@`, `!`, `c@`, `c!`.**  TOS is an address.  `@` reads 8 bytes
   from it; `!` writes 8.  `c@` reads 1 byte (zero-extending); `c!`
   writes 1.  Note that the in-register cache (`rdi`) gets reused
   for both the address-in and the value-out.

## Canonical chunks

This chapter introduces the chunks:

- `<<dup-code>>` — `dup_code @ 0x13B`, 9 bytes.
- `<<drop-code>>` — `drop_code @ 0x144`, 9 bytes.
- `<<swap-code>>` — `swap_code @ 0x14D`, 12 bytes.
- `<<to-r-code>>` — `to_r_code @ 0x159`, 12 bytes.
- `<<r-from-code>>` — `r_from_code @ 0x165`, 12 bytes.
- `<<fetch-code>>` — `fetch_code @ 0x171`, 4 bytes.
- `<<store-code>>` — `store_code @ 0x175`, 20 bytes.
- `<<cfetch-code>>` — `cfetch_code @ 0x189`, 5 bytes.
- `<<cstore-code>>` — `cstore_code @ 0x18E`, 19 bytes.

This chapter also appends to the root block a fenced
`file=000-seed.hex0` line containing the `<<name>>` references in
the order they appear above (matching source-file order).

## Try it

```sh
./build.sh
echo "[lit] 65 [lit] 66 swap emit emit bye" | ./seed-forth
# prints "AB" because swap reverses the push order
```

For each primitive you've read, write a one-line shell test that
exercises it and predict the output before running.

## Exercises

1. `dup_code` is 9 bytes.  Write the equivalent of a primitive
   `2dup_code` (duplicate the top *two* cells, leaving 4 on the
   stack).  How many bytes?  Compare to `: 2dup over over ;`
   compiled at runtime.

2. `c!` writes only the low byte of TOS.  The high 7 bytes of `rdi`
   are not preserved — they hold the *next* TOS after `add rbp, 8`.
   Trace this: after `5 6 c!`, what's the new TOS?

3. Why does `>r` need to first `pop rax` (the return address) before
   touching `rdi`?  What would happen if it didn't?

4. Modify a copy of `000-seed.hex0` to add a hypothetical `nip`
   primitive (effect: `( a b -- b )`).  How many bytes?  Is it
   smaller than the Forth-level `: nip swap drop ;` after
   compilation?

## Takeaways

- The data-stack-in-register-cache convention costs about 9 bytes
  per push/pop primitive — half a cache line for the smallest
  primitive.
- Every primitive ends in `C3` (ret).  Calls go through `CALL
  rel32`, so callee addresses must be known at hex-assembly time.
- `>r` and `r>` bridge the data and return stacks by going through
  `rax` and the x86 `push`/`pop`.

Next: Chapter 15 — Arithmetic, Logic, Comparison.
