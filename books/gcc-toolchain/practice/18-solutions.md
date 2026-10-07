# G18: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/18-source-generators-must-have-builders.md#try-the-mechanism).
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

### G18-01 changed — Name both products

Use the model in G18-01: What produces tree-check.h in the gencheck story?

Change the premise: An expected string lives in Python memory. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G18-02 changed — Trace the chain

Use the model in G18-02: Name the executable that generates Heirloom’s parser.

Change the premise: Name the producer of final flex scan.c. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G18-03 changed — Keep the temporary scope

Use the model in G18-03: Why is scan.lex.l not a claim of complete scanner
equivalence?

Change the premise: The temporary tool runs successfully. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G18-04 changed — Retain an adaptation

Use the model in G18-04: What must accompany the U+0160 comment transliteration?

Change the premise: A patch applies with an offset but zero fuzz. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G18-05 changed — Separate generation and comparison

Use the model in G18-05: Does the host genmodes oracle’s output feed the Forth
build?

Change the premise: Marker coverage succeeds but byte comparison fails. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

### G18-06 changed — Bound a library proof

Use the model in G18-06: Why do five selected libiberty members not establish
complete libiberty?

Change the premise: The complete census later builds the library. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G18-07 changed — Attribute a result

Use the model in G18-07: May the three documented genmodes sizes be described as
measured in this chapter?

Change the premise: A reader derives the same expected output shape. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G18-01

1. Distinguish executable stdout from expected bytes.
2. Name the executable that writes the generated header.
3. gencheck-direct runs and its stdout becomes production text.

### Hints for G18-02

1. Each generated C file needs an executable parent.
2. Follow parser.y into the identified yacc invocation.
3. The Forth-built oyacc makes parser.c before that C is compiled.

### Hints for G18-03

1. A bootstrap bridge has an explicit replacement point.
2. Locate the temporary scanner’s replacement event.
3. The restricted lex adaptation serves flex-tmp, which then generates flex’s own scanner.

### Hints for G18-04

1. Preparation is an identified producer step.
2. Retain the one-letter transformation and both identities.
3. The comment transliteration has explicit hashes, rationale and license provenance.

### Hints for G18-05

1. Coverage and byte equality are different predicates.
2. Trace the output consumed by the next production step.
3. Oracle equality does not decide production ancestry by itself.

### Hints for G18-06

1. Name the exact archive member set.
2. State the finite set that closes the named generator.
3. Five selected libiberty members do not represent the whole library.

### Hints for G18-07

1. Use the evidence label that matches the action.
2. Identify the existing record’s provenance.
3. The documented sizes are attributed results rather than measurements made for this chapter.

## Worked solutions

### Solution G18-01 — Name both products

The original question asks: What produces tree-check.h in the gencheck story?

The Forth-built gencheck-direct executable runs with its selected
generated/configured inputs. Its stdout is production text.

**Check your explanation:** Distinguish executable stdout from expected bytes. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** calling the compiler of gencheck the immediate producer
of its stdout. gencheck-direct runs and its stdout becomes production text.

### Solution G18-02 — Trace the chain

The original question asks: Name the executable that generates Heirloom’s
parser.

The Forth-built oyacc, consuming parser.y before Forth compiles parser.c.

**Check your explanation:** Each generated C file needs an executable parent. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** leaving a generated parser’s executable producer unnamed.
The Forth-built oyacc makes parser.c before that C is compiled.

### Solution G18-03 — Keep the temporary scope

The original question asks: Why is scan.lex.l not a claim of complete scanner
equivalence?

It is a restricted adaptation solely for the temporary build; flex-tmp replaces
its result with flex’s own generated scanner.

**Check your explanation:** A bootstrap bridge has an explicit replacement
point. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** claiming unrestricted scanner equivalence from the
temporary adaptation. The restricted lex adaptation serves flex-tmp, which then
generates flex’s own scanner.

### Solution G18-04 — Retain an adaptation

The original question asks: What must accompany the U+0160 comment
transliteration?

Original/adapted hashes, exact one-letter change, rationale, provenance and
retained license notice.

**Check your explanation:** Preparation is an identified producer step. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** describing adapted source as untouched release bytes. The
comment transliteration has explicit hashes, rationale and license provenance.

### Solution G18-05 — Separate generation and comparison

The original question asks: Does the host genmodes oracle’s output feed the
Forth build?

No. It compares complete outputs independently; production retains the
Forth-built generator’s text.

**Check your explanation:** Coverage and byte equality are different predicates.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** substituting host-generated output after it matches.
Oracle equality does not decide production ancestry by itself.

### Solution G18-06 — Bound a library proof

The original question asks: Why do five selected libiberty members not establish
complete libiberty?

They close the named genmodes link, while the remaining full library units have
their own build outcomes.

**Check your explanation:** Name the exact archive member set. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** calling a narrow link closure complete libiberty
coverage. Five selected libiberty members do not represent the whole library.

### Solution G18-07 — Attribute a result

The original question asks: May the three documented genmodes sizes be described
as measured in this chapter?

No. They are attributed pinned-source records; no generator ran for this new
manuscript.

**Check your explanation:** Use the evidence label that matches the action. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** presenting copied size numbers as a new generator
execution. The documented sizes are attributed results rather than measurements
made for this chapter.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G18-01 — Name both products

It is an output oracle, not a production generator. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G18-02 — Trace the chain

flex-tmp processes the patched original scan.l. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G18-03 — Keep the temporary scope

That establishes its bounded role, not all final scanner behavior. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G18-04 — Retain an adaptation

Keep exact patch bytes and command/output; offset is still part of the
preparation record. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G18-05 — Separate generation and comparison

Keep the differential failure; markers alone do not establish complete output
equality. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G18-06 — Bound a library proof

That is a distinct later evidence boundary with its own inputs and record.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G18-07 — Attribute a result

That supplies a derivation, not an observed size or fresh oracle run. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/18-source-generators-must-have-builders.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
