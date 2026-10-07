# G10: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/10-floating-values-and-conversion.md#try-the-mechanism).
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

### G10-01 changed — Classify a move

Use the model in G10-01: Does moving 1.5’s payload into XMM0 numerically convert
it?

Change the premise: Move integer payload one without conversion. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G10-02 changed — Keep storage width

Use the model in G10-02: How many bytes does float store despite an eight-byte
expression slot?

Change the premise: Use double. What follows under this changed premise? State
the result or remaining obligation and explain which original reasoning still
applies. Keep the other supplied contracts.

### G10-03 changed — Choose precision

Use the model in G10-03: Why not do all float arithmetic as double until
storage?

Change the premise: One operand is double. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G10-04 changed — Separate return banks

Use the model in G10-04: Where do floating and integer scalar results cross the
call boundary?

Change the premise: A caller declared integer while provider returns double.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G10-05 changed — Treat unsigned values

Use the model in G10-05: Why special-case the high unsigned 64-bit half?

Change the premise: Use a small signed positive integer. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G10-06 changed — Handle unordered comparison

Use the model in G10-06: Can NaN equal itself under the selected comparison
rules?

Change the premise: Compare either signed zero with zero for truth. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G10-07 changed — Bound literal support

Use the model in G10-07: Does float arithmetic imply acceptance of 1.0f by this
decoder?

Change the premise: Try the typed spelling 0x1p0L. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G10-01

1. Ask whether the represented number or just the location changes.
2. Write a mathematical value and its payload separately.
3. A copied hexadecimal payload is not an integer numeric conversion.

### Hints for G10-02

1. Slot capacity is not C object size.
2. Read the destination type before selecting the store.
3. Float and double have different widths and representations.

### Hints for G10-03

1. The common type selects the SSE precision prefix.
2. Locate the arithmetic operation before the final store.
3. Binary32 rounding at an intermediate operation can differ from a late binary64-to-float store.

### Hints for G10-04

1. Internal carrier and ABI register differ.
2. Label result banks at the ABI boundary.
3. XMM0 and RAX are different return carriers before internal expression adaptation.

### Hints for G10-05

1. Signedness remains meaningful at equal width.
2. Ask whether bit 63 is magnitude or sign for this source.
3. The unsigned high-half path preserves magnitude rather than applying signed conversion blindly.

### Hints for G10-06

1. Unordered and zero tests are separate cases.
2. Include the unordered condition in the comparison.
3. NaN equality excludes unordered while not-equal includes it.

### Hints for G10-07

1. Lexical recognition does not imply decoder acceptance.
2. Read the decoder’s spelling gate.
3. The wrapper selects binary32 for f/F before rounding.

## Worked solutions

### Solution G10-01 — Classify a move

The original question asks: Does moving 1.5’s payload into XMM0 numerically
convert it?

No. It transports the existing binary64 encoding; integer-to-floating conversion
is a different operation.

**Check your explanation:** Ask whether the represented number or just the
location changes. A matching final answer without that reason leaves the
mechanism uncertain. If your answer differs, compare the supplied premises
first, then locate the first transition at which your model departs from the
chapter.

**Common wrong path:** returning the floating bits as the converted integer
value. A copied hexadecimal payload is not an integer numeric conversion.

### Solution G10-02 — Keep storage width

The original question asks: How many bytes does float store despite an
eight-byte expression slot?

Four; the storage adapter preserves the floating expression type while choosing
four-byte payload writes.

**Check your explanation:** Slot capacity is not C object size. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** storing the low half of a double payload to implement
float conversion. Float and double have different widths and representations.

### Solution G10-03 — Choose precision

The original question asks: Why not do all float arithmetic as double until
storage?

Intermediate rounding would differ from the selected binary32 arithmetic
contract.

**Check your explanation:** The common type selects the SSE precision prefix. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** postponing every float rounding until storage. Binary32
rounding at an intermediate operation can differ from a late binary64-to-float
store.

### Solution G10-04 — Separate return banks

The original question asks: Where do floating and integer scalar results cross
the call boundary?

Floating in XMM0, integer in RAX; both may become RDI carriers inside
expressions.

**Check your explanation:** Internal carrier and ABI register differ. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** reading a floating return from the integer return bank.
XMM0 and RAX are different return carriers before internal expression
adaptation.

### Solution G10-05 — Treat unsigned values

The original question asks: Why special-case the high unsigned 64-bit half?

A signed conversion would interpret bit 63 as a negative sign; the sticky-half
path preserves unsigned magnitude before doubling.

**Check your explanation:** Signedness remains meaningful at equal width. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** interpreting a large unsigned value as negative. The
unsigned high-half path preserves magnitude rather than applying signed
conversion blindly.

### Solution G10-06 — Handle unordered comparison

The original question asks: Can NaN equal itself under the selected comparison
rules?

No. Equality excludes unordered; not-equal includes it.

**Check your explanation:** Unordered and zero tests are separate cases. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** assuming every identical-looking payload must compare
equal numerically. NaN equality excludes unordered while not-equal includes it.

### Solution G10-07 — Bound literal support

The original question asks: Does float arithmetic imply acceptance of 1.0f by
this decoder?

Arithmetic alone does not establish spelling support. This pin’s typed wrapper
does accept 1.0f: it strips f and selects binary32 before exact rounding.

**Check your explanation:** Lexical recognition does not imply decoder
acceptance. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** inferring literal grammar from emitted float arithmetic.
The typed wrapper selects binary32 for f/F; an unsuffixed literal can also
convert from double.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G10-01 — Classify a move

Those bits do not encode floating 1.0. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G10-02 — Keep storage width

Its object storage is eight bytes. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G10-03 — Choose precision

The common floating type becomes double and operand conversion precedes
arithmetic. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G10-04 — Separate return banks

Name resolution cannot repair that class mismatch; declarations must agree.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G10-05 — Treat unsigned values

The ordinary signed conversion path is adequate for that admitted value. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G10-06 — Handle unordered comparison

Both zeros are false because the test removes the sign in scratch. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G10-07 — Bound literal support

Extended L-suffixed hexfloat with a p exponent is admitted; raw binary64
hexfloat remains rejected. The selected format must be named.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/10-floating-values-and-conversion.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
