# Compiler entry and profile: hints and solutions

Return to [Chapter 1](../chapters/01-compiler-entry-and-profile.md). These are paper derivations under its pinned source and legacy-profile contracts, not results from building or running the compiler. The triangle-output predictions assume successful character writes. Each exercise starts from a fresh program state unless stated otherwise.

Choose a first hint for orientation, a second for one decisive step, or the worked solution whenever useful. After feedback, close the answer and try the changed case. A repeated sentence is less informative than a newly derived state.

## Entry check

1. `[9]` becomes `[9, 9]` after `dup`, `[9, 9, 2]` after `[lit] 2`, then `[9, 18]` after `*`. Multiplication consumes only the top two values. The original lower nine survives.
2. From an empty stack, `count` leaves `[A]`; `count @` leaves `[7]`. `[lit] 4 count !` builds `[4, A]`, then stores four in the cell at A and leaves `[]`. The address has not moved and has not become four.
3. Defining `twice` constructs a callable body; its ordinary `dup` and `+` do not double a caller's value during definition. Subsequently `[lit] 3 twice` gives `[3]`, then `[3, 3]`, then `[6]` from an empty stack. None of these operations prints six.
4. No. `allot` advances the allocation cursor. This declaration reserves the named data area without establishing its prior contents. Initialization requires actual writes or a separate stated guarantee.

If any answer differs, use its [specific refresher](../chapters/01-compiler-entry-and-profile.md#bring-four-forth-contracts), then reattempt with a different value. For example, `dup [lit] 3 *` from `[5]` leaves `[5, 15]`; a later store of six at A changes the cell contents, not A. Correctness on this bridge is enough to begin; reconstructing all seed instructions is not the entrance task.

## C1-01 — Separate the two executions

**Hint 1.** Locate the first operation that stops treating the remaining input as Forth source.

**Hint 2.** `120-cc-main.fth` ends with an invocation, not only a colon definition. Its `cc-load-stdin` consumes all remaining input bytes as C.

**Worked solution.** The proposed order executes the default driver before `121-cc-sysv.fth` has been interpreted. Therefore that later file's Forth bytes become part of the raw C input. The repair is to keep all required library layers in lexical order while holding `120-cc-main.fth` aside, put every selected library including `121` before it, and put C source after it. Other layers above 121 must receive the same treatment; swapping only these two files is not a complete general loader rule.

Loading `121` does not select System V: the target flag starts at zero and selection requires `cc-sysv-enable` plus the appropriate driver. Similarly, installing optional native words is not choosing the TinyCC program path.

| Event | Actor | Why |
|---|---|---|
| Reserve the output storage | Builder | It needs somewhere to accumulate future executable bytes |
| Store five in `w[2]` | Generated program | The C loop computes that value during the third body iteration |
| Run the driver's `bye` | Builder | It ends the compiler invocation |
| Return sixteen from C `main` | Generated program | It follows the completed triangle computation |

“Exit zero” is incomplete without identifying the process. A builder reaching `bye` requests a zero exit, but its legacy output helper did not check write or close results. Even a complete output file has not been shown to execute. The triangle is predicted only for a later run meeting the chapter's assumptions.

**Wrong path to diagnose.** “They are both x86-64, so they are the same execution” confuses an architecture with a process identity. Also, moving a file earlier makes its definitions available; it does not itself perform an optional mode-selection call.

**Changed case.** A dedicated driver omits `120`, loads the compiler libraries, explicitly selects LP64/direct preprocessing, then calls `cc-native-program`. Is that the default path with a different output filename? No. The program parser, layout and call contract have changed. Conversely, changing only the default output path would not select a new target. Explain both differences before continuing.

## C1-02 — Complete the row trace

**Hint 1.** Keep the caller's array cell distinct from the callee's parameter copy.

**Hint 2.** Row one receives the cumulative star total from row zero: one. At row three, the previous rows contributed `1 + 3 + 5`.

**Worked solution.** For row one, width is `1 + 1 * 2 = 3`, padding is `(4 - 1) - 1 = 2`, and the total changes from one to four. `line(2, 3)` reduces its own `pad` and `n` to zero; `w[1]` remains three. For row three, width is seven, padding zero, and the total changes from nine to sixteen. Its first `while` body runs zero times. `w[3]` remains seven after the call.

The original test rejects `r = 4`. With `<=`, that same test accepts it. The additional body immediately attempts `w[4] = 1 + 4 * 2`. Four elements have valid indexes zero through three, so the selected destination is outside the array. Stop at that failed storage precondition. Do not predict a fifth output line, a particular crash, or a harmless write into `r`.

**Wrong path to diagnose.** An array's length is a count, not its final valid index. Also, deriving the next width as nine does not make its destination legal. An arithmetic result and an access precondition are separate obligations.

**Changed case.** Suppose the original `<` test remains and you inspect `line(0, 0)` separately. Both `while` bodies run zero times; the unconditional final call still requests one newline. Neither caller argument storage nor an array element is changed by those local parameters. This case tests the placement of the unconditional statement rather than another positive width.

## C1-03 — Change the shape, then the check

**Hint 1.** The assignment formula and the final comparison are separate pieces of code. Changing one does not update the other.

**Hint 2.** For the wider four-row case, the widths are two, four, six, and eight. The spaces still follow three, two, one, zero.

**Worked solution, wider four-row case.** The cumulative star totals are two, six, twelve, and twenty. The line requests, showing spaces as counts, are:

| Row | Spaces | Stars | Newlines |
|---:|---:|---:|---:|
| 0 | 3 | 2 | 1 |
| 1 | 2 | 4 | 1 |
| 2 | 1 | 6 | 1 |
| 3 | 0 | 8 | 1 |

There are `6 + 20 + 4 = 30` requested character bytes. `t.stars` is twenty, but `ROWS * ROWS` is still sixteen. The comparison fails and `main` returns one. The returned number is neither the star total nor the character count in this changed program. Widening the triangle does not rewrite the acceptance condition.

**Worked solution, original formula with three rows.** Reset the program, restore `1 + r * 2`, and replace `ROWS` with three. The body runs at indexes zero, one, and two. Widths are one, three, five; padding values are two, one, zero; totals are one, four, nine. Requested characters total `3 + 9 + 3 = 15`. The final comparison is `9 == 3 * 3`, so `main` returns nine. The array now has three elements; the rejected test at `r = 3` preserves its bounds.

**Wrong path to diagnose.** Returning twenty in the first case skips the `if` condition. Returning sixteen in the second case accidentally keeps the former macro value in the final comparison. Apply the same replacement to every use of `ROWS`.

**Changed case.** Restore canonical `tri.c` and set `ROWS` to one. There is one iteration at zero: width one, padding zero, total one, and two requested characters including newline. The comparison succeeds, but the result is one, the same number as the failure branch's return value. Therefore an observed exit status of one alone would not distinguish these branches. The source trace or additional observation would be needed. This is a limit of that status-based check, not evidence of a compiler fault.

## C1-04 — Separate size from calling convention

**Hint 1.** Multiply counts by the width specified for that particular representation.

**Hint 2.** LP64's four-byte `int` describes an object. A private native argument slot is a different representation and remains eight bytes.

**Worked solution.** The four-element array payload occupies `4 * 8 = 32` bytes in the legacy profile and `4 * 4 = 16` bytes in LP64. Four Forth cells occupy 32 bytes. Four private TinyCC argument slots also occupy 32 bytes.

These equal 32-byte results describe different storage with different owners and lifetimes. The builder's Forth cells are not the target's parameters, and neither is automatically the C array. In the TinyCC path, a four-byte integer object can contribute a value represented in an eight-byte call slot. A representation used to communicate a value need not have the same width as the original object.

These calculations specify only the named payload or slots. A complete function frame may also contain other locals, parameters, saved state, padding, or reserved space; its accounting needs the particular frame contract. Nor do object widths establish host interoperability. Calls must agree on argument placement, result placement, alignment and other ABI details, and the legacy image has a restricted runtime/linkage path. “All are eight bytes” is not that evidence.

**Changed case.** Increase the array to five integer elements: legacy payload 40 bytes, LP64 payload 20 bytes. Five private native argument slots require 40 bytes. Explain why the 20-byte payload does not imply twenty bytes of call slots or a twenty-byte total frame. If that explanation holds, proceed without memorizing a frame size not taught here.

## C1-05 — Place the work and bound the evidence

**Hint 1.** The executable header is partly known early, while its final size is known late.

**Hint 2.** In the actual driver, `cc-preprocess` precedes `cc-emit-elf-header`, which precedes `cc-parse-program`. Finalization follows parsing.

**Worked solution.** Among the listed jobs, the order is:

1. Store raw input in `cc-in-buf`
2. Preprocess into `cc-src-buf`, including macro replacement
3. Emit the initial ELF header
4. Parse tokens and emit instructions
5. Repair final ELF sizes, after global finalization
6. Attempt the output-file write

The list omits initialization operations; it is not a replacement implementation of `cc-main`. `ROWS` becomes replacement text `4` during preprocessing, before the lexer delivers the final declaration's tokens. The header's entry is `0x400078`, where the entry stub begins. That stub calls the separately located C `main`; its call target is repaired when the compiler knows the function's address.

A corrected report might say:

> The paper trace predicts four rows and return value sixteen under the stated conditions. The reported zero exit belongs to the builder; it does not confirm a complete output write or execution of that file. This work provides no new Linux-bootstrap execution evidence.

This accepts the exercise's hypothetical report of an exit without pretending that this chapter actually observed one. To claim execution, a record would need the exact source/profile and commands, completed output artifact, run environment, and captured behavior. To claim a later bootstrap outcome, it would need the named later artifacts, transformations, and acceptance observations too. A paper trace, a compiler exit, and a multi-stage bootstrap are different evidence scopes.

**Wrong path to diagnose.** Placing the ELF header last assumes all output must be known before any bytes can be emitted. Reserved fields and later patches remove that requirement. Calling the predicted triangle “observed output” makes a different mistake: it upgrades a derivation into an experiment that did not occur.

**Changed case.** Suppose a fully recorded run of this exact four-row input prints the predicted triangle and exits sixteen. Can that one observation prove arbitrary C programs correct or a complete Linux chain built? No. It would support behavior on the named input, profile and environment. Further claims require further evidence, and a finite passing case is not a universal correctness proof.

## What to carry forward

You should now be able to explain the program's behavior, preserve its input/loop/storage preconditions, distinguish object widths from argument representation, and locate the transition from Forth loading to C compilation. Keep the [chapter's profile and source record](../chapters/01-compiler-entry-and-profile.md#source-and-evidence) available. After other work, reconstruct the phase boundary and retry a changed case without its answer. These are proposed learning checks; no learner retention or transfer result is claimed.
