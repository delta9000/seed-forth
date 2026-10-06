# Control flow by patching: hints and solutions

Return to [Chapter 9](../chapters/09-control-flow-by-patching.md). These answers are manual derivations under its pinned seed contracts, not results from a Forth run. Addresses are independent paper models. C is the data stack during compilation; D is the data stack during later execution; R is the return stack. All tops are at the right. Model code storage is valid, separate from live stacks and system cells, and large enough for the stated layout.

Use the first hint to choose a representation, the second to expose a difficult step, or the worked answer when that would help. After comparing your first differing state, close the answer and attempt the changed case.

## S9-01 — Separate construction from execution

**Hint 1.** Relocating the body does not change its instruction lengths. The address remembered by `if,` is five bytes after its call begins.

**Hint 2.** The literal takes thirteen bytes and the addition call takes five. `then,` writes the current HERE through the remembered address; it does not move HERE.

**Worked solution.** The complete layout is:

| Source item | Placement or patch | HERE after | C after |
|---|---|---:|---|
| Start | Body starts at 2000 | 2000 | `[]` |
| `if,` | Call 2000–2004; zero placeholder 2005–2012 | 2013 | `[2005]` |
| `[lit] 1` | Literal call 2013–2017; cell 2018–2025 | 2026 | `[2005]` |
| `+` | Call 2026–2030 | 2031 | `[2005]` |
| `then,` | Cell at 2005 becomes 2031 | 2031 | `[]` |
| `;` | Return byte at 2031 | 2032 | `[]` |

A full-width read from 2005 would now produce 2031, whose decimal bytes are `239 7 0 0 0 0 0 0`. The fixup **address** remains 2005. It was consumed from C by the patch, not converted into 2031 on the stack.

For runtime `[99, 9, 0]`, `0branch` consumes the zero and selects 2031. The final return leaves `[99, 9]`. For `[99, 9, 2]`, it consumes two and selects 2013. The literal leaves `[99, 9, 1]`; addition leaves `[99, 10]`; execution returns at 2031. Both preserve 99 and restore R appropriately.

Neither runtime input belongs in C: the definition is built before either call supplies nine and a flag. C records compiler work. The literal one encountered during compilation supplies bytes for a later push; it does not add one to the outstanding fixup.

**Common wrong path.** Putting `[2005, 1]` in the C column after compiled `[lit] 1` confuses its interpret-mode result with its compile-mode emission. Its temporary compiler work finishes before that row.

**Changed case.** Replace the runtime true flag two with 256. Predict before checking: the same true path runs and leaves ten. A nonzero flag need not fit in one byte or equal the canonical all-ones value. The compilation layout is unchanged because runtime flag values are not embedded here.

## S9-02 — Diagnose the address and width

**Hint 1.** Replacing `,` with `c,` changes HERE's advance from eight to one. A later `!` still writes eight bytes.

**Hint 2.** After the short placeholder, the next call begins at 3006. List every address that a store beginning at 3005 touches. For the separate `here !` mistake, label which stack value `!` treats as its destination.

**Worked solution: short reservation.** With only the placeholder changed, the emitted layout before patching is:

| Field | Addresses |
|---|---|
| Conditional call | 3000–3004 |
| One placeholder byte | 3005 |
| Literal call | 3006–3010 |
| Literal value cell | 3011–3018 |
| Addition call | 3019–3023 |
| Final return location | 3024 |

At `then,`, HERE is 3024 and C contains 3005. The correct-width `!` stores 3024 across 3005–3012. It therefore overwrites the entire literal call at 3006–3010 and the first two bytes of its value cell at 3011–3012, in addition to the intended placeholder byte.

There is a second contract failure even before reasoning about those overwritten instructions: the conditional primitive always treats the region at 3005 as an eight-byte inline cell. Its nonzero path resumes at 3013, not at the compiler's wrongly placed literal call at 3006. A byte-sized placeholder cannot satisfy this primitive's runtime contract. Stop here; do not predict meaningful execution of the malformed body.

Repair the reservation by restoring `,`. It must both write eight bytes and advance HERE by eight. The following literal then begins at 3013, and the final return location becomes 3031.

**Worked solution: reversed store.** With the reservation repaired, a proposed `then,` consisting of `here !` does this:

```
start          C: [3005]          HERE = 3031
here           C: [3005, 3031]
!              C: []             stores value 3005 at address 3031
```

The intended write is value 3031 at address 3005. The missing `swap` reversed those roles. The old placeholder remains zero, while an eight-byte cell is written at the future continuation. A later `;` writing a return byte there does not repair the untouched branch target.

Restore `here swap !`. Its intermediate `[3031, 3005]` gives the store the correct destination on top.

**Common wrong path.** An empty final C does not establish that the correct bytes were patched. Both wrong and right stores consume two inputs; track the memory address as well as the stack height.

**Changed case.** Keep the full eight-byte placeholder but replace only the patch's `!` with `c!`. With target 3031, the first slot byte becomes 215 because `3031=11×256+215`; the other seven placeholder bytes remain zero. The cell therefore contains 215, not 3031. Reservation width and patch width must both agree with the runtime eight-byte fetch.

## S9-03 — Complete an alternative path

**Hint 1.** `else,` emits a thirteen-byte unconditional branch before patching the old conditional. Its target cell is the new outstanding fixup.

**Hint 2.** At the start of `else,`, HERE is 4026 and C is `[4005]`. After reserving its new cell, HERE is 4039 and C is `[4005, 4031]`.

**Worked solution.** The conditional call occupies 4000–4004, and its slot F begins at 4005. The first literal occupies 4013–4025. The unconditional call occupies 4026–4030, with slot G at 4031–4038. The second literal occupies 4039–4051. The final return is at 4052; final HERE is 4053.

`else,` patches the cell at 4005 to contain 4039. `then,` patches the cell at 4031 to contain 4052. C goes `[] → [4005] → [4031] → []` at the three combinators; compiling either literal leaves the outstanding fixup unchanged.

| Initial D | Conditional selection | Subsequent path | Final D |
|---|---:|---|---|
| `[99, 0]` | 4039 | Push twelve; final return | `[99, 12]` |
| `[99, U]` | 4013 | Push nine; unconditional branch to 4052; return | `[99, 9]` |

Here `U=2^64-1`, the all-ones flag. `0branch` consumes it just as it consumes zero. The unconditional branch at 4026 prevents the true arm from continuing into the second literal. It has no data input and does not remove nine.

**Common wrong path.** Patching F to 4031 would point at G's data bytes. The false destination must be **after** the entire unconditional call-and-cell sequence, at 4039.

**Changed case.** Insert `dup` immediately after `[lit] 9` in the true arm. The added ordinary call contributes five bytes. Now the unconditional call begins at 4031, G begins at 4036, the false arm starts at 4044, the final return is at 4057, and final HERE is 4058. F contains 4044 and G contains 4057. The true path leaves `[99, 9, 9]`, while the false path leaves `[99, 12]`. Correct control-flow patching does not guarantee matching data-stack effects across arms; that requires a separate contract check.

## S9-04 — Follow a zero-iteration loop

**Hint 1.** `begin,` remembers the address of the first runtime call, `dup`. `while,` remembers a different address: where its exit cell starts.

**Hint 2.** The final return is 49 bytes after the body start. Each positive count produces a true test, a subtraction, and a backward branch; zero produces a false test and no subtraction.

**Worked solution.** B is 5000. The `dup` call occupies 5000–5004. The conditional call occupies 5005–5009, so F is 5010. The literal occupies 5018–5030; the subtraction call occupies 5031–5035. The backward call occupies 5036–5040 and its target cell occupies 5041–5048. That cell contains B, 5000. The exit cell at F contains 5049, the final return's address. Body size is 50 bytes; final HERE is 5050.

C after `while,` is `[5000, 5010]`. During `repeat,`, `swap` produces `[5010, 5000]`; emitting the backward cell leaves `[5010]`; the exit patch leaves `[]`.

For runtime input `[99, 2]`:

```
after dup                [99, 2, 2]
after true test          [99, 2]
after literal and -      [99, 1]
after backward branch    [99, 1]        next instruction at 5000

after dup                [99, 1, 1]
after true test          [99, 1]
after literal and -      [99, 0]
after backward branch    [99, 0]        next instruction at 5000

after dup                [99, 0, 0]
after false test         [99, 0]        next instruction at 5049
```

The final return leaves `[99, 0]`. There are three tests and two subtractions. Starting with `[99, 0]` follows only the last three-line group: one test, zero subtractions, same final D.

Without `dup`, the conditional consumes the only count. Starting from `[99, 2]` would leave `[99]` after the true test. The following one and subtraction would operate on the older 99, producing 98 instead of decrementing the intended count. That already violates preservation of older items; stop the intended-contract trace there. Starting from `[99, 0]` would leave `[99]`, losing the promised final count even on the exit path.

**Common wrong path.** Counting the final false test as another loop-body pass gives three subtractions from input two. The zero test goes directly to the return; it never reaches the literal at 5018.

**Changed case.** Compare `once-down` from the chapter with input one and with input zero. From one it subtracts to zero, duplicates it, turns the copy into U with `0=`, and consumes U at `until,`, leaving zero after one body pass. From zero its first subtraction wraps to U; its following equality test produces zero, so the backward branch is taken. That input is outside the stated positive-count contract. In particular, this is not a zero-iteration version of `countdown`. Do not infer a short runtime or a general loop guarantee from the first input.

## S9-05 — Repair an early return

**Hint 1.** At the early return, inspect the actual top of R. `RET` does not search downward for an entry labeled “return destination.”

**Hint 2.** The current word owns the parked seven. The caller's 77 is older and belongs below this word's own return destination. Restore only the current word's temporary.

**Worked solution.** Let `Rcaller` abbreviate `[…, ret(caller), 77]`. Entering the damaged `saved-or-zero` puts `ret(saved-or-zero)` above that prefix:

| Moment | D | R |
|---|---|---|
| Enter word | `[99, 2, 7]` | `Rcaller, ret(saved-or-zero)` |
| After `>r` | `[99, 2]` | `Rcaller, ret(saved-or-zero), 7` |
| After conditional consumes two | `[99]` | `Rcaller, ret(saved-or-zero), 7` |
| Reach damaged early `RET` | `[99]` | Top is seven, not this word's return destination |

The conditional's own slot address has been consumed, so it contributes no surviving entry to hide the seven. The early `RET` would select address seven. This is the first broken return condition; do not invent a valid final result or a particular crash.

Restore the source:

```
: saved-or-zero  >r if, r> exit, then, r> drop [lit] 0 ;
```

On the true path, `r>` changes D to `[99, 7]` and R to `Rcaller, ret(saved-or-zero)`. The early return then consumes that destination, leaving `[99, 7]` and exactly `Rcaller` for the caller.

On the false path, start with `[99, 0, 7]`. `>r` leaves `[99, 0]` and the same parked seven. The conditional consumes zero and skips the true arm. The later `r>` leaves `[99, 7]` and removes the seven from R; `drop` leaves `[99]`; the literal leaves `[99, 0]`. The ordinary final return removes this invocation's return destination, again leaving exactly `Rcaller`.

The caller's 77 remains on both paths. It is below `ret(saved-or-zero)`, and this word neither owns nor needs to retrieve it. Returning with the whole caller prefix preserved is compatible with the caller having its own borrowed temporary.

**Common wrong path.** Adding another `r>` to “empty R” would cross the invocation boundary. The goal is to remove this word's temporaries before its return, not empty the shared return stack.

**Changed case.** Use all-ones flag U, saved value 42, and caller-owned temporary 123 instead of 77. The true branch still runs because U is nonzero. After the repaired word returns, D is `[99, 42]` and the caller's R still ends in 123. None of the reasoning depended on seven, two, or 77 having special bit patterns.

## What to revisit

An address error calls for a memory row with distinct slot and contents. A width error calls for numbered byte positions. A missing runtime count calls for D before and after the conditional. A broken early return calls for R with the current invocation's destination visible. Choose the representation matching the observed error, then retry one changed case with the worked answer closed.

After another chapter, return to S9-02 and S9-05: explain the failure mechanism before repairing it. Correctly repeating the worked layout is useful practice; independently detecting the same kind of error in a changed layout is a separate check.
