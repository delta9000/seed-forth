# The native colon compiler: hints and solutions

Return to [Chapter 16](../chapters/16-native-colon-compiler.md).
These are checked static derivations for the pinned Linux/x86-64 seed, not
executed observations. All addresses and byte strings use hexadecimal
unless identified as decimal. Cells occupy eight bytes; stack tops are at
the right. `U` denotes the all-ones cell. Earlier stack values and valid
storage remain subject to the chapter's preconditions.

Use the first hint for orientation and the second for a concrete next step.
After reading a solution, close it and try the changed case. Being able to
follow a worked table is useful; reproducing the reasoning independently
is a different check.

## S16-01 — Recover the old top after copying

**Hint 1.** `read_word` adds two items. Identify where it saved 99 before
letting the string instructions borrow `rdi`.

**Hint 2.** At colon's post-read `rbp=P-16`, `[rbp]` is T and `[rbp+8]`
is 99. REP advances its destination by the count only under DF=0.

**Worked solution.** The complete significant states are:

| Point | `rbp` | `rdi` | Other relevant facts |
|---|---|---|---|
| Before colon | P | 99 | C=`[99]` |
| After reading `lift` | P-16 | 4 | `[P-16]=T`; `[P-8]=99` |
| Fixed fields written | P-16 | 4 | `[0x401000]=0x400617`; flags=0; length=4 |
| Copy prepared | P-16 | `0x40100A` | `rsi=T`; `rcx=4`; LATEST=`0x401000` |
| REP finished | P-16 | `0x40100E` | `rsi=T+4`; `rcx=0`; copied `6C 69 66 74` |
| HERE saved | P-16 | `0x40100E` | HERE=`0x40100E` |
| Reload at `052A` | P-16 | 99 | Reads `[rbp+8]` |
| Pointer advance at `052E` | P | 99 | C=`[99]` restored |
| Mode store, then RET | P | 99 | STATE=1; this call's return destination consumed |

The header occupies `[0x401000,0x40100E)`, fourteen bytes. Its name bytes
occupy `[0x40100A,0x40100E)`, and the next byte is the body's start.

Replacing the reload by `mov rdi,[rbp]` would retrieve T instead of 99.
The pointer advance still removes both temporary slots, so the final
logical stack would be `[T]`. The old 99 would remain in memory outside
the resulting live stack. Moving the pointer does not repair the wrong
cached top.

With DF=1, the first copy writes the initial `l` at `0x40100A`. The second
reads T-1 and writes `0x401009`, overwriting the length field. Further
copies go backward as well. No valid forward-copy result follows. The
AMD64 process-initialization ABI provides the documented initial DF=0;
continuing code must preserve that condition. Neither REP nor an unseen
CLD in this body supplies it: there is no CLD here.

**Wrong path to diagnose.** Saying “RDI still contains the length after
REP” ignores its explicit replacement by LEA. Saying “the CPU always
copies forward” ignores DF. Both errors lose the reason HERE can be
obtained from the final destination pointer.

**Changed case.** Reset to name `go`, initial HERE=`0x401040`, and the
same C. Before REP, `rcx=2`, `rdi=0x40104A`; afterward `rdi=0x40104C` and
HERE receives that address. The header has twelve bytes; the two stack
slots and sixteen-byte cleanup are unchanged. Token length changes copy
work, not the number of returned stack cells.

## S16-02 — Finish a call without losing its prefix

**Hint 1.** Name the instruction's start and end separately. Decode the
four displacement bytes as little-endian two's complement.

**Hint 2.** `0x40101B+5=0x401020`. The target is below that origin, so the
required displacement is negative.

**Worked solution.** Let entry `rbp=Q`, `rdi=0x4001B7`, `[Q]=99`; older
storage, including the dummy if appropriate, follows Q. The helper does:

```text
load HERE:          rax = 0x40101B
write opcode:       [0x40101B] = E8
advance rax:        rax = 0x401020
subtract:           rdi = 0xFFFFFFFFFFFFF197
store low 32 bits:  [0x40101C..0x40101F] = 97 F1 FF FF
save HERE:          HERE = 0x401020
restore prefix:     rdi = 99; rbp = Q+8
return:             C = [99]
```

The signed distance is `-0xE69`, decimal -3689. The complete five bytes
are `E8 97 F1 FF FF`. Neither STATE nor LATEST changes.

The proposed `target-HERE` computes `-0xE64`, or -3684. A CPU still adds
that distance to the instruction's **end** at `0x401020`, reaching
`0x4001BC`, five bytes past the intended entry. It does not compensate
for a compiler that used the wrong origin.

A valid rel32 distance lies from -2147483648 through 2147483647, inclusive.
The helper stores the low four bytes for every input xt, without testing
that bound. For example, in an independent valid-address paper layout,
a desired distance of `0x80000000` is positive 2147483648, but the encoded
32-bit pattern sign-extends as negative 2147483648. The requested and
actual destinations differ by `0x100000000`. Truncation always produces
four bytes; it does not always preserve the intended target.

**Wrong path to diagnose.** Using EDI as the store source does not mean
the preceding SUB was 32-bit. SUB computes a 64-bit result in RDI; the
four-byte memory store selects the low part afterward.

**Changed case.** Start A=`0x401030`, target=`0x401080`, with
C=`[88,99,target]`. End=`0x401035`, distance=`0x4B` (75 decimal), bytes
`E8 4B 00 00 00`, new HERE=`0x401035`, final C=`[88,99]`. The helper
consumes the same one xt for forward and backward calls.

## S16-03 — Follow both literal modes

**Hint 1.** Read/parse happen before the STATE test in both cases. The
first TEST asks about the parser's flag, not the value three.

**Hint 2.** After dropping the flag, the cache contains three. Saving it
once more allows `mov edi,lit-xt` to replace the cache without losing it.

**Worked solution.** Use incoming `rbp=P`, `rdi=99`, `[P]=88`. In both
resets, reading gives `[88,99,T,1]` with `rbp=P-16`. Successful parsing
gives `[88,99,3,U]`, still with `rbp=P-16`. The flag is in RDI and three
at `[P-16]`; `[P-8]` holds 99 and `[P]` holds 88.

TEST finds the flag nonzero. Reloading three and advancing the pointer
leaves `[88,99,3]`, `rdi=3`, `rbp=P-8`.

- **STATE=0:** the mode TEST produces zero; JNZ is not taken; RET returns
  with `[88,99,3]`. HERE and LATEST have not changed, and STATE remains zero
- **STATE=2:** JNZ is taken because two is nonzero. The compile branch
  reserves P-16 again and stores three there, giving the temporary logical
  `[88,99,3,3]`. MOV EDI installs `0x4005A0` as the new top, giving
  `[88,99,3,lit-xt]`

The helper writes `E8 8D F5 FF FF` at `[0x40100E,0x401013)` and consumes
the xt. It returns to instruction `0x4005FC` with `[88,99,3]`, `rbp=P-8`,
and HERE=`0x401013`. JMP then reaches comma without pushing another
return address. Comma writes `03 00 00 00 00 00 00 00` at
`[0x401013,0x40101B)`, restores 99 from `[P-8]`, advances `rbp` to P,
and returns to `[lit]`'s caller.

The compile result is `[88,99]`, HERE=`0x40101B`, unchanged LATEST, and
STATE still **2**. This body tests nonzero; it does not normalize STATE to
one. The original `[lit]` return destination survives the helper's call
and return, and is finally consumed by comma's RET.

For `3x`, the parser reports a zero flag. The first JZ goes to
`fatal_token` before the flag cleanup or STATE test. It reports the token
and exits; no literal bytes are emitted and no successful return is
promised. If colon already published a header, that publication is not
rolled back. The failure is not interpreted as the number three or as a
request to compile zero.

**Wrong path to diagnose.** Leaving three on C after compile-mode `[lit]`
forgets the final comma consumption. Conversely, dropping the entire
prefix would confuse the helper's xt with every value below it.

**Changed case.** Reset with STATE=0 and token `0`. Successful parsing
returns `[88,99,0,U]`; zero is a valid value because the separate success
flag is nonzero. The final stack is `[88,99,0]`. With STATE=1, the same
input emits the same call followed by eight zero bytes, leaving
`[88,99]`. It does not take the invalid-token branch.

## S16-04 — Remove every temporary return address

**Hint 1.** Distinguish the cell's address S, its value three, and the
continuation S+8. Only the value belongs on D.

**Hint 2.** PUSH adds the continuation to R, but the immediately following
RET removes it. Draw the state after RET as its own row.

**Worked solution.** Before the literal call, let `rsp=V`,
`rbp=P`, `rdi=7`, and `[P]=99`. `Rbase` includes the surrounding
`lift` invocation's return destination.

| Event | `rsp` | R | Data state |
|---|---|---|---|
| Before call | V | `Rbase` | `[99,7]` |
| CALL at `0x40100E` | V-8 | `Rbase,0x401013` | Unchanged |
| POP RAX | V | `Rbase` | `rax=0x401013` |
| SUB RBP,8 | V | `Rbase` | `rbp=P-8`; cache still 7 |
| Save RDI | V | `Rbase` | `[P-8]=7` |
| Load inline cell | V | `Rbase` | `rdi=3`; D=`[99,7,3]` |
| ADD RAX,8 | V | `Rbase` | `rax=0x40101B` |
| PUSH RAX | V-8 | `Rbase,0x40101B` | Unchanged |
| RET | V | `Rbase` | Resume at `0x40101B` with `[99,7,3]` |

The address `0x401013` is no longer on R after POP; `0x40101B` is no
longer there after RET. The inline cell still occupies dictionary memory.
The next ordinary addition call temporarily creates its own return
address, `0x401020`; addition returns there with `[99,10]`. The C3 at
that address then returns from `lift` itself.

With an adjustment of seven, the resumed address would be `0x40101A`,
the last byte of the value cell, not the call at `0x40101B`. This breaks
the instruction/data boundary. Do not infer a particular crash or output
without decoding and validating that unintended instruction stream.

A top-level call has a return address into the interpreter's instruction
stream. It has no promised eight-byte literal payload at that address.
The presence of a native return destination therefore does not establish
`lit`'s call-site precondition.

**Wrong path to diagnose.** `[Rbase,S+8]` is the pre-RET state, not the
post-RET state. Keeping it afterward invents a leaked return-stack cell.

**Changed case.** For a valid independent call site A=`0x402040`, the
inline cell starts at `0x402045`. If it stores decimal 300, its bytes are
`2C 01 00 00 00 00 00 00`; the resumed address is `0x40204D`. From
D=`[55]`, the result is `[55,300]` and R returns to its pre-call shape.
Changing the value does not change the eight-byte skip.

## S16-05 — Rebuild the entry in a changed layout

**Hint 1.** `boost` has five name bytes. Its header differs from `lift`'s
before any body displacement is calculated.

**Hint 2.** Start the body at `0x40200F`; add five to find the first
call's origin, then eight to find the second call's start.

**Worked solution.** Header size is `8+1+1+5=15`; body size remains
`13+5+1=19`. Total size is 34 decimal bytes, hexadecimal `0x22`.

```text
virtual range         bytes                       meaning
[402000,402008) 00 10 40 00 00 00 00 00          link 0x401000
[402008,402009) 00                               flags
[402009,40200A) 05                               name length
[40200A,40200F) 62 6F 6F 73 74                   "boost"
[40200F,402014) E8 8C E5 FF FF                   CALL lit
[402014,40201C) 0C 00 00 00 00 00 00 00          inline twelve
[40201C,402021) E8 96 E1 FF FF                   CALL +
[402021,402022) C3                               RET
```

The two distances are:

```text
lit: 0x4005A0 - 0x402014 = -0x1A74 = -6772 decimal
 + : 0x4001B7 - 0x402021 = -0x1E6A = -7786 decimal
```

After compilation, HERE=`0x402022`, LATEST=`0x402000`, STATE=0,
and C=`[88,99]`. Later D=`[77,8]` becomes `[77,8,12]`, then `[77,20]`.
That execution does not change the compilation cursor or dictionary chain.

A second executed semicolon writes C3 at `0x402022`, makes
HERE=`0x402023`, and stores zero in STATE again. C and LATEST are unchanged.
It does not create another header, detect that the preceding definition
already ended, or certify its data/return-stack balance. On an ordinary
call, `boost` still returns at its first C3; the extra byte is not reached
by that path.

**Wrong path to diagnose.** Reusing `lift`'s offsets after merely changing
the base misses the extra name byte. Both relative origins move by that
byte, even though the runtime instruction pattern has the same length.

**Changed case.** On a fresh reset at the same entry address, consider
`: boost [lit] 12 [lit] 4 + + ;`. The header is still fifteen bytes;
the body is `13+13+5+5+1=37` bytes. Therefore HERE ends at `0x402034`.
Check the instruction positions independently:

| Call start | Target | Address after call | Displacement bytes |
|---|---|---|---|
| `0x40200F` | lit=`0x4005A0` | `0x402014` | `8C E5 FF FF` |
| `0x40201C` | lit=`0x4005A0` | `0x402021` | `7F E5 FF FF` |
| `0x402029` | +=`0x4001B7` | `0x40202E` | `89 E1 FF FF` |
| `0x40202E` | +=`0x4001B7` | `0x402033` | `84 E1 FF FF` |

The inline cells occupy `[0x402014,0x40201C)` and
`[0x402021,0x402029)`; RET occupies `[0x402033,0x402034)`.
D=`[77,8]` becomes `[77,8,12,4]`, then `[77,8,16]`, then `[77,24]`.
Two calls to the same target at different positions need different
relative displacements. C still preserves `[88,99]` throughout construction.
