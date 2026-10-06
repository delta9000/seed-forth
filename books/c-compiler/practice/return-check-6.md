# Return check: where does this path finish?

Try these after C16–C19, with the individual worked examples closed. Use the
pinned legacy direct-ELF profile, fresh builder state where specified, and
valid source and storage within the stated limits. The questions ask for
paper predictions. Keep the builder's next action separate from the
instructions a generated program would execute.

## Questions

### CR6-01

What value does this program predict for `total` when it returns? Trace `r`
and `total` at each loop boundary, rather than guessing from the number of
iterations.

```c
int main(void) {
    int r;
    int total;
    total = 0;
    for (r = 0; r < 4; r = r + 1) {
        switch (r) {
        case 1: continue;
        default: total = total + r;
        }
        total = total + 10;
    }
    return total;
}
```

At `continue`, which generated destination comes next, and who restores the
switch's saved RBX? Now replace only `continue` with `break`. Does that leave
the loop? Predict the changed result before reading the answer.

### CR6-02

A `for` is the last statement of a function. Its body is a single `if`, with
no braces of its own and no `else`:

```c
for (r = 0; r < 3; r = r + 1)
    if (r) total = total + 1;
}
```

The final `}` belongs to the surrounding function; `r` and `total` are valid
previously declared locals. After compiling the assignment, the `if` parser
reads that `}` while looking for an `else`, then puts it back. The reader's
byte cursor is already past the brace.

The `for` parser must now revisit its step expression. Is saving and restoring
only the byte cursor and source limit enough to preserve the function's closing
brace? Give the state needed before replay, during replay, and on return to
the function parser. Do not assign a runtime meaning to the pending-token flag.

### CR6-03

At the end of user-source parsing, consider these function records. The two
list columns contain pending output-field locations, not executable calls in
the builder. The `main` target is valid. Every unshown function record has
empty lists.

| Name | Recorded target | Pending rel32 calls | Pending imm64 addresses |
|---|---:|---|---|
| `main` | nonzero | empty | empty |
| `unused` | 0 | empty | empty |
| `write` | 0 | empty | one field |
| `memset` | 0 | one field | empty |

Using the default late-shim table, which row gains a body during late emission?
Can an address use demand a body even without a call? Which row prevents
successful completion, and why does `unused` not have the same effect?

Finally, remove the `memset` use so its lists are empty too. Is the entry
stub's call to `main` already handled by the two empty lists on the `main`
record, or does it have a separate patching step?

### CR6-04

Start a fresh legacy compilation with this exact source and no added globals,
late-shim uses, or provider changes:

```c
int helper(void) { return 2; }
int main(void) { return 7; }
```

Retrieve these established lengths: the ELF header is 120 bytes, the entry
stub 26, and the eagerly emitted runtime 376. Each of these zero-parameter
constant-return functions has an 11-byte prologue, a seven-byte integer load,
a three-byte result move, a five-byte explicit epilogue, and an eight-byte
implicit-return tail.

Derive the file offsets of `helper` and `main`, the final output cursor, and
the entry call's little-endian rel32 field. The call opcode is at file offset
129 and its four-byte field starts at 130. What remains the ELF entry address?
Which return value reaches the entry stub, and does the unused helper's body
change that prediction?

## Changed cases with the answers closed

Use these for a second attempt after checking the original question.

- CR6-02: replace the single `if` body with a compound statement whose own
  closing brace has been consumed without putback. Which reader state must
  replay restore? Should it always manufacture a pending brace?
- CR6-03: make all pending-use lists empty but leave `cc-main-vaddr` zero.
  Does the function check succeed? Which check decides the outcome?
- CR6-04: move the helper definition after `main`. Which of the file length,
  main address, entry displacement and predicted exit argument change?

## Hints

- CR6-01: `continue` belongs to the loop; `break` belongs to the innermost
  breakable construct. Count the switch saves crossed by each route
- CR6-02: a reader can be physically past a token while still owing that token
  to the next parser
- CR6-03: demand is the union of two kinds of unresolved use. Registration by
  itself is not demand
- CR6-04: emitted source order determines both function positions. The rel32
  base is just after its field, while the ELF entry is the start of the stub

## Worked answers

### CR6-01

The predicted result is **35**, with `r = 4` at loop exit.

| Body-entry `r` | Switch action | Addition after switch | `total` before step |
|---:|---|---|---:|
| 0 | default adds 0 | add 10 | 10 |
| 1 | continue leaves the switch and body | skipped | 10 |
| 2 | default adds 2 | add 10 | 22 |
| 3 | default adds 3 | add 10 | 35 |

The `for` step still executes after `continue`, so `r` advances from 1 to 2.
Jumping straight to the condition instead would keep seeing 1 and would not
implement this `for`.

The loop was entered outside a switch, so its saved switch depth is zero.
At the `continue`, current switch depth is one. The parser emits one POP RBX
before the jump to the loop's step. This route bypasses the switch's ordinary
cleanup, so that cleanup cannot restore the save for it.

With `break` in place of `continue`, the predicted result is **45**. The
innermost breakable construct is the switch. Its break jumps to the common
switch cleanup, which performs the one POP RBX; execution then reaches
`total = total + 10` even when `r` is 1. All four iterations execute that
addition, while the default cases still contribute 0 + 2 + 3. The step and
condition eventually leave `r` at 4 again.

The two routes both restore one saved register, but they do not reach the
same source statement next. A correct cleanup count alone does not establish
a correct destination.

### CR6-02

Saving only cursor and limit is insufficient. Just before replay, the current
token is `}`, the pending flag is true, and the cursor is already after that
brace. The source limit still covers the original function input.

The actual `for` saves the whole eight-cell reader record in a fresh block
and saves source length separately. It temporarily installs the captured
step start and step end as cursor and limit, and clears pending. Clearing it
matters: the next reader operation must read the step, not return the waiting
`}`. Step parsing may replace all the current-token fields and its pending
state.

After step emission, the parser restores the old source length and the saved
reader record. The next read by the function parser therefore returns the
pending `}` without fetching later bytes. The function parser recognizes and
consumes its own closing brace.

Restoring only the old byte cursor after step parsing would not reconstruct
the brace token or its pending status. Reading from that cursor would begin
*after* the brace; the exact later failure would depend on the remaining
input. Nor should the cursor be manually moved backward by one: this is a
saved token contract, not a rule that every token occupies one byte.

Changed case: if the body were a compound statement whose own `}` had been
consumed without putback, the saved pending flag could instead be false.
Restoration must reproduce the actual state, not always manufacture a pending
brace. These are builder reader states; they do not describe whether a target
loop is currently running.

### CR6-03

`write` gains its default shim body. Its pending address field is enough:
late emission tests the OR of the call-list and address-list heads. It records
the body's target, patches both lists with their respective walkers, clears
both heads, and invokes the row's emitter. An empty call list needs no patch,
but the imm64 address field does.

`memset` remains unresolved. The default setup registers its name as an
external prototype, but supplies no late-shim row or body. Its pending call
causes error **206** in the subsequent used-function check. There is no
successful main patch or output-writing conclusion for that stopped path.
`unused` has no pending use, so its target zero alone does not trigger that
check. This is a check for unresolved uses, not a demand that every prototype
acquire a definition.

After removing the `memset` use, all the shown use lists can be empty and the
check can succeed. The entry call still needs `cc-patch-call-main`, which uses
its separately recorded displacement-field offset and `cc-main-vaddr`.
It is not a node on `main`'s ordinary caller list. An empty ordinary list does
not mean that every reference elsewhere in the output is finalized.

Changed case: if all use lists are empty but `cc-main-vaddr` is zero, the
separate main check fails with **207**. It does not silently make the entry
call valid merely because the unresolved-use scan found nothing.

### CR6-04

The fixed prefix occupies `120 + 26 + 376 = 522` bytes. Each function occupies
`11 + 7 + 3 + 5 + 8 = 34` bytes, giving this layout:

| Item | File range, end excluded | Target entry address |
|---|---|---|
| `helper` | [522, 556) | `0x40020A` |
| `main` | [556, 590) | `0x40022C` |

The final output cursor is **590**. With no global data or BSS, finalization
adds no bytes. The low four bytes of `p_filesz` become `4E 02 00 00`; the
minimum `p_memsz` remains 81920.

The call's next instruction is at `130 + 4 = 134`. Its displacement is
`556 − 134 = 422`, so the field stores **`A6 01 00 00`**. The ELF entry remains
**`0x400078`**, the start of the stub, rather than either function's entry.

The stub calls `main`, which returns 7. The stub moves that result to the exit
argument and requests exit 7. The uncalled helper occupies bytes but is not
executed on this path; its return 2 does not replace the main result. Both
implicit-return tails remain emitted even though the explicit return in each
function bypasses its tail.

Changed case: put the helper definition *after* `main`. The file still has
590 bytes, but main now starts at offset 522 and the entry displacement
returns to `522 − 134 = 388`, stored `84 01 00 00`. The execution prediction
remains exit 7. Source order changed an address and its patch, not the chosen
function's result.

These cursor and field calculations describe the predicted output buffer.
They do not establish that the driver's single write attempt delivered a
complete file, or that a generated program was run.

## Find the first wrong turn

If your result differs, identify the first destination, saved reader field,
unresolved-use owner, or output coordinate on which your trace diverges.
Use that chapter's worked example, then retry the changed case with the answer
closed. A correct numeric answer with the wrong next destination deserves
another trace too.

[Back to the volume](../README.md)
