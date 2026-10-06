# C10 practice help: calls, literals, and deferred addresses

[Back to the chapter](../chapters/10-calls-literals-and-deferred-addresses.md)

These are checked manual derivations under the chapter's fixed-base, valid-storage, bounded-arithmetic, and stated-profile assumptions. No compiler, Forth example, C example, or generated program was executed. Hints and solutions are available immediately; use the amount of help that makes the next attempt informative.

When an answer differs, identify the first changed meaning: argument index versus pop order, instruction start versus operand start, builder pointer versus output offset, relative displacement versus absolute address, source spelling versus decoded bytes, or selected profile versus shared helper. A correct final number with the wrong reference point is worth revisiting before the mixed problems.

## C10-01 — Reverse the right thing

**Hint 1.** Argument zero is evaluated first, but argument five is nearest RSP after all six pushes.

**Hint 2.** The pop loop starts with index `n−1`. POP R9 is two bytes, `41 59`; every pop removes eight machine-stack bytes.

**Checked solution.** After staging, RSP=S−48 and the saved memory is:

| Address | Value | Destination when popped |
|---|---:|---|
| S−48 | 60 | R9 |
| S−40 | 50 | R8 |
| S−32 | 40 | RCX |
| S−24 | 30 | RDX |
| S−16 | 20 | RSI |
| S−8 | 10 | RDI |

The pop byte sequence is `41 59 41 58 59 5A 5E 5F`, eight instruction bytes for six eight-byte removals. RSP progresses S−40, S−32, S−24, S−16, S−8, S. Final registers in argument order contain 10,20,30,40,50,60. CALL then decreases RSP to S−8 and writes its return address there. That overwrites a no-longer-needed argument-staging position; it does not lose a still-needed argument because the values have moved into registers.

Starting pops with RDI would give argument zero the value 60, followed by reversed assignments. The stack would balance but the call's inputs would be wrong. This is why stack-depth equality is weaker than a correct argument mapping. `cc-parse-call` checks `count > 6` and raises error 122; the low-level index dispatcher alone does not provide that protection.

**Changed case.** Zero arguments cause no argument evaluation, push, or pop. The pop loop begins at −1 and exits; the call and post-call result move can still be emitted. Seven arguments reach error 122 after their parse-and-push phase and before argument pops and call dispatch. Do not infer that the builder appended no bytes or rolled back already emitted argument code. The compiler error occurs during emission, not during execution of those target PUSH instructions.

**Next step.** If the register order differed, label each saved value with its source argument index and follow only one pop at a time. Then try three arguments without the table. If only RSP differed, separate staging, CALL, and RET into three events.

## C10-02 — Move the star call

**Hint 1.** The CALL has one opcode byte and four displacement bytes. Offset 640 is not the displacement's reference point.

**Hint 2.** Subtract 645 from 146. Encode the resulting signed value in four little-endian bytes.

**Checked solution.** The operand begins at 641, the next instruction begins at 645, and the displacement is `146−645=−499`. Its 32-bit two's-complement representation is `0xFFFFFE0D`, so the complete instruction is:

```text
E8 0D FE FF FF
```

Checking in the forward direction gives `645+(−499)=146`. The common error `146−640` lands five bytes past the intended target because the CPU adds to the next instruction, not the opcode address. Using operand offset 641 alone still misses the operand's four-byte width.

For the stipulated successful one-byte write, this `putchar` shim returns RAX=1. The caller's `48 89 C7` then makes RDI=1. Argument value 42 was the byte requested for output; it is not the successful return value of this shim. The chapter's illustrative callsite at 1024 uses a different displacement, but both calls identify the same target at 146.

**Changed case.** With stipulated raw write result −9, the shim returns RAX=−9, and the result move gives RDI=−9. Removing its scratch with POP does not change RAX. Do not import the generic write wrapper's conversion to −1 or `fputc`'s saved-character return. Those are different runtime contracts examined in C11.

**Next step.** If the byte order was reversed, write `FFFFFE0D` as four byte pairs before ordering them from least to most significant. If the result was 42, separate requested byte, bytes transferred, and returned register value.

## C10-03 — Prepend, walk, discharge

**Hint 1.** The head cell stores a node address. The first node cell stores a patch offset. They are one dereference apart.

**Hint 2.** After the second prepend, the chain is `9016 → 9000 → 0`; compute the relative value independently at each recorded offset.

**Checked solution.** The first allocation writes `[9000]=513`, `[9008]=0`, and `[H]=9000`. The second writes `[9016]=561`, `[9024]=9000`, and `[H]=9016`. It consumes 32 arena bytes. Walk order and patches are:

| Node | Recorded field | Next-instruction target coordinate | Displacement | Field bytes |
|---:|---:|---|---:|---|
| 9016 | 561 | `0x400000+565` | `768−565=203` | `CB 00 00 00` |
| 9000 | 513 | `0x400000+517` | `768−517=251` | `FB 00 00 00` |

The walker then follows zero and finishes. It does not modify `[H]`. The definition consumer explicitly stores zero in the prototype's call-head cell after walking. No operation in this sequence frees individual nodes; their arena storage remains allocated until its owning lifetime is reset or replaced appropriately.

H names the builder location holding the first pointer. 9016 names a builder node. Neither is an output offset; the node's stored 561 is the value the output patcher needs. Clearing `[H]` disconnects the list but does not erase those node cells or rewind the arena.

**Changed case.** Start with `[H]=8000` and an existing node `[8000]=401`, `[8008]=0`. The first new node's next becomes 8000, so the completed chain is `9016 → 9000 → 8000 → 0`. The first two patches are unchanged. The last is `768−(401+4)=363`, or `6B 01 00 00`. This prepend operation still allocates 32 new bytes; the three reachable nodes occupy 48 bytes in total. Confusing existing storage with new allocation would overcount the operation.

**Next step.** If a pointer became a displacement, annotate each number as head-cell address, node pointer, output offset, or target address. Recompute only after those labels are consistent.

## C10-04 — Same target, different field

**Hint 1.** The target's file offset is 512. Only the CALL subtracts a next-instruction address.

**Hint 2.** The fields start at 701 and 722. Their widths are four and eight, even though either node would store its offset in an eight-byte builder cell.

**Checked solution.** The CALL ends at 705. Its displacement is `512−705=−193`, represented by `0xFFFFFF3F`. The four bytes at field 701 are `3F FF FF FF`, making the instruction `E8 3F FF FF FF`.

The MOVABS at 720 has its field at 722 and receives the absolute target `0x400200`. Its eight field bytes are `00 02 40 00 00 00 00 00`, making the complete instruction `48 BF 00 02 40 00 00 00 00 00`. Applying the relative formula here would load a small displacement as a pointer. Applying the absolute value to the CALL would send it somewhere else entirely.

Literal 2,147,483,648 uses `48 BF 00 00 00 80 00 00 00 00`. The seven-byte alternative would interpret its four-byte immediate as signed and extend its high bit, producing `0xFFFFFFFF80000000`. The desired positive value is `0x0000000080000000`.

**Changed case.** At target `0x400500`, the CALL displacement is `1280−705=575`, giving `3F 02 00 00`. The MOVABS field becomes `00 05 40 00 00 00 00 00`. Its field location and width do not change when the target moves.

For bit pattern `0x8000000000000000` with LP64 enabled, unsigned division by `2147483648` yields a nonzero quotient, so the selected instruction is `48 BF 00 00 00 00 00 00 00 80`. The LP64 magnitude check is the reason this conclusion covers bit 63 set. The legacy upper-bound comparison must not be silently promoted to the same unsigned-range contract.

**Next step.** If the two function patches matched, write down what the CPU does with each field: add a displacement to the next address, or copy an immediate value into RDI. Then retry with one backward target and one forward target.

## C10-05 — Count spelling and payload

**Hint 1.** Count the backslash in each source escape. The decoder's returned n excludes it, but the source advance includes it.

**Hint 2.** This body emits four payload bytes plus one terminator. The JMP's displacement equals that five-byte region.

**Checked solution.** The source body has ten bytes: one for A, four for `\101`, four for `\x2A`, and one for `!`. Decoded payload is `41 41 2A 21`, followed by implicit `00`.

| Part | Offset range | Bytes or value |
|---|---|---|
| JMP opcode and operand | 900–904 | `E9 05 00 00 00` |
| String bytes | 905–909 | `41 41 2A 21 00` |
| MOVABS opcode | 910–911 | `48 BF` |
| MOVABS operand | 912–919 | `89 03 40 00 00 00 00 00` |

The saved JMP field is 901, and `910−(901+4)=5`. String address is `0x400000+905=0x400389`. Final output position is 920. Position 920 is the next free byte, not the index of the last byte written.

Using source length ten as the displacement would skip five bytes into the MOVABS instruction. Omitting the implicit terminator from the displacement would land on a zero data byte. Both errors come from measuring the wrong output extent.

**Changed case.** Body `A\0B` has four source bytes and three payload bytes, `41 00 42`. Including the implicit terminator gives `41 00 42 00`, four emitted bytes. At the same starting position, the JMP displacement becomes 4; string address remains `0x400389`; MOVABS begins at 909; and final position is 919.

With the native string provider selected through the LP64 wrapper, adjacent tokens `"A\0" "B"` produce the same four combined bytes. The first piece's temporary terminator is removed; its explicit payload zero remains. The second piece's temporary terminator is also removed, then one final terminator is emitted. `cc-last-expr-array-len` becomes 4. This is not evidence that the legacy wrapper also concatenates adjacent tokens.

**Next step.** If the counts disagree, keep three columns: source bytes consumed, payload bytes emitted, and terminator bytes. If B disappeared from your layout, you imported a later NUL-terminated scan into an emitter that is following source length.

## C10-06 — Place both areas

**Hint 1.** The data base is captured before any data bytes are appended. Only the following BSS boundary is padded.

**Hint 2.** Position 1010 plus sixteen is 1026. The next multiple of eight is 1032, not 1040.

**Checked solution.** The data base is `0x400000+1010 = 0x4003F2`. Appending sixteen data bytes reaches position 1026. BSS is nonzero, so six padding bytes reach 1032, making BSS base `0x400408`. Final file size is 1032, and BSS size passed to the ELF finalizer is 24.

| Slot | Address calculation | Address | Eight patched bytes |
|---|---|---|---|
| 0 | Data base+0 | `0x4003F2` | `F2 03 40 00 00 00 00 00` |
| 8 | Data base+8 | `0x4003FA` | `FA 03 40 00 00 00 00 00` |
| `2^40+8` | BSS base+8 | `0x400410` | `10 04 40 00 00 00 00 00` |

The tag is subtracted before adding the BSS base. It is not added to the target pointer. File-plus-BSS is `1032+24=1056`, so `p_memsz` stays at the minimum 81,920. The low four file-size bytes become `08 04 00 00`; their upper four remain zero. The data base was not aligned by this finalizer.

**Changed case.** With zero BSS extent, the alignment loop is skipped. Data base stays `0x4003F2`; final output position is 1026; the BSS-base variable is assigned `0x400402`, although there is no BSS object to reference. `cc-bss-size` becomes zero. File-size low bytes are `02 04 00 00`, and memory extent remains 81,920. Removing BSS changes six padding bytes, not the sixteen allocated data bytes.

**Next step.** If the file size included 24 BSS bytes, distinguish bytes appended by the builder from memory extent requested in the header. If the data addresses were rounded, mark the precise step where each base is captured.

## C10-07 — Choose before recording

**Hint 1.** Capacity checks accept equality. They test prospective count before either record cell is written.

**Hint 2.** Workspace selection changes active pointers and limit. There is no loop copying old records into the new arrays.

**Checked solution.** At count 16,383, the next record passes prospective-count check 16,384, writes both columns at index 16,383, and sets count to 16,384. Another append proposes 16,385 and raises error 81 before changing the arrays or count in `cc-gfixup-add`.

There is a narrower failure boundary than “nothing was emitted.” When called through `cc-emit-global-ref`, the ten-byte MOVABS has already been appended before `cc-gfixup-add` checks record capacity. No rollback is shown. This does not affect the count calculation, but it prevents a false atomic-emission claim.

Switching to the direct workspace with count 16,384 retains that count while selecting different storage. The new arrays do not thereby contain the old records. The missing operation would be migration, which these selectors do not implement. The valid studied route starts with fresh logical usage and selects a workspace before collecting references; `cc-globals-init` can reset that usage, but would discard pending work if called halfway through it.

The direct capacity is 17,920. Its one mapped pair occupies `17920×16=286720` bytes; the second column begins after 143,360 bytes. The default pair is two 131,072-byte arrays. None of these quantities is the output buffer capacity or BSS extent.

**Changed case.** At a fresh direct count of 17,919, one append succeeds at index 17,919 and raises count to 17,920. Another proposes 17,921 and raises 81. A failed initial lazy mapping can also raise 81, but before normal reference collection through that selected workspace. Same error number does not make mapping failure and record-capacity exhaustion the same event. A previously successful direct mapping can be selected again without remapping it.

**Next step.** If a larger capacity seemed sufficient to preserve old records, draw the two old array bases and the two new ones. A count identifies a prefix only relative to the selected storage.

## C10-08 — Preserve the prepared arguments

**Hint 1.** Slot 16 means displacement `−8×17=−136`, which does not fit a signed byte.

**Hint 2.** The local-EA helper changes the short ModR/M value `45` to `85` and emits `78 FF FF FF`.

**Checked solution.** The pointer load into RAX is `48 8B 85 78 FF FF FF`, seven bytes. The indirect call is `FF D0`, two bytes, giving a nine-byte load-and-call sequence. There is no four-byte relative displacement in CALL RAX.

The R8 spill into slot 16 is `4C 89 85 78 FF FF FF`. `4C` selects REX.W and REX.R: the ModR/M register field names the store's source, extended from code zero to R8. POP R8 uses `41 58`, with REX.B extending the register code embedded in the POP opcode. “Extended register” does not mean that the same REX bit applies to every encoding.

The pointer load targets RAX because RDI already contains argument zero. Loading the pointer into RDI would replace that argument with the call target. Loading into RAX is a register-lifetime choice; it does not validate the pointer, allocate its local slot, or establish the entire ABI.

**Changed case.** At slot 15, displacement is −128, encoded as `80`. The load becomes `48 8B 45 80`; the R8 spill becomes `4C 89 45 80`. Both shrink from seven to four bytes because ModR/M uses its signed-byte-displacement form. The indirect CALL remains `FF D0`. The REX.W/R selection stays tied to width and register role, not to the displacement's size.

**Next step.** If the last field was `88`, re-evaluate `−8×(slot+1)` before encoding it. If the R8 spill began with `49`, locate whether this instruction encodes R8 in the ModR/M reg field or r/m field.

## C10-09 — Name the completion event

**Hint 1.** Ask when the missing fact becomes available. A string's end is known much earlier than the final data base.

**Hint 2.** One kind of metadata is an arena list, another is parallel arrays, and a short-lived wrapper can keep a single offset on its builder stack.

**Checked solution.** Under the chapter's executable path:

| Field | Missing fact and remembered location | Completion event | Patch |
|---|---|---|---|
| Forward function CALL | Function target; field offset in node on call head | Definition, or demanded late-shim emission | Four bytes: `target−(base+field+4)` |
| Function-address MOVABS | Same target; separate node on address head | Definition, or demanded late-shim emission | Eight bytes: target itself |
| Global-address MOVABS | Final data/BSS base; field offset and slot in matching array indices | Global finalization after data append and BSS boundary placement | Eight bytes: data base+slot, or BSS base+(slot−tag) |
| Inline-string JMP | End of decoded string region; single field offset retained by wrapper | Immediately after decoded bytes and final terminator | Four bytes: current output position−(field+4) |
| ELF file-size field | Final number of file bytes; fixed field offset 96 | ELF finalization after global finalization | Low four bytes of output length; high four already zero |

The related memory-size field at offset 104 uses file length plus BSS extent if that exceeds 81,920. This is a size patch, not either a relative branch or an absolute target pointer. An entry-stub call to `main` has its own stored offset and target variables, patched by the program consumer; it is not one of the global records.

“Patch everything during global finalization” supplies neither the function symbol's list traversal nor the wrapper's immediate control-flow closure. The actual consumers perform those earlier. Global finalization handles only its recorded global uses and storage placement; ELF finalization remains a later step.

An address-only use of a late shim has an empty call head but a nonempty address head. The late-shim consumer tests their OR, so it assigns a target, patches both applicable lists, clears both heads, and emits the body. An unused unresolved prototype with both heads zero contributes no pending use to reject. Assume the program otherwise supplies a valid `main`; that independent check still exists.

**Changed case.** If an ordinary function still has either pending list after the late-shim opportunity, `cc-check-fns-defined` raises error 206. That differs from successfully resolved fields whose old nodes remain allocated: in the latter case both owner heads have been cleared, so the checker sees no pending uses. Retained arena bytes are not themselves a to-do list; reachability from the relevant owner is decisive.

**Next step.** If every row seemed to need the same final pass, write a short emission timeline and place “fact first known” on it. If you mixed array records with nodes, name each owner before following any pointer.

## A return visit without copied answers

The chapter collects these changed prompts without answers. After a useful gap, choose one that changes a premise rather than only a number: zero BSS, an embedded NUL, a bit-63 LP64 literal, an address-only late shim, or a workspace switch with pending records. State the profile and representation first, then derive the result.

You can judge an attempt by whether its intermediate states preserve those distinctions and whether the final bytes satisfy the stated formulas. Looking up an opcode is compatible with practicing patch arithmetic. Reading a correct solution is supported study; a later independent attempt provides different evidence. Neither replaces an authorized execution record or a study of how representative readers learn this material.
