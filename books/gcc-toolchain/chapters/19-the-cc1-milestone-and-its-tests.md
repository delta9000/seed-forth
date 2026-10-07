# The cc1 milestone and its tests

A compiler can link successfully and still miscompile its first input. What
evidence changes when cc1 writes assembly, and what changes again when that
assembly becomes a running test?

Follow one hypothetical torture-test record through its three failure stages.
The pinned runner’s host output tools are explicit test support, distinct from
G21’s production closure.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G18 supplies source generators and G17 supplies the source census. **cc1** is
GCC’s compiler proper; it writes assembly. GCC’s driver, assembler and linker
perform other steps. A **test oracle** checks behavior without becoming the
producer of the compiler being tested.

## Stop at the compiler proper’s real output

The census uses configured original Makefiles to build libiberty, cc1’s objects
and libcpp, then optionally links cc1. Compilation acceptance, successful
linking and emitted assembly are three facts. C90 implicit-int errors can
survive the first two, as the recorded bsearch pointer-return problem showed.

The original GCC sources and generated prerequisites keep their pins and actual
configuration facts. A successful object census is not a universal C acceptance
claim. Some source paths can remain unexercised even when all selected objects
exist.

The first behavioral question is whether cc1 accepts a named input and emits the
expected kind of assembly under supplied flags. That assembly alone is not a
loaded ELF executable. Its consumer chain must appear in the next record.

Sources: [census/link versus
behavior](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/census.py#L1-L36).

## Put the host-supported chain on the page

torture.py invokes the supplied Forth-built cc1, then host gcc assembles and
links its assembly with -no-pie -lm. It executes that test executable. Host
compiler tools supply test output objects here; they do not build the production
cc1 executable or enter the Forth build route.

The runner also creates private GCC headers from configured inputs, retains the
originating configure environment and uses native host system headers for this
test setup. It disables fixincludes and supplies the documented gsyslimits.h
fallback. That is an explicitly hosted test environment, not Stage C’s musl
sysroot.

A successful no-header source-built G21 chain answers a different question:
whether GCC uses the project’s as/ld. Neither result can be relabeled as the
other merely because both eventually run a small program.

Sources: [torture producer and header
setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L413-L447).

## Classify the first failed boundary

Supply a test whose cc1 invocation exits zero and emits assembly, whose host
link exits zero, but whose executable returns an unexpected result. The runner
classifies FAIL(run). If cc1 rejects before assembly, it is FAIL(cc1); if
assembly/link fails after cc1 succeeds, it is FAIL(link).

This staging preserves causality. A run failure is not evidence that linking
failed, and a cc1 failure is not a generated-program crash. Per-test assembly,
diagnostics, executable where produced and captured output let a later reviewer
inspect the first divergence.

Timeouts and resource ceilings bound the attempt. The runner uses a 4,000,000
KiB cc1 address-space limit, 120-second compiler timeout and 20-second execution
timeout; parallelism cannot exceed six. A timeout is a classified outcome under
that setup, not proof of infinite execution.

Sources: [resource and retention
policies](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L425-L431),
[per-test phase
results](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture.py#L250-L335).

## Do not turn unknown exception scripts into passes

The tiny .x evaluator validates against 25 exact active scripts in the pinned
manifest. It recognizes a bounded set of target/option flags, skips and
stage-specific expected failures; it does not interpret arbitrary Tcl.
Unknown/changed scripts and orphan exception files fail visibly.

An XFAIL applies only to its named compile or execute stage. An unexpected pass
is reported as failure with XPASS reason. A skipped test supplies no execution
outcome for its program. setup errors and unexpected failures cause nonzero
runner status.

Therefore a report needs attempted levels, active options, target, exception
policy and classifications, not just one passing percentage. Changing the
accepted exception set changes the meaning of the aggregate count.

Sources: [exact exception scripts and result
classes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L449-L469),
[pinned exception
inventory](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture-x.json#L1-L20).

## Read the surviving evidence at its actual scope

The pinned repository supplies the runner, exception inventory and retained
proof recipes. It does not turn this new chapter into an execution log. We do
not invent a total torture pass count or claim a new complete suite run.

The relevant achievement is bounded: a produced cc1 can be checked for emitted
assembly and generated-program behavior with named host-supported output tools.
G20 will build those downstream tools from sources; G21 joins them to remove the
host output-tool dependency from its production fixture.

Compiler correctness remains larger than any finite suite or byte fixed point.
Keep all selected source facts, generated-input lineage, failures and
independent oracle roles available. An educational exercise can correctly
classify a supplied report without having run the corresponding program.

Sources: [runner evidence
boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L413-L469).

## A completed link can preserve a wrong declaration

Supply a source use of `bsearch` without an appropriate visible declaration.
Under the admitted implicit-function behavior, the caller can treat the result
as an int. The real function returns a pointer. On LP64, those are different
widths and interpretations. A linker matching the spelling `bsearch` has no C
signature table here from which to repair the caller's assumption.

The call may therefore have a resolved machine destination while the caller
consumes its result incorrectly. This is a semantic interface failure, not
necessarily an unresolved-symbol failure. Repeating the successful link would
not repair it. Retaining the prepared source and lint finding directs attention
to the declaration boundary before testing downstream effects.

A host syntax tool that warns about the declaration supplies an oracle view. Its
warning deserves comparison with the selected compiler's behavior, but does not
make it a production compiler in the direct route. This is another reason to
distinguish the ancestry of production bytes from tools used to investigate
them.

Sources: [census/link versus
behavior](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/census.py#L1-L36).

## Follow the entire torture-test producer chain

The source-built cc1 produces assembly for an execution test. Host output tools
then assemble and link that assembly, with the documented command options and
libraries. The test executable contains bytes produced by that test chain. Its
result can support the source-built compiler's behavior on the named source,
while remaining dependent on host assembly and linking.

This is stronger than a syntax-only census for the tested case: a machine
program runs and returns an observed result. It is narrower than a complete
source-built output-toolchain result. G20 and G21 add the assembler, linker and
driver boundaries that this test arrangement deliberately borrows from the host.

Record compiler failure, assembler failure, linker failure and target execution
failure separately. A count of all failures without phase can conceal whether
cc1 ever produced accepted assembly. A timeout is also a recorded test outcome
rather than permission to invent a successful target status.

Sources: [torture producer and header
setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L413-L447).

## Preserve the named test set and its exceptions

The repository's torture wrapper selects named scripts and carries skip and
expected-failure handling. Read those policies before interpreting totals. An
expected failure that occurs is a different outcome from a passing supported
case. An unexpected pass calls the expectation into question; it is not
automatically another ordinary pass.

The chapter does not invent a broad numerical success rate from the fact that
twenty-five scripts are named. Each script can contain its own cases and
selection rules. The evidence domain is the retained test recipe and its
documented reports, not a guessed denominator.

For a later reproduction, preserve the selected scripts, prepared source,
compiler identity, output-tool identities and per-phase report. That makes a new
result comparable with the recorded one. This manuscript supplies no new torture
run or revised count. It closes the cc1 milestone while keeping the downstream
tools and hosted runtime as the next concrete obligations.

Sources: [resource and retention
policies](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L425-L431),
[per-test phase
results](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture.py#L250-L335),
[exact exception scripts and result
classes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L449-L469),
[pinned exception
inventory](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture-x.json#L1-L20).

## Keep expectation separate from observation

An execution test has an expected result before it runs and an actual result
afterward. The wrapper's classification relates the two. A supported expected
pass that returns its required value is an ordinary pass. A documented expected
compile failure that compiles successfully becomes an unexpected pass, which
this runner treats as a failure of expectation.

A skipped case supplies no runtime observation. Its reason may be justified by
current unsupported behavior, but that reason cannot be counted as a successful
target execution. A timeout records another outcome and should retain where
progress stopped. These categories help scope the cc1 milestone rather than
weaken it.

| Supplied event | Classification question | Fact retained |
|---|---|---|
| cc1 rejects input | Was compile failure expected? | Compiler status and diagnostics |
| Assembly accepted, link fails | Which output-tool phase failed? | Prior compile/assembly success |
| Executable returns wrong value | Was run behavior expected? | Earlier completed phases |
| Expected failure passes | Is expectation now contradicted? | XPASS reason and runner policy |
| Case skipped | Why was no target run attempted? | No executed behavior for that case |

Host gcc in the torture chain supplies explicit assembly/link support, including
the documented options and libm where requested. It does not rebuild the
installed production cc1 in that test. Keep the test chain and production chain
visible together so an accurate ancestry statement does not conceal support used
for behavioral evidence.

A passing case at O0 supports that source and level in its actual environment.
It does not establish every optimization setting. A collection of selected
wrapper scripts is not a universal GCC testsuite result. Retain the selection
and per-case classifications rather than inventing a broad pass percentage from
script count.

Private-header replay has a similar distinction: a test can consume prior
configuration successfully without rerunning configure. Preserve the earlier
producer of those answers. The new compilation result and inherited
configuration lineage are jointly relevant to understanding what cc1 actually
saw.

This chapter has read the inspected runner and pinned milestone reports. A new
torture session would need its own compiler identity, host tool identities,
selected cases, phase results and target observations. None has been generated
here. The next chapters close output-tool and hosted-runtime boundaries that
these host-supported tests leave open.

Sources: [torture producer and header
setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L413-L447),
[resource and retention
policies](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L425-L431),
[per-test phase
results](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture.py#L250-L335),
[exact exception scripts and result
classes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L449-L469),
[pinned exception
inventory](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture-x.json#L1-L20),
[runner evidence
boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L413-L469).

## Trace a result through the test chain without losing its source

Supply one torture source and a chosen optimization level. The runner asks the
source-built cc1 to emit assembly. If that phase rejects the source, there is no
target executable to run. If it succeeds, host output support assembles and
links the assembly into the named test executable. Only after those phases can
the runner observe a process result.

For a hypothetical case expecting return zero, supply successful compile,
assembly and link followed by nonzero execution. The correct phase
classification is run failure. The earlier phases remain successful records.
Replacing the whole trace with “compiler failed” would conceal where the actual
discrepancy appeared and which tools had already accepted their inputs.

Supply another case documented to fail compilation, then let compilation
succeed. The runner reports unexpected pass according to its explicit policy.
This is a mismatch between expectation and observation; it can motivate
reviewing the old expectation. It does not automatically prove that the
resulting target would behave correctly if executed.

Skip handling gives no new target behavior. Its selected reason explains why the
test was not attempted under this wrapper. Counting it alongside ordinary passes
would change the evidence domain. A timeout similarly remains its own result
with retained progress, not a passing observation that merely took too long to
watch.

The bsearch example explains why linking success is especially incomplete as a
semantic oracle. A missing declaration can make the caller consume an int result
where the function actually returns a pointer. LP64 storage gives the mismatch
practical importance. The linker can satisfy the spelling while lacking the
original C types needed to repair the caller.

A host syntax-only lint run can detect this interface concern before execution.
Its accepted language and diagnostics have their own assumptions. It remains a
supporting oracle with no production target objects. Host assembly/link support
in the torture runner has a different role: it does produce the test executable,
while still not producing installed production cc1.

The source-built compiler's test evidence is therefore meaningful but bounded. A
named case/level supports a behavior under that exact test chain. The selected
twenty-five scripts and exception policies do not authorize an invented
all-program pass count. Retain source preparation, compiler identity, host
tools, options and per-phase outcomes whenever comparing another run.

This chapter attributes the existing cc1 milestone and tests to the pinned
account. It has not compiled a new torture source, run an executable or updated
expected-failure classifications. The next milestone needs the source-built
output tools to replace the borrowed services in an actual joined production
chain.

Sources: [census/link versus behavior](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/census.py#L1-L36), [torture producer and header setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L413-L447), [resource and retention policies](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L425-L431), [per-test phase results](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture.py#L250-L335), [exact exception scripts and result classes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L449-L469), [pinned exception inventory](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/torture-x.json#L1-L20), [runner evidence boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L413-L469).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](18-source-generators-must-have-builders.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/19-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G19-01 — Identify cc1 output

What artifact does cc1 normally produce in this test chain? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G19-02 — Classify the failed stage

Use the supplied successful cc1/link but failed run record. Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G19-03 — Name host support

Does host gcc in torture.py produce the production cc1? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G19-04 — Read a skip

What does SKIP supply about runtime behavior? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G19-05 — Scope XFAIL

An expected compile failure instead passes. How is it reported? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G19-06 — Retain configuration facts

May private-header replay be credited as fresh configure? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G19-07 — Bound a test claim

A supplied test passes at -O0. Does it establish every optimization level and
program? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now reach cc1 assembly and bound host-supported torture evidence. Use
the state transitions above to justify that explanation, rather than treating a
source filename or a successful later milestone as a substitute for the
mechanism.

Continue to [G20: Building the downstream
binutils](20-building-the-downstream-binutils.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
