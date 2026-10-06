# Arithmetic in instruction bytes: hints and solutions

Return to [Chapter 13](../chapters/13-arithmetic-in-instruction-bytes.md).
These are checked manual derivations for the pinned Linux/x86-64 seed, not
observed executions. Instruction offsets are hexadecimal. Logical stack top
is at the right; `M=2^64`, `U=M-1`, and `H=2^63`. Memory accesses and return
addresses satisfy the chapter's stated preconditions unless a problem
explicitly violates one.

Try the first hint for orientation, then the second for a concrete step.
The worked solution is available whenever useful. After reading feedback,
close it and try the changed case; distinguish a result you can reproduce
independently from one you can follow with the answer beside it.

## S13-01 — Track the consumed slot

**Hint 1.** Separate the input arithmetic from the pointer arithmetic. The
old lower operand remains in memory even when it stops being a live item.

**Hint 2.** `U+1` is `M`, so its low 64 bits are zero. The next ADD computes
`0x1000+8`, not another sum of Forth operands.

**Worked solution.** For addition, `[0x1000]=U` and `[0x1008]=99` throughout:

| Completed instruction | `rdi` | `rbp` | Relevant status |
|---|---|---|---|
| Entry | 1 | `0x1000` | Incoming flags are irrelevant |
| `01B7: add rdi,[rbp]` | 0 | `0x1000` | ZF=1; carry out gives CF=1 |
| `01BB: add rbp,8` | 0 | `0x1008` | Pointer result is nonzero: ZF=0; CF=0 |
| `01BF: ret` | 0 | `0x1008` | Return to K; these data values do not change |

The final logical stack is `[99,0]`. At the successful return, `[rbp]=99`;
`U` at the lower address is outside the live stack. No data-memory bytes
were erased or overwritten. RET reads the call's return destination and
advances `rsp` by eight; it does not erase that memory either.

After return, ZF=0 reflects the pointer increment. Treating it as the answer
to “was the sum zero?” would be wrong. The sum is still the zero cell in
`rdi`, and `0=` would test it afresh. Signed overflow is a different flag:
this `U+1` pattern is signed `-1+1`, which fits. Carry and signed overflow
must not be used as interchangeable names.

For NAND, the memory input at `0x1000` is twelve:

| Completed instruction | `rdi` | `rbp` |
|---|---|---|
| Entry | `0x000000000000000A` | `0x1000` |
| `01CE: and rdi,[rbp]` | `0x0000000000000008` | `0x1000` |
| `01D2: not rdi` | `0xFFFFFFFFFFFFFFF7` | `0x1000` |
| `01D5: add rbp,8` | `0xFFFFFFFFFFFFFFF7` | `0x1008` |
| `01D9: ret` | `0xFFFFFFFFFFFFFFF7` | `0x1008` |

The result is `[99,U-8]`. Neither the twelve nor the older 99 was overwritten.
The input twelve is no longer live after the pointer advances; the older 99
is still the next stack value.

**Wrong path to diagnose.** Returning `rdi=7` for NAND silently changed the
width to four bits. Returning `rbp=0x1010` dropped an additional older item.
The low four result bits are seven, but the word operates on a full cell and
consumes exactly one memory-backed operand.

**Changed case.** Independently use addition with `[0x1000]=H-1`, `rdi=1`.
Predict before checking: the arithmetic result is `H`, CF=0, and OF=1 at
`01B7`, because the signed positive sum exceeds `H-1`. The pointer ADD then
replaces those status answers. The final stack is `[99,H]`, with
`rbp=0x1008`. This time there is signed overflow without unsigned carry.

## S13-02 — Diagnose two zero-test edits

**Hint 1.** Write all 64 bits, or all sixteen hexadecimal digits, after each
partial-register operation. Name the register a byte write actually touches.

**Hint 2.** `0x100` has zero in its low byte but a one in bit eight. TEST
examines that bit too; SETE does not overwrite it. Without the `40` prefix,
SETE's target would be part of `rbx` instead of part of `rdi`.

**Worked solution.** In the actual body, starting from `[99,0x100]`:

```text
01E6 TEST:   rdi = 0000000000000100, ZF=0
01E9 SETE:   rdi = 0000000000000100, dil=0
01ED MOVZX:  rdi = 0000000000000000
01F1 NEG:    rdi = 0000000000000000
01F4 RET:    logical stack [99,0]
```

`rbp=P` and `[P]=99` throughout. The first SETE line has not malfunctioned:
it wrote exactly the promised byte. MOVZX supplies the missing whole-register
normalization before NEG.

In the variant without MOVZX, the first divergence from the correct
normalization occurs where that instruction was removed. SETE still leaves
`rdi=0x100`; the next NEG then yields `M-256`, or `0xFFFFFFFFFFFFFF00`.
The returned stack would be `[99,M-256]`. This is both nonzero and different
from `U`, so it fails the required false answer and the canonical-flag
contract. An input of five has no old high bits. SETE clears its low byte,
making the whole register zero even without MOVZX; that example hides the
omission.

For the separate missing-REX variant, start with input zero. TEST correctly
sets ZF=1. The changed bytes `0F 94 C7` mean `sete bh`: they set bits 8–15 of
`rbx` to the byte one, preserving its other bits. This is the first incorrect
register effect. `rdi` remains zero. The unchanged MOVZX reads `dil=0` and
writes whole-register zero; NEG keeps zero. The returned stack would be
`[99,0]`, although input zero requires `[99,U]`. The variant also changes a
register that the real body does not touch.

**Wrong path to diagnose.** “SETcc only writes a byte, so it only tests a
byte” confuses the destination width with the earlier TEST's width. SETE
reads ZF from the full-register TEST. “REX has no bits set, so it has no
effect” confuses its option bits with its presence.

**Changed case.** Try input `0x101` with the real body and with the
missing-MOVZX variant. SETE first changes the register to `0x100` in both.
The real body then yields zero; the variant yields `M-256`. In contrast,
input `0xFF` again hides the omission because SETE clears its only nonzero
byte. Testing many small inputs is not a substitute for selecting a case
that carries information in the untouched high bits.

## S13-03 — Complete and bound division

**Hint 1.** At DIV, the numerator is in two implicit registers. The explicit
operand `rdi` is still the divisor, not the quotient destination.

**Hint 2.** Check `100 = 7*13+9`. Pointer movement and copying `rax` to `rdi`
happen after DIV. For the bound, use `b>=1` and `a<=U`.

**Worked solution.** Starting with `rbp=P`, `[P]=100`, `[P+8]=99`, and
`rdi=13`, the MOV at `0200` sets `rax=100`; the XOR at `0204` sets `rdx=0`.
Immediately after DIV at `0207`, the requested blanks are:

```text
rax=7, rdx=9, rdi=13, rbp=P
```

At `020A`, `rbp=P+8`. At `020E`, `rdi=7`. At `0211`, RET resumes at K and
advances `rsp` by eight, leaving data stack `[99,7]`. The scratch register
`rdx` still contains nine immediately afterward, but no operation pushed a
second data item or made it the cached top. The word's public result is the
quotient alone.

For every valid input, the physical 128-bit dividend has numeric value
`0*M+a=a`. If `1<=b<=U`, then `0<=floor(a/b)<=a<=U`. Thus the quotient is
representable in its 64-bit destination. This argument excludes quotient
overflow under the body's actual preparation, not under every possible
use of the DIV instruction.

With divisor zero, DIV faults at `0207`, after the operand load and clearing
of `rdx`, before the pointer increment. There is no successful return or
recoverable Forth flag to put in a final-stack picture.

With the hypothetical stale state `rdx=1`, `rax=0`, `rdi=1`, the dividend
would be `1*M+0=M`. Its quotient is `M`, larger than the greatest 64-bit
unsigned value `U`, so DIV faults for quotient overflow. A nonzero divisor
alone is not sufficient once the zero-high-half premise is removed.

**Wrong path to diagnose.** Labeling `RDX:RAX` as a “64-bit dividend” hides
why stale RDX is dangerous. Its physical width is 128 bits; this source
constrains its value to the 64-bit range. A second error is swapping the
Forth operands: `[100,13]` supplies one hundred divided by thirteen.

**Changed case.** Compare successful inputs `[99,U,1]`, `[99,U,U]`, and
`[99,0,H]`. Their quotient/remainder pairs are `(U,0)`, `(1,0)`, and `(0,0)`.
All fit the same bound; their final stacks retain only the quotient. The
first exercises the maximum permitted quotient, not an overflow.

## S13-04 — Separate product bits from interpretation

**Hint 1.** The first MOV copies the top operand to `rax`. This IMUL form
keeps only the low 64 bits, and a later MOV publishes them in `rdi`.

**Hint 2.** Under unsigned interpretation, `U*2=2M-2`. Under signed
interpretation, the first factor is -1. Subtracting one whole multiple of
`M` does not change the retained pattern.

**Worked solution.** Start with `rdi=2`, `rbp=P`, `[P]=U`, and `[P+8]=99`:

| Completed instruction | `rax` | `rdi` | `rbp` |
|---|---|---|---|
| `021D: mov rax,rdi` | 2 | 2 | P |
| `0220: imul rax,[rbp]` | M-2 | 2 | P |
| `0225: add rbp,8` | M-2 | 2 | P+8 |
| `0229: mov rdi,rax` | M-2 | M-2 | P+8 |
| `022C: ret` | M-2 | M-2 | P+8 |

The result is `[99,M-2]`, with `M-2=0xFFFFFFFFFFFFFFFE`. The full unsigned
product is `2M-2`; the full signed product is -2. Their difference is `2M`,
a multiple of the modulus, so their low 64 bits agree.

Signed -2 fits, so IMUL's CF and OF are clear immediately after IMUL. The
unsigned mathematical product exceeds `U` and has a nonzero upper half.
Thus these flags do not answer whether that unsigned product needed more
than one cell. The subsequent pointer ADD replaces the arithmetic flags
before the primitive returns anyway. Neither the high half nor overflow
status is supplied as another Forth result.

For the hypothetical eight-bit model, `M8=256` and `U8=255`.
Unsigned `255*2=510`; signed `(-1)*2=-2`. Both retain `254`, pattern `0xFE`.
The unsigned high part is one; the signed product fits in `[-128,127]`.
The argument transfers because the two interpretations differ by a multiple
of the **new** modulus. It does not transfer by keeping `M=2^64` in the
calculation. If this model also packed one-byte physical stack cells, the
slot stride would be one; the real body's eight-byte adjustment is not
portable unchanged to that layout.

**Wrong path to diagnose.** “IMUL means signed, so unsigned inputs are
invalid” misses the low-half contract. “Low halves agree, so signed and
unsigned multiplication are identical” extends it too far. Full products,
representable ranges, and overflow meanings still differ.

**Changed case.** In the eight-bit model, multiply `0x80` by two. The full
products are unsigned 256 and signed -256; both retain zero, but neither
fits in its respective one-cell range. Then divide that retained zero by
two: the quotient is zero, not the original pattern `0x80`. Discarding high
bits can destroy the information needed to reverse multiplication.

## S13-05 — Find the composition's boundary

**Hint 1.** Trace what each primitive is asked to do before deciding what
question the final flag answers. A correct sign test of a wrapped result
need not compare the original numbers correctly.

**Hint 2.** Chapter 3's subtraction forms the inverse of `U`, which is one
modulo `M`. Adding that to `H-1` retains `H`.

**Worked solution.** In the library subtraction, the top operand's
complement is zero; adding one forms its modular inverse. The final
addition computes `H-1+1=H`. Expanding the rest of `0<` gives:

```text
original patterns         [H-1, U]
after -                   [H]
after pushing H           [H, H]
after unsigned /          [1]
after first 0=            [0]
after second 0=           [U]
```

The original signed values are `H-1` and -1, so “left is less than right”
is false. Their mathematical signed difference is `H`, outside the signed
cell range. Its stored pattern has the interpretation `-H`, so the valid
sign-extraction routine reports a negative pattern. The final flag is
canonical but wrong for the proposed signed-order question. No primitive
violated its own contract.

Equality uses `- 0=`. The same subtraction leaves nonzero `H`, so its flag
is zero: the patterns are unequal. More generally, two representatives in
`0..M-1` can have a difference congruent to zero modulo `M` only if they are
equal, since their difference lies strictly between `-M` and `M`. Signed
ordering cannot use that all-cell argument; its subtraction must retain
the sign of the mathematical signed difference.

In the eight-bit case, `M8=256`, `H8=128`, and `U8=255`:

```text
original patterns         [127, 255]       signed: [127, -1]
after -                   [128]            signed: -128
after pushing H8 and /    [1]
after first 0=            [0]
after second 0=           [255]
```

The same error appears at the changed boundary. Equality still returns
zero. This is a model of the argument at another width, not an executed
variant of the x86-64 bytes.

**Wrong path to diagnose.** Blaming DIV for signed-division behavior gets
the mechanism backward: DIV deliberately interprets the pattern as unsigned
to read its top bit. The incorrect ordering inference began when a wrapped
subtraction's sign was treated as the mathematical difference's sign.

**Changed case.** Return to real 64-bit cells and compare seven with two,
then two with seven. The differences are five and `M-5`, with signed
interpretations five and -5. Division by H gives zero and one; the two
zero tests produce zero and `U`, respectively. Both mathematical differences
fit, so both signed-order answers are correct. Explain the bound before
using this success to generalize to another pair.

## What this feedback checks

You have accounted for the five byte-bounded bodies, their live-stack
changes, canonical-flag construction, and the limits of their arithmetic
contracts. The worked answers provide audit criteria, not evidence that
the seed ran or that a reader can yet explain every case independently.
For a fresh attempt, choose a body, cover its trace, and predict one boundary
input while preserving an older stack value.
