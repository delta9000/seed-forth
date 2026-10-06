# C09 practice: hints and checked solutions

[Return to the chapter](../chapters/09-instructions-inside-an-executable.md#practice-bytes-state-and-boundaries)

These are manually checked byte/state derivations from the pinned [080 executable emitter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/080-cc-elf.fth) and [090 instruction emitters](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth). They are not compiler-output observations or execution tests. The chapter's valid-memory, bounded-input, and profile assumptions apply. Byte strings below are manual compositions, with lower-address bytes first; logical stack top is at the right.

Try the exercise before opening its solution if that serves your goal. Use as much help as you need. The changed-case answers are separated at the end so a retry can begin from the answer-free prompts in the chapter. Correct results should include the stated reasoning; accidental agreement on one number is insufficient to diagnose a wrong coordinate or width.

## C9-01 — Reconstruct the subtraction

### Hints

1. Keep two worksheets: the builder's byte count and the future machine's state. Advancing the first does not advance RSP
2. Add each complete instruction's length to obtain the next start. A PUSH here is one instruction byte but transfers eight target bytes
3. Immediately before SUB, RDI must be the left operand and RCX the right. Identify which instruction would overwrite each one

### Checked solution

The builder starts at output offset 1024 and ends at 1047. The seven starts and target addresses are:

| Instruction | File offset | Target address | Length |
|---|---:|---|---:|
| Load slot 0 | 1024 | `0x400400` | 4 |
| PUSH RDI | 1028 | `0x400404` | 1 |
| Load immediate 1 | 1029 | `0x400405` | 7 |
| MOV RCX,RDI | 1036 | `0x40040C` | 3 |
| POP RDI | 1039 | `0x40040F` | 1 |
| SUB RDI,RCX | 1040 | `0x400410` | 3 |
| Store slot 0 | 1043 | `0x400413` | 4 |

The target state after each instruction is:

| Step | RDI | RCX | RSP | `[P-8]` | Live temporary owned by this fragment |
|---|---:|---:|---|---:|---|
| Load | 2 | Irrelevant | S | 2 | None |
| PUSH | 2 | Irrelevant | S−8 | 2 | 2 at S−8 |
| Immediate | 1 | Irrelevant | S−8 | 2 | 2 at S−8 |
| Move right | 1 | 1 | S−8 | 2 | 2 at S−8 |
| POP | 2 | 1 | S | 2 | None |
| SUB | 1 | 1 | S | 2 | None |
| Store | 1 | 1 | S | 1 | None |

Reversing the move-right and pop steps first replaces RDI=1 with saved 2, then copies 2 into RCX. SUB would calculate 2−2=0. The error is a destroyed right operand, not a backward subtraction opcode. The stale two at S−8 after POP is not a live extra expression value.

Adding lengths gives 23. RSP's net change is zero, independent of that byte count. A solution that increments RSP by 23 confuses instruction-storage extent with the stack effect of executing the instructions.

## C9-02 — Cross the addressing boundary

### Hints

1. Calculate `−8*(slot+1)` before choosing its stored representation
2. A signed byte includes −128. For a wider displacement, change `mod=01` to `mod=10`, retaining the operand fields
3. Slot 16's displacement is −136. Its four-byte representation is `2^32−136`, written little-endian

### Checked solution

Slot 15 gives −128. Load bytes are `48 8B 7D 80`; store bytes are `48 89 7D 80`. Here `7D = 01|111|101`: disp8 memory, RDI register, RBP base. The displacement byte 80 has unsigned value 128 but signed value −128.

Slot 16 gives −136, or 32-bit pattern FFFFFF78. Load bytes are `48 8B BD 78 FF FF FF`; store bytes are `48 89 BD 78 FF FF FF`. `BD = 10|111|101` selects disp32. Both instructions grow by three bytes. The full fragment therefore grows from 23 to 29 bytes. The memory access remains a qword; no C value became wider.

Slot −3 gives `−8*(−2)=+16`: load `48 8B 7D 10`, store `48 89 7D 10`. It passes the emitter's exact `−16 <= slot < 16` predicate. That arithmetic says where the instruction would access; it does not establish an allocated legacy local. Default local allocation uses nonnegative slots 0–31 and a separate capacity check.

A common wrong answer uses `7D 78` for slot 16. Signed byte 78 is positive 120, so it would access P+120. Retaining only the low byte without selecting the wider addressing form loses the intended sign and magnitude.

## C9-03 — Repair a condition value

### Hints

1. AL is only the low byte of RAX. Write the full sixteen hexadecimal digits after SETL
2. The real sequence clears RAX before CMP. CMP then replaces the flags created by XOR
3. C's comparison produces 0 or 1 in a full register; a nonzero value is not necessarily the canonical result

### Checked solution

With incoming RAX=`0x100` and the XOR omitted:

| Comparison | SETL result in AL | Whole RAX after SETL | Final RDI |
|---|---:|---|---:|
| `2 < 3` | 1 | `0x0000000000000101` | 257 |
| `3 < 2` | 0 | `0x0000000000000100` | 256 |

The second case is especially revealing: a false comparison leaves a nonzero expression value. The high bit at position eight survives a byte write. The real preceding XOR clears that bit and every other high bit, so the full results are 1 and 0.

Moving XOR between CMP and SETL is not equivalent. XOR RAX,RAX sets ZF=1, SF=0, OF=0 and CF=0; SETL would now see SF=OF and produce zero, regardless of the comparison's previous signed-order result. Repair the producer/consumer ordering, not merely the high bits.

Canonical true is 1 in the generated C comparison and all-ones/−1 in the builder's Forth boolean convention. Both count as true to a nonzero test, but `1 AND 8` differs from all-ones AND 8. The conventions cannot be interchanged as bit masks.

## C9-04 — Locate the branch field

### Hints

1. JZ has a two-byte opcode followed by its four-byte operand
2. The returned offset is the start of the operand. Add four to find the CPU's relative reference point
3. A patch overwrites bytes; it does not move the output cursor backward or append a second instruction

### Checked solution

JZ starts at 600, its field starts at 602, and its next instruction corresponds to offset 606. The displacement is `625−606=19`, hexadecimal 13. Its complete bytes become `0F 84 13 00 00 00`. Target virtual address is `0x400000+625=0x400271`. The builder position remains 625 after patching.

Subtracting the **opcode start** yields 25. Encoding that displacement makes the CPU go to 606+25=631 (`0x400277`), six bytes too far. Subtracting the **operand start but omitting +4** yields 23, reaching 629 (`0x400275`), four bytes too far. Both computations mix the desired destination with the wrong origin, but by different amounts.

The CPU takes JZ when ZF=1. If immediately preceded by `TEST RDI,RDI`, that means RDI was zero. With ZF=0 it continues at the fall-through location corresponding to offset 606. Builder patching does not determine that future condition.

The patch primitive requires a valid existing operand field and a fitting rel32. It does not authorize arbitrary file offsets or prove a branch destination is an instruction boundary.

## C9-05 — Account for the frame and return

### Hints

1. CALL, the prologue's PUSH, and the frame subtraction are three separate decreases of RSP
2. Once MOV RBP,RSP completes, use that stable new RBP for both local coordinates
3. The epilogue's first move abandons the local extent; only the following POP and RET read saved control-related cells

### Checked solution

All pointers in this table are hexadecimal target addresses:

| Completed action | RSP | RBP | Relevant memory |
|---|---|---|---|
| Before CALL | `1000` | `2000` | Caller-owned state |
| CALL | `0FF8` | `2000` | `[0FF8]=K` |
| PUSH RBP | `0FF0` | `2000` | `[0FF0]=2000` |
| MOV RBP,RSP | `0FF0` | `0FF0` | Saved old base remains |
| SUB RSP,256 | `0EF0` | `0FF0` | Local extent reserved, not initialized |
| MOV RSP,RBP | `0FF0` | `0FF0` | Local extent no longer live |
| POP RBP | `0FF8` | `2000` | Old base restored |
| RET | `1000` | `2000` | Resume at K |

Slot zero is `0FF0−8=0FE8`. Slot 31 is `0FF0−256=0EF0`. The return destination is at 0FF8; saved old RBP is at 0FF0. Neither cell is slot zero.

RAX carries whatever result the function arranged before returning. The five-byte default epilogue does not convert RDI into RAX and does not zero the local memory it abandons.

Stack balance is an endpoint claim. ABI alignment must hold at relevant intermediate call boundaries as well, including with nested saved expression values, staged arguments, and switch saves. The shown arithmetic alone is not a proof about every such path or the complete System V contract.

## C9-06 — Keep a typed assignment's value

### Hints

1. Treat “bytes written” and “RDI after the operation” as separate questions
2. 511 is `0x1FF`; truncating to one byte leaves FF
3. Signed extension of FF repeats its top bit. A byte store alone does not perform that extension on the source register

### Checked solution

Under LP64 integer defaults, signed-char storage uses `40 88 39` and writes FF at A. Without conversion, RDI stays 511. If `cc-emit-convert-rdi` for signed char runs first, it emits `48 0F BE FF`, yielding RDI=`0xFFFFFFFFFFFFFFFF`, or −1. The subsequent store still writes FF, while the expression register now retains −1. Equal stored bytes do not establish equal expression results.

A signed typed byte load uses `48 0F BE 3F`, giving −1 from FF. An unsigned typed byte load uses `48 0F B6 3F`, giving 255. Both read one byte. Their different extension rules explain the different whole-register values.

For an unsigned four-byte load, `8B 3F` writes EDI. The architectural 32-bit-register-write rule clears upper RDI, so a loaded dword FFFFFFFF produces `0x00000000FFFFFFFF`. In contrast, a write to DIL alone would not clear higher bits. Register destination width and memory width both matter.

A legacy local typed wrapper would take its explicit qword branch. Giving the correct LP64 bytes without naming the profile leaves an important premise missing.

## C9-07 — Finalize the envelope

### Hints

1. Keep file count, BSS count, memory count, and end address in separate rows
2. Start from the header's minimum 81,920; compare it with file+BSS
3. A four-byte patch changes an eight-byte field whose upper half was already emitted as zero

### Checked solution

File count 81,920 is `0x14000`. BSS 16 raises the required memory count to 81,936, or `0x14010`, above the minimum.

| Field | File offset, decimal | Final eight bytes |
|---|---:|---|
| `p_filesz` | 96 | `00 40 01 00 00 00 00 00` |
| `p_memsz` | 104 | `10 40 01 00 00 00 00 00` |

The first target byte beyond the file portion is at `0x400000+0x14000=0x414000`. The zero-filled tail occupies `[0x414000,0x414010)`, sixteen bytes. The memory end is a virtual address; 81,936 is a length.

The finalizer writes only each low four-byte half. This is sufficient for these bounded counts because the high halves started at zero and the selected output/BSS bounds remain below 2^32. ELF64's size fields are still eight bytes. Do not generalize the implementation technique to arbitrary 64-bit sizes or stale headers.

Counting BSS as file bytes would incorrectly increase filesz to 81,936 and claim bytes exist in the output that were never appended. Treating the minimum memory extent as a declaration allocator also confuses responsibilities: it supplies loadable headroom; declaration/global allocation decides which C objects occupy storage within the permitted layout.

## C9-08 — Separate arithmetic contracts

### Hints

1. IDIV sees RDX:RAX, not RDI alone. Trace MOV and CQO first
2. Quotient truncates toward zero; recover the remainder from `dividend = quotient*divisor + remainder`
3. A masked processor shift count and a permitted source-language shift count answer different questions

### Checked solution

MOV RAX,RDI installs signed −7, pattern `0xFFFFFFFFFFFFFFF9`. CQO makes RDX=`0xFFFFFFFFFFFFFFFF`, so the concatenated signed 128-bit dividend is −7. RCX remains 3. IDIV produces RAX=−2 and RDX=−1 because `−7=(−2)*3+(−1)`.

The quotient emitter's final MOV puts −2 in RDI. The remainder emitter's final `48 89 D7` instead puts −1 there. Neither has two public results merely because both scratch registers contain useful numbers.

SAR of −3 by one preserves the sign and gives −2. IDIV of −3 by two truncates toward zero and gives −1, with remainder −1. Replacing one operation by the other without considering negative odd operands changes the result.

These 64-bit shift forms use the low six count bits. Count 64 therefore becomes zero and leaves the operand unchanged. That is a machine decode/execute rule, not a promise that C permits shifts by 64 on a 64-bit type, negative shifts, or overflowing signed shifts.

IDIV faults on divisor zero or a quotient outside its signed destination range. For a sign-extended 64-bit input and signed 64-bit divisor, the notable nonzero-divisor overflow case is `−2^63 / −1`. No compiler diagnostic or valid post-division register state is supplied by these emitters for the faulting case.

## Changed-case answer checks

Attempt these from the chapter's prompt list with the preceding solutions closed. These checks give the decisive differences rather than repeating every unchanged row.

### C9-01 changed

With pad=5 and right=3, the intermediate pairs `(RDI,RCX)` after moving right, popping, and subtracting are `(3,3)`, `(5,3)`, and `(2,3)`. Stored pad and final RDI become 2; RSP returns to S. The immediate field is `03 00 00 00`.

Starting at 700, instruction offsets are 700, 704, 705, 712, 715, 716, and 719; end is 723. Add `0x400000` to each for target addresses. Length stays 23 because the new bounded literal has the same immediate form. New values changed state, while relocating the whole fragment changed coordinates without changing these local-instruction encodings.

### C9-02 changed

Slot −16 gives displacement +120 and qualifies for disp8: load `48 8B 7D 78`, four bytes. Slot −17 gives +128 and requires disp32: `48 8B BD 80 00 00 00`, seven bytes. The raw byte 80 would mean −128 in a disp8 field, which is why retaining that shorter form would be wrong.

This is the positive-displacement counterpart of the slot-15/16 boundary. Both negative slots remain outside ordinary legacy-local allocation. The helper's encoding range and the frame allocator's ownership contract answer different questions.

### C9-03 changed

The real unary-not sequence gives 1 for input zero and 0 for input 256. RAX's initial `0xABCDEF0000000000` does not matter because XOR clears it before TEST.

Without XOR, SETE would leave whole RAX `0xABCDEF0000000001` for zero and `0xABCDEF0000000000` for 256; the final move copies those noncanonical values to RDI. Input 256 is in RDI, not RAX, so do not overwrite the supplied stale-RAX premise with it.

### C9-04 changed

The JMP at 900 is five bytes long: field 901, next instruction offset 905. A target at 880 requires displacement −25, 32-bit pattern FFFFFFE7. Complete bytes are `E9 E7 FF FF FF`; target virtual address is `0x400370`.

This is the arithmetic a known-backward-target emitter would need. Calling `cc-patch-rel32-to-here` while the output position is 905 instead patches displacement zero and reaches 905. The helper takes its target from the current cursor; it has no separate target argument. A normal append-only emission sequence also cannot emit at 900 and then naturally have current position 880. Negative relative arithmetic is valid; attributing that target selection to the wrong helper is not.

### C9-05 changed

CALL and the first two prologue instructions remain unchanged: new RBP is 0FF0. Subtracting 128 gives RSP=0F70. The last of sixteen reserved eight-byte slots is slot 15 at 0F70. Slot 31 would lie outside this stated reserved extent even though its address can be encoded.

With the active System V restore hook and a valid saved-RBX slot, `48 8B 5D F8` first reloads RBX from `[0FE8]`. It changes neither RSP nor RBP. The ordinary five-byte epilogue then proceeds as before; total epilogue bytes are nine. Merely enabling a restore without the matching saved-slot arrangement would not justify the same result.

### C9-06 changed

`0x12345` narrows to word 2345, decimal 9029. Store-only bytes `66 89 39` write `45 23` at A and A+1 but leave RDI=74565. Unsigned-short conversion `48 0F B7 FF` first makes RDI=9029, then the same store writes the same two bytes. A+2 onward is unchanged by either store.

The decisive invariant is still “store width does not convert the source register.” The changed width tests whether that reasoning transfers beyond the special DIL/REX byte-register form.

### C9-07 changed

File count 4096 is 0x1000; BSS 100,000 is 0x186A0. Their sum is 104,096, or 0x196A0, exceeding the minimum. Filesz becomes `00 10 00 00 00 00 00 00`; memsz becomes `A0 96 01 00 00 00 00 00`.

The file portion ends at target address `0x401000`; the memory extent ends at `0x4196A0`. The interval between them contains 100,000 initially zero bytes. Using 0x196A0 as that end address forgets the segment base; adding BSS to filesz forgets that the added extent has no corresponding file bytes.

### C9-08 changed

Unsigned dividend `2^64−1`, divided by two, gives quotient `2^63−1` and remainder one. The unsigned emitter sets RAX to all ones, clears RDX through EDX, and DIV sees the nonnegative 128-bit value with high half zero. Applying CQO instead would supply a different unsigned dividend.

SHR of all ones by one gives `0x7FFFFFFFFFFFFFFF`; SAR gives `0xFFFFFFFFFFFFFFFF`, still signed −1. Identical input bits do not choose their interpretation automatically. The caller's type decision selects which emitter is meaningful.

## A useful next check

If your final numbers agree but your intermediate pointers or widths do not, return to that transition before adding more instructions. For a later independent check, take one local memory operation and one control transfer from the chapter and explain their bytes without its worked state table. Keep the opcode reference available: the goal is to apply the coordinate and state contracts, not memorize navigation or an instruction encyclopedia.
