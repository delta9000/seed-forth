# G24: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/24-equal-sort-keys-and-unequal-bytes.md#try-the-mechanism).
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

### G24-01 changed — Keep equal identities

Use the model in G24-01: The supplied comparator returns zero for A/B. Which
output orders are legal?

Change the premise: Compare payload as a secondary key. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G24-02 changed — Connect order to bytes

Use the model in G24-02: Why can swapping RBP/RDX alter compiler bytes without
the reported address behavior changing?

Change the premise: A different mismatch changes the accessed displacement. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G24-03 changed — Locate the runtime change

Use the model in G24-03: Which runtime builds stage 2’s code and which runs the
next compiler?

Change the premise: Relink only Stage C cc1’s qsort as reported. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G24-04 changed — Reject false stability

Use the model in G24-04: Is this smoothsort generally stable for equal keys?

Change the premise: A test checks an already equal run only. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G24-05 changed — Preserve provenance

Use the model in G24-05: Does compiling musl qsort.c with Forth introduce a host
libc object?

Change the premise: A host qsort object is copied instead. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G24-06 changed — Retain permutation

Use the model in G24-06: Why check identities beyond sorted keys?

Change the premise: All keys are equal. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G24-07 changed — Bound the reported fix

Use the model in G24-07: What does the recorded seven-executable diagnosis
establish?

Change the premise: No new sorting test ran here. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G24-01

1. Comparator equality need not mean byte identity.
2. Label payload identities beyond their equal keys.
3. The comparator observes a key that the downstream printer may not fully describe.

### Hints for G24-02

1. Equivalence is local to the demonstrated case.
2. Inspect the concrete equivalent operand choice.
3. A local address equivalence does not cover arbitrary changed displacement.

### Hints for G24-03

1. Runtime belongs to the executing producer.
2. Locate the runtime used by each executing compiler.
3. Stage C uses seed runtime to build 2; stage 2 uses musl to build 3.

### Hints for G24-04

1. State the quantified input class.
2. Quantify the sorted-run behavior narrowly.
3. A property of already sorted runs is weaker than general equal-key stability.

### Hints for G24-05

1. Source origin and executable producer differ.
2. Read the source-built runtime object’s provenance.
3. The relink uses identified source compiled by Forth rather than a copied host object.

### Hints for G24-06

1. Ordering and membership are separate invariants.
2. Check ordering and permutation independently.
3. Equal-key freedom cannot excuse dropped or duplicated payloads.

### Hints for G24-07

1. A recorded intervention has a named scope.
2. Separate the supplied paper records from the pinned diagnosis.
3. No fresh sort or seven-executable comparison was run here.

## Worked solutions

### Solution G24-01 — Keep equal identities

The original question asks: The supplied comparator returns zero for A/B. Which
output orders are legal?

Both A,B and B,A satisfy key ordering; their payload identities remain
different.

**Check your explanation:** Comparator equality need not mean byte identity. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** equating equal comparison results with identical records.
The comparator observes a key that the downstream printer may not fully
describe.

### Solution G24-02 — Connect order to bytes

The original question asks: Why can swapping RBP/RDX alter compiler bytes
without the reported address behavior changing?

The consumer writes operand order, yielding different text/encoding for the
documented equivalent effective-address choice.

**Check your explanation:** Equivalence is local to the demonstrated case. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** calling every generated-byte mismatch harmless. A local
address equivalence does not cover arbitrary changed displacement.

### Solution G24-03 — Locate the runtime change

The original question asks: Which runtime builds stage 2’s code and which runs
the next compiler?

Stage C cc1 runs on the seed runtime to build stage 2; stage 2 runs on musl to
build stage 3.

**Check your explanation:** Runtime belongs to the executing producer. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** assuming identical GCC source forces identical runtime
sorting behavior. Stage C uses seed runtime to build 2; stage 2 uses musl to
build 3.

### Solution G24-04 — Reject false stability

The original question asks: Is this smoothsort generally stable for equal keys?

No. It leaves sorted runs in place but general equal elements need not retain
order.

**Check your explanation:** State the quantified input class. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** calling smoothsort stable for every input permutation. A
property of already sorted runs is weaker than general equal-key stability.

### Solution G24-05 — Preserve provenance

The original question asks: Does compiling musl qsort.c with Forth introduce a
host libc object?

No. It introduces identified source with its license/adaptation, compiled into a
new production object by Forth.

**Check your explanation:** Source origin and executable producer differ. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** describing the intervention as host-libc substitution.
The relink uses identified source compiled by Forth rather than a copied host
object.

### Solution G24-06 — Retain permutation

The original question asks: Why check identities beyond sorted keys?

A broken sort can duplicate/drop equal elements while still producing ordered
keys; complete identities reveal it.

**Check your explanation:** Ordering and membership are separate invariants. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** testing only nondecreasing keys. Equal-key freedom cannot
excuse dropped or duplicated payloads.

### Solution G24-07 — Bound the reported fix

The original question asks: What does the recorded seven-executable diagnosis
establish?

That particular mismatch and the reported relink’s effect on Stage D; it is not
a universal reproducibility or correctness theorem.

**Check your explanation:** A recorded intervention has a named scope. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** presenting the manuscript’s model as a reproduced fixed
point. No fresh sort or seven-executable comparison was run here.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G24-01 — Keep equal identities

That changes the comparator’s ordering contract and can determine a unique order
for these two records. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G24-02 — Connect order to bytes

Do not infer harmlessness; it requires its own semantic diagnosis. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G24-03 — Locate the runtime change

That changes the earlier producer’s runtime algorithm while retaining the
documented rest of its lineage. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G24-04 — Reject false stability

That tests the narrower property and cannot prove general stability. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G24-05 — Preserve provenance

That changes production ancestry. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G24-06 — Retain permutation

Permutation preservation remains meaningful even when every order is key-sorted.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G24-07 — Bound the reported fix

The chapter must retain attribution and paper-example labels. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/24-equal-sort-keys-and-unequal-bytes.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
