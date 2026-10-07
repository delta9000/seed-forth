# G08: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/08-target-headers-and-honest-feature-probes.md#try-the-mechanism).
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

### G8-01 changed — Classify a macro

Use the model in G8-01: What do LP64, __STDC__ and __SEED_FORTH__ each identify?

Change the premise: Add a hypothetical __GNUC__ define only to pass a probe.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G8-02 changed — Follow include order

Use the model in G8-02: Where does the driver’s runtime directory sit relative
to explicit -I directories?

Change the premise: Use -nostdinc. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G8-03 changed — Separate declaration and body

Use the model in G8-03: A header-only probe accepts a function declaration. Has
that function been linked?

Change the premise: A link probe succeeds too. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G8-04 changed — Read the rejected flag

Use the model in G8-04: Why may configure’s -g failure coexist with a successful
build using empty CFLAGS?

Change the premise: The transcript shows -g accepted with no debug
implementation. What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

### G8-05 changed — Keep location coordinates

Use the model in G8-05: A #line filename changes. Does relative include lookup
follow that displayed name?

Change the premise: A header macro is invoked in the parent file. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G8-06 changed — Retain negative evidence

Use the model in G8-06: Configure exits zero but some guarded tool attempts
failed. May the failures be omitted?

Change the premise: The same configuration is reused without rerunning probes.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G8-07 changed — Name the runtime

Use the model in G8-07: Why can the host’s FILE object not be passed to this
runtime’s stdio?

Change the premise: Both libraries use eight-byte pointers. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G8-01

1. Match each name to a narrow contract.
2. Separate data-model, branch and producer identities.
3. An identity macro selects a contract; it does not prove every semantic behavior.

### Hints for G8-02

1. A search option changes paths, not preprocessing existence.
2. List quoted, explicit and runtime search candidates in order.
3. The physical including directory precedes explicit -I; the runtime include follows explicit directories.

### Hints for G8-03

1. Identify whether the probe compiled, linked or ran.
2. Locate the operation that the probe reached.
3. A declaration can be parsed without object implementation or linking.

### Hints for G8-04

1. Keep probe answers separate from make overrides.
2. Check option admission before diagnosing language syntax.
3. Empty supported build flags can avoid a hardcoded unsupported debug flag honestly.

### Hints for G8-05

1. Separate opened path, logical location and flattened diagnostics.
2. Keep displayed and opened filenames separately.
3. The physical path remains the owner for relative include lookup.

### Hints for G8-06

1. A copied answer does not acquire a new producer.
2. Read the retained failed attempts alongside final status.
3. Configure can continue after provisional probes, so zero final status does not erase their failures.

### Hints for G8-07

1. A declaration names the selected ABI and implementation.
2. Ask which runtime owns the stream representation.
3. Opaque FILE declarations do not make host and source-built stream objects interchangeable.

## Worked solutions

### Solution G8-01 — Classify a macro

The original question asks: What do LP64, __STDC__ and __SEED_FORTH__ each
identify?

LP64 identifies the data model; __STDC__ selects the supported
prototype-oriented branch; __SEED_FORTH__ identifies this producer. None alone
certifies all semantics.

**Check your explanation:** Match each name to a narrow contract. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** reading LP64 as complete C implementation certification.
An identity macro selects a contract; it does not prove every semantic behavior.

### Solution G8-02 — Follow include order

The original question asks: Where does the driver’s runtime directory sit
relative to explicit -I directories?

It follows them. Quoted includes also try the including file’s physical
directory first.

**Check your explanation:** A search option changes paths, not preprocessing
existence. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** letting the logical #line filename become the include
owner. The physical including directory precedes explicit -I; the runtime
include follows explicit directories.

### Solution G8-03 — Separate declaration and body

The original question asks: A header-only probe accepts a function declaration.
Has that function been linked?

No. Parsing a declaration supplies type information without a body or completed
executable.

**Check your explanation:** Identify whether the probe compiled, linked or ran.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** crediting a header-only parse as a linked function body.
A declaration can be parsed without object implementation or linking.

### Solution G8-04 — Read the rejected flag

The original question asks: Why may configure’s -g failure coexist with a
successful build using empty CFLAGS?

The compiler rejects unsupported debug output honestly; the recipe overrides the
Makefile’s hardcoded flag with supported empty flags.

**Check your explanation:** Keep probe answers separate from make overrides. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** claiming debug support merely because the later
empty-flags build succeeds. Empty supported build flags can avoid a hardcoded
unsupported debug flag honestly.

### Solution G8-05 — Keep location coordinates

The original question asks: A #line filename changes. Does relative include
lookup follow that displayed name?

No. Logical display location changes while physical opened paths remain the
include-search owners.

**Check your explanation:** Separate opened path, logical location and flattened
diagnostics. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** searching beside a displayed #line name rather than the
physical input. The physical path remains the owner for relative include lookup.

### Solution G8-06 — Retain negative evidence

The original question asks: Configure exits zero but some guarded tool attempts
failed. May the failures be omitted?

No. Success is provisional; retained traces identify actual questions, failed
attempts and consumers of computed answers.

**Check your explanation:** A copied answer does not acquire a new producer. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** deleting failed-probe traces once configure exits zero.
Configure can continue after provisional probes, so zero final status does not
erase their failures.

### Solution G8-07 — Name the runtime

The original question asks: Why can the host’s FILE object not be passed to this
runtime’s stdio?

FILE is opaque and the source-built runtime has its own representation and
ownership. Matching function names do not grant object-layout compatibility.

**Check your explanation:** A declaration names the selected ABI and
implementation. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** passing a host FILE object into another runtime based on
matching function names. Opaque FILE declarations do not make host and
source-built stream objects interchangeable.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G8-01 — Classify a macro

That falsely advertises compatibility and can select unsupported branches; it is
not the recorded policy. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G8-02 — Follow include order

The default runtime directory is removed; preprocessing and explicit directories
remain. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G8-03 — Separate declaration and body

It establishes its selected symbol closure, still not the function’s executed
semantics. Accept an explanation that follows the changed premise and retains
the unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G8-04 — Read the rejected flag

That would contradict the stated driver contract and must not be treated as the
recorded probe policy. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G8-05 — Keep location coordinates

Its dynamic location follows the supported invocation/argument rules, not
necessarily the macro-definition line. Accept an explanation that follows the
changed premise and retains the unmodified contracts. Do not accept a new
execution claim merely because the paper result is consistent.

### Check G8-06 — Retain negative evidence

Its original configuration compiler remains the producer of those answers.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G8-07 — Name the runtime

Pointer width does not establish pointed-to representation compatibility. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/08-target-headers-and-honest-feature-probes.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
