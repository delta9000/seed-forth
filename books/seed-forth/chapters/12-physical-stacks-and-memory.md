# 12. Physical stacks and memory

[Previous: Executable and entry](11-executable-and-entry.md) · [Practice help](../practice/12-solutions.md) · [Next: Arithmetic in instruction bytes](13-arithmetic-in-instruction-bytes.md)

A logical stack `[7, 3]` contains two values. The seed does not keep both in an ordinary memory stack: 3 is in `rdi`, 7 is in memory, and an extra saved zero sits underneath. That zero is **not** a third logical value. Why is it there, and how can `drop` remove a value without clearing any memory?

One representation rule answers both questions. We will use it to audit ten primitive bodies, connecting every instruction to a state change. By the end, you should be able to reconstruct a logical stack from its registers and live memory, explain the return-address shuffles, and check that a store consumes its operands while preserving older values.

## Choose your route

Bring the [logical stack](01-values-and-words.md), [memory widths](02-addresses-and-bytes.md), [bit notation](03-bits-and-subtraction.md), and [return ownership](04-return-stack-and-shuffles.md) from Chapters 1–4, the literal/call distinction from [Chapter 8](08-defining-words-and-phases.md), and Chapter 11's hexadecimal, instruction notation, and offset-to-address mapping. Intel-style operands put destination first: `mov rdi, [rbp]` reads memory into a register.

Quick check: from `[99, 7, 3]`, `swap drop` leaves `[99, 3]`. A store uses `[value, address]`; `r@` copies a borrowed value but leaves it parked. Revisit the relevant contract if any answer needs unpacking. Experienced readers can attempt S12-01 and S12-04 before deciding which traces to skim.

**Evidence boundary.** We inspect `000-seed.hex0` at [revision bbcc1732152af2d884737272eed870d2410ffe8e](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0). GNU objdump 2.44 independently decoded these exact body ranges from the source-decoded 1,772-byte image, as x86-64 binary in Intel syntax with base `0x400000`. That is a static disassembler observation, not a seed execution. State tables are manual derivations; the ISA references support instruction meanings. Nothing here requires building or running the seed.

## The rule that a primitive must restore

Here “physical” means the registers-and-memory representation; displayed memory addresses are process virtual addresses, not physical RAM locations. Assume enough real operands and usable stack space, intact return destinations, and no accidental writes into live stack storage. The bodies do not enforce these preconditions.

Let `B = 0x411000`, the initial data-stack pointer. At startup, `rbp=B` and `rdi=0`, but the logical data stack is empty. Zero is the **dummy cache value**, not a user-supplied zero. These facts follow from the [startup and register convention](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L53-L65).

At completed word boundaries during valid stack use:

- For a nonempty logical stack, `rdi` holds its top value
- If there is another logical value, `[rbp]` holds that next-deeper value; still older values occupy successive cells at higher addresses
- For a nonempty stack, one saved dummy at `B-8` remains below all real values
- Each logical push subtracts eight from `rbp`; each logical removal adds eight

Thus, with logical depth `n`, `rbp=B-8n`. For `n=1`, `[rbp]` is the saved dummy, **not** another argument. For `n=0`, the cache again contains the dummy and `rbp=B`. This is a derived invariant under valid operations and intact storage. There is no logical-depth counter or guard in these bodies. A physical cell containing zero does not authorize `+` on a one-value stack.

“Below” means older in the logical order. Because physical stack memory grows toward lower addresses, older memory cells have higher addresses. Keep the representations separate:

```text
Logical D, top right:   [7, 3]
Cached top:            rdi = 3

Memory cell address    Contents              Role
B-16 = 0x410FF0         7                     next-deeper value; rbp points here
B-8  = 0x410FF8         0                     saved dummy, outside logical D
```

Memory entries here are eight-byte little-endian cells. The table lists increasing addresses downward; it is not a second top-right stack drawing.

### Derive those two values

A push saves the old cache before replacing it. The [literal implementation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L568-L575) and Chapter 8's generated constant body both use that shape. Below we isolate its **data-stack actions**, omitting literal reading and call bookkeeping:

| Action completed | `rbp` | `rdi` | Memory written |
|---|---|---:|---|
| Startup | `B` | 0, dummy | None by this action |
| Reserve a cell for push 7 | `B-8` | 0 | None |
| Save old cache | `B-8` | 0 | `[B-8]=0`, dummy |
| Install 7 | `B-8` | 7 | None; now `D=[7]` |
| Reserve a cell for push 3 | `B-16` | 7 | None |
| Save old cache | `B-16` | 7 | `[B-16]=7` |
| Install 3 | `B-16` | 3 | None; now `D=[7,3]` |

The invariant describes completed operations, not every intermediate instruction. Reserving space alone has not yet established the new stack. Saving the dummy lets the last valid removal use the ordinary reload shape without a special empty-stack branch.

This is the seed's private convention. It is not the System V function-call ABI, and it does not establish how generated C represents arguments or expressions. `rbp` is a data-stack pointer here because this program uses it that way; the processor does not assign it that job.

## Read one encoding, then reuse the pattern

Source labels distinguish a dictionary header from executable code. We audit only **bodies** here; the later dictionary audit owns the intervening headers. An offset `0x0C7` maps to address `0x4000C7`. In each listing the first column is a hexadecimal **file offset**, not a runtime address. Ranges below include the start and exclude the end.

### `dup`: save the cache without replacing it

[`dup_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L81-L84), `[0x0C7, 0x0D0)`, 9 bytes:

```text
0C7  48 83 ED 08    sub rbp, 8
0CB  48 89 7D 00    mov [rbp+0], rdi
0CF  C3             ret
```

`sub` reserves another cell at the lower address. `mov` fills it with the old top, leaving the same value in `rdi`. `ret` resumes the caller using its saved return destination; it does not pop a data value.

Here is enough decoding to explain the bytes rather than memorize them. A **ModR/M byte** splits into `mod | reg | r/m`, fields of 2, 3, and 3 bits. Depending on the opcode, the middle field selects a register or refines the operation. A **displacement** is an added address offset.

```text
48          REX.W: 64-bit operand size for these instructions
83 ED 08    ED = 11 | 101 | 101: register, subtraction, rbp
            08 is the immediate amount, eight
89 7D 00    89 moves from the register into the register/memory operand
            7D = 01 | 111 | 101: byte displacement, rdi, rbp base
            00 is that displacement: address rbp+0
```

The `48` prefix has W=1 and its register-extension bits R/X/B clear. The zero displacement is part of this encoding: the displacement-free `r/m=101` memory form has a different meaning in 64-bit mode. See Intel's [instruction-format specification, Volume 2A, §§2.1.3 and 2.2.1](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf). You need these selected fields, not the full encoding tables. The short immediate `08` is extended to the operand width; its value stays eight. Pointer arithmetic also changes processor **status flags**, condition bits describing an arithmetic result. The pointer-changing bodies do not preserve incoming arithmetic flags; none of the ten bodies reads them to decide its work. We track data, memory, and control effects here.

From our two-value reset, subtraction gives `rbp=B-24`; the store writes 3 there. `rdi` stays 3, `[B-16]` stays 7, and the dummy stays at `B-8`. The reconstructed logical stack is `[7,3,3]`. Duplication has copied a register into memory, without first reading the old top from memory.

### `drop`: change which cells are live

[`drop_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L91-L94), `[0x0DE, 0x0E7)`, 9 bytes:

```text
0DE  48 8B 7D 00    mov rdi, [rbp+0]
0E2  48 83 C5 08    add rbp, 8
0E6  C3             ret
```

Opcode `8B` reverses the transfer direction of `89`: load the register from the register/memory operand. The address fields remain `7D 00`. In the addition, `C5 = 11 | 000 | 101`; middle field `000` selects addition for opcode `83`.

Apply this body after that `dup`. The load restores 3 from `B-24`; the addition advances `rbp` to `B-16`. Return leaves `[7,3]` again. The discarded slot still contains 3, but is outside the live stack. Moving a boundary need not erase bytes.

Two further valid drops restore 7, then the dummy, ending with `D=[]`, `rbp=B`. A third drop lacks an input. Stop the logical trace there: these bytes contain no underflow check, diagnostic, or safe recovery path.

### `swap`: preserve a value before overwriting its home

[`swap_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L101-L105), `[0x0F5, 0x101)`, 12 bytes:

```text
0F5  48 8B 45 00    mov rax, [rbp+0]
0F9  48 89 7D 00    mov [rbp+0], rdi
0FD  48 89 C7       mov rdi, rax
100  C3             ret
```

`45 = 01 | 000 | 101` selects `rax` instead of `rdi` for the load. `C7 = 11 | 000 | 111` selects register-to-register movement from `rax` to `rdi`. Here `rax` is scratch storage.

Reset to `[7,3]`. First save 7 in `rax`; then overwrite `[B-16]` with 3; finally put the saved 7 into `rdi`. Return leaves `[3,7]`. No pointer moves, so the depth is unchanged. Reversing the first two instructions would lose 7 before saving it.

## The return stack holds control state too

The data representation uses `rbp` and `rdi`. Native `push`, `pop`, `call`, and `ret` instead use **`rsp`**, the processor stack pointer. For the forms here, `push` decreases `rsp` by eight and stores a cell; `pop` loads a cell then increases `rsp` by eight. Their one-byte encodings already select 64-bit registers in this mode. These instruction meanings are specified in Intel's [Volume 2B, PUSH and POP entries](https://cdrdv2-public.intel.com/868141/253667-089-sdm-vol-2b.pdf).

Keep Chapter 4's ownership boundary: an executing colon invocation may borrow slots above its own return destination and must remove them before returning. A primitive's own call temporarily adds another destination above those slots.

### `>r`: put the value under this call's destination

[`to_r_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L112-L118), `[0x10D, 0x119)`, 12 bytes:

```text
10D  58             pop rax
10E  57             push rdi
10F  50             push rax
110  48 8B 7D 00    mov rdi, [rbp+0]
114  48 83 C5 08    add rbp, 8
118  C3             ret
```

Reset `D=[7,3]`. Let `S` be `rsp` before the call, pointing at `ret(owner)`. Return-stack pictures below have top at the right; older entries are omitted with `…`.

| Action completed | `rsp` | Live return stack |
|---|---|---|
| Before call | `S` | `[…, ret(owner)]` |
| `CALL >r` | `S-8` | `[…, ret(owner), ret(>r)]` |
| `pop rax` | `S` | `[…, ret(owner)]`; destination saved in `rax` |
| `push rdi` | `S-8` | `[…, ret(owner), 3]` |
| `push rax` | `S-16` | `[…, ret(owner), 3, ret(>r)]` |
| Reload data cache; advance `rbp` | `S-16` | Unchanged; `rdi=7`, `rbp=B-8` |
| `ret` | `S-8` | `[…, ret(owner), 3]` |

The final two data instructions remove 3 from D, leaving `[7]`. Restoring the destination **above** 3 allows this primitive to return while leaving 3 owned by the still-running caller. Pushing 3 above the destination without that shuffle would make `ret` use 3 as an instruction address.

### `r>`: recover the value without losing the continuation

[`r_from_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L125-L131), `[0x125, 0x131)`, 12 bytes:

```text
125  48 83 ED 08    sub rbp, 8
129  48 89 7D 00    mov [rbp+0], rdi
12D  58             pop rax
12E  5F             pop rdi
12F  50             push rax
130  C3             ret
```

Continue from the preceding result. `CALL r>` puts its destination at `S-16`. The first two instructions reserve `B-16` and save 7 there. The cache can now be replaced safely.

Then `pop rax` removes this call's destination, advancing `rsp` to `S-8`. `pop rdi` retrieves 3 and advances it to `S`. `push rax` restores the destination at `S-8`; `ret` consumes it and restores `rsp=S`. We finish with `D=[7,3]`, `rbp=B-16`, `rdi=3`, and no borrowed slot. Each pop has a different role: continuation first, data second.

### `r@`: skip exactly one destination

[`r_at_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L138-L145), `[0x13D, 0x14E)`, 17 bytes:

```text
13D  48 8B 44 24 08 mov rax, [rsp+8]
142  48 83 ED 08    sub rbp, 8
146  48 89 7D 00    mov [rbp+0], rdi
14A  48 89 C7       mov rdi, rax
14D  C3             ret
```

The new address encoding is `44 24 08`. ModR/M `44` selects `rax`, a byte displacement, and an extra **SIB** addressing byte. SIB means scale/index/base; `24` selects `rsp` as base with no index. The displacement `08` gives `[rsp+8]`. Those fields explain the extra byte compared with `[rbp+0]`.

Instead of executing `r>` after our `>r`, call `r@`. At entry `[rsp]` is `ret(r@)` and `[rsp+8]` is 3. The load copies 3 into `rax`; subtraction and store save the old data top 7; the register move makes 3 the new top. Return consumes only `ret(r@)`. Thus D becomes `[7,3]`, but R still contains the borrowed 3. A later `r>` is still required.

A wrapper changes the picture:

```text
R at entry to r@ inside helper:
[…, ret(owner), 3, ret(helper), ret(r@)]
```

The same `[rsp+8]` now contains `ret(helper)`. `r@` does not search for the caller's temporary. Ordinary balanced helper calls remain possible while 3 is parked; accessing that temporary through a new invocation is the mistake.

## Fetches replace the address in the cache

[`fetch_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L152-L154), `[0x159, 0x15D)`, 4 bytes:

```text
159  48 8B 3F       mov rdi, [rdi]
15C  C3             ret
```

`3F = 00 | 111 | 111` selects destination `rdi` and memory at `rdi`, without a displacement. The address uses the **old** register value; the loaded cell replaces it. No `rbp` adjustment is needed for `( address -- value )`.

For paper memory at address `A` containing hex bytes `34 12 00 00 00 00 00 00`, `[99,A]` becomes `[99,4660]`. The eight-byte load uses little-endian order.

[`cfetch_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L174-L176), `[0x188, 0x18D)`, 5 bytes:

```text
188  48 0F B6 3F    movzx rdi, byte [rdi]
18C  C3             ret
```

`0F B6` selects a byte source with **zero-extension**: copy its eight bits and fill the higher destination bits with zeros. REX.W makes the destination 64 bits, without turning the byte source into an eight-byte read. This distinction follows the [MOVZX entry in Intel Volume 2B](https://cdrdv2-public.intel.com/868141/253667-089-sdm-vol-2b.pdf#page=139).

On the same reset, `c@` gives `[99,52]`; byte `FF` would give 255, not an all-ones 64-bit cell. Both fetches then return normally. Require readable memory of the stated width; neither checks whether the supplied number is a suitable address.

## Stores must restore the older prefix

Assume writable destination `A` is separate from live stacks, code, and reserved state. Our paper stack is `[99,4660,A]`: **value below, address on top**. Its representation is:

```text
rdi=A       rbp=B-24
[B-24]=4660     [B-16]=99     [B-8]=dummy
```

[`store_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L161-L167), `[0x168, 0x17C)`, 20 bytes:

```text
168  48 8B 45 00    mov rax, [rbp+0]
16C  48 89 07       mov [rdi], rax
16F  48 83 C5 08    add rbp, 8
173  48 8B 7D 00    mov rdi, [rbp+0]
177  48 83 C5 08    add rbp, 8
17B  C3             ret
```

In `07 = 00 | 000 | 111`, the source is `rax` and the destination is memory at `rdi`. REX.W plus `89` selects the eight-byte store.

Follow all six instructions:

1. Save 4660 from `B-24` into `rax`; the address remains in `rdi`
2. Write eight bytes at `A`: `34 12 00 00 00 00 00 00`
3. Advance `rbp` to `B-16`, passing the value's old slot
4. Reload 99 into `rdi`, replacing the consumed address
5. Advance `rbp` to `B-8`, since 99 is now cached rather than a deeper memory value
6. Return to the caller, with logical `D=[99]`

The two additions remove two inputs, but neither frees an “address slot”: the address was in `rdi`. One passes the value's memory slot; the other passes the slot whose contents become the new cache. If there were no older logical values, step 4 would load the dummy instead, leaving the empty representation. If the older prefix had several values, only its top would move into the cache; the rest would remain in memory.

[`cstore_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L183-L189), `[0x199, 0x1AC)`, 19 bytes:

```text
199  48 8B 45 00    mov rax, [rbp+0]
19D  88 07          mov byte [rdi], al
19F  48 83 C5 08    add rbp, 8
1A3  48 8B 7D 00    mov rdi, [rbp+0]
1A7  48 83 C5 08    add rbp, 8
1AB  C3             ret
```

Only the store changes. Opcode `88` selects a byte transfer; `al` is the low eight bits of `rax`. The same operand fields still select the destination address in `rdi`. Loading the value, advancing twice, restoring the older top, and returning have exactly the preceding roles.

On a separate reset with input 4660 (`0x1234`), `c!` writes only `34` at `A`; `A+1` onward stays unchanged. With input 300, it writes 44. The discarded high bits do not become extra stack results. A one-byte **memory access** still consumes two full-sized **stack cells**.

## Practice: reconstruct, explain, change one condition

Use paper; `A` below always denotes separate, suitably accessible model memory. The [feedback companion](../practice/12-solutions.md) has graduated hints, worked answers, and changed cases.

### S12-01 — Find the hidden extra cell

From startup, push 5 then 9. Give D, `rbp`, `rdi`, every live memory value, and the dummy's location. Trace `dup drop swap` instruction by instruction. Why is the dummy not a third operand? Continue with valid drops until empty; identify where one more drop first violates the contract.

### S12-02 — Repair a physical push

A proposed push of new value `x` performs `sub rbp,8; mov rdi,x; mov [rbp],rdi`. From `[7,3]`, reconstruct its actual final stack. Reorder the operations to preserve the old top. Explain why `dup` needs no instruction to install a new cache value, and why the `00` in `48 89 7D 00` is not a stored zero.

### S12-03 — Account for both consumed inputs

Reset D to `[88,300,A]`, with eight bytes at A initially all `AA` in hex. Trace each instruction of `c!`, including `rbp`, `rdi`, and destination bytes. Repeat with `!`. What goes wrong if the last `add rbp,8` is omitted? Check the result by applying a subsequent `dup drop` on paper.

### S12-04 — Locate the owned temporary

An `owner` invocation starts with D=`[11]` and performs `>r r@ r>`. Show every primitive's temporary return destination and the final D/R. Explain why `r@` cannot replace the final `r>`. Change the middle action to a helper whose body is `r@`: which value does it copy, and why?

### S12-05 — Transfer between representations

Begin with D=`[42,300,A]`, where A initially holds hex bytes `34 12 00 00 00 00 00 00`. Derive the physical and logical states after `c!`, then a push of A, then `@`. Repeat using `c@` instead of `@`. State which cells remain live, which memory bytes changed, and why zero-extension matters despite all stack cells being 64 bits.

## Check, pause, and continue

All ten bodies total 119 instruction bytes. That count excludes their dictionary headers; it is not a claim about optimal size or speed. We have accounted for each instruction by restoring an invariant: cached top, deeper live memory, and intact return ownership.

If a trace goes wrong, first ask whether the disputed item is a logical value, stale memory, the dummy, or a return destination. Then find the instruction that changed its role. For a pause, save `[7,3]` with `rdi=3`, `rbp=B-16`, `[B-16]=7`, and `[B-8]=dummy`. On returning, explain `swap` without looking at the worked trace.

Next, [Arithmetic in instruction bytes](13-arithmetic-in-instruction-bytes.md) keeps this representation while changing the cached value through calculation. These traces establish a static account of the inspected bytes, not an executed test or evidence of learner mastery.
