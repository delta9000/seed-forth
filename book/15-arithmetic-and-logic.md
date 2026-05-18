# Chapter 15 — Arithmetic, Logic, Comparison

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read the x86-64 encoding of `+`, `nand`, `0=`, `/`, `*` byte for
  byte;
- explain why `/` is unsigned (`DIV` not `IDIV`) and what that buys
  us for Ch 7's signed-comparison trick;
- predict the bytes that `nand` produces from two specific 64-bit
  inputs.

## Source coverage

`000-seed.hex0` lines roughly 153–200 plus the `/` and `*`
primitives further down.  Five primitive bodies: `plus_code @
0x1A1`, `nand_code @ 0x1AA`, `zeq_code @ 0x1B6`, the `/_code`
primitive, and the `*_code` primitive.

## Concepts introduced

- **In-place arithmetic on the TOS register.**  `+` is `mov rax,
  [rbp]; add rdi, rax; add rbp, 8` — operates on `rdi` directly.
- **`NAND` as `AND` + `NOT`.**  x86 has no NAND; the seed emits
  `and rdi, rax; not rdi`.
- **`0=` is conditional-set-to-zero.**  Read the `test rdi, rdi;
  sete al; ...` idiom and the small canonicalisation that turns
  `0`/`1` into `-1`/`0`.
- **Unsigned `DIV` clears `rdx` first.**  The 64-by-64 unsigned
  divide on x86 takes the dividend in `rdx:rax` (128 bits!).  The
  seed always zeroes `rdx` to keep the high half empty.

## Concepts carried in

- Stack convention from Ch 14.

## Concepts deferred

- How the Forth-level `-` (Ch 4) chains `nand`+`+` — already covered
  in Part I; this chapter focuses on the primitives below them.

## Section plan

1. **`+` in 9 bytes.**  Load under-TOS to `rax`; add to `rdi`; pop
   the slot.  Net: TOS = TOS + 2OS.
2. **`nand` in 12 bytes.**  `and rdi, [rbp]; not rdi; add rbp, 8`.
   Note that `not` is one-byte `F7 D7`.
3. **`0=` in 15 bytes.**  `test rdi, rdi; sete al; movzx rdi, al;
   neg rdi`.  The `neg` converts `0/1` to `0/-1` (Forth boolean).
4. **`/` and the `DIV` instruction.**  x86's `DIV r/m64` divides
   `RDX:RAX` by the operand; quotient into `RAX`, remainder into
   `RDX`.  The seed's `/_code` clears `rdx`, loads dividend from
   `[rbp]`, divides, returns quotient in `rdi`.
5. **`*` and the `MUL` instruction.**  Symmetric to `DIV`: `RAX *
   r/m64` produces 128-bit result in `RDX:RAX`.  The seed keeps only
   the low half (`rax`) — overflow silently discarded.

## Canonical chunks

- `<<plus-code>>` — 9 bytes at `0x1A1`.
- `<<nand-code>>` — 12 bytes at `0x1AA`.
- `<<zeq-code>>` — 15 bytes at `0x1B6`.
- `<<div-code>>` — `/_code`, roughly 20 bytes.
- `<<mul-code>>` — `*_code`, roughly 15 bytes.

Append references to the root block in source-file order.

## Try it

```sh
./build.sh
echo "[lit] 7 [lit] 5 + [lit] 48 + emit bye" | ./seed-forth
# 7+5=12, +48='<', so prints "<"
echo "[lit] 100 [lit] 13 / [lit] 48 + emit bye" | ./seed-forth
# 100/13=7, +48='7', prints "7"
```

## Exercises

1. `+` doesn't check for carry — overflow wraps silently.  Construct
   an input that overflows the 64-bit positive range and confirm the
   wrap behaviour.

2. `*` ignores `rdx` (the high 64 bits of the 128-bit product).
   Construct an input where this matters.  Why doesn't the C
   compiler care?

3. The `/` primitive doesn't handle divide-by-zero (the CPU traps).
   Why doesn't the seed expose `0/?` checking?  (Hint: how often
   does the Forth-level code actually need to divide by a value it
   doesn't trust?)

4. Add a `mod` primitive (`u1 u2 -- u1 mod u2`) to a copy of
   `000-seed.hex0`.  It's almost identical to `/`; what changes?

## Takeaways

- All five arithmetic primitives operate in-register on `rdi`,
  loading their second argument from `[rbp]` and popping that slot.
- Unsigned division is what makes Ch 7's sign-bit trick work, and
  it's what x86 gives you most directly (`DIV`).
- The primitives are silent about overflow and divide-by-zero —
  the seed trusts the caller, and seedforth's only caller is
  `010-lib.fth`.

Next: Chapter 16 — I/O: `emit`, `key`, `syscall6`.
