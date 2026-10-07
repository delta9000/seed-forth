# G20: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/20-building-the-downstream-binutils.md#try-the-mechanism).
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

### G20-01 changed — Name the two linkers

Use the model in G20-01: Who produces ld-new and who later uses it?

Change the premise: 140 is present during compilation. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G20-02 changed — Find the parser producer

Use the model in G20-02: A release ships parser C but the view omits it. What
must remain?

Change the premise: A hand-written header exists near the parser. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G20-03 changed — Read make continuation

Use the model in G20-03: Does make -k turn failed units into successes?

Change the premise: All objects exist but ld-new is missing. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G20-04 changed — Check jobs

Use the model in G20-04: May the book promise a binutils -j8 invocation under
this parser?

Change the premise: Use -j6. What follows under this changed premise? State the
result or remaining obligation and explain which original reasoning still
applies. Keep the other supplied contracts.

### G20-05 changed — Preserve diagnostics

Use the model in G20-05: What is lost if only a grouped diagnostic count is
retained?

Change the premise: Two failures have the same normalized text. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G20-06 changed — Identify outputs

Use the model in G20-06: Name the six requested binutils outputs.

Change the premise: Configure succeeds without any outputs. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G20-07 changed — Keep chronology

Use the model in G20-07: How should the early “links in progress” paragraph
relate to the later driver recipe?

Change the premise: No new run was performed for the book. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G20-01

1. Separate executable production from later consumption.
2. Name the earlier bounded linker and later binutils linker.
3. One produces ld-new; the other later consumes GCC output.

### Hints for G20-02

1. Omission must expose an actual dependency edge.
2. Preserve descriptions and real generator rules.
3. Omitting shipped parser C leaves a source-built regeneration obligation.

### Hints for G20-03

1. Object production does not replace final link.
2. Read keep-going as scheduling policy.
3. A missing final tool is still a failed output even if other units completed.

### Hints for G20-04

1. Read the actual command parser.
2. Inspect the script’s admitted integer range.
3. A historical command can differ from the current parser gate.

### Hints for G20-05

1. Aggregation is a view over retained evidence.
2. Keep normalized groups linked to raw traces.
3. Equal messages can come from distinct units and invocations.

### Hints for G20-06

1. The requested executables are the acceptance boundary.
2. List final executable paths rather than component objects.
3. The stage requires six named tools after linking.

### Hints for G20-07

1. Name the time and boundary of each claim.
2. Order the records by their actual milestones.
3. An early incomplete account and a later completed recipe describe successive states.

## Worked solutions

### Solution G20-01 — Name the two linkers

The original question asks: Who produces ld-new and who later uses it?

The Forth linker produces the binutils ld-new executable from Forth-compiled
objects; GCC’s later output chain uses that executable to link its objects.

**Check your explanation:** Separate executable production from later
consumption. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** merging two executable generations under the word linker.
One produces ld-new; the other later consumes GCC output.

### Solution G20-02 — Find the parser producer

The original question asks: A release ships parser C but the view omits it. What
must remain?

The descriptions and required Forth-built oyacc/flex producer rules, with
retained view provenance.

**Check your explanation:** Omission must expose an actual dependency edge. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** deleting generated files without supplying their
producers. Omitting shipped parser C leaves a source-built regeneration
obligation.

### Solution G20-03 — Read make continuation

The original question asks: Does make -k turn failed units into successes?

No. It continues independent work so the census can retain multiple successes
and failures.

**Check your explanation:** Object production does not replace final link. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** treating continued make work as repair of a failed unit.
A missing final tool is still a failed output even if other units completed.

### Solution G20-04 — Check jobs

The original question asks: May the book promise a binutils -j8 invocation under
this parser?

No. Its accepted range is 1–6; the older example is not an executed validation
card.

**Check your explanation:** Read the actual command parser. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** copying an old job count without checking admission. A
historical command can differ from the current parser gate.

### Solution G20-05 — Preserve diagnostics

The original question asks: What is lost if only a grouped diagnostic count is
retained?

Unit, concrete arguments, source/configuration context and exact failure phase
can be lost. Keep the original traces alongside grouping.

**Check your explanation:** Aggregation is a view over retained evidence. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** throwing away the unit identities once counts are
grouped. Equal messages can come from distinct units and invocations.

### Solution G20-06 — Identify outputs

The original question asks: Name the six requested binutils outputs.

as-new, ld-new, ar, nm-new, objdump and readelf in their named gas/ld/binutils
directories.

**Check your explanation:** The requested executables are the acceptance
boundary. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** declaring completion from configure or object-file
presence. The stage requires six named tools after linking.

### Solution G20-07 — Keep chronology

The original question asks: How should the early “links in progress” paragraph
relate to the later driver recipe?

As an earlier milestone with retained limits, followed by a later boundary
requiring complete verified tools.

**Check your explanation:** Name the time and boundary of each claim. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** flattening chronology into contradictory simultaneous
claims. An early incomplete account and a later completed recipe describe
successive states.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G20-01 — Name the two linkers

Its presence does not mean the later GCC driver invokes 140 instead of installed
ld. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G20-02 — Find the parser producer

It remains; source-view removal targets generated artifacts, not all nearby
headers. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G20-03 — Read make continuation

The required executable boundary is incomplete and the recipe fails. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G20-04 — Check jobs

That is within the admitted range, with success still unobserved here. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G20-05 — Preserve diagnostics

They remain distinct attempted units. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G20-06 — Identify outputs

It establishes only that script exit, not downstream tool production. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G20-07 — Keep chronology

Both remain source-attributed accounts, not fresh observations. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/20-building-the-downstream-binutils.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
