# G15: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/15-aggregate-values-and-x87-transport.md#try-the-mechanism).
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

### G15-01 changed — Classify a record

Use the model in G15-01: Classify a naturally aligned two-long sixteen-byte
record under the admitted integer rules.

Change the premise: Make its size twenty-four bytes. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G15-02 changed — Roll back registers

Use the model in G15-02: Five GP scalars precede the two-eightbyte record. Where
does it go?

Change the premise: Add a following scalar. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G15-03 changed — Snapshot a value

Use the model in G15-03: Why not retain only r’s address when a later argument
mutates r?

Change the premise: The argument is a pointer to r instead. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G15-04 changed — Order copies

Use the model in G15-04: Why spill register parameters before stack copies?

Change the premise: Load outgoing registers before copying stack arguments. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G15-05 changed — Allocate a hidden result

Use the model in G15-05: A MEMORY return precedes one explicit long argument.
Which register carries that argument?

Change the premise: The result is a small one-eightbyte INTEGER record instead.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G15-06 changed — Transport long double

Use the model in G15-06: Does a long-double argument use XMM0 when available?

Change the premise: The program asks for long-double addition in this producer.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G15-07 changed — Protect result lifetime

Use the model in G15-07: Why is returning a pointer to a callee local not the
MEMORY return model?

Change the premise: A small result is captured into the caller’s frame slot.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G15-01

1. Size and member validation both matter.
2. Count admitted INTEGER eightbytes from the record extent.
3. A sixteen-byte two-long record has two chunks, while its expression carrier still addresses bytes.

### Hints for G15-02

1. Test complete demand before committing.
2. Undo the unsuccessful tentative assignment.
3. The later scalar can use the register the record did not finally consume.

### Hints for G15-03

1. Passing object bytes differs from passing an address.
2. Track source storage and snapshot storage separately.
3. Later argument evaluation can change the source without changing the evaluated snapshot.

### Hints for G15-04

1. Copy helpers have their own register consumers.
2. Check which registers the byte copier uses.
3. Preserve incoming register parameters before stack copying can overwrite those registers.

### Hints for G15-05

1. Classify the result before planning parameters.
2. Place the memory-return pointer before explicit parameters.
3. RDI is hidden destination, so the explicit long begins at the next general register.

### Hints for G15-06

1. Transport and arithmetic have separate providers.
2. Read X87 argument alignment independently of payload size.
3. Stack space and the ST0 result are different transport boundaries.

### Hints for G15-07

1. Follow the owner across RET.
2. Identify who owns the completed return bytes.
3. A caller-owned hidden destination survives the callee frame; a local pointer does not.

## Worked solutions

### Solution G15-01 — Classify a record

The original question asks: Classify a naturally aligned two-long sixteen-byte
record under the admitted integer rules.

Two INTEGER eightbytes; its expression carrier is still an address to bytes.

**Check your explanation:** Size and member validation both matter. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** confusing an address carrier with pointer-valued record
contents. A sixteen-byte two-long record has two chunks, while its expression
carrier still addresses bytes.

### Solution G15-02 — Roll back registers

The original question asks: Five GP scalars precede the two-eightbyte record.
Where does it go?

Entirely on the stack; the last GP register remains available.

**Check your explanation:** Test complete demand before committing. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** leaving R9 spent after whole-record rollback. The later
scalar can use the register the record did not finally consume.

### Solution G15-03 — Snapshot a value

The original question asks: Why not retain only r’s address when a later
argument mutates r?

By-value argument evaluation must preserve the earlier captured bytes. The
snapshot prevents the later mutation from changing that value.

**Check your explanation:** Passing object bytes differs from passing an
address. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** passing a live source pointer in place of an earlier
by-value snapshot. Later argument evaluation can change the source without
changing the evaluated snapshot.

### Solution G15-04 — Order copies

The original question asks: Why spill register parameters before stack copies?

The byte-copy implementation uses GP registers that could destroy
still-unspilled parameters.

**Check your explanation:** Copy helpers have their own register consumers. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** copying stack parameters while live incoming register
values remain unspilled. Preserve incoming register parameters before stack
copying can overwrite those registers.

### Solution G15-05 — Allocate a hidden result

The original question asks: A MEMORY return precedes one explicit long argument.
Which register carries that argument?

RSI, because RDI carries the hidden result destination.

**Check your explanation:** Classify the result before planning parameters. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** assigning the explicit first argument to the hidden
destination register. RDI is hidden destination, so the explicit long begins at
the next general register.

### Solution G15-06 — Transport long double

The original question asks: Does a long-double argument use XMM0 when available?

No. Its X87 class argument uses a sixteen-aligned stack copy; the result uses
st(0).

**Check your explanation:** Transport and arithmetic have separate providers. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** using the binary64 call class for long double. Stack
space and the ST0 result are different transport boundaries.

### Solution G15-07 — Protect result lifetime

The original question asks: Why is returning a pointer to a callee local not the
MEMORY return model?

The hidden destination is caller-owned; copying there preserves the value beyond
the callee frame’s lifetime.

**Check your explanation:** Follow the owner across RET. A matching final answer
without that reason leaves the mechanism uncertain. If your answer differs,
compare the supplied premises first, then locate the first transition at which
your model departs from the chapter.

**Common wrong path:** returning an expired callee-local address as a
memory-return value. A caller-owned hidden destination survives the callee
frame; a local pointer does not.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G15-01 — Classify a record

It uses MEMORY under the bounded classifier. Accept an explanation that follows
the changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G15-02 — Roll back registers

It can use R9 because the record consumed no partial register assignment. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G15-03 — Snapshot a value

Then passing the pointer value has a different contract; it need not snapshot
r’s entire object. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G15-04 — Order copies

The same clobber risk appears on the caller side. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G15-05 — Allocate a hidden result

No hidden destination is needed; the first explicit scalar can use RDI. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G15-06 — Transport long double

That computing use rejects under the bounded transport-only contract. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G15-07 — Protect result lifetime

Its expression address refers to that caller-owned result storage, not the
callee’s dead source. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/15-aggregate-values-and-x87-transport.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
