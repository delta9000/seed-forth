# Hosted closure with libgcc and musl

A no-header executable can run without answering who supplies printf, startup
objects or compiler-generated arithmetic helpers. What new producer edges make a
normal hosted program possible?

Follow Stage C from headers through compiler, libgcc and musl into its hosted
hello. The recipe and recorded account supply the evidence; this chapter does
not run a new Stage C build.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G21 supplies the joined compiler/output-tool chain. A **sysroot** is the
selected target header/library tree. **libgcc** supplies compiler support
routines; musl supplies the target C library and process-startup objects. These
target dependencies are distinct from host tools orchestrating the build.

## Install target declarations before configuring consumers

The recipe verifies musl 1.1.24’s archive and unpacked source against its pins,
then uses the original Makefile install-headers rule to populate
WORK/sysroot/usr/include. That header step requires no target compiler. It
occurs before configuring GCC, allowing GCC’s own header decisions to describe
musl rather than host /usr/include.

GCC configuration receives both --with-binutils WORK/toolchain and
--with-sysroot WORK/sysroot. Target headers and libraries live beneath that
root’s usr/include and usr/lib; assembler/linker defaults remain the verified
source-built paths. C-only native AMD64 is the selected build/host/target
profile.

This does not erase configuration probes. Their actual frozen Forth
compiler/runtime remains the producer. The new target-header tree is a named
input whose hash and installation commands belong in the step record.

Sources: [inputs, headers and configuration
ordering](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L11-L25).

## Build the compiler with Forth, its libraries with GCC

The census builds cc1 with Forth, then Makefile rules build xgcc, cpp, collect2
and specs with that same producer. GCC’s Makefile next uses its GCC_FOR_TARGET
xgcc/cc1 to build libgcc.a, libgcov.a and crtbegin/crtend variants through
stmp-multilib.

That is a producer transition. Forth is the immediate compiler for the first GCC
executable; that GCC is the immediate compiler for target support libraries.
Saying every Stage C object came directly from Forth would erase the new
capability. Saying host GCC built libgcc would introduce a nonexistent
production ancestor.

GCC is installed into WORK/gcc/install with its private headers, libraries and
crt objects. Combined-tree links and the install-tools/include directory supply
build-tree layout expectations. They are identified adjustments, not silent
source patches.

Sources: [producer transition and build
adjustments](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L24-L54),
[libgcc and
installation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L180-L243).

## Let musl’s own build populate the target runtime

musl’s original configure and Makefile run out of tree with CC set to the
installed Stage C GCC and AR/RANLIB set to identified source-built tools. It
builds static libc.a and crt1.o, crti.o and crtn.o, then installs with DESTDIR
into the sysroot under prefix /usr.

The installed compiler itself still uses the source-built seed runtime on which
its Forth-produced executable was linked. A program that this GCC compiles can
use musl instead. Builder runtime and generated program runtime are different
environments, just as G01 separated compiler process from target process.

No GCC or musl source file is patched in this Stage C recipe. The configured
Makefile’s STMP_FIXINC is emptied, gsyslimits.h supplies syslimits.h and
combined-tree links are added. Changing build-tree orchestration is still a
recorded dependency; it is not claimed to be an untouched build directory.

Sources: [source versus build-tree
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L40-L54),
[musl
configure/build/install](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L244-L265).

## Let the hosted fixture exercise the new edges

The hello source uses formatting, allocation, sorting, integer/string
conversion, long-double output, a stdio file round trip and 128-bit division. It
is compiled with plain installed gcc -static -O2, relying on default startfiles
and target libraries rather than -nostdlib.

The recipe captures program output and compares it with stage-c-hello.expected.
It also runs the identified nm and requires __divti3, showing the fixture linked
the intended libgcc helper. Merely returning zero would not expose whether that
compiler support edge was exercised.

Long-double formatting in this generated hosted program is musl/GCC behavior.
G10/G13’s Forth producer now supplies x87 computation and exact floating
formatting, but it retains separately bounded
printf contracts. A product can grow beyond its producer’s implementation
surface without retroactively granting those features to the producer.

Sources: [hello output and libgcc
witness](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L267-L285),
[hosted fixture
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/gcc/stage-c-hello.c#L1-L62).

## Retain step completion rather than a single hopeful status

The nine ordered steps are inputs, headers, configure, cc1, driver, libgcc,
install, musl and hello. Each report keeps commands, exit statuses, time, logs,
input/output hashes and reached/not-reached state. --resume skips steps recorded
successful in an existing work directory; it is reuse, not an automatic fresh
execution of every edge.

Host target tools are guarded during the post-configuration make sequence, with
attempts logged. Host Python/shell/make and platform services still run
orchestration. The recorded direct-GCC account describes the hosted closure;
this book adds no new report directory or measurement.

G23 can now name Stage C GCC as the producer of stage 2. That later build uses
musl as its own runtime, making the runtime change relevant to G24’s equal-key
sorting and G25’s byte-comparison predicate.

Sources: [retained and resumed
steps](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L56-L59),
[step
report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L287-L302),
[Stage C
account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L285-L309).

## Put headers before the questions that need them

Stage C installs the selected musl headers before configuring the target
compiler and runtime build. Header availability can influence configuration and
compilation decisions, so this is an input dependency rather than a cosmetic
installation order. A sysroot containing libraries later does not repair an
earlier probe that saw the wrong headers.

The first GCC compiler remains a Forth-built product in this sequence. Once
available, that compiler builds libgcc and musl. Draw this handoff explicitly:
Forth to first GCC; first GCC to target runtime objects and libraries. “All
source built” is true at the named stages only when the source and actual
executable producer for each arrow remain identifiable.

The script's nine steps retain generated build views and required adaptations.
Build-tree Make adjustments are different from rewriting upstream C
implementation files. Both can affect the recipe, but their scope and retained
provenance differ. A reader should be able to locate the adjusted build input
without being told that all upstream inputs were magically unchanged.

Sources: [inputs, headers and configuration
ordering](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L11-L25),
[producer transition and build
adjustments](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L24-L54),
[libgcc and
installation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L180-L243).

## Close the target link with the right kinds of inputs

A hosted program needs declarations during compilation and implementations
during linking. Startup objects establish entry and call main; libc supplies
ordinary runtime services; libgcc supplies compiler-generated helpers when the
source's operations need them. The sysroot organizes these inputs, but its
directory name is not evidence that every required file exists.

The Stage C fixture includes a use requiring the selected wide integer division
helper. That makes libgcc a concrete dependency in the exercised chain. A small
program using only int addition could run without exposing this missing runtime
component, so its successful exit would be a weaker hosted-closure check.

The fixture also exercises formatted output and other hosted behavior. Those are
products of the newly built target runtime and compiler handoff. In particular,
later long-double formatting does not broaden the seed stdio formatter's
supported conversions. G13's limits remain true for that earlier runtime.

Read the hosted test's producer list together with its output. GCC, assembler,
linker, startup objects and libraries all contribute. A matched message without
input identity could have come from a different toolchain. A complete set of
library hashes without a target run would identify inputs while leaving behavior
unobserved.

Sources: [source versus build-tree
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L40-L54),
[musl
configure/build/install](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L244-L265),
[hello output and libgcc
witness](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L267-L285),
[hosted fixture
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/gcc/stage-c-hello.c#L1-L62).

## Make the hosted boundary an entrance to rebuilding

The completed installed Stage C toolchain becomes the starting compiler for
Stage D. Its ability to compile a named hosted fixture makes this handoff more
substantial than a cc1 binary that produces assembly only. The next question is
whether it can rebuild GCC and its runtimes under controlled inputs.

That question adds path, generated-parser and sorting inputs that can affect
bytes even when the target behavior remains acceptable. Stage C's successful
hosted output is therefore neither a prediction of byte equality nor a universal
compiler-correctness claim. Preserve it as one observed capability in the
recorded route.

This chapter supplies the dependency order and explains the retained fixture. It
does not create a fresh sysroot, compile musl, reproduce the nine steps or
record new output. The later generation comparisons remain separately attributed
evidence with a narrower declared equality predicate.

Sources: [retained and resumed
steps](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L56-L59),
[step
report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L287-L302),
[Stage C
account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L285-L309).

## Witness each library edge in the hosted fixture

The hosted source includes stdio, stdlib and string declarations, uses allocated
strings and sorting, formats several numerical kinds and performs wide integer
division. These uses give the fixture more coverage than a program that merely
returns zero. Each still has a named finite input and expected result rather
than universal runtime evidence.

The wide division uses a volatile divisor to keep the intended operation from
disappearing as a constant-folded value. The recipe requires __divti3 in symbol
output, witnessing the selected libgcc helper edge. A printed integer result
alone could fail to show whether that helper was actually part of the
executable.

The temporary-file round trip supplies another concrete boundary: writing
formatted text, resetting position, reading a line and writing it to stdout.
Allocation and string copying exercise different runtime objects. The exact
expected output is retained in its own source file. No output text is invented
from memory by this chapter.

| Fixture feature | Dependency it makes concrete | Limit of the witness |
|---|---|---|
| Header declarations | Intended target include inputs | Not every header branch |
| Wide division | libgcc helper | Not every arithmetic helper |
| Formatted output | GCC-built musl stdio | Not seed formatter expansion |
| Allocation/string copy | Target runtime storage and bytes | Not all failure behavior |
| Temporary-file round trip | Hosted file/position services | Not every device or filesystem |

The first compiler producing this program still runs on the earlier seed
runtime. The program runs with its selected target musl. Mixing these two
runtimes would make the sorting and formatting account incoherent: target
behavior does not change the runtime already linked into the producer.

Resume handling can skip earlier successful steps while retaining their records.
A resumed Stage C run should report reused headers/libgcc work as reuse, not as
fresh production. Input identities still matter for both paths. A partially
populated directory without those successful records is not equivalent to a
finished previous step.

The chapter reads the Stage C sequence and fixture at the immutable pin. It has
not installed headers, built libraries, opened a target tmpfile or captured new
expected-output agreement. The recorded hosted closure supplies a concrete
starting compiler for rebuilding, while the next chapters ask separately about
controlled paths and generated-byte equality.

Sources: [producer transition and build
adjustments](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L24-L54),
[libgcc and
installation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L180-L243),
[source versus build-tree
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L40-L54),
[musl
configure/build/install](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L244-L265),
[hello output and libgcc
witness](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L267-L285),
[hosted fixture
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/gcc/stage-c-hello.c#L1-L62),
[retained and resumed
steps](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L56-L59),
[step
report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L287-L302),
[Stage C
account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L285-L309).

## Read a resumed Stage C record without inventing new production

Stage C is a sequence of dependency-bearing steps. Headers precede consumers
that configure and compile against them. The first GCC compiler becomes the
producer for libgcc and musl. Target startup and libraries then enter a hosted
program link. The resulting installed compiler/sysroot can become Stage D's
starting input.

An interrupted run can resume through the script's recorded completed steps. If
a step is skipped because its earlier successful record is reused, report reuse.
Its outputs retain their earlier producer and input identity. The presence of a
file with a familiar name is not enough to assign it to a successful earlier
step without the retained record.

This matters particularly for generated and configured views. Build-tree
adjustments, header links and the cleared fixincludes stamp rule are actual
inputs to the successful recipe. A resumed run should not hide them by
describing the whole source as pristine and unmodified. Equally, the Makefile
adjustment is not an arbitrary patch to GCC's C implementation.

The hosted fixture makes several dependencies visible. It uses GCC's target
declarations, a real wide-division helper, musl allocation/string/sort services
and formatted output. Its long-double formatting is computed by the later
GCC/musl product, beyond the Forth producer's opaque transport limit. The
fixture's temporary-file round trip adds another hosted service with its own
failure branches.

The first cc1 still runs on seed runtime. The generated hosted program runs with
target musl. This distinction keeps producer behavior separate from product
behavior. It also prepares the later sorting diagnosis: changing the executing
compiler's qsort can change generated bytes even when the target libraries
remain identified inputs.

A successful hosted run must retain exact output and process status alongside
the tools, startup objects and libraries that produced it. The script's __divti3
symbol check adds an explicit witness for the intended libgcc edge. A generic
hello message would not show that the wide helper was actually linked.

Stage C's capability is broader than G21's freestanding fixture and narrower
than all possible hosted C programs. It supplies a concrete toolchain with named
target runtime closure. Stage D then asks a different question about later
generations and artifact agreement. A stage-C output match cannot imply that
later equality before the comparisons occur.

The chapter has read the nine-step recipe, prepared inputs, resume boundary and
fixture at the edition pin. It has not run or resumed Stage C, calculated new
library hashes or opened target files. Its attributed result remains useful as
the next producer in the recorded lineage, with fresh reproduction a separate
task.

Sources: [inputs, headers and configuration ordering](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L11-L25), [producer transition and build adjustments](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L24-L54), [libgcc and installation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L180-L243), [source versus build-tree policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L40-L54), [musl configure/build/install](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L244-L265), [hello output and libgcc witness](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L267-L285), [hosted fixture source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/gcc/stage-c-hello.c#L1-L62), [retained and resumed steps](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L56-L59), [step report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L287-L302), [Stage C account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L285-L309).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](21-a-freestanding-gcc-driver-toolchain.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/22-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G22-01 — Order the headers

Why install musl headers before GCC configure? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G22-02 — Name immediate producers

Who builds cc1 and who builds libgcc in Stage C? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G22-03 — Separate runtimes

Does a musl-linked target imply the Forth-built cc1 runs on musl? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G22-04 — Classify adjustments

Is clearing STMP_FIXINC a GCC C-source patch? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G22-05 — Witness libgcc

Why require __divti3 in hello’s symbol output? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G22-06 — Report resume

A resumed run skips already successful headers/libgcc steps. Were they rerun?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G22-07 — Bound hosted closure

Does this recipe establish Linux kernel boot or every hosted C program? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

## What this mechanism makes available

You can now reach a static hosted program using named libgcc/crt/musl/sysroot
inputs. Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G23: Rebuild lineage and controlled
paths](23-rebuild-lineage-and-controlled-paths.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
