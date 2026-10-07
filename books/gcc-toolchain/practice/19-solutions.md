# G19: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/19-the-cc1-milestone-and-its-tests.md#try-the-mechanism).
Write a prediction and a reason before checking. A correct answer should
identify the relevant owner, phase, width or evidence boundary.

Choose the support you need:

- [Changed prompts](#changed-prompts) contain no answers
- [Graduated hints](#graduated-hints) help with the original problems
- [Worked solutions](#worked-solutions) explain the original answers
- [Changed-task checks](#changed-task-checks) stay separate at the end

Record whether you used a hint or reopened the chapter. These are
supplied-contract paper tasks, with no build environment required. A supported
attempt and a later independent reattempt provide different evidence; neither is
automatically a measure of lasting learning.

## Changed prompts

### G19-01 changed — Identify cc1 output

Use the model in G19-01: What artifact does cc1 normally produce in this test
chain?

Change the premise: Only the cc1 object census is complete. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G19-02 changed — Classify the failed stage

Use the model in G19-02: Use the supplied successful cc1/link but failed run
record.

Change the premise: The host link fails instead. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G19-03 changed — Name host support

Use the model in G19-03: Does host gcc in torture.py produce the production cc1?

Change the premise: The test executable uses host libm. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G19-04 changed — Read a skip

Use the model in G19-04: What does SKIP supply about runtime behavior?

Change the premise: An unknown .x script appears. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G19-05 changed — Scope XFAIL

Use the model in G19-05: An expected compile failure instead passes. How is it
reported?

Change the premise: The test fails at a different stage. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G19-06 changed — Retain configuration facts

Use the model in G19-06: May private-header replay be credited as fresh
configure?

Change the premise: Configured hashes are copied exactly. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G19-07 changed — Bound a test claim

Use the model in G19-07: A supplied test passes at -O0. Does it establish every
optimization level and program?

Change the premise: A stage fixed point is also recorded. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G19-01

1. Name the output of each executable.
2. Find the artifact cc1 supplies before output tools run.
3. Assembly is an input to later assembly/linking, not an executable by itself.

### Hints for G19-02

1. Choose the first failed consumer boundary.
2. Retain each prior phase result.
3. A successful compile/link followed by unexpected execution is classified at run.

### Hints for G19-03

1. Separate tested producer from support for its outputs.
2. Locate host gcc on the test-support branch.
3. It assembles/links test assembly rather than producing installed cc1.

### Hints for G19-04

1. Exception interpretation is itself a checked input.
2. Read the skip reason before interpreting the case.
3. No execution happened for a skipped case.

### Hints for G19-05

1. Expected failure has a named boundary.
2. Compare expected and actual phases.
3. A compile-expected-failure that passes produces XPASS and is a runner failure.

### Hints for G19-06

1. A replay is a new compilation over old answers.
2. Find the original private-header configuration record.
3. Replayed answers keep their earlier producer identity.

### Hints for G19-07

1. State inputs, flags and checked behavior.
2. Keep named source and optimization level in the claim.
3. A pass at O0 has its actual test domain, not every program and option.

## Worked solutions

### Solution G19-01 — Identify cc1 output

The original question asks: What artifact does cc1 normally produce in this test
chain?

Assembly; assembler/linker work follows before an executable exists.

**Check your explanation:** Name the output of each executable. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** calling an assembly file a completed target program.
Assembly is an input to later assembly/linking, not an executable by itself.

### Solution G19-02 — Classify the failed stage

The original question asks: Use the supplied successful cc1/link but failed run
record.

FAIL(run), retaining earlier successful stages and unexpected behavior.

**Check your explanation:** Choose the first failed consumer boundary. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** erasing earlier successes when assigning the run failure.
A successful compile/link followed by unexpected execution is classified at run.

### Solution G19-03 — Name host support

The original question asks: Does host gcc in torture.py produce the production
cc1?

No. It assembles/links test assembly as explicit test support.

**Check your explanation:** Separate tested producer from support for its
outputs. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** confusing a test executable’s producer with the
production compiler’s producer. It assembles/links test assembly rather than
producing installed cc1.

### Solution G19-04 — Read a skip

The original question asks: What does SKIP supply about runtime behavior?

No executed behavior for that case; retain its reason and policy.

**Check your explanation:** Exception interpretation is itself a checked input.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** counting a skip as observed passing behavior. No
execution happened for a skipped case.

### Solution G19-05 — Scope XFAIL

The original question asks: An expected compile failure instead passes. How is
it reported?

As an unexpected pass with XPASS reason, treated as failure by this runner.

**Check your explanation:** Expected failure has a named boundary. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** folding unexpected passes into ordinary supported-case
success. A compile-expected-failure that passes produces XPASS and is a runner
failure.

### Solution G19-06 — Retain configuration facts

The original question asks: May private-header replay be credited as fresh
configure?

No. Its original configuration record identifies the producer of inherited
answers.

**Check your explanation:** A replay is a new compilation over old answers. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** calling private-header replay fresh configure evidence.
Replayed answers keep their earlier producer identity.

### Solution G19-07 — Bound a test claim

The original question asks: A supplied test passes at -O0. Does it establish
every optimization level and program?

No. It establishes the named case/level under the recorded support chain.

**Check your explanation:** State inputs, flags and checked behavior. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** generalizing one admitted case to universal compiler
correctness. A pass at O0 has its actual test domain, not every program and
option.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G19-01 — Identify cc1 output

That establishes source acceptance, not emitted test assembly or behavior.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G19-02 — Classify the failed stage

FAIL(link); no successful target execution follows. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G19-03 — Name host support

That is another test environment dependency, not production runtime closure.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G19-04 — Read a skip

The bounded evaluator fails rather than silently skipping or treating it as
passed. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G19-05 — Scope XFAIL

The original stage-specific expectation does not automatically excuse it. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G19-06 — Retain configuration facts

Copy identity is verified; fresh probes are still absent. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G19-07 — Bound a test claim

That adds a distinct artifact equality predicate, not universal semantic
correctness. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/19-the-cc1-milestone-and-its-tests.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
