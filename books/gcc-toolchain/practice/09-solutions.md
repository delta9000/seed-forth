# G09: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/09-typed-constants-and-symbolic-addresses.md#try-the-mechanism).
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

### G9-01 changed — Wrap at the right time

Use the model in G9-01: Derive (0xffffffffU+2U)>2U in this profile.

Change the premise: Replace 2U in the comparison with 0U. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G9-02 changed — Retain rank

Use the model in G9-02: Why is equal long/long-long width insufficient to select
the common type?

Change the premise: Combine 1L and 1LL. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G9-03 changed — Scale an addend

Use the model in G9-03: Give the symbolic representation for items+2 when
elements are eight bytes.

Change the premise: Cast the symbolic pointer to long before adding two. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G9-04 changed — Reject two identities

Use the model in G9-04: Why not evaluate the difference of arbitrary independent
symbols as one current relocation?

Change the premise: Both declarations currently have parser IDs. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G9-05 changed — Keep the dead arm typed

Use the model in G9-05: What type/value follows from 1 ? -1 : 1U?

Change the premise: Use 1 || (1/0). What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G9-06 changed — Choose a static leaf

Use the model in G9-06: Where does object-mode initialization put a symbolic
pointer obligation?

Change the premise: A numeric four-byte int leaf is supplied. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G9-07 changed — Preserve a delimiter

Use the model in G9-07: Why restore the constant pool and leave the comma
pending?

Change the premise: A recursive sizeof contains an array-bound parse. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G9-01

1. Normalization precedes the next operator.
2. Use the operation’s unsigned-int width before comparing.
3. Normalize the addition, then evaluate the greater-than expression.

### Hints for G9-02

1. Compare rank as well as width and signedness.
2. Keep arithmetic rank alongside byte width.
3. Long and long long can occupy equal widths yet have different ranks.

### Hints for G9-03

1. Pointer arithmetic uses element size; integer arithmetic does not.
2. Name the pointed-to element before adding.
3. Multiply the index by the long element stride, retaining one symbol identity.

### Hints for G9-04

1. Identity is not placement.
2. Count symbol identities required by the expression.
3. One-symbol-plus-addend cannot represent arbitrary independent two-symbol subtraction.

### Hints for G9-05

1. Skipping arithmetic does not skip grammar or type checking.
2. Use both arms to select the common type.
3. Only the chosen value is evaluated, then it is converted to that common type.

### Hints for G9-06

1. Traversal and leaf action have different owners.
2. Locate the chosen initializer leaf consumer.
3. Object mode records a data relocation instead of scheduling a runtime store.

### Hints for G9-07

1. Name the enclosing consumer before advancing.
2. Identify the enclosing parser’s next token and watermark.
3. Public constant parsing restores private pool state and leaves the delimiter for its caller.

## Worked solutions

### Solution G9-01 — Wrap at the right time

The original question asks: Derive (0xffffffffU+2U)>2U in this profile.

Unsigned int addition normalizes to one before comparison, so the int result is
zero.

**Check your explanation:** Normalization precedes the next operator. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** postponing narrowing until a final store. Normalize the
addition, then evaluate the greater-than expression.

### Solution G9-02 — Retain rank

The original question asks: Why is equal long/long-long width insufficient to
select the common type?

Rank is retained separately; long long ranks above long even at equal width.

**Check your explanation:** Compare rank as well as width and signedness. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** using size equality as type equality. Long and long long
can occupy equal widths yet have different ranks.

### Solution G9-03 — Scale an addend

The original question asks: Give the symbolic representation for items+2 when
elements are eight bytes.

The items symbol plus addend sixteen; no final address is known.

**Check your explanation:** Pointer arithmetic uses element size; integer
arithmetic does not. A matching final answer without that reason leaves the
mechanism uncertain. If your answer differs, compare the supplied premises
first, then locate the first transition at which your model departs from the
chapter.

**Common wrong path:** adding a scalar index directly to a symbol record ID.
Multiply the index by the long element stride, retaining one symbol identity.

### Solution G9-04 — Reject two identities

The original question asks: Why not evaluate the difference of arbitrary
independent symbols as one current relocation?

The representation carries only one symbol plus an addend and lacks the
two-symbol expression needed.

**Check your explanation:** Identity is not placement. A matching final answer
without that reason leaves the mechanism uncertain. If your answer differs,
compare the supplied premises first, then locate the first transition at which
your model departs from the chapter.

**Common wrong path:** inventing a final distance before independent symbols
have been placed. One-symbol-plus-addend cannot represent arbitrary independent
two-symbol subtraction.

### Solution G9-05 — Keep the dead arm typed

The original question asks: What type/value follows from 1 ? -1 : 1U?

Both arms choose unsigned int; the selected −1 converts to its unsigned int
representation.

**Check your explanation:** Skipping arithmetic does not skip grammar or type
checking. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** retaining signed minus one merely because that arm was
chosen. Only the chosen value is evaluated, then it is converted to that common
type.

### Solution G9-06 — Choose a static leaf

The original question asks: Where does object-mode initialization put a symbolic
pointer obligation?

It records an absolute relocation on its data field, with symbol and addend. It
does not queue a native runtime store routine.

**Check your explanation:** Traversal and leaf action have different owners. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** turning shared 118 traversal into a private
initialization queue. Object mode records a data relocation instead of
scheduling a runtime store.

### Solution G9-07 — Preserve a delimiter

The original question asks: Why restore the constant pool and leave the comma
pending?

The enclosing declaration owns its separator and prior temporary watermark.
Consuming or retaining those states would corrupt later parsing.

**Check your explanation:** Name the enclosing consumer before advancing. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** consuming the enclosing comma or leaking temporary
records. Public constant parsing restores private pool state and leaves the
delimiter for its caller.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G9-01 — Wrap at the right time

One is greater than zero, so the int result becomes one. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G9-02 — Retain rank

The result type is long long under the common-type rules. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G9-03 — Scale an addend

The addend grows by two bytes instead; identity is preserved. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G9-04 — Reject two identities

Subtracting IDs is still meaningless as address arithmetic. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G9-05 — Keep the dead arm typed

It parses the discarded division without performing it and returns int one.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G9-06 — Choose a static leaf

It converts to int and patches its reserved data bytes directly. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G9-07 — Preserve a delimiter

The inner parse must restore its own temporary scope and return control without
spending the parent’s records. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/09-typed-constants-and-symbolic-addresses.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
