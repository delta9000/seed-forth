# Chapter 12: practice help and solutions

[Return to Physical stacks and memory](../chapters/12-physical-stacks-and-memory.md)

These are manual derivations from the inspected primitive bodies, not execution results. Try the first hint before the second if you want less support. Compare your first differing state with the worked answer; a final number alone can hide a misplaced pointer or return destination.

Throughout, `B=0x411000`. D and R have top at the right. Memory expressions denote eight-byte cells unless explicitly called bytes. All payload destinations are separate, valid paper-model memory, not instructions for live writes. A listed post-state is after the named instruction or completed operation.

## S12-01 — Find the hidden extra cell

### Hint 1

The first push saves the startup cache even though that cache is not a logical input. The second push saves the first real value.

### Hint 2

After the two pushes, `rbp=B-16`, not `B-8`. One live memory cell holds 5 and one holds the dummy; 9 is cached. Distinguish this physical count from the two logical values.

### Worked answer

After push 5, `rdi=5`, `rbp=B-8`, and `[B-8]=0`, the dummy. After push 9:

```text
D = [5,9]
rdi = 9
rbp = B-16 = 0x410FF0
[B-16] = 5
[B-8]  = 0, dummy
```

The primitive instructions then act as follows. Each `ret` consumes that primitive's own return destination and leaves the data representation unchanged.

| Instruction | Data state change |
|---|---|
| `dup`: `sub rbp,8` | `rbp=B-24=0x410FE8` |
| `mov [rbp],rdi` | `[B-24]=9`; `rdi` remains 9 |
| `ret` | Completed D=`[5,9,9]` |
| `drop`: `mov rdi,[rbp]` | Load 9 from `B-24` |
| `add rbp,8` | `rbp=B-16`; old `B-24` slot becomes stale |
| `ret` | Completed D=`[5,9]` |
| `swap`: `mov rax,[rbp]` | `rax=5` |
| `mov [rbp],rdi` | `[B-16]=9` |
| `mov rdi,rax` | `rdi=5` |
| `ret` | Completed D=`[9,5]`; `rbp` still `B-16` |

One valid drop loads 9 from `B-16`, then advances `rbp` to `B-8`, leaving `[9]`. The next loads the dummy from `B-8`, then advances to B, leaving `[]`. Their returns do not change these data states.

The next drop has no logical input. Its precondition fails **before** its first instruction. Do not relabel the dummy as an available zero, and do not invent an underflow error message. Old bytes left at smaller addresses are not live stack values either.

### Changed case

Repeat the two-push setup with values **0 then 9**. The real zero resides at `B-16`; the dummy zero remains at `B-8`. `swap` gives `[9,0]`. Equal bit patterns do not make the entries interchangeable: their positions and histories determine which is a logical value.

If your count included the dummy, redraw the physical memory alongside D rather than making one combined stack picture.

## S12-02 — Repair a physical push

### Hint 1

Which instruction is the last chance to preserve the old cache value 3?

### Hint 2

The proposed sequence sets `rdi=x` before saving it. Consequently, the memory store copies x, not 3.

### Worked answer

Starting with `rbp=B-16`, `rdi=3`, `[B-16]=7`, the broken sequence does this:

```text
sub rbp,8          rbp=B-24
mov rdi,x          rdi=x; old 3 is lost
mov [rbp],rdi      [B-24]=x
```

Its completed physical representation is `[7,x,x]`, not `[7,3,x]`. The depth change alone is correct; the values are not. Here `mov rdi,x` names the proposed value installation, without specifying its instruction encoding.

The corrected order is:

```text
sub rbp,8
mov [rbp],rdi
mov rdi,x
```

Now `[B-24]=3`, `[B-16]=7`, and `rdi=x`. The result is `[7,3,x]`. Saving before reserving the new cell would overwrite the existing 7 at `B-16`, so that is not a valid reordering either.

For `dup`, the desired new top equals the old top. Reserving space and saving `rdi` already leaves two representations of that value: one in memory and one still cached. Installing another value is unnecessary for this contract.

In `48 89 7D 00`, `00` is the one-byte **address displacement**. It makes the destination `rbp+0`. The bytes written into that destination come from `rdi`; they are not supplied by this displacement byte.

### Changed case

Use the corrected push with `x=0`, then drop once. It first leaves `[7,3,0]` and then `[7,3]`. A genuine zero can be pushed and removed normally. Being numerically zero does not make it the startup dummy.

If your result preserves the depth but loses 3, track the last location containing each input before checking the final stack count.

## S12-03 — Account for both consumed inputs

### Hint 1

The address is in `rdi`. The value 300 is in memory at `rbp`, and 88 is in the next higher cell.

### Hint 2

After the first pointer addition, `[rbp]` is 88. Once 88 becomes the cached top, its old memory slot must also be passed to avoid counting it twice.

### Worked answer

Initially `rbp=B-24`, `rdi=A`, `[B-24]=300`, `[B-16]=88`, and `[B-8]=dummy`.

| `c!` instruction | Post-state relevant to the operation |
|---|---|
| `mov rax,[rbp]` | `rax=300=0x012C`; `rbp` and `rdi` unchanged |
| `mov byte [rdi],al` | Byte at A becomes `2C`; all seven following bytes remain `AA` |
| `add rbp,8` | `rbp=B-16`; `rdi` still A |
| `mov rdi,[rbp]` | `rdi=88` |
| `add rbp,8` | `rbp=B-8`, pointing at dummy |
| `ret` | D=`[88]`; resume caller |

The final payload row is `2C AA AA AA AA AA AA AA`. `!` follows the same register and pointer transitions, but its second instruction writes the whole cell. From the independent reset it leaves `2C 01 00 00 00 00 00 00`. Both consume two stack inputs and preserve 88.

If the final pointer addition is omitted, `rdi=88` but `rbp=B-16`, where memory still holds 88. The resulting physical representation has the spurious duplicate `[88,88]`. It no longer implements the promised store contract.

A subsequent `dup` reserves `B-24`, writes 88 there, and gives physical `[88,88,88]`. Its following `drop` reloads 88 and returns `rbp` to `B-16`, giving `[88,88]` again. That pair preserves the bad representation; it cannot repair the missing adjustment. One more drop would still leave a logical 88 in that physical reconstruction, where the correct store followed by one drop would be empty.

### Changed case

Give the store an older prefix of two values: `[77,88,300,A]`. Correct completion leaves `[77,88]`, with `rdi=88`, `rbp=B-16`, and `[B-16]=77`. Omitting the final addition leaves `[77,88,88]`. The error duplicates the surviving prefix's top, not necessarily the stored value.

If you described an “address slot” being freed, locate the address before the store: it was in the cache. The second pointer movement passes the reloaded prefix value's old slot.

## S12-04 — Locate the owned temporary

### Hint 1

Mark return destinations separately from data. `ret(owner)` belongs underneath the borrowed 11; each primitive gets its own temporary destination above both.

### Hint 2

`r@` reads one cell past **its own** destination. In a helper, that next cell is the helper's destination.

### Worked answer

Let O mean `ret(owner)`, T mean `ret(>r)`, P mean `ret(r@)`, and F mean `ret(r>)`. These symbols label addresses; none is an extra data argument. Older return-stack cells are omitted with `…`.

```text
Enter owner:                D=[11]       R=[…,O]
CALL >r:                                R=[…,O,T]
pop rax:                    rax=T       R=[…,O]
push rdi:                               R=[…,O,11]
push rax:                               R=[…,O,11,T]
reload dummy; advance rbp:  D=[]         R=[…,O,11,T]
RET from >r:                            R=[…,O,11]

CALL r@:                                R=[…,O,11,P]
load [rsp+8]:               rax=11       R unchanged
reserve; save old cache:    saved dummy  R unchanged
mov rdi,rax:                D=[11]       R unchanged
RET from r@:                            R=[…,O,11]

CALL r>:                                R=[…,O,11,F]
reserve; save old cache:    saved 11     R unchanged
pop rax:                    rax=F       R=[…,O,11]
pop rdi:                    D=[11,11]   R=[…,O]
push rax:                               R=[…,O,F]
RET from r>:                            R=[…,O]
RET from owner:                         R=[…]
```

After the final primitive, `rdi=11`, `rbp=B-16`, `[B-16]=11`, and `[B-8]=dummy`. The invocation can return because its temporary is gone. Omitting `r>` leaves 11 above O; owner's return would treat that 11 as a destination. Copying is not recovering.

With helper body `r@`, let H mean `ret(helper)`. Its primitive sees `R=[…,O,11,H,P]`. It copies H. Its return removes P, the helper's return removes H, and 11 remains owned by owner. Owner's later `r>` retrieves 11, so final D is `[H,11]`, not `[11,11]`. The helper did not consume the borrowed slot, but it produced the wrong data.

### Changed case

Within one owner invocation, start with `[11,22]` and trace `>r >r r@ r> r>`. The parked order becomes `[22,11]` above O. The peek copies 11; the two recoveries retrieve 11 then 22. Final D=`[11,11,22]`, and R again ends at O before owner returns.

If you retrieved 22 first, write the order of parking. If you retrieved a caller's temporary through a helper, draw every intervening destination before reading `[rsp+8]`.

## S12-05 — Transfer between representations

### Hint 1

Follow the memory write and the data-stack removals separately. A later fetch reads the updated bytes, not the original row.

### Hint 2

The low byte of 300 is 44 (`2C`). The byte at `A+1` remains `12`, decimal 18. A cell fetch includes that second byte; a byte fetch does not.

### Worked answer

Initially D=`[42,300,A]`, `rbp=B-24`, `rdi=A`, `[B-24]=300`, `[B-16]=42`, `[B-8]=dummy`.

After `c!`:

```text
D=[42]                rdi=42             rbp=B-8
live memory:          [B-8]=dummy
payload at A:         2C 12 00 00 00 00 00 00
```

The old 300 and saved 42 remain as stale memory below `rbp`; they are not logical values. Pushing A reserves `B-16`, writes cached 42 there, and installs A:

```text
D=[42,A]              rdi=A              rbp=B-16
live memory:          [B-16]=42; [B-8]=dummy
```

`@` reads eight bytes, giving `44 + 18×256 = 4652`, hexadecimal `0x122C`. It replaces A in `rdi`; neither `rbp` nor the deeper 42 changes. Final D=`[42,4652]`.

On the separate `c@` branch, the one-byte read obtains 44 and zero-extends it into the full cache, leaving `[42,44]`. A full-width destination does not imply a full-width memory access. Clearing its higher bits ensures the result contains only the byte's unsigned value, with no residue from the old address or sign-extension.

### Changed case

Reset the original row and use input **511** instead of 300. `c!` writes `FF`, leaving `FF 12 00 00 00 00 00 00`. The cell-fetch branch returns `0x12FF=4863`; the byte-fetch branch returns 255. Its high bit is one, but `c@` still clears the upper 56 bits.

If the two fetches seemed equivalent, calculate the contribution of the byte at `A+1`. If the deeper 42 disappeared, inspect which operation was allowed to overwrite its live slot.

## Decide what to revisit

- A dummy or stale-byte mistake: reconstruct S12-01 from startup
- A correct count with a lost value: inspect save-before-replace in S12-02
- An extra surviving value: track both store pointer adjustments in S12-03
- A correct D but unsafe return: label invocation ownership in S12-04
- A wrong fetched number: redraw the byte row in S12-05 before interpreting it

Close the answer and attempt one changed case independently. A corrected trace with support is progress; an independent explanation provides different evidence. Neither this solution set nor a static byte audit is a learner study.
