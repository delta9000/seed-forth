# 4. The return stack and useful shuffles

[Previous: Bits and subtraction](03-bits-and-subtraction.md) · [Practice help](../practice/04-solutions.md) · [Next: Comparisons and characters](05-comparisons-and-characters.md)

Suppose the data stack is `[7, 3]`, and you need `[7, 3, 7]`. `dup` copies the wrong value: the top is 3. We could move 3 aside, copy 7, then put the values in the required order. Where can we keep 3 while doing that?

The seed has a second stack, the **return stack**. Its main job is to remember where execution should resume after a word finishes. A definition can also borrow space there, but the two uses must coexist. This chapter explains the borrowing rule, derives the library's shuffles, and shows why an apparently harmless helper can read the wrong thing.

By the end, you should be able to trace both stacks, explain why `r@` leaves a temporary in place, construct a deeper copy, and detect a return-stack mistake before claiming a result.

## Choose your route

You need [Chapter 1's](01-values-and-words.md) stack effects, `dup`, `drop`, `swap`, and colon definitions. The optional bitwise application also uses [Chapter 3's](03-bits-and-subtraction.md) `nand`, `and`, and `or`. Memory addresses and machine instructions are not prerequisites.

A quick check: from `[99, 7, 3]`, what does `swap dup` leave? Which value remains underneath the two operations? If the answer `[99, 3, 7, 7]` needs unpacking, revisit the individual contracts in Chapter 1.

If you already use Forth, try S4-01 and S4-03 first. Explain the return destinations as well as the data values. If both explanations hold up, skim the source definitions and try S4-05. Knowing a standard word's name does not settle this seed's call boundary.

**Edition and evidence.** We use the Linux/x86-64 seed at revision `bbcc1732152af2d884737272eed870d2410ffe8e`, the pinned `direct-gcc-overlay` edition. Cells are 64 bits. Every trace here is manually derived from inspected source, not executed output. These are paper studies of definitions, not instructions to experiment with an unbalanced return stack in a running seed.

## Why a call needs a destination

Consider a caller that uses `over` and then continues with another word. Entering `over` must not forget that continuation. A **return destination** is the address of the next instruction to execute in the caller when this call finishes.

In this seed, a native `CALL` puts that destination on the processor's stack, then enters the called code. A native `RET` removes the top return-stack cell and uses it as the next instruction address. A colon definition ends with a `RET` instruction that `;` compiled when the definition was made. The text token `;` is not being interpreted anew each time the word runs.

The data stack has a separate representation: its top value is held in register `rdi`, with deeper values addressed through `rbp`. The return stack uses `rsp`, the processor's stack pointer. You do not need to memorize these register names yet; the consequence matters now: calling a word does not insert its return destination among its data arguments.

Our pictures put the **top at the right on both stacks**. We label them `D` and `R`. A marker such as `ret(over)` means “the destination for returning from this invocation of `over`.” It is a label for an address, not a Forth word or a value we choose.

```text
Just inside over:
D: [7, 3]
R: […, ret(over)]
```

The ellipsis means older entries remain underneath. It does not mean an empty stack. Return destinations and borrowed values occupy the same real return stack; the different notation helps us remember their roles. The hardware does not attach these labels or protect one kind from the other.

## Three contracts, with an ownership condition

At a boundary between words in one executing colon definition, the primitives provide these effects:

| Word | Data-stack effect | Return-stack effect | Job |
|---|---|---|---|
| `>r` | `( x -- )` | `( -- x )` | Move the top data value to the return stack |
| `r>` | `( -- x )` | `( x -- )` | Remove the top borrowed value and put it on the data stack |
| `r@` | `( -- x )` | `( x -- x )` | Copy the top borrowed value onto the data stack |

The return effects describe the borrowed portion, above the current definition's return destination. To use `r>` or `r@` for temporary data, that portion must contain a value belonging to the **current invocation**. Neither word searches past other calls to find a value you meant.

Here is a complete teaching definition, not a library excerpt:

```forth
: saved-copy  >r r@ r> ;
```

Its intended contract is `( x -- x x )`. Rows show states after each completed primitive call, so each primitive's short-lived return destination is omitted here:

| Operation | D | R | Reason |
|---|---|---|---|
| Enter `saved-copy` | `[7]` | `[…, ret(saved-copy)]` | Its caller supplied one value |
| `>r` | `[]` | `[…, ret(saved-copy), 7]` | Move that value aside |
| `r@` | `[7]` | `[…, ret(saved-copy), 7]` | Copy it; the original stays parked |
| `r>` | `[7, 7]` | `[…, ret(saved-copy)]` | Recover the original |
| Definition returns | `[7, 7]` | `[…]` | Consume `ret(saved-copy)` to resume its caller |

The final `r>` is necessary even after `r@`. A copy did not repay the borrowed slot.

The discipline is stronger than counting arrows in a source file: **restore the return stack before each particular colon invocation returns, removing its temporaries in last-in, first-out order**. This is what “balanced within the same dynamic invocation” means. Each call has its own lifetime. You cannot park a value in one definition and leave another definition to collect it after the first has returned.

If a body returns with 7 still above its return destination, its compiled `RET` uses 7 as an instruction address. If `r>` removes a return destination instead of an owned temporary, control state is missing later. The seed provides no guard or rollback for these mistakes. Stop a contract-level trace at the violated condition; do not promise a friendly error, an unchanged stack, or a particular crash.

## How the primitives step around their own calls

There is a detail to reconcile: calling `>r` itself adds a return destination. Why does it not bury the temporary underneath the wrong entry?

The primitive explicitly handles that destination. Zoom in on the first operation of `saved-copy`. Here, unlike the previous table, we include the internal call entry:

```text
Before the call:            R: […, ret(saved-copy)]
CALL >r:                   R: […, ret(saved-copy), ret(>r)]
Save ret(>r) in a register: R: […, ret(saved-copy)]
Push data value 7:         R: […, ret(saved-copy), 7]
Restore ret(>r):           R: […, ret(saved-copy), 7, ret(>r)]
RET from >r:               R: […, ret(saved-copy), 7]
```

The routine also removes 7 from the data stack before returning. `r>` uses the corresponding technique: set aside its own return destination, remove the cell below it into the data stack, restore its destination, and return.

`r@` does not remove the borrowed cell. At entry, its own destination is on top, so it reads **one cell below** that destination. In the source this is `[rsp+8]`: one 8-byte cell past the top address. It copies that value to the data stack, then returns normally.

These are the mechanisms in [`to_r_code`, `r_from_code`, and `r_at_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L107-L145). Their explicit treatment of their own call is why the word-boundary contracts work. They do not skip an arbitrary number of caller destinations.

## Derive `over`: expose, copy, restore, order

The library supplies the operation we wanted:

```forth
: over  >r dup r> swap ;
```

Its contract is `( a b -- a b a )`. We trace the actual body with a lower value, 99, to make preservation visible. As before, the primitive calls have completed at each row.

| Operation | D | R | Why this step is needed |
|---|---|---|---|
| Enter `over` | `[99, 7, 3]` | `[…, ret(over)]` | Copy 7 while preserving 3 |
| `>r` | `[99, 7]` | `[…, ret(over), 3]` | Expose 7 without discarding 3 |
| `dup` | `[99, 7, 7]` | `[…, ret(over), 3]` | Make the required extra copy |
| `r>` | `[99, 7, 7, 3]` | `[…, ret(over)]` | Recover 3 before returning |
| `swap` | `[99, 7, 3, 7]` | `[…, ret(over)]` | Move the new copy above 3 |
| Definition returns | `[99, 7, 3, 7]` | `[…]` | Resume the caller |

The two stacks answer different correctness questions. The data column proves that the requested copy is in the right place. The return column proves that `over` can return with its caller's older entries intact. A correct-looking data result alone is insufficient.

Replace 7 and 3 with `a` and `b` in the table. Nothing depends on their numeric values. We only need two data inputs, enough space, and intact call state. The library definition is at [`010-lib.fth`, `over`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L34-L36).

## Derive `rot`: move the third value to the top

Now the goal is `( a b c -- b c a )`. A single `swap` cannot touch `a` while `b` and `c` are above it. Park `c`, exchange `a` and `b`, then restore `c` and exchange the last pair:

```forth
: rot   >r swap r> swap ;
```

| Operation | D | R |
|---|---|---|
| Enter `rot` | `[99, 7, 3, 5]` | `[…, ret(rot)]` |
| `>r` | `[99, 7, 3]` | `[…, ret(rot), 5]` |
| `swap` | `[99, 3, 7]` | `[…, ret(rot), 5]` |
| `r>` | `[99, 3, 7, 5]` | `[…, ret(rot)]` |
| `swap` | `[99, 3, 5, 7]` | `[…, ret(rot)]` |
| Definition returns | `[99, 3, 5, 7]` | `[…]` |

The first swap moves 7 above 3. Restoring 5 temporarily puts 5 above 7, so the final swap is still needed. The result rotates the top **three** entries; 99 is outside the word's input region and stays put. Compared with `over`, the parked value plays the same role, but the operation performed while it is absent changes from copying to exchanging.

## Three smaller compositions

The library also defines:

```forth
: nip   swap drop ;
: 2dup  over over ;
: 2drop drop drop ;
```

`nip ( a b -- b )` removes the second-from-top value. From `[99, 7, 3]`, `swap` produces `[99, 3, 7]`; `drop` then leaves `[99, 3]`. Dropping first would discard 3, the value we wanted to keep.

`2dup ( a b -- a b a b )` duplicates a pair. Its first `over` gives `[a, b, a]`. The second sees **b** as second-from-top in that new stack, so it gives `[a, b, a, b]`. Each call has its own `ret(over)`, borrows and restores its own slot, then returns to `2dup`. The second call is not retrieving anything parked by the first.

`2drop ( a b -- )` removes the pair: `[99, a, b]` becomes `[99, a]`, then `[99]`. The `2` in these names describes two cells, not a change to the 64-bit cell width. These definitions and `rot` appear in [`010-lib.fth`, stack shuffles](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L139-L153).

## A helper call changes what `r@` sees

Can we package `r@` in this teaching helper and use it to inspect any caller's parked value?

```forth
: copy-saved  r@ ;
```

No. Suppose `owner` has parked 7, then calls `copy-saved`. The return stack at entry to the primitive is:

```text
R: […, ret(owner), 7, ret(copy-saved), ret(r@)]
```

`r@` skips only `ret(r@)`. The next cell is `ret(copy-saved)`, so that address is what it copies. It does not reach 7. Copying the marker does not consume it: the helper can still return, but the data result is an address instead of the intended temporary. The helper's apparent data-stack contract concealed a dependency on call depth.

This does **not** prohibit ordinary calls while a value is parked. A balanced helper such as `over` adds its own destination above the caller's temporary, manages its own temporaries above that, and removes them before returning. The caller's parked value becomes accessible again after the helper returns. What is forbidden by our temporary-storage contract is transferring ownership across definition boundaries or assuming a wrapper preserves direct `r@` access.

## Optional application: preserve operands for XOR

Chapter 3 gave us bitwise operations. XOR sets a bit when exactly one input bit is one. We can compute it as `(a OR b) AND NOT(a AND b)`: OR includes both single-one cases, and the complemented AND removes the double-one case.

Here is an **extra teaching word**, not an existing definition in the pinned library:

```forth
: xor-cell  2dup nand >r or r> and ;
```

Let `U` mean the 64-bit all-ones value from Chapter 3. This trace groups completed library calls by their contracts:

| Operation | D | R |
|---|---|---|
| Enter `xor-cell` | `[12, 10]` | `[…, ret(xor-cell)]` |
| `2dup` | `[12, 10, 12, 10]` | `[…, ret(xor-cell)]` |
| `nand` | `[12, 10, U-8]` | `[…, ret(xor-cell)]` |
| `>r` | `[12, 10]` | `[…, ret(xor-cell), U-8]` |
| `or` | `[14]` | `[…, ret(xor-cell), U-8]` |
| `r>` | `[14, U-8]` | `[…, ret(xor-cell)]` |
| `and` | `[6]` | `[…, ret(xor-cell)]` |
| Definition returns | `[6]` | `[…]` |

The call to `or` is allowed while the mask is parked. Its return destination temporarily sits above the mask, then disappears on return. No helper tries to fetch that mask. For a changed case, equal inputs must give zero: every set bit would otherwise be a double-one case.

## Depth is a construction question

The selected shuffle vocabulary has no depth-indexed `pick` word. That does **not** mean a value below the third cell is unreachable, or that arbitrary-depth `pick` is impossible to construct. Repeated balanced parking can reach a chosen fixed depth; S4-05 asks you to do that. A runtime-selected depth needs additional control machinery, such as an appropriately designed loop or recursive construction, with its own restoration argument. We have not taught that machinery yet.

Keep the claims separate: “not provided here,” “not yet constructed,” and “impossible” are different statements. Neither the small primitive set nor these short definitions establishes the last one.

## Practice

Use paper and the [graduated feedback](../practice/04-solutions.md). Keep both stacks visible whenever a word borrows return-stack space.

### S4-01 — Distinguish copying from recovering

Trace `saved-copy` from data stack `[99, 5]`. Include its return destination. Someone removes the final `r>` because “`r@` already brought the value back.” Identify the last valid state before the definition tries to return, and explain the broken precondition without predicting a crash outcome.

### S4-02 — Complete a rotation

Fill the blanks in `: rot  >r ____ r> ____ ;` for contract `( a b c -- b c a )`. Trace from `[99, 2, 8, 4]` with both stacks. Explain why neither blank can be `dup`.

### S4-03 — Diagnose the helper boundary

An `owner` body performs `>r copy-saved r>`, using the helper above. Starting with `[11]`, what does `copy-saved` add to the data stack? Draw the return stack at entry to its `r@`. Explain why the later `r>` in `owner` still retrieves 11. Repair the body to produce `[11, 11]` without using that helper.

### S4-04 — Construct a related shuffle

Define a teaching word `tuck ( a b -- b a b )` using `swap` and `over`. Then replace `over` with its body to produce a definition using only primitives. Trace both versions from `[99, 2, 9]`; check the primitive version's return-stack balance.

### S4-05 — Copy beyond the third cell

Define `fourth-copy ( a b c d -- a b c d a )` using `>r`, `r>`, `swap`, and the defined `over`. Keep every borrowed value within this invocation. Trace from `[1, 2, 3, 4]`, including the temporary order. Explain why calling `over` while two values are parked is permitted, even though the S4-03 helper fails.

## Check, pause, and continue

If a trace diverges, find the first differing row. Wrong data order calls for labeling positions before each `swap`. A return-stack mismatch calls for labeling which invocation owns each temporary and destination. If S4-03 is unclear, draw the extra helper destination before trying to memorize a rule.

You can stop after `over`: save its state just after `dup`, including both stacks. On return, recover the parked value and finish the shuffle, then try new inputs without that saved trace. If the core exercises are reliable, the optional XOR case offers a different reason to preserve values.

We have learned to rearrange data while keeping the path back to the caller intact. Next, [Comparisons and characters](05-comparisons-and-characters.md) uses ordered operands and bitwise flags to ask questions about values.

## Source boundary

In addition to the linked primitive and library definitions, the call account uses [`compile_call` and `semicolon_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L538-L561); the two-stack representation follows the [register conventions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L53-L61). The compiler's byte emission and full machine-call encoding remain later topics. The [edition record](../../EDITION.md) states the wider evidence limits. No build, seed execution, or source change is claimed here.
