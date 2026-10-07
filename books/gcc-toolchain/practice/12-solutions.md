# G12: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/12-variadic-cursors-and-argument-classes.md#try-the-mechanism).
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

### G12-01 changed — Locate fields

Use the model in G12-01: Give all four field offsets and total va_list record
size.

Change the premise: Pass va_list as a function parameter. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G12-02 changed — Walk mixed classes

Use the model in G12-02: Use the one-named-int model to retrieve int, double,
long.

Change the premise: Retrieve double before the first int. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G12-03 changed — Exhaust one bank

Use the model in G12-03: At gp=48 and fp=48, retrieve long then double from
overflow O.

Change the premise: Set fp=176 too. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G12-04 changed — Apply promotions

Use the model in G12-04: An unnamed float is passed. Which admitted type
retrieves its promoted value?

Change the premise: An unnamed narrow integer is supplied. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G12-05 changed — Copy the cursor

Use the model in G12-05: Does va_copy allocate and duplicate every argument?

Change the premise: The invocation has returned. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G12-06 changed — Align wider overflow

Use the model in G12-06: A long-double overflow cursor is 0x1008. Give address
and next cursor.

Change the premise: Start at 0x1010. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G12-07 changed — Bound aggregate support

Use the model in G12-07: Does a named record’s effect on va_start imply unnamed
aggregate va_arg?

Change the premise: The record occupies only eight bytes. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G12-01

1. Follow the header’s array identity.
2. Distinguish scalar offsets from pointer fields.
3. Lay out two four-byte offsets followed by two eight-byte pointers.

### Hints for G12-02

1. Requested type chooses a bank.
2. Write GP and FP cursors separately before retrieval.
3. int/long spend general slots while double spends a floating-save slot.

### Hints for G12-03

1. Bank exhaustion is independent.
2. Check general exhaustion without changing the floating count.
3. Overflow starts for the exhausted class while other slots may remain.

### Hints for G12-04

1. Default promotions precede placement.
2. Apply default promotions before retrieval.
3. A variadic float arrives as the promoted double type.

### Hints for G12-05

1. Record ownership differs from argument storage ownership.
2. Draw two cursor records referring to the same save area.
3. Copying traversal state makes later offsets independent.

### Hints for G12-06

1. X87 transport uses sixteen-byte alignment and size.
2. Round the wider overflow pointer before consuming.
3. Align 0x1008 upward to sixteen before adding a sixteen-byte long-double extent.

### Hints for G12-07

1. Separate named planning from tail retrieval.
2. Check which classes the retrieval provider implements.
3. Inspect cc-ag-va-record separately from named-argument planning.

## Worked solutions

### Solution G12-01 — Locate fields

The original question asks: Give all four field offsets and total va_list record
size.

Offsets 0,4,8,16; size 24 and alignment eight. va_list itself is an array of one
record.

**Check your explanation:** Follow the header’s array identity. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** making every va_list field an eight-byte cell. Lay out
two four-byte offsets followed by two eight-byte pointers.

### Solution G12-02 — Walk mixed classes

The original question asks: Use the one-named-int model to retrieve int, double,
long.

GP goes 8→16→24; FP goes 48→64. The double leaves GP unchanged.

**Check your explanation:** Requested type chooses a bank. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** using one counter for interleaved argument classes.
int/long spend general slots while double spends a floating-save slot.

### Solution G12-03 — Exhaust one bank

The original question asks: At gp=48 and fp=48, retrieve long then double from
overflow O.

Long reads O and advances overflow to O+8; double still reads XMM save offset 48
and advances fp to 64.

**Check your explanation:** Bank exhaustion is independent. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** switching every later type to overflow after one class
exhausts. Overflow starts for the exhausted class while other slots may remain.

### Solution G12-04 — Apply promotions

The original question asks: An unnamed float is passed. Which admitted type
retrieves its promoted value?

double; the caller promotes float in the ellipsis tail.

**Check your explanation:** Default promotions precede placement. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** asking va_arg for the original unpromoted float. A
variadic float arrives as the promoted double type.

### Solution G12-05 — Copy the cursor

The original question asks: Does va_copy allocate and duplicate every argument?

No. It copies cursor fields; both records share the invocation’s argument
storage but advance independently.

**Check your explanation:** Record ownership differs from argument storage
ownership. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** sharing one mutable offset between va_copy results.
Copying traversal state makes later offsets independent.

### Solution G12-06 — Align wider overflow

The original question asks: A long-double overflow cursor is 0x1008. Give
address and next cursor.

Align to 0x1010 and consume sixteen bytes, giving next 0x1020.

**Check your explanation:** X87 transport uses sixteen-byte alignment and size.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** consuming the wider argument from an unaligned overflow
address. Align 0x1008 upward to sixteen before adding a sixteen-byte long-double
extent.

### Solution G12-07 — Bound aggregate support

The original question asks: Does a named record’s effect on va_start imply
unnamed aggregate va_arg?

Named planning alone does not imply retrieval. At this pin a separate 131
provider supplies it: all INTEGER chunks must fit remaining GP slots, otherwise
the whole record uses aligned overflow. Floating-member records still reject.

**Check your explanation:** Separate named planning from tail retrieval. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** generalizing scalar cursors to every aggregate type. A
later fixed-signature aggregate planner does not add aggregate va_arg.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G12-01 — Locate fields

Its array declaration adjusts to a pointer to the record, not a record copy.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G12-02 — Walk mixed classes

FP first becomes 64; GP still starts at eight for the int. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G12-03 — Exhaust one bank

Now double uses overflow at O+8 and advances it to O+16. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G12-04 — Apply promotions

Use its promoted integer type, rather than treating byte storage width as the
ABI slot width. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G12-05 — Copy the cursor

A copied cursor does not extend that storage’s lifetime. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G12-06 — Align wider overflow

No padding is needed; next is still 0x1020. Accept an explanation that follows
the changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G12-07 — Bound aggregate support

Size alone does not determine class. An admitted two-eightbyte INTEGER record
uses two consecutive GP slots only if both fit; otherwise it uses overflow. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/12-variadic-cursors-and-argument-classes.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
