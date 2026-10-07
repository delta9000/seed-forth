# G11: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/11-decimal-literals-rounded-once.md#try-the-mechanism).
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

### G11-01 changed — Construct a ratio

Use the model in G11-01: Give mantissa, scale and exact ratio for 1.25.

Change the premise: Use 12.5e-1. What follows under this changed premise? State
the result or remaining obligation and explain which original reasoning still
applies. Keep the other supplied contracts.

### G11-02 changed — Round an even midpoint

Use the model in G11-02: Use the three-bit model at 1.125.

Change the premise: Use midpoint 1.375. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G11-03 changed — Compare a remainder

Use the model in G11-03: What do 2r<D, 2r>D and 2r=D each mean?

Change the premise: A nonzero remainder is supplied without its relation to D.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G11-04 changed — Preserve a carry

Use the model in G11-04: Rounding grows the significand beyond its normal
retained width. What happens?

Change the premise: The increased exponent exceeds 1023. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G11-05 changed — Reach the smallest spacing

Use the model in G11-05: What happens at exactly 2^−1075?

Change the premise: Move just above that midpoint within the boundary branch.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G11-06 changed — Retain grammar limits

Use the model in G11-06: Is an exponent magnitude of one million equivalent to
unlimited exponent text?

Change the premise: A suffix f follows a valid decimal mantissa. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G11-07 changed — Name the producer

Use the model in G11-07: What did Forth produce: a host double or target bits?

Change the premise: A host oracle agrees for one literal. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G11-01

1. Scale is exponent minus fractional count.
2. Turn digits and scale into integers first.
3. Keep numerator and denominator exact before choosing binary bits.

### Hints for G11-02

1. Inspect the retained quotient’s low bit at equality.
2. Place the candidate between its two representable neighbors.
3. At a tie, inspect the least significant retained bit.

### Hints for G11-03

1. Keep the exact remainder and denominator.
2. Compare twice the remainder with the denominator.
3. Only exact equality reaches the quotient-parity tie rule.

### Hints for G11-04

1. Normalization must remain valid after rounding.
2. Retain the bit carried beyond the significand.
3. Shifting the carried quotient increases the exponent and can expose range overflow.

### Hints for G11-05

1. Subnormal spacing is fixed at 2^−1074.
2. Use fixed spacing at the subnormal bottom.
3. Half the minimum subnormal ties with zero, whose retained result is even.

### Hints for G11-06

1. Check token, digit and exponent bounds separately.
2. Read magnitude and spelling bounds independently.
3. A bounded admitted exponent value does not permit unlimited token length.

### Hints for G11-07

1. Distinguish encoding production from floating execution.
2. Identify the object produced by the Forth calculation.
3. The integer ratio calculation supplies a target binary64 encoding cell.

## Worked solutions

### Solution G11-01 — Construct a ratio

The original question asks: Give mantissa, scale and exact ratio for 1.25.

125, −2 and 125/100=5/4. No rounding is needed for its terminating binary
representation.

**Check your explanation:** Scale is exponent minus fractional count. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** introducing host floating rounding before the target
rounding. Keep numerator and denominator exact before choosing binary bits.

### Solution G11-02 — Round an even midpoint

The original question asks: Use the three-bit model at 1.125.

The lower significand 100 is even, so the exact midpoint rounds to 1.

**Check your explanation:** Inspect the retained quotient’s low bit at equality.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** always rounding a halfway value downward. At a tie,
inspect the least significant retained bit.

### Solution G11-03 — Compare a remainder

The original question asks: What do 2r<D, 2r>D and 2r=D each mean?

Below halfway, above halfway and exact tie respectively; only the tie depends on
quotient parity.

**Check your explanation:** Keep the exact remainder and denominator. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** rounding upward for every nonzero discarded remainder.
Only exact equality reaches the quotient-parity tie rule.

### Solution G11-04 — Preserve a carry

The original question asks: Rounding grows the significand beyond its normal
retained width. What happens?

The quotient shifts and exponent increases; the carry is preserved and may
expose overflow.

**Check your explanation:** Normalization must remain valid after rounding. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** dropping a rounding carry before the exponent check.
Shifting the carried quotient increases the exponent and can expose range
overflow.

### Solution G11-05 — Reach the smallest spacing

The original question asks: What happens at exactly 2^−1075?

It is half the minimum positive subnormal, and ties to even chooses zero.

**Check your explanation:** Subnormal spacing is fixed at 2^−1074. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** rejecting a zero rounded result solely because the exact
input is positive. Half the minimum subnormal ties with zero, whose retained
result is even.

### Solution G11-06 — Retain grammar limits

The original question asks: Is an exponent magnitude of one million equivalent
to unlimited exponent text?

No. Token length and spelling checks remain independent; magnitude also has its
explicit limit.

**Check your explanation:** Check token, digit and exponent bounds separately. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** treating a magnitude limit as the only parser limit. A
bounded admitted exponent value does not permit unlimited token length.

### Solution G11-07 — Name the producer

The original question asks: What did Forth produce: a host double or target
bits?

A binary64 encoding cell produced using integer ratio and rounding operations.
G10 later emits its payload.

**Check your explanation:** Distinguish encoding production from floating
execution. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** inserting a host double conversion as an unrecorded
production step. The integer ratio calculation supplies a target binary64
encoding cell.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G11-01 — Construct a ratio

Mantissa 125, one fractional digit and exponent −1 give scale −2, the same
ratio. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G11-02 — Round an even midpoint

The lower 101 is odd, so it rounds up to 1.5 with 110. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G11-03 — Compare a remainder

Nonzero alone is insufficient to decide which neighbor. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G11-04 — Preserve a carry

The decoder reports overflow. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G11-05 — Reach the smallest spacing

It rounds to the minimum subnormal, encoding one. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G11-06 — Retain grammar limits

Suffix-unsupported rejects; runtime float arithmetic does not broaden literal
grammar. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G11-07 — Name the producer

That adds one comparison outcome, not proof for every spelling or target
execution. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/11-decimal-literals-rounded-once.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
