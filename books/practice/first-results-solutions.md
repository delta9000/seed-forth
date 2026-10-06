# Two small results: hints and feedback

Return to [the entrance and prompts](../FIRST-RESULTS.md#try-a-change).
Use only as much help as you need. A successful attempt after a hint is useful
practice; a later attempt with feedback closed answers a different question.

## H1-01 — Keep the older value

### Hints

1. `dup` changes only the top end; label 99 as the older value
2. Each `+` consumes two values, then returns one
3. Just before `emit`, the stack is `[99, 65]`. Its contract consumes 65

### Worked answer

| After | Stack |
|---|---|
| `dup` | `[99, 32, 32]` |
| `+` | `[99, 64]` |
| `[lit] 1` | `[99, 64, 1]` |
| `+` | `[99, 65]` |
| `emit` | `[99]` |

The output request is one byte with value 65, ASCII `A`. The successful-output
assumption is needed to claim that it arrived. In the returning `emit` path,
the cleanup recovers the older top regardless of the write result. Seeing
`[99]` therefore cannot establish successful output.

If your answer printed `65`, distinguish the numeric value from a decimal
representation made of two character bytes. `emit` does not perform that
number-to-text conversion. If 99 vanished, find which row consumed it: none
of the required operations did.

**Changed reattempt:** stop immediately before `emit`. What is present on the
stack, what output has this sequence requested so far, and what would `bye`
do next? The target distinction is stored state versus external action.

## H1-02 — Send the result to memory

### Hints

1. Keep the value and address in separate columns even though both are numbers
2. `[lit] 1000` gives `[99, 65, 1000]`
3. `c!` consumes the last two entries and changes one addressed byte

### Worked answer

The final stack is `[99]`. The memory bytes at 999, 1000 and 1001 become
10, 65 and 30. Only the middle byte changes. There is no output request:
writing memory is the destination selected by this operation.

An answer that writes 1000 into address 65 has reversed the inputs. An answer
that changes eight bytes has used the cell-store idea rather than the
specified byte-store contract. This exercise grants ownership of address
1000; the operation itself does not check or grant that ownership.

**Changed reattempt:** supply value 321 at the same valid address. Using the
stated low-byte rule, explain why the stored byte is again 65 and why the
neighboring bytes must still be unchanged. Recall that 321 = 256 + 65.

## H2-01 — Find the unfinished use

### Hints

1. Each next-unused offset is the previous offset plus the new region's length
2. A four-byte field beginning at 130 occupies offsets 130 through 133
3. Its next instruction is at 134, not at the start of the call's opcode

### Worked answer

The next-unused offsets are 120, 146, 522 and 556. The field calculation is
`522 - (130 + 4) = 388`. The builder changes the contents of four already
reserved bytes. It appends none, so the final length remains 556.

If you obtained 392, you subtracted the field's start instead of its end. If
you obtained 560, you treated an overwrite as an append. These are different
mistakes, even if both are described informally as “an offset error.”

**Changed reattempt:** keep the destination at 522 but stipulate that this
kind of field starts at 150. Derive its four-byte displacement and state
which supplied fact changed. This is an illustrative location exercise,
not a claim that our original stub has been re-encoded that way.

## H2-02 — Move a body, keep the result

### Hints

1. The helper is a user body, so it comes after the supplied runtime prefix
2. If it comes first, add 34 to `main`'s starting offset
3. The entry stub and its four-byte field have not moved

### Worked answer

With the helper before `main`:

| Quantity | New value | Reason |
|---|---:|---|
| Entry-stub start offset | 120 | Earlier headers and stub are unchanged |
| `main` offset | 556 | `522 + 34` |
| Total size | 590 | `556 + 34` |
| Call displacement | 422 | `556 - 134` |
| Specified `main` result | 7 | Its body still returns seven |

Putting the helper after `main` keeps `main` at 522 and the displacement at
388. The total remains 590 because both bodies are still emitted. Being
unused does not make a body disappear in this profile.

The two placements show why total file size cannot identify a call target.
They have equal lengths but different relevant layouts. All resulting
execution claims retain the entrance's successful-write/load/exit assumptions.

**Changed reattempt:** use a helper of supplied length L and give the two
layout formulas without choosing a number. State which expression depends
on body order, and which depends only on the added length. Explain the
reason before doing arithmetic.

## What an independent explanation should contain

A good explanation names the state being changed, applies the correct
operation, and identifies the next consumer of the result. The arithmetic
alone is insufficient if it belongs to the wrong process, location or time.

If an attempt stalls, use the relevant contract or one completed intermediate
row, then try a changed case with feedback closed. These prompts check
specific explanations. They do not certify the whole Forth seed, compiler
implementation or bootstrapping route.

## Check after a changed reattempt

Use these after making the changed attempt, rather than as its starting row.

- **H1-01:** just before `emit`, the stack is `[99, 65]` and the calculation
  has requested no output. Replacing `emit` with `bye` requests exit status
  zero; it prints neither number
- **H1-02:** 321 leaves remainder 65 after one complete group of 256. Only
  address 1000 changes to 65; neighboring bytes stay 10 and 30. With the same
  older stack prefix, 99 survives
- **H2-01:** `522 - (150 + 4) = 368`. Moving the field changes its end, the
  reference point for the displacement; the supplied destination stays 522
- **H2-02:** before `main`, the helper gives `main=522+L`, size `556+L`, and
  displacement `388+L`. After `main`, it gives `main=522`, size `556+L`, and
  displacement 388. The entry-stub start remains 120 and the specified
  result remains seven. These formulas assume the same valid, nonwrapping
  layout and capacity conditions; they do not establish an arbitrary helper's
  accepted syntax or actual emitted length
