# Return stack and shuffle feedback

Return to [Chapter 4](../chapters/04-return-stack-and-shuffles.md). These are manual derivations under the pinned chapter contract, not seed executions. Both stacks have their top at the right. `D` is the data stack; `R` is the return stack. `ret(name)` labels the return destination for a particular call of `name`, and `…` represents unchanged older return-stack entries.

Use one hint at a time if that helps. After comparing a solution, try its changed case with the solution closed. A copied trace and an independent explanation establish different things about your current performance.

## S4-01 — Distinguish copying from recovering

**Hint 1.** Keep two columns. A new data-stack entry does not by itself tell you whether an entry disappeared from the return stack.

**Hint 2.** `r@` has return effect `( x -- x )`. Only the final `r>` removes the borrowed 5.

**Worked solution.** The teaching definition is `: saved-copy  >r r@ r> ;`. Rows show states after completed primitive calls:

| Operation | D | R |
|---|---|---|
| Enter `saved-copy` | `[99, 5]` | `[…, ret(saved-copy)]` |
| `>r` | `[99]` | `[…, ret(saved-copy), 5]` |
| `r@` | `[99, 5]` | `[…, ret(saved-copy), 5]` |
| `r>` | `[99, 5, 5]` | `[…, ret(saved-copy)]` |
| Definition returns | `[99, 5, 5]` | `[…]` |

99 is outside the word's one-input region. It survives every operation.

If the last `r>` is removed, the state after `r@` is still `D: [99, 5]`, `R: […, ret(saved-copy), 5]`. That is a possible intermediate state inside the definition, but it is not ready for the definition's return. The top return-stack entry is the borrowed value, not `ret(saved-copy)`. The compiled `RET` would take 5 as an instruction address. Stop the valid-return trace there; a particular failure outcome is not part of the word's contract.

**Plausible wrong path.** Treating `r@` as if it moved the value produces an empty borrowed region too early. That confuses “I can use a copy now” with “the stored original has been removed.”

**Changed case.** Consider the paper definition `: saved-sum  >r r@ r@ + r> drop ;` on input `[5]`. Its body states are:

```text
operation     D          R
>r            []         […, ret(saved-sum), 5]
r@            [5]        […, ret(saved-sum), 5]
r@            [5, 5]     […, ret(saved-sum), 5]
+             [10]       […, ret(saved-sum), 5]
r>            [10, 5]    […, ret(saved-sum)]
drop          [10]       […, ret(saved-sum)]
```

Two reads leave the stored value intact until `r>`. The final `drop` discards the recovered original because the sum is already the wanted result. Returning now consumes `ret(saved-sum)` normally. This is an extra teaching construction, not a library definition.

## S4-02 — Complete a rotation

**Hint 1.** After `>r`, the third input is safe for the moment, and the first two are exposed.

**Hint 2.** To turn `[a, b]` into `[b, a]`, exchange them. After retrieving `c`, you still need `a` above it.

**Worked solution.** Both blanks are `swap`:

```forth
: rot  >r swap r> swap ;
```

| Operation | D | R |
|---|---|---|
| Enter `rot` | `[99, 2, 8, 4]` | `[…, ret(rot)]` |
| `>r` | `[99, 2, 8]` | `[…, ret(rot), 4]` |
| `swap` | `[99, 8, 2]` | `[…, ret(rot), 4]` |
| `r>` | `[99, 8, 2, 4]` | `[…, ret(rot)]` |
| `swap` | `[99, 8, 4, 2]` | `[…, ret(rot)]` |
| Definition returns | `[99, 8, 4, 2]` | `[…]` |

`rot` rearranges three cells without changing their number or multiplicity. `dup` would add a copy, and there is no matching discard elsewhere in this body. It cannot replace either exchange while preserving this contract.

**Plausible wrong path.** Stopping at `[99, 8, 2, 4]` after `r>` confuses restoration with final ordering. Recovering 4 places it on top; the last swap is what places 2 there instead.

**Changed case.** Apply `rot` twice to `[99, 2, 8, 4]`, treating each call as its established contract. The first gives `[99, 8, 4, 2]`; the second gives `[99, 4, 2, 8]`. This is the inverse rotation `( a b c -- c a b )`. A third `rot` restores the original order. Each invocation balances its own return stack; the second call does not inherit an unfinished temporary from the first.

## S4-03 — Diagnose the helper boundary

**Hint 1.** Add a destination every time a call begins. There are two calls to account for between `owner` and the instruction inside `r@`.

**Hint 2.** At primitive entry, `r@` reads one cell below `ret(r@)`. Which marker is there?

**Worked solution.** After `owner` executes `>r` on input 11:

```text
D: []
R: […, ret(owner), 11]
```

Calling `copy-saved` and then its `r@` produces:

```text
D: []
R: […, ret(owner), 11, ret(copy-saved), ret(r@)]
```

The primitive skips `ret(r@)` and copies `ret(copy-saved)`. That marker names the address in `owner` immediately after its call to `copy-saved`. It is not the parked 11, nor an address we need to calculate numerically.

After `r@` returns and then `copy-saved` returns, the state is:

```text
D: [ret(copy-saved)]
R: […, ret(owner), 11]
```

Both return destinations were available because `r@` copied rather than removed the marker. Back inside `owner`, the direct `r>` can now recover 11, giving `D: [ret(copy-saved), 11]` and `R: […, ret(owner)]`. The owner can return with intact control state, but it computed the wrong data result.

The repaired body is `>r r@ r>`. With no intermediate colon helper, the primitive's return stack at entry is `[…, ret(owner), 11, ret(r@)]`, so one-cell-below is 11. The body leaves `[11, 11]` and removes its borrowed slot before returning.

**Plausible wrong path.** Imagining that `r@` finds the nearest “user value” grants it a search or type tag it does not have. The source uses a fixed one-cell offset.

**Changed case.** A teaching word `owner-over` has body `>r over r>` and starts with `[2, 9, 11]`. Its direct `>r` parks 11. Calling `over` enters with:

```text
D: [2, 9]
R: […, ret(owner-over), 11, ret(over)]
```

Within `over`, its own `>r` parks 9 above `ret(over)`. It copies 2, restores 9, reorders the data, and returns. At that boundary:

```text
D: [2, 9, 2]
R: […, ret(owner-over), 11]
```

The owner's `r>` now leaves `[2, 9, 2, 11]`. Ordinary balanced helpers are allowed while a value is parked; they must not assume direct access to the caller's borrowed storage.

## S4-04 — Construct a related shuffle

**Hint 1.** `over` repeats the second-from-top value. Put the value you want repeated in that position first.

**Hint 2.** From `[a, b]`, `swap` makes `[b, a]`; `over` can then copy `b`.

**Worked solution.** The composed teaching definition is:

```forth
: tuck  swap over ;
```

Its data trace is `[99, 2, 9] -> [99, 9, 2] -> [99, 9, 2, 9]`. Replacing the `over` call with its body gives:

```forth
: tuck  swap >r dup r> swap ;
```

These are alternative definitions on paper, not two instructions to redefine a live dictionary entry.

| Operation | D | R |
|---|---|---|
| Enter `tuck` | `[99, 2, 9]` | `[…, ret(tuck)]` |
| `swap` | `[99, 9, 2]` | `[…, ret(tuck)]` |
| `>r` | `[99, 9]` | `[…, ret(tuck), 2]` |
| `dup` | `[99, 9, 9]` | `[…, ret(tuck), 2]` |
| `r>` | `[99, 9, 9, 2]` | `[…, ret(tuck)]` |
| `swap` | `[99, 9, 2, 9]` | `[…, ret(tuck)]` |
| Definition returns | `[99, 9, 2, 9]` | `[…]` |

In the composed version, `over` owns the temporary during its invocation. In the expanded version, `tuck` owns it. Both balance storage within the invocation that acquired it. This expansion works because `over`'s entire balanced body is transferred together; it is not a general license to move individual return-stack operations between definitions.

**Plausible wrong path.** Omitting the initial `swap` gives the body of `over`, with output `[99, 2, 9, 2]`. The extra copy is then the wrong input.

**Changed case.** With equal inputs `[5, 5]`, both correct `tuck` and that broken proposal leave `[5, 5, 5]`. Equal inputs hide the order error. A meaningful check needs distinguishable labels or unequal values as well as the equal-input boundary.

## S4-05 — Copy beyond the third cell

**Hint 1.** `over` already knows how to copy the lower of two exposed data values. Move only the values that prevent those two from being exposed.

**Hint 2.** Park `d`, then `c`, leaving `[a, b]`. After `over`, retrieve `c` and swap it below the copied `a`; do the same for `d`.

**Worked solution.** One teaching definition is:

```forth
: fourth-copy  >r >r over r> swap r> swap ;
```

The table treats the complete `over` call as one step, then opens its return-stack behavior below:

| Operation | D | R |
|---|---|---|
| Enter `fourth-copy` | `[1, 2, 3, 4]` | `[…, ret(fourth-copy)]` |
| `>r` | `[1, 2, 3]` | `[…, ret(fourth-copy), 4]` |
| `>r` | `[1, 2]` | `[…, ret(fourth-copy), 4, 3]` |
| `over` | `[1, 2, 1]` | `[…, ret(fourth-copy), 4, 3]` |
| `r>` | `[1, 2, 1, 3]` | `[…, ret(fourth-copy), 4]` |
| `swap` | `[1, 2, 3, 1]` | `[…, ret(fourth-copy), 4]` |
| `r>` | `[1, 2, 3, 1, 4]` | `[…, ret(fourth-copy)]` |
| `swap` | `[1, 2, 3, 4, 1]` | `[…, ret(fourth-copy)]` |
| Definition returns | `[1, 2, 3, 4, 1]` | `[…]` |

Entering `over` adds `ret(over)` above 3. Its direct `>r` parks 2 above that new marker. At the inner parked point, the return stack is:

```text
R: […, ret(fourth-copy), 4, 3, ret(over), 2]
```

`over` retrieves its own 2 and returns through `ret(over)`. Only then does `fourth-copy` retrieve its own 3, followed by its own 4. No return destination is treated as temporary data. S4-03 failed because its helper tried to read a caller-owned value without accounting for the intervening destination; this helper only uses values it parks itself.

**Plausible wrong path.** Assuming that the first `r>` returns 4 overlooks last-in, first-out order. 3 was parked later and is retrieved first. Retrieving both values without the swaps would also leave the new copy buried instead of on top.

**Changed case.** Preserve a lower prefix and include zero: starting with `[99, 0, 6, 7, 8]`, the same word leaves `[99, 0, 6, 7, 8, 0]`. The parked values are 8 and then 7. The copied zero is ordinary data, not a signal that a stack is empty. The lower 99 remains outside the four-input region.

The construction disproves a three-cell access limit. It is still a fixed-depth word: the depth was chosen in its definition. We have not implemented a runtime-indexed `pick` or established resource bounds for one.

## Optional XOR check

For `xor-cell` on equal inputs `[5, 5]`, `2dup nand` leaves `[5, 5, U-5]`. Park the mask; `or` leaves `[5]`; retrieve the mask and apply `and`. A set bit in 5 is clear in `U-5`, so the final result is zero. With `[0, 5]`, the NAND mask is `U`, OR gives 5, and AND with `U` preserves 5. Both checks concern all 64 bits, not a four-bit approximation.

## Decide what to revisit

- If you lost values, check the data effects of individual primitives before expanding a full definition
- If the values are right but return state is wrong, label each destination and each temporary's owner
- If the worked trace is easy but the changed case is not, compare the first changed assumption rather than rereading every section
- If the traces and explanations hold independently, continue to comparisons; revisit a return-stack case after intervening work to check recall

These checks are opportunities to observe what you can do. They are not evidence of learner-tested effectiveness or a guarantee that a program with unexamined inputs is safe.
