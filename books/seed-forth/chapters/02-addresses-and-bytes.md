# 2. Addresses, bytes, and a place to write

[Previous: Values and words](01-values-and-words.md) · [Practice help](../practice/02-solutions.md) · [Next: Bits and subtraction](03-bits-and-subtraction.md)

A stack lets one word leave a result for another. Now we want to build a sequence of bytes in memory. If the first byte goes at address 1000, where should the second go? Where do we remember that answer?

We will build toward the library word `c,`, pronounced “c-comma.” It stores one byte and remembers the next available address. To explain it, we need to distinguish three things: a value, an address, and a memory cell containing an address.

By the end, you should be able to trace `c,` through both the stack and memory, explain why it uses two different stores, and diagnose an eight-byte overwrite disguised as a one-byte write.

## Choose your route

This chapter assumes [Chapter 1](01-values-and-words.md): stack top at the right, 64-bit cells, stack effects, and `[lit]` decimal literals. We keep its bracketed stack pictures: `[7, 8]` has 8 on top; `[]` is empty. A quick prerequisite check: starting with `[7]`, `[lit] 8 +` leaves `[15]`; starting with `[7, 8]`, `swap` leaves `[8, 7]`. If either step is unclear, revisit that chapter before adding memory state.

Already comfortable with byte-addressed memory? Try S2-01 and S2-02 first. Correct answers with reasons let you skip to “Build the byte writer.” If you know conventional Forth, still read the `here`/`latest` distinction: these words do not return the same kind of thing in this seed.

**Edition and evidence.** This is the Linux/x86-64 seed at [commit bbcc1732152af2d884737272eed870d2410ffe8e](https://github.com/delta9000/seed-forth/tree/bbcc1732152af2d884737272eed870d2410ffe8e), the pinned `direct-gcc-overlay` edition. Primitive contracts come from inspected source. All traces below are manually derived, not executed observations.

**Paper model only.** Addresses such as 1000 and 2008 are invented teaching locations, not scratch space in a running seed. Do not enter these memory-writing examples into a live session. The code excerpts explain existing definitions; this chapter does not provide a memory-allocation or execution setup.

## A value is not its address

Picture memory as numbered byte locations. An **address** identifies a location; the **value** stored there is what a read retrieves. The distinction resembles a house number and the contents of the house, but memory does not know what its contents mean.

Here is our first illustrative memory row. Addresses increase from left to right. Every number in this row is decimal.

| Address | 1000 | 1001 | 1002 | 1003 | 1004 | 1005 | 1006 | 1007 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Stored byte | 52 | 18 | 0 | 0 | 0 | 0 | 0 | 0 |

The byte **at address 1000** is **52**. Address 1000 does not contain 1000 merely because that is its address. Changing the stored byte to 65 leaves the address itself unchanged.

On the data stack, an address occupies a cell like any other number. Nothing in its bits labels it “address.” A memory-reading word uses its input as an address; `+` uses its inputs for arithmetic. Supplying the wrong kind of value can therefore make a word access the wrong place. The stack notation gives us a contract the machine does not enforce for us.

## One byte, eight bytes, one cell

A **byte** has eight bits and can represent an unsigned value from 0 through 255. A seed **cell** has 64 bits, so a cell-sized memory access spans eight consecutive bytes. Memory addresses count bytes: the next byte after address 1000 is 1001; the next nonoverlapping eight-byte cell after one beginning at 1000 begins at 1008.

Which end of a multi-byte number goes first? This seed uses **little-endian** order: the byte with the smallest numeric weight lives at the lowest address. For a cell beginning at 1000, the first byte contributes its value, the next contributes its value times 256, the next contributes its value times 256 times 256, and so on.

Our row therefore represents the cell value:

```text
52 + 18 × 256 + six zero contributions = 4660
```

Reading eight bytes beginning at 1000 gives 4660. Reading one byte there gives 52. Neither answer moves the bytes around; we chose different widths for the read.

You will also encounter **hexadecimal**, or base sixteen, in source addresses and byte listings. The prefix `0x` marks that notation; digits after 9 are A through F, meaning ten through fifteen. Two hex digits represent one byte. Decimal 52 is `0x34`, decimal 18 is `0x12`, and decimal 4660 is `0x1234`. Its first two stored bytes are consequently `34 12` in a hex listing. Numeric notation and storage order are separate choices. You do not need to memorize these conversions to follow the decimal traces below.

## Four words connect the stack to memory

The seed supplies these contracts. Here `a` means an address, `v` a cell value, and `b` a byte-sized result. Stack top remains at the right.

| Word | Stack effect | Memory effect |
|---|---|---|
| `@` (“fetch”) | `( a -- v )` | Reads eight bytes beginning at `a` as one cell |
| `!` (“store”) | `( v a -- )` | Writes all eight bytes of `v` beginning at `a` |
| `c@` (“c-fetch”) | `( a -- b )` | Reads one byte; returns a cell value from 0 to 255 |
| `c!` (“c-store”) | `( v a -- )` | Writes only the low byte of `v` at `a` |

These are the inspected [`fetch_code`, `store_code`, `cfetch_code`, and `cstore_code` primitives](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L146-L189). A fetch replaces its address on the stack with the fetched value. A store consumes both the value and the address. Neither store leaves a success result.

Notice the order for stores: **value below, address on top**. Starting with stack `[65, 1000]`, `c!` writes 65 at address 1000 and leaves an empty stack. It does not store 1000 at address 65. Any older stack items remain below the consumed pair.

“Low byte” is a width rule. For an unsigned value, it is the remainder after removing whole groups of 256. Thus 300 consists of one group of 256 plus 44; `c!` stores 44 from an input of 300. It does not reject the input or spread 300 over two locations. Meanwhile, `c@` puts the byte into a full stack cell with all higher bits zero.

Compare two **separate resets** of our initial row:

| Paper operation | Bytes afterward at 1000 through 1007 |
|---|---|
| Store 65 with `c!` | `65 18 0 0 0 0 0 0` |
| Store 65 with `!` | `65 0 0 0 0 0 0 0` |

The first changes one byte. The second writes the complete eight-byte representation of 65, destroying the 18 in the next location. A small value does not make `!` a small store.

**Stop/resume point.** You can pause here. Save this sentence: “Addresses count bytes; `@` and `!` access eight, `c@` and `c!` access one.” On returning, redraw the row and predict the two stores before continuing. If the distinction still slips, use S2-01’s first hint rather than carrying uncertainty into the cursor trace.

## Remember the next available address

Repeatedly storing at 1000 overwrites the first byte. We need a changing **cursor**: the address where the next byte should go. The seed keeps this cursor in a cell named **HERE**. Uppercase HERE names the stored system variable; lowercase `here` names a word.

A **system variable**, or sysvar, is memory the seed uses to remember its own state. We need only two here:

- LATEST holds the address of the newest dictionary entry. The dictionary records named words; its entry layout can wait
- HERE holds the current allocation cursor, where the next dictionary bytes will be written

Our illustrative setup assigns these cells the following addresses:

| Cell name | Address of this cell | Value stored in this cell |
|---|---:|---:|
| LATEST | 2000 | 1900 |
| HERE | 2008 | 1000 |

The HERE cell begins at **2008**, but its contents are **1000**. Those contents are themselves an address: the payload location we intend to write next. “Address of a cell” and “address stored in a cell” are two different roles.

The seed's exported words are deliberately worth checking:

- `latest ( -- a )` pushes the **address of the LATEST cell**: 2000 in our model
- `here ( -- a )` pushes the **contents of the HERE cell**: 1000 in our model

Consequently, `latest @` fetches 1900. But `here @` would fetch an eight-byte cell from the payload beginning at 1000. It would not fetch the cursor again. `here` has already fetched that cursor.

The implementation confirms this asymmetry: [`latest_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L495-L504) pushes a fixed sysvar address; [`here_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L362-L371) reads the HERE cell. Similar names are not a substitute for their stack contracts.

## Find the cell we need to update

To advance the cursor we must change the contents of HERE. A store therefore needs the address of the HERE cell, not the current cursor value.

In the pinned seed, HERE follows LATEST immediately. Each occupies eight bytes. The library derives the required address:

```forth
: here-addr  latest [lit] 8 + ;
```

Trace its execution in the illustrative setup:

| After | Stack | Why |
|---|---|---|
| Start | `[]` | No input needed |
| `latest` | `[2000]` | Address of LATEST's cell |
| `[lit] 8` | `[2000, 8]` | Distance to the next cell, in bytes |
| `+` | `[2008]` | Address of HERE's cell |

No memory fetch is needed to find the neighboring cell. Inserting `@` after `latest` would instead fetch 1900 and compute 1908, the wrong address.

For source readers, these are the **actual pinned sysvar locations**, not the illustrative ones:

| System cell | Address in this revision |
|---|---|
| STATE | `0x413000` |
| LATEST | `0x413008` |
| HERE | `0x413010` |

The [`sysvar_init` layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L60-L71) initializes HERE's **contents** to `0x401000`; compiling definitions advances those contents. The table's cell addresses remain fixed in this edition. `here-addr` avoids repeating the numeric address, but still depends on the eight-byte width and LATEST/HERE adjacency. Moving the whole layout together preserves the derivation; changing that adjacency does not.

## Build the byte writer

The full [`010-lib.fth` definition](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L12-L23) is:

```forth
: c,
  here c!
  here-addr @ [lit] 1 + here-addr !
;
```

Its stack effect is `( v -- )`. It writes the low byte of `v` at the old cursor, then advances the cursor by one byte.

We are tracing **a later call to the defined word**, not the act of compiling this definition. Keep the Chapter 1 contract for `: ... ;`; the compiler's own memory writes are a separate mechanism.

Reset the illustrative model. HERE's cell at 2008 contains 1000. Payload bytes at 1000 through 1007 are `90 91 92 93 94 95 96 97`. The input stack is `[77, 65]`; 77 is an older value that this word must preserve.

Before reading the trace, predict two results: the byte at 1000 and the value stored in HERE afterward.

| Step | After executing | Data stack, top right | Byte at 1000 | Byte at 1001 | Cursor stored at 2008 |
|---:|---|---|---:|---:|---:|
| 0 | Start | `[77, 65]` | 90 | 91 | 1000 |
| 1 | `here` | `[77, 65, 1000]` | 90 | 91 | 1000 |
| 2 | `c!` | `[77]` | 65 | 91 | 1000 |
| 3 | `here-addr` | `[77, 2008]` | 65 | 91 | 1000 |
| 4 | `@` | `[77, 1000]` | 65 | 91 | 1000 |
| 5 | `[lit] 1` | `[77, 1000, 1]` | 65 | 91 | 1000 |
| 6 | `+` | `[77, 1001]` | 65 | 91 | 1000 |
| 7 | `here-addr` | `[77, 1001, 2008]` | 65 | 91 | 1000 |
| 8 | `!` | `[77]` | 65 | 91 | 1001 |

At step 2, `c!` consumes both 65 and 1000. Nothing remains that would remember the destination for us. Steps 3–4 retrieve the cursor again through its cell's address. Step 6 computes the next address **on the stack**; the stored cursor is still 1000. Only step 8 writes 1001 back into HERE.

This is a **read-modify-write**: fetch a stored value, calculate its replacement, then store the replacement at the same cell address. The final `!` writes eight bytes because the cursor is a full cell. The earlier `c!` writes one byte because that is the payload width promised by `c,`.

A subsequent call with input 66 uses the new cursor, writes 66 at 1001, and leaves HERE containing 1002. The existing 65 at 1000 survives. Storing bytes in succession is what “emission” means here. `c,` does not output anything to the terminal.

## The invariant and its limits

Let the old cursor be `P`. For a successful call within the intended memory region:

1. The payload byte at `P` becomes the input's low byte
2. Other payload bytes remain unchanged
3. HERE's cell holds `P + 1`
4. The input is consumed; older logical stack items remain

This contract assumes the destination is writable, belongs to the available region, does not overlap live stack storage, code, sysvars, or other reserved state, and advancing the cursor does not wrap the address. The definition contains no capacity or ownership check. Incrementing HERE tracks allocation within an existing region; it does not ask the operating system to supply memory.

Now replace the first `c!` with `!` in the worked trace. The payload becomes `65 0 0 0 0 0 0 0`, but HERE still advances only to 1001. Seven future byte locations have been overwritten. A correct final stack and a correctly incremented cursor would not reveal this error; the payload row does.

Finally, writing bytes is different from executing bytes. These stores change memory. Treating stored bytes as instructions requires a later mechanism to transfer control to them and requires those bytes to encode suitable instructions. Nothing about `c,` alone establishes either condition.

## Practice: explain the changed state

Use paper, a text editor, or spoken traces. Each exercise starts from its own stated reset. Try without the worked answer first if that helps you check yourself; [graduated hints and solutions](../practice/02-solutions.md) remain available whenever needed.

### S2-01 — Read widths, then change one byte

Reset bytes 1000–1007 to `52 18 0 0 0 0 0 0`. What does `c@` return with input 1000? What does `@` return? Now apply `c!` to stack `[300, 1000]`. Give the new eight-byte row and the result of a subsequent cell fetch from 1000. Explain the reduction of 300.

### S2-02 — Which address?

Reset LATEST's cell at 2000 to 1900 and HERE's cell at 2008 to 1000. Give the result of each separate expression: `latest`, `latest @`, `here`, `here-addr`, and `here-addr @`. Why is `latest @ [lit] 8 +` not a replacement for `here-addr`?

### S2-03 — Finish the update

Fill both blanks in this copy of `c,`:

```forth
: c,  here c!  here-addr ___ [lit] 1 + here-addr ___ ;
```

Use the full trace's initial memory and cursor, but start with stack `[77, 511]`. Give the stack immediately before the last blank, the final stack, both first payload bytes, and the final cursor. Explain why the two stores have different widths.

### S2-04 — A plausible wrong repair

Someone changes `here c!` to `here !` while keeping the increment at one. With input 65 and the full trace's reset, identify every changed payload byte. They then propose incrementing by eight instead. Does that restore the original one-byte contract? Explain which requirement remains broken.

### S2-05 — Build a two-byte writer

On paper, define `c2, ( v -- )` for values from 0 through 65535. It must write two bytes in little-endian order and advance HERE by two, using `c,`, `dup`, unsigned `/`, and literals. Trace input 4660 from cursor 1000, including the stack between the two calls to `c,`.

After checking, close the solution and reattempt S2-05 with **256**, without copying the first trace. This tests the zero low-byte boundary. If you emitted the high byte first, return to the memory row; if you lost the value after the first store, inspect `dup`'s role. You may also save this changed case for your next session.

## What you can now account for

You can distinguish where a cell lives from the value it stores, choose a byte or cell access, and follow the two stores that make `c,` work. The result is a small byte-building mechanism with an explicit boundary, not yet an instruction-execution mechanism.

If you stop here, save “HERE at 2008 contains 1001 after writing 65 at 1000.” On resuming, predict where the next byte goes. [Chapter 3](03-bits-and-subtraction.md) changes focus to what can be derived from bit operations; the address/value distinction will remain useful whenever arithmetic updates stored state.
