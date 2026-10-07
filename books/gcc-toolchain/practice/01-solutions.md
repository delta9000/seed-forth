# G01: hints, solutions, and changed checks

Start with the [chapter problems](../chapters/01-a-program-from-two-files.md#try-the-mechanism).
Write a prediction and a reason before checking. A correct number with the
wrong owner, coordinate, or phase still needs repair.

Choose the support you need:

- [Changed prompts](#changed-prompts) contain no answers; try them after the
  original problems or return to them after another activity
- [Graduated hints](#graduated-hints) help with the original problems
- [Worked solutions](#worked-solutions) explain the original answers
- [Changed-task checks](#changed-task-checks) are kept separately at the end

Record whether you used a hint or reopened the chapter. That describes the
attempt, not your ability. If several steps are unclear, resume from one
worked state you can explain. These are paper tasks with supplied contracts;
no build environment is needed.

## Changed prompts

### G1-01 changed — A declaration without a use

Keep `answer.c` unchanged. Change `main.c` to:

```c
extern int answer(void);
int main(void) { return 7; }
```

The selected object writer exports a function record when it is defined or
referenced; an unused external declaration alone does not demand export.
With default startup/runtime retained, would this source force the linker
to find `answer` if `answer.o` were omitted? Explain what changed and what
`main` should return. This supplies the export rule; it does not ask you to
infer it from generic C knowledge.

### G1-02 changed — Inspect a wrong field

Keep the chapter's illustrative addresses. A proposed linker writes decimal
15 into the call field, explaining, “The destination is 15 bytes beyond
`P`.” Use the CPU's contract to predict the reached address. Locate the
mistake and derive the corrected value. Do not change the destination to
make the proposed field appear right.

### G1-03 changed — An absolute field of the same width

A supplied record now describes a four-byte **unsigned absolute** relocation,
with rule `S + A`, `S=0x401150`, and `A=0`. Its storage field begins at
`0x401121`. Assume the address fits the field.

Derive its stored value and little-endian bytes. Explain why a four-byte
field need not use the call's rule, and which supplied fact makes the storage
address irrelevant to this calculation. No new C source syntax is required.

### G1-04 changed — Move both together

Return to the original call and eight-byte pointer contracts. Move both the
caller's relative field and `answer` forward `0x20` bytes. Derive the relative
field and the absolute pointer value. Explain the different effects of one
common move. Keep both addends unchanged.

### G1-05 changed — A matching name is not a matching interface

A separately compiled provider exports the name `answer`, but its declared
result type is `long`; `main.o` was compiled using `extern int answer(void);`.
The supplied linker contract resolves names without comparing C signatures.

Does successful name resolution establish that these sources agree? Identify
where the disagreement lives and a change that repairs the source-level
contract. Do not predict a particular returned value or diagnostic.

### G1-06 changed — Remove the automatic runtime inputs

Keep the two original user objects. Add `-nostdlib` to the link command and
supply no other input. This option removes the default startup and runtime
archive; the driver still requests `_start` as entry.

Which entry obligation is now missing? Why cannot the linker use `main`
automatically under that contract? Would supplying an arbitrary body named
`_start` be enough to claim the original initializer-to-main-to-exit behavior?

### G1-07 changed — A preserved stack can still be misaligned

In an illustrative caller, RSP is `0x8008`, decimal 32776, immediately before
CALL. CALL subtracts eight and stores its return address. RET later recovers
the return address and restores those eight bytes. Assume no other stack change for
this small arithmetic model.

Derive RSP on callee entry and after RET. Does getting the original pointer
back establish that the call obeyed the required pre-call alignment? Also
explain why a C `int` stored in four bytes can still be carried temporarily
in RDI without changing its storage type.

## Graduated hints

Use one hint at a time. Hint 1 points to the idea; hint 2 names the important
boundary; hint 3 gives a starting step.

### Hints for G1-01

1. A body supplies work; a declaration supplies information about work
2. Ask what the compiler sees in this translation unit, rather than what is
   present somewhere in the source directory
3. `extern int answer(void);` has no body. The expression `answer()` uses
   that declaration's zero-parameter, integer-result promise

### Hints for G1-02

1. Start with how the CPU uses the field
2. `P` names the first of four field bytes, not the next instruction
3. Compute `P + 4 = 0x401085`, then subtract that address from `S`

### Hints for G1-03

1. The consumer is still a relative CALL; changing placement did not change
   the instruction's contract
2. Keep the distinction between field start and next instruction
3. Compute `0x401150 - 0x401125`; `0x20` is decimal 32

### Hints for G1-04

1. Compare the inputs to the two rules before calculating
2. A relative field depends on `P`; the absolute pointer rule does not
3. In the caller-only move, new `P` is `0x4010A1`. The relative change is
   minus `0x20`, while `S` stays fixed

### Hints for G1-05

1. One stage is allowed to leave this obligation open
2. Distinguish a declaration from the object that supplies the definition
3. `main.o` retains a referenced undefined symbol named `answer`. What input
   is now available to resolve it?

### Hints for G1-06

1. Distinguish the tools doing work from the artifacts they produce
2. `start.o` and `startup.o` have different source languages and jobs
3. Python starts the seed process. Forth implementations in that process
   generate bytes; the later target process begins at `_start`

### Hints for G1-07

1. Layout, transport, output packaging, and the compiler's own storage each
   answer a different question
2. “Before CALL” and “on callee entry” are separate states
3. CALL moves the supplied `0x8000` (decimal 32768) down by eight; check
   divisibility by 16 at the moment the rule specifies

## Worked solutions

### Solution G1-01 — Separate knowing from supplying

`answer.c` defines `answer`: the declaration of its name and type is followed
by a body. `main.c` first declares `answer` with no body, then defines `main`.
Inside `main`'s body, `answer()` is the cross-file use.

The compiler can check that the call supplies zero arguments and expects an
integer result without knowing the function's placement. It emits the call
bytes with an unfinished field and records the referenced symbol.
`main.o` is therefore an artifact that can exist before a final linked
address for `answer` exists. `answer.o` later supplies the definition; the
linker joins that definition with the use.

The predicted call result is seven, which `main` returns. Neither source has
an output operation. The startup path later passes the result to Linux exit.

**Check your reasoning:** identify both definitions, the body-free external
declaration, the call expression, the object-level unfinished obligation,
and the absence of requested output. “The compiler finds `answer.c`” is not
an acceptable explanation: the two compilation operations are separate.

### Solution G1-02 — Keep the right address

The CPU's addition base is `P + 4 = 0x401085`. The required displacement is
`0x401090 - 0x401085 = 0x0B`, decimal 11. Little-endian four-byte storage is
`0B 00 00 00`.

Adding eleven to `P` instead reaches `0x40108C`, four bytes short of the
symbol. The field starts before the base the CPU uses. That is why the
relocation rule with ELF's field coordinate is `S + (-4) - P`.

The compiler reserved the bytes and produced the relocation record. The
Forth linker overwrites the field after definition selection and placement.
The CPU consumes the completed field later, while the target runs. The
linker does not have to execute the call to calculate it.

**Common wrong answer:** using the opcode address, `0x401080`, as `P` gives
12 under the relocation formula. That substitutes a different coordinate.

**Check separately:** correct next-instruction base; displacement; stored
byte order; linker as patcher; CPU as later consumer. A correct final number
alone does not establish those distinctions.

### Solution G1-03 — Complete the record

This is a `PLT32` call relocation of width four bytes with addend `-4`.

```text
S                 = 0x401150
P                 = 0x401121
A                 = -4
Next instruction  = 0x401125
Field             = S + A - P
                  = 0x401150 - 0x401125
                  = 0x2B = 43
Stored bytes      = 2B 00 00 00
CPU destination   = 0x401125 + 43 = 0x401150
```

The value fits a signed four-byte displacement. We were given virtual
addresses after placement, not a location within the object file. No
symbol-table index was supplied either; inventing one would add no evidence
about the destination.

**Common wrong answer:** `0x2F`, decimal 47, is the distance from the field
start to `S`. It forgets that the CPU adds after consuming four field bytes.

**Check your record:** name the relative operation as well as width. “It is
four bytes” does not select the formula, because the linker admits absolute
four-byte kinds too.

### Solution G1-04 — Move one thing

The baseline values are relative displacement 11 and absolute pointer
`0x401090`.

For the **caller-only move**, new `P` is `0x4010A1`, so the next instruction
is `0x4010A5`. The symbol remains `0x401090`:

```text
relative field = 0x401090 - 0x4010A5 = -0x15 = -21
absolute value = 0x401090 + 0 = 0x401090
```

The negative distance means backward from the next instruction. It is not
an invalid function address. The absolute pointer is unchanged because its
consumer needs the destination itself, regardless of the pointer's storage
location. Negative-byte encoding was not requested.

For the **callee-only move**, restart from the baseline. New `S` is
`0x4010C0`; `P` remains `0x401081`:

```text
relative field = 0x4010C0 - 0x401085 = 0x3B = 59
absolute value = 0x4010C0
```

Both values depend on `S`, so both change. The relative field increases by
48, the decimal value of `0x30`.

**Check your explanation:** the reason is the consumer's relative or
absolute interpretation, not an inherent distinction between four and eight
bytes. Also check that the second case restarts from the original placement;
carrying forward the first move answers another question.

### Solution G1-05 — Locate the broken promise

The failing stage is final linking, assuming the other setup and inputs are
valid. `main.o` can contain a declared call whose strong reference to
`answer` remains unresolved. Without `answer.o` or another authorized
provider of that definition, the linker cannot complete that obligation.

Repeating a compatible declaration adds no instructions and no definition.
It does not resolve the missing symbol. This differs from a declaration/type
error rejected while compiling a translation unit.

The repair for the original task is to restore its intended provider
`answer.o` to the link inputs. There is no reason to rewrite the call or
invent another definition. Nor should a report claim that the produced
program crashed: this failure occurs before a completed executable is
published.

**Check your diagnosis:** identify the phase, the unresolved name, why
compilation could precede it, and why declarations do not supply bodies. An
exact diagnostic line is unnecessary and has not been observed here.

### Solution G1-06 — Reconstruct the producers

A sufficient producer account has these edges:

1. An identified initial hex0 translator and annotated seed bytes produced
   the existing seed executable. The driver checks that executable against
   the annotated bytes; the current invocation does not create it
2. Python snapshots inputs and starts that seed with compiler Forth source,
   generated driver text, and each user C source. Forth preprocessing,
   compilation, and object writing produce `main.o` and `answer.o`
3. On a runtime cache miss, the same selected Forth compiler compiles runtime
   C with its runtime headers. Compiling `startup.c` supplies `startup.o`
4. Forth support builders emit `start.o` and the six other support objects.
   `start.o` comes from `cc-sysrt-runtime-start-object`, not from a C source
5. The Forth archive builder packages non-start runtime objects into
   `libseed.a`. The Forth linker consumes eager `start.o`, the two ordinary
   user objects, and needed archive members to produce the executable
6. Python publishes the completed executable at `seven`. Only a later load
   and execution starts the target process

A verified cache replaces fresh runtime-object production with checked
reuse. Its copied objects retain their earlier producers. The driver still
builds the runtime archive from those objects and links; cache reuse is not
proof that the runtime was rebuilt during that invocation.

At runtime, `_start` calls `__seed_init_runtime` and then `main`; `main`
calls `answer`, receives seven, and returns seven. Startup passes it to
the C exit wrapper using RDI; handlers and pending output precede
_Exit’s syscall 60. The initializer's `startup.o`
and the eager `start.o` must not be merged into one imagined artifact.

**Rubric:** include source-to-object, support-byte-to-object, archive, link,
and execution boundaries; name Python's orchestration role; retain runtime
headers and seed provenance; distinguish cache reuse. Omission of an
individual library algorithm is acceptable. Omission of the runtime itself,
or claiming GCC or TinyCC generated this program, changes the ancestry.

### Solution G1-07 — Keep contracts separate

- “C int uses four bytes” describes the selected **data layout**
- “The integer result returns in RAX” describes the **calling convention**
- “Compilation produces ET_REL” describes the **output format**
- “Forth cells use eight bytes” describes the **compiler implementation's
  representation**

Layout describes stored values; the calling convention describes cooperation
at a call boundary; output format describes an artifact; the implementation
uses its own representation while producing that artifact. A claim about one
does not logically choose the others. In particular, neither an eight-byte
Forth cell nor the 64-bit RAX register implies an eight-byte C `int`.

With RSP `0x8000` (32768) before CALL, storing the eight-byte return address
makes callee-entry RSP `0x7FF8` (32760). The first value is divisible by 16;
the second is eight bytes below such a boundary. The required pre-call state is aligned,
and the changed entry state is expected. Do not label the call invalid by
checking the rule at the wrong moment.

**Check your explanation:** all four classifications; distinction between
stored width and register carrier; subtraction of eight; alignment tested
before CALL. “System V means 64-bit” does not identify these separate facts.

## Changed-task checks

Open these only after attempting the changed prompts. If an answer differs,
locate the first disagreement in the stated contract before changing your
arithmetic.

### Check G1-01 — A declaration without a use

Under the supplied export rule, the unused external declaration does not
force an undefined `answer` into `main.o`'s demands. The changed `main`
returns literal seven without calling `answer`. Omitting `answer.o` therefore
does not create the original missing-definition failure. Default startup and
runtime requirements remain.

Accept an explanation that distinguishes a name being declared from that
name being needed in emitted code. Reject “every declaration must have a
body in the final executable” as too broad for this contract. Linking alone
is still not an observation of the program running.

### Check G1-02 — Inspect a wrong field

The CPU starts at `0x401085`, so adding decimal 15 (`0x0F`) reaches
`0x401094`, four bytes past `answer`. The proposal used the field start as
the CPU's base. Correcting the base gives displacement eleven, not a new
symbol address. A complete answer must show both reached addresses and the
coordinate error.

### Check G1-03 — An absolute field of the same width

The field stores `0x401150`, with bytes `50 11 40 00`. Its contract is an
unsigned absolute relocation with `A=0`, so no subtraction of `P` occurs.
The supplied representability assumption permits the four-byte encoding.

Accept answers that choose the operation from the relocation kind and
consumer, then choose the encoding from its width. “Four bytes means
relative” is the specific generalization this task challenges.

### Check G1-04 — Move both together

New `P` is `0x4010A1`; new `S` is `0x4010B0`. The next instruction is
`0x4010A5`, and the distance to `0x4010B0` remains eleven. Algebraically,
adding `0x20` to both `S` and `P` cancels in `S + A - P`.

The absolute pointer becomes `0x4010B0`, whose eight bytes are
`B0 10 40 00 00 00 00 00`. An absolute destination changes when the
destination moves, even when the caller moves with it. Require both results
and the cancellation argument; the unchanged relative field alone is not
the full answer.

### Check G1-05 — A matching name is not a matching interface

Successful resolution establishes that a provider with the needed name was
found. It does not establish agreement between an `int` declaration and a
`long` definition. The disagreement is in the C interfaces used to compile
the separate translation units, including their different result widths in
this profile.

A repair is to make both sources use the same intended signature, then
recompile the affected source or sources and relink. For the original
exercise, retaining `int answer(void)` in both files preserves the intended
contract. Do not invent a guaranteed link error or return value from the
mismatch: neither was supplied or observed.

### Check G1-06 — Remove the automatic runtime inputs

Neither user object defines `_start`, and the driver still requests that
entry. The linker cannot silently reinterpret `main` as the requested name
or manufacture startup's behavior. The entry obligation is unresolved.

Even a supplied `_start` definition would need its own contract before we
could claim runtime initialization, calling `main` correctly, and passing
its result to Linux exit. A matching name alone establishes none of those
behaviors. Restoring the default startup/runtime inputs restores the
original intended producer path; choosing a custom startup is a different
explicitly specified fixture.

### Check G1-07 — A preserved stack can still be misaligned

Callee-entry RSP is `0x8000` (32768); after RET it returns to `0x8008` (32776).
The arithmetic balances, but pre-call 32776 leaves remainder eight when
divided by 16. Entry happens to be aligned because CALL moved the pointer;
that does not satisfy the rule for
the earlier moment.

RDI has room to carry the integer value while generated expression code is
working. The selected C type still determines four-byte storage and its
conversion behavior. Carrier capacity does not redefine the C data model.

Accept an answer only if it distinguishes balanced restoration, pre-call
alignment, and C storage width. These are three different invariants.

## Evidence for the feedback

The questions and solutions use the chapter's exact-pin source contracts
and explicitly illustrative placements. The changed unused-declaration rule
comes from
[`cc-om-export-needed?`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L426-L457).
The four-byte absolute and relative rules come from
[`lnk-relocation`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/140-cc-link.fth#L448-L494).
Name resolution, rather than cross-file C signature checking, is visible in
[the linker's symbol registration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/140-cc-link.fth#L260-L342).

These are checked paper derivations, not executed fixture results. A
supported solution, an independent attempt, and a later changed-context
attempt provide different evidence. No reader study or observed learning
outcome is claimed.
