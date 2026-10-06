# 11. From executable bytes to the entry point

[Previous: Storage, deferred words, and bytes](10-storage-deferred-words-and-bytes.md) · [Practice help](../practice/11-solutions.md) · [Next: Physical stacks and memory](12-physical-stacks-and-memory.md)

Chapter 2 distinguished an address from the value stored there. We can now replace its invented locations with two real ones: the seed stores `0x401000` **at** `0x413010`. The first is where new dictionary bytes will begin; the second is HERE's system-variable cell. Neither location exists in the 1,772-byte file. How can its startup code write there?

The answer crosses two interfaces. The executable's headers ask Linux to establish memory. Then seven machine instructions establish the seed's own state. We will account for all 120 header bytes and all 66 startup bytes, ending at the jump into the input loop.

By the end, you should be able to decode a little-endian field, translate a file offset into a process address, distinguish file-backed bytes from initially zero bytes, and derive the startup jump's target. This opens the machine-code audit without requiring you to memorize an instruction manual.

## Choose your route and evidence boundary

Bring the byte/address distinction from [Chapter 2](02-addresses-and-bytes.md), call/return destinations from [Chapter 4](04-return-stack-and-shuffles.md), little-endian writers from [Chapter 6](06-memory-updates-and-writers.md), and headers, execution tokens, and relative calls from [Chapter 8](08-defining-words-and-phases.md).

Two quick checks: what cell value begins with bytes `34 12` followed by six zero bytes? Does `here` return HERE's cell address? The answers are `0x1234`, or decimal 4660, and no: `here` returns its contents. If either is uncertain, revisit the corresponding memory trace. If both are secure, try S11-01 and S11-04 first, then use the field tables as a reference. Experienced assembly readers can skip the instruction-reading bridge, but should still check the edition's memory layout.

**Edition and method.** Our primary evidence is [`000-seed.hex0`, headers through startup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L19-L74), at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`. Values below were checked against its bytes. GNU objdump 2.44 also statically disassembled virtual addresses `[0x400078,0x4000BA)` from an exact byte-decoded copy; readelf independently displayed its ELF fields. That checks a decoding, not a running process. No build, seed execution, compiler run, or full-system proof is claimed.

The execution model assumes Linux on x86-64 in 64-bit user mode, successful loading at the requested virtual addresses, usable process-stack memory, and permission to use the requested readable/writable/executable segment. Host policy and resource limits can prevent loading. We trust the loader, virtual-memory machinery, and CPU instruction semantics here; inspecting the seed does not audit those systems.

## Read numbers before reading instructions

In a byte listing, `EC` means one hexadecimal byte: fourteen sixteens plus twelve, or decimal 236. Hex digits are `0`–`9`, then `A`–`F` for ten through fifteen. The prefix `0x` marks a whole number as hexadecimal. Thus `0x10` is decimal 16, while the adjacent byte pair `10 00` occupies two locations.

Little-endian order gives successive bytes weights 1, 256, 65536, and so on. Decode the file-size bytes by their positions:

```text
EC 06 00 00 00 00 00 00
236 + 6 × 256 = 1772 = 0x6EC
```

The entry field uses the same rule:

```text
78 00 40 00 00 00 00 00
0x78 + 0x00 × 0x100 + 0x40 × 0x10000 = 0x400078
```

Do not reverse the digits inside a byte. `78` remains `78`; only the weights of successive **bytes** increase. Nor do we reverse an entire instruction: its prefix, opcode, address bytes, and value bytes have separate roles.

We use half-open ranges such as `[0x000, 0x040)`: include the first address and stop before the second. This range contains `0x40`, or 64, bytes. Byte listings run from lower to higher addresses, left to right. Hexadecimal in these explanations is display notation, not seed literal syntax; the earlier `[lit]` decimal-input contract has not changed.

## Give each address its coordinate system

A **file offset** counts bytes from the beginning of a file. A **virtual address** identifies a location in this process's address space. It is not a physical RAM address. For a byte within a loadable segment's file portion, the general relationship is:

```text
virtual address = p_vaddr + (file offset - p_offset)
```

This seed chooses `p_offset=0` and `p_vaddr=0x400000`, giving:

```text
virtual address = 0x400000 + file offset
file offset     = virtual address - 0x400000
```

For example, the entry byte at offset `0x078` belongs at `0x400078`. The `dup` body at offset `0x0C7` belongs at `0x4000C7`. These are two descriptions of corresponding bytes, not two numeric values to interchange in an instruction.

The inverse calculation does not prove a byte exists in the file. Subtracting the base from HERE's initial value `0x401000` gives `0x1000`, but the file ends at offset `0x6EC`. That location belongs to the segment's additional memory, not its file contents.

Absolute pointers in the seed assume this fixed layout. Changing the load address alone would not update the embedded pointers. Relative distances can survive moving both endpoints together, but that does not make the complete seed relocatable.

## The headers describe loading, not Forth words

**ELF**, the Executable and Linkable Format, is the container Linux reads. Its **ELF header** identifies the file and locates other header tables. A **program header** describes a segment to load or other process-loading information. **Section headers** describe organized regions useful to linkers and inspection tools. They are not the same table.

This file has one program header, of type `PT_LOAD`, and no section-header table. Its loader uses the segment description; it does not need section names such as `.text`. These roles follow the [ELF header specification](https://refspecs.linuxfoundation.org/elf/gabi4+/ch4.eheader.html) and [program-header specification](https://refspecs.linuxfoundation.org/elf/gabi4+/ch5.pheader.html). The actual values below come from the pinned seed.

### All 64 ELF-header bytes

Offsets and byte strings below are hexadecimal; widths are decimal. Every byte in `[0x000, 0x040)` appears once.

| Offset | Width | Bytes | Field and meaning in this image |
|---|---:|---|---|
| `000` | 4 | `7F 45 4C 46` | Identification magic: byte `7F`, then `ELF` |
| `004` | 1 | `02` | Class: ELF64 |
| `005` | 1 | `01` | Data encoding: little-endian |
| `006` | 1 | `01` | Identification version: 1 |
| `007` | 1 | `00` | OS/ABI tag: no specified extensions, conventionally System V |
| `008` | 1 | `00` | ABI version: 0 |
| `009` | 7 | `00 00 00 00 00 00 00` | Identification padding |
| `010` | 2 | `02 00` | `e_type`: executable, `ET_EXEC` |
| `012` | 2 | `3E 00` | `e_machine`: 62, x86-64 |
| `014` | 4 | `01 00 00 00` | `e_version`: 1 |
| `018` | 8 | `78 00 40 00 00 00 00 00` | `e_entry`: virtual address `0x400078` |
| `020` | 8 | `40 00 00 00 00 00 00 00` | `e_phoff`: program-header table at file offset `0x40` |
| `028` | 8 | `00 00 00 00 00 00 00 00` | `e_shoff`: no section-header table |
| `030` | 4 | `00 00 00 00` | `e_flags`: no processor-specific flags set |
| `034` | 2 | `40 00` | `e_ehsize`: 64-byte ELF header |
| `036` | 2 | `38 00` | `e_phentsize`: 56 bytes per program header |
| `038` | 2 | `01 00` | `e_phnum`: one program header |
| `03A` | 2 | `00 00` | `e_shentsize`: zero, with no section table |
| `03C` | 2 | `00 00` | `e_shnum`: no section entries in this image |
| `03E` | 2 | `00 00` | `e_shstrndx`: no section-name string table |

Read the structure, not twenty independent facts: the table starts at `0x40`, has one entry of `0x38` bytes, and therefore ends at `0x78`. Adding the mapping base gives `0x400078`, matching `e_entry`. Here the entry is immediately after both headers. ELF does not require every executable to put its entry there.

The zero OS/ABI tag does not make the program operating-system independent. Later instructions use Linux's system-call interface. Nor does every zero field mean “the kernel checks this must be zero”; some fields describe absent structures or reserved space.

### All 56 program-header bytes

This table covers `[0x040, 0x078)` without gaps.

| Offset | Width | Bytes | Field and meaning in this image |
|---|---:|---|---|
| `040` | 4 | `01 00 00 00` | `p_type`: `PT_LOAD`, a loadable segment |
| `044` | 4 | `07 00 00 00` | `p_flags`: read 4 + write 2 + execute 1 |
| `048` | 8 | `00 00 00 00 00 00 00 00` | `p_offset`: file portion starts at zero |
| `050` | 8 | `00 00 40 00 00 00 00 00` | `p_vaddr`: virtual start `0x400000` |
| `058` | 8 | `00 00 40 00 00 00 00 00` | `p_paddr`: `0x400000`; not a physical placement request used by this Linux loader |
| `060` | 8 | `EC 06 00 00 00 00 00 00` | `p_filesz`: 1,772 bytes supplied by the file |
| `068` | 8 | `00 00 00 01 00 00 00 00` | `p_memsz`: `0x1000000` bytes of segment memory |
| `070` | 8 | `00 10 00 00 00 00 00 00` | `p_align`: `0x1000`, or 4096-byte alignment |

For `p_memsz`, the nonzero byte is the fourth byte: its weight is `256³`, giving 16,777,216 bytes, or 16 MiB. For alignment, `p_offset` and `p_vaddr` have the same remainder modulo `0x1000`, namely zero. This matches the 4096-byte page arrangement used here; do not infer every ELF requires these exact addresses.

## A small file describes a larger virtual extent

The [ELF `PT_LOAD` contract](https://refspecs.linuxfoundation.org/elf/gabi4+/ch5.pheader.html) divides this segment into two ranges before startup writes:

| Virtual range | Initial source of byte values |
|---|---|
| `[0x400000, 0x4006EC)` | The file's 1,772 bytes, including both headers |
| `[0x4006EC, 0x1400000)` | Zero-valued memory beyond the file portion |

The second end is `0x400000 + 0x1000000`, not `0x1000000`. `p_memsz` is a length. The last file-derived byte is at `0x4006EB`; `0x4006EC` is the first byte beyond it.

This is a **virtual mapping extent**, not evidence that Linux immediately allocates and touches 16 MiB of distinct physical pages. Linux can provide zero-valued anonymous memory through [demand paging](https://www.kernel.org/doc/html/v6.12/admin-guide/mm/concepts.html); physical backing and accounting depend on accesses and policy. The [Linux ELF loader](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/fs/binfmt_elf.c) handles the file-page tail and additional memory separately. A header alone is not a measurement of resident memory.

The seed assigns several roles inside that extent:

| Address | Role established or used by the seed |
|---|---|
| `0x401000` | Initial HERE cursor; new dictionary storage grows upward |
| `0x411000` | Initial data-stack pointer; stored stack cells grow downward |
| `0x412000` | Single-byte I/O scratch location |
| `0x412800` | Token input buffer, TIB |
| `0x413000` | STATE cell |
| `0x413008` | LATEST cell |
| `0x413010` | HERE cell |
| `0x413018` | LAST_FOUND cell |

Being inside the segment is insufficient permission to use a location for arbitrary data. The growing dictionary can collide with live stack storage and reserved regions. The full 16 MiB is not one unconditionally available dictionary arena; recall [Chapter 10's layout-specific cursor change](10-storage-deferred-words-and-bytes.md#deeper-boundary-skip-vm-pages-is-a-profile-specific-jump).

The segment requests read, write, and execute permissions because the seed writes native instructions and later runs them there. This is a compact implementation choice with a protection tradeoff. Separating fixed code from data is possible, but newly generated code still needs an execution-permission strategy; the mere number of segments does not determine when a permission-changing syscall is needed.

**Stop/resume.** Save “file end `0x4006EC`, initial cursor `0x401000`, HERE cell `0x413010`.” On return, explain why these are three different locations before continuing to instructions.

## A small instruction-reading key

A **register** is named CPU storage: `rbp`, `rdi`, and `rsp` hold 64-bit values here. An **immediate** is a value encoded inside an instruction. A **memory operand** refers to bytes at an address. In the Intel-style notation used below, the destination comes first:

```text
mov rbp, 0x411000          copy an immediate value into rbp
mov rax, [rbp]            read memory at the address held in rbp
mov qword [0x413010], ... write eight bytes at that address
```

Brackets in assembly mean memory access, unlike our earlier Forth stack pictures. `qword` means an eight-byte quantity; it says how much memory is accessed, not how many bytes encode the instruction.

An instruction's **opcode** selects its operation. Other encoding bytes select operands or alter the operation's width. In these startup forms, `48` is a **REX prefix** with its W bit set, selecting 64-bit operands. It is part of the following instruction, not a standalone operation. It does not imply that every following immediate occupies eight bytes.

x86 instructions have variable lengths. We record each known boundary as `offset: bytes ; meaning`. A newline in the source is helpful annotation; the CPU does not see it. A disassembler given the wrong boundary can mistake data or an immediate for an opcode. The ISA reference is [Intel's Software Developer's Manual, Volume 2](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html), particularly instruction formats and the MOV, XOR, and JMP entries.

## Seven instructions establish the starting state

Here are all bytes in `[0x078, 0x0BA)`. The left column gives **file offsets**; add `0x400000` for instruction addresses.

```text
078: 48 BD 00 10 41 00 00 00 00 00       ; movabs rbp, 0x411000
082: 48 31 FF                            ; xor rdi, rdi
085: 48 C7 04 25 00 30 41 00 00 00 00 00 ; mov qword [0x413000], 0
091: 48 C7 04 25 08 30 41 00 17 06 40 00 ; mov qword [0x413008], 0x400617
09D: 48 C7 04 25 10 30 41 00 00 10 40 00 ; mov qword [0x413010], 0x401000
0A9: 48 C7 04 25 18 30 41 00 00 00 00 00 ; mov qword [0x413018], 0
0B5: E9 DF 05 00 00                      ; jmp 0x400699
```

First, `48 BD` selects a move of an eight-byte immediate into `rbp`. The remaining eight bytes decode to `0x411000`. GNU objdump calls this form `movabs`; the source comment calls it `mov`. They describe the same ten bytes, not two different actions.

Next, `48 31 FF` XORs `rdi` with itself. Each bit XOR itself is zero, so the resulting `rdi` is zero. `31` selects XOR; the operand byte `FF` selects registers, with `rdi` as both operands. XOR also changes arithmetic flags, but the unconditional startup path does not use those results.

These establish the physical representation behind an initially empty logical data stack. `rbp` points at the base, and `rdi` is the cached top-of-stack register. Its initial zero is a baseline value, not an extra user-visible Forth item. A later push spills the old cached value at `0x411000-8 = 0x410FF8` before replacing the top. Chapter 12 will trace that representation and its limits.

### Decode one store, then reuse its pattern

Take the HERE initialization at offset `0x09D`:

```text
48            REX.W prefix: select the 64-bit operand form
C7            immediate-to-destination move opcode
04 25         operand/addressing selection bytes
10 30 41 00   destination address
00 10 40 00   immediate value
```

`C7` with the selected operation bits is a move of an immediate into the destination. The **ModR/M** byte `04` selects the memory form and a following **SIB** addressing byte. That SIB byte, `25`, selects no index and no base register in this encoding, leaving the next four bytes to supply the address. You need not memorize these bit fields yet; recognize the complete `48 C7 04 25` pattern and its two distinct four-byte payloads.

`10 30 41 00` gives destination `0x413010`. `00 10 40 00` gives immediate `0x401000`. This instruction sign-extends its 32-bit immediate to 64 bits and writes a **qword**. All four startup immediates have their sign bit clear, so their high four stored bytes are zero. Its length is `1+1+2+4+4 = 12` bytes, while its store width is eight bytes. Immediate width and store width differ.

After the four stores, the established state is:

| Cell address | Cell | Contents | Consequence |
|---|---|---|---|
| `0x413000` | STATE | `0` | Interpret mode |
| `0x413008` | LATEST | `0x400617` | Head of the existing primitive dictionary |
| `0x413010` | HERE | `0x401000` | Cursor for new dictionary bytes |
| `0x413018` | LAST_FOUND | `0` | No remembered successful lookup yet |

`0x400617` is the **header** of `0branch`, not its code address. The [pinned header and body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L613-L631) make that distinction visible. Zeroing STATE and LAST_FOUND repeats the initially zero memory values explicitly. We account for the instructions actually present rather than optimizing them away.

Later definitions write new headers and bodies beginning at HERE, advance the cursor, and update LATEST. The runtime dictionary consequently includes newly generated bytes outside the original file and links back into the built-in entries. The file does not grow merely because its process writes memory. This is why the library-level words you traced earlier need not all exist as machine code in the 1,772-byte image.

## Jump from the end of the instruction

`E9` introduces a direct jump with a signed four-byte relative displacement. Decode `DF 05 00 00` as `0x5DF`, positive because its sign bit is clear. As with Chapter 8's calls, the reference point is the address **after the entire instruction**:

```text
jump starts:       0x4000B5
instruction size:          5
next address:      0x4000BA
add displacement:   +0x5DF
jump target:       0x400699
```

Using file offsets gives the same distance: `0x699-0x0BA = 0x5DF`. Subtracting from the jump's first byte would incorrectly give `0x5E4`. If encoded, that larger displacement would land five bytes too far forward.

“Next address” is an arithmetic origin, not a claim that an instruction actually begins there. Offset `0x0BA` starts `dup`'s dictionary **header**. The unconditional jump skips that data and the intervening routines, reaching [`repl` at offset `0x699`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L664-L689). Unlike a call, this jump saves no return address.

Linux has already supplied a process stack through `rsp`. Startup does not replace it; the seed uses that stack for native return addresses and its return-stack operations. It initializes `rbp` and `rdi`, not every register. Entry itself is not an ordinary call with a caller's return destination to pop.

This is **userspace process loading** by an already-running Linux kernel. It does not initialize hardware, establish the CPU's initial boot mode, or boot a kernel. Those are different tasks with different entry contracts.

## Practice

Use paper or a read-only byte listing. No exercise asks you to edit or execute the seed. [Hints, checked solutions, and changed cases](../practice/11-solutions.md) are separate so you can attempt a prediction first.

### S11-01 — Decode the two coordinate systems

Decode the eight bytes at offset `0x018` and the eight at `0x020`. Which result is a virtual address, and which is a file offset? Use the table's entry count and entry size to derive where the headers end. Explain why decoding both eight-byte fields identically does not make their meanings identical.

### S11-02 — Find the file boundary

Classify `0x4006EB`, `0x4006EC`, `0x401000`, and `0x413010` as file-derived or initially zero memory. Then give the value of the cell at the last address after startup. Diagnose “the 16 MiB segment is all file data” and “all 16 MiB must already occupy separate physical pages.”

### S11-03 — Separate destination, value, and width

Decode the store at `0x091`: give its memory destination, immediate value, instruction length, store width, and resulting eight bytes at the destination. A reviewer says it writes four bytes because its immediate has four bytes. Locate the mistaken inference.

### S11-04 — Repair the jump arithmetic

A worksheet computes the startup displacement as `0x699-0x0B5`. Give the displacement it would encode and the actual target those bytes would reach from `0x4000B5`. Then restore the correct displacement and its four bytes. Show the instruction-end calculation explicitly.

### S11-05 — Explain what startup does not establish

A proposed summary says: “The ELF headers create the dictionary, the zero in `rdi` is the first Forth input, and `rsp` is changed to `0x411000`. Loading this file boots the kernel.” Correct each claim using one specific field or instruction. Explain why neither static disassembly nor this startup trace proves the rest of the seed correct.

## Close the first audit region

If a result differs, classify the problem before rereading everything: byte order, file-versus-memory coordinates, address-versus-contents, instruction boundary, or a claim beyond the evidence. Use that exercise's first hint, then retry its changed case with the solution closed. You can stop with the three saved addresses or the jump calculation; both are complete subproblems.

Coverage is exact: `[0x000,0x040)` contains 64 ELF-header bytes; `[0x040,0x078)` contains 56 program-header bytes; `[0x078,0x085)` contains 13 register-initialization bytes; `[0x085,0x0B5)` contains 48 sysvar-store bytes; `[0x0B5,0x0BA)` contains the five-byte jump. Total: **186 of 1,772 image bytes accounted for**, with no gap or overlap in this region.

That is coverage of the representation and a conditional startup derivation, not a percentage of system correctness. We have left the loader and CPU as explicit trusted interfaces and have not traced the REPL yet. Next, [Physical stacks and memory](12-physical-stacks-and-memory.md) follows the built-in words immediately after this region and turns the register conventions into stack transitions you can check.
