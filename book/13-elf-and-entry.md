# Chapter 13 — The ELF and the Entry Point

> **Status:** structural stub.  Section plan and chunk roster are in
> place; the canonical hex chunks are added as you write the chapter.
> See "Canonical chunks" below for the planned `<<name>>` boundaries.

## Goal

By the end of this chapter the reader can:

- explain the layout of a minimal 64-bit Linux ELF executable
  (`Elf64_Ehdr` + one `Elf64_Phdr`);
- compute the entry-point address `0x400078` and verify it against
  the byte at offset `0x18` in the file;
- read the `_start` prologue and the sysvar-init code at `0x085`;
- explain why the program header maps 16 MiB even though the on-disk
  image is only 2,040 bytes.

## Source coverage

`000-seed.hex0` lines 1–63 (file header, ELF + program header,
`_start`, sysvar init, the `JMP repl` at `0x0CD`).

## Concepts introduced

- **`Elf64_Ehdr`** — the 64-byte file header: magic, class,
  endianness, OS ABI, type (`ET_EXEC`), machine (`EM_X86_64`), entry
  point, program-header offset, etc.
- **`Elf64_Phdr`** — one program header describing a single
  `PT_LOAD` segment with R|W|X flags.
- **The 16 MiB virtual mapping.**  `p_memsz = 0x1000000` so the
  Forth compiler can scratch into pages that don't exist on disk.
- **The data-stack convention.**  `rbp` is the data-stack pointer;
  `rdi` holds TOS as a register cache; the stack grows down from
  `0x411000`.
- **The sysvar page at `0x413000`.**  Six cells: `STATE`, `LATEST`,
  `HERE`, `LAST_FOUND`, `NUMBER_HOOK`, `INPUT_FD`.

## Concepts carried in

- Nothing from Part I.  Part II is the *opening* of the seed black
  box; everything Part I treated as a primitive is now revealed.

## Concepts deferred

- Each primitive's body bytes — Chs 14–19.
- The dictionary headers (the `--- bye @ 0x44D ---` style entries) —
  Ch 17.
- `parse_decimal_code` and the REPL — Ch 20.

## Section plan

1. **Why we're here.**  Part I treated the 32 primitives as black
   boxes.  Now we open them.  We start at the top of `000-seed.hex0`
   because every primitive's offset is measured from the entry point.
2. **The ELF magic and `Elf64_Ehdr`.**  Walk the first 64 bytes
   field by field.  Cross-reference `man 5 elf` for each entry.
3. **The single `Elf64_Phdr`.**  One `PT_LOAD` segment, R|W|X,
   `p_offset = 0`, `p_vaddr = 0x400000`, `p_filesz = 2040`, `p_memsz
   = 16 MiB`.  Why one segment is enough.
4. **`_start` at `0x400078`.**  `mov rbp, 0x411000` initialises the
   data stack; `xor rdi, rdi` clears TOS.
5. **The sysvar init at `0x085`.**  Six `mov [imm32], imm32`
   instructions seed the sysvar page.  Note that `LATEST` is
   initialised to the entry address of the last hand-written word
   (`'` at `0x4007E8`) — chained-list initialisation is done at
   *assembly* time, not runtime.
6. **`JMP repl` at `0x0CD`.**  The first 32-bit signed displacement
   you'll compute by hand.  `rel32 = 0x35E − (0x0CD + 5) = 0x28C`.

## Canonical chunks

This chapter introduces the following named chunks (defined in this
chapter's writing; referenced by the root block):

- `<<file-header-comment>>` — the `;; 000-seed.hex0 — ...` banner.
- `<<elf-header>>` — bytes 0..63.
- `<<program-header>>` — bytes 64..119.
- `<<entry-point>>` — `_start` at `0x078`.
- `<<sysvar-init>>` — the six `mov [imm32], imm32` calls at `0x085`.
- `<<jmp-to-repl>>` — the single `JMP rel32` at `0x0CD`.

This chapter is also responsible for opening the root block that
later chapters add to:

```
\ TODO (when writing): emit a fenced block of the form
\
\   ```hex0 file=000-seed.hex0
\   <<file-header-comment>>
\   <<elf-header>>
\   <<program-header>>
\   <<entry-point>>
\   <<sysvar-init>>
\   <<jmp-to-repl>>
\   ```
\
\ Each chunk's body is a separate fenced block tagged
\ `chunk=<name>`, containing the hand-laid-out hex from
\ 000-seed.hex0 lines 11..30, 33..40, 51..52, 55..60, 63 respectively.
```

## Try it

```sh
./build.sh    # assembles 000-seed.hex0; you should get a 2040-byte ELF.
file ./seed-forth
readelf -h ./seed-forth     # confirms the header we just read.
readelf -l ./seed-forth     # confirms the one PT_LOAD segment.
```

Compare the `readelf` output to the hex you read in this chapter,
field by field.

## Exercises

1. The entry point is at `0x400078`.  The header is 64 bytes plus one
   56-byte program header — total 120 bytes.  Why is the entry at
   offset `0x78` (=120) and not, say, `0x100`?

2. `p_memsz = 16 MiB` but `p_filesz = 2040`.  What does the kernel do
   with the bytes between `2040` and `16 MiB`?  (Hint: trace what
   happens when seed-forth writes to `0x420000`.)

3. The sysvar `LATEST` is initialised at assembly time to the entry
   of the `'` primitive.  Why not initialise it to zero and have the
   REPL walk the chain to find the tail?  (Hint: count clock cycles
   on startup; compare to the cost of one `mov`.)

4. Why R|W|X for the single segment?  What would change if you split
   it into separate R-X (code) and R-W (sysvars + heap) segments?

## Takeaways

- A 64-bit Linux ELF can be written by hand in 120 bytes and still
  satisfy the kernel's loader.
- The seed maps one big R|W|X segment that includes its own
  compile-time-allocated buffers, avoiding any need for `mmap`.
- Every primitive in the next six chapters is reachable from this
  entry point via direct address; we will measure each one's offset
  from `0x400078` as we go.

Next: Chapter 14 — Stack Primitives in Machine Code.
