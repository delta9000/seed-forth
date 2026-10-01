# Appendix B — The memory map

Two memory regimes appear in this book:

1. **The seed-Forth VM**: one `PT_LOAD` segment of 16 MiB starting
   at virtual address `0x400000`.  Everything the seed needs (code,
   dictionary headers, the heap that `HERE` walks across, the data
   stack, the I/O scratch byte, the token buffer, and the sysvars)
   lives inside this one segment.  No `mmap` calls; the kernel
   zero-fills the part of the segment that extends past the on-disk
   image.

2. **The C compiler's runtime heap**: a 256 MiB anonymous mmap that
   compiled programs allocate from with a bump-allocator `calloc`
   shim.  Sized to host M2-Planet self-compiles without ever calling
   `free` (which is a no-op).  This region is *outside* the seed's
   16 MiB and is allocated lazily by Linux on first touch.

## The seed-Forth memory map (`PT_LOAD` covers `0x400000..0x1400000`)

The picture puts higher addresses at the top; `^` and `v` mark
which way a region fills.

```text
0x1400000 +-----------------------------------------+ end of the 16 MiB PT_LOAD
          | unused tail                             |
          |                                         |
          | ^ compiler tables: macros, macro        |
          |   scratch, includes, symbols, scopes,   |
          |   globals, fixups (grow up; ~3.7 MiB)   |
0x814000  +-----------------------------------------+
          | output buffer                 1 MiB     |
0x714000  +-----------------------------------------+
          | source buffer (preprocessed)  2 MiB     |
0x514000  +-----------------------------------------+
          | input buffer (stdin)          1 MiB     |
0x414000  +-----------------------------------------+ <-- skip-vm-pages jumps HERE here
0x413000  | sysvars, 8 bytes each: STATE, LATEST,   |
          | HERE, LAST_FOUND (rest of page unused)  |
0x412800  | token buffer (read_word)                |
0x412000  | I/O scratch byte (emit, key)            |
0x411000  +-----------------------------------------+ <-- rbp starts here
          | data stack (grows down)                 |
          | v                                       |
0x410000  +-----------------------------------------+
          | (no guard: a runaway stack continues    |
          |  down into the heap)                    |
          |                                         |
          | 32 KiB compiler arena (020-cc-arena)    |
          | ^ dictionary heap: 010-lib.fth and      |
          |   020-cc-arena.fth definitions (grow up)|
0x401000  +-----------------------------------------+ <-- HERE starts here
          | zero-filled gap (past the file image)   |
0x4006EC  +-----------------------------------------+
          | seed image: ELF header, program header, |
          | _start, sysvar init, 32 primitives      |
          | (header + code each), REPL (1,772 bytes)|
0x400000  +-----------------------------------------+ PT_LOAD start (e_entry = 0x400078)
```

The round addresses above `0x414000` are where each region nominally
starts.  Every buffer is made with `create … allot`, so its data
begins just past its own dictionary header (and past any
definitions compiled in between): `cc-in-buf`'s first byte is at
`0x414000 + 76`, `cc-src-buf`'s at `0x514000 + 200`, and
`cc-out-buf`'s at `0x714000 + 1,225`.

The table below lists each region in address order; sizes are in
bytes unless noted.  "Owner" is what *writes* to the region.
"Introduced" is the chapter that first explains the region in
detail.

| Range | Size | Region | Owner | Introduced |
|---|---|---|---|---|
| `0x400000` — `0x40003F` | 64    | ELF header (`Elf64_Ehdr`)         | seed image | Ch 13 |
| `0x400040` — `0x400077` | 56    | program header (`Elf64_Phdr`)     | seed image | Ch 13 |
| `0x400078` — `0x400084` | 13    | `_start` (init `rbp`, clear `rdi`) | seed image | Ch 13 |
| `0x400085` — `0x4000B4` | 48    | sysvar init (4× `mov [imm32], imm32`) | seed image | Ch 13 |
| `0x4000B5` — `0x4000B9` | 5     | `jmp repl`                        | seed image | Ch 13 |
| `0x4000BA` — `0x4006EB` | ~1.6K | the 32 primitives, each a dictionary header followed by its code, with the unnamed helpers beside their users and the REPL last | seed image | Chs 14–20 |
| `0x4006EC` — `0x400FFF` | ~2.3K | zero-filled gap below the dictionary heap (the segment's `memsz` exceeds the 1,772-byte on-disk image) | seed loader | Ch 13 |
| `0x401000` — *(grows up)* | ~37K | dictionary heap, low part (~5K of `010-lib.fth` and `020-cc-arena.fth` definitions, then the 32K `cc-arena-base` area): headers + bodies that `010-lib.fth` and `020-cc-arena.fth` define before `030-cc-io.fth` jumps `HERE` to `0x414000` | seed code | Chs 2, 17, 21 |
| tail of low heap | 32K | C compiler's **arena** (`create cc-arena-base  cc-arena-cap allot` — the 32 KiB slab sits at the *end* of the low dictionary heap, just before the HERE-jump) | `cc-alloc` | Ch 21 |
| `0x410000` — `0x410FFF` | 4K  | data stack: pushes start just below `0x411000` and grow *down* through this page.  Nothing guards it — the whole segment is RWX — so a deep stack would run on down into the low dictionary heap.  `HERE` is jumped *past* the stack before the C compiler's big buffers are created | seed code (`rbp` pushes) | Chs 13, 14 |
| `0x411000`              | —   | initial data-stack base (grows *down* in `rbp`) | seed code | Chs 13, 14 |
| `0x412000`              | 1   | I/O scratch byte (`emit`/`key` buffer) | seed code | Ch 16 |
| `0x412800` — `0x412FFF` | 2K  | token buffer (`read_word` assembles here; a token is at most 255 bytes, and `report_token` appends `?` and a newline) | seed code | Chs 13, 17 |
| `0x413000`              | 8   | `STATE` sysvar    | seed init + `:` / `;` | Chs 10, 13 |
| `0x413008`              | 8   | `LATEST` sysvar (head of dictionary)   | seed init + `:` | Chs 10, 13, 17 |
| `0x413010`              | 8   | `HERE` sysvar (next-byte-to-write)     | seed init + `,`, `:`, `;`, `compile_call` (REPL and `[lit]`) | Chs 2, 13 |
| `0x413018`              | 8   | `LAST_FOUND` sysvar (latest hit from `find`) | `find_code` | Chs 13, 17 |
| `0x413020` — `0x413FFF` | ~4K | rest of the sysvar page, unused | — | Ch 13 |
| `0x414000` — `0x513FFF` | 1 MiB | C compiler's **input buffer** `cc-in-buf` (stdin slurped once)  | `cc-load-stdin` | Ch 21 |
| `0x514000` — `0x713FFF` | 2 MiB | C compiler's **source buffer** `cc-src-buf` (preprocessed source, read by the lexer) | `cc-preprocess` | Chs 21, 22 |
| `0x714000` — `0x813FFF` | 1 MiB | C compiler's **output buffer** `cc-out-buf` (ELF bytes accumulated) | `cc-emit-*` | Ch 21 |
| `0x814000` — *(grows up)* | ~3.7 MiB | macro table + 64 KiB macro pool, 2 MiB macro scratch, 1 MiB include pool (4 × 256 KiB), symbol/type/scope parallel arrays, 64 KiB globals data area, 16,384-entry fixup table — all `create … allot`'d in load order across `040`–`116`, ending near `0xBD1500` | `cc-*` | Chs 22, 24, 26, 31 |
| *(end of buffers)* — `0x13FFFFF` | remainder | genuinely unused tail of the 16 MiB `PT_LOAD` | — | Ch 13 |

The numbers come from `020-cc-arena.fth` and `030-cc-io.fth`: the
arena is `[lit] 32768 constant cc-arena-cap` followed by `create
cc-arena-base  cc-arena-cap allot`, allotted at the current
`HERE`, so it sits at the tail of the dictionary heap *before*
`030-cc-io.fth` calls `skip-vm-pages` (`010-lib.fth`), which jumps
`HERE` to `0x414000`, one page above the sysvar page's start.  After
the jump the input buffer (1 MiB) is created at `0x414000`, the
source buffer (2 MiB) at `0x514000` and the output buffer (1 MiB) at
`0x714000`.  Every later compiler buffer (the macro, symbol, type,
string, and globals tables) continues upward from `0x814000` in load
order.  The largest are the preprocessor's: 2 MiB of scratch for
macro arguments and replacements, and 1 MiB for included files.
A compiled program's global *arrays* take no room here at all: they
are only a size until the output ELF's `p_memsz` asks the kernel for
them (Ch 26 §5).  None of these are separately
mmapped; they are `create … allot`'d inside the existing `PT_LOAD`
segment.

## The C-compiler runtime heap (compiled-program memory)

The C compiler emits a `calloc` shim that runs *inside compiled
programs*, not inside the seed.  This shim mmaps a 256 MiB
anonymous private region at compiled-program startup and bumps a
pointer through it.  Ch 26 walks the shim's machine code.

| Range | Size | Region | Owner |
|---|---|---|---|
| `mmap`-chosen | 256 MiB | `heap_base..heap_pos` (lazy zero-fill by Linux) | the compiled program's `calloc` |

There is no overlap with the seed's `0x400000..0x1400000` mapping:
this 256 MiB lives wherever Linux's `mmap` decides, typically
high in the virtual address space.

## The two regimes side by side

The seed-Forth VM packs everything into 16 MiB because the seed
itself is *1,772 bytes*: spending another mmap call would add
five instructions of overhead the budget cannot afford.

The compiled program's heap is 256 MiB because M2-Planet allocates
type tables, struct tables, function tables, and source buffers
during its own self-compile, and the simplest allocator that gets
the job done is "bump until the mmap is full, then crash."  Free
is a no-op.

Both regimes share one principle: *one region, one bump pointer*.
The seed avoids mmap entirely (it gets its segment from the
kernel's ELF loader); compiled programs make one mmap call at
startup and never another.

## Where to look for confirmation

| Address | Authority |
|---|---|
| Sysvar layout      | `000-seed.hex0:60` (the conventions comment above `_start`); the four cells are initialised at `:67`–`:71`, and the `state`/`latest` primitives (`:484`–`:504`) export their addresses |
| Data-stack base    | `000-seed.hex0:64` (`mov rbp, 0x411000`) |
| Token buffer       | `000-seed.hex0:398` (`read_word`) |
| I/O scratch        | `000-seed.hex0:267` (`emit_code`) and `:288` (`key_code`) |
| Source buffer base | `020-cc-arena.fth` and `030-cc-io.fth` |
| 256 MiB heap mmap  | `090-cc-emit.fth` `cc-emit-calloc-shim` (Ch 26) |
