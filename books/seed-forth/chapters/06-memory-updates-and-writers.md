# 6. Memory updates and multi-byte writers

[Previous: Comparisons and characters](05-comparisons-and-characters.md) · [Practice help](../practice/06-solutions.md) · [Edition coverage](../../COVERAGE.md)

A counter contains seven. We want to add three without losing the counter's address. Later, we want to place the number 305419896 into four consecutive bytes. Both jobs combine arithmetic and memory, but their contracts differ: one replaces an existing cell; the other writes a sequence and advances a cursor.

This chapter explains the library words `+!`, `-!`, `,4`, and `,8`. By the end, you should be able to trace their stack and memory changes, locate an operand-order mistake, and decide when decoding emitted bytes can recover the whole original value.

## Choose your route and reset the model

You need [Chapter 2's](02-addresses-and-bytes.md) `@`, `!`, `c!`, `here`, `here-addr`, and `c,`; [Chapter 3's](03-bits-and-subtraction.md) modular subtraction; and [Chapter 4's](04-return-stack-and-shuffles.md) `over ( a b -- a b a )`. Stack tops remain at the right. Cells are 64 bits; addresses count bytes; multi-byte values use little-endian order. All arithmetic inputs shown as seed text use `[lit]` and unsigned decimal digits.

Try two prerequisite checks:

- From `[99, 3, 3000]`, what does `swap over` leave? Which value will `@` then interpret as an address?
- If HERE contains 1000, what does `c,` do with input 300?

The answers are `[99, 3000, 3, 3000]`, then a fetch from 3000; and one stored byte, 44, followed by HERE becoming 1001. If either is uncertain, revisit the linked chapter's trace. If both are secure, inspect the definitions and move to S6-02 through S6-05.

**Evidence boundary.** Definitions below come from the Linux/x86-64 seed at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`. Tables are derived paper traces, not terminal output or seed executions. We trace later calls to existing words, not the memory activity of compiling their definitions.

Use this reset unless a section changes it:

| Object | Model location | Initial contents |
|---|---|---|
| LATEST cell | 2000–2007 | Cell value 1900 |
| HERE cell | 2008–2015 | Cell value 1000 |
| Counter cell | 3000–3007 | Cell value 7 |
| Payload bytes | 1000–1007 | `90 91 92 93 94 95 96 97` |

These are invented locations, **not usable scratch addresses in a running seed**. Assume valid writable storage, enough space, no address wrap, and disjoint counter, payload, system cells, code, and live stack storage. The older stack value 99 must survive each word. “Counter” is a label in our model, not a defined Forth word. Do not enter the model's memory-writing examples into a live session.

## Keep the address while replacing its contents

The actual definition is:

```forth
: +!  swap over @ + swap ! ;
```

Its contract is `( n addr -- )`: add `n` to the eight-byte cell beginning at `addr`, with the usual 64-bit wrap, and consume both inputs. Predict where the result will live before following the trace. It will be stored in memory, not left on top.

| After operation | Data stack | Counter address | Cell value at that address |
|---|---|---:|---:|
| Start | `[99, 3, 3000]` | 3000 | 7 |
| `swap` | `[99, 3000, 3]` | 3000 | 7 |
| `over` | `[99, 3000, 3, 3000]` | 3000 | 7 |
| `@` | `[99, 3000, 3, 7]` | 3000 | 7 |
| `+` | `[99, 3000, 10]` | 3000 | 7 |
| `swap` | `[99, 10, 3000]` | 3000 | 7 |
| `!` | `[99]` | 3000 | 10 |

`@` consumes the address used for the fetch. `over` made a second copy so another address remains below the calculation. The last `swap` arranges the store's required order: value below, destination on top. Until `!`, the new ten exists only on the stack; memory still contains seven.

This is a **read-modify-write**: retrieve the old contents, calculate replacement contents, then store them at the retained address. It does not mean moving the cell itself. The counter's address stays 3000. HERE stays 1000 because this update does not use the cursor.

The final `!` writes eight bytes even though ten fits in one. The counter's byte representation becomes `10 0 0 0 0 0 0 0`. Replacing `!` with `c!` is not a general optimization: adding one to a cell containing 255 should produce bytes `0 1 0 0 0 0 0 0`. A one-byte store would write only the zero and fail to write the carry into the second byte.

## Subtraction exposes operand roles

Reset the counter to seven and change the amount to four. The source says:

```forth
: -!  swap over @ swap - swap ! ;
```

We want old contents minus amount: `7-4`, not `4-7`. Here is every step:

| After operation | Data stack | Counter address | Cell value at that address |
|---|---|---:|---:|
| Start | `[99, 4, 3000]` | 3000 | 7 |
| `swap` | `[99, 3000, 4]` | 3000 | 7 |
| `over` | `[99, 3000, 4, 3000]` | 3000 | 7 |
| `@` | `[99, 3000, 4, 7]` | 3000 | 7 |
| `swap` | `[99, 3000, 7, 4]` | 3000 | 7 |
| `-` | `[99, 3000, 3]` | 3000 | 7 |
| `swap` | `[99, 3, 3000]` | 3000 | 7 |
| `!` | `[99]` | 3000 | 3 |

The middle `swap` puts **the amount four on top**, with the old contents seven immediately below. That is the `( a b -- a-b )` contract. Naming the operands catches a mistake that addition would hide.

A different mistake appears in the older book's suggested `negate swap +!` spelling. Do not assume `negate` is a seed word. To analyze the idea, use the teaching construction from S3-04:

```forth
: negate-cell  dup nand [lit] 1 + ;
```

This forms the modular inverse of its top input. Write `M=2^64`. The proposed `negate-cell swap +!`, starting from `[99, 4, 3000]`, first negates **the address**, producing `[99, 4, M-3000]`. After `swap`, the stack is `[99, M-3000, 4]`. Now `+!` would treat four as an address. Stop: that is outside our valid counter-storage contract. Do not invent a meaningful memory result.

The intended composition is `swap negate-cell swap +!`: expose four, negate four, restore the address to the top. The actual library `-!` already handles the order correctly. This diagnosis corrects an explanation; it does not require changing the source.

## From a cell value to a byte sequence

A cell update uses an explicit destination. A writer instead takes its destination from HERE:

| Word | Input | Payload written | Cursor advance |
|---|---|---|---:|
| `c,` | One cell | Low byte | 1 byte |
| `,4` | One cell | Low four bytes, least significant first | 4 bytes |
| `,8` | One cell | All eight bytes, least significant first | 8 bytes |

Each consumes its input and preserves older stack values. Every internal `c,` writes one payload byte and updates HERE's eight-byte cell. The total affected state therefore includes both the payload and cursor. None of these words checks capacity or allocates more memory.

How can division extract bytes? For an unsigned integer `v`, dividing by 256 discards the lowest base-256 digit. That digit is the low byte. For example, `305419896 = 1193046 × 256 + 120`: write 120, then continue with quotient 1193046. `c,` already keeps only the low byte; no extra mask is needed.

The seed's `/` uses unsigned division. Dividing by 256 therefore moves the next eight bits down and introduces zeros at the high end. This remains the desired operation when a cell's top bit is set. A signed interpretation must not make the writer retain leading one-bits as a signed right shift might. No timing claim is needed: this construction uses existing words rather than adding a shift primitive.

## Four bytes, including every intermediate state

Here is the exact writer definition:

```forth
: ,4
  dup c,                       \ byte 0
  [lit] 256 / dup c,           \ byte 1
  [lit] 256 / dup c,           \ byte 2
  [lit] 256 / c, ;             \ byte 3
```

Reset the model and start with `[99, 305419896]`. Its hexadecimal display is `0x12345678`; that notation makes the four bytes visible, but is **not valid literal input**. The corresponding seed literal is `[lit] 305419896`.

In this table, `/256` abbreviates the two-word sequence `[lit] 256 /`; its temporary literal is shown in the first such step. A dash means no payload write. All byte values are decimal.

| After operation | Data stack | Payload write | HERE contents |
|---|---|---|---:|
| Start | `[99, 305419896]` | — | 1000 |
| `dup` | `[99, 305419896, 305419896]` | — | 1000 |
| `c,` | `[99, 305419896]` | 1000 ← 120 | 1001 |
| `[lit] 256` | `[99, 305419896, 256]` | — | 1001 |
| `/` | `[99, 1193046]` | — | 1001 |
| `dup` | `[99, 1193046, 1193046]` | — | 1001 |
| `c,` | `[99, 1193046]` | 1001 ← 86 | 1002 |
| `/256` | `[99, 4660]` | — | 1002 |
| `dup` | `[99, 4660, 4660]` | — | 1002 |
| `c,` | `[99, 4660]` | 1002 ← 52 | 1003 |
| `/256` | `[99, 18]` | — | 1003 |
| `c,` | `[99]` | 1003 ← 18 | 1004 |

Each early `dup` supplies a disposable copy to `c,`, retaining the value needed for division. The last store needs no copy because no later quotient is needed. The payload row is now `120 86 52 18 94 95 96 97`. Bytes 1004–1007, the counter, and LATEST are unchanged. HERE's contents, stored at 2008, are 1004.

The definition accepts any unsigned 64-bit input, but writes only its low 32 bits. Input 4294967297, which is `2^32+1`, would produce `1 0 0 0`. Decoding those four bytes gives one. That is the promised truncation, not a failed full-width round trip.

## Eight bytes: preserve the original for the upper half

The exact source builds on `,4`:

```forth
: ,8
  dup ,4                                                 \ low 4 bytes
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /        \ shift right 32
  ,4 ;                                                   \ high 4 bytes
```

Reset again. Let `V` stand for decimal 72623859790382856, displayed in hexadecimal as `0x0102030405060708`. `V` is only a table abbreviation, not a Forth name. Valid literal text would be `[lit] 72623859790382856`.

Starting with `[99, V]`, the outer `dup` gives `[99, V, V]`. Expand the first `,4` below. Before each `c,`, the row includes any required division and duplication from that definition:

| Byte destination | Stack immediately before `c,` | Stored byte | Stack after `c,` | HERE after |
|---:|---|---:|---|---:|
| 1000 | `[99, V, V, V]` | 8 | `[99, V, V]` | 1001 |
| 1001 | `[99, V, 283686952306183, 283686952306183]` | 7 | `[99, V, 283686952306183]` | 1002 |
| 1002 | `[99, V, 1108152157446, 1108152157446]` | 6 | `[99, V, 1108152157446]` | 1003 |
| 1003 | `[99, V, 4328719365]` | 5 | `[99, V]` | 1004 |

The retained `V` has not been divided. The first writer consumes its own working copy, leaving the original ready for the middle line:

| After operation | Data stack | HERE contents |
|---|---|---:|
| First `/256` | `[99, 283686952306183]` | 1004 |
| Second `/256` | `[99, 1108152157446]` | 1004 |
| Third `/256` | `[99, 4328719365]` | 1004 |
| Fourth `/256` | `[99, 16909060]` | 1004 |

These divisions write no bytes. Four divisions discard exactly the low four bytes, leaving the original upper half. The final `,4` expands as follows:

| Byte destination | Stack immediately before `c,` | Stored byte | Stack after `c,` | HERE after |
|---:|---|---:|---|---:|
| 1004 | `[99, 16909060, 16909060]` | 4 | `[99, 16909060]` | 1005 |
| 1005 | `[99, 66051, 66051]` | 3 | `[99, 66051]` | 1006 |
| 1006 | `[99, 258, 258]` | 2 | `[99, 258]` | 1007 |
| 1007 | `[99, 1]` | 1 | `[99]` | 1008 |

Final state: payload `8 7 6 5 4 3 2 1`, HERE containing 1008, counter still seven, older stack value 99 intact. Each byte has a destination and a weight; reading the displayed input left-to-right would have produced the opposite byte order.

## Check the representation without inventing a reader word

A paper decoder multiplies each byte by its little-endian weight and adds:

```text
four bytes b0 b1 b2 b3:
b0 + b1×256 + b2×65536 + b3×16777216

our four-byte example:
120 + 86×256 + 52×65536 + 18×16777216 = 305419896
```

For eight bytes, continue the weights through `256^7`; the row `8 7 6 5 4 3 2 1` reconstructs 72623859790382856. A `,4` round trip recovers the whole input only when it fits in 32 unsigned bits. A `,8` round trip can recover every 64-bit cell pattern, given unchanged bytes and the same byte order.

Do not substitute `@` for a four-byte decoder: `@` reads eight bytes, including four neighboring bytes that `,4` did not write. We have not introduced a seed `@4` word. After `,8`, an eight-byte fetch from the remembered original address matches the width; `here @` afterward would instead read at the advanced cursor.

Writers can be composed consecutively: a four-byte field followed by an eight-byte field occupies twelve bytes. There is no automatic padding or alignment between them. The next writer starts wherever the previous writer left HERE.

These bytes may later represent data or parts of instructions. Their writer cannot decide which interpretation is valid, arrange a correct instruction encoding, or cause execution. Those are later contracts. This chapter establishes placement and representation only.

## Practice

Use independent resets and paper traces. The [feedback companion](../practice/06-solutions.md) offers hints, checked derivations, and changed cases.

### S6-01 — Complete the cell update

Fill `: +! swap ____ @ + swap ____ ;`. Trace `[99, 3, 3000]` with counter seven. Then reset the counter to 255 and add one. Give all eight final counter bytes and explain what would go wrong with a final `c!`.

### S6-02 — Diagnose the operand roles

With counter seven and stack `[99, 4, 3000]`, remove only the middle `swap` from `-!`. What value would be stored? Separately, trace the proposed `negate-cell swap +!` only as far as its address error. Repair that composition and justify which input gets negated.

### S6-03 — Finish a narrower representation

Fill each blank with one word:

```forth
: ,4
  ____ c,
  [lit] 256 / ____ c,
  [lit] 256 / ____ c,
  [lit] 256 / c, ;
```

Explain why those positions need copies but the last `c,` does not. Trace input 65536 from `[99, 65536]`, including bytes, final stack, and cursor. Would input 4295032832 produce the same four bytes? Explain before calculating every step.

### S6-04 — Keep the original alive

Remove the first `dup` from `,8`. Starting with `[99, V]`, what remains after its first `,4`, and which value does the next division use? Restore the definition and independently trace input 4294967297 through both four-byte halves. Give all eight bytes and final state.

### S6-05 — Read a small record

An invented record contains a four-byte tag followed by an eight-byte count. Reset HERE to 1000 and provide twelve writable payload bytes, all initially 90. Starting with older stack value 99, emit tag 16909060 and then count 4294967297 using the appropriate writers. Give literal-and-word input, the twelve bytes, each field's start, the final cursor, and the paper-decoded values. Why would one `@` at 1000 not read only the tag?

## Stop and return

If stuck, identify the first disagreement: operand roles, lost copy, byte width, or cursor movement. Rework that one transition with the companion's hint; you do not need to restart the chapter. For a pause, save `[99, V]`, HERE 1004, and payload prefix `8 7 6 5` from the eight-byte trace. On return, predict why four divisions come next before reopening the table.

You can now distinguish updating a cell from emitting its representation, preserve an address or original value when it is needed again, and check byte order against a decoder. After intervening work, use the [mixed return check](../practice/return-check-2.md) to revisit these contracts beside shuffles and comparisons. A later syscall unit is planned; current and unfinished material are listed in [edition coverage](../../COVERAGE.md).

## Source and evidence

The definitions are exact excerpts from [`010-lib.fth`, memory helpers and writers, lines 155–178](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L155-L178). Their dependencies are [`c,` and `here-addr`, lines 12–23](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L12-L23), [`over` and subtraction, lines 34–40](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L34-L40), and the seed's [cell/byte accesses](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L147-L189) and [unsigned division](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L224-L237). The address-order diagnosis addresses the [older Chapter 9](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/09-memory-and-cell-writers.md). All outcomes here are derived, with no source change, build, or seed run claimed. See the [edition record](../../EDITION.md) for scope.

Continue the reading route with [Linux I/O contracts](07-linux-io-contracts.md).
