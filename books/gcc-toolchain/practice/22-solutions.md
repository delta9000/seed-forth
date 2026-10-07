# G22: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/22-hosted-closure-with-libgcc-and-musl.md#try-the-mechanism).
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

### G22-01 changed — Order the headers

Use the model in G22-01: Why install musl headers before GCC configure?

Change the premise: Only headers are installed. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G22-02 changed — Name immediate producers

Use the model in G22-02: Who builds cc1 and who builds libgcc in Stage C?

Change the premise: Who builds libc.a? What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G22-03 changed — Separate runtimes

Use the model in G22-03: Does a musl-linked target imply the Forth-built cc1
runs on musl?

Change the premise: Stage 2 GCC is built as a hosted product. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G22-04 changed — Classify adjustments

Use the model in G22-04: Is clearing STMP_FIXINC a GCC C-source patch?

Change the premise: A source file is changed instead. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G22-05 changed — Witness libgcc

Use the model in G22-05: Why require __divti3 in hello’s symbol output?

Change the premise: Output matches but the symbol is absent. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G22-06 changed — Report resume

Use the model in G22-06: A resumed run skips already successful headers/libgcc
steps. Were they rerun?

Change the premise: Hello runs anew. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G22-07 changed — Bound hosted closure

Use the model in G22-07: Does this recipe establish Linux kernel boot or every
hosted C program?

Change the premise: The program formats long double successfully. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G22-01

1. Declarations precede configuration consumers, but not all runtime outputs.
2. Place target headers before configuration consumers.
3. A later installed library cannot repair an earlier probe’s header environment.

### Hints for G22-02

1. Name each artifact’s immediate compiler.
2. Name the executable compiling each runtime.
3. Forth builds first GCC, then that GCC builds libgcc and musl.

### Hints for G22-03

1. Builder and target runtime roles differ.
2. Label the compiler runtime and target runtime separately.
3. First cc1 runs on seed runtime while its generated program links against musl.

### Hints for G22-04

1. Keep source and build-tree inputs separate.
2. Locate STMP_FIXINC in the configured Makefile.
3. Clearing a build rule is a retained build-tree adjustment rather than a C implementation patch.

### Hints for G22-05

1. Acceptance has multiple named conjuncts.
2. Find the symbol that witnesses the wide-division edge.
3. The fixture’s __divti3 requirement is more specific than a generic printed message.

### Hints for G22-06

1. A resumed report contains mixed execution times.
2. Read successful prior steps beside resume policy.
3. Skipped completed steps reuse old evidence and were not rerun.

### Hints for G22-07

1. Attribute capability to the executable that provides it.
2. State the hosted fixture’s actual domain.
3. A static program and target libraries do not observe kernel boot or all hosted programs.

## Worked solutions

### Solution G22-01 — Order the headers

The original question asks: Why install musl headers before GCC configure?

Configure/header generation should consume the intended target declarations
instead of selecting host headers.

**Check your explanation:** Declarations precede configuration consumers, but
not all runtime outputs. A matching final answer without that reason leaves the
mechanism uncertain. If your answer differs, compare the supplied premises
first, then locate the first transition at which your model departs from the
chapter.

**Common wrong path:** treating header installation order as merely cosmetic. A
later installed library cannot repair an earlier probe’s header environment.

### Solution G22-02 — Name immediate producers

The original question asks: Who builds cc1 and who builds libgcc in Stage C?

Forth builds cc1; the resulting xgcc/cc1 builds target libgcc.

**Check your explanation:** Name each artifact’s immediate compiler. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** calling every Stage C object Forth-compiled. Forth builds
first GCC, then that GCC builds libgcc and musl.

### Solution G22-03 — Separate runtimes

The original question asks: Does a musl-linked target imply the Forth-built cc1
runs on musl?

No. The first compiler executable uses its source-built seed runtime; its
generated program uses the selected musl target library.

**Check your explanation:** Builder and target runtime roles differ. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** assuming a musl target changes the already built
compiler’s runtime. First cc1 runs on seed runtime while its generated program
links against musl.

### Solution G22-04 — Classify adjustments

The original question asks: Is clearing STMP_FIXINC a GCC C-source patch?

No. It is an explicit configured-Makefile adjustment, retained alongside
links/header installation changes.

**Check your explanation:** Keep source and build-tree inputs separate. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** misclassifying every recipe adaptation as an upstream
C-source change. Clearing a build rule is a retained build-tree adjustment
rather than a C implementation patch.

### Solution G22-05 — Witness libgcc

The original question asks: Why require __divti3 in hello’s symbol output?

It witnesses the intended 128-bit division helper edge, beyond generic
successful output.

**Check your explanation:** Acceptance has multiple named conjuncts. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** claiming libgcc was exercised without checking the
intended helper. The fixture’s __divti3 requirement is more specific than a
generic printed message.

### Solution G22-06 — Report resume

The original question asks: A resumed run skips already successful
headers/libgcc steps. Were they rerun?

No. Their earlier successful records are reused; preserve the original
input/output identities.

**Check your explanation:** A resumed report contains mixed execution times. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** describing every resumed step as freshly executed.
Skipped completed steps reuse old evidence and were not rerun.

### Solution G22-07 — Bound hosted closure

The original question asks: Does this recipe establish Linux kernel boot or
every hosted C program?

No. It closes the named static hosted fixture and target library chain, with
later kernel and general-correctness claims separate.

**Check your explanation:** Attribute capability to the executable that provides
it. A matching final answer without that reason leaves the mechanism uncertain.
If your answer differs, compare the supplied premises first, then locate the
first transition at which your model departs from the chapter.

**Common wrong path:** using a successful hello as a direct-GCC Linux result. A
static program and target libraries do not observe kernel boot or all hosted
programs.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G22-01 — Order the headers

Target library and startup closure remains incomplete. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G22-02 — Name immediate producers

The installed Stage C GCC via musl’s original build. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G22-03 — Separate runtimes

Its musl runtime is part of the next generation’s execution environment. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G22-04 — Classify adjustments

That would need its own adaptation record and cannot inherit Stage C’s
no-source-patch wording. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G22-05 — Witness libgcc

The recipe’s acceptance predicate is not fully met. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G22-06 — Report resume

That new behavior has its own command/status without relabeling skipped steps.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G22-07 — Bound hosted closure

That is GCC/musl product behavior, not an expansion of the Forth formatter’s
supported surface. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/22-hosted-closure-with-libgcc-and-musl.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
