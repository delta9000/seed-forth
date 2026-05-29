# Chapter 15 — Arithmetic, Logic, Comparison

```text
Missing capability: +, nand, 0=, /, * were black boxes.
New pattern: each primitive reads [rbp], modifies rdi in place, advances rbp, and returns.
Artifact after this chapter: the arithmetic and logic primitives' machine code (54 bytes total).
Proof link: the *unsigned* division and sign-extraction here are exactly what Ch 7's comparisons rest on.
```

The arithmetic primitives are *small*.  `plus_code`, `nand_code`,
and `zeq_code` sit at lines 153–170 of `000-seed.hex0`; `divide_code`,
the `/` dictionary entry, and `star_code` are tucked further down at
lines 649–683 (with `r_at_code`, the stack op already covered in
Ch 14, sandwiched between them in source order).  Together they
encode `+`, `nand`, `0=`, `/`, and `*` in 54 bytes total: every
primitive reads `[rbp]`, modifies `rdi` in place, advances `rbp`,
and returns.  Open `000-seed.hex0` to lines 153–170 and 649–683 with
Ch 14's data-stack convention (`rdi` = TOS, `[rbp]` = under-TOS) in
mind.

By the end you'll be able to read the x86-64 encoding of `+`,
`nand`, `0=`, `/`, and `*` byte for byte, explain why `/` is
*unsigned* (`DIV` rather than `IDIV`) and what that choice buys us
for Ch 7's signed-comparison trick, and predict the bytes that
`nand` and `+` will produce from any two 64-bit inputs.  The
Forth-level wrappers that chain these primitives, like `-` (which
chains `nand` and `+`) and the comparison operators that lean on
unsigned `DIV` to extract a sign bit, are already covered in Chs 4
and 7; this chapter stays at the machine-code layer below them.

---

The arithmetic primitives are *small*.  `+` and `nand` are 9 and 12
bytes each; `0=` is 15; `divide_code` and `star_code` are 10 and 8.
That's 54 bytes for the entire arithmetic-and-logic core.  All of
them follow the same pattern as the stack primitives in Ch 14 —
read `[rbp]`, modify `rdi`, advance `rbp` — with one extra step in
the middle that actually computes something.

## 1. `+` in 9 bytes

```hex0 chunk=plus-code
;; ----- plus_code @ 0x1A1 -----
48 03 7D 00
48 83 C5 08
C3

```

```
48 03 7D 00      add rdi, [rbp]   ; TOS += under-TOS
48 83 C5 08      add rbp, 8       ; pop the under-TOS slot
C3               ret
```

The whole add is one instruction: `ADD r64, r/m64`.  No temporary
register; no spill; the sum lands in `rdi` and the consumed slot is
released.

Overflow wraps silently in twos-complement.  The CPU sets `OF` (the
overflow flag), but the seed never reads it.  This is fine for
unsigned arithmetic and fine for signed arithmetic *as long as you
don't care about overflow*.  The Forth-level `-` (Ch 4) uses `+`
under the hood, so two's-complement wrap is what makes `a - b ==
a + (-b)` work without any extra checks.

## 2. `nand` in 12 bytes

```hex0 chunk=nand-code
;; ----- nand_code @ 0x1AA -----
48 23 7D 00
48 F7 D7
48 83 C5 08
C3

```

x86 has `AND`, `OR`, `XOR`, and `NOT`, but no `NAND`.  The seed
synthesises NAND as AND-then-NOT:

```
48 23 7D 00      and rdi, [rbp]   ; rdi = rdi AND under-TOS
48 F7 D7         not rdi          ; rdi = ~rdi
48 83 C5 08      add rbp, 8       ; pop the slot
C3               ret
```

`NOT r/m64` is one of the few x86 instructions that operates on a
single register with no second operand — it just flips every bit.
Cost: 3 bytes (REX + opcode + ModR/M).

This is exactly the primitive that made Ch 3 — "Logic from one
primitive" — possible.  At the Forth layer we built `and`, `or`,
`not`, and `xor` out of `nand` and `dup`.  Now we see what those
Forth definitions *compile to*: a `CALL` to the 12 bytes above,
preceded and followed by whatever stack-shuffling `dup nand` etc.
expand to.

## 3. `0=` in 15 bytes

```hex0 chunk=zeq-code
;; ----- zeq_code @ 0x1B6 -----
48 85 FF
40 0F 94 C7
48 0F B6 FF
48 F7 DF
C3

```

`0=` returns Forth-canonical `-1` if its input is zero, `0`
otherwise.  Four instructions:

```
48 85 FF         test rdi, rdi    ; sets ZF if rdi == 0
40 0F 94 C7      sete dil         ; dil = (ZF ? 1 : 0)
48 0F B6 FF      movzx rdi, dil   ; zero-extend dil into rdi
48 F7 DF         neg rdi          ; 0 → 0, 1 → -1
C3               ret
```

The dance is necessary because `SETcc` only writes one byte (the
low byte of a register), so we have to clear the high 56 bits with
`MOVZX` and then negate to land on Forth's `-1` convention.  `neg
rdi` is the cheapest way to turn `0/1` into `0/-1`: `-0 == 0` and
`-1 == 0xFFFFFFFFFFFFFFFF` in twos-complement.

If you wondered in Ch 6 why `digit?` returned `-1`/`0` rather than
`1`/`0` — this is why.  The seed's only equality primitive emits
that convention, and every higher layer keeps it.

The `40` prefix on `sete dil` is a *REX prefix with no bits set*.
On x86-64, accessing the low byte of `rdi` (named `dil`) requires
this prefix; without it, the encoding would target the legacy
register `bh`, which doesn't make sense here.

## 4. `/` and the `DIV` instruction

```hex0 chunk=divide-code
;; ----- divide_code @ 0x710 ( a b -- a/b ) unsigned 64-bit divide -----
;; rdx:rax / rdi → rax=quot, rdx=rem.  We treat dividend as 64-bit
;; (rdx zeroed) — divide-by-zero traps the process; that's acceptable for now.
48 8B 45 00                               ; mov rax, [rbp]   ; rax = a (dividend)
48 31 D2                                  ; xor rdx, rdx     ; high half = 0
48 F7 F7                                  ; div rdi          ; rdx:rax / rdi
48 83 C5 08                               ; add rbp, 8        ; pop a
48 89 C7                                  ; mov rdi, rax     ; TOS = quot
C3                                        ; ret

```

x86's `DIV r/m64` is awkward: the dividend is 128 bits, sitting in
the `rdx:rax` register pair, and the divisor is the 64-bit operand.
The quotient lands in `rax`; the remainder lands in `rdx`.

We don't need a 128-bit dividend, so we zero `rdx` first.  After
that, `rdx:rax / rdi` is the same as `rax / rdi` for unsigned
inputs.

```
mov rax, [rbp]   ; rax = a (under-TOS, the dividend)
xor rdx, rdx     ; rdx = 0 (high half of dividend)
div rdi          ; rax = a / b, rdx = a mod b
add rbp, 8       ; pop a's slot
mov rdi, rax     ; new TOS = quotient
ret
```

Note: **unsigned**.  `DIV` interprets both operands as unsigned
64-bit integers.  If you pass a negative dividend (in two's-
complement, the high bit set), `DIV` treats it as a huge positive
number — and that is exactly the behaviour Ch 7 leans on to extract
the sign bit (`(n + 2^63) / 2^64`, computed as `n / 2^63` with
unsigned division).  Signed division (`IDIV`) would defeat that
trick.

Divide by zero raises `#DE` and the kernel kills the process with
`SIGFPE`.  The seed does not check; the C compiler (Part III) does
not check either.  Callers are expected to know.

The `/` dictionary entry follows immediately:

```hex0 chunk=divide-dict
;; --- / @ 0x722 (xt = 0x72D) ---
F9 06 40 00 00 00 00 00                     ; link = 0x4006F9 (syscall6)
00                                        ; flags
01                                        ; nlen
2F                                        ; "/"
E9 DE FF FF FF                              ; jmp divide_code (rel = 0x710 - 0x732 = -34)

```

The dictionary entry layout (`link / flags / nlen / name / jmp body`)
is the same shape we'll spell out in Ch 17.  Here it's worth pointing
out only that `/` sits in source order *after* `syscall6`'s entry,
and chains backwards through `link = 0x4006F9` (the syscall6 entry
address).

## 5. `*` and the `IMUL` instruction

```hex0 chunk=star-code
;; ----- star_code @ 0x743 ( a b -- a*b ) signed 64-bit multiply -----
;; b is in TOS (rdi); a is at [rbp]. Result low half in rax -> TOS.
48 89 F8                                  ; mov rax, rdi       ; rax = b
48 0F AF 45 00                            ; imul rax, [rbp]    ; signed 64x64->64 (low half)
48 83 C5 08                               ; add rbp, 8         ; pop a
48 89 C7                                  ; mov rdi, rax       ; new TOS = a*b
C3                                        ; ret

```

`IMUL r64, r/m64` is the two-operand form: `rax *= [rbp]`,
discarding the high 64 bits of the 128-bit product.  Signed or
unsigned doesn't matter for the low half — they agree.

The high half *is* lost.  If you multiply two 33-bit positive
integers, the true product has 66 bits and the top two are gone.
For the C compiler in Part III this is acceptable: the language's
`int` is 64-bit and overflow is undefined.

There is no `*` dictionary entry yet in the source range we're
reading; it sits near the end of the file along with the other
late additions (`r@`, `state`, `latest`, `'`).  We'll meet it in
Ch 17 as part of the `<<late-dicts>>` chunk.

## 6. What's not here

The seed exposes five arithmetic primitives.  It does *not* have:

- `MOD` — derivable from `/`: `: mod  2dup / * - ;`.
- `>` or `<` or any signed comparison primitive — Ch 7 builds them
  from `-` and the unsigned-`/` sign-bit trick.
- shift operators (`SHL`, `SHR`, `SAR`) — the seed doesn't need
  them; the C compiler emits them inline.
- bitwise OR, AND, XOR as separate primitives — Ch 3 derived them
  from `nand`.

Every omission saves about 10 + name-length bytes of dictionary
header plus a primitive body of 8–15 bytes.  Five omissions ≈
100 bytes saved.

The pattern from Ch 3 holds: keep the *one* primitive that lets you
build the rest, and pay for the rest with Forth-level definitions
whose runtime cost is incurred only when they are actually called.

## Try it

```sh
./build.sh
echo "[lit] 7 [lit] 5 + [lit] 48 + emit bye" | ./seed-forth
# 7+5=12, +48 = ASCII '<', prints "<"

echo "[lit] 100 [lit] 13 / [lit] 48 + emit bye" | ./seed-forth
# 100/13=7, +48 = '7', prints "7"

echo "[lit] 6 [lit] 7 * [lit] 48 + emit bye" | ./seed-forth
# 6*7=42, +48 = 'Z' (ASCII 90 = 'Z'), prints "Z"

{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo "[lit] 0 0= [lit] 48 - emit bye"
} | grep -v '^[[:space:]]*$' | ./seed-forth
# 0= on 0 returns -1 (the canonical Forth true).  Library-level `-`
# (Ch 4) computes -1 - 48 = -49; emit's low byte is 0xCF — non-printable,
# so spot it with `| xxd | head -1`.
```

## Exercises

1. **★★ Verify.** `+` doesn't check for carry — overflow wraps silently.  Construct
   an input that overflows the 64-bit *signed* range (positive →
   negative) and confirm the result by emitting the high bit as a
   character.

2. **★★ Trace.** `*` ignores the high 64 bits of the 128-bit product.  Construct
   an input pair where this matters (i.e., the true product would
   exceed 64 bits).  Why doesn't the C compiler care about this in
   practice?

3. **★ Trace.** The `/` primitive doesn't handle divide-by-zero (the CPU traps,
   the kernel sends `SIGFPE`).  Why doesn't the seed expose a
   `?divide` checker?  (Hint: how often does the Forth-level code
   actually need to divide by an untrusted value?)

4. **★★★ Extend.** Add a `mod` primitive (`u1 u2 -- u1 mod u2`) to a copy of
   `000-seed.hex0`.  It's almost identical to `divide_code`; what
   one byte changes?  (Hint: `rdx`, not `rax`, holds the remainder
   after `DIV`.)

5. **★★★ Verify.** The `40` prefix on `sete dil` puzzled some readers.  Try
   assembling `sete bh` (no prefix) and `sete dil` (with the `40`
   prefix) using `nasm` or `as`; compare the encodings.  Why does
   the seed need the prefix?

## Takeaways

- All five arithmetic primitives operate in-register on `rdi`,
  loading their second argument from `[rbp]` and popping that slot
  — no scratch register except for `*` and `/`, which need `rax`
  (because `IMUL` and `DIV` use it implicitly).
- Unsigned division is what makes Ch 7's sign-bit trick work, and
  it's what x86 gives you most cheaply (`DIV`).
- The primitives are silent about overflow and divide-by-zero —
  the seed trusts the caller, and its only caller is
  `010-lib.fth` (plus, eventually, the C compiler emitting code).

Next: Chapter 16 — I/O: `emit`, `key`, `syscall6`.
