# Frozen driver, configure, and source census

A runtime cache can save a compilation, but it cannot erase who originally
produced its objects. What must a later invocation verify before reusing those
bytes?

Follow one snapshot and one cached member, then widen the record to configure
and cc1’s source census. We have not taken a new production snapshot or run GCC
configure for this chapter.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G05/G07/G08/G09/G11/G13/G15/G16 supply the production components this driver
selects. For the first story, retrieve just producer/artifact, content hash and
configure-probe distinctions. A **snapshot** is retained input bytes; a **cache
key** identifies a particular captured input set, while an artifact hash
identifies output bytes.

## A native frozen driver

seed-cc and seed-ar now replace Python orchestration for admitted commands;
the seed bootstraps both from C. Their source capture/cache contract keeps the
same production boundary, with native driver/header identities replacing the
Python adapter identity and a separate cache. The repository reports bootstrap,
Python-built and native self-rebuilt bytes agreeing, plus isolated command/tree
equivalence; these are attributed records, not new book runs. Historical GCC
configure/census scripts below still use their recorded Python route.
See [bootstrap, identities and evidence](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/SEED-CC.md#L20-L146).

## Capture the producer before running it

Toolchain gathers annotated seed, existing seed executable, library, numbered
compiler files, driver and runtime C/headers. It rereads the names and bytes to
detect changes during capture. It checks the executable against decoded
annotated seed bytes, then privately copies it and the runtime inputs.

The identity is a digest of the ordered name-to-source-hash mapping. It does not
regenerate the seed. Initial translator provenance remains part of the entrance
contract. The private Forth stream excludes the executing legacy 120 driver and
invokes an explicit object-mode driver instead.

User headers remain read at requested paths by Forth rather than all being
captured into this same compiler snapshot. Avoid changing them during a future
invocation and retain them in any reproduction record. Calling the compiler
snapshot frozen does not imply every external user source dependency has been
frozen.

Sources: [capture and compiler
invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L254).

## Verify reuse before assigning its ancestry

Runtime cache validation requires the exact source hash mapping, exact expected
artifact-name set and each cached object digest. A stale or damaged entry
triggers private rebuilding. On a hit, bytes are checked again while being
copied privately, catching changes between validation and consumption.

A hit means this invocation reused checked objects from the named producer
identity. It does not mean those objects were rebuilt now. A miss builds runtime
C and the seven support objects, writes a manifest and uses private staging for
atomic directory publication. Concurrent invocations can accept a verified
winner without sharing mutable in-progress output.

Runtime source inventory excludes math.c from the default archive; the support
names include syscall, errno, start, frame, sigreturn, setjmp and longjmp.
start.o is eager, while the other runtime objects form libseed.a. User
defines/include options do not mutate the runtime compile’s private header
policy.

Sources: [runtime cache and
producers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L256-L332),
[archive, cache and publication
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L105).

## Freeze the configuration question too

configure.py verifies the archive against the source pins and compares the
source tree’s files and symlinks with that archive, rejecting unexpected extras
apart from Git metadata. It captures the compiler before any probe, supplies
explicit CC/CPP and empty flags, removes site/cache shortcuts and guards host
target tools.

Retained configure.log, config.log, invocation environment, input manifests and
per-probe traces identify how answers were obtained. A successful configure exit
remains provisional. G08 explained why a generated size/type macro or feature
answer must be checked against its actual question and consumer.

Replay can reuse configured inputs while compiling with a new snapshot. That new
snapshot is the compilation producer, while the old configuration compiler
remains the producer of the inherited probe answers. A single current-source
hash cannot collapse both histories.

Sources: [configure identity and retained
probes](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L149-L172),
[configuration replay
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L421-L435).

## Let the Makefile choose the work

The census asks the configured original GCC Makefile for C_OBJS, main.o and
OBJS, sorting its resulting object names. It does not guess cc1’s source set
from every C file in an extracted directory. The Makefile also builds needed
generator programs and generated headers before compiling consumers.

Explicit overrides choose supported empty flags, Forth-built oyacc/flex and
actual libiberty/libcpp archive paths. make -k continues after failures so the
census retains each attempted unit, rather than stopping at the first missing
feature and treating the unseen remainder as accepted.

Compiler traces map outputs to actual invocations. Each object record retains
built/not-built, size/hash or diagnostic. --link adds archive and cc1 link work.
Compiling all selected objects and linking cc1 are separate outcomes; neither
alone establishes cc1’s generated programs work.

Sources: [Makefile-selected object list and census
scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L1-L95).

## Inspect declarations even after names resolve

The optional host GCC syntax lint checks the same target headers for implicit
function declarations. It supplies no production object bytes. The source
records why this matters: undeclared bsearch was assumed to return int under
C90, truncating a pointer despite successful name resolution and causing an
early cc1 failure on VLA inputs.

A missing lint oracle is not secretly a passed lint run. Keep its availability
and result distinct from Forth production compilation. A repaired header changes
the caller’s generated interface; replacing a link provider alone cannot recover
a pointer already truncated by its caller.

G18 will follow the actual generated-input producer graph. G19 will bound cc1
behavior tests. The source census is a reproducible account of attempted work,
not a declaration of universal language support or an observed new build in this
book.

Sources: [implicit declaration failure and lint
role](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L25-L36),
[optional lint
invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L108-L152).

## Freeze the producer before reusing its product

The direct driver gathers selected Forth layers and supporting inputs into a
toolchain snapshot. This snapshot identifies the producer that will compile a
user source. Cache reuse is meaningful only when the key and recorded artifacts
belong to that producer. A familiar output filename cannot replace that identity
check.

Supply two invocations with identical user source but different selected
provider bytes. Their toolchain identities differ. Reusing an old artifact
merely because the user source is unchanged would ignore the changed compiler.
Conversely, a matching frozen producer does not freeze every user include file
forever. Keep producer inputs and invocation-specific source inputs as separate
sets.

The cache also needs its expected artifact set. A key hit with a missing or
changed cached file is not the same event as a valid hit. The driver's
verification and recheck make that distinction explicit. An eventual cold/warm
comparison should record both the key and the actual retained outputs, rather
than reporting only elapsed time.

These contracts let us name what a later census compiled. “Built by Forth”
becomes a claim about identified executing bytes and selected layers, not a
property inferred from the directory containing an object.

Sources: [capture and compiler
invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L254),
[runtime cache and
producers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L256-L332),
[archive, cache and publication
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L105).

## Separate observing configure from replaying its decisions

A configure run asks questions in an environment and writes decisions that later
Makefiles consume. The repository's direct route records and reuses a named
generated view. The view is an input artifact with a producer and context. It is
not a timeless summary of everything this compiler supports.

When reading a replay, ask which decisions came from an earlier observation and
which compilation work occurs now. A current successful object compile does not
independently rerun the earlier feature probe. A stored configure result does
not prove that the current compiler invocation admitted every flag used by the
original probe.

This separation matters for target headers and runtime closure. A question can
compile without linking, link without running, or run with an explicitly
supplied runtime. G08's phase distinctions survive into configure reporting.
Preserve the test source, invocation and acceptance event when a result is
important to the argument.

Sources: [configure identity and retained
probes](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L149-L172),
[configuration replay
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L421-L435).

## Let Make choose the translation units

The source census follows the original build system's selected compilation work.
Generated source, prepared parser/scanner inputs and ordinary source can all
appear in that set. Enumerating files with a suffix is a different question: it
may include unused files and miss how generated inputs reached the build.

For each selected unit, retain its source identity and build arguments before
classifying success or failure. An object that links can still contain a wrong
implicit declaration, as G19 will show. Host syntax lint provides another view
of that prepared source; it remains an oracle, with its own accepted language
and assumptions.

The reported `bsearch` warning illustrates why warnings about undeclared
functions deserve interpretation. An implicit integer result cannot safely stand
in for a pointer-width result on this target. The census and lint reports expose
a candidate semantic boundary, not a request to trust whichever tool printed
“success.” This chapter has inspected the capture and reporting mechanisms; no
new cold-cache, configure or census run was made.

Sources: [Makefile-selected object list and census
scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L1-L95),
[implicit declaration failure and lint
role](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L25-L36),
[optional lint
invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L108-L152).

## Read a report without confusing its counters

A source census reports work selected by a build system. It can group
diagnostics, retain successful object production and record failure invocations.
Each view answers a different question. A total number of objects does not
identify which generated source was consumed, and a normalized warning group
does not identify every invocation that produced it.

Supply two failed units with the same diagnostic after line-number
normalization. A group count of two is useful for seeing a shared problem. The
original trace is still needed to find their sources, arguments and
configuration contexts. The grouping operation should add a view rather than
replace those records.

Now supply an artifact with a matching source key but changed cached bytes. The
source identity remains useful for provenance, while artifact verification
rejects reuse. A cache report must record which relation passed or failed
instead of calling every key hit successful compilation.

| Reported fact | Named domain | What remains separate |
|---|---|---|
| Compiler source identity | Captured producer inputs | Arbitrary user-header identity |
| Cache key match | Candidate reuse | Actual cached-file verification |
| Configure final status | Configuration recipe | Probe-by-probe lineage |
| Make-selected unit list | Configured compilation work | Every source file in the tree |
| Grouped diagnostics | Normalized summary | Concrete invocation evidence |
| Host lint warning | Oracle interpretation | Production object bytes |

A configuration replay can use a newer compiler to rebuild selected units while
inheriting older configuration headers. Name the original answer producer in
that report. If the new compiler did not rerun the probes, it did not produce
new feature answers. This is a lineage issue even when the resulting units
compile successfully.

The implicit pointer-return problem also shows why phase outcomes need
interpretation. A compiler can accept a source, the linker can find its function
and the program can still consume an incorrectly assumed result type. The lint
oracle helps expose this interface. It does not produce the production compiler
or objects.

A future cold/warm experiment should retain invocation-specific headers, key,
expected cached artifacts, actual digests and the reuse/rebuild events. Those
details would permit a new result to disagree with the inspected mechanism. The
book has recorded no new cache timing, census or replay outcome.

Sources: [capture and compiler
invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L254),
[runtime cache and
producers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L256-L332),
[archive, cache and publication
policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L105),
[configure identity and retained
probes](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L149-L172),
[configuration replay
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L421-L435),
[Makefile-selected object list and census
scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L1-L95),
[implicit declaration failure and lint
role](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L25-L36),
[optional lint
invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L108-L152).

## A differential failure can repair the evidence model

The pinned generator account retains a historical object built while computed
includes were skipped. That object is explicitly quarantined rather than reused
as accepted target input. Its existence is useful evidence of the earlier
failure boundary, not a product to carry into later successful closure.

Computed include handling mattered because GCC's target definitions supplied
extra modes, formats and long-double adjustments. Merely counting output markers
could miss some of those target facts. The production check retained
preprocessing and original definition inputs so a later comparison could ask
whether the generator consumed the complete target description.

The account also distinguishes an early naive inventory that included both
conditional location branches from a compiler defect. Correcting the inventory
repaired the checker question. A differential test can reveal a bad oracle or
bad expected set as well as a bad producer. Preserve the original failure and
the reason for reclassification instead of erasing it after a pass.

Configuration lineage enters this diagnosis too. The exact auto-host facts
choose branches. A new compiler snapshot can reuse those configured headers
while remaining distinct from the earlier compiler that answered the probes. If
the final proof reruns configure on the complete current source, that is a new
named evidence event, not something a replay implied automatically.

The census uses original Make-selected compilation work and retains source
manifests. Complete input hashing identifies what could have been consumed;
actual invocation records identify the work that occurred. A superset header
manifest is useful for provenance without claiming that every file in it
affected every translation unit.

The runtime cache provides similar discipline at a smaller scale. A candidate
identity hit requires exact expected artifacts and digests. Rechecking while
copying avoids accepting bytes that changed between initial validation and
consumption. A rebuild produces new artifacts under private staging; a
concurrent verified winner supplies another reuse path. Each event should retain
its actual producer and time.

These mechanisms make later reports interpretable. They prevent “same source”
from excusing corrupt artifacts, “generator ran” from excusing incomplete target
definitions, and “configure exited zero” from erasing individual failed
questions. They also let an investigator repair an oracle without calling every
disagreement a compiler failure.

This chapter has inspected the pinned records and capture recipes. It has not
created a new snapshot, repaired source, rerun a generator or observed a cache
race. The learning task is to trace which input, producer, oracle or expectation
changed before deciding what a reported difference means.

Sources: [capture and compiler invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L164-L254), [runtime cache and producers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/gcc-direct-cc.py#L256-L332), [archive, cache and publication policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L105), [configure identity and retained probes](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L149-L172), [configuration replay boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L421-L435), [Makefile-selected object list and census scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L1-L95), [implicit declaration failure and lint role](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L25-L36), [optional lint invocation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/census.py#L108-L152).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](16-indexed-archives-and-lazy-extraction.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/17-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G17-01 — Name two hashes

Contrast source identity and artifact digest. Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G17-02 — Bound the snapshot

Are arbitrary user headers copied by Toolchain’s compiler capture? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G17-03 — Report a cache hit

May a verified hit be described as a runtime rebuilt during this invocation?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G17-04 — Select the census

Why ask the Makefile for cc1’s objects? Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G17-05 — Preserve configuration lineage

A replay copies old config headers and uses a new compiler. Who produced the
answers? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

### G17-06 — Locate the pointer loss

Why can a found bsearch symbol coexist with an invalid pointer result? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G17-07 — Classify an oracle

Does host syntax-only lint enter production ancestry? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

## What this mechanism makes available

You can now pin one source/configure/producer record before the generator story.
Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G18: Source generators must have
builders](18-source-generators-must-have-builders.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
