# G14: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/14-bitfield-layout-and-preserving-stores.md#try-the-mechanism).
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

### G14-01 changed — Separate metadata

Use the model in G14-01: Do 72-byte field records imply 72-byte target fields?

Change the premise: The base unit is four bytes and width three. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G14-02 changed — Extract a field

Use the model in G14-02: Derive the supplied 0xA6 field value.

Change the premise: Extract payload 111 as signed three-bit. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G14-03 changed — Preserve a unit

Use the model in G14-03: Assign five to width three/shift one in 0xA6.

Change the premise: Assign thirteen. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G14-04 changed — Handle a zero width

Use the model in G14-04: What does an unnamed zero-width declaration change?

Change the premise: Give that zero-width field a name. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G14-05 changed — Choose promotion

Use the model in G14-05: What is the expression type of an unsigned three-bit
field?

Change the premise: Use unsigned width 32. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G14-06 changed — Reject an address

Use the model in G14-06: Why reject taking an ordinary pointer to this bitfield?

Change the premise: Its parent record has a valid symbol. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G14-07 changed — Bound volatile behavior

Use the model in G14-07: Does the preserving store establish atomic neighbor
updates?

Change the premise: The field is volatile. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G14-01

1. Distinguish descriptor representation from represented storage.
2. Keep compiler metadata separate from target layout.
3. A seventy-two-byte field record describes a bit range rather than occupying that range.

### Hints for G14-02

1. Remove neighbors before interpreting signedness.
2. Shift the supplied unit by the field position.
3. Keep only three low bits after shifting one.

### Hints for G14-03

1. Clear old field bits before OR-ing new ones.
2. Clear only the positioned field mask.
3. Merge the shifted three-bit payload with the preserved old unit.

### Hints for G14-04

1. Layout effects need not create named fields.
2. Read layout and initializer roles separately.
3. A zero-width unnamed declaration advances unit placement without consuming an initializer element.

### Hints for G14-05

1. Bit width affects promotion separately from unit size.
2. Compare the field range with the admitted int range.
3. Unsigned three-bit values fit int and receive that selected promotion.

### Hints for G14-06

1. A parent symbol is not a field pointer.
2. Locate whether the field has an independent byte address.
3. A bit range cannot supply the ordinary object pointer this provider requires.

### Hints for G14-07

1. Value preservation and concurrency are separate claims.
2. Distinguish access preservation from atomicity.
3. A volatile read-modify-write remains multiple operations under this contract.

## Worked solutions

### Solution G14-01 — Separate metadata

The original question asks: Do 72-byte field records imply 72-byte target
fields?

No. They are compiler metadata; target storage follows the field’s unit, bit
width and position.

**Check your explanation:** Distinguish descriptor representation from
represented storage. A matching final answer without that reason leaves the
mechanism uncertain. If your answer differs, compare the supplied premises
first, then locate the first transition at which your model departs from the
chapter.

**Common wrong path:** allocating seventy-two target bytes per described
bitfield. A seventy-two-byte field record describes a bit range rather than
occupying that range.

### Solution G14-02 — Extract a field

The original question asks: Derive the supplied 0xA6 field value.

Shift one, then mask seven; result three.

**Check your explanation:** Remove neighbors before interpreting signedness. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** extracting three low unit bits without the field shift.
Keep only three low bits after shifting one.

### Solution G14-03 — Preserve a unit

The original question asks: Assign five to width three/shift one in 0xA6.

Mask 0x0E, retained 0xA0, inserted 0x0A, result 0xAA.

**Check your explanation:** Clear old field bits before OR-ing new ones. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** replacing neighboring bits with a standalone field
payload. Merge the shifted three-bit payload with the preserved old unit.

### Solution G14-04 — Handle a zero width

The original question asks: What does an unnamed zero-width declaration change?

It advances to the natural-unit boundary and consumes no initializer element.

**Check your explanation:** Layout effects need not create named fields. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** treating a zero-width separator as an ordinary
initialized field. A zero-width unnamed declaration advances unit placement
without consuming an initializer element.

### Solution G14-05 — Choose promotion

The original question asks: What is the expression type of an unsigned three-bit
field?

int, because its range fits the selected narrow-field promotion rule.

**Check your explanation:** Bit width affects promotion separately from unit
size. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** assuming an unsigned declaration always produces
unsigned-int expressions. Unsigned three-bit values fit int and receive that
selected promotion.

### Solution G14-06 — Reject an address

The original question asks: Why reject taking an ordinary pointer to this
bitfield?

Its location is a bit range, lacking an independent byte-addressable object and
supported address representation.

**Check your explanation:** A parent symbol is not a field pointer. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** taking an address of an arbitrary bit position as a
conventional C object. A bit range cannot supply the ordinary object pointer
this provider requires.

### Solution G14-07 — Bound volatile behavior

The original question asks: Does the preserving store establish atomic neighbor
updates?

No. It is ordinary load/modify/store with no synchronization guarantee.

**Check your explanation:** Value preservation and concurrency are separate
claims. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** claiming concurrent safety from a volatile declaration. A
volatile read-modify-write remains multiple operations under this contract.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G14-01 — Separate metadata

The field uses three bits in that unit, without a seventy-two-byte target
allocation. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G14-02 — Extract a field

It sign-extends to −1. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G14-03 — Preserve a unit

The same low three bits yield 0xAA. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G14-04 — Handle a zero width

The bounded provider rejects it. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G14-05 — Choose promotion

It remains unsigned int. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G14-06 — Reject an address

The parent’s address does not create a separate field address contract. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G14-07 — Bound volatile behavior

Volatile does not add atomicity and a compound update may load twice. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/14-bitfield-layout-and-preserving-stores.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
