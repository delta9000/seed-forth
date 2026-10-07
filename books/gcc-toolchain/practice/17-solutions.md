# G17: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/17-frozen-driver-configure-and-source-census.md#try-the-mechanism).
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

### G17-01 changed — Name two hashes

Use the model in G17-01: Contrast source identity and artifact digest.

Change the premise: One cached object hash fails. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G17-02 changed — Bound the snapshot

Use the model in G17-02: Are arbitrary user headers copied by Toolchain’s
compiler capture?

Change the premise: A runtime header changes. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G17-03 changed — Report a cache hit

Use the model in G17-03: May a verified hit be described as a runtime rebuilt
during this invocation?

Change the premise: A cold miss occurs. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G17-04 changed — Select the census

Use the model in G17-04: Why ask the Makefile for cc1’s objects?

Change the premise: make -k records three failures and many successes. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G17-05 changed — Preserve configuration lineage

Use the model in G17-05: A replay copies old config headers and uses a new
compiler. Who produced the answers?

Change the premise: All copied header hashes match. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G17-06 changed — Locate the pointer loss

Use the model in G17-06: Why can a found bsearch symbol coexist with an invalid
pointer result?

Change the premise: A proper pointer-return declaration is supplied and the
caller rebuilt. What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

### G17-07 changed — Classify an oracle

Use the model in G17-07: Does host syntax-only lint enter production ancestry?

Change the premise: A host-built generated C file is substituted into
production. What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G17-01

1. Inspect both manifest sides.
2. Name the input key and actual cached output separately.
3. A source identity cannot certify an artifact whose bytes changed.

### Hints for G17-02

1. Separate compiler/runtime and external user inputs.
2. Distinguish captured compiler layers from arbitrary user includes.
3. User headers are read at requested paths and need their own retained identities.

### Hints for G17-03

1. Reuse preserves ancestry rather than creating a new producer.
2. Name the reuse event rather than a rebuild event.
3. A verified hit retains an earlier producer’s artifact without running that production again.

### Hints for G17-04

1. Selection and acceptance are different predicates.
2. Let configured Make select the required work.
3. Generated prerequisites and unused source files make suffix enumeration a different set.

### Hints for G17-05

1. An answer keeps its producer when copied.
2. Name the compiler that originally answered the probes.
3. The replay compiler consumes inherited configuration unless it reruns the questions.

### Hints for G17-06

1. Check the declaration used before emission.
2. Compare the declaration’s result width with the real interface.
3. An implicit int result can misrepresent a returned pointer in LP64.

### Hints for G17-07

1. Track bytes that feed later production consumers.
2. Name the oracle’s artifact and whether production consumes it.
3. Host syntax lint diagnoses source but does not make route object bytes.

## Worked solutions

### Solution G17-01 — Name two hashes

The original question asks: Contrast source identity and artifact digest.

Source identity names captured inputs; artifact digest names produced bytes.
Equal source keys alone do not verify a corrupted cached artifact.

**Check your explanation:** Inspect both manifest sides. A matching final answer
without that reason leaves the mechanism uncertain. If your answer differs,
compare the supplied premises first, then locate the first transition at which
your model departs from the chapter.

**Common wrong path:** using equal source keys to excuse a corrupted cached
file. A source identity cannot certify an artifact whose bytes changed.

### Solution G17-02 — Bound the snapshot

The original question asks: Are arbitrary user headers copied by Toolchain’s
compiler capture?

No. They are read by Forth at requested paths; a reproduction must retain their
actual identities separately.

**Check your explanation:** Separate compiler/runtime and external user inputs.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** assuming the compiler snapshot copied every later user
header. User headers are read at requested paths and need their own retained
identities.

### Solution G17-03 — Report a cache hit

The original question asks: May a verified hit be described as a runtime rebuilt
during this invocation?

No. It is verified reuse with the earlier producer identity.

**Check your explanation:** Reuse preserves ancestry rather than creating a new
producer. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** crediting cache reuse as newly executed runtime
compilation. A verified hit retains an earlier producer’s artifact without
running that production again.

### Solution G17-04 — Select the census

The original question asks: Why ask the Makefile for cc1’s objects?

It owns the configured selection and generated prerequisites. Directory
enumeration would include irrelevant or omit generated units.

**Check your explanation:** Selection and acceptance are different predicates. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** counting every C filename as a cc1 translation unit.
Generated prerequisites and unused source files make suffix enumeration a
different set.

### Solution G17-05 — Preserve configuration lineage

The original question asks: A replay copies old config headers and uses a new
compiler. Who produced the answers?

The original configure compiler; the new compiler only produces replayed
compilations unless probes are rerun.

**Check your explanation:** An answer keeps its producer when copied. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** giving a new compiler credit for old configuration
answers. The replay compiler consumes inherited configuration unless it reruns
the questions.

### Solution G17-06 — Locate the pointer loss

The original question asks: Why can a found bsearch symbol coexist with an
invalid pointer result?

An undeclared C90 call was compiled as returning int; name resolution cannot
change that caller interface.

**Check your explanation:** Check the declaration used before emission. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** treating resolved bsearch as a checked pointer interface.
An implicit int result can misrepresent a returned pointer in LP64.

### Solution G17-07 — Classify an oracle

The original question asks: Does host syntax-only lint enter production
ancestry?

No. It is a declaration-check oracle, with no target objects supplied.

**Check your explanation:** Track bytes that feed later production consumers. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** making a helpful diagnostic tool an undocumented
production ancestor. Host syntax lint diagnoses source but does not make route
object bytes.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G17-01 — Name two hashes

The cache is not trusted and private source rebuilding is required. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G17-02 — Bound the snapshot

It belongs to captured runtime inputs and changes the source identity. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G17-03 — Report a cache hit

The current private build supplies new runtime objects and their manifest.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G17-04 — Select the census

Retain all individual outcomes; continuation does not convert failed units to
accepted ones. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G17-05 — Preserve configuration lineage

That verifies copied identity, not new probe execution. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G17-06 — Locate the pointer loss

That repairs the relevant type boundary; actual behavior still requires testing.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G17-07 — Classify an oracle

That would change the producer graph and cannot retain the same Forth-only
generation claim. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/17-frozen-driver-configure-and-source-census.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
