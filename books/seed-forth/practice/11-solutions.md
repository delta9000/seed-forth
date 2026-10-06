# Executable and entry: hints and solutions

Return to [Chapter 11](../chapters/11-executable-and-entry.md). These are checked byte and address derivations for the pinned Linux/x86-64 seed, not execution results. Hexadecimal bytes are listed from lower to higher addresses. Half-open ranges include the start and exclude the end.

Use Hint 1 for an orientation, Hint 2 for a specific transition, or the solution when useful. After checking, close the answer and try the changed case. All changes below are paper cases, not instructions to modify or run the executable.

## S11-01 — Decode the two coordinate systems

**Hint 1.** Identify each field before interpreting the decoded integer. The byte order is shared; the field's role is not.

**Hint 2.** Offset `0x018` contains `78 00 40 00 00 00 00 00`. Offset `0x020` contains `40 00 00 00 00 00 00 00`. Add one `0x38`-byte entry to the latter value.

**Worked solution.** The first field is `e_entry=0x400078`, a virtual instruction address. Its nonzero contributions are `0x78` and `0x40 × 0x10000`. The second is `e_phoff=0x40`, a file offset. Both occupy eight bytes and both use little-endian representation. Neither width nor byte order labels a number as an address of a particular kind; the ELF field definition supplies that meaning.

The program-header table starts at file offset `0x40`, has one entry, and uses `0x38` bytes per entry. Its end is `0x40+1×0x38 = 0x78`. This is immediately after the 64-byte ELF header and 56-byte program header. The first code byte there maps to `0x400000+0x78 = 0x400078`, agreeing with the entry field.

**Wrong path to diagnose.** Treating `e_phoff` as virtual address `0x40` misses the file-relative coordinate system. Conversely, using `e_entry=0x400078` as a file offset would seek far beyond the 1,772-byte file. The same eight-byte representation does not make these uses interchangeable.

**Changed case.** In a hypothetical image with the same segment base, the table still starts at `0x40` but has two `0x38`-byte entries, with code immediately afterward. The table ends at `0xB0`; the new entry address would be `0x4000B0`, encoded `B0 00 40 00 00 00 00 00`. This is layout arithmetic only. It does not assert that adding a second table entry alone produces a valid executable or repairs other embedded addresses.

## S11-02 — Find the file boundary

**Hint 1.** Compute the exclusive end of the file-derived range before classifying individual addresses.

**Hint 2.** Add `0x6EC` to the virtual base `0x400000`. The end itself belongs to the zero-valued tail, not the file portion. Then separate the time before startup stores from the time after them.

**Worked solution.** The file-derived range is `[0x400000, 0x4006EC)`. Therefore:

| Address | Initial source | Later fact relevant to this question |
|---|---|---|
| `0x4006EB` | Last file byte | Not initially zero by a loader-tail guarantee |
| `0x4006EC` | First zero-valued tail byte | Not present in the file |
| `0x401000` | Zero-valued tail | Initial dictionary cursor points here |
| `0x413010` | Zero-valued tail | Startup stores the HERE value here |

Immediately after startup, the cell beginning at `0x413010` contains `0x401000`. Its eight bytes are `00 10 40 00 00 00 00 00`. The cell's address remains `0x413010`; the stored value is another address. The startup store changes this cell, not the bytes at the cursor's destination `0x401000`.

The segment's virtual extent is 16 MiB; only 1,772 bytes originate in the file. The larger memory size neither expands the on-disk file nor establishes that every virtual page already has a distinct resident physical page. Demand paging and memory policy determine backing. A read returning zero is a statement about a byte value, not a full report about page residency.

**Wrong path to diagnose.** Subtracting the base from `0x401000` gives `0x1000`, but this merely calculates a segment-relative position. Since `0x1000 >= 0x6EC`, there is no corresponding byte in the original file. Also avoid calling HERE's zero-valued initial destination “unmapped”: the mapping contract includes it.

**Changed case.** Suppose a separate hypothetical image has `p_filesz=0x900`, the same base, and `p_memsz=0x1000000`. Its file-derived end is `0x400900`; `0x4008FF` is its last file byte. Its memory end remains `0x1400000`. The changed file size moves the file/zero boundary, not the end of the virtual extent. This comparison assumes an actual file with those supplied bytes and successful loading.

## S11-03 — Separate destination, value, and width

**Hint 1.** Split the instruction into the fixed four-byte encoding pattern, the four address bytes, and the four immediate bytes.

**Hint 2.** Read `08 30 41 00` as the destination and `17 06 40 00` as the value. The `48` prefix selects the 64-bit store form; the immediate is sign-extended.

**Worked solution.** The complete instruction is:

```text
48 C7 04 25 | 08 30 41 00 | 17 06 40 00
pattern       destination   immediate
```

Its destination is `0x413008`, the LATEST cell. Its immediate is `0x400617`, the `0branch` header address. Twelve instruction bytes occupy offsets `[0x091,0x09D)`. The store writes eight memory bytes at addresses `[0x413008,0x413010)`:

```text
17 06 40 00 00 00 00 00
```

The immediate's high bit is clear, so sign-extending it introduces zero high bits. This is not a four-byte store followed by whatever happened to be in adjacent memory. The instruction explicitly writes all eight bytes. It also does not read the memory at `0x400617`; it copies that number into LATEST.

**Wrong path to diagnose.** Instruction length, immediate width, and memory-access width answer three different questions. Here their answers are twelve, four, and eight bytes. Counting only the immediate measures neither the instruction's length nor its store width.

**Changed case.** Keep the destination and encoding pattern but use immediate bytes `FF FF FF FF`. The signed 32-bit immediate represents -1. Sign-extension produces the 64-bit all-ones value, so all eight destination bytes become `FF`. A prediction of four `FF` bytes followed by four zeros would describe zero-extension, which this instruction form does not perform. The unchanged instruction still occupies twelve bytes and writes eight.

## S11-04 — Repair the jump arithmetic

**Hint 1.** Derive the address after the five-byte instruction independently of the desired target.

**Hint 2.** The CPU adds the displacement to `0x4000BA`. If the worksheet subtracts only `0x0B5`, its displacement is five too large.

**Worked solution.** The worksheet obtains `0x699-0x0B5 = 0x5E4`. Its four encoded displacement bytes would be `E4 05 00 00`. From a jump starting at `0x4000B5`, these would reach:

```text
0x4000B5 + 5 + 0x5E4 = 0x40069E
```

That is five bytes beyond the intended `0x400699`. The correct subtraction is `0x699-(0x0B5+5) = 0x5DF`, encoded as `DF 05 00 00`. Including the opcode, the actual instruction is `E9 DF 05 00 00`.

The equivalent virtual-address subtraction is `0x400699-0x4000BA = 0x5DF`: the common mapping base cancels. “Next address” remains meaningful even though the byte at `0x4000BA` belongs to `dup`'s header, not a fall-through instruction.

**Wrong path to diagnose.** Using a correct little-endian encoding of a wrong displacement still produces a wrong jump. Check the reference address before checking byte order. In the opposite error, interpreting the actual displacement from the first byte would predict `0x400694`; that is a mistaken analysis of the correct instruction, not the worksheet's incorrectly encoded target.

**Changed case.** Keep the jump at the same address but choose a hypothetical target sixteen bytes after the real target, `0x4006A9`. The end remains `0x4000BA`. The displacement becomes `0x5EF`, with bytes `EF 05 00 00`. This tests arithmetic only; it does not assert that `0x4006A9` is an appropriate routine entry.

## S11-05 — Explain what startup does not establish

**Hint 1.** Assign each responsibility to a component: existing file contents, Linux loader, or seed instruction. Then ask which register each instruction actually writes.

**Hint 2.** The first instruction writes `rbp`, not `rsp`. LATEST is initialized to a header already present in the file. The register zero is baseline state for the stack representation.

**Worked solution.** A corrected summary is:

- The file already contains the built-in dictionary's headers and bodies. The ELF headers describe loading; the startup store makes LATEST point to the existing `0branch` header at `0x400617`
- `xor rdi,rdi` supplies the cached-stack baseline. The logical data stack is initially empty; zero is not a user input pushed by the outer loop
- `movabs rbp,0x411000` initializes the data-stack pointer. No startup instruction writes `rsp`; it continues to refer to the process stack supplied by Linux
- An already-running kernel loads this userspace process and transfers control to `0x400078`. This program does not boot or replace that kernel

The four system cells are initialized explicitly, and the jump reaches the REPL under the stated machine and loading assumptions. Other general registers have not all been initialized by this block. The REPL, primitive bodies, later emitted code, invalid inputs, resource limits, and trusted operating-system machinery remain outside this startup derivation. Static disassembly agrees about instruction decoding; it is neither an execution test nor a correctness proof of those components.

**Wrong path to diagnose.** A complete count of this region's bytes is not a count of all behaviors checked. A disassembler can decode an instruction that would be unsafe under particular register values or memory conditions. Coverage and correctness require different evidence.

**Changed case.** Suppose the headers request the same address range but an execution policy refuses writable executable mappings. The conditional startup trace does not begin: its successful-loading precondition fails. Do not claim an initialized HERE or a reached REPL from the header bytes alone. That failure also does not identify a wrong instruction in the source; it identifies a mismatch with the required execution environment.
