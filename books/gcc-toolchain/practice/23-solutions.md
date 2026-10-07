# G23: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/23-rebuild-lineage-and-controlled-paths.md#try-the-mechanism).
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

### G23-01 changed — Draw the lineage

Use the model in G23-01: Name producers for stages 2,3,4.

Change the premise: Stage 3 is rebuilt with host gcc instead. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G23-02 changed — Read the criterion

Use the model in G23-02: Is equality of stages 3/4 alone enough for this recipe?

Change the premise: Stage C bytes differ from stage 2. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G23-03 changed — Control paths

Use the model in G23-03: Why not configure each generation under a different
prefix?

Change the premise: Use DESTDIR for later installation. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G23-04 changed — Keep patches visible

Use the model in G23-04: Why add YYBYACC to the poison exemption?

Change the premise: The old exemption occurs twice. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G23-05 changed — Bound language scope

Use the model in G23-05: Does C-only GCC equality compare all GCC languages?

Change the premise: A separate C++ build later succeeds. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G23-06 changed — Diagnose unequal paths

Use the model in G23-06: Two files differ only in embedded run-directory
strings. Does that prove a semantic compiler error?

Change the premise: Paths are controlled but equivalent address operands swap.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G23-07 changed — Report evidence

Use the model in G23-07: May source inspection of build() be called a newly
completed Stage D run?

Change the premise: A saved report says fixed_point true. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G23-01

1. Every stage box needs a predecessor executable.
2. Write the producer above each generation arrow.
3. Stage C makes 2, stage 2 makes 3, and stage 3 makes 4.

### Hints for G23-02

1. Read exactly which pairs are required.
2. List both required adjacent comparisons.
3. Agreement of 3/4 leaves the separate 2/3 condition unanswered.

### Hints for G23-03

1. Logical install path differs from staging root.
2. Distinguish configured prefix from installation staging.
3. DESTDIR stores separate trees while retaining a common configured prefix.

### Hints for G23-04

1. Adaptation has a checked precondition.
2. Read the generated-parser macro and poison exemption together.
3. YYBYACC is already recognized elsewhere but needs the documented exemption.

### Hints for G23-05

1. The configured source set defines scope.
2. Read configured languages and omitted source trees.
3. C-only equality has a C-only product domain.

### Hints for G23-06

1. Start with controlled inputs and first differences.
2. Compare the embedded path inputs before assigning cause.
3. Different directory strings demonstrate byte difference without proving semantic error.

### Hints for G23-07

1. A predicate implementation differs from an observed predicate result.
2. Identify inspection and execution as different events.
3. Reading build() explains a recipe without producing new generations.

## Worked solutions

### Solution G23-01 — Draw the lineage

The original question asks: Name producers for stages 2,3,4.

Stage C GCC builds 2; 2 builds 3; 3 builds 4. Same identified downstream
tools/sysroot remain inputs.

**Check your explanation:** Every stage box needs a predecessor executable. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** naming stages without identifying the executing compiler.
Stage C makes 2, stage 2 makes 3, and stage 3 makes 4.

### Solution G23-02 — Read the criterion

The original question asks: Is equality of stages 3/4 alone enough for this
recipe?

No. Stages 2/3 must agree too.

**Check your explanation:** Read exactly which pairs are required. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** accepting only the last pair. Agreement of 3/4 leaves the
separate 2/3 condition unanswered.

### Solution G23-03 — Control paths

The original question asks: Why not configure each generation under a different
prefix?

Embedded paths can change bytes independently of compiler semantics; the recipe
controls prefix/source/build coordinates.

**Check your explanation:** Logical install path differs from staging root. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** changing embedded prefix strings merely to separate
artifact directories. DESTDIR stores separate trees while retaining a common
configured prefix.

### Solution G23-04 — Keep patches visible

The original question asks: Why add YYBYACC to the poison exemption?

The generated parser is already recognized elsewhere but would otherwise be
rejected by real GCC’s poisoning policy.

**Check your explanation:** Adaptation has a checked precondition. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** hiding a checked parser adaptation behind unchanged
archive identity. YYBYACC is already recognized elsewhere but needs the
documented exemption.

### Solution G23-05 — Bound language scope

The original question asks: Does C-only GCC equality compare all GCC languages?

No. The source/configuration explicitly omit other language trees.

**Check your explanation:** The configured source set defines scope. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** crediting unavailable frontends to the fixed-point
result. C-only equality has a C-only product domain.

### Solution G23-06 — Diagnose unequal paths

The original question asks: Two files differ only in embedded run-directory
strings. Does that prove a semantic compiler error?

No. It proves byte inequality with different path inputs; control that input
before assigning cause.

**Check your explanation:** Start with controlled inputs and first differences.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** diagnosing a compiler defect before controlling path
inputs. Different directory strings demonstrate byte difference without proving
semantic error.

### Solution G23-07 — Report evidence

The original question asks: May source inspection of build() be called a newly
completed Stage D run?

No. It explains the recipe; recorded results remain attributed and new execution
remains absent.

**Check your explanation:** A predicate implementation differs from an observed
predicate result. A matching final answer without that reason leaves the
mechanism uncertain. If your answer differs, compare the supplied premises
first, then locate the first transition at which your model departs from the
chapter.

**Common wrong path:** calling source inspection a freshly completed Stage D
run. Reading build() explains a recipe without producing new generations.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G23-01 — Draw the lineage

That changes the lineage and cannot inherit the recorded Stage D claim. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G23-02 — Read the criterion

That alone is not failure of the specified later-generation predicate; Stage C
is not its compared generation. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G23-03 — Control paths

It stages separate installed trees while retaining the common configured prefix.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G23-04 — Keep patches visible

The script’s exact-once guard rejects the unexpected source state. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G23-05 — Bound language scope

It needs its own lineage and artifact predicate. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G23-06 — Diagnose unequal paths

Inspect the runtime tie-ordering cause developed in G24. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G23-07 — Report evidence

Its exact inputs, artifact set and comparison rules must still be named. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/23-rebuild-lineage-and-controlled-paths.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
