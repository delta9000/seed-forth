# G25: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/25-fixed-point-evidence-and-toolchain-capstone.md#try-the-mechanism).
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

### G25-01 changed — State the domain

Use the model in G25-01: Which files are compared before examining content?

Change the premise: Only gcc/cc1/collect2 hashes are available. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G25-02 changed — Compare an archive

Use the model in G25-02: Container hashes differ but ordered names/member hashes
agree. What does the script conclude?

Change the premise: Member order changes. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G25-03 changed — Require stage 2

Use the model in G25-03: Stages 3/4 agree, but 2/3 differ in cc1. Does Stage D
pass?

Change the premise: All required differences are absent. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G25-04 changed — Name producer ancestry

Use the model in G25-04: Give the immediate producers of first GCC, libgcc and
stage 3.

Change the premise: Add host gcc used for torture linking. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G25-05 changed — Keep source transformations

Use the model in G25-05: Why retain YYBYACC and scanner adaptations in the final
account?

Change the premise: The complete source hash mapping is equal. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G25-06 changed — Bound the archive reader

Use the model in G25-06: Does ar p by member name prove universal handling of
duplicate archive names?

Change the premise: All intended member names are unique and whitespace-free.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G25-07 changed — Close the capstone honestly

Use the model in G25-07: What remains after the recorded fixed point?

Change the premise: A new reader correctly solves the paper capstone. What
follows under this changed premise? State the result or remaining obligation and
explain which original reasoning still applies. Keep the other supplied
contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G25-01

1. Inventory agreement precedes content agreement.
2. Compare path inventories before common contents.
3. A missing installed file matters even when all common hashes agree.

### Hints for G25-02

1. Use the implemented view, not an invented normalization.
2. Read the archive fallback’s ordered representation.
3. Equal member contents can be accepted with unequal whole-container digests.

### Hints for G25-03

1. Check every required pair.
2. Check every required generation edge.
3. A single final adjacent match cannot erase an earlier required difference.

### Hints for G25-04

1. Follow production-consumed artifacts separately.
2. Trace consumed artifacts rather than useful diagnostics.
3. First GCC, libgcc and later generations have different immediate producers.

### Hints for G25-05

1. Inputs include preparation history and exact resulting bytes.
2. Retain preparations as actual source inputs.
3. The final graph includes scanner/parser transformations with identified resulting bytes.

### Hints for G25-06

1. Inspect how extraction identifies members.
2. Inspect how ar p identifies the extracted member.
3. Name-based extraction needs the intended naming assumptions.

### Hints for G25-07

1. Different achievements require different observations.
2. Give each outcome its own observation.
3. Paper learning, fresh rebuilding and direct-chain Linux boot are separate achievements.

## Worked solutions

### Solution G25-01 — State the domain

The original question asks: Which files are compared before examining content?

All file relative paths in each installed tree; missing-path sets are reported
along with common-file differences.

**Check your explanation:** Inventory agreement precedes content agreement. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** checking only three selected executable hashes. A missing
installed file matters even when all common hashes agree.

### Solution G25-02 — Compare an archive

The original question asks: Container hashes differ but ordered names/member
hashes agree. What does the script conclude?

It accepts the archive under its member-content fallback, without claiming equal
container bytes.

**Check your explanation:** Use the implemented view, not an invented
normalization. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** calling the accepted archives identical raw files. Equal
member contents can be accepted with unequal whole-container digests.

### Solution G25-03 — Require stage 2

The original question asks: Stages 3/4 agree, but 2/3 differ in cc1. Does Stage
D pass?

No. Both adjacent comparisons must have no missing or differing files.

**Check your explanation:** Check every required pair. A matching final answer
without that reason leaves the mechanism uncertain. If your answer differs,
compare the supplied premises first, then locate the first transition at which
your model departs from the chapter.

**Common wrong path:** accepting stage 3/4 while ignoring stage 2/3. A single
final adjacent match cannot erase an earlier required difference.

### Solution G25-04 — Name producer ancestry

The original question asks: Give the immediate producers of first GCC, libgcc
and stage 3.

Forth builds first GCC; that GCC builds libgcc; stage 2 builds stage 3.

**Check your explanation:** Follow production-consumed artifacts separately. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** adding a host oracle to production ancestry without
consumed bytes. First GCC, libgcc and later generations have different immediate
producers.

### Solution G25-05 — Keep source transformations

The original question asks: Why retain YYBYACC and scanner adaptations in the
final account?

They are actual prepared input differences with checked provenance, not
invisible consequences of “source built.”

**Check your explanation:** Inputs include preparation history and exact
resulting bytes. A matching final answer without that reason leaves the
mechanism uncertain. If your answer differs, compare the supplied premises
first, then locate the first transition at which your model departs from the
chapter.

**Common wrong path:** listing only pristine archives while omitting consumed
adaptations. The final graph includes scanner/parser transformations with
identified resulting bytes.

### Solution G25-06 — Bound the archive reader

The original question asks: Does ar p by member name prove universal handling of
duplicate archive names?

No. The implemented name-based view has assumptions; intended generated
libraries are its bounded domain.

**Check your explanation:** Inspect how extraction identifies members. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** claiming universal duplicate-name archive validation.
Name-based extraction needs the intended naming assumptions.

### Solution G25-07 — Close the capstone honestly

The original question asks: What remains after the recorded fixed point?

Fresh reproduction and reader validation, broader semantic/compiler-trust
questions, orchestration/platform dependencies and the separate direct-GCC
kernel/boot obligation.

**Check your explanation:** Different achievements require different
observations. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** using a toolchain comparison to close the unobserved
kernel continuation. Paper learning, fresh rebuilding and direct-chain Linux
boot are separate achievements.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G25-01 — State the domain

Those are useful selected identities but insufficient for the full
installed-tree predicate. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G25-02 — Compare an archive

The ordered pairs differ and the fallback fails. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G25-03 — Require stage 2

The predicate passes under its declared file/member scope, not universal
semantic correctness. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G25-04 — Name producer ancestry

It belongs to the explicit test chain, not production GCC ancestry. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G25-05 — Keep source transformations

That strengthens input identity but does not eliminate the need to name
transformations. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G25-06 — Bound the archive reader

That removes the relevant ambiguity for this supplied comparison, without
broadening to every archive. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G25-07 — Close the capstone honestly

That is a learning attempt, not a fresh toolchain build or Linux boot. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/25-fixed-point-evidence-and-toolchain-capstone.md) and
its stated illustrative inputs. The numerical states are derivations; any
historical result remains attributed to its repository account. No exercise,
generated instruction or build was executed to create these answers.
