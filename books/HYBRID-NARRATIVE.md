# The main route: get a result, then open its dependencies

A seven-line program can raise a book's worth of questions. Who translates it?
Who supplies its first instruction? What does a function call assume? Why can
two files refer to each other before either knows its final address?

This series will answer those questions in the order a useful result makes
them necessary. Its main destination is the **direct GCC toolchain**. Along
the way, you will make a small Forth word, follow a small C executable, join
two separately compiled objects, and identify the tools behind a GCC-built
program. Finally, you will explain exactly what the later rebuild comparison
establishes.

The main route has five milestones. It is a route through selected stories
and explicit short bridges, not a requirement to finish every preceding
chapter. Complete implementation explanations and the full seed-byte audit
remain available as connected depth routes. Their learning goals remain
larger than those of an introductory slice.

**Current state:** S01–S19, C01–C22 and G01–G25 are paper drafts. The
[short first-results entrance](FIRST-RESULTS.md) and
[G01 two-file story](gcc-toolchain/chapters/01-a-program-from-two-files.md)
provide the first mainline bridges; the [GCC-toolchain series](gcc-toolchain/README.md) now continues through all planned G02–G25 mechanisms and attributed results. New G02–G25 execution, independent manuscript review and reader validation remain pending. This page retains the main route and its future operational obligations. The new examples and
clean-start setup have not been executed. Existing implementation results
retain their own [source and evidence identities](EDITION.md). All source
links below use the same immutable edition.

## See the destination first

The production route has this shape:

```text
starting hex0 translator + annotated seed bytes
    -> seed Forth
seed Forth + extended C frontend + object/link/runtime support
    -> required source generators, GCC 4.0.4, and binutils
that GCC/toolchain
    -> target libraries and musl sysroot
    -> hosted programs and later GCC generations
```

“Direct” means that M2-Planet, pnut and TinyCC executables are not required
compiler ancestors on this branch. It does not remove the frontend,
calling convention, objects, linker, runtime, headers or generated-source
work. The [direct compiler driver](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L254)
selects the System V object profile; it does not invoke those intermediate
compilers.

Linux, CPU behavior, source acquisition and host orchestration remain
prerequisites. The Python, shell, make, text, archive and patch tools used by
a particular recipe must appear in that recipe's record. A source-built
target C library does not replace the host services running the build.

For every result, keep two questions separate:

- **What have I explained?** A supplied compiler can be used through a
  precise interface before its parser is opened. Name where that parser is
  taught and when a task needs it
- **What actually produced the result?** Name executable producers, source
  inputs, target runtime and host support, including a reused cache. A tool
  used only for comparison is a different role from a production ancestor

These questions prevent both extremes: an unexplained success presented as
mastery, and months of implementation detail before a reader sees a program.

## H1. Make a Forth word do something

**Question:** How can a few words preserve an old value, calculate a new one,
and send a byte out?

Begin with [the short first-results story](FIRST-RESULTS.md#a-number-becomes-a-character),
then use [S1](seed-forth/chapters/01-values-and-words.md) for the full composition lesson.
The first stopping point is entirely on paper. Follow the existing
`twice-plus-one` idea, starting with stack `[99, 32]`: doubling the top
value and adding one gives 65. The short
output bridge supplies the meaning of `emit`: request the low byte as
output, consuming the value. ASCII byte 65 is `A`. The complete I/O mechanism
can wait until [S7](seed-forth/chapters/07-linux-io-contracts.md); the distinction
between a request and successful output cannot.

**By the end, you should be able to:** trace every intermediate stack,
explain why an older 99 survives, and distinguish a number left on the stack
from a requested output byte.

**Bring or learn here:** ordinary arithmetic, cells, the top-right stack
notation, explicit literals, a word's inputs/outputs, and a colon-definition
contract. Installation is not an entrance requirement for this paper story.
The later run card must introduce files, redirected input, end-of-input and
output capture rather than quietly assume shell expertise.

**Practice progression:** predict the result; complete a trace with one row
given; reconstruct it without the row. Feedback checks the copied operand,
65, preserved 99 and consumed output value separately, so a correct final
number cannot hide a wrong intermediate state.

**Changed task:** after the [S2 address/byte bridge](seed-forth/chapters/02-addresses-and-bytes.md),
store the result at a supplied valid address with `c!` instead of emitting it.
Success means using the taught value/address order, changing one byte rather
than eight, preserving surrounding bytes and retaining the older 99. This
changes the interface, not just the input number.

**What is supplied:** primitive and colon-word behavior. Their mechanisms
are opened in S08 and the S11–S18 audit. The future runnable checkpoint must
identify its starting translator/seed, environment and actual captured byte;
the present trace does not stand in for that observation.

## H2. Follow a whole C program before opening every compiler part

**Question:** If the source says `int main(void) { return 7; }`, who calls
`main`, and where does the seven go?

The [short C entrance](FIRST-RESULTS.md#seven-goes-somewhere-else) now supplies
the function/return and process bridge. Then read C01's [two-process distinction](c-compiler/chapters/01-compiler-entry-and-profile.md#two-processes-with-a-boundary-between-them)
and [legacy profile](c-compiler/chapters/01-compiler-entry-and-profile.md#name-the-compiler-profile),
then the continuous first story in [C19](c-compiler/chapters/19-translation-units-and-process-entry.md).
It derives a 556-byte output buffer: 120 bytes of headers, a 26-byte entry
stub, 376 bytes of eagerly emitted runtime, and a 34-byte `main`. The call
field starts at offset 130; its destination is 522, so its displacement is
`522 - (130 + 4) = 388`.

There is a satisfying surprise here: most of this tiny program's bytes do
not come from its one statement. That is the reason to open startup and
runtime, rather than memorize their inventory first.

**By the end, you should be able to:** locate entry and `main`, explain the
final patch, distinguish the compiler process from the generated process,
and explain why returning seven does not print seven. Buffer construction,
successful file writing, loading and execution are separate events.

**Bring or learn here:** a function/return primer, byte offsets and
little-endian fields, file positions versus virtual addresses, and a small
CALL/RET/frame contract. [C09's coordinate bridge](c-compiler/chapters/09-instructions-inside-an-executable.md#one-byte-three-coordinates)
and C19's local key supply the existing coordinate and frame facts. The
short H2 entrance supplies its function/return primer without requiring a
Forth implementation excerpt. A later excerpt-reading session needs its
local Forth bridge. The complete native seed audit is not required.

**Practice progression:** complete the layout with body lengths supplied;
derive the call field; explain the entry-to-exit path without looking at the
worked table. Assess both arithmetic and the actor/time of each step.

**Proposed changed task:** stipulate an admitted unused helper whose emitted
body is 34 bytes, placed before `main`. Predict which values move: `main` becomes 556, total
size 590 and displacement 422. The entry remains at offset 120, and the
specified `main` still returns seven. A helper after `main` changes the total
size without moving that entry-call target. Explain the source-order cause.

**What is supplied:** the full Forth compiler, its preprocessing pass,
runtime bodies and bounded output writer. This input needs no include or
macro expansion lesson, though preprocessing still occurs. The legacy
compiler emits ELF directly; it has no external assembler dependency waiting
to be removed by C21.

After the first result, return to [C01's triangle](c-compiler/chapters/01-compiler-entry-and-profile.md#derive-the-triangle-before-opening-the-compiler).
Now arrays, loops and copied function arguments answer concrete questions.
Use the first stories in C12, C13, C16 and C18 as those questions arise. The
full C01–C19 implementation route remains available for deeper reconstruction.

## A short lesson in replacing one dependency

Before introducing objects, use [C22's handoff](c-compiler/chapters/22-two-pass-assembly-and-bootstrap-handoff.md#reference-the-assembled-program-becomes-the-next-assembler)
as a compact case study. On the **M2 branch**, the Forth compiler builds M2;
M2 emits M1 text; the Forth assembler turns that text plus supplied companions
into another M2 executable. M2 and the Forth assembler then build M1 and hex2.

At the handoff, those new tools assemble the **same** `self-v1-amd64.M1`
input. The recipe compares the resulting `cc-out-v2` with `cc-out-v2-fasm`.
That is a well-defined replacement: named input, replaced service, output
representation and acceptance rule. The later equality of `self-v2` and
`self-v3` M1 text is a different claim. See the actual
[replacement and later comparisons](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L222-L264).

This short example belongs in the main narrative. Executing the complete M2
route, studying its upstream compiler, and completing C20–C22's full assembler
lab are optional depth. None is a production prerequisite for direct GCC.

## H3. Join two objects that could not know each other's address

**Question:** How can a caller refer to a function in another file, and how
can the two agree about a call?

The [G01 paper entrance](gcc-toolchain/chapters/01-a-program-from-two-files.md)
now follows two small sources: one defines
`answer()`, returning seven; the other declares and calls it. The direct
profile produces separate **ET_REL objects**, then the Forth linker joins
them with explicitly identified startup/runtime inputs. Its command card is source-checked but unexecuted; exact object dumps and
actual fixture addresses remain to be established. The selected call record
and illustrative placement teach the interface without inventing a dump.

**By the end, you should be able to:** separate an object from an executable,
identify a definition and unresolved use, explain a relocation's symbol,
field and addend, derive one patched field, and state the scalar System V
call/result/alignment promises.

**Bring or learn here:** H2's coordinates and two processes; declaration versus
definition; separate translation units; object sections, symbols and
relocations; the selected data model and ABI. LP64 sizes do not specify a
calling convention. C18's [alignment counterexample](c-compiler/chapters/18-functions-and-call-frame-accounting.md#balanced-is-not-necessarily-aligned)
explains why the legacy convention must not be silently reused.

**Practice progression:** first label the two files' definitions and uses;
then complete a relocation calculation; finally account for the joined
program's producer chain. A clearly illustrative PC-relative field with
`S=0x401090`, `P=0x401081`, `A=-4` gives `S+A-P=11`, hence four bytes
`0B 00 00 00`. This is the
[linker's stated formula](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/140-cc-link.fth#L464-L493),
not a claimed object dump from the proposed fixture.

**Changed task:** use an eight-byte absolute pointer to the same symbol,
supplying the `S+A` rule. Move the caller and callee independently. Success
means choosing the right relocation kind and width, then explaining why a
caller move affects the relative field but not the absolute pointer when the
symbol stays put. A missing-definition case follows once that distinction is
secure.

**What is supplied:** the rest of the object, archive, linker and target
runtime implementation, behind named interfaces. G01 supplies the first continuous path; G02/G04/G05/G06
will open the needed implementations; G03 and G09 will supply the needed
shared declaration/initializer mechanisms. Building TinyCC first is not an
entrance condition.

### Shared machinery stays on the main route

The direct driver loads common native support before selecting different
providers. “Optional TinyCC” must therefore never mean “all native frontend
code is optional.” The source shows specific reuse:

- [Object-mode selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L441-L448)
  enables System V; the object-program driver rejects a remaining
  runtime-initializer queue
- [System V translation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1337-L1346)
  uses the shared native declaration machinery
- [Object initializer handling](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L178-L180)
  calls `cc-ni-value` from the shared initializer traversal

G01 introduces the LP64/profile change. G03 owns shared declarations,
descriptors and initializer structure; G09 owns static constant/relocation
lowering. G04/G15 own the selected call providers, and G06 the direct startup
and runtime boundary. C23/C24 retain the private-stack ABI and TinyCC route
as an optional complete application. The depth map will account for every
shared definition; these selected edges are not a claim of that future audit's
completion.

## H4. Let GCC produce a program, then supply its output tools

**Question:** If a source-built GCC compiler proper (`cc1`) has emitted assembly, what is
still missing before its toolchain can produce an executable?

This milestone has three visible stopping points: a real generator and its
output; GCC `cc1` and assembly; then the driver with source-built binutils
producing a no-header freestanding program. Name each result for what it is.
The main story follows one producer before showing the full source census.

**By the end, you should be able to:** follow generator source → generator
executable → generated source → object; explain why generated C remains an
input; and identify the actual compiler, assembler and linker behind a
program.

**Bring or learn here:** H3 objects/linking, source identity and preparation,
headers and predefines, configure's host/build/target choices, and basic
scanner/parser roles. C03–C05's preprocessing mechanisms now have an immediate
purpose: a real header or generated source needs them. Teach the relevant
mechanism before asking for its diagnosis.

**Practice progression:** read a small authentic producer record, label each
artifact's representation and consumer, then distinguish production tools
from test support. The early `cc1` torture tests use host assembly/link and
header support. Their success cannot be relabeled as a closed source-built
output toolchain. The later
[binutils and driver route](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/driver.py#L76-L169)
provides the needed output tools. At the freestanding stage, do not infer
host-header independence from a sample that includes no headers.

**Changed task:** examine the actual temporary-flex handoff. Heirloom lex
produces a temporary scanner; `flex-tmp` regenerates flex's scanner; the new
scanner object replaces the old one before final flex is linked. Identify
what changed and which downstream artifact used it. The
[recipe](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/lexers.py#L116-L143)
is the source of the acceptance conditions; do not invent an equality gate
merely because another bootstrap example had one.

**What is supplied:** most GCC internals and generator internals after their
input/output role is clear. The oyacc → Heirloom lex → temporary flex → final
flex chain contains actual production producers. Optional host-GCC lint and
host-supported tests have separate roles. Full floating, aggregate, variadic,
header and runtime mechanisms remain in G03–G16, with required interfaces
taught before use and implementation exercises requiring their depth sessions.

## H5. Build a hosted program and interpret a rebuild

**Question:** What does ordinary C still need beyond the compiler, and what
does agreement between later compiler builds tell us?

Follow the
[target-library and musl stage](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L164-L259)
to libgcc/libgcov/crt, an explicit musl sysroot and a selected static hosted
program. The recipe installs musl source headers before compiler
configuration; GCC subsequently builds target libraries, rather than
producing those source headers. Then trace who builds GCC stages 2, 3 and 4 and exactly which
artifacts are compared. This finishes the promised toolchain story.

**By the end, you should be able to:** attribute runtime, startup and header
producers; reconstruct compiler ancestry; distinguish behavior from byte
equality; and explain the archive comparison rule and remaining dependencies.

**Bring or learn here:** H4's producer graph; runtime versus compiler; target
headers versus their implementations; archive member identity/order; and
controlled source, configuration and path inputs. G16 supplies the archive
bridge, G22 hosted closure, and G23–G25 the rebuilding and comparison story.

**Practice progression:** interpret a bounded comparison report. Distinguish
equal ordinary files, equal-size but unequal files, archive containers whose
member names/order/content agree, and a comparison that failed to run. The
[Stage-D rules](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L99-L189)
select actual installed files; the documented 54-file result is a recorded
result, not a hardcoded gate for every run.

**Changed task:** after an intervening activity, examine two valid sorts that
order equal-key records differently. A generator numbers records in that
order. Explain how sorted keys can agree while generated bytes differ, and
propose a comparison that would locate the first difference. G24's tie-order
story supplies this mechanism before the capstone asks for it. Assess the
causal explanation and diagnostic choice, not familiarity with a filename.

**What is supplied:** library algorithms not needed for the selected trace,
with their source and later explanation named. Source-built target libraries
do not eliminate the build host's libc or Linux. Equality under a specified
comparison does not prove general correctness, benign sources or Linux boot.

## Where the alternate routes belong

| Route | Place in this series | What must not be inferred |
|---|---|---|
| Complete seed-byte audit | S11–S19, an independent audit route and capstone | Using Forth contracts does not earn the all-bytes audit objective |
| Full default C implementation | C01–C19, a coherent reconstruction route | Finishing H2's slice does not establish parser/emitter mastery |
| M2, Forth assembler, M1/hex2 | Short replacement case on the main route; full C20–C22 lab and lineage comparison optional | M2 is not a required ancestor of direct GCC; Stage A's GCC reference is an oracle |
| pnut | Optional comparison and alternate bootstrap route | Forth-built pnut does not universally descend from M2 |
| Direct TinyCC | C23/C24 optional private-profile application and closure | pnut-kit source provenance does not imply a pnut executable ran |
| Historical GNU/compiler ladders | Optional lineage comparisons | A newer compiler reached by another route does not establish direct-GCC ancestry |
| Kernels and Linux | Separate K01–K08 continuation | A TinyCC-lineage smoke or supplied-kernel handoff is not a direct-GCC-built Linux boot |

The distinct pnut routes are visible in the
[i386 comparison](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/pnut/sf-pnut-check.sh#L80-L151)
and [amd64 recipe](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/amd64.recipe#L10-L68).
The [direct TinyCC recipe](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/tcc.recipe#L15-L87)
and its [source-provenance account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/REPRODUCIBLE.md#L589-L655)
keep source reuse separate from executable ancestry. The
[K1 record](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/k1/README.md#L255-L281)
has its own lineage and limits. A direct-GCC kernel chapter needs its own
kernel/configuration/image provenance and observed boot/userspace acceptance.

## Preserve the depth; change when it is needed

The [unit-by-unit narrative map](narrative-map.csv) assigns every stable S/C/G/K
unit a first-reading role, milestone home and retained depth. The
[coverage map](COVERAGE.md) continues to account for every original chapter
and appendix. The [learning path](LEARNING-PATH.md) keeps the full-depth
prerequisites, rather than quietly certifying them after a short bridge.

A bridge teaches an interface needed now. A depth session opens its mechanism.
An optional route has a different chosen destination. These are different
reasons to defer material. No chapter, source explanation or exercise is
removed by this plan. Existing mixed checks retain their actual prerequisites;
a reader who took the short route needs the named depth sessions before
attempting a depth-dependent check.

Each new first session should stay physically continuous: puzzle, prediction,
mechanism, payoff and a small changed case. Put provider inventories and
unneeded variants afterward. Keep an assumption where it affects an inference,
then collect the larger evidence account once. Short sessions are defined by
a resolved question, not by padding or a promised reading speed.

Practice progresses from a worked example to a completion problem, an
independent reconstruction and a changed task. Keep hints and solutions
separate; record whether help was used. Later mixed checks remove chapter
labels as cues. Confidence, enjoyable reading, immediate performance,
retention and transfer need separate observations; one cannot stand in for
another.

## Next writing and validation

1. Keep the completed H1/H2 paper entrance usable without installation.
   Complete and validate its separate runnable setup cards with exact source,
   reset state, environment, command and retained output
2. Review the drafted G02–G16 implementation sessions after G01. The first
   two-file story now names the shared native/LP64 interfaces, runtime-aware
   startup and lazy archive; preserve their full-depth source homes
3. Review the drafted G17–G25 generator → output tools → hosted → rebuild route.
   Open a mechanism when a concrete source or failure needs it, while naming
   all supplied production components from the start
4. Validate each new fixture before calling it observed; then use independent
   reader attempts to find missing prerequisites and assess the intended
   outcome. Delayed and changed tasks need their own evidence

A preview shows the destination. A paper derivation explains a predicted
result. A retained run establishes an observation under its actual conditions.
A reader's independent attempt establishes a different kind of evidence.
The series will keep those achievements distinct while building toward all
four.
