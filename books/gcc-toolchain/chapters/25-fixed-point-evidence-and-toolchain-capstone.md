# Fixed-point evidence and toolchain capstone

Two archives contain identical object members but different timestamp bytes.
Should a fixed-point check reject them, accept them, or quietly rewrite both
files?

Read Stage D’s actual comparison rule, then reconstruct the entire direct-GCC
producer graph. The destination is a bounded GCC 4.0.4 toolchain result, with
the kernel continuation still open.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G24 supplies the runtime cause of equal-key byte choices. Keep G16’s archive
identities available. A **comparison predicate** specifies which artifacts and
relations count as agreement. A **fixed point** here is agreement of named later
generations under that predicate; it is not a theorem about every program or the
absence of hidden compiler defects.

## The additional plumbing lineage

The newer plumbing route bootstraps native seed-cc/seed-ar, then builds kaem.
Stage 1 uses seed-cc for small stage0 file/hash/unpack tools and GNU make 3.82;
stage 2 uses that make and explicit config.h files for sed, gzip, patch,
diffutils, grep, gawk, tar and 80 coreutils programs. Recipes avoid shell
metacharacters and use no configure script. The lexer and bash stages are
separate: the pin records a lexer-stage execution audit, while completing a
GCC rebuild entirely under replaced plumbing remains outside that result.
The recipe record still lists two coreutils patches and `sed -f`'s rejected
`"rt"` mode; its long-double-gap wording predates the new layer 132, so this
edition does not infer that patch removal or a new rebuild occurred.
See [stages and retained limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/plumbing/README.md#L1-L113),
[lexer audit and final checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/plumbing/README.md#L258-L282).

## Compare the same file inventory first

compare() enumerates relative paths for files in each installed tree, sorts them
and records paths only in the first or second tree. It then compares common
paths by SHA-256. Equal lengths alone are never its acceptance rule. Missing
files cannot be hidden by comparing just gcc and cc1.

Ordinary files with unequal digests enter differing. The report retains the
count of the first tree’s files, both missing-path lists and differing list.
That is the artifact domain: installed file contents under relative paths. It is
not a complete equality test of permissions, directory metadata or all symlink
identities.

For nonarchives, the script does not disassemble and normalize register choices,
paths or padding. G23 controlled path inputs and G24 changed the producing
runtime instead. The ordinary predicate remains exact recorded file-content hash
equality, with the usual digest assumption stated.

Sources: [inventory and content
comparison](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156).

## Compare archive members without claiming container identity

If an unequal file ends in .a, the script asks the identified source-built ar
for its ordered member names, then extracts each named member and hashes its
bytes. Matching ordered name/digest pairs accepts that archive for this
predicate despite different complete-container hashes.

The stated reason is binutils 2.30 ar’s member timestamps. The comparison does
not rewrite the archives or delete arbitrary bytes. It compares a defined
content view. Changing member order, names or payload hashes fails; equal
timestamps alone are irrelevant to payload equality.

This is not an unrestricted proof for every possible archive encoding. The
implementation uses ar t and ar p by name and whitespace-splits the name output;
its intended generated target libraries supply the relevant naming assumptions.
Duplicate or exotic names would require further validation to claim a universal
member-identity check. Keep that bounded implementation detail visible.

Sources: [ordered member-name/hash
fallback](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156),
[archive timestamp
reason](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L547).

## Require both generation edges

The main script builds stage 2, then 3, then 4 and invokes comparison on 3/4 and
2/3. passed is true only when neither comparison has differing, only_in_first or
only_in_second entries. It records stage-4 hashes for gcc, cc1 and collect2 in
addition to the full-tree comparisons.

Supply a paper report where 3/4 agree but 2/3 differs in cc1. It fails this
recipe even though the last pair looks stable. Supply a report where all
ordinary files match and two .a containers differ only in timestamps while
ordered member hashes match. That passes the stated predicate, but must not be
described as raw byte equality of every archive container.

The pinned direct-GCC and sorting documents report the successful controlled
lineage. No new report.json or stage-4 hash has been produced by this chapter. A
source inspection of the boolean is not a new observed fixed point.

Sources: [paired acceptance and
report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L175-L204),
[recorded direct-GCC
endpoint](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L565).

## Reconstruct the producers from the small result

Begin with the identified starting translator and annotated seed bytes producing
seed Forth. The direct driver verifies and runs that seed with selected
frontend, LP64/System V, object, link, archive, constant, floating, bitfield and
aggregate providers. Those produce ordinary runtime objects and executable
source generators.

oyacc produces parser C; Heirloom lex supplies the temporary scanner for flex;
flex-tmp replaces it with flex’s generated scanner. The original GCC Makefiles
select generators and cc1 units; Forth compiles and links the first compiler and
binutils. The joined GCC driver uses those output tools for its freestanding
fixture.

Stage C installs musl headers, builds the first GCC compiler through Forth, then
uses that GCC for libgcc/crt and musl. Its hosted fixture uses the target
sysroot. Stage D uses that compiler for stage 2 and the later generations for
3/4, retaining paths, adaptations and runtime algorithm identity. Every arrow
names an executable producer and its inputs, rather than a directory label
alone.

Sources: [initial direct-profile
production](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L332),
[generator
chain](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/lexers.py#L56-L138),
[hosted producer
handoff](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L11-L39),
[later
generations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L8-L25).

## Retain comparisons without turning them into ancestors

Host syntax lint, generator byte oracles, cc1 torture assembly/linking and the
report-only assembler oracle have different supporting roles. None supplies
production compiler bytes in the recorded direct route. The torture executables
do use host output tools, so their test-chain provenance cannot be concealed by
the narrower production statement.

Python, shell, make, sed, patch, archive acquisition/extraction and the
operating platform remain required at their named steps. A verified seed
comparison does not identify its initial translator by itself. A matched
generator output does not prove the oracle correct. A matched
compiler-generation tree does not prove the compiler has no self-consistent
defect.

The capstone can end confidently with the actual scoped achievement: a
source-attributed direct GCC 4.0.4 toolchain, hosted target inputs and later
installed-generation agreement under the named file/member rule. It leaves
independent learner execution, fresh reproduction, general compiler correctness
and direct-GCC-to-Linux boot as separate obligations.

Sources: [host-supported test
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L437-L455),
[optional runtime oracle
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L76-L91).

## Work through an acceptance report by hand

Supply three installed paths: a compiler executable, a startup object and a
static library. Between two generations, the executable and startup object have
equal content digests. The library's complete-container digests differ, but its
ordered member-name/digest lists match. Under the inspected fallback, these
three paths have no reported content difference.

Add a fourth path present only in the first generation. The comparison now fails
even though every common path passed. Inventory agreement is part of the
predicate. Looking only at the compiler executable's hash would conceal this
missing installed product.

Next retain the same paths but change the library's second member payload. Its
member digest differs and the fallback fails. Keep payload identity separate
from container metadata. The timestamp explanation permits the named
member-content comparison; it does not excuse arbitrary library differences.

Finally, compare stage 2 with 3 and stage 3 with 4. Supply agreement for the
latter pair but one compiler difference for the former. The final passed flag is
false. The recipe asks for both edges, so a single final adjacent match cannot
substitute for its actual condition.

Sources: [inventory and content
comparison](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156),
[ordered member-name/hash
fallback](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156),
[archive timestamp
reason](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L547),
[paired acceptance and
report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L175-L204),
[recorded direct-GCC
endpoint](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L565).

## Trace one final byte backward through the graph

Choose a byte in stage 4 cc1. Its immediate executable producer is stage 3 GCC
together with the named output tools and runtime/build inputs. Stage 3 was
produced by stage 2, which was produced by Stage C. Stage C's first compiler was
produced through the direct Forth route. Continue backward into generated
parser/scanner inputs and the executable generators that made them.

This tracing exercise does not yield one simple chain for every byte. Headers,
generated sources, runtime libraries, build configuration and adaptations enter
along different edges. An oracle that compared one generator output belongs
beside its edge as evidence. It does not become an ancestor unless its bytes
were consumed by production.

The starting seed likewise has a producer and comparison history. A named seed
hash identifies bytes, but the trust account also needs the initial translation
path and assumptions. Later fixed-point agreement does not retroactively
eliminate the starting executable, operating platform or orchestration
dependencies.

Write the graph with two labels on each important edge: the artifact produced
and the event that supports the claim. Some events are source inspections, some
are retained comparisons, and some are attributed executions. A newly derived
paper address belongs in the first category with supplied premises, not in the
execution category.

Sources: [initial direct-profile
production](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L332),
[generator
chain](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/lexers.py#L56-L138),
[hosted producer
handoff](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L11-L39),
[later
generations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L8-L25),
[host-supported test
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L437-L455),
[optional runtime oracle
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L76-L91).

## End with an achievement whose boundaries can be retained

The series has opened independently compiled objects, a selected ABI, runtime
closure, generator ancestry, source-built output tools and hosted rebuilding.
Its endpoint is a recorded direct GCC 4.0.4 toolchain whose later installed
generations agree under the named file/member predicate. That statement can be
inspected and challenged because it retains its domain.

It does not prove that every possible C program compiles correctly. A
self-consistent defect can survive generation agreement. The archive predicate
also has the stated name-based assumptions. Broader compiler trust and semantic
testing require additional evidence rather than a stronger adjective attached to
this comparison.

The direct-GCC-to-Linux continuation remains planned. A historical kernel route
built through a different compiler ladder cannot close that obligation. The next
volume must pin its actual toolchain, kernel inputs, boot contract and
observable outcome. A reader who reconstructs this graph has completed a paper
learning task; a reader who reproduces the build has completed a distinct
operational task. Both can be valuable without confusing one for the other.

Sources: [paired acceptance and
report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L175-L204),
[recorded direct-GCC
endpoint](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L565),
[host-supported test
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L437-L455),
[optional runtime oracle
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L76-L91).

## Keep the capstone graph useful when a claim is challenged

Suppose a reader challenges the statement that the final compiler is source
built. The graph answers with executable producers and consumed artifacts: the
Forth-built first compiler, its generated inputs, the later GCC producers,
source-built output tools, runtimes, headers and retained preparations. An
oracle comparison can support an edge without becoming its executable ancestor.

Suppose the reader instead challenges fixed-point agreement. The report answers
with installed path inventories, ordinary content hashes, archive ordered-member
fallback and both adjacent generation edges. Source ancestry alone does not
answer this equality question. The artifact domain and predicate must remain
explicit.

Suppose the reader challenges compiler correctness for another program. The
fixed point cannot settle that new semantic case. Testing, interface reasoning
and further source analysis are relevant, with their own scopes. A
self-consistent wrong translation can survive generation agreement, so a larger
claim cannot be smuggled through the same comparison report.

| Claim | Required evidence kind | Current scope |
|---|---|---|
| Source ancestry | Producers and consumed inputs | Pinned direct route and adaptations |
| Particular behavior | Identified target run | Named recorded fixtures |
| Later generation agreement | Defined artifact predicate | Installed files/member views for both pairs |
| New reader understanding | Independent attempt and explanation | Pending for these chapters |
| Fresh reproduction | New retained build/run record | Not performed here |
| Direct-chain Linux boot | Selected kernel/boot inputs and outcome | Separately planned |

Archive fallback deserves one final qualification. The implemented ar listing is
split into names and extraction is by name. Intended generated libraries make
that useful. Exotic or duplicate member naming would need more validation before
making a universal archive-reader claim. This is a practical assumption about
the comparison mechanism, not an excuse to accept different ordered payloads.

The operating platform and orchestration remain in the trust account. Python,
shell, make and source preparation can influence which bytes are compiled even
when they do not generate target instruction bytes directly. A complete graph
names those roles rather than deleting them from the story because the C
compiler was small.

The series can end at a specific achieved record while leaving new work open.
Its paper route explains the recorded GCC 4.0.4 toolchain and its bounded
equality result. Fresh learning evidence, fresh execution and the direct-GCC
kernel continuation require their own events. Keeping those boundaries makes the
capstone reproducible as a claim, even before a reader undertakes the full
operational reproduction.

Sources: [inventory and content
comparison](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156),
[ordered member-name/hash
fallback](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156),
[archive timestamp
reason](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L547),
[paired acceptance and
report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L175-L204),
[recorded direct-GCC
endpoint](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L565),
[initial direct-profile
production](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L332),
[generator
chain](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/lexers.py#L56-L138),
[hosted producer
handoff](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L11-L39),
[later
generations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L8-L25),
[host-supported test
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L437-L455),
[optional runtime oracle
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L76-L91).

## Use the endpoint to choose the next observation

The final report's artifact domain is the installed tree. It begins by comparing
relative-path inventories, then hashes common file contents. Missing paths
remain differences. Ordinary files with unequal digests remain unequal; the
comparison does not broadly erase path strings, instruction choices or padding
to obtain agreement.

An unequal .a file can use the ordered member-name/hash fallback. This is a
defined content predicate motivated by the recorded timestamp difference. It
does not claim complete-container byte identity. A changed ordered member name
or payload digest fails the fallback even if the library still links a small
program successfully.

The name-based extraction and whitespace-split listing retain intended-library
assumptions. Duplicate or exotic member names would need additional validation
for a universal archive claim. State those assumptions with the comparison
rather than presenting the fallback as an unrestricted canonicalization of every
ar file.

Both required generation edges must have no differing or missing paths. The
report also retains selected stage-4 tool hashes. Those selected identities help
locate the endpoint, but do not replace full-tree inventory and content checks.
A three-hash summary is a useful index to evidence, not the predicate itself.

Now ask for a fresh reproduction. It needs actual source/generated inputs,
adaptations, executable producers, operating environment, completed steps,
installed artifacts and both comparison reports. The chapter's static reading
supplies the recipe and explains the acceptance condition; it does not supply a
newly executed build record.

Ask instead for evidence that another C program is compiled correctly. Select
that source and an appropriate behavioral/reference comparison. Generation
agreement alone cannot answer it, because a self-consistent translation defect
can persist. The new program's test graph needs its own scope and supporting
tools.

Ask for a reader's retained understanding. An independent reconstruction of the
producer graph and a changed archive comparison can supply learning evidence,
especially after a delay and without solutions. It is distinct from execution
evidence even when the answers are correct. These chapters provide the practice
structure while actual reader outcomes remain pending.

Finally, ask for direct-chain Linux boot. The next volume must identify the
exact compiler/toolchain, kernel source/configuration, boot artifacts, platform
and observable acceptance. Historical ladders to Linux use their own producers
and cannot silently become this route's evidence. The current capstone ends at
the recorded GCC 4.0.4 toolchain and bounded later-generation agreement, with
that kernel continuation explicitly open.

Sources: [inventory and content comparison](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156), [ordered member-name/hash fallback](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L137-L156), [archive timestamp reason](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L547), [paired acceptance and report](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L175-L204), [recorded direct-GCC endpoint](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L536-L565), [initial direct-profile production](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L332), [generator chain](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/lexers.py#L56-L138), [hosted producer handoff](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-c.py#L11-L39), [later generations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/stage-d.py#L8-L25), [host-supported test boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L437-L455), [optional runtime oracle boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L76-L91).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](24-equal-sort-keys-and-unequal-bytes.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/25-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G25-01 — State the domain

Which files are compared before examining content? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G25-02 — Compare an archive

Container hashes differ but ordered names/member hashes agree. What does the
script conclude? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G25-03 — Require stage 2

Stages 3/4 agree, but 2/3 differ in cc1. Does Stage D pass? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G25-04 — Name producer ancestry

Give the immediate producers of first GCC, libgcc and stage 3. Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G25-05 — Keep source transformations

Why retain YYBYACC and scanner adaptations in the final account? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G25-06 — Bound the archive reader

Does ar p by member name prove universal handling of duplicate archive names?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G25-07 — Close the capstone honestly

What remains after the recorded fixed point? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

## What this mechanism makes available

You can now interpret exact file/member predicates and remaining dependencies.
Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

The [series map](../README.md) returns to the earlier producer and runtime
lessons. The kernel continuation remains a separately planned volume.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
