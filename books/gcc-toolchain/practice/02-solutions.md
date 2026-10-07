# G02: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/02-objects-symbols-and-relocation-records.md#try-the-mechanism).
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

### G2-01 changed — Locate the obligation

Use the model in G2-01: For text end 21, derive the first and last bytes of a
four-byte relocation at offset 17. Would offset 18 fit? Name the coordinate.

Change the premise: Change text end to 24 and field offset to 20. Does it fit
exactly? What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G2-02 changed — Align before reserving

Use the model in G2-02: Starting with data length 5, align to 8 and reserve four
bytes. Give padding, object offset and new length.

Change the premise: Repeat from length 8. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G2-03 changed — Translate identity

Use the model in G2-03: Use the three-handle worked state. What file index must
a relocation to handle 1 contain, and why?

Change the premise: Create two locals after answer and before main. What index
does answer receive? What follows under this changed premise? State the result
or remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

### G2-04 changed — Count memory and file bytes

Use the model in G2-04: Reserve 32 bytes in BSS. Which extent grows? Can
cc-obj-byte supply its payload?

Change the premise: Reserve the same count in data. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G2-05 changed — Keep the addend explicit

Use the model in G2-05: A PLT32 field contains four zero bytes and its RELA
addend is −4. Which supplies the adjustment?

Change the premise: Replace the placeholder bytes with a supplied nonzero
pattern while keeping the RELA record. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G2-06 changed — Preserve an old output

Use the model in G2-06: A partial write succeeds, then close reports failure. Is
the final path ready to publish? Identify the owned resource.

Change the premise: Exclusive creation finds an existing temporary. May cleanup
unlink it? What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

### G2-07 changed — Bound the claim

Use the model in G2-07: An inspector verifies ET_REL and ten sections. Does that
establish final placement or execution? List the remaining boundaries.

Change the premise: A file hash also matches a saved object hash. What changes?
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G2-01

1. Use exclusive end = offset + width.
2. Locate the exclusive end of text.
3. Add the field width to its starting offset and compare with that end.

### Hints for G2-02

1. Find the next multiple of eight.
2. Keep alignment and reservation as two steps.
3. Find the next multiple of eight before adding the object size.

### Hints for G2-03

1. Separate creation order from local-first serialization.
2. Write creation handles and serialized indexes in separate columns.
3. Put the null row first, then locals, then nonlocals.

### Hints for G2-04

1. Ask which section has backing bytes.
2. Ask whether the section has a payload in the file.
3. BSS increases an extent even though no reserved zero payload is serialized.

### Hints for G2-05

1. RELA names an explicit addend.
2. Read the A in RELA as a separate record field.
3. Find the signed eight-byte addend rather than decoding the placeholder.

### Hints for G2-06

1. Ownership begins only after successful exclusive creation.
2. Locate the first successful exclusive creation.
3. Distinguish a descriptor no longer owned from a temporary path still owned.

### Hints for G2-07

1. Name the artifact being inspected.
2. Identify whether the inspected artifact is relocatable or executable.
3. List the remaining consumers after object serialization.

## Worked solutions

### Solution G2-01 — Locate the obligation

The original question asks: For text end 21, derive the first and last bytes of
a four-byte relocation at offset 17. Would offset 18 fit? Name the coordinate.

The field is section offsets 17–20, wholly below exclusive end 21. Offset 18
would end at 22 and fails. These are text-relative positions, not final virtual
addresses.

**Check your explanation:** Use exclusive end = offset + width. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** reading the last byte as the exclusive end, which shifts
the fit test by one. Add the field width to its starting offset and compare with
that end.

### Solution G2-02 — Align before reserving

The original question asks: Starting with data length 5, align to 8 and reserve
four bytes. Give padding, object offset and new length.

Padding is three, object offset 8 and final length 12. Alignment reserves
storage before the object reservation.

**Check your explanation:** Find the next multiple of eight. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** adding eight bytes of padding even when the cursor is
already aligned. Find the next multiple of eight before adding the object size.

### Solution G2-03 — Translate identity

The original question asks: Use the three-handle worked state. What file index
must a relocation to handle 1 contain, and why?

Index 2 names answer after the local-first pass. Copying API handle 1 would
select private in this supplied table.

**Check your explanation:** Separate creation order from local-first
serialization. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** copying a writer handle into the file as though it were
already a symbol index. Put the null row first, then locals, then nonlocals.

### Solution G2-04 — Count memory and file bytes

The original question asks: Reserve 32 bytes in BSS. Which extent grows? Can
cc-obj-byte supply its payload?

BSS memory extent grows by 32. Its payload is not emitted, and direct byte
emission to BSS rejects. Metadata still occupies file bytes.

**Check your explanation:** Ask which section has backing bytes. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** equating memory size with bytes emitted into the file.
BSS increases an extent even though no reserved zero payload is serialized.

### Solution G2-05 — Keep the addend explicit

The original question asks: A PLT32 field contains four zero bytes and its RELA
addend is −4. Which supplies the adjustment?

The explicit eight-byte RELA addend supplies −4. Placeholder bytes reserve the
later patch; they are not the addend.

**Check your explanation:** RELA names an explicit addend. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** using the old call-field bytes as an implicit addend.
Find the signed eight-byte addend rather than decoding the placeholder.

### Solution G2-06 — Preserve an old output

The original question asks: A partial write succeeds, then close reports
failure. Is the final path ready to publish? Identify the owned resource.

No. The owned sibling temporary is abandoned and the old final path is not
replaced. The descriptor is marked invalid after the close attempt.

**Check your explanation:** Ownership begins only after successful exclusive
creation. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** publishing after bytes were written while ignoring failed
close. Distinguish a descriptor no longer owned from a temporary path still
owned.

### Solution G2-07 — Bound the claim

The original question asks: An inspector verifies ET_REL and ten sections. Does
that establish final placement or execution? List the remaining boundaries.

It establishes bounded file-format facts. G05 must validate, resolve and place;
publication, loading and target execution require separate evidence.

**Check your explanation:** Name the artifact being inspected. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** treating an ELF family identification as evidence of
process execution. List the remaining consumers after object serialization.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G2-01 — Locate the obligation

It occupies 20–23 and fits end 24 exactly; no address placement is implied.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G2-02 — Align before reserving

Padding is zero, object offset 8 and final length 12. Alignment does not always
add a full unit. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G2-03 — Translate identity

With null row zero and two locals first, answer receives index 3. Its API handle
remains 1. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G2-04 — Count memory and file bytes

Data length grows by 32 and its zeroed payload is file-backed. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G2-05 — Keep the addend explicit

The consumer still uses the explicit addend; the field is overwritten. Do not
infer an implicit adjustment. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G2-06 — Preserve an old output

No; this attempt never acquired ownership of that existing temporary. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G2-07 — Bound the claim

Object identity is stronger, but an object hash still does not supply final link
addresses or an executed result. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/02-objects-symbols-and-relocation-records.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
