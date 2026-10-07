# 19. From contracts to a complete seed audit

[Previous: Decimal parser and REPL](18-decimal-parser-and-repl.md) · [Practice help](../practice/19-solutions.md) · [Later-volume coverage](../../COVERAGE.md)

Can you explain a new word twice: first as a transformation of values,
then as a particular sequence of bytes with particular return destinations?
Can you say what that explanation establishes without claiming that it
proves the computer, operating system, or future compiler correct?

Those are this volume's final tasks. We will account for the entire seed
file, then derive a fresh definition from its initial state:

```forth
: inc [lit] 1 + ;
```

The result is small enough to check completely. Its construction crosses
the same boundaries as a larger program: input, name lookup, compilation,
storage, instruction decoding, data representation, and return ownership.
No later compiler volume is needed to finish this one.

## Pick the evidence you want to produce

Bring the phase model from [Chapter 8](08-defining-words-and-phases.md),
physical stack invariant from [Chapter 12](12-physical-stacks-and-memory.md),
and header/compiler mechanisms from
[Chapters 15](15-dictionary-and-token-input.md) and
[16](16-native-colon-compiler.md). The preceding branch and interpreter
chapters connect inline operands and input dispatch to their native bodies.

Two quick checks: is a dictionary entry's address its execution token?
Does `[lit]` leave its number on the compiling stack? Here the answers are
no: code follows the header, and compile-mode `[lit]` consumes the parsed
number while emitting its future push. If either distinction is uncertain,
repair it before doing displacement arithmetic. You may keep those
chapters open; remembering navigation and opcode tables is not the goal.

For a shorter route, attempt S19-01 and S19-05 first. For a supported route,
work through the two passes below: construction, then execution prediction.
Save an intermediate address table if you stop between them.

**Evidence boundary.** The edition is Linux/x86-64 at
[revision bbcc1732152af2d884737272eed870d2410ffe8e](https://github.com/delta9000/seed-forth/tree/bbcc1732152af2d884737272eed870d2410ffe8e).
The capstone is a checked static derivation from that source. The created
entry is a **predicted runtime-memory artifact**, not bytes collected from
a running seed. No seed execution, build, or novice setup trial has been
performed for this capstone.

## Reconcile the file, rather than count explanations

The [audit ledger](../AUDIT.md) and its
[76 source regions](../source-audit.csv) partition file offsets
`[0x000,0x6EC)`: 1,772 bytes. Start offsets are inclusive; ends are
exclusive. Every file byte belongs to one row, including bytes that encode
metadata rather than instructions.

| File content | Regions | Bytes | Teaching responsibility |
|---|---:|---:|---|
| ELF header and program header | 2 | 120 | S11 |
| Startup | 3 | 66 | S11 |
| Dictionary headers | 32 | 421 | S15 |
| Primitive bodies | 32 | 760 | S12–S17 |
| Six unnamed helpers | 6 | 322 | S15, S16, S18 |
| REPL | 1 | 83 | S18 |
| Total | 76 | 1,772 | Whole file |

The instruction-byte total is therefore `66+760+322+83 = 1,231`.
Together, `120+421+1,231 = 1,772`. The chapter allocations provide a
second reconciliation: S11–S18 own respectively 186, 119, 70, 142, 816,
237, 34, and 168 bytes. Their sum is also 1,772. This chapter adds no
new file-byte ownership.

There are 32 named primitives, each with a header and body. That explains
64 regions, not 64 primitives. The six unnamed helpers are `read_word`,
`read_char`, `report_token`, `fatal_token`, `compile_call`, and
`parse_decimal_code`; the REPL is counted separately in the table. The
CSV uses kind `helper` for all seven of those non-dictionary routines.
Neither convention creates an extra callable dictionary word.

The partition itself does not establish that a manuscript explains every
region. The substantive explanations in
[Chapter 17](17-inline-branch-operands.md) cover the 34 branch bytes;
[Chapter 18](18-decimal-parser-and-repl.md) covers the final 168
parser/REPL bytes. Together with S11–S16, they complete the file-byte
explanations. The ledger records that manuscript coverage separately from
behavioral evidence. Counting regions cannot substitute for reading their
mechanisms and checking their boundaries.

Nor does complete explanation establish arbitrary-input correctness.
Chapter ownership says where to inspect an argument. It does not certify
that every argument is valid, every precondition holds, or every reachable
execution is safe. An omitted underflow check remains omitted even when
its absence is accurately documented.

The learned library contracts connect to this accounting:

- Byte and cell writers depend on the memory primitives, HERE's meaning,
  and the width-specific arithmetic used to advance it
- Shuffles and early exits depend on the cached-top representation and
  the separate ownership of data and native return-stack cells
- Defining words depend on header construction, executable storage,
  STATE-controlled token dispatch, and correctly encoded call targets
- Control-flow words depend on the branch primitives' inline target cells;
  deferred words additionally depend on storage lifetime and `execute`

Those dependencies explain why we learned contracts before auditing their
implementation. The pinned
[`010-lib.fth`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth)
is a separate source file. Its text, and the definitions it would create
when loaded, are not additional bytes inside the 1,772-byte seed image.

## Fix a fresh starting state

Our capstone starts immediately after successful seed initialization,
before loading `010-lib.fth` or defining anything else. The input stream
contains the displayed definition, with ordinary spaces and a final
newline. Its tokens are available successfully and intact. The initial
logical data stack is empty, and no borrowed return-stack values remain.

The [startup stores](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L63-L75)
give these concrete values:

| Quantity | Initial value |
|---|---|
| HERE, stored at `0x413010` | `0x401000` |
| LATEST, stored at `0x413008` | `0x400617`, the `0branch` header |
| STATE, stored at `0x413000` | 0 |
| Data-stack base B | `0x411000` |
| `rbp`, `rdi` | B, 0; the zero is an empty-stack dummy |

The literal target is
[`lit`'s code at `0x4005A0`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L563-L575).
Addition's target is
[`+`'s code at `0x4001B7`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L191-L199).
These are execution tokens, abbreviated xts, not their header addresses.
All addresses below are virtual addresses. Byte strings proceed from
lower to higher address; multibyte fields are little-endian; cells are
eight bytes. Logical stack tops appear at the right.

Assume sufficient writable and executable dictionary storage, valid
stacks, intact system cells and headers, no overlapping live regions, and
forward string copying with DF=0. The newly written word must be complete
before it is called. The seed does not enforce all these conditions.
A process with the library already loaded is a different starting state;
its HERE and LATEST cannot be replaced by these values on paper without
changing the problem.

## Construction pass: account for every created byte

### 1. Colon consumes the name

The outer loop finds ordinary `:` while STATE is zero, so it executes
colon. Colon itself consumes the next token, `inc`. The loop will not
later treat that name as a request to execute a word.

The header has eight link bytes, one flags byte, one length byte, and
three name bytes. It occupies `8+1+1+3=13` bytes, hexadecimal `0xD`.
From the initial HERE:

```text
entry address                 0x401000
link                          0x400617
flags                         00
name length                   03
name bytes                    69 6E 63       "inc"
first code address / inc xt   0x40100D
```

There is no alignment padding, name terminator, or separate xt field.
Colon sets LATEST to `0x401000`, HERE to `0x40100D`, and STATE to one.
The name-reading/copying temporaries are removed; the compiling data
stack is empty again. The
[colon implementation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L520-L537)
publishes LATEST before the body exists. Publication is not a completion
check or a promise that a later error will roll back the entry.

### 2. Immediate `[lit]` consumes `1`

The loop executes `[lit]` despite nonzero STATE because its immediate bit
is set. It reads token `1`; decimal parsing returns value one and a
separate nonzero success flag. `[lit]` discards that flag and takes its
compile path. It emits CALL `lit`, then an eight-byte one. Neither the
flag nor the one remains on the compiling stack.

Derive the CALL from its new location, rather than borrowing an earlier
example. A five-byte CALL beginning at A encodes `target-(A+5)`:

```text
A                            = 0x40100D
address after CALL           = 0x401012
lit xt - address after CALL  = 0x4005A0 - 0x401012
                             = -0xA72 = -2674 decimal
32-bit displacement pattern = 0xFFFFF58E
five emitted bytes          = E8 8E F5 FF FF
```

The displacement fits signed 32-bit range. The runtime inverse check is
`0x401012-0xA72 = 0x4005A0`. The eight literal bytes begin at `0x401012`:
`01 00 00 00 00 00 00 00`. They are inline data, not eight instructions.
After the complete 13-byte literal sequence, HERE is `0x40101A`.

This connects the immediate
[`[lit]` body](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L577-L601)
to the shared
[`compile_call` helper](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L551-L562).
The helper writes the low four displacement bytes without checking range;
our arithmetic supplies that check for this call.

### 3. Compile addition; execute semicolon

Ordinary `+` is found while STATE is one. The loop compiles its call;
it does not try to add on the empty compiling stack.

```text
A                            = 0x40101A
address after CALL           = 0x40101F
plus xt - address after CALL = 0x4001B7 - 0x40101F
                             = -0xE68 = -3688 decimal
32-bit displacement pattern = 0xFFFFF198
five emitted bytes          = E8 98 F1 FF FF
```

The inverse check is `0x40101F-0xE68 = 0x4001B7`. Immediate `;` then
executes, writes one C3 at `0x40101F`, advances HERE, and clears STATE.
It emits a return instruction, not a call to the semicolon primitive.

### The complete predicted entry

| Virtual range, end excluded | Bytes | Meaning |
|---|---|---|
| `[401000,401008)` | `17 06 40 00 00 00 00 00` | Link to initial LATEST |
| `[401008,401009)` | `00` | Ordinary word flags |
| `[401009,40100A)` | `03` | Three-byte name |
| `[40100A,40100D)` | `69 6E 63` | `inc` |
| `[40100D,401012)` | `E8 8E F5 FF FF` | CALL `lit` |
| `[401012,40101A)` | `01 00 00 00 00 00 00 00` | Inline one |
| `[40101A,40101F)` | `E8 98 F1 FF FF` | CALL `+` |
| `[40101F,401020)` | `C3` | RET |

Concatenating those fields produces exactly 32 bytes. The row break below
is only a display break, not a field boundary:

```text
17 06 40 00 00 00 00 00 00 03 69 6E 63 E8 8E F5
FF FF 01 00 00 00 00 00 00 00 E8 98 F1 FF FF C3
```

Final HERE=`0x401020`, LATEST=`0x401000`, STATE=0, and compiling stack
`[]`. Compare both field boundaries and this concatenated string: a right
length alone would miss swapped bytes or a wrong target. These bytes were
checked by independent address arithmetic and byte construction, not by
reading process memory.

The original seed file still ends at mapped address `0x4006EC`. The new
entry is in runtime dictionary storage beginning at `0x401000`. It is
neither a replacement for the original file nor 32 additional file bytes
in the audit ledger.

## Execution pass: follow `[lit] 5 inc`

Now consider the next input, with STATE zero:

```forth
[lit] 5 inc
```

Logically, `[lit] 5` leaves `[5]`. Calling `inc` pushes its stored one and
then adds: `[5] -> [5,1] -> [6]`. A stated older prefix is preserved:
`[99] -> [99,5] -> [99,5,1] -> [99,6]`. That second trace is a separate
case; 99 was not silently present in our fresh initialization.

The physical trace explains why those stack effects are credible. After
interpreted `[lit] 5`, `rdi=5`, `rbp=B-8=0x410FF8`, and `[B-8]=0` is the
saved dummy. Reading/finding `inc` temporarily pushes its xt; `execute`
consumes that xt and tail-jumps to `0x40100D`, restoring the same data
representation. The
[REPL's CALL to `execute`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L664-L689)
saved `0x4006EA`. The tail jump adds no second return destination.

Let the native stack pointer immediately before that outer CALL be S,
with older return-stack contents R0. R0 and S are symbolic: Linux's process
stack address is not fixed by this seed. At `inc` entry, `rsp=S-8` and
R is `[R0,0x4006EA]`. Keep this caller destination distinct from the
literal's inline-cell address:

| Event | Data representation | Native control state |
|---|---|---|
| CALL `lit` at `0x40100D` | Unchanged `[5]` | `rsp=S-16`; top=`0x401012` |
| `lit` pops that address into RAX | Unchanged | `rsp=S-8`; caller destination exposed |
| Reserve/save old cache; load cell | `rbp=B-16`, `[B-16]=5`, `rdi=1`; D=`[5,1]` | RAX initially points at the cell |
| Add eight to RAX; push; RET | Same `[5,1]` | Resume `0x40101A`; `rsp=S-8` |
| CALL `+` | Same `[5,1]` | `rsp=S-16`; top=`0x40101F` |
| Add `[rbp]` to RDI; advance RBP | `rdi=6`, `rbp=B-8`; D=`[6]` | Addition's destination still on R |
| `+` RET, then `inc` RET | `[6]` | First `0x40101F`, then `0x4006EA`; finally `rsp=S`, R=R0 |

The literal continuation `0x40101A` was pushed and consumed by its RET.
It is not leaked on R. The discarded data slot at B-16 may still contain
five, but it is outside the live stack. HERE, LATEST, and STATE remain
unchanged by these runtime operations; lookup may update LAST_FOUND.

For the older-prefix case, start `inc` with `rdi=5`, `rbp=B-16`, and
`[B-16]=99`. Literal execution temporarily moves RBP to B-24 and stores
five there. Addition returns RBP to B-16 with `rdi=6`; 99 remains at
`[B-16]`. Preserving a prefix is a statement about live representation,
not about leaving every memory byte untouched.

A possible future observation would use `[lit] 64 inc emit bye` after
constructing the word. Under successful input and a successful one-byte
stdout write, the predicted output is one byte `41` hexadecimal, ASCII
`A`, without a newline, followed by exit status zero. This was not run.
`emit` does not turn a failed write into a reliable diagnostic, and
`bye`'s zero status would not by itself prove that the byte was delivered.

## State the remaining trust honestly

The capstone crosses several boundaries whose assumptions have not
vanished because the program is small:

1. **CPU and instruction model.** We rely on x86-64 decoding, operand
   widths, little-endian memory, CALL/RET behavior, and the supplied
   hardware implementing that model. The register invariant is this
   program's convention, not a rule automatically enforced by the CPU
2. **Linux loading and syscalls.** We rely on acceptance of this ELF
   mapping and its permissions, mapped/zero-filled storage, process-entry
   conditions, a usable native stack, and the syscall interface. Auditing
   the seed's syscall instructions does not audit Linux's implementation
3. **Input, storage, and calls.** We assume the intended token bytes
   arrive, adequate capacity exists, live regions do not collide, DF
   remains clear, targets are executable, and callers supply enough
   operands and correctly shaped inline data. There is no general
   sandbox or automatic memory-safety argument here
4. **Source and inspection.** We rely on obtaining the intended pinned
   source, decoding its hex text correctly, and inspecting bytes with
   dependable tools. For this format, text after `;` is commentary;
   noncomment hex octets produce the file bytes. An address annotation
   or disassembler label can be wrong even when it looks plausible

The source-decoded image's SHA-256 is
`697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e`.
A digest identifies the compared byte sequence; it does not assign
meaning or safety to it. Static disassembly gives another inspectable
decoding. Independent arithmetic catches some shared mistakes but does
not remove trust in the source reader, checker, editor, or host system.

Keep five claims separate. **Coverage** accounts for the file.
**Execution evidence** records what a specified run actually did.
**Reproducibility evidence** records a specified regeneration/comparison
process. **Semantic correctness** needs a specification and an argument
that behavior meets it under explicit conditions. **Security** additionally
needs a threat model and evidence about behavior under those threats.
A matching rebuild can preserve a shared bug; a successful example can
miss other paths; a tiny seed can still expose unchecked writes.

The GCC, broader toolchain, and Linux-bootstrap route belongs to later
volumes in the [coverage plan](../../COVERAGE.md). Neither a completed C
compiler volume nor a proof of Linux is supplied here. This volume's
ending is a bounded account of the seed and its library mechanisms.

## Your artifact and five checks

Build a paper variation after the completed `inc`, without resetting the
dictionary: `: bump [lit] 7 + ;`. Supply its complete entry, final system
values, and predicted result for `[99,5]`. The changed name length and
link mean that reusing the old string is insufficient. Feedback is in
S19-02; attempt the construction before opening it if you can.

### S19-01 — Derive the whole fresh entry

With only the starting-state table and primitive xts available, reconstruct
all 32 `inc` bytes. Explain every field, both signed displacements, final
HERE/LATEST/STATE, and why compilation leaves the data stack empty. Reverse
each displacement to verify its destination.

### S19-02 — Shift a layout and extend the chain

In a separate paper reset, set initial HERE to `0x401080`, keeping the
initial LATEST and STATE. Derive the complete `inc` entry and final HERE.
Which bytes change? Then attempt `bump` in the unshifted, already-extended
capstone state described above. Explain why its link differs.

### S19-03 — Track width and overflow

Predict `inc` on the unsigned maximum cell `18446744073709551615` and on
signed maximum `9223372036854775807`. Separately change the definition's
literal to 256. Which bytes and addresses change? Would `[lit]
18446744073709551616` be rejected by this parser? Distinguish a value's
width, a stored literal's width, and CALL's displacement width.

### S19-04 — Diagnose phase and target mistakes

Explain the bare-seed result of `: inc 1 + ;` when no word named `1`
exists. Does it mean the same thing? Separately diagnose replacing the
correct literal call by `E8 81 F5 FF FF` at `0x40100D`. Identify the
actual target and the broken contract without inventing an observed crash.

### S19-05 — Write an honest audit conclusion

Write four sentences identifying the inspected artifact, established
static result, unperformed checks, and remaining assumptions. Evaluate:
“All 1,772 bytes are covered, and a matching rebuild would prove this
system secure.” Name evidence that would improve the conclusion without
claiming that you collected it.

## Decide what you can demonstrate, then stop or continue

Accept your capstone when a second reading can recover the entire byte
string, both targets, the exact final system values, and each temporary
return address from your explanation. Your runtime account should preserve
an explicitly stated older prefix and distinguish dead storage from live
values. Your conclusion should distinguish file coverage from execution,
reproducibility, correctness, and security. A wrong intermediate address
is useful evidence about what to repair, not a reason to repeat everything.

If you cannot start, use the first hint. If fields are right but calls are
wrong, write A and A+5 on separate lines. If returns are confusing, pause
before `lit`'s RET and draw its immediate before/after states. After
feedback, try the changed case rather than copying the same answer.

For a stop/resume checkpoint, save three facts: entry `0x401000`, code
`0x40100D`, continuation after inline data `0x40101A`. On returning,
reconstruct the missing boundaries before reading your finished table.
A later independent attempt can check retention; this manuscript has not
established a learning outcome or validated novice installation steps.

You can end the volume by demonstrating a precise capability: given the
pinned source and stated starting conditions, derive a new word's layout,
explain its stack and control transitions, diagnose a changed case, and
state exactly what evidence supports the result. Continuing to a compiler
is another learning task, with new prerequisites and new proof obligations.
