# G06: hints, solutions, and changed checks

Start with the [chapter
problems](../chapters/06-raw-syscalls-startup-and-runtime-control.md#try-the-mechanism).
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

### G6-01 changed — Map the bridge

Use the model in G6-01: Where does C input a6 arrive, and where must Linux
receive it?

Change the premise: Name the registers SYSCALL clobbers. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G6-02 changed — Translate an error

Use the model in G6-02: A wrapper receives raw −2. What does the raw leaf do to
errno? What may the wrapper do?

Change the premise: A successful mapping follows an earlier error. Must errno
become zero? What follows under this changed premise? State the result or
remaining obligation and explain which original reasoning still applies. Keep
the other supplied contracts.

### G6-03 changed — Keep startups separate

Use the model in G6-03: Name the producer and role of start.o and startup.o.

Change the premise: Select the raw 32-byte startup builder. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G6-04 changed — Preserve arguments

Use the model in G6-04: Why push argc and argv after aligning in the
runtime-aware startup?

Change the premise: Push only one of the pair before that call. What follows
under this changed premise? State the result or remaining obligation and explain
which original reasoning still applies. Keep the other supplied contracts.

### G6-05 changed — Query a stable frame

Use the model in G6-05: Why can a parent-frame metric survive temporary argument
pushes?

Change the premise: Use a caller without that frame chain. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G6-06 changed — Normalize nonlocal return

Use the model in G6-06: What does longjmp(buffer,0) make the saved setjmp
return?

Change the premise: Use a supplied nonzero int −3. What follows under this
changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

### G6-07 changed — State what is saved

Use the model in G6-07: Does the eight-word buffer restore signal masks or
revive returned frames?

Change the premise: A signal-return leaf adds a prologue. What follows under
this changed premise? State the result or remaining obligation and explain which
original reasoning still applies. Keep the other supplied contracts.

## Graduated hints

Use one hint at a time. The first names the idea, the second locates the
boundary, and the third supplies a starting step.

### Hints for G6-01

1. The number consumes the first C argument position.
2. Label each C input by meaning before moving it.
3. The syscall number adds a C input, and the kernel fourth argument uses R10.

### Hints for G6-02

1. Translation belongs to the public consumer.
2. Separate the raw helper result from the wrapper result.
3. An error records positive errno and changes the function result to minus one.

### Hints for G6-03

1. Follow definitions and calls, not similar filenames.
2. Separate process entry from C runtime initialization.
3. start.o is Forth-built entry; startup.o is the C-built initialization member.

### Hints for G6-04

1. Count both register lifetime and stack alignment.
2. Locate the initializer call before main.
3. Protect argc/argv against volatile-register clobbers; two saved words retain alignment.

### Hints for G6-05

1. The metric is based on RBP, not the current RSP.
2. Compare fixed RBP with changing RSP.
3. The parent-frame slot stays at the admitted RBP coordinate during temporary pushes.

### Hints for G6-06

1. Zero distinguishes initial return from resumed return.
2. Distinguish initial and resumed results.
3. longjmp changes a requested zero to one when resuming setjmp.

### Hints for G6-07

1. Name the owner of the saved state.
2. List the buffer’s named saved fields.
3. Saved registers/continuation require a still-live destination and do not include signal masks.

## Worked solutions

### Solution G6-01 — Map the bridge

The original question asks: Where does C input a6 arrive, and where must Linux
receive it?

It arrives at entry RSP+8 and is loaded into R9. The syscall number goes to RAX;
a4 goes to R10.

**Check your explanation:** The number consumes the first C argument position. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** copying C register positions directly into the kernel
interface. The syscall number adds a C input, and the kernel fourth argument
uses R10.

### Solution G6-02 — Translate an error

The original question asks: A wrapper receives raw −2. What does the raw leaf do
to errno? What may the wrapper do?

The leaf changes no errno. The public wrapper recognizes the negative error
band, stores 2 and supplies its declared failure result.

**Check your explanation:** Translation belongs to the public consumer. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** returning raw minus two as the documented libc-style
result. An error records positive errno and changes the function result to minus
one.

### Solution G6-03 — Keep startups separate

The original question asks: Name the producer and role of start.o and startup.o.

start.o is Forth-built entry code; startup.o is C-built runtime initialization
selected from the archive.

**Check your explanation:** Follow definitions and calls, not similar filenames.
A matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** using the two similarly named objects as interchangeable
entry providers. start.o is Forth-built entry; startup.o is the C-built
initialization member.

### Solution G6-04 — Preserve arguments

The original question asks: Why push argc and argv after aligning in the
runtime-aware startup?

The initializer call can clobber argument registers; the saved pair restores the
prepared main inputs. Two eight-byte pushes retain pre-call alignment.

**Check your explanation:** Count both register lifetime and stack alignment. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** assuming prepared main arguments survive an earlier
initializer call in registers. Protect argc/argv against volatile-register
clobbers; two saved words retain alignment.

### Solution G6-05 — Query a stable frame

The original question asks: Why can a parent-frame metric survive temporary
argument pushes?

The admitted caller keeps RBP fixed while RSP changes; [RBP] retains its
parent’s saved frame.

**Check your explanation:** The metric is based on RBP, not the current RSP. A
matching final answer without that reason leaves the mechanism uncertain. If
your answer differs, compare the supplied premises first, then locate the first
transition at which your model departs from the chapter.

**Common wrong path:** following temporary RSP movement as though it changed the
saved parent frame. The parent-frame slot stays at the admitted RBP coordinate
during temporary pushes.

### Solution G6-06 — Normalize nonlocal return

The original question asks: What does longjmp(buffer,0) make the saved setjmp
return?

It resumes the saved continuation with int result one. The direct setjmp return
had been zero.

**Check your explanation:** Zero distinguishes initial return from resumed
return. A matching final answer without that reason leaves the mechanism
uncertain. If your answer differs, compare the supplied premises first, then
locate the first transition at which your model departs from the chapter.

**Common wrong path:** making initial execution and resumption indistinguishable
by returning zero twice. longjmp changes a requested zero to one when resuming
setjmp.

### Solution G6-07 — State what is saved

The original question asks: Does the eight-word buffer restore signal masks or
revive returned frames?

No. It stores named callee-saved registers, post-return RSP and RIP, with a
still-live destination required.

**Check your explanation:** Name the owner of the saved state. A matching final
answer without that reason leaves the mechanism uncertain. If your answer
differs, compare the supplied premises first, then locate the first transition
at which your model departs from the chapter.

**Common wrong path:** treating eight words as a full process snapshot or a way
to revive an expired frame. Saved registers/continuation require a still-live
destination and do not include signal masks.

## Changed-task checks

Open these after attempting the changed prompts. A changed input can leave one
result unchanged while changing another owner or evidence obligation.

### Check G6-01 — Map the bridge

RCX and R11; a4 cannot remain in RCX for this boundary. Accept an explanation
that follows the changed premise and retains the unmodified contracts. Do not
accept a new execution claim merely because the paper result is consistent.

### Check G6-02 — Translate an error

No; the mapping wrapper preserves errno on success. Accept an explanation that
follows the changed premise and retains the unmodified contracts. Do not accept
a new execution claim merely because the paper result is consistent.

### Check G6-03 — Keep startups separate

It calls main without the initializer, changing the startup behavior. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G6-04 — Preserve arguments

Without another adjustment, sixteen-byte pre-call alignment is lost; this is a
different unsatisfied model. Accept an explanation that follows the changed
premise and retains the unmodified contracts. Do not accept a new execution
claim merely because the paper result is consistent.

### Check G6-05 — Query a stable frame

The helper’s private contract no longer applies; no valid backtrace or depth
result is promised. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

### Check G6-06 — Normalize nonlocal return

The low int value is normalized with sign extension and remains −3. Accept an
explanation that follows the changed premise and retains the unmodified
contracts. Do not accept a new execution claim merely because the paper result
is consistent.

### Check G6-07 — State what is saved

That changes RSP away from the kernel-owned signal frame and violates its
separate contract. Accept an explanation that follows the changed premise and
retains the unmodified contracts. Do not accept a new execution claim merely
because the paper result is consistent.

## Evidence for the feedback

The feedback uses the [chapter’s pinned-source
contracts](../chapters/06-raw-syscalls-startup-and-runtime-control.md) and its
stated illustrative inputs. The numerical states are derivations; any historical
result remains attributed to its repository account. No exercise, generated
instruction or build was executed to create these answers.
