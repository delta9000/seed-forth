# G21: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/21-a-freestanding-gcc-driver-toolchain.md#try-the-mechanism).
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

### G21-01 changed — Separate search policies

Use the model in G21-01: Does -B automatically replace executable
DEFAULT_ASSEMBLER?

Change the premise: Only cc1 needs locating. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G21-02 changed — Retain copied ancestry

Use the model in G21-02: Why hash-check stage-B outputs before installing as/ld?

Change the premise: Installed as is later replaced. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G21-03 changed — Interpret the fixture

Use the model in G21-03: What do two printed lines and status 42 establish?

Change the premise: Only status 42 is captured. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

### G21-04 changed — Trace production

Use the model in G21-04: Where does host as in the report-only oracle enter the
chain?

Change the premise: Its .text matches. What follows under this changed premise?
State the result or remaining obligation and explain which original reasoning
still applies. Keep the other supplied contracts.

### G21-05 changed — Move a tool directory

Use the model in G21-05: Can copying WORK/toolchain elsewhere guarantee the same
assembler selection?

Change the premise: The new directory still contains gcc and cc1. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G21-06 changed — Bound hosted claims

Use the model in G21-06: Why does the no-header fixture not establish a musl
sysroot?

Change the premise: A later hello includes stdio and uses default libraries.
What follows under this changed premise? State the result or remaining
obligation and explain which original reasoning still applies. Keep the other
supplied contracts.

### G21-07 changed — Name execution evidence

Use the model in G21-07: May verbose tool names be called successful execve
traces?

Change the premise: Tracing is unavailable. What follows under this changed
premise? State the result or remaining obligation and explain which original
reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G21-01

1. Search rules differ by tool.
2. Read actual executable selection before compiler output.
3. Compiler-prefix search and configured as/ld paths have distinct roles.

### Hints for G21-02

1. A path is not an artifact digest.
2. Compare copied bytes to their stage-B record.
3. A matching digest identifies which installed producer artifact was copied.

### Hints for G21-03

1. Program behavior has more than one output channel.
2. Keep the supplied entry and exit contract small.
3. A no-libc executable does not request hosted startup or stdio.

### Hints for G21-04

1. Follow which bytes are consumed by production linking.
2. Locate the host assembler’s report-only output.
3. An oracle object is not the source-built production object.

### Hints for G21-05

1. Distinguish file movement from configured path inputs.
2. Read embedded absolute defaults with the moved tree.
3. Moving files need not change the driver’s configured assembler path.

### Hints for G21-06

1. Input omission cannot prove an untested dependency.
2. Read include-search configuration separately from sysroot contents.
3. A configured path can remain unpopulated at this boundary.

### Hints for G21-07

1. Use the actual observation method’s name.
2. Distinguish a printed command from an observed system call.
3. Only retained tracing can establish the actual execve claim.

## Worked solutions

### Solution G21-01 — Separate search policies

The original question asks: Does -B automatically replace executable
DEFAULT_ASSEMBLER?

No. The recorded absolute assembler default is preferred; --with-binutils must
configure it correctly.

**Check your explanation:** Search rules differ by tool. A matching final answer
without that reason leaves the mechanism uncertain. If your answer differs,
compare the supplied premises first, then locate the first transition at which
your model departs from the chapter.

**Common wrong path:** assuming every familiar tool name resolves through the
same search path. Compiler-prefix search and configured as/ld paths have
distinct roles.

### Solution G21-02 — Retain copied ancestry

The original question asks: Why hash-check stage-B outputs before installing
as/ld?

To identify actual copied producer bytes, rather than treating tool names as
proof of source-built origin.

**Check your explanation:** A path is not an artifact digest. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** trusting a new file solely because it was renamed as or
ld. A matching digest identifies which installed producer artifact was copied.

### Solution G21-03 — Interpret the fixture

The original question asks: What do two printed lines and status 42 establish?

The named fixture’s captured output/status under the selected chain, conditional
on its actual run record.

**Check your explanation:** Program behavior has more than one output channel. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** claiming libc closure from the freestanding fixture. A
no-libc executable does not request hosted startup or stdio.

### Solution G21-04 — Trace production

The original question asks: Where does host as in the report-only oracle enter
the chain?

It independently assembles the same assembly for comparison; its objects do not
feed production.

**Check your explanation:** Follow which bytes are consumed by production
linking. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** substituting host as after a text comparison. An oracle
object is not the source-built production object.

### Solution G21-05 — Move a tool directory

The original question asks: Can copying WORK/toolchain elsewhere guarantee the
same assembler selection?

No. Embedded absolute defaults remain tied to WORK.

**Check your explanation:** Distinguish file movement from configured path
inputs. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** assuming all tool resolution relocates with a copied
directory. Moving files need not change the driver’s configured assembler path.

### Solution G21-06 — Bound hosted claims

The original question asks: Why does the no-header fixture not establish a musl
sysroot?

It uses no target headers and omits default libraries/startfiles; host system
include paths remain in the first driver.

**Check your explanation:** Input omission cannot prove an untested dependency.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** assuming a working driver already has target headers and
libraries. A configured path can remain unpopulated at this boundary.

### Solution G21-07 — Name execution evidence

The original question asks: May verbose tool names be called successful execve
traces?

Only actual retained tracing establishes that syscall evidence. Verbose output
has its own narrower status.

**Check your explanation:** Use the actual observation method’s name. A matching
final answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** describing verbose driver text as a successful execution
trace. Only retained tracing can establish the actual execve claim.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G21-01 — Separate search policies

The -B prefix can select the flat cc1 search fallback. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G21-02 — Retain copied ancestry

Its current identity must be verified again before the original lineage claim
applies. Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G21-03 — Interpret the fixture

Output acceptance and producer provenance remain separate missing evidence.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

### Check G21-04 — Trace production

That is section-scoped equality, not whole-object identity or universal
assembler correctness. Accept an explanation that follows the changed premise
and retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G21-05 — Move a tool directory

Those names do not rewrite DEFAULT_ASSEMBLER/LINKER. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G21-06 — Bound hosted claims

That requires G22’s separately identified target headers/runtime closure. Accept
an explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G21-07 — Name execution evidence

Retain that limit and the available verbose/guard checks; do not invent a trace.
Accept an explanation that follows the changed premise and retains the
unmodified contracts. Do not accept a new execution claim merely because the
paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/21-a-freestanding-gcc-driver-toolchain.md) and its stated
illustrative inputs. The numerical states are derivations; any historical result
remains attributed to its repository account. No exercise, generated instruction
or build was executed to create these answers.
