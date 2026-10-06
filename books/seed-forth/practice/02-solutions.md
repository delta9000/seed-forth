# Chapter 2 practice: hints and checked solutions

[Return to the chapter](../chapters/02-addresses-and-bytes.md#practice-explain-the-changed-state)

These answers are checked by manual derivation from the pinned seed contracts. They are not execution results. All numeric addresses below belong to the illustrative paper model. Do not use them as live memory destinations.

You can choose a hint or go directly to a solution. For a useful self-check, compare the first differing intermediate state, not only the final number. Correct work with a hint is useful supported practice; a fresh changed case without the solution checks something different.

## S2-01 — Read widths, then change one byte

### Hints

1. A byte fetch and a cell fetch begin at the same address but read different amounts of memory
2. The second byte contributes its value times 256 to a little-endian cell
3. Split 300 into one whole group of 256 and what remains. Only the remainder is stored by `c!`

### Solution

`c@` returns 52. `@` returns `52 + 18 × 256 = 4660`.

The stack `[300, 1000]` puts the destination on top. `c!` consumes both items and stores 44, because `300 = 256 + 44`. The row becomes:

```text
Address: 1000 1001 1002 1003 1004 1005 1006 1007
Byte:      44   18    0    0    0    0    0    0
```

A subsequent cell fetch returns `44 + 18 × 256 = 4652`.

**Check:** the address remains 1000; the next byte remains 18. If your answer was 44 for the cell fetch, you used the byte width. If your answer was 300, you assumed a one-byte store preserves a value that needs two bytes.

## S2-02 — Which address?

### Hints

1. Label each number by its role before calculating: sysvar cell address, dictionary entry address, or payload cursor
2. `latest` returns a cell's address; `here` has already read its cell
3. From stack `[2000]`, `@` produces 1900. Adding eight afterward therefore starts from 1900

### Solution

| Separate expression | Result | Meaning |
|---|---:|---|
| `latest` | 2000 | Address of the LATEST cell |
| `latest @` | 1900 | Address stored in LATEST, naming the newest entry |
| `here` | 1000 | Cursor stored in HERE |
| `here-addr` | 2008 | Address of the HERE cell |
| `here-addr @` | 1000 | Cursor fetched through the HERE cell's address |

`latest @ [lit] 8 +` computes `1900 + 8 = 1908`. It finds a location eight bytes after the dictionary entry's start. The required derivation is `2000 + 8 = 2008`, using the sysvar cell's address without fetching its contents.

**Check:** both `here` and `here-addr @` return 1000; `here-addr` alone does not. If those three results were identical, revisit the distinction between the two columns in the chapter's sysvar table.

## S2-03 — Finish the update

### Hints

1. What turns a cell address into its stored value? What replaces a cell's contents?
2. Immediately before the final operation, the desired new cursor must be below the HERE cell's address
3. The partial stack after `here-addr @` is `[77, 1000]`, because the input 511 was already consumed by `c!`

### Solution

The blanks are `@` and `!`:

```forth
: c,  here c!  here-addr @ [lit] 1 + here-addr ! ;
```

The complete logical stack trace for this input is:

| After | Stack |
|---|---|
| Start | `[77, 511]` |
| `here` | `[77, 511, 1000]` |
| `c!` | `[77]` |
| `here-addr` | `[77, 2008]` |
| `@` | `[77, 1000]` |
| `[lit] 1` | `[77, 1000, 1]` |
| `+` | `[77, 1001]` |
| `here-addr` | `[77, 1001, 2008]` |
| `!` | `[77]` |

The first payload byte becomes 255 because `511 = 256 + 255`. The next byte stays 91. The cursor stored at 2008 becomes 1001. The stack immediately before the final blank is `[77, 1001, 2008]`; afterward it is `[77]`.

The first store writes a one-byte payload. The final store writes a cell-sized cursor. Replacing the final `!` with `c!` would update only the first of the cursor's eight bytes. It can appear to work when the higher bytes happen to stay the same, so one successful small increment would not establish the general contract.

**Changed check, if needed:** reset the cursor to 1023 and consider advancing it to 1024. In little-endian bytes, the old cursor begins `255 3`, while the new one must begin `0 4`. A byte-only update would leave `0 3`, which represents 768. This boundary explains why the full-cell store is necessary. The addresses remain illustrative.

## S2-04 — A plausible wrong repair

### Hints

1. The width of the store comes from the word, not the size of the value
2. Write the eight-byte representation of 65 over the entire initial row
3. Changing the cursor afterward cannot undo those already written bytes

### Solution

The initial bytes are `90 91 92 93 94 95 96 97`. The mistaken `!` produces `65 0 0 0 0 0 0 0` at addresses 1000 through 1007. All eight bytes differ from their initial values:

- Address 1000 changes from 90 to 65
- Addresses 1001 through 1007 change from 91–97 respectively to zero

With the original increment, HERE becomes 1001 and points into the just-overwritten region. With an increment of eight, HERE would become 1008. That change creates a cell-sized writer's movement, but does not restore `c,`'s one-byte contract: seven additional payload bytes still change, and the cursor advances by eight rather than one.

**Check:** “the final stack is correct” is insufficient. The acceptance criteria include payload width and cursor movement as well as the stack. A cell writer can be useful, but it is a different operation that should have its own contract.

## S2-05 — Build a two-byte writer

### Hints

1. `c,` already takes the low byte. The problem is retaining the value long enough to obtain the next byte
2. Use `dup` before the first `c,`. Dividing the surviving unsigned value by 256 removes the low-byte remainder
3. Starting from 4660, `dup c,` leaves 4660 on the stack and writes 52. Dividing the surviving value by 256 gives 18

### Solution

One definition satisfying the stated two-byte contract is:

```forth
: c2,  dup c, [lit] 256 / c, ;
```

This is a paper construction using the existing `c,`; no source file was changed and the definition was not executed.

| After | Stack | Newly written byte | Cursor |
|---|---|---|---:|
| Start | `[4660]` | None | 1000 |
| `dup` | `[4660, 4660]` | None | 1000 |
| First `c,` | `[4660]` | 52 at 1000 | 1001 |
| `[lit] 256` | `[4660, 256]` | None | 1001 |
| `/` | `[18]` | None | 1001 |
| Second `c,` | `[]` | 18 at 1001 | 1002 |

The first call consumes the duplicate, preserving the original for division. The second call consumes the quotient. The final order is `52 18`, the low byte first. Older stack items, if present, would survive unchanged. Payload bytes beyond the two destinations remain unchanged under `c,`'s preconditions.

For the changed-case reattempt, attempt **256** before reading further.

### Changed-case answer: 256

`dup` produces `[256, 256]`; the first `c,` writes 0 and leaves `[256]`. Division by 256 leaves `[1]`, and the second `c,` writes 1. From initial cursor 1000 the final bytes are `0 1`, the final cursor is 1002, and the input is consumed.

Zero is still a byte to write. Omitting it would shift the position and meaning of the following byte. Reading these two bytes as a little-endian value gives `0 + 1 × 256 = 256`.

**Acceptance criteria:** two stores, low byte first, cursor advanced by two, input consumed, older stack items preserved. Values from 0 through 65535 fit in two bytes. The same construction on larger values would retain only their low two bytes; claiming an exact round trip for them would exceed this exercise's contract.

## Decide what to revisit

- Wrong read size or truncated-value reasoning: return to “Four words connect the stack to memory,” then retry S2-01 with 257 instead of 300. The stored low byte should be 1
- Correct arithmetic, wrong address: redraw the sysvar table and retry S2-02 before rereading the full writer
- Correct individual operations, lost overall state: retain the chapter's three-column state record for stack, payload, and cursor
- Correct independent trace and changed case: move to [Chapter 3](../chapters/03-bits-and-subtraction.md). You can revisit the construction later with the solution closed; immediate success is not yet evidence of delayed retention

If you pause, save the exercise ID, initial state, and first uncertain step. That gives you a concrete place to resume without reconstructing the whole chapter.
