# G05: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/05-linking-independently-built-objects.md#try-the-mechanism).
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

### G5-01 changed — Place text

Use the model in G5-01: Derive A/B starts, B’s virtual address and the gap in
the supplied layout.

Change the premise: Change A size to 32. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G5-02 changed — Close the call

Use the model in G5-02: Derive the model call’s field bytes and CPU destination.

Change the premise: Move B forward sixteen without moving A. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G5-03 changed — Choose the provider

Use the model in G5-03: A weak definition precedes a strong definition of
answer. Which survives?

Change the premise: Replace the first with a strong definition too. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G5-04 changed — Resolve weak uses

Use the model in G5-04: An undefined weak use has no provider. Contrast an
undefined strong use.

Change the premise: A weak provider exists for the strong use. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G5-05 changed — Preserve BSS

Use the model in G5-05: Add sixteen BSS bytes after an aligned data end. Which
final extent grows?

Change the premise: Move the same bytes to initialized data. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G5-06 changed — Reject a false entry

Use the model in G5-06: The requested name is main but the driver contract
requested _start. Can name resolution silently substitute main?

Change the premise: _start exists in data. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G5-07 changed — Report publication

Use the model in G5-07: A failed link leaves an older file at the output path.
What may be claimed?

Change the premise: The new temporary contains all bytes but close fails. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G5-01

1. Round the current exclusive end to B’s alignment.
2. Place B after A’s exclusive end and required alignment.
3. Round 0x1015 up to the next sixteen-byte boundary before adding the image base.

### Hints for G5-02

1. Convert both positions to virtual coordinates first.
2. Write S, A and P as separate values.
3. Use the field address for P; use the next instruction only for the CPU check.

### Hints for G5-03

1. Strength determines replacement, not just input order.
2. Read weak and strong binding with the name.
3. The strong provider replaces the prior weak choice.

### Hints for G5-04

1. Separate reference strength from provider strength.
2. Distinguish a permitted absent weak use from a required definition.
3. Zero resolution is not an implementation of a function.

### Hints for G5-05

1. File backing and memory reservation differ.
2. Keep segment file extent and memory extent separate.
3. BSS contributes memory after the stored writable bytes.

### Hints for G5-06

1. Check both requested identity and section role.
2. Find the resolved process-entry provider.
3. The loader starts at the executable entry; main is reached by startup.

### Hints for G5-07

1. Use final status and output identity together.
2. Find the publication transition after output construction.
3. A complete output buffer still needs successful delivery and final publication.

## Worked solutions

### Solution G5-01 — Place text

The original question asks: Derive A/B starts, B’s virtual address and the gap
in the supplied layout.

A starts at 0x1000, B at 0x1020, B’s address is 0x401020 and the gap is eleven
bytes after A’s end 0x1015.

**Check your explanation:** Round the current exclusive end to B’s alignment. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** placing B directly at A’s unaligned end. Round 0x1015 up
to the next sixteen-byte boundary before adding the image base.

### Solution G5-02 — Close the call

The original question asks: Derive the model call’s field bytes and CPU
destination.

P=0x401011, S=0x401020, A=−4; field eleven gives 0B 00 00 00, and P+4+11 reaches
S.

**Check your explanation:** Convert both positions to virtual coordinates first.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** subtracting the four-byte width twice. Use the field
address for P; use the next instruction only for the CPU check.

### Solution G5-03 — Choose the provider

The original question asks: A weak definition precedes a strong definition of
answer. Which survives?

The strong definition replaces the weak choice. Ownership moves with the chosen
symbol.

**Check your explanation:** Strength determines replacement, not just input
order. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** letting earlier command position make a weak definition
defeat a strong one. The strong provider replaces the prior weak choice.

### Solution G5-04 — Resolve weak uses

The original question asks: An undefined weak use has no provider. Contrast an
undefined strong use.

The weak use can resolve to zero; the strong use fails resolution. Zero is not a
function implementation.

**Check your explanation:** Separate reference strength from provider strength.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** treating weak-zero resolution as a callable provider.
Zero resolution is not an implementation of a function.

### Solution G5-05 — Preserve BSS

The original question asks: Add sixteen BSS bytes after an aligned data end.
Which final extent grows?

Memory extent grows, while the BSS payload adds no file bytes. Its alignment may
still affect placement.

**Check your explanation:** File backing and memory reservation differ. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** inventing a zero-filled file payload to explain every BSS
byte. BSS contributes memory after the stored writable bytes.

### Solution G5-06 — Reject a false entry

The original question asks: The requested name is main but the driver contract
requested _start. Can name resolution silently substitute main?

No. Entry lookup uses the requested name and requires a text definition. The
driver must supply or request the intended startup.

**Check your explanation:** Check both requested identity and section role. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** using main as entry without its required runtime
preparation. The loader starts at the executable entry; main is reached by
startup.

### Solution G5-07 — Report publication

The original question asks: A failed link leaves an older file at the output
path. What may be claimed?

The new link failed and the old file survived. Its presence does not demonstrate
a new executable or new execution.

**Check your explanation:** Use final status and output identity together. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** treating a correct relocation calculation as a successful
file write. A complete output buffer still needs successful delivery and final
publication.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G5-01 — Place text

A ends at 0x1020, B starts there and the gap disappears. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G5-02 — Close the call

Field becomes 27, bytes 1B 00 00 00. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G5-03 — Choose the provider

Two strong definitions reject rather than silently select the latter. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G5-04 — Resolve weak uses

Its definition can supply the needed name; archive extraction still depends on
strong demand. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G5-05 — Preserve BSS

Their payload now grows file size as well as mapped memory. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G5-06 — Reject a false entry

It still fails the text-entry check. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G5-07 — Report publication

Publication is still unauthorized by the implementation’s completion rule; the
old path must not be replaced. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/05-linking-independently-built-objects.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
