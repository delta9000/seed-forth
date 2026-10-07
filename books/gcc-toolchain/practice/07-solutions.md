# G07: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/07-source-built-allocation-and-byte-operations.md#try-the-mechanism).
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

### G7-01 changed — Choose a class

Use the model in G7-01: Give capacity and stride for request 17.

Change the premise: Use request 32, then 33. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G7-02 changed — Keep failure ownership

Use the model in G7-02: Growing the supplied 17-byte block fails. What remains
live?

Change the premise: Shrink to twelve. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G7-03 changed — Check multiplication first

Use the model in G7-03: Why does calloc compare before multiplying?

Change the premise: count is zero. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G7-04 changed — Move overlap

Use the model in G7-04: Derive the supplied ABCDE move.

Change the premise: Move four bytes from offset one to zero. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G7-05 changed — Separate string contracts

Use the model in G7-05: Does strncpy(dst,"ABCD",4) promise a trailing zero?

Change the premise: Use count six with sufficient destination. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G7-06 changed — Reject a mapping flag

Use the model in G7-06: Why reject MAP_FIXED before calling Linux?

Change the premise: A file offset is above 4 GiB but page-aligned and
nonnegative. What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

### G7-07 changed — Bound runtime closure

Use the model in G7-07: All generator references resolve. Does this establish
every libc service?

Change the premise: The generator runs one successful input too. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G7-01

1. Round payload to the next available power-of-two class.
2. Name request, payload class and block stride separately.
3. Add allocator overhead after choosing the thirty-two-byte class.

### Hints for G7-02

1. Allocate first, free only after success.
2. Keep the old pointer until replacement succeeds.
3. The failure branch preserves the old allocation and its contents.

### Hints for G7-03

1. Use SIZE_MAX/count only for nonzero count.
2. Check the product before interpreting it as an extent.
3. A wrapped count times size is not the original requested storage.

### Hints for G7-04

1. Choose direction before writing.
2. Compare source and destination addresses.
3. Higher overlapping destination requires copying from the end.

### Hints for G7-05

1. The count describes copied/padded bytes.
2. Count source characters against the supplied bound.
3. Four characters fill count four before a terminator can be copied.

### Hints for G7-06

1. Flag support and full-width offsets are separate.
2. Identify the mappings the caller already owns.
3. MAP_FIXED could replace unrelated mappings rather than merely giving a hint.

### Hints for G7-07

1. Name the consumer and exercised path.
2. Name the unresolved set the link actually closes.
3. A selected generator name closure leaves untested libc semantics outside its evidence.

## Worked solutions

### Solution G7-01 — Choose a class

The original question asks: Give capacity and stride for request 17.

Capacity 32, plus sixteen-byte header, gives stride 48. Requested size remains
17.

**Check your explanation:** Round payload to the next available power-of-two
class. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** letting the caller write the whole block stride as its
requested object. Add allocator overhead after choosing the thirty-two-byte
class.

### Solution G7-02 — Keep failure ownership

The original question asks: Growing the supplied 17-byte block fails. What
remains live?

The original pointer, seventeen requested bytes and old metadata remain valid;
only successful replacement triggers free.

**Check your explanation:** Allocate first, free only after success. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** discarding the only old pointer because realloc returned
null. The failure branch preserves the old allocation and its contents.

### Solution G7-03 — Check multiplication first

The original question asks: Why does calloc compare before multiplying?

Unsigned multiplication can wrap. The division-based bound establishes
representability before computing the total.

**Check your explanation:** Use SIZE_MAX/count only for nonzero count. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** accepting a small wrapped calloc product. A wrapped count
times size is not the original requested storage.

### Solution G7-04 — Move overlap

The original question asks: Derive the supplied ABCDE move.

Backward copying gives AABCD, preserving each still-unread source byte.

**Check your explanation:** Choose direction before writing. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** using forward copy when each store destroys a later
source byte. Higher overlapping destination requires copying from the end.

### Solution G7-05 — Separate string contracts

The original question asks: Does strncpy(dst,"ABCD",4) promise a trailing zero?

No. The four source bytes fill the count, leaving no terminator under this
implementation.

**Check your explanation:** The count describes copied/padded bytes. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** assuming every bounded string copy guarantees a trailing
zero. Four characters fill count four before a terminator can be copied.

### Solution G7-06 — Reject a mapping flag

The original question asks: Why reject MAP_FIXED before calling Linux?

The bounded interface promises hints that cannot replace unrelated mappings;
MAP_FIXED would change that ownership contract.

**Check your explanation:** Flag support and full-width offsets are separate. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** letting a bounded mapping wrapper overwrite an existing
unrelated allocation. MAP_FIXED could replace unrelated mappings rather than
merely giving a hint.

### Solution G7-07 — Bound runtime closure

The original question asks: All generator references resolve. Does this
establish every libc service?

No. It establishes a selected name closure, with actual semantics and executed
workload outcomes separate.

**Check your explanation:** Name the consumer and exercised path. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** equating resolved generator references with every libc
service. A selected generator name closure leaves untested libc semantics
outside its evidence.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G7-01 — Choose a class

32 uses capacity 32/stride 48; 33 uses capacity 64/stride 80. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G7-02 — Keep failure ownership

The pointer is reused and requested size becomes twelve; its backing extent need
not shrink. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G7-03 — Check multiplication first

The guard avoids division by zero; total is zero and the allocator’s zero-size
policy applies. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G7-04 — Move overlap

Forward copying gives BCDEE; destination is below source. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G7-05 — Separate string contracts

ABCD is followed by two zero bytes. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G7-06 — Reject a mapping flag

Its width is retained; actual mapping success still depends on kernel/file
premises. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G7-07 — Bound runtime closure

That adds bounded behavior evidence, still not universal libc or compiler
correctness. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/07-source-built-allocation-and-byte-operations.md) and
its stated illustrative inputs. The numerical states are derivations; any
historical result remains attributed to its repository account. No exercise,
generated instruction or build was executed to create these answers.
