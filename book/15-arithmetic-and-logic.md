# Chapter 15 — Arithmetic, Logic, Comparison

```text
Missing capability: +, nand, 0=, /, * were black boxes.
New pattern: each binary primitive reads [rbp], modifies rdi in place, advances rbp, and returns.
Artifact after this chapter: the arithmetic and logic primitives' machine code (70 bytes total).
Proof link: the *unsigned* division and sign-extraction here are exactly what Ch 7's comparisons rest on.
```

x86-64 has `AND`, `OR`, `XOR` and `NOT` instructions.  It has no
`NAND`.  Yet `nand` is the seed's only logic primitive, and Ch 3
rebuilt `and`, `or`, `xor` and `not` on top of it in Forth.  So the
seed synthesises the one operation the CPU lacks, then derives the
four it has.  The reason is the budget: every primitive costs a
body *and* a dictionary entry, and one functionally complete
operation buys all four others for the price of one.

The second choice is quieter.  Ch 7 got signed comparisons out of
division, and that only works because the seed's `/` is *unsigned*
(`DIV`, not `IDIV`).  This chapter opens both, along with `+`, `0=`
and `*`: 70 bytes of x86-64 in total.  `+` and `nand` are 9 and 12
bytes, `0=` is 15, and `divide_code` and `star_code` are 18 and 16.
`plus_code`, `nand_code` and `zeq_code` are at lines 153–170 of
`000-seed.hex0`; `divide_code`, the `/` dictionary entry and
`star_code` are at lines 649–683, with Ch 14's `r_at_code` between
them.  Each binary primitive follows Ch 14's pattern with one
computing step in the middle: read the second operand from `[rbp]`,
combine it into `rdi`, release the slot, return.

## 1. `+` in 9 bytes

```hex0 chunk=plus-code
;; ----- plus_code @ 0x1A1 -----
48 03 7D 00
48 83 C5 08
C3

```

Decoded:

```
48 03 7D 00      add rdi, [rbp]   ; TOS += under-TOS
48 83 C5 08      add rbp, 8       ; pop the under-TOS slot
C3               ret
```

The whole add is one instruction, `ADD r64, r/m64`, with no
temporary register and no spill.

Overflow wraps silently in two's complement; the CPU sets `OF`, but
the seed never reads it.  The Forth-level `-` (Ch 4) is `+` under
the hood, and that wrap is what makes `a - b == a + (-b)` work
without any extra checks.

## 2. `nand` in 12 bytes

```hex0 chunk=nand-code
;; ----- nand_code @ 0x1AA -----
48 23 7D 00
48 F7 D7
48 83 C5 08
C3

```

With no `NAND` instruction to use, the body is AND-then-NOT:

```
48 23 7D 00      and rdi, [rbp]   ; rdi = rdi AND under-TOS
48 F7 D7         not rdi          ; rdi = ~rdi
48 83 C5 08      add rbp, 8       ; pop the slot
C3               ret
```

`NOT r/m64` flips every bit of one register in 3 bytes.  These 12
bytes are what Ch 3 stands on.  The Forth-level `and`,
`or`, `not` and `xor` built there compile to `CALL`s to this body,
surrounded by whatever stack shuffling `dup nand` and friends need.

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

The `40` prefix on `sete dil` is a *REX prefix with no bits set*.
On x86-64, accessing the low byte of `rdi` (named `dil`) requires
this prefix; without it, the same encoding names the legacy
register `bh`.

The `-1` result is why Ch 6's `digit?` returns `-1`/`0` rather than
`1`/`0`: the seed's only equality primitive produces that
convention, and every higher layer keeps it.

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
inputs.  Stripped of its hex, the body reads:

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
number.  That is the behaviour Ch 7 relies on to extract the sign
bit: unsigned `n / 2^63` is `1` when the top bit is set
and `0` when it isn't.  Signed division (`IDIV`) would defeat that
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

Ch 17 explains the entry layout (`link / flags / nlen / name / jmp
body`).  The one thing to note here is that `/` follows `syscall6`'s
entry in the source and links back to it through
`link = 0x4006F9`.

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
discarding the high 64 bits of the 128-bit product.  Signed and
unsigned multiplication agree on the low half, so the distinction
doesn't matter here.  The body routes the product through `rax` by
choice: two-operand `IMUL` works on any register, and
`imul rdi, [rbp]` would do the job in fewer bytes.

The high half *is* lost.  If you multiply two 33-bit positive
integers, the true product has 66 bits and the top two are gone.
For the C compiler in Part III this is acceptable: the language's
`int` is 64-bit and overflow is undefined.

`*`'s dictionary entry is not next to its body.  It sits at the end
of the file with the entries for `r@`, `state`, `latest` and `'`,
in the `<<late-dicts>>` chunk that Ch 17 shows.

## 6. What's not here

The seed exposes five arithmetic primitives.  It does *not* have:

- `MOD`, derivable from `/`: `: mod  2dup / * - ;`.
- `>`, `<` or any signed comparison; Ch 7 builds them from `-` and
  the unsigned-`/` sign-bit trick.
- Shift operators (`SHL`, `SHR`, `SAR`).  The seed doesn't need
  them, and the C compiler emits them inline.
- Bitwise OR, AND and XOR; Ch 3 derives them from `nand`.

Every omission saves a `15 + name-length`-byte dictionary entry
(header plus JMP stub, Appendix A) and a primitive body of 8–15
bytes.  Together they save well over 100 bytes.

This is Ch 3's approach again: keep the one primitive that lets you
build the rest, and write the rest in Forth.

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
# (Ch 4) computes -1 - 48 = -49; emit's low byte is 0xCF, which is
# non-printable, so spot it with `| xxd | head -1`.

echo "[lit] 0 dup nand [lit] 9223372036854775808 / [lit] 48 + emit bye" | ./seed-forth
# prints "1"
echo "[lit] 5 [lit] 9223372036854775808 / [lit] 48 + emit bye" | ./seed-forth
# prints "0"
```

The last two are Ch 7's sign test with nothing in the way.
`[lit] 0 dup nand` is `-1` (all 64 bits set), and
9223372036854775808 is 2^63.  One unsigned `DIV` by 2^63 turns the
top bit into a `1` for the negative number and a `0` for 5.  With
`IDIV`, `-1` divided by that same bit pattern would give `0`, and
`010-lib.fth`'s `<`, defined as `- neg-flag`, would answer false for
nearly every pair where it should answer true.

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

5. **★★★ Verify.** Try assembling `sete bh` (no prefix) and `sete dil` (with the `40`
   prefix) using `nasm` or `as`; compare the encodings.  Why does
   the seed need the prefix?

## Takeaways

- All five primitives work in place on `rdi`, and the four binary
  ones take their second operand from `[rbp]` and release that slot.
- `/` uses unsigned `DIV`, which is both the cheapest x86 division
  and the property Ch 7's sign-bit trick depends on.
- The primitives never check for overflow or divide-by-zero, because
  the seed trusts its callers: `010-lib.fth` and the Forth code of
  the C compiler.

**Running count: 415 of 2,040 bytes read (20%).**  This chapter
added 86: 70 bytes of arithmetic and `/`'s 16-byte dictionary entry.

Everything so far computes on values already on the stack.  None
of it has touched the world outside the process.  The seed contains
exactly four `syscall` instructions, and Ch 16 reads all of them.

Next: Chapter 16 — I/O: `emit`, `key`, `syscall6`.
