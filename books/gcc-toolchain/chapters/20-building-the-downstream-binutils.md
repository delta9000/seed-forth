# Building the downstream binutils

GCC’s assembly needs an assembler, and its objects need a linker. What makes the
downstream tools source-built products rather than host commands that happened
to have the right names?

Follow one regenerated parser into the binutils build, then inspect the six
required executable outputs and retained failures. The early “links in progress”
paragraph belongs to an earlier boundary than the joined driver recipe.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G18 supplies Forth-built oyacc/flex. binutils 2.30 is the selected downstream
source package; its gas/as-new and ld/ld-new are C programs built through the
Forth toolchain. They are distinct from the small Forth object writer/linker
that produces their executables.

## Remove the shipped shortcut from the source view

configure’s verified binutils source view omits shipped generated parser/scanner
C and headers. The original .y/.l descriptions remain so the original Makefiles
regenerate their consumers with supplied oyacc/flex. Hand-written parser headers
remain intact. An omitted generated file has a required producer, not merely a
reason to delete inconvenient input.

The source archive and exact view manifest distinguish pristine release bytes
from the build view. Python, shell, make and source transformation remain
orchestration. No host compiler supplies route objects. A source-built assembler
still runs on the trusted Linux/AMD64 platform.

This graph has two linker generations: 140 links the C-built ld executable, and
that ld later links GCC-produced objects. Calling both “the linker” without
naming the producer and time would hide the reconstruction’s actual dependency
change.

Sources: [source view, generators and build
scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L1-L35).

## Preserve the original selection with explicit overrides

The recipe restores configure-command.json’s environment and LC_ALL=C. Both
YACC/BISON name oyacc and LEX/FLEX name flex, covering the Makefiles’ different
spellings. Empty CFLAGS/LDFLAGS and warning variables remove unsupported flags
explicitly rather than forging compiler feature answers.

The top-level Makefile’s MAKEOVERRIDES behavior can drop warning overrides on
recursion. The recipe builds all-gas, all-ld and all-binutils with make -k, then
invokes the component directories directly to retain the required settings.
Continuation lets the report collect failures across the work set.

The implementation limits jobs to 1–6. One older README command displays -j8,
but it is outside this binutils script’s accepted range and must not become a
tested book card. A reader checking a prospective command should prefer the
actual parser’s admitted options.

Sources: [flags and recursive make
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L12-L35),
[command selection and job
bounds](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L137-L197).

## Require the actual tools, not just their component objects

The requested outputs are gas/as-new, ld/ld-new, binutils/ar, binutils/nm-new,
binutils/objdump and binutils/readelf. Their presence, sizes and SHA-256 hashes
enter the stage-B report. Missing required executables cause nonzero recipe
status; successful configure cannot substitute for a missing link.

Build traces distinguish compile and link invocations and exclude configure
conftests and preprocessing-only calls from this build census. Diagnostics are
grouped after removing source line numbers, but the original per-invocation
trace keeps the concrete context. Grouping similar messages must not erase the
failed unit’s identity.

An object success can coexist with a tool link failure caused by another object
or unresolved runtime name. It is therefore useful to retain individual compiler
and linker outputs even when the top-level make returned a broad error status.

Sources: [six outputs and failed-invocation
reports](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L49-L136).

## Treat built and exercised as different states

A hash proves the named installed bytes match a recorded artifact under the hash
comparison assumption. It does not prove the assembler accepts every instruction
or the linker accepts arbitrary objects. G21 selects actual as/ld inputs and
exercises a freestanding program; Stage C/D use the same identified tools more
broadly.

The pinned documentation contains an earlier account where components compiled
and links were still in progress, followed by later recipes requiring complete
binutils and verifying installed executables. Read them chronologically. Do not
flatten them into either “nothing linked” or “every binutils behavior is
proven.”

No stage-B work directory was created here, and no missing output was rebuilt.
This chapter explains the source and recorded report contract. A later actual
run must retain generator identities, source-view manifest, tool hashes,
failures and command statuses before it becomes new evidence.

Sources: [stage-B report
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L194-L219),
[later joined-toolchain
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L221-L283).

## The output linker is a product before it is a dependency

The direct route first uses the Forth object's bounded linker to create
executable build tools. One of those products is binutils ld. Later GCC output
is linked by that source-built ld. Label the earlier and later consumers on the
graph: the fact that both perform linking does not make them the same executable
or give them the same accepted input format.

Likewise, binutils as is a source-built product that consumes GCC's assembly
output. The Forth compiler does not need to become a general GCC assembly parser
to make that handoff. It builds the assembler's C implementation, then the
resulting executable supplies that service to later compiler output.

The selected binutils build includes more than these two tools, using the
original Make-selected work. Keep each tool's retained executable and report. A
successful assembler build does not imply the linker or archive tool succeeded;
a compiler census does not establish that the final tool was linked and
runnable.

Sources: [source view, generators and build
scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L1-L35).

## Carry regenerated inputs into the original build

Parser and scanner source are prepared through G18's generator chain. The
binutils build consumes those files in its generated view. Record which
generator produced each replacement rather than treating every checked-in
generated file as an unexplained source primitive.

The original Makefiles still decide work after preparation. Running Make in a
keep-going mode permits independent tasks to proceed after a failure, so the
final report must retain failures as well as successes. A large collection of
objects is not a complete six-tool result if one final executable remains
absent.

Concurrency belongs to the actual driver interface. The admitted job range is
one through six in the inspected script. An earlier narrative mention of another
job count is historical context, not authority to override that argument gate.
The newest stage account must be read with its recipe rather than merging every
note into one simultaneous run.

Sources: [flags and recursive make
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L12-L35),
[command selection and job
bounds](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L137-L197),
[six outputs and failed-invocation
reports](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L49-L136).

## Test the service at its new boundary

An eventual assembler check can supply one named assembly file, retain the exact
assembler executable and inspect its output object. A linker check can supply
named objects and retain an executable's entry and segment metadata. The joined
driver test in G21 then asks whether GCC actually invokes these tools.

These checks have different consumers. A product hash identifies the file that
will run; a successful tool invocation demonstrates an admitted input; a
successful target program demonstrates one completed output chain. None should
be inferred merely from an archive of build logs that contains the word
“success” for a different step.

The pinned README contains chronological progress, including earlier incomplete
binutils work and later direct-toolchain results. State those as successive
records. This chapter does not erase the old failure record or present a fresh
build as completed. It explains how the source-built output tools fit the
recorded route and what a later observation would need to retain.

Sources: [six outputs and failed-invocation
reports](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L49-L136),
[stage-B report
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L194-L219),
[later joined-toolchain
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L221-L283).

## Read the six-tool boundary one executable at a time

The requested products are as-new, ld-new, ar, nm-new, objdump and readelf in
their specified component directories. Some consume assembly, some objects or
archives, and some inspect binary metadata. The stage's report records
executable presence, size and digest for each. One surviving product cannot
stand for the complete requested set.

Supply a build where every compile invocation succeeded but ld-new is absent
after the final link. The compilation census is useful evidence about its
selected units. The stage remains incomplete at the executable-output boundary.
Now supply ld-new with a hash but no exercise of it: production identity is
established, while behavior on a prospective object remains pending.

| Tool product | Role in later work | Evidence to retain before use |
|---|---|---|
| as-new | Assembly to object | Actual executable and admitted invocation |
| ld-new | Objects to executable | Actual executable and ordered link inputs |
| ar | Library/member operations | Archive format and member identities |
| nm-new | Symbol inspection | Reported file identity |
| objdump | Binary inspection | Input and requested view |
| readelf | ELF metadata inspection | Input and selected fields |

The table supplies roles rather than a claim that this chapter tested every
tool. The joined driver fixture in G21 exercises a specific as/ld chain. Stage
C/D use the identified archive and other tools under their own recipes. Keep
those observations attached to their actual consumers.

The binutils recipe restores its recorded configure environment, supplies all
Make spellings for yacc/flex and clears unsupported compiler flags. Its
recursive overrides are important because a top-level setting can otherwise be
dropped on entering a component. Follow the command that actually reaches the
component rather than inferring its arguments from the parent command alone.

make -k allows independent work to continue, preserving a larger diagnostic set.
It does not convert a failed final link into a success. Normalized groups
summarize similar messages; raw traces retain which unit and phase supplied
them. A complete report includes both.

The pinned notes are chronological: earlier link work was incomplete, later
toolchain recipes require completed verified products. The chapter explains that
progression without creating a new stage-B work tree or claiming to have rebuilt
missing executables. A future reproduction should retain source view, generator
identities, component commands and every required output.

Sources: [source view, generators and build
scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L1-L35),
[flags and recursive make
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L12-L35),
[command selection and job
bounds](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L137-L197),
[six outputs and failed-invocation
reports](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L49-L136),
[stage-B report
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L194-L219),
[later joined-toolchain
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L221-L283).

## Separate compilation work from build-system work

A binutils component build contains ordinary C compilation, generated-source
prerequisites and final links. The compiler driver participates in some of those
steps, while Make, shell and generator executables participate in others. A
trace should identify the operation rather than attributing every command in the
build directory to the C compiler.

The verified source view removes shipped generated parser/scanner artifacts
while retaining their descriptions and hand-written headers. This makes the
original Make rules invoke the named source-built generators. If a description
is absent or its generator is unavailable, the missing input is an earlier
boundary than C parsing. Supplying a random preexisting generated file would
change the production route.

Configure's retained command environment establishes the compiler and generated
build variables. The stage restores LC_ALL=C and explicit tool overrides. YACC
and BISON both name the selected yacc; LEX and FLEX both name the selected
scanner generator. Using every Make spelling matters because different rules can
consult different variables.

Empty compiler/linker and warning flags keep invocations within the direct
driver's admitted interface. The top-level MAKEOVERRIDES behavior can drop
settings in recursive calls, so the recipe also invokes component directories
with explicit overrides. The command reaching a component is the relevant input
for diagnosing a rejected flag or missing producer.

The recipe uses keep-going to collect independent progress and failures. It does
not promise success for every invocation or every target just because some
component work continues. Final required executables are checked after
compilation and linking, with retained sizes and digests. Missing ld-new still
makes the requested six-tool stage incomplete.

Diagnostic grouping removes incidental source-line details to identify repeated
message kinds. Retained raw traces provide the concrete unit, arguments and
phase. A useful report can say that two failures look alike while preserving
which two attempts failed. Replacing raw evidence with one normalized string
would prevent a later investigator from identifying their actual inputs.

The old account of components compiling while links remained in progress is
historical evidence of a partial boundary. The later joined-toolchain and hosted
recipes require completed installed tools. Their coexistence is a chronological
story rather than a contradiction. The book should let a reader locate both
states without implying that the later work ran again here.

A future bounded reproduction can begin with one generated parser, one component
and one final executable, retaining every producer and input. Completing that
slice would still not replace the stage's six-output condition. This chapter
provides the full selected report contract and roles, with no new binutils build
or exercise.

Sources: [source view, generators and build scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L1-L35), [flags and recursive make policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L12-L35), [command selection and job bounds](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L137-L197), [six outputs and failed-invocation reports](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/binutils.py#L49-L136), [stage-B report boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L194-L219), [later joined-toolchain boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L221-L283).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](19-the-cc1-milestone-and-its-tests.md) remains available for
a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/20-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G20-01 — Name the two linkers

Who produces ld-new and who later uses it? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G20-02 — Find the parser producer

A release ships parser C but the view omits it. What must remain? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G20-03 — Read make continuation

Does make -k turn failed units into successes? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G20-04 — Check jobs

May the book promise a binutils -j8 invocation under this parser? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G20-05 — Preserve diagnostics

What is lost if only a grouped diagnostic count is retained? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G20-06 — Identify outputs

Name the six requested binutils outputs. Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G20-07 — Keep chronology

How should the early “links in progress” paragraph relate to the later driver
recipe? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now build the downstream assembler/linker tools from their selected
inputs. Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G21: A freestanding GCC driver
toolchain](21-a-freestanding-gcc-driver-toolchain.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
