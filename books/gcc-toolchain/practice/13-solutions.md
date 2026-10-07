# G13: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/13-streams-and-bounded-formatting.md#try-the-mechanism).
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

### G13-01 changed — Count objects

Use the model in G13-01: Derive the fread result from replies 3,2,0 for size
four/count two.

Change the premise: The third reply is a negative error instead. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G13-02 changed — Distinguish sticky flags

Use the model in G13-02: Does successful I/O automatically erase every prior
error?

Change the premise: A successful fseek occurs. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G13-03 changed — Account for pushback

Use the model in G13-03: Kernel position ten with one pushed byte: what does
ftell report?

Change the premise: A relative seek of zero succeeds. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G13-04 changed — Separate count from storage

Use the model in G13-04: What follows from four-byte snprintf storage for ABCDE?

Change the premise: Use size zero. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G13-05 changed — Use the promoted argument

Use the model in G13-05: Why does an hh integer conversion not fetch a one-byte
variadic slot?

Change the premise: A star width is negative. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G13-06 changed — Reject unsupported formatting

Use the model in G13-06: May printf use %f merely because double arithmetic is
implemented?

Change the premise: A wide character value is 128. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G13-07 changed — Report an observed write

Use the model in G13-07: The formatter counted five bytes, but its stream write
failed after three. What should a record preserve?

Change the premise: No write was executed. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G13-01

1. Divide actual bytes by object size only at return.
2. Compute transferred bytes before complete objects.
3. Divide the five-byte progress by the four-byte object size for the reported count.

### Hints for G13-02

1. Read each operation’s state updates.
2. Identify the operation that clears the indicators.
3. Successful I/O need not erase a prior sticky error; clearerr explicitly clears both.

### Hints for G13-03

1. Logical position subtracts pending input.
2. Keep a pending byte alongside the descriptor offset.
3. A logical position includes pushback state the kernel offset cannot see.

### Hints for G13-04

1. Reserve one byte for the terminator.
2. Track attempted formatted length separately from stores.
3. Capacity four permits three data characters and a terminator.

### Hints for G13-05

1. Retrieval type precedes output narrowing.
2. Apply default promotion before formatting narrowing.
3. hh determines the output interpretation after fetching the promoted integer.

### Hints for G13-06

1. Language arithmetic and library formatting are separate providers.
2. Read the supported conversion cases.
3. The separate floatfmt provider supplies double/extended80 conversions at this pin.

### Hints for G13-07

1. Name request, progress and final status independently.
2. Record logical count and actual stream progress separately.
3. A write failing after three bytes does not deliver all five counted characters.

## Worked solutions

### Solution G13-01 — Count objects

The original question asks: Derive the fread result from replies 3,2,0 for size
four/count two.

Five bytes enter the buffer; one complete object is returned; zero sets EOF.

**Check your explanation:** Divide actual bytes by object size only at return. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** concluding only four destination bytes changed because
one object was returned. Divide the five-byte progress by the four-byte object
size for the reported count.

### Solution G13-02 — Distinguish sticky flags

The original question asks: Does successful I/O automatically erase every prior
error?

No. Error and EOF are explicit state; clearerr clears both, and operations have
their specified narrower effects.

**Check your explanation:** Read each operation’s state updates. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** using one success as proof every older stream indicator
was reset. Successful I/O need not erase a prior sticky error; clearerr
explicitly clears both.

### Solution G13-03 — Account for pushback

The original question asks: Kernel position ten with one pushed byte: what does
ftell report?

Nine; the descriptor has not actually moved backward.

**Check your explanation:** Logical position subtracts pending input. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** reporting only the descriptor offset after ungetc. A
logical position includes pushback state the kernel offset cannot see.

### Solution G13-04 — Separate count from storage

The original question asks: What follows from four-byte snprintf storage for
ABCDE?

Return five, store ABC plus NUL. Logical count differs from capacity and stored
prefix.

**Check your explanation:** Reserve one byte for the terminator. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** returning the truncated stored length instead of required
length. Capacity four permits three data characters and a terminator.

### Solution G13-05 — Use the promoted argument

The original question asks: Why does an hh integer conversion not fetch a
one-byte variadic slot?

The tail passed a promoted integer; the formatter fetches it first and then
narrows.

**Check your explanation:** Retrieval type precedes output narrowing. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** fetching a one-byte variadic slot that the caller never
supplied. hh determines the output interpretation after fetching the promoted
integer.

### Solution G13-06 — Reject unsupported formatting

The original question asks: May printf use %f merely because double arithmetic
is implemented?

Arithmetic alone is insufficient evidence, but this pin supplies a separate
exact floating formatter. %f takes a promoted double; %Lf takes long double.

**Check your explanation:** Language arithmetic and library formatting are
separate providers. A matching final answer without that reason leaves the
mechanism uncertain. If your answer differs, compare the supplied premises
first, then locate the first transition at which your model departs from the
chapter.

**Common wrong path:** using later hosted output to broaden seed printf support.
Both the seed formatter and later musl product supply floating output under
their respective contracts.

### Solution G13-07 — Report an observed write

The original question asks: The formatter counted five bytes, but its stream
write failed after three. What should a record preserve?

Logical/requested count, three-byte progress, failure status and sticky error
separately. Five counted bytes are not five observed output bytes.

**Check your explanation:** Name request, progress and final status
independently. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** calling a formatter’s required length observed output
progress. A write failing after three bytes does not deliver all five counted
characters.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G13-01 — Count objects

Five bytes and one complete object still precede the failure; error/errno are
set instead of EOF by that reply. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G13-02 — Distinguish sticky flags

It clears pushback and EOF, while sticky error is not automatically cleared.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G13-03 — Account for pushback

The kernel request accounts for the pushed byte, then pending pushback and EOF
are cleared. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G13-04 — Separate count from storage

No bytes are stored; supported length calculation still gives five. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G13-05 — Use the promoted argument

It consumes int and selects left justification with its positive magnitude,
except the checked INT_MIN boundary. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G13-06 — Reject unsupported formatting

Its ASCII-wide path rejects with EILSEQ. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G13-07 — Report an observed write

Only a paper prediction can be claimed; there is no measured stream output.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/13-streams-and-bounded-formatting.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
