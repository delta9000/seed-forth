# G04: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/04-a-shared-scalar-argument-planner.md#try-the-mechanism).
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

### G4-01 changed — Assign registers

Use the model in G4-01: Place the seven supplied long arguments. Where is
argument seven before CALL?

Change the premise: Use eight long arguments. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G4-02 changed — Change coordinates

Use the model in G4-02: Locate argument seven at callee entry and after the RBP
prologue.

Change the premise: The entry RSP is 0x9008. Give both frame reference and
argument address. What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

### G4-03 changed — Derive alignment

Use the model in G4-03: Reconstruct the supplied 0x8008 one-stack-argument
model.

Change the premise: Start at 0x8010 instead. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G4-04 changed — Protect an outer argument

Use the model in G4-04: Why must the planner preserve a live first argument
during a nested second-argument call?

Change the premise: A switch register save is also live. May it be ignored? What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G4-05 changed — Stage an indirect target

Use the model in G4-05: Why does the target survive in R10 rather than depending
on AL?

Change the premise: The count remains zero. Can target preservation be omitted?
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G4-06 changed — Receive the result

Use the model in G4-06: Explain int storage, integer ABI return and internal
expression carrier.

Change the premise: The returned low 32 bits represent −1. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G4-07 changed — Identify the selected provider

Use the model in G4-07: Why is 121’s scalar call definition insufficient as the
full direct-profile account?

Change the premise: Only a file’s presence in a load list is known. What is
still needed? What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G4-01

1. Use the six INTEGER registers in order.
2. Number general-class positions from the beginning.
3. Assign the first six destinations before putting the seventh into overflow.

### Hints for G4-02

1. Count the return address and saved RBP separately.
2. Draw the stack before CALL and at entry.
3. CALL adds a return-address word; saving RBP adds another.

### Hints for G4-03

1. Align downward after reserving outgoing bytes plus slack.
2. Track the saved pointer, subtraction and aligned pointer separately.
3. Round down only after subtracting the demanded temporary extent.

### Hints for G4-04

1. Count every surviving owner, not just this call’s arguments.
2. List what the nested call is permitted to overwrite.
3. Protect earlier evaluated values before assigning the outer call registers.

### Hints for G4-05

1. Destination and vector count are separate values.
2. Locate the source of the indirect target at final call time.
3. Account for argument-register moves and the AL preparation before CALL.

### Hints for G4-06

1. The declared type controls normalization.
2. Name storage, ABI and expression representations separately.
3. An int’s four-byte object, RAX/EAX return and internal RDI carrier have different roles.

### Hints for G4-07

1. Follow the final binding, not just the first definition.
2. Follow the final hook installation in load order.
3. 131 replaces the evaluated-call provider while retaining shared 121 helpers.

## Worked solutions

### Solution G4-01 — Assign registers

The original question asks: Place the seven supplied long arguments. Where is
argument seven before CALL?

10–60 occupy RDI, RSI, RDX, RCX, R8, R9; 70 occupies outgoing stack offset zero.

**Check your explanation:** Use the six INTEGER registers in order. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** giving an integer-only seventh argument another general
register. Assign the first six destinations before putting the seventh into
overflow.

### Solution G4-02 — Change coordinates

The original question asks: Locate argument seven at callee entry and after the
RBP prologue.

It is at entry RSP+8 and later RBP+16. CALL and saved RBP explain the coordinate
changes.

**Check your explanation:** Count the return address and saved RBP separately. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** reading outgoing offset zero at entry RSP rather than
beyond the return address. CALL adds a return-address word; saving RBP adds
another.

### Solution G4-03 — Derive alignment

The original question asks: Reconstruct the supplied 0x8008 one-stack-argument
model.

Subtract 8+15=23 to 0x7FF1, align to 0x7FF0, CALL enters at 0x7FE8.

**Check your explanation:** Align downward after reserving outgoing bytes plus
slack. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** restoring a rounded pointer instead of the saved caller
state. Round down only after subtracting the demanded temporary extent.

### Solution G4-04 — Protect an outer argument

The original question asks: Why must the planner preserve a live first argument
during a nested second-argument call?

The nested outgoing area and volatile registers can overwrite temporary state.
The saved live span preserves outer ownership before alignment and restores it
afterward.

**Check your explanation:** Count every surviving owner, not just this call’s
arguments. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** assuming argument registers preserve values through a
nested call. Protect earlier evaluated values before assigning the outer call
registers.

### Solution G4-05 — Stage an indirect target

The original question asks: Why does the target survive in R10 rather than
depending on AL?

AL communicates vector-register count, while R10 holds the indirect destination.
Updating the count must not overwrite the target.

**Check your explanation:** Destination and vector count are separate values. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** preserving arguments while destroying the function
address. Account for argument-register moves and the AL preparation before CALL.

### Solution G4-06 — Receive the result

The original question asks: Explain int storage, integer ABI return and internal
expression carrier.

Storage is four bytes; the ABI returns through RAX/EAX; generated expression
code uses RDI with conversion to the declared signed int type.

**Check your explanation:** The declared type controls normalization. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** using the register width to infer the C object’s storage
width. An int’s four-byte object, RAX/EAX return and internal RDI carrier have
different roles.

### Solution G4-07 — Identify the selected provider

The original question asks: Why is 121’s scalar call definition insufficient as
the full direct-profile account?

131 later installs the evaluated-call provider and owns explicit
locations/snapshots, while 121 supplies shared helpers and fallbacks.

**Check your explanation:** Follow the final binding, not just the first
definition. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** describing a loaded fallback as the selected direct call
implementation. 131 replaces the evaluated-call provider while retaining shared
121 helpers.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G4-01 — Assign registers

Argument eight occupies the next eight-byte stack slot; the six-register
allocation is unchanged. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G4-02 — Change coordinates

After PUSH RBP, RBP is 0x9000; the argument is 0x9010, equal to entry RSP+8.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G4-03 — Derive alignment

Subtract 23 to 0x7FF9, align to 0x7FF0, and enter at 0x7FE8. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G4-04 — Protect an outer argument

No; switch depth is included alongside expression-stack depth. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G4-05 — Stage an indirect target

No. Argument evaluation and register loading still threaten the target
independently of the count. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G4-06 — Receive the result

Signed int conversion extends that sign for the wider internal carrier; storage
width remains four. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G4-07 — Identify the selected provider

The activation gates and final deferred bindings must be traced before claiming
selected behavior. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/04-a-shared-scalar-argument-planner.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
