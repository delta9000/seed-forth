# Memory updates and writers: hints and solutions

Return to [Chapter 6](../chapters/06-memory-updates-and-writers.md). These are checked paper derivations under its pinned 64-bit seed contracts, not executed observations. Stack tops are at the right. `M=2^64`; invented addresses are valid only in the chapter's disjoint-memory model. Start each exercise from its own reset.

Try the first hint if you need a starting point, the second if one transition is still unclear, or the solution whenever useful. After feedback, close the worked answer before attempting the changed case.

## S6-01 — Complete the cell update

**Hint 1.** `@` consumes the address it reads. Keep another copy for the eventual store.

**Hint 2.** Immediately before the first blank, the stack is `[99, 3000, 3]`. Copy the second-from-top item. At the last blank, you need the store whose width matches the cell fetched by `@`.

**Worked solution.** The blanks are `over` and `!`, producing the actual library definition:

```forth
: +!  swap over @ + swap ! ;
```

| Operation | Data stack after | Counter contents |
|---|---|---:|
| Start | `[99, 3, 3000]` | 7 |
| `swap` | `[99, 3000, 3]` | 7 |
| `over` | `[99, 3000, 3, 3000]` | 7 |
| `@` | `[99, 3000, 3, 7]` | 7 |
| `+` | `[99, 3000, 10]` | 7 |
| `swap` | `[99, 10, 3000]` | 7 |
| `!` | `[99]` | 10 |

In the changed reset, `[99, 1, 3000]` becomes `[99, 3000, 1, 255]` after `swap over @`. Addition leaves `[99, 3000, 256]`; the final `swap !` stores 256 and leaves `[99]`.

The eight bytes at 3000–3007 become `0 1 0 0 0 0 0 0`. If `c!` replaced `!`, only the first byte would change to zero. The second byte, initially zero, would stay zero. The resulting cell would therefore contain zero, not 256. HERE remains 1000 in either paper trace; no cursor word participates.

**Common wrong path.** A correct final stack does not establish a correct memory update. Both store widths consume the same number of stack cells, so you must check the byte row too.

**Changed case.** Add one to a counter containing `M-1`. Full-width addition wraps to zero, so all eight stored bytes become zero. A final `c!` would instead leave `0 255 255 255 255 255 255 255`, retaining stale upper bytes.

## S6-02 — Diagnose the operand roles

**Hint 1.** After the fetch, the stack is `[99, 3000, 4, 7]`. Which of four and seven does `-` subtract from the other?

**Hint 2.** For the separate negation proposal, label the top value's role before executing `negate-cell`. The name of the intended operation cannot change which value is on top.

**Worked solution.** Without the middle `swap`, subtraction computes `4-7`. The cell-sized result is `M-3`, or 18446744073709551613. The remaining `swap !` stores that value at 3000, leaves `[99]`, and writes bytes `253 255 255 255 255 255 255 255`. The address preservation works; the arithmetic operands are reversed.

The separate proposal fails earlier at the level of roles:

| Operation | Data stack after | Meaning |
|---|---|---|
| Start | `[99, 4, 3000]` | Amount, then counter address |
| `negate-cell` | `[99, 4, M-3000]` | Negates the address |
| `swap` | `[99, M-3000, 4]` | Four is now where `+!` expects an address |

Stop before expanding that `+!`: the proposed destination is not valid counter storage in our model. Nothing authorizes a fetch from address four or predicts what a real machine would do there.

A repaired composition is `swap negate-cell swap +!`:

```text
start                [99, 4, 3000]
swap                 [99, 3000, 4]
negate-cell          [99, 3000, M-4]
swap                 [99, M-4, 3000]
+!                   [99]               counter becomes 3
```

The inverse is formed from four. Adding it to seven gives `M+3`, which wraps to three. This teaching composition uses the explicitly defined `negate-cell`; the pinned library's direct `-!` does not depend on that extra word.

**Changed case.** Reset the counter to seven and subtract nine correctly. The result is `M-2`, with signed interpretation -2. Its eight bytes are `254 255 255 255 255 255 255 255`. The helper does not clamp a counter to zero or reject an amount larger than its contents.

## S6-03 — Finish a narrower representation

**Hint 1.** A `c,` consumes its working input. Ask whether the remaining definition still needs that value.

**Hint 2.** The successive quotients for 65536 are 256, one, and zero. A zero low byte is still a byte to write; it does not end the definition.

**Worked solution.** Place `dup` before the first three `c,` calls:

```forth
: ,4
  dup c,
  [lit] 256 / dup c,
  [lit] 256 / dup c,
  [lit] 256 / c, ;
```

These are the source operations with explanatory comments omitted. Each copied value is consumed by `c,`; the retained copy supplies the next division. The last `c,` consumes the final quotient because this writer has completed its four-byte contract.

| Operation or pair | Stack after | Payload write | HERE contents |
|---|---|---|---:|
| Start | `[99, 65536]` | — | 1000 |
| `dup c,` | `[99, 65536]` | 1000 ← 0 | 1001 |
| `[lit] 256 /` | `[99, 256]` | — | 1001 |
| `dup c,` | `[99, 256]` | 1001 ← 0 | 1002 |
| `[lit] 256 /` | `[99, 1]` | — | 1002 |
| `dup c,` | `[99, 1]` | 1002 ← 1 | 1003 |
| `[lit] 256 /` | `[99, 0]` | — | 1003 |
| `c,` | `[99]` | 1003 ← 0 | 1004 |

The full initial eight-byte payload becomes `0 0 1 0 94 95 96 97`; the counter remains seven. The paper decoder returns `1×65536=65536`.

Input 4295032832 equals `2^32+65536`, so it has the same low four bytes. `,4` writes `0 0 1 0` again. Decoding those four bytes cannot distinguish the two inputs: the high contribution was deliberately omitted.

**Common wrong path.** Emitting `1 0 0 0` would treat the third byte's value as though it belonged at the first address. Leading or trailing zeroes have positions and cannot be skipped.

**Changed case.** Use 16777216, or `256^3`. Its bytes are `0 0 0 1`, with the same final cursor 1004 and stack `[99]`. The nonzero contribution has moved by one byte; the writer's width has not changed.

## S6-04 — Keep the original alive

**Hint 1.** Treat `,4` by its contract first: one input consumed, four bytes written. What remains if you did not duplicate the input?

**Hint 2.** An older value may still make an operation mechanically possible. That does not give the word permission to use it as its own working input.

**Worked solution.** Starting from `[99, V]`, a first `,4` without the outer `dup` consumes `V` and leaves `[99]`. HERE is 1004 and the first four payload bytes are `8 7 6 5`. The next `[lit] 256 /` operates on 99 and produces zero. It has consumed the older value it promised to preserve, rather than advancing through the original input's upper half. A nonempty stack has hidden the lost-copy bug.

With the correct definition and input 4294967297, the outer `dup` leaves `[99, 4294967297, 4294967297]`. The first `,4` emits `1 0 0 0` and leaves `[99, 4294967297]`, with HERE 1004. The middle line produces:

```text
[99, 16777216]
[99, 65536]
[99, 256]
[99, 1]
```

The second `,4` emits `1 0 0 0` at 1004–1007 and consumes the remaining one. Final payload: `1 0 0 0 1 0 0 0`; final stack: `[99]`; final HERE contents: 1008; counter: seven.

The decoder gives `1 + 1×256^4 = 4294967297`. Both the low and high halves contribute one, but at different weights.

**Changed case.** Use 4294967296. Only the first payload byte changes: the row is `0 0 0 0 1 0 0 0`. All four low bytes may be zero while the full cell remains nonzero. Zero low bytes do not permit omitting the upper half.

## S6-05 — Read a small record

**Hint 1.** Decide each field's width before choosing its writer. The second field begins at the cursor left by the first.

**Hint 2.** Tag 16909060 displays as hexadecimal `0x01020304`. Count 4294967297 has one in byte positions zero and four. Hexadecimal is a display aid here; supply decimal literals in seed text.

**Worked solution.** On paper, beginning with `[99]` and the specified memory reset:

```forth
[lit] 16909060 ,4 [lit] 4294967297 ,8
```

This is study input for the model, not an execution setup for a live seed.

| Field | Start address | Bytes in increasing address order | HERE after field |
|---|---:|---|---:|
| Tag | 1000 | `4 3 2 1` | 1004 |
| Count | 1004 | `1 0 0 0 1 0 0 0` | 1012 |

The twelve-byte payload is `4 3 2 1 1 0 0 0 1 0 0 0`. Each writer consumes its own value, so `[99]` survives. The counter remains seven; no padding is inserted between the fields.

Decode each field relative to its own start:

- Tag: `4 + 3×256 + 2×65536 + 1×16777216 = 16909060`
- Count: `1 + 1×256^4 = 4294967297`

An `@` from 1000 reads eight bytes, `4 3 2 1 1 0 0 0`. It combines the tag with the first four bytes of the count and returns `16909060 + 4294967296 = 4311876356`. The decoder needs the field contract; the memory-read word does not know where a field ends.

**Common wrong path.** Starting the count at 1008 assumes automatic alignment. Neither `,4` nor `,8` makes that adjustment. Any required padding would have to be an explicit part of a different record contract.

**Changed case.** Reverse the field order, keeping each field's width. The count starts at 1000, the tag at 1008, and HERE still finishes at 1012. An `@` from 1000 now reads the whole count and yields 4294967297. The same fetch can be appropriate or inappropriate depending on the record layout.

## Choose a return check

If an answer differs, compare the first changed stack or byte, not only the final number. For operand mistakes, label amount, address, and old contents. For writer mistakes, keep one column for the working quotient and another for HERE.

After other work or at your next session, try the reversed-field case without its solution, then justify the width of each read. A successful supported trace, a fresh independent trace, and a later return are different observations. These exercises provide ways to check those capabilities; they do not claim that reading the chapter has already established them.
