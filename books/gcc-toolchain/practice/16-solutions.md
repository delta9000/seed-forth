# G16: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/16-indexed-archives-and-lazy-extraction.md#try-the-mechanism).
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

### G16-01 changed — Separate byte orders

Use the model in G16-01: Which archive fields use big-endian four-byte values
despite little-endian ELF payloads?

Change the premise: An ELF relocation addend follows inside a member. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G16-02 changed — Trace a rescan

Use the model in G16-02: Give selection order for environment/startup/spare in
the supplied model.

Change the premise: Put startup before environment. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G16-03 changed — Use strong demand

Use the model in G16-03: Does an unresolved weak name alone pull a member?

Change the premise: A strong demand has only a weak definition available. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G16-04 changed — Keep whole members

Use the model in G16-04: A selected object contains an unused function’s strong
reference. May it be ignored just because that function will not run?

Change the premise: The object was never selected. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G16-05 changed — Respect input order

Use the model in G16-05: Why can libhelpers before consumer leave answer
unresolved?

Change the premise: Repeat libhelpers after consumer. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G16-06 changed — Preserve lifetime

Use the model in G16-06: Why copy selected member bytes before closing the
archive?

Change the premise: No member is selected. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G16-07 changed — Name the fixed point

Use the model in G16-07: What does “no new archive member” establish?

Change the premise: A later object introduces a new name. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G16-01

1. Each container has its own serialized contract.
2. Read the index format before following its offset.
3. Its byte order is distinct from ELF member serialization.

### Hints for G16-02

1. Update demands as each member enters the linker.
2. Add a selected member’s undefined uses to the needs.
3. Rescan the same archive when A introduces the need for support.

### Hints for G16-03

1. Reference strength and definition strength differ.
2. Retain binding in the demand set.
3. A weak undefined use does not drive extraction like a strong need.

### Hints for G16-04

1. Select objects before discussing executed functions.
2. Select the object member as a whole.
3. A needed definition brings the member’s other symbols and relocations.

### Hints for G16-05

1. An active archive rescan differs from reopening a closed search.
2. Locate when the need appears on the command line.
3. A passed archive is not reopened merely because a later object adds a use.

### Hints for G16-06

1. Payload ownership and input identity are distinct.
2. Follow borrowed member names into linker ownership.
3. Selected bytes must outlive closing the archive that originally supplied their spans.

### Hints for G16-07

1. State which process has reached its stopping rule.
2. Define the scope of the fixed point.
3. The repeat loop closes needs within the current archive boundary.

## Worked solutions

### Solution G16-01 — Separate byte orders

The original question asks: Which archive fields use big-endian four-byte values
despite little-endian ELF payloads?

The archive symbol-index count and member offsets. ELF’s byte order does not
apply to the enclosing ar index.

**Check your explanation:** Each container has its own serialized contract. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** using little-endian reads for every archive number. Its
byte order is distinct from ELF member serialization.

### Solution G16-02 — Trace a rescan

The original question asks: Give selection order for environment/startup/spare
in the supplied model.

startup first introduces environ; environment follows on a later pass; spare
remains unselected.

**Check your explanation:** Update demands as each member enters the linker. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** stopping after selecting only the first directly needed
member. Rescan the same archive when A introduces the need for support.

### Solution G16-03 — Use strong demand

The original question asks: Does an unresolved weak name alone pull a member?

No. Extraction is triggered by strong unresolved names.

**Check your explanation:** Reference strength and definition strength differ. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** extracting a member for every undefined spelling. A weak
undefined use does not drive extraction like a strong need.

### Solution G16-04 — Keep whole members

The original question asks: A selected object contains an unused function’s
strong reference. May it be ignored just because that function will not run?

No. Whole-object inclusion exposes its symbol obligations; runtime reachability
is not member selection.

**Check your explanation:** Select objects before discussing executed functions.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** extracting only one function’s bytes from an archive
member. A needed definition brings the member’s other symbols and relocations.

### Solution G16-05 — Respect input order

The original question asks: Why can libhelpers before consumer leave answer
unresolved?

Its scan completed before the demand appeared, and earlier archives are not
implicitly revisited.

**Check your explanation:** An active archive rescan differs from reopening a
closed search. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** equating provider presence anywhere with command-order
linkability. A passed archive is not reopened merely because a later object adds
a use.

### Solution G16-06 — Preserve lifetime

The original question asks: Why copy selected member bytes before closing the
archive?

The linker owns the selected mappings and their borrowed name spans
independently of the archive’s lifetime.

**Check your explanation:** Payload ownership and input identity are distinct. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** retaining pointers into closed archive storage. Selected
bytes must outlive closing the archive that originally supplied their spans.

### Solution G16-07 — Name the fixed point

The original question asks: What does “no new archive member” establish?

Closure of this bounded membership search, not equality of compiler generations
or universal unresolved-name closure across future inputs.

**Check your explanation:** State which process has reached its stopping rule. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** claiming unlimited global rescanning from a local loop.
The repeat loop closes needs within the current archive boundary.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G16-01 — Separate byte orders

It uses the object’s explicit little-endian eight-byte representation. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G16-02 — Trace a rescan

Both can be selected in the same pass; final needed membership remains startup
and environment. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G16-03 — Use strong demand

That indexed definition can supply it. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G16-04 — Keep whole members

Its inner payload is not included merely because it exists in the archive.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G16-05 — Respect input order

The repeated search can now select the needed provider. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G16-06 — Preserve lifetime

The archive still counts as an input identity for alias protection. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G16-07 — Name the fixed point

The completed earlier scan is not automatically rerun. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/16-indexed-archives-and-lazy-extraction.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
