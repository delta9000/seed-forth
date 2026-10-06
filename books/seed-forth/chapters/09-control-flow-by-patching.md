# 9. Control flow by patching

[Previous: Defining words and phases](08-defining-words-and-phases.md) · [Practice help](../practice/09-solutions.md) · [Next: Storage, deferred words, and bytes](10-storage-deferred-words-and-bytes.md)

A definition can calculate a flag. How does that flag choose which instructions run next? There is a second problem for its compiler: when it reaches the beginning of an `if,`, it has not compiled the end yet. It cannot write an address it does not know.

The library solves both problems with **emit, remember, patch**. Emit a branch with an empty target cell, remember that cell's address, then fill it when the destination becomes known. Backward branches are easier: their destinations already exist.

By the end, you should be able to compile a conditional and a countdown on paper, follow both runtime paths, distinguish a fixup from its stored destination, and explain why repeating a loop does not accumulate return addresses.

## Bring the right contracts

Use [Chapter 3's](03-bits-and-subtraction.md) subtraction and zero/nonzero distinction, [Chapter 4's](04-return-stack-and-shuffles.md) call/return and temporary-borrowing rules, [Chapter 6's](06-memory-updates-and-writers.md) byte widths, and [Chapter 8's](08-defining-words-and-phases.md) compilation phases. In particular:

- An ordinary compiled call occupies five bytes: `E8` followed by a four-byte relative displacement
- A compiled `[lit] n` occupies thirteen bytes: a five-byte call to `lit`, followed by the eight-byte value
- `,` writes one eight-byte cell at HERE and advances HERE by eight; `!` overwrites an addressed cell without advancing HERE
- An immediate word executes while the surrounding definition is being compiled; `;` emits a one-byte `RET`

Check yourself: if a call starts at 1000, which address does it put on the return stack? If an inline cell begins at that return address, which address follows its eight bytes? The answers are 1005 and 1013. If those quantities feel interchangeable, revisit the call layout before proceeding. If they are secure, try S9-02 and S9-04, then inspect any explanation your answers need.

**Evidence and model.** All traces are manual derivations from the Linux/x86-64 seed at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`, not executed observations. Stack tops are at the right. Cells are 64 bits, addresses count bytes, and stored cells are little-endian. Invented body addresses such as 1000 are paper locations, not live scratch addresses. Assume valid writable code storage, no address wrap, no overlap with stacks or system cells, enough stacks, correctly nested combinators, intact calls, and encodable call displacements. Each example resets the model; its dictionary header has already been created before the stated body start.

## Two times, two different stack pictures

During compilation, the compiler uses the ordinary data stack to hold unfinished work. Later, the generated program uses the data stack for its inputs and results. These are different times, not two new physical stacks.

We label compilation-time pictures `C` and runtime pictures `D`. `C: [1005]` can mean “a branch target cell still needs patching.” `D: [7, 2]` can mean “a number and a flag supplied to the finished word.” The flag is not present when the compiler sees `if,`.

For example:

```
: maybe-add  if, [lit] 1 + then, ;
```

The intended runtime effect is `( n flag -- result )`: add one when the flag is nonzero, otherwise retain `n`. While defining it, `if,` runs now and writes code that will consume a flag later. `[lit] 1` emits a future literal. `+` emits a future call. `then,` runs now and patches memory. None performs the requested addition during compilation.

One subtlety: the existing definition of `if,` itself contains `[lit] 0`. That source text was compiled when the library defined `if,`. When `if,` later executes as an immediate helper, its already-compiled literal code pushes zero **now**, for its own `,` to consume. STATE affects how the input loop handles tokens; it does not make every running word recompile its own body.

A combinator is an ordinary library word used to build another word's control structure. Its immediate flag supplies the phase choice. The punctuation in `if,` is part of its name; it does not give the parser a new grammar rule.

## The thirteen-byte branch contract

The seed supplies `branch` and `0branch`. Their target comes from memory immediately after their call, not from `D`:

```
At address A:       CALL branch or CALL 0branch       5 bytes
At address S=A+5:   inline absolute destination T     8 bytes
At address A+13:    following instruction
```

“Inline” means stored among the instructions. The cell is data, so execution must not proceed through its bytes as instructions. The call's relative displacement reaches the **primitive's code**. The following cell holds the **program's destination**, an absolute address. These are different addresses with different encodings. The eight-byte slot is part of the required call-site contract: a bare call to `branch` without its following target cell is not a complete branch sequence.

| Primitive | Runtime D effect | Next instruction |
|---|---|---|
| `branch` | `( -- )` | Destination stored in the inline cell |
| `0branch` | `( flag -- )` | Stored destination if flag is zero; otherwise `S+8` |

Every nonzero flag counts as true: 2 works, as does the all-ones canonical true flag. `0branch` consumes the flag on **both** paths. It is a zero test, not a signed-positive test and not a bitwise mask operation.

Here is the complete return-stack handshake. Let `Rbase` stand for the stack before this branch call, including the surrounding word's return destination and any properly owned temporary values. This is explanatory notation, not a Forth name.

| Moment | R | Next action |
|---|---|---|
| Before branch call | `Rbase` | Execute call at A |
| On primitive entry | `Rbase, S` | S points to the inline cell |
| After removing S | `Rbase` | Select destination Q |
| After pushing Q | `Rbase, Q` | Execute primitive's `RET` |
| After that `RET` | `Rbase` | Continue executing at Q |

For `branch`, `Q=T`. For `0branch`, `Q=T` if the removed flag was zero, otherwise `Q=S+8`. The conditional primitive removes the data flag before making that choice.

The selected destination exists on R **before** `RET`; `RET` consumes it. Afterward, neither Q nor S remains there. The inline cell itself remains in code memory. “Consumed slot” therefore means its temporary return-stack address is gone, not that memory was erased. This distinction fixes an incorrect post-`RET` description in the older branch chapter.

The source's four operations for `branch_code` are remove the call's return address, fetch a cell through it, push the fetched address, and return there. `zbranch_code` adds the flag removal and zero/nonzero choice. No additional machine-instruction vocabulary is needed to trace that contract.

## Capture the primitives, then reserve a fixup

The library obtains execution tokens once while it loads:

```
' branch  constant branch-xt
' 0branch constant 0branch-xt
```

Tick reads the following name and returns its body address. `constant` captures that value under a new name. Thus `0branch-xt call,` emits a call to `0branch`; it does not execute a conditional branch while compiling. Reloading against a changed seed resolves its current addresses without hard-coding them here.

The actual forward-branch definitions are:

```
: if,
  0branch-xt call,
  here                         \ slot address, returned as fixup
  [lit] 0 ,                    \ reserve 8 bytes (` ,` emits a cell)
;
immediate

: then,
  here swap ! ;
immediate
```

Suppose HERE begins at A and `C` has an untouched older portion K. `call,` advances HERE to `S=A+5`. `here` remembers S on C. The zero literal and `,` initialize an eight-byte placeholder at S, leaving `C: [K, S]` and HERE at `A+13`.

That remembered S is a **fixup address**: where to write later. Zero is merely the cell's current contents. It is not a safe destination or a promise that the compiler will reject unfinished code.

When the body is complete, let HERE be T. `then,` performs:

```
start          C: [K, S]         cell at S contains 0
here           C: [K, S, T]
swap           C: [K, T, S]
!              C: [K]            cell at S contains T
```

The store consumes value T and destination S in that order. It writes eight bytes. HERE remains T: patching previously reserved storage emits no new code. There is no runtime call to `then,`.

### Compile and run `maybe-add`

Reset the body start to 1000. The symbolic body length between `if,` and `then,` is thirteen bytes for the literal plus five for `+`, so the false destination is `1000+13+18=1031`.

| Source processed | Bytes placed or changed | HERE afterward | C afterward |
|---|---|---:|---|
| Body starts | None | 1000 | `[]` |
| `if,` | Call at 1000–1004; zero cell at 1005–1012 | 1013 | `[1005]` |
| `[lit] 1` | Call at 1013–1017; value cell at 1018–1025 | 1026 | `[1005]` |
| `+` | Call at 1026–1030 | 1031 | `[1005]` |
| `then,` | Store 1031 in cell beginning at 1005 | 1031 | `[]` |
| `;` | `RET` at 1031 | 1032 | `[]` |

The target cell becomes decimal bytes `7 4 0 0 0 0 0 0`, because `1031=7+4×256`. Its address remains 1005. Reading that cell gets 1031; jumping to 1005 instead would enter data.

Now compile time is over. Start independent runtime traces:

| Input D | Conditional action at 1000 | Remaining path | Final D |
|---|---|---|---|
| `[99, 7, 0]` | Consume zero; select stored 1031 | Final `RET` | `[99, 7]` |
| `[99, 7, 2]` | Consume two; select 1013 | Push one; add; final `RET` | `[99, 8]` |

On the true path, D changes from `[99, 7]` to `[99, 7, 1]` to `[99, 8]`. The branch call restores R to its pre-call shape on either path; the final `RET` then consumes the surrounding word's own return destination. Both paths preserve the older 99.

## An `else,` needs another branch

If the true arm falls straight into the false arm, both run. `else,` therefore emits an unconditional branch over the false arm, then patches the earlier conditional to enter that false arm:

```
: else,
  branch-xt call,
  here                         \ start of new (else-end) target slot
  [lit] 0 ,                    \ reserve 8 bytes
  swap                         \ ( fixup-else fixup-if )
  here swap !                  \ patch fixup-if -> just past unconditional branch
;
immediate
```

Call the old fixup F and the new one G. After the new placeholder, `C: [F, G]`. The first `swap` gives `[G, F]`; `here swap !` patches F and leaves G. The compiler exchanges one outstanding question for another: the false-arm start is now known, but its end is not.

Use this complete example with another independent body start of 1000:

```
: choose-byte  if, [lit] 65 else, [lit] 66 then, ;
```

| Source processed | Layout or patch | HERE afterward | C afterward |
|---|---|---:|---|
| `if,` | Conditional call 1000–1004; F=1005, initially zero | 1013 | `[1005]` |
| `[lit] 65` | Literal call and value, 1013–1025 | 1026 | `[1005]` |
| `else,` | Unconditional call 1026–1030; G=1031, initially zero; set cell F to 1039 | 1039 | `[1031]` |
| `[lit] 66` | Literal call and value, 1039–1051 | 1052 | `[1031]` |
| `then,` | Set cell G to 1052 | 1052 | `[]` |
| `;` | `RET` at 1052 | 1053 | `[]` |

Predict both paths before reading them. With `D: [99, 2]`, the conditional consumes two and continues at 1013. The literal leaves `[99, 65]`. The unconditional branch at 1026 uses its inline target 1052, so 66 is never pushed. With `[99, 0]`, the conditional consumes zero and goes directly to 1039. That literal leaves `[99, 66]`, then execution reaches the final return.

There is one value on either outcome, not two. No text token is skipped by the compiler: it compiled both arms. The finished program chooses a path through their bytes. The entire body is 53 bytes; `then,` contributes zero of them.

## Mark a loop, remember its exit

A loop needs a backward destination and, for a pre-test loop, a forward exit. These source definitions keep both on C:

```
: begin,  here ;
immediate

: while,
  0branch-xt call,
  here [lit] 0 , ;
immediate

: repeat,
  swap branch-xt call, ,       \ unconditional `CALL branch` + back-target cell
  here swap !                  \ patch loop-exit fixup -> just-past-repeat
;
immediate
```

`begin, ( -- back-target )` emits nothing. It records the current code address B. `while, ( back-target -- back-target fixup )` emits the same conditional shape as `if,`, preserving B underneath its new exit fixup F. At runtime, that conditional consumes a flag and leaves the loop when the flag is zero.

At `repeat,`, start with `[B, F]`. `swap` produces `[F, B]`. `branch-xt call,` emits five bytes while preserving B, then `,` writes B as the backward destination and consumes it. Only F remains. Finally `here swap !` fills F with the address after this thirteen-byte backward branch.

Thus two remembered items disappear for two different reasons: B becomes inline target data; F identifies an earlier cell to patch. Confusing their roles makes a plausible-looking stack of addresses describe the wrong program.

### Compile the countdown completely

Our teaching word leaves its final zero on the stack:

```
: countdown  begin, dup while, [lit] 1 - repeat, ;
```

Its input contract is a nonnegative count `n` with `0 ≤ n < 2^63`, supplied above any older values. We test the count itself for zero. We do not require a signed comparison or convert it into a canonical flag.

Reset the body start to 1000:

| Source processed | Bytes placed or changed | HERE afterward | C afterward |
|---|---|---:|---|
| `begin,` | Remember B=1000; emit nothing | 1000 | `[1000]` |
| `dup` | Call at 1000–1004 | 1005 | `[1000]` |
| `while,` | Conditional call 1005–1009; exit cell F=1010, initially zero | 1018 | `[1000, 1010]` |
| `[lit] 1` | Literal call 1018–1022; value cell 1023–1030 | 1031 | `[1000, 1010]` |
| `-` | Call at 1031–1035 | 1036 | `[1000, 1010]` |
| `repeat,` | Branch call 1036–1040; cell 1041–1048 contains 1000; patch cell 1010 to 1049 | 1049 | `[]` |
| `;` | `RET` at 1049 | 1050 | `[]` |

The size is `5+13+13+5+13+1=50` bytes. `begin,` emits zero bytes. The exit cell contains decimal bytes `25 4 0 0 0 0 0 0`; the backward cell contains `232 3 0 0 0 0 0 0`. These encode absolute 1049 and 1000. Neither is a relative displacement from its slot.

During `repeat,` specifically, C goes `[1000, 1010] → [1010, 1000] → [1010] → []`. The middle reduction is the backward target's `,`; the last is the exit patch's `!`. Writing the backward cell advances HERE. Patching the exit cell does not.

### Run it from three, then from zero

At runtime, the code at 1000 duplicates the current count. The conditional consumes the copy, preserving the original for subtraction or the final result.

| Visit to 1000 | D after `dup` | D after conditional | Arithmetic before backward branch | Next address |
|---|---|---|---|---:|
| Start with three | `[99, 3, 3]` | `[99, 3]` | Push one: `[99, 3, 1]`; subtract: `[99, 2]` | 1000 |
| Count is two | `[99, 2, 2]` | `[99, 2]` | Push one: `[99, 2, 1]`; subtract: `[99, 1]` | 1000 |
| Count is one | `[99, 1, 1]` | `[99, 1]` | Push one: `[99, 1, 1]`; subtract: `[99, 0]` | 1000 |
| Count is zero | `[99, 0, 0]` | `[99, 0]` | None: conditional selects 1049 | 1049 |

At 1049, the final return leaves `[99, 0]` for the caller. There were three subtraction passes and four tests. Each literal skips its own value cell; each branch consumes its own temporary return destination. Reaching 1000 again is a jump within this invocation, not a recursive call to `countdown`. R does not grow on each repetition.

Starting instead with `[99, 0]` gives `[99, 0, 0]` after the first `dup`. The conditional consumes one zero, selects 1049, and returns `[99, 0]`. The subtraction body runs **zero times**. It does not first underflow zero to an all-ones cell.

For the stated count domain, each body pass subtracts one from a positive integer without wrapping. That quantity reaches zero after exactly `n` passes, assuming execution continues and the stated contracts hold. This argument belongs to this body and domain; the loop combinators do not establish termination for arbitrary bodies. A signed-negative bit pattern is nonzero too. Do not interpret this loop as “continue while signed-positive.”

## Post-tests, unconditional repetition, and early return

The remaining actual definitions are:

```
: until,
  0branch-xt call, , ;         \ `CALL 0branch` + back-target cell
immediate

: again,
  branch-xt call, , ;          \ `CALL branch` + back-target cell
immediate

: exit,  ret, ;
immediate
```

Both loop closers consume the back-target left by `begin,`. `until,` emits a conditional backward branch. Consequently `begin, BODY until,` executes BODY before testing the flag BODY supplies: false repeats; true continues. `again,` emits an unconditional backward branch and consumes no runtime flag.

Compare this extra teaching definition:

```
: once-down  begin, [lit] 1 - dup 0= until, ;
```

For positive count one, the body subtracts to zero, duplicates zero, and `0=` replaces the copy with the all-ones true flag. `until,`'s conditional consumes that flag and continues beyond its inline cell, leaving zero. The body ran once. Input zero is outside this positive-count contract: it subtracts before testing and wraps to `2^64-1`. You cannot reuse `countdown`'s zero-iteration reasoning here.

An `again,` loop needs some other route out if it is to return, such as an `exit,` reached in its body. `exit,` emits a one-byte `RET` **inside the word being defined**. It is an early return from that word, not merely a jump past the nearest loop. Its compiler helper still returns normally after emitting the byte.

The return-stack rule from Chapter 4 applies on every exit path. Consider:

```
: saved-or-zero  >r if, r> exit, then, r> drop [lit] 0 ;
```

The runtime inputs are `( flag saved -- result )`. `>r` parks `saved`; the conditional consumes `flag`. A nonzero flag reaches `r>`, which restores the saved value to D before the early return. A zero flag skips that arm, retrieves and discards the saved value, pushes zero, and reaches the ordinary final return. Both paths remove their own temporary before returning.

If the true arm were only `exit,`, its `RET` would use the parked value as an instruction address. The branch mechanism did not create that problem and cannot repair it. Balanced branches preserve the R they found; they do not guarantee that your word left its own R in a returnable state. S9-05 makes that caller boundary explicit.

## Practice

Use independent paper resets. [Hints and worked answers](../practice/09-solutions.md) are available when useful; a changed reattempt follows each answer.

### S9-01 — Separate construction from execution

Compile `maybe-add` with body start 2000. Give its fixup address, stored destination, final HERE, and C after each source item. Then trace runtime inputs `[99, 9, 0]` and `[99, 9, 2]`. Explain why neither nine nor the runtime flag appears in your compilation trace.

### S9-02 — Diagnose the address and width

Reset `maybe-add` to body start 3000. First, replace only `if,`'s placeholder `,` with `c,`. Keep `then,` unchanged. Where do the literal call and final return now begin? Which following bytes does the eight-byte patch overwrite? Separately, restore the proper placeholder but replace `then,` with `here !`. Give the reversed value/address roles. Repair both errors without executing malformed code.

### S9-03 — Complete an alternative path

Compile `: choose if, [lit] 9 else, [lit] 12 then, ;` at body start 4000. Fill in both fixup addresses and their final contents. Trace zero and the all-ones flag from `[99, flag]`. Explain which emitted instruction prevents the true path from also pushing twelve.

### S9-04 — Follow a zero-iteration loop

Compile `countdown` at body start 5000. Give B, F, both final branch destinations, body size, and final HERE. Run it on paper from two and zero, counting tests and subtractions separately. Then remove `dup`: which runtime value would `while,` consume, and why is the original countdown contract lost?

### S9-05 — Repair an early return

In `saved-or-zero`, remove the `r>` immediately before `exit,`. Trace `[99, 2, 7]` only to the first broken return condition. Restore that operation and trace both flags two and zero with saved value seven. Before calling this word, suppose its caller's R is `[…, ret(caller), 77]`, with 77 owned by the caller. Show why that 77 must remain when this word returns.

## Stop, check, and continue

If stuck, identify which state first differs: C, generated memory, D, or R. Rework that transition with a hint rather than repeating the whole example. For a useful pause, save countdown's compile-time state `C: [1000, 1010]`, HERE 1036. On return, finish `repeat,` and explain why its two stores have different cursor effects.

You have traced all nine control-flow combinators and their shared inline-cell mechanism. After intervening material, retry the width diagnosis and zero-input trace without the tables. Next, [Storage, deferred words, and bytes](10-storage-deferred-words-and-bytes.md) uses these mechanisms to work with retained data and repeated byte operations.

## Source and evidence

The excerpts are from the pinned [`010-lib.fth`, capture and nine combinators](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L298-L372). The runtime contracts are inspected in [`branch_code` and `zbranch_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L602-L631); the widths follow [`compile_call`, `lit_code`, and `[lit]`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L551-L600), [`comma_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L373-L389), and [`call,`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L227-L236). The older [control-flow chapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/11-control-flow-combinators.md) and [inline-cell chapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/19-branches-and-inline-cells.md) provide the coverage being reorganized. No source edit, build, seed run, or hardware-performance result is claimed. See the [edition record](../../EDITION.md).
