# 9. Instructions inside an executable

The triangle's inner work includes `pad = pad - 1`. Suppose `pad` is two. How can a Forth program write bytes now that will later change a C program's local variable to one? The answer needs two separate stories: the builder appends instruction bytes, and a future processor interprets those bytes using its own registers and memory.

Our main route follows one 23-byte fragment. By the end, you should be able to derive its bytes, distinguish a file offset from either kind of address, predict its register and stack effects, and patch a branch from the correct reference point. The grouped references then cover the remaining integer encoders and every field of this executable header. You need not memorize the opcode tables to use them.

## Choose a route and name the machine

Bring [C02's append and patch contracts](02-buffers-arenas-and-failure.md) and [C07's type-size contracts](07-types-and-stable-descriptors.md). We supply the instruction-reading bridge here; the seed volume's complete physical audit is optional background. The seed's cached Forth data stack is **not** the generated C program's expression stack, even though both programs use registers with the same names.

Try these checks:

- Decode little-endian bytes `34 12 00 00` as a number
- Explain why a pointer to `cc-out-buf+512` is not the generated program's address `0x400200`
- With left operand 2 saved, right operand 1 in RDI, say which operand must survive before subtraction

If these are new, begin with the next two sections. If they are secure, attempt C9-01 through C9-04 and use the references to check your reasoning. For a short first session, stop after the slot-16 boundary. On a later pass, read the frame and ELF sections before the typed-depth section.

**Evidence boundary.** This chapter describes inspected source at revision `bbcc1732152af2d884737272eed870d2410ffe8e`: [080-cc-elf.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/080-cc-elf.fth) and the instruction machinery in [090-cc-emit.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth). All emitted-byte tables below are **manual compositions from those definitions**, not output captured from a compiler run. All future-machine states are conditional paper derivations. No compiler build, Forth/C execution, or generated-program execution was performed for this chapter.

The main profile is the legacy, fixed-address Linux/x86-64 executable: eight-byte integer operations and eight-byte frame slots. LP64 storage and System V calling policy are separate explicit selections. Assume sufficient builder capacity, valid target addresses and stack space, intact return destinations, and arithmetic inputs within the stated example's domain. A correct byte derivation alone does not establish loader acceptance, successful file writing, or whole-program correctness.

## One byte, three coordinates

Hexadecimal uses digits `0`–`9` and `A`–`F`; `F8` means decimal 248. A byte listing runs from lower to higher addresses, left to right. `0x1234` is a number; `34 12` is its two-byte little-endian representation. Successive bytes have weights 1, 256, 65536, and so on. Thus the diagnostic's four bytes represent decimal 4660. Reverse neither the digits within a byte nor the complete instruction.

An instruction may contain both fixed opcode bytes and little-endian fields. In `48 C7 C7 01 00 00 00`, only the last four bytes are the immediate field. The three prefix/opcode/operand bytes stay in their written order.

Keep these coordinates distinct:

| Name | Meaning | Example for one emitted byte |
|---|---|---|
| Builder pointer | Address in the running compiler's storage | `cc-out-buf + 512` |
| File offset | Byte count from the beginning of the eventual file | 512, or `0x200` |
| Target virtual address | Address at which the loaded C program will see that byte | `0x400200` |

The ELF segment here starts at file offset zero and target address `0x400000`. Therefore, for a file-backed byte in this segment, target address = `0x400000 + file offset`. `cc-base-vaddr` is 4,194,304, or `0x400000`; `cc-here-vaddr` adds the current `cc-out-pos @`. It does not inspect the builder buffer's address. Two processes can assign completely different meanings to the same numerical address.

C02 established that an append advances `cc-out-pos`; a patch overwrites existing bytes without advancing it. `cc-emit-byte`, `cc-emit-4le`, and `cc-emit-8le` build the output buffer. They do not extend the seed's HERE dictionary cursor. Appending code is still a data-writing operation in the builder. The generated instruction has not run merely because its bytes now exist.

The initial layout is small: `cc-emit-elf-header` writes 64 header bytes and one 56-byte program-header entry. Their sum is 120, or `0x78`. `cc-entry-vaddr` is consequently `0x400078`. The program entry there is a stub, not `main` itself. We will inspect every header field in the [ELF reference](#reference-the-complete-executable-envelope); first let us give the bytes after the header some meaning.

## Follow `pad = pad - 1` through seven transitions

A **register** is named CPU storage. RDI, RCX, RAX, RBP, and RSP are 64-bit registers. Here the generated code uses RDI for the current expression result, RCX for a saved right operand, RAX for a return value or division work, RBP for a frame base, and RSP for the machine stack. These roles are conventions of this code, not properties the register names enforce.

Assembly notation puts the destination first. `mov rcx, rdi` copies RDI into RCX. Brackets mean memory access: `mov rdi, [rbp-8]` reads from an address calculated using RBP. A **qword** is eight bytes; a **dword** is four; a **word** is two. Instruction length and memory-access width are different quantities.

Use this stipulated reset, adapted from the triangle's `line(2,3)` case:

- `pad` occupies local slot 0, whose address is `P-8`
- RBP = P, valid qword memory `[P-8]` contains 2, and RSP = S
- The writable stack cell at `S-8` does not overlap the local
- The builder's next file offset is 1024; these chosen coordinates are not a historical `tri.c` dump

Read the table once for state changes, then once for byte counts. A dash means the register's previous value is irrelevant to this trace. Each row describes the state **after** the named instruction.

| File offset, decimal | Manually composed bytes | Decoded instruction | RDI | RCX | RSP | Consequence |
|---:|---|---|---:|---:|---|---|
| 1024 | `48 8B 7D F8` | `mov rdi, [rbp-8]` | 2 | — | S | Read `pad` |
| 1028 | `57` | `push rdi` | 2 | — | S−8 | Save 2 at `[S-8]` |
| 1029 | `48 C7 C7 01 00 00 00` | `mov rdi, 1` | 1 | — | S−8 | Right operand replaces RDI |
| 1036 | `48 89 F9` | `mov rcx, rdi` | 1 | 1 | S−8 | Preserve the right operand |
| 1039 | `5F` | `pop rdi` | 2 | 1 | S | Restore the left operand |
| 1040 | `48 29 CF` | `sub rdi, rcx` | 1 | 1 | S | Compute left minus right |
| 1043 | `48 89 7D F8` | `mov [rbp-8], rdi` | 1 | 1 | S | Write `pad=1` |

The lengths are `4+1+7+3+1+3+4=23`. The next output offset is 1047, or `0x417`, and its target address is `0x400417`. Popping restores the stack boundary; it does not erase the stale two at `S-8`. Storing the result preserves RDI, so a surrounding expression could still use its value.

Why save the left operand? Evaluating the right operand uses the same result register. Without a save, loading one would destroy the only available copy of two. Why move the right into RCX before popping? The pop itself replaces RDI. Addition can conceal an operand-order mistake; subtraction makes it visible.

The inspected primitive for the decisive arithmetic step is:

```forth
: cc-emit-sub-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  41 cc-emit-byte
  [lit] 207 cc-emit-byte ;
```

Decimal 72, 41, and 207 become bytes `48 29 CF`. During **builder** execution, this definition appends three bytes. During **target** execution, those bytes subtract RCX from RDI. The Forth data stack consumed by an emitter and the target machine stack changed by an emitted PUSH belong to different executions.

This is a composition of inspected emitters, not a claim that invoking the whole parser necessarily produces this exact seven-instruction fragment in every context. Expression parsing, conversions, and optimization choices are separate questions opened later.

## Decode only the fields this fragment needs

An **opcode** selects an instruction form. A **REX prefix** selects width or extra registers for suitable forms in 64-bit mode. `48` has W=1, requesting 64-bit operands here; its R/X/B register-extension bits are zero. It does not make every immediate eight bytes.

The low three-bit register codes used here are:

| Code | Register | Code | Register |
|---:|---|---:|---|
| 0 | RAX | 4 | RSP |
| 1 | RCX | 5 | RBP |
| 2 | RDX | 6 | RSI |
| 3 | RBX | 7 | RDI |

R8 and R9 use codes 0 and 1 plus a relevant extension bit. REX.R extends a ModR/M register field, REX.B extends a base/r/m or opcode-register field, and REX.X extends a SIB index. We will use only the cases this source needs.

The **ModR/M byte** splits into `mod | reg | r/m`, with 2, 3, and 3 bits. For our local load, `7D = 01 | 111 | 101`: memory with a signed one-byte displacement, register RDI, base RBP. Its following `F8` is −8 in signed-byte representation because 248−256=−8. Opcode `8B` transfers from that memory operand into the register. Changing the opcode to `89` transfers from the register into memory; `7D F8` still chooses the same operands.

For the subtraction, `CF = 11 | 001 | 111`. `mod=11` means registers, RCX is the `reg` operand, and RDI is the `r/m` operand. Opcode `29 /r` places the result in the `r/m` operand. The `/r` notation says both operand fields participate; it is not an additional emitted byte.

Do not turn that direction into a universal rule. `cc-emit-imul-rdi-rcx` emits `48 0F AF F9`. For this IMUL form, the **reg field is the destination**. `F9 = 11 | 111 | 001` selects RDI times RCX. SUB uses CF and this IMUL uses F9 for the same left/right register roles. Decode the opcode's form before naming the destination. [The inspected arithmetic definitions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L281-L331) make the distinction explicit.

A notation such as `C7 /0` instead uses the middle field as an **opcode extension**, fixed to zero. In `48 C7 C7`, the last C7 is `11 | 000 | 111`: register destination RDI, operation extension zero. The opcode's first C7 and the operand-selection C7 happen to have equal byte values but different jobs.

`cc-emit-mov-rdi-imm32` uses that seven-byte form: four immediate bytes sign-extended to the 64-bit destination. A positive one works; `00 00 00 80` denotes signed −2,147,483,648 after extension, not positive 2,147,483,648. `48 BF` followed by an eight-byte immediate can represent the latter directly. C10 opens that emitter and the profile-specific literal selector. The distinction is immediate width versus destination width, as specified in Intel's [MOV opcode table, Volume 2B, printed 4-35–4-36](https://cdrdv2-public.intel.com/835752/253667-sdm-vol-2b.pdf#page=37).

### The slot-15/slot-16 boundary

The local-address rule is `RBP - 8*(slot+1)`. Slot numbers are compiler metadata; the instruction holds the resulting byte displacement. `cc-disp8-from-slot` negates `8*(slot+1)` and keeps its low byte. `cc-emit-local-ea` chooses whether that byte form can express the address:

```forth
: cc-emit-local-ea
  over [lit] 16 < >r over [lit] 0 [lit] 16 - >= r> and if,
    cc-emit-byte
    cc-disp8-from-slot cc-emit-byte
  else,
    [lit] 64 + cc-emit-byte                       \ mod=01 -> mod=10
    1+ [lit] 8 *                                  \ 8 * (slot+1)
    [lit] 0 swap - cc-emit-4le                    \ negate; low 4 bytes = disp32
  then, ;
```

Here Forth stack top is at the right. The input is `[slot, modrm8]`; `over` copies the slot for the test, and the temporary return-stack flag is retrieved before either branch. The helper consumes the slot and supplied ModR/M form. It appends address-selection bytes, without allocating storage or checking whether a variable owns that slot.

For nonnegative local slots:

| Slot | Displacement | Address bytes for RDI load/store | Complete load |
|---:|---:|---|---|
| 0 | −8 | `7D F8` | `48 8B 7D F8` |
| 15 | −128 | `7D 80` | `48 8B 7D 80` |
| 16 | −136 | `BD 78 FF FF FF` | `48 8B BD 78 FF FF FF` |

A signed byte reaches −128 but not −136. Adding 64 to 7D changes its `mod` bits from `01` to `10`, yielding BD and a signed four-byte displacement. The load grows from four to seven bytes; the addressed value remains an eight-byte qword.

The actual predicate is broader than “slots below sixteen”: it selects disp8 for `−16 <= slot < 16`. For example slot −3 gives +16 and address bytes `7D 10`. Such coordinates can describe native stack parameters. They are not allocated legacy locals. The default allocation limit of 32 slots belongs to `cc-fn-add-slots` in [110-cc-decl.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L29-L46), which rejects a claim beyond its limit with error 162. An encoder's ability to name an address does not make that address owned memory. The four-byte form also requires the mathematical displacement `−8*(slot+1)` to fit a signed 32-bit field, with no prior arithmetic wrap. This helper writes the low four bytes without checking that condition; its ability to emit them is not an unrestricted-address guarantee.

**Stop/resume.** Save “left=2, right=1, RBP=P, RSP=S; slot 16 is P−136.” On returning, derive the new load and store lengths without copying the table. The changed full fragment should follow from those two changes; its arithmetic instructions need no alteration.

## Turn conditions into either data or a destination

Processor **status flags** record properties of an arithmetic or logical result. They are neither a C value in RDI nor the builder's Forth flag. For a subtraction-like comparison, ZF says the result was zero, SF records its sign bit, OF records signed overflow, and CF records unsigned borrow. Signed ordering uses SF together with OF; the sign bit alone can mislead after overflow.

`CMP` computes flag information without storing the subtraction result. `TEST rdi,rdi`, bytes `48 85 FF`, computes flags from a bitwise AND without changing RDI; in particular ZF is one exactly when RDI is zero. `cc-emit-test-rdi` emits that test.

### Materialize a C comparison

`cc-emit-cmp-set` uses this twelve-byte shape; wrappers supply the SETcc opcode:

| Manually composed bytes | Action | Why this order matters |
|---|---|---|
| `48 31 C0` | Zero all of RAX | SETcc will write only AL, its low byte |
| `48 39 CF` | Compare RDI against RCX | Establish flags for left minus right |
| `0F xx C0` | Set AL to 0 or 1 | Consume the selected condition |
| `48 89 C7` | Copy RAX into RDI | Return a full-width C result |

Zeroing RAX after CMP would replace the comparison's flags. Omitting it would leave unknown high bits above AL. These two errors require different repairs. Here the resulting true value is **1**, unlike the seed's canonical Forth true flag, all 64 bits set (−1). Both are nonzero, but they differ as data, especially under bitwise operations.

| Emitter | `xx` | Condition for result 1 |
|---|---|---|
| `cc-emit-cmp-eq` | `94` | ZF=1 |
| `cc-emit-cmp-ne` | `95` | ZF=0 |
| `cc-emit-cmp-lt` | `9C` | SF differs from OF |
| `cc-emit-cmp-ge` | `9D` | SF equals OF |
| `cc-emit-cmp-le` | `9E` | ZF=1 or SF differs from OF |
| `cc-emit-cmp-gt` | `9F` | ZF=0 and SF equals OF |

For `2 < 3`, the comparison establishes a negative, nonoverflowed difference; SETL writes AL=1, and the final RDI is 1. For `3 < 2`, AL=0 and RDI=0. The instruction form, rather than a Forth subtraction-and-sign shortcut, supplies signed ordering.

`cc-emit-not-zero-flag` implements C unary `!`: `48 31 C0; 48 85 FF; 0F 94 C0; 48 89 C7`. It returns 1 for an input of zero and 0 for any nonzero input. Its name does not mean bitwise complement; `cc-emit-not-rdi` performs that separate operation.

### Patch from the end of the displacement field

A conditional branch can use the flags directly without making a C integer. The three owned placeholder emitters write:

| Emitter | Bytes | Returned file offset |
|---|---|---|
| `cc-emit-jz-rel32-placeholder` | `0F 84 00 00 00 00` | Start+2 |
| `cc-emit-jnz-rel32-placeholder` | `0F 85 00 00 00 00` | Start+2 |
| `cc-emit-jmp-rel32-placeholder` | `E9 00 00 00 00` | Start+1 |

JZ takes its destination when ZF=1; JNZ when ZF=0; JMP always takes it. A **rel32** is a signed four-byte displacement added to the address following the instruction. These emitters return the **operand offset**, not the opcode offset. If `q` is that operand offset and T is the desired target file offset, displacement = `T-(q+4)`. The common mapping base cancels out.

For a paper JZ beginning at offset 600, q=602 and the next instruction address corresponds to offset 606. If the current output position later reaches 625, `cc-patch-rel32-to-here` writes 19: bytes `13 00 00 00`. The branch now reaches target address `0x400271`. It does not reach `0x400275`, the erroneous result from omitting the field's four-byte length.

The patcher's implementation is short:

```forth
: cc-patch-rel32-to-here
  cc-out-pos @                                    ( patch-off target-off )
  over [lit] 4 + -                                ( patch-off rel32 )
  swap cc-out-patch-4le ;
```

The builder's final position stays 625. A later CPU, when ZF=0, would fall through instead; a patch does not force the branch condition. A backward displacement uses the same signed arithmetic, but the named backward-jump provider and structured control-flow ownership live in `112-cc-stmt.fth` and later statement chapters. C10 opens CALL placeholders and the longer-lived lists that remember their operands.

No general rel32 range validation is established here. The four-byte encoding requires a fitting signed displacement. Nor do C02's append-capacity checks make arbitrary patch offsets safe: the caller must identify a valid existing field of the right width.

## Cross the call/frame interface without opening the parser

A near CALL saves the next instruction's address as an eight-byte return destination on the target stack and transfers control. RET consumes that address. Neither instruction understands a C parameter, a local-variable name, or a builder fixup node. For a valid call made with RSP=S, callee entry has RSP=S−8 and `[S-8]=K`, where K is the return destination.

`cc-emit-prologue ( frame-bytes -- )` appends eleven bytes: `55 48 89 E5 48 81 EC` followed by four little-endian frame-size bytes. They decode as PUSH RBP, MOV RBP,RSP, SUB RSP,frame-bytes. With frame-bytes=256:

| Completed action | RSP | RBP | Owned state established |
|---|---|---|---|
| CALL entry | S−8 | Old P | Return destination K at S−8 |
| PUSH RBP | S−16 | Old P | Old P saved at S−16 |
| MOV RBP,RSP | S−16 | S−16 | Stable base for this frame |
| SUB RSP,256 | S−272 | S−16 | Space for 32 eight-byte slots |

Slot zero is now at S−24; slot 31 is at S−272. The prologue reserves space without clearing local contents. Its supplied immediate is sign-extended by the instruction, so this contract assumes a valid positive bounded frame size. Choosing the size and assigning slots belong to function parsing in C18; the emitter itself takes a byte count.

The default `cc-emit-epilogue` appends `48 89 EC 5D C3`: MOV RSP,RBP discards the frame extent, POP RBP restores the old base, and RET removes K and resumes the caller with RSP=S. A function result must already be in RAX under this return convention. The epilogue does not discover or move it. `cc-emit-mov-rax-rdi` is available for that transfer.

Before those five bytes, the emitter invokes `cc-emit-restore-callee-fwd`, initially bound to `cc-emit-restore-noop`. The System V provider can add a restore, so “five bytes” is a **default** total. A matching prologue/epilogue shape is not a proof of complete System V interoperability: call-boundary alignment, argument placement, preserved registers, and nested temporary lifetimes also matter. C10 supplies the restricted call sequence; C18 and the later target chapters own whole-function policy.

The first code at `0x400078` is a 26-byte entry stub that obtains process arguments, calls main, and requests Linux exit using the result. The [bounded entry seam in 116-cc-prog.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/116-cc-prog.fth#L585-L622) supplies that promise. C19 opens its full control path. Process entry itself is not an ordinary call with a caller's saved return address.

## Reference: addresses, movement, and memory updates

Use this section when an emitter in later chapters needs a byte-level explanation. All byte rows remain manual compositions. [090's movement and memory definitions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L27-L179) implement these contracts.

### Preserve values and distinguish addresses from contents

| Emitter | Bytes | Target effect |
|---|---|---|
| `cc-emit-push-rdi` | `57` | RSP decreases by 8; save RDI |
| `cc-emit-pop-rdi` / `cc-emit-pop-rsi` | `5F` / `5E` | Load named register; RSP increases by 8 |
| `cc-emit-pop-rdx` / `cc-emit-pop-rcx` | `5A` / `59` | Same stack effect |
| `cc-emit-pop-r8` / `cc-emit-pop-r9` | `41 58` / `41 59` | REX.B selects the extended register |
| `cc-emit-push-rbx` / `cc-emit-pop-rbx` | `53` / `5B` | Save/restore RBX; same eight-byte stack width |
| `cc-emit-mov-rcx-rdi` | `48 89 F9` | RCX gets RDI |
| `cc-emit-mov-rax-rdi` | `48 89 F8` | RAX gets RDI |
| `cc-emit-mov-rdi-rax` | `48 89 C7` | RDI gets RAX |
| `cc-emit-mov-rbx-rdi` | `48 89 FB` | RBX gets RDI, used for a switch value |
| `cc-emit-xor-rax-rax` | `48 31 C0` | RAX becomes zero; flags change too |

The tracked RDI push and all six listed argument/result pops call `cc-emit-track-push-fwd` or `cc-emit-track-pop-fwd` first. Both initially use `cc-emit-track-noop`, which emits no bytes and changes no accounting. Raw RBX saves do not use these hooks. The distinction allows later bookkeeping to count expression/argument temporaries separately from lexical switch saves; it does not make RBX intrinsically immune to other code.

| Emitter | Bytes or shared suffix | Target effect |
|---|---|---|
| `cc-emit-load-local` | `48 8B` + local EA for 7D | Read qword into RDI |
| `cc-emit-store-local` | `48 89` + local EA for 7D | Write RDI qword |
| `cc-emit-lea-rdi-local` | `48 8D` + local EA for 7D | Put calculated address in RDI; no memory read |
| `cc-emit-load-via-rdi` | `48 8B 3F` | RDI gets qword at old RDI |
| `cc-emit-load-byte-via-rdi` | `48 0F B6 3F` | Read one byte and zero-extend it |
| `cc-emit-store-via-rcx` | `48 89 39` | Write RDI qword at RCX |
| `cc-emit-store-byte-via-rcx` | `40 88 39` | Write only DIL, RDI's low byte, at RCX |
| `cc-emit-zx-byte-rdi` | `40 0F B6 FF` | Keep low byte, zero all higher result bits |

LEA of slot zero produces P−8 even if the bytes there hold two. Following it with a qword dereference then produces two. The first obtains a location; the second reads its contents. `cc-emit-load-byte-via-rdi` reads `FF` as 255. It does not infer a signed char from the address.

DIL and DI name the low eight and sixteen bits of RDI; EDI names the low 32. A write to EDI clears RDI's upper 32 bits in 64-bit mode. Writes to DIL or DI alone leave higher bits unchanged. The bare REX prefix `40`, although W=0, selects the newer low-byte register names: without it the relevant code 7 denotes BH rather than DIL. Thus `40` in the byte operations is meaningful, not padding. A byte store of RDI=300 writes decimal 44 but leaves RDI=300. Memory narrowing and expression-result conversion are different operations.

### Scale, bias, and update without losing an old value

`cc-emit-shl-rdi-imm8` emits `48 C1 E7` plus a count byte. `cc-emit-shl-rdi-3` supplies count 3. Within a nonoverflowing index calculation that multiplies by eight. Eight is the element width of this use, not a universal `sizeof(int)` in every profile. `cc-emit-add-rdi-imm32` emits `48 81 C7` plus a sign-extended immediate, useful for adding a field offset to a base address.

The memory-update helpers in [090's post-runtime arithmetic region](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L1005-L1096) are easy to miss if one stops reading at the runtime bodies:

| Emitter | Manually composed form | Effect |
|---|---|---|
| `cc-emit-inc-mem-local` | `48 FF` + local EA for 45 | Increment local qword |
| `cc-emit-dec-mem-local` | `48 FF` + local EA for 4D | Decrement local qword |
| `cc-emit-inc-via-rcx` | byte? true: `FE 01`; false: `48 FF 01` | Increment byte or qword at RCX |
| `cc-emit-dec-via-rcx` | byte? true: `FE 09`; false: `48 FF 09` | Decrement byte or qword at RCX |
| `cc-emit-load-via-rcx` | byte? true: `48 0F B6 39`; false: `48 8B 39` | Read zero-extended byte or qword into RDI |

`byte?` is a builder-side selector: zero chooses qword, nonzero chooses byte. It is not an immediate written into the instruction. With old `pad=2`, a caller can load two into RDI and then decrement its memory slot, leaving RDI=2 and stored `pad=1`. That is useful for post-decrement, but the caller must arrange the load first. These helpers do not themselves decide prefix versus postfix C semantics. INC/DEC change arithmetic flags but preserve CF; they do not overwrite RDI or RCX with the updated memory value.

### The few extra address forms needed by the runtime

When a memory ModR/M operand has `r/m=100`, a **SIB byte** supplies scale, index, and base. Split it into 2/3/3 bits. Scale bits 00 mean an index multiplier of one. With the ordinary unextended forms used here:

- SIB `24 = 00|100|100` means no index and base RSP; `48 8B 3C 24` reads a qword from `[rsp]` into RDI
- SIB `17 = 00|010|111` means base RDI plus RDX
- SIB `07 = 00|000|111` means base RDI plus RAX

The special index code in the first case means no index, not “add RSP twice.” C11 uses these forms for scratch bytes and string scanning. The opcode still determines access width and direction.

A displacement-only `mod=00,r/m=101` form in 64-bit addressing instead supplies **RIP-relative** memory: address = next instruction address + signed disp32. For instance, the runtime's `48 8B 05` plus a four-byte field loads RAX from that calculated location. A seven-byte instruction beginning at offset 200 with displacement 20 accesses the location corresponding to offset 227. The CPU adds from 207, not 200. C11 applies this rule to the allocator's inline data slots.

One more interface is `F3 A4`, REP MOVSB. With direction flag DF clear and valid nonoverlapping spans, it copies bytes from RSI to RDI, advancing both and reducing RCX to zero. DF set reverses the address progression. This flag is separate from ZF/SF/OF/CF; arithmetic comparisons do not establish its required direction. C11 states the runtime's DF premise rather than inventing a CLD instruction. The [pinned runtime bytes](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L965-L971) and Intel's [MOVS/REP descriptions](https://cdrdv2-public.intel.com/835752/253667-sdm-vol-2b.pdf) are the relevant seams.

## Reference: arithmetic has width and failure conditions

The left/right arrangement remains RDI=left, RCX=right. The core subtract example supplies the sequencing; these emitters change only the operation. Bitwise operations act independently on each bit.

| Emitter | Bytes | Result in RDI |
|---|---|---|
| `cc-emit-add-rdi-rcx` | `48 01 CF` | Low 64 bits of left+right |
| `cc-emit-sub-rdi-rcx` | `48 29 CF` | Low 64 bits of left−right |
| `cc-emit-imul-rdi-rcx` | `48 0F AF F9` | Low 64 bits of product |
| `cc-emit-and-rdi-rcx` | `48 21 CF` | Bitwise AND |
| `cc-emit-or-rdi-rcx` | `48 09 CF` | Bitwise OR |
| `cc-emit-xor-rdi-rcx` | `48 31 CF` | Bitwise exclusive OR |
| `cc-emit-not-rdi` | `48 F7 D7` | Complement every bit |
| `cc-emit-neg-rdi` | `48 F7 DF` | Low 64 bits of zero−RDI |
| `cc-emit-shl-rdi-cl` | `48 D3 E7` | Shift left, filling low positions with zero |
| `cc-emit-sar-rdi-cl` | `48 D3 FF` | Shift right, repeating the sign bit |

NOT does not change flags; NEG does. Neither is C logical `!`. A full low-half multiplication can discard significant high bits. The CPU's wrapping result is not a blanket promise that overflowing signed C expressions are valid language operations.

The variable shift count is read from CL, the low byte of RCX. For these 64-bit forms the processor masks the count to six bits; a count of 64 acts as zero. The immediate-count SHL also uses that mask. This machine rule does not authorize a C shift by the type's width or a negative count. Parser/type policy and the source language's permitted operands must be considered separately. SAR of −3 by one gives −2; signed IDIV by two gives −1. Right shift and signed division have different rounding behavior for this negative odd case.

### Prepare both halves before dividing

`cc-emit-idiv-quotient` emits `48 89 F8; 48 99; 48 F7 F9; 48 89 C7`. The steps are MOV RAX,RDI; CQO; IDIV RCX; MOV RDI,RAX. CQO sign-extends RAX into the 128-bit pair RDX:RAX: RDX becomes zero for nonnegative RAX and all ones for negative RAX. The colon means high-half/low-half concatenation, not division.

With RDI=−7 and RCX=3, IDIV computes quotient −2 in RAX and remainder −1 in RDX, satisfying `−7 = (−2)*3 + (−1)`. `cc-emit-idiv-remainder` uses the same first eight bytes but ends `48 89 D7`, moving RDX instead. Each returns one chosen expression value, not two values.

The divisor must be nonzero and the quotient must fit the signed destination. In particular, signed minimum `−2^63` divided by −1 cannot fit and causes a processor divide error. These helpers do not turn that fault into a builder `cc-die` diagnostic. A stale RDX would change the dividend, which is why CQO is a necessary preparation step. Intel's [IDIV and CQO entries, Volume 2A](https://cdrdv2-public.intel.com/835751/253666-sdm-vol-2a.pdf) define that architectural boundary.

`cc-emit-cmp-rbx-imm32` is another useful grouped form: `48 81 FB` plus four immediate bytes compares RBX against a **sign-extended** constant. Its `/7` extension means CMP. A switch caller chooses when RBX holds the saved selector and how case destinations are reached; this primitive supplies neither the lifetime nor the dispatch structure.

## Depth: integer storage under an explicit LP64 profile

This section is optional on the first pass, but it prevents an important overgeneralization: not every loaded C integer occupies eight memory bytes. In C07's LP64 model, signed/unsigned char, short, int, and long have widths 1, 2, 4, and 8. Expression registers and these frame-slot coordinates still use 64-bit registers/eight-byte slots. A four-byte memory access does not imply a four-byte RDI register.

The [typed encoder block](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L1234-L1384) delegates type checking through `cc-emit-type-check-fwd`, initially bound to `cc-emit-type-check-noop`. Its stack interface is type in, type out. A later provider may check or map the storage type before dispatch. A known size alone is not proof that an aggregate or floating value can use integer arithmetic. The typed pointer and conversion dispatchers do not each have their own LP64 gate: they use the supplied type and installed provider. The local wrappers below contain explicit legacy/LP64 branches; do not generalize their switch to every typed primitive.

### Loads choose both width and extension

`cc-emit-load-typed-via-rdi` selects by `ty-size` and `ty-unsigned?` after the hook. Signed extension repeats the source sign bit; zero extension fills higher positions with zero. The old RDI still supplies the address before being replaced.

| Source width | Unsigned load bytes | Signed load bytes | Result example |
|---:|---|---|---|
| 1 | `48 0F B6 3F` | `48 0F BE 3F` | Byte FF gives 255 or −1 |
| 2 | `48 0F B7 3F` | `48 0F BF 3F` | Word FFFF gives 65535 or −1 |
| 4 | `8B 3F` | `48 63 3F` | Dword FFFFFFFF gives 4294967295 or −1 |
| Fallback | `48 8B 3F` | `48 8B 3F` | Read an eight-byte qword |

The unsigned four-byte form writes EDI, thereby clearing upper RDI. The signed form is MOVSXD. Fallback means “this code emits a qword load,” not “every other possible type is safely eight bytes.” Appropriate type checking and callers bound the valid use.

`cc-emit-load-local-typed ( slot ty -- )` explicitly tests `cc-target-lp64`. Active LP64 composes LEA of the slot with the typed pointer load. Legacy mode discards the type and uses `cc-emit-load-local`, preserving its qword access. Thus an LP64 signed-char load at slot zero is a four-byte LEA followed by a four-byte MOVSX, not a shortened qword-load instruction with an implicit sign rule.

### A store and a conversion solve different problems

`cc-emit-store-typed-via-rcx` writes only the destination width: one byte `40 88 39`, two bytes `66 89 39`, four bytes `89 39`, or fallback qword `48 89 39`. Prefix `66` selects the word-sized transfer here. These stores preserve RDI. Starting from RDI=511, a one-byte store writes FF but still leaves 511 in the register.

`cc-emit-convert-rdi` instead narrows the register value and extends the retained part according to the destination integer type. Conversion to signed char makes that 511 into −1; conversion to unsigned char makes it 255. An assignment expression that must retain the converted value needs conversion as well as a correctly sized store.

| Destination width | Unsigned RDI conversion | Signed RDI conversion |
|---:|---|---|
| 1 | `40 0F B6 FF` | `48 0F BE FF` |
| 2 | `48 0F B7 FF` | `48 0F BF FF` |
| 4 | `89 FF` | `48 63 FF` |
| Fallback | No bytes | No bytes |

For the right operand, `cc-emit-convert-rcx` uses CL/CX/ECX instead. Its one-byte unsigned/signed forms are `48 0F B6 C9` / `48 0F BE C9`; two-byte forms use B7/BF with C9; four-byte forms are `89 C9` / `48 63 C9`; fallback emits nothing. Do not copy RDI's bare `40` choice indiscriminately: the actual RCX helper uses `48` and a 64-bit destination for its byte extensions.

The source-aware hooks have `( source destination -- )` interfaces. `cc-emit-convert-value-default` discards source via `nip` and calls `cc-emit-convert-rdi`; `cc-emit-convert-right-default` does the same for RCX. They initially supply `cc-emit-convert-value` and `cc-emit-convert-right`. The defaults depend on destination integer representation because narrowing/sign extension is the work they know how to do. Their existence leaves room for providers whose conversion depends on both types.

`cc-emit-store-local-typed` invokes the type hook, then takes an explicit legacy branch to qword storage. With LP64 active it emits the same byte/word/dword prefixes as pointer storage but supplies local-EA form 7D: `40 88`, `66 89`, or `89`, followed by address bytes; fallback calls the qword local store. It still preserves RDI and still uses slot displacement `−8*(slot+1)`. The disp8/disp32 boundary is independent of the amount written.

### Unsigned operations require the caller's type decision

`cc-emit-udiv-quotient` moves RDI to RAX, emits `31 D2` to zero EDX and therefore all RDX, emits `48 F7 F1` for DIV RCX, and moves RAX back to RDI. `cc-emit-udiv-remainder` instead ends with `48 89 D7`. Zeroing the high dividend half differs from CQO's signed preparation. For a nonzero divisor and a dividend confined to the original 64-bit RDI value, the unsigned quotient fits; division by zero still faults.

The four unsigned comparison wrappers reuse the twelve-byte `cc-emit-cmp-set` shape: `cc-emit-cmp-ult` selects 92 (CF=1), `cc-emit-cmp-uge` selects 93 (CF=0), `cc-emit-cmp-ule` selects 96 (CF=1 or ZF=1), and `cc-emit-cmp-ugt` selects 97 (CF=0 and ZF=0). `cc-emit-shr-rdi-cl` emits `48 D3 EF`, a logical right shift that fills high positions with zeros.

These helpers do not choose the common C type or perform promotions automatically. Callers must select the proper signed/unsigned operation and convert both operands first. C12/C13 and the later target units own that policy. For example, all-ones RDI is signed −1 but unsigned `2^64−1`; choosing SAR versus SHR changes the meaning of a right shift even though the input bits are identical.

### Loading providers is not selecting their profile

The default has `cc-target-lp64=0` and `cc-target-sysv=0`. [121's `cc-sysv-enable`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1337-L1341) explicitly enables System V, LP64, and direct preprocessing, disables bootstrap floatbits, and resets named target state. Its appropriate program driver is also required. LP64 alone does not select that ABI; the native TinyCC path uses a private all-stack convention.

The bounded provider seams are:

- `cc-sysv-track-push/pop` replace the tracking hooks but change their builder-side depth only when System V is active. The pop provider detects accounting underflow with error 239. It does not insert a target-stack guard
- `cc-sysv-restore-callee` adds `48 8B 5D F8`, restoring RBX from `[rbp-8]`, only in its active profile. The matching saved-slot policy belongs to System V functions, not arbitrary slot-zero programs
- `cc-sysv-value-type-check` checks evaluated values under System V. Later `cc-fp-storage-type` preserves that check and maps active binary32 storage to an unsigned four-byte payload; mapping storage is not floating arithmetic conversion
- `cc-fp-convert` and `cc-fp-convert-right` replace the source-aware conversion hooks. Their floating recognition requires System V; nonfloating inputs fall back to the integer defaults

These are inspected hooks in [121-cc-sysv.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth) and [127-cc-binary64.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L1-L23), with [conversion delegation here](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L164-L198). Their presence does not establish complete floating, aggregate, varargs, or ABI behavior. Those mechanisms remain later-volume work.

## Reference: the complete executable envelope

ELF's header locates the program-header table. A `PT_LOAD` entry describes bytes and additional memory for the loader. Section headers serve different organization/linking purposes; this image has none. The [ELF header](https://refspecs.linuxfoundation.org/elf/gabi4+/ch4.eheader.html) and [program-header](https://refspecs.linuxfoundation.org/elf/gabi4+/ch5.pheader.html) specifications define those roles. The exact values below come from this edition's `cc-emit-elf-header`, not from a generic ELF template.

Offsets are hexadecimal; widths are decimal bytes. Every byte in the 120-byte envelope appears in these tables. Initial fields are shown **before final-size patching**.

| Offset | Width | Bytes | Field |
|---|---:|---|---|
| `00` | 4 | `7F 45 4C 46` | ELF magic |
| `04` | 1 | `02` | ELF64 class |
| `05` | 1 | `01` | Little-endian data |
| `06` | 1 | `01` | Identification version |
| `07` | 1 | `00` | OS/ABI tag |
| `08` | 1 | `00` | ABI version |
| `09` | 7 | `00 00 00 00 00 00 00` | Identification padding |
| `10` | 2 | `02 00` | `e_type=ET_EXEC` |
| `12` | 2 | `3E 00` | `e_machine=62`, x86-64 |
| `14` | 4 | `01 00 00 00` | `e_version=1` |
| `18` | 8 | `78 00 40 00 00 00 00 00` | `e_entry=0x400078` |
| `20` | 8 | `40 00 00 00 00 00 00 00` | `e_phoff=64` |
| `28` | 8 | `00 00 00 00 00 00 00 00` | `e_shoff=0` |
| `30` | 4 | `00 00 00 00` | `e_flags=0` |
| `34` | 2 | `40 00` | `e_ehsize=64` |
| `36` | 2 | `38 00` | `e_phentsize=56` |
| `38` | 2 | `01 00` | `e_phnum=1` |
| `3A` | 2 | `00 00` | `e_shentsize=0` |
| `3C` | 2 | `00 00` | `e_shnum=0` |
| `3E` | 2 | `00 00` | `e_shstrndx=0` |

| Offset | Width | Initial bytes | Program-header field |
|---|---:|---|---|
| `40` | 4 | `01 00 00 00` | `p_type=PT_LOAD` |
| `44` | 4 | `07 00 00 00` | `p_flags=read 4 + write 2 + execute 1` |
| `48` | 8 | `00 00 00 00 00 00 00 00` | `p_offset=0` |
| `50` | 8 | `00 00 40 00 00 00 00 00` | `p_vaddr=0x400000` |
| `58` | 8 | `00 00 40 00 00 00 00 00` | `p_paddr=0x400000` |
| `60` | 8 | `00 00 00 00 00 00 00 00` | `p_filesz=0`, pending finalization |
| `68` | 8 | `00 40 01 00 00 00 00 00` | `p_memsz=81920`, or `0x14000` |
| `70` | 8 | `00 10 00 00 00 00 00 00` | `p_align=4096`, or `0x1000` |

The program table ends at `0x40+0x38=0x78`, matching entry placement. `p_offset` and `p_vaddr` have equal remainders modulo 4096. The physical-address field is not a request that this userspace program occupy physical RAM at `0x400000`. The OS/ABI tag also does not certify System V function-call behavior; instruction and runtime policy remain separate.

The segment requests read/write/execute together. That keeps code, data, and later zero-filled storage in one mapping, with a protection tradeoff. There is no separate code/data protection policy, dynamic-linker description, section table, PIE layout, or object-file relocation machinery in this emitter. Loading the separate object writer does not change these bytes into an `ET_REL` file.

### Finish sizes after the file bytes are settled

For this boundary, take C10's global-finalization promise: all file-backed global bytes and any required file padding have been appended, and `cc-bss-size @` records additional zero-filled object storage. We need its resulting counts here, not its placement algorithm.

`cc-filesz-offset` is decimal 96 (`0x60`); `cc-memsz-offset` is 104 (`0x68`). `cc-finalize-elf` writes the final output count into the **low four bytes** of `p_filesz`. It adds that count to `cc-bss-size @`; if the sum exceeds 81,920, it patches the low four bytes of `p_memsz`. Otherwise it leaves the original minimum intact. For a fresh header and one bounded finalization, the result is:

- `p_filesz = final file-byte count`
- `p_memsz = max(81920, final file-byte count + BSS byte count)`

For file count 1024 and BSS count 24, the patched filesz bytes are `00 04 00 00`, followed by the four already-zero high bytes. Memsz remains `00 40 01 00 00 00 00 00`. The 24 BSS bytes do not appear in the file; the remaining minimum headroom is not another allocated C object. For file count 81,920 and BSS 16, memsz grows to 81,936 (`0x14010`), with low bytes `10 40 01 00`.

The ELF loading contract provides zero-valued memory between the segment's file extent and memory extent. This specifies virtual contents, not immediate physical-page residency. Memsz must cover filesz; the finalizer's maximum rule supplies that relation within the stated valid counts.

Why patch only half an eight-byte field? This implementation's selected output limits are 1 MiB by default or 4 MiB in its explicitly selected direct workspace; BSS is bounded at 256 MiB. Their combined bounded extents stay below 2^32, and the upper halves began at zero. The patch is justified by those bounds, not by ELF64 having four-byte size fields. Reusing arbitrary old header bytes or supporting images above 4 GiB would require a different argument. This finalizer does not validate such uses or shrink an already-patched larger memsz on a later call.

C02's append failure remains error 21, and a multi-byte instruction can be partly appended before a later append fails. No rollback is implied. Final-size patching assumes valid header fields and counts. The later write routine's successful return does not itself certify a complete disk file, because its legacy write/close results are discarded. These limits separate a sound paper layout from execution evidence.

## Practice: bytes, state, and boundaries

Use paper or read-only source inspection. These exercises ask for no source edits, builds, or execution. [Graduated hints and checked solutions](../practice/09-solutions.md) are separate. State which profile you use, keep builder and target snapshots separate, and explain the decisive transition rather than giving only final bytes.

### C9-01 — Reconstruct the subtraction

Using the core reset, derive every instruction's starting file offset and target address. Fill RDI, RCX, RSP, `[P-8]`, and the live temporary after each step. Explain why reversing the move-right and restore-left instructions fails. Then derive the total byte count independently from the emitter forms.

### C9-02 — Cross the addressing boundary

Derive complete load and store bytes for slots 15 and 16. Give the new length of the entire core fragment when `pad` occupies slot 16. Decode each ModR/M field. Separately, derive slot −3's address and say why the emitter accepting it does not authorize a negative legacy local allocation.

### C9-03 — Repair a condition value

The real signed comparison sequence starts by zeroing RAX. A hypothetical version omits that step while incoming RAX is `0x100`. Trace `2 < 3` and `3 < 2` through SETL and the final move. Explain why moving the XOR after CMP is a different mistake. Contrast the real C true result with the builder's canonical Forth true.

### C9-04 — Locate the branch field

A JZ starts at output offset 600 and is patched when output reaches 625. Give its returned operand offset, final six bytes, target virtual address, and output position after patching. Diagnose two alternatives: subtracting the opcode offset, and forgetting the four-byte field length. State the flags needed for the CPU to take this target.

### C9-05 — Account for the frame and return

A valid CALL begins with RSP=`0x1000`, old RBP=`0x2000`, and return destination K. The callee uses frame-bytes=256. Derive stack/base pointers after each prologue instruction, addresses of local slots 0 and 31, and every epilogue step. Identify which cells contain return control and which contain saved frame state. Explain why balanced pointers alone do not prove ABI alignment.

### C9-06 — Keep a typed assignment's value

Under LP64 with integer default hooks, RDI=511 and RCX=A, a valid destination. Derive the effects of storing to signed char with and without converting RDI first. Give the stored byte and the expression-register value in each case. Then explain a signed versus unsigned typed load of byte FF and why a four-byte unsigned load clears high register bits.

### C9-07 — Finalize the envelope

Begin with a fresh header, final file count 81,920, and BSS count 16. Give both eight-byte size fields, their patch offsets, and the first byte address beyond the file extent. Explain the zero-filled tail and why only four bytes are patched. Diagnose treating BSS as extra file bytes or treating the minimum memsz as a count of declared C objects.

### C9-08 — Separate arithmetic contracts

For RDI=−7 and RCX=3, give the signed quotient and remainder paths, including RAX/RDX after CQO and IDIV. Compare SAR of −3 by one with signed division by two. Explain the machine result of a 64-bit shift count of 64, then state why that result is not permission for an arbitrary C shift. Identify the two signed-division fault boundaries.

### Changed-case prompts, with answers kept separate

After checking an exercise, close its solution and try the corresponding changed case:

- C9-01: use `pad=5`, right operand 3, and start offset 700; keep slot zero
- C9-02: compare slots −16 and −17; give complete load bytes and separate encoding from ownership
- C9-03: begin RAX at `0xABCDEF0000000000` and evaluate real `!0` and `!256`; compare a hypothetical omitted XOR
- C9-04: a JMP begins at offset 900 with a known earlier target at 880; derive its signed field and explain why patch-to-here at position 905 cannot select that target
- C9-05: use a 128-byte frame from the same call state; then consider the active four-byte RBX restoration hook with a correctly initialized saved slot
- C9-06: change to unsigned short and RDI=`0x12345`; compare a store-only sequence with conversion then store
- C9-07: use file count 4096 and BSS count 100,000; distinguish memory size from its end address
- C9-08: use unsigned RDI=`2^64−1`, RCX=2; then compare SHR and SAR of the same all-ones input by one

If a mismatch appears, classify it: wrong coordinate, instruction length, operand direction, width/extension, stale flags, or wrong profile. Use the first hint that addresses that mismatch. A pause can preserve one completed row and the next question; rereading the whole opcode reference is rarely the smallest repair. Correct assisted work and independent changed-case work are different observations, and neither is evidence of a reader study we have not conducted.

## What this chapter has established

The 23-byte fragment connects a builder's append operations to a future machine's state transitions. Slot addressing, conditions, branches, frames, and typed width choices reuse a small set of encoding fields, while the ELF envelope assigns their file bytes target addresses. The exact source append bytes govern these derivations; comments supply orientation, not an independent specification.

The architectural cross-checks used Intel's October 2024 [Volume 2A, 253666-085US](https://cdrdv2-public.intel.com/835751/253666-sdm-vol-2a.pdf) for instruction formats, CALL, CQO, DIV/IDIV, and IMUL, and [Volume 2B, 253667-085US](https://cdrdv2-public.intel.com/835752/253667-sdm-vol-2b.pdf) for MOV, shifts, SETcc, stack operations, and string operations, consulted October 6, 2026. These specify processor behavior; the source determines which forms are emitted. Manual derivation is the checking method reported here.

C10 next gives delayed destinations a lifetime: calls, wide literal/address fields, inline strings, and fixup records. C11 then uses these instruction contracts to explain the bounded legacy runtime. Neither later subject requires pretending the builder's pointers are target addresses or that emitted bytes have already executed.
