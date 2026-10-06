# 13. Arithmetic in instruction bytes

[Previous: Physical stacks and memory](12-physical-stacks-and-memory.md) · [Practice help](../practice/13-solutions.md) · [Remaining route](../../COVERAGE.md)

We have used `+` to add cells and `0=` to make flags. Now inspect an
unexpected difference between them: addition's processor zero flag does not
survive the arithmetic primitive as the answer to “was the sum zero?” Yet
`0=` reliably returns a whole zero or all-ones cell. Which instructions make
those two statements compatible?

This chapter opens five bodies: `+`, `nand`, `0=`, unsigned `/`, and low-half
`*`. By the end, you should be able to account for every instruction's bytes,
trace its registers and stack slots, and explain three boundaries: partial
byte writes, unsigned division, and discarded product bits.

Bring the [instruction-reading key from Chapter 11](11-executable-and-entry.md#a-small-instruction-reading-key) and the cached-top
invariant from [Chapter 12](12-physical-stacks-and-memory.md). We also revisit
[Chapter 3's modular construction](03-bits-and-subtraction.md) and
[Chapter 5's comparison boundary](05-comparisons-and-characters.md). We do
not need to open the input loop or run the seed.

**Evidence boundary.** The source is the Linux/x86-64 seed at
[revision 7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b).
Each decoded listing was checked against its exact source bytes and against
bounded static disassembly with GNU objdump 2.44. The state traces and
boundary arguments are manual derivations. Neither disassembly nor a paper
trace is execution evidence; no seed was executed for this chapter.

## Find your entry point

Before continuing, explain these two transitions:

- With `rdi=b`, `rbp=P`, `[P]=a`, and `[P+8]=99`, where should the result and
  `99` be after a binary word?
- Does writing one byte named `dil` replace every bit of `rdi`?

If the first is uncertain, return to Chapter 12's physical-stack invariant.
If the second is uncertain, keep the full `0=` trace in this chapter. If both
are familiar, scan the five listings, then attempt S13-02 through S13-05.
The division and multiplication bounds still matter when the mnemonics look
familiar. You can inspect one body at a time without memorizing the opcodes.

## One frame for all four binary words

Keep logical stack top at the right. For a starting stack `[99, a, b]`, the
physical state is:

```text
rdi = b              cached top
rbp = P
[P]   = a            next cell below top
[P+8] = 99           older cell
```

Square brackets around an address mean an eight-byte memory value here;
logical stack pictures contain comma-separated values. `P` is a stipulated
valid stack address, not an address to try writing on your machine. Addresses
increase toward older memory-backed entries. Cells and these loads are
64-bit, with little-endian memory representation. The saved dummy below all
logical values is omitted from this local picture; these bodies preserve it.

A successful binary body must leave `rdi=result` and `rbp=P+8`. Consequently,
its new `[rbp]` is the older `99`. None of these four bodies writes the data
stack memory. They read `a` before advancing the pointer. The old bytes for
`a` still exist at `P`, but that slot is outside the new live stack. Consuming
a value does not require erasing its bytes.

Assume sufficient operands and valid storage. These bodies do not check
logical depth. Also assume an ordinary call entered with `rsp=S` and a
valid return destination `K` at `[S]`. None changes `rsp` before its final
`ret`; that instruction resumes at `K` and advances `rsp` to `S+8`. It removes
the call's return destination, not a Forth data operand. These assumptions
let us focus on arithmetic without hiding the return step.

In every listing, the left column gives **half-open hexadecimal file-offset
ranges**, including the start and stopping before the end. Add the seed
mapping base `0x400000` for virtual addresses: offset
`01B7` begins at address `0x4001B7`. Byte counts exclude dictionary headers.
`qword [rbp]` spells an eight-byte access. The source's zero displacement
byte makes `[rbp+0]` equivalent to `[rbp]`; it is still part of the encoding.

## Addition: compute, then release a slot

The [nine-byte `plus_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L196-L199)
starts at virtual address `0x4001B7`:

```text
offset range    bytes             decoded instruction
[01B7,01BB)   48 03 7D 00       add rdi, qword [rbp]
[01BB,01BF)   48 83 C5 08       add rbp, 8
[01BF,01C0)   C3                ret
```

The `48` prefix selects the 64-bit operand width here. In the first line,
`03` selects addition into the register; `7D 00` identifies `rdi` and the
memory operand at `rbp` with a zero displacement. In the second, `08` is an
immediate eight, the size of one memory-backed cell. We must account for
both additions even though only one adds the user's numbers.

Start from `[99, 7, 5]`, so `rdi=5`, `[P]=7`, and `[P+8]=99`:

| After instruction at | `rdi` | `rbp` | Reason |
|---|---:|---|---|
| Entry | 5 | P | Top in register; seven below it |
| `01B7` | 12 | P | Five plus the cell loaded from P |
| `01BB` | 12 | P+8 | Release seven's memory-backed slot |
| `01BF` | 12 | P+8 | Return to K; data state stays `[99, 12]` |

The answer is always the low 64 bits. Write `M=2^64`, `U=M-1`, and
`H=2^63`, as in earlier chapters. Adding `U` and one produces a mathematical
sum of `M` and a stored result of zero. Adding `H-1` and one stores `H`,
whose signed interpretation is `-H`. Those are two interpretations of
wrapping, not two different addition instructions.

The processor does set status flags after `add rdi,[rbp]`: among them, carry
`CF`, signed overflow `OF`, and zero `ZF`. But the next `add rbp,8` sets
arithmetic flags for the **pointer calculation**, overwriting those answers.
For example, with `P=0x1000`, `U+1` first sets ZF because its stored sum is
zero; the pointer result `0x1008` is nonzero. The primitive returns no stable
public arithmetic-status result in those flags. Its Forth result is the cell
in `rdi`. This is why a subsequent `0=` must test that cell itself.

## NAND: two machine operations, one Forth result

The [twelve-byte `nand_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L206-L210)
starts at `0x4001CE`:

```text
offset range    bytes             decoded instruction
[01CE,01D2)   48 23 7D 00       and rdi, qword [rbp]
[01D2,01D5)   48 F7 D7          not rdi
[01D5,01D9)   48 83 C5 08       add rbp, 8
[01D9,01DA)   C3                ret
```

Compare its first line with addition. The operands and addressing bytes are
the same; opcode `23` asks for AND instead. The next instruction complements
the complete register. This is the meaning of NAND: retain the positions
where both inputs have ones, then flip all positions.

For `[99, 12, 10]`, predict the low four bits, but keep the actual width at
64 bits throughout:

| After instruction at | `rdi` | `rbp` | What the value means |
|---|---|---|---|
| Entry | `0x000000000000000A` | P | Ten, with `[P]=12` |
| `01CE` | `0x0000000000000008` | P | `1100 AND 1010` gives `1000` in the low nibble |
| `01D2` | `0xFFFFFFFFFFFFFFF7` | P | Complement all 64 bits: `U-8` |
| `01D5` | `0xFFFFFFFFFFFFFFF7` | P+8 | Older 99 is now at `[rbp]` |
| `01D9` | `0xFFFFFFFFFFFFFFF7` | P+8 | Return with logical stack `[99, U-8]` |

The leading ones distinguish the real result from the four-bit teaching
answer seven. NAND is not a whole-value truth test: two nonzero inputs can
have no common one bits. For example, two and four produce `U` here.

This body supplies the bitwise contract used in Chapter 3. `dup nand`
complements a cell; `nand dup nand` removes NAND's complement to form AND.
Combined with wrapping addition, it also supplies the inverse `~b+1` used
by subtraction. That connection follows from the values and stack effects
we just traced. It makes no claim that NAND is the uniquely smallest design
choice or that a derived word has a particular execution time.

## Zero test: a one-byte answer becomes a whole-cell flag

The [fifteen-byte `zeq_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L217-L222)
starts at `0x4001E6`. Unlike the other four words, its contract is unary:
`( n -- flag )`. From `[99,n]`, `rdi=n` and `[rbp]=99`. It must preserve
`rbp`, because no memory-backed operand is consumed.

```text
offset range    bytes             decoded instruction
[01E6,01E9)   48 85 FF          test rdi, rdi
[01E9,01ED)   40 0F 94 C7       sete dil
[01ED,01F1)   48 0F B6 FF       movzx rdi, dil
[01F1,01F4)   48 F7 DF          neg rdi
[01F4,01F5)   C3                ret
```

`TEST` computes an AND for flag-setting purposes without storing that AND
into `rdi`. Testing a register with itself therefore sets ZF exactly when
its entire 64-bit value is zero. `SETE` reads that flag and writes a byte
containing one when ZF is set, zero otherwise. `SETZ` is another name for
this same condition and encoding; neither mnemonic tests only the old low
byte.

The destination `dil` is the lowest eight bits of `rdi`. Writing it leaves
the old high 56 bits alone. `MOVZX` then copies that byte into the whole
64-bit destination with zeros in all the higher positions. Finally, `NEG`
computes zero minus that whole value, giving zero from zero and `U` from one.
The canonical Forth flag is now data, independent of later status-flag changes.

Follow both zero and `0x100` (decimal 256). In each column, `rbp=P` and
`[P]=99` remain unchanged:

| After instruction at | Input zero: `rdi` | Input `0x100`: `rdi` |
|---|---|---|
| Entry | `0x0000000000000000` | `0x0000000000000100` |
| `01E6` TEST | unchanged; ZF=1 | unchanged; ZF=0 |
| `01E9` SETE | `0x0000000000000001` | `0x0000000000000100` |
| `01ED` MOVZX | `0x0000000000000001` | `0x0000000000000000` |
| `01F1` NEG | `0xFFFFFFFFFFFFFFFF` | `0x0000000000000000` |
| `01F4` RET | return with `[99,U]` | return with `[99,0]` |

The nonzero column explains why `MOVZX` matters. After SETE, the low byte
is correctly zero, but bit eight of the old input is still one. Omit MOVZX
and NEG would turn `0x100` into `0xFFFFFFFFFFFFFF00`, a nonzero, noncanonical
answer to a test that should be false. Input five would hide the bug: its
only set bits lie in the byte SETE overwrites.

There is a second byte-level trap. The prefix `40` is a REX prefix with its
W/R/X/B option bits clear. Its **presence** changes the byte-register names
available to the following instruction:

```text
40 0F 94 C7    sete dil     writes bits 0–7 of rdi
   0F 94 C7    sete bh      writes bits 8–15 of rbx
```

The lower line is a hypothetical deletion, not source code. Without REX,
the byte register selected by this encoding is the legacy `bh`, not `dil`.
Thus `40` is not removable padding. `MOVZX` has its own `48` REX prefix,
selecting a 64-bit destination and the appropriate low-byte source naming.
The source and the ISA register tables must agree about the destination;
looking only at the intended mnemonic would miss this mistake. Intel's
[Volume 2A register table](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=104)
and [Volume 2B SETcc entry](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2b-manual.pdf#page=598)
provide the architectural cross-check.

**Pause here if needed.** Keep the state immediately after SETE for input
`0x100`. On return, explain which bits are stale and which instruction clears
them. That one transition is more useful than memorizing all fifteen bytes.

## Division: arrange an unsigned dividend, then keep its quotient

The [eighteen-byte `divide_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L229-L237)
starts at `0x400200`:

```text
offset range    bytes             decoded instruction
[0200,0204)   48 8B 45 00       mov rax, qword [rbp]
[0204,0207)   48 31 D2          xor rdx, rdx
[0207,020A)   48 F7 F7          div rdi
[020A,020E)   48 83 C5 08       add rbp, 8
[020E,0211)   48 89 C7          mov rdi, rax
[0211,0212)   C3                ret
```

The first two instructions prepare a special input arrangement for DIV.
The processor takes a **128-bit unsigned dividend** from the register pair
`RDX:RAX`: high half in `rdx`, low half in `rax`. The colon denotes
concatenation, not division. Its numerical value is `rdx*M + rax`.
The explicit operand `rdi` is the 64-bit divisor.

Loading `a` from `[rbp]` puts the lower Forth operand in `rax`. XORing `rdx`
with itself clears it, regardless of its previous contents. The physical
DIV input remains 128 bits; this routine deliberately supplies a value in
the 64-bit range by making its upper half zero. It does not expose arbitrary
128-bit division as a Forth word.

From `[99,100,13]`, use `?` for irrelevant incoming scratch-register values:

| After instruction at | `rax` | `rdx` | `rdi` | `rbp` |
|---|---:|---:|---:|---|
| Entry | ? | ? | 13 | P |
| `0200` | 100 | ? | 13 | P |
| `0204` | 100 | 0 | 13 | P |
| `0207` | 7 | 9 | 13 | P |
| `020A` | 7 | 9 | 13 | P+8 |
| `020E` | 7 | 9 | 7 | P+8 |
| `0211` | 7 | 9 | 7 | P+8; return to K |

The arithmetic check is `100 = 7*13 + 9`, with `0 <= 9 < 13`.
DIV puts quotient in `rax` and remainder in `rdx`. The body copies only the
quotient into the cached top. Its final logical stack is `[99,7]`, not
`[99,7,9]`. A leftover scratch-register value is not a public stack result.

DIV can fault for a zero divisor or an oversized quotient. But for this
routine's valid nonzero `b`, quotient overflow is excluded: `0 <= a <= U`,
`b >= 1`, so `floor(a/b) <= a <= U`. The quotient fits. Clearing `rdx` is
essential to that argument. A hypothetical stale high half of one with low
half zero and divisor one would ask for quotient `M`, which cannot fit in
`rax`. These are architectural divide-error conditions, as specified in
[Intel's DIV entry](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=387).

For `b=0`, the real body reaches a processor divide-error fault, `#DE`;
it has no Forth error-return path. The source identifies the Linux signal
as SIGFPE. Do not continue a successful-return trace, invent quotient zero,
or assume rollback. We do not run this failure case.

Unsigned means what it says. The pattern `U` is signed -1 under a different
interpretation, but `U / 2` here yields `H-1`, with remainder one. It does
not request signed -1 divided by two. Likewise, `U / H` yields one. That
last calculation is Chapter 5's top-bit extraction; DIV itself has not
become a signed comparison.

## Multiplication: why the low half is enough for this contract

The [sixteen-byte `star_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L244-L249)
starts at `0x40021D`:

```text
offset range    bytes             decoded instruction
[021D,0220)   48 89 F8          mov rax, rdi
[0220,0225)   48 0F AF 45 00    imul rax, qword [rbp]
[0225,0229)   48 83 C5 08       add rbp, 8
[0229,022C)   48 89 C7          mov rdi, rax
[022C,022D)   C3                ret
```

This is the **two-operand** IMUL form: multiply the destination's old value
by the memory operand, then keep a destination-width result. It is not the
one-operand form that exposes a double-width result in a register pair.
Unlike DIV, this IMUL form does not mandate `rax`; these bytes choose it
as temporary storage. `rdi` must hold the final Forth result.

For `[99,6,7]`, `[P]=6` and `[P+8]=99` remain unchanged:

```text
after              rax       rdi       rbp
entry                ?         7         P
021D MOV             7         7         P
0220 IMUL           42         7         P
0225 ADD            42         7         P+8
0229 MOV            42        42         P+8
022C RET            42        42         P+8; return with [99,42]
```

The name IMUL describes signed multiplication, but the retained low 64 bits
also give the unsigned product modulo `M`. Here is why. An unsigned operand
`a` and its signed interpretation differ by either zero or `M`; the same
holds for `b`. Replacing either factor by a value differing by `M` changes
the product only by multiples of `M`. Discarding those multiples therefore
leaves identical low bits.

For `a=U` and `b=2`, unsigned multiplication gives `2M-2`, while signed
interpretation gives `(-1)*2=-2`. Both retain the pattern `M-2`, or
`0xFFFFFFFFFFFFFFFE`. Their full products are different. The signed product
fits in 64 signed bits; the unsigned product exceeds one unsigned cell.
Thus equal low bits do not imply identical overflow tests or identical high
halves. IMUL's CF/OF report its signed-fit condition, not whether an unsigned
high half would be nonzero. The later pointer ADD overwrites those flags
anyway. See [Intel's two-operand IMUL description](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=546).

Nor does multiplication generally preserve a mathematical product for later
division. `H*2` retains zero, so dividing that result by two gives zero rather
than recovering `H`. Keep the one-cell contract in view when rearranging an
expression. We have audited this primitive, not established a compiler's
integer semantics or correctness.

## Connect the layers without extending the claim

Together the bodies contain `9+12+15+18+16 = 70` bytes. Their gaps are
separate dictionary headers, not omitted arithmetic instructions. Every
binary body advances `rbp` by eight exactly once; `0=` never advances it.
All five return one cell in `rdi` under their successful-call preconditions.

This accounts for Chapter 3's construction of `(a-b) modulo M`: NAND
supplies complement and ADD supplies wrapping addition. It also accounts
for Chapter 5's `0<`: unsigned division by `H` produces zero or one, and two
zero tests normalize that result to zero or `U`.

It does **not** remove Chapter 5's ordering limitation. For signed operands
`H-1` and -1, subtraction retains `H`, whose top bit is set. `0<` correctly
recognizes that stored pattern as negative, so `- 0<` returns true even
though the original left operand is greater. Every primitive can meet its
contract while their composition answers a question outside its safe domain.
Equality after modular subtraction remains sound; signed ordering still
needs the stated difference bound.

## Practice

These are paper audits, including the defective variants. Do not patch or
execute the seed. The [feedback companion](../practice/13-solutions.md)
provides graduated hints, worked solutions, and changed cases.

### S13-01 — Track the consumed slot

Independently start each body with `rbp=0x1000`, `[0x1008]=99`, and a valid
return destination K. For `+`, set `[0x1000]=U`, `rdi=1`. For `nand`, set
`[0x1000]=12`, `rdi=10`. Give every instruction's starting offset, resulting
`rdi` and `rbp`, and final logical stack. Which memory bytes are erased?
For addition, why would inspecting ZF after return misdescribe the sum?

### S13-02 — Diagnose two zero-test edits

First trace the real `0=` on `rdi=0x100`. Then reason about two separate
hypothetical edits: removing MOVZX, and removing only the `40` before SETE.
For the second edit, use input zero and retain MOVZX. Identify the first
wrong register effect, the returned value, and any unintended register write.
Why would a missing-MOVZX test using input five be insufficient?

### S13-03 — Complete and bound division

Start with `[99,100,13]`. Fill the unknowns immediately after DIV:
`rax=___`, `rdx=___`, `rdi=___`, `rbp=___`. Complete the successful return.
Explain why the remainder does not become a second Forth result. Prove the
quotient fits for every nonzero divisor in the actual body. Separately,
locate the failure if the divisor is zero, and if a hypothetical omitted XOR
leaves `rdx=1`, `rax=0`, and divisor one at DIV.

### S13-04 — Separate product bits from interpretation

Trace `*` on `[99,U,2]`. Give its two unbounded mathematical products under
unsigned and signed interpretations, its retained cell, and its final stack
pointer. Explain why the signed-fit flag is not an unsigned-overflow test.
Then change to a hypothetical eight-bit cell model: multiply patterns
`0xFF` and `0x02`. State which argument transfers and which numerical bounds
change. This is a model change, not an alternate decoding of these bytes.

### S13-05 — Find the composition's boundary

Trace the library sequence `- 0<` on patterns `[H-1,U]`, using the contracts
now supported by the five bodies. Identify the wrapped subtraction, the
quotient by H, and both zero-test results. Does the final canonical flag
correctly compare the original signed operands? Explain why replacing this
ordering question with equality does not have the same failure. Check your
reasoning on a hypothetical eight-bit model with patterns `0x7F` and `0xFF`.

## Stop, check, and return

If the right numerical answer has the wrong `rbp`, return to the shared
frame before studying more opcodes. If the zero-test result is wrong, write
all sixteen hexadecimal digits after SETE. If division seems signed, label
the unsigned dividend and divisor before calculating. Use the first hint
that addresses your actual mismatch, then attempt the changed case without
copying its answer.

For a later return check, explain one successful body and one failure boundary
from the listings alone. Assisted completion and independent explanation
are different evidence; neither this chapter's audit nor its exercises
establish a novice learning outcome without a reader's attempt.

The physical I/O audit is still planned. See the [coverage map](../../COVERAGE.md)
for that remaining route rather than assuming a next implementation chapter
is already available.

## Source and checking record

The listings cover `000-seed.hex0` ranges `[0x1B7,0x1C0)`, `[0x1CE,0x1DA)`,
`[0x1E6,0x1F5)`, `[0x200,0x212)`, and `[0x21D,0x22D)`, including every return.
The source-decoded image was treated only as nonexecutable data. GNU objdump
2.44 used binary input, x86-64 mode, Intel syntax, base adjustment
`0x400000`, and separate exact start/stop bounds matching those half-open
ranges. It agreed with the instructions shown.
The linked Intel references are the September 2016 Volume 2A/2B instruction
manuals, consulted for the specified legacy encodings on 2026-10-06.
Derived states are not tool output. No build, seed run, timing measurement,
or wider compiler validation is claimed.
