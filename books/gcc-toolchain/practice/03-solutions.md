# G03: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/03-signatures-declarators-and-ranked-arrays.md#try-the-mechanism).
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

### G3-01 changed — Distinguish two lists

Use the model in G3-01: What does (void) promise that empty declaration
parentheses do not?

Change the premise: Compare two declarations that differ only in parameter
names. What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G3-02 changed — Derive a record

Use the model in G3-02: Derive mark/value offsets and size for the supplied
char/long pair.

Change the premise: Make the record a union. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G3-03 changed — Walk one row

Use the model in G3-03: For `long grid[2][3]`, derive row and whole sizes and
the stride of a decayed row pointer.

Change the premise: Use `grid[2][4]`. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G3-04 changed — Place the qualifier

Use the model in G3-04: Compare const long (*a)[3] and long (*const b)[3].

Change the premise: May implicit conversion discard const from a row? What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G3-05 changed — Restore the owner

Use the model in G3-05: An inner record declaration overwrites cc-nctx. What
must happen on return?

Change the premise: A field table moves but the descriptor header does not. What
else must move logically? What follows under this changed premise? State the
result or remaining obligation and explain which original reasoning still
applies. Keep the other supplied contracts.

### G3-06 changed — Choose the initializer producer

Use the model in G3-06: Why is using 118 on the direct route not evidence of
private TinyCC runtime initialization?

Change the premise: An inferred array is scanned before allocation. Why rewind?
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G3-07 changed — Locate a missing check

Use the model in G3-07: Two objects resolve answer by name but used different
result types. Which boundary must be repaired?

Change the premise: The two types occupy equal storage widths. Is that
sufficient? What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G3-01

1. Read count and prototype flags separately.
2. Compare the parameter-list forms rather than the names.
3. Distinguish explicitly zero parameters from an unspecified parameter list.

### Hints for G3-02

1. Align each struct field before adding its size.
2. Place char before aligning the long.
3. Round the long’s start to eight, then round the completed record extent.

### Hints for G3-03

1. The pointed-to object is a whole row.
2. Compute the inner array before the outer extent.
3. A decayed outer array points to a row, so use a row as its stride.

### Hints for G3-04

1. Ask what object the qualifier describes.
2. Place const on the layer named by the declaration.
3. Ask whether the pointer object or its pointed-to element is writable.

### Hints for G3-05

1. Separate context pointer, descriptor and field-table addresses.
2. Identify which parser state the mark restores.
3. Token position and allocated descriptor identity have different owners.

### Hints for G3-06

1. Keep traversal separate from scalar-leaf action.
2. Separate the shared traversal from its selected callback.
3. Object leaves write static bytes/relocations; the private queue has another completion event.

### Hints for G3-07

1. The linker has names and sections, not the original signatures.
2. Open the file interface the linker actually receives.
3. ELF symbol names and C signatures are not the same serialized metadata.

## Worked solutions

### Solution G3-01 — Distinguish two lists

The original question asks: What does (void) promise that empty declaration
parentheses do not?

It promises zero parameters. Empty declaration parentheses leave their
specification unknown; they do not encode a zero-parameter prototype.

**Check your explanation:** Read count and prototype flags separately. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** assuming empty declaration parentheses enforce the same
contract as void. Distinguish explicitly zero parameters from an unspecified
parameter list.

### Solution G3-02 — Derive a record

The original question asks: Derive mark/value offsets and size for the supplied
char/long pair.

mark is at zero, value at eight, total size sixteen, alignment eight. The seven
intervening bytes are padding.

**Check your explanation:** Align each struct field before adding its size. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** putting long at byte one and ignoring its alignment.
Round the long’s start to eight, then round the completed record extent.

### Solution G3-03 — Walk one row

The original question asks: For `long grid[2][3]`, derive row and whole sizes
and the stride of a decayed row pointer.

Row size is 24, whole size 48 and pointer stride 24. Each long remains eight
bytes.

**Check your explanation:** The pointed-to object is a whole row. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** using eight-byte pointer storage as the stride of every
pointed-to type. A decayed outer array points to a row, so use a row as its
stride.

### Solution G3-04 — Place the qualifier

The original question asks: Compare const long (*a)[3] and long (*const b)[3].

a points to const rows; b is a const pointer object pointing to unqualified
rows. Their qualifiers belong to different constructors.

**Check your explanation:** Ask what object the qualifier describes. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** flattening all qualifiers into one flag on the whole
declaration. Ask whether the pointer object or its pointed-to element is
writable.

### Solution G3-05 — Restore the owner

The original question asks: An inner record declaration overwrites cc-nctx. What
must happen on return?

Restore the enclosing context so its name, type, dimensions and storage policy
remain the outer declaration’s. Reader restoration alone is insufficient.

**Check your explanation:** Separate context pointer, descriptor and field-table
addresses. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** expecting lexer rewind to undo every compiler allocation.
Token position and allocated descriptor identity have different owners.

### Solution G3-06 — Choose the initializer producer

The original question asks: Why is using 118 on the direct route not evidence of
private TinyCC runtime initialization?

Its shared recursive traversal is reused under selected callbacks. Object-mode
static leaves patch data/relocations; the private queue is a different consumer.

**Check your explanation:** Keep traversal separate from scalar-leaf action. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** attributing queued initialization to every user of 118.
Object leaves write static bytes/relocations; the private queue has another
completion event.

### Solution G3-07 — Locate a missing check

The original question asks: Two objects resolve answer by name but used
different result types. Which boundary must be repaired?

The source declarations and their object compilations must agree. Name
resolution does not compare cross-file signatures or guarantee the returned
value.

**Check your explanation:** The linker has names and sections, not the original
signatures. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** expecting a successful name match to verify two C
interfaces. ELF symbol names and C signatures are not the same serialized
metadata.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G3-01 — Distinguish two lists

Names alone do not change the retained parameter types or count. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G3-02 — Derive a record

Both fields begin at zero; size and alignment are eight under the supplied
natural-layout rules. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G3-03 — Walk one row

Row and stride become 32, full size 64. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G3-04 — Place the qualifier

No; the selected qualifier check rejects that loss without an explicit permitted
cast. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G3-05 — Restore the owner

Qualification entries keyed by field-record addresses must be re-keyed to the
new records. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G3-06 — Choose the initializer producer

The second pass must initialize from the original tokens after the first pass
computed its extent. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G3-07 — Locate a missing check

No. Equal width does not establish compatible type identity, rank or calling
semantics. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/03-signatures-declarators-and-ranked-arrays.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
