# Appendix B — The memory map

Three distinct classes of allocation matter here. Keep the compiler's own
working memory separate from the memory of a program it generates:

1. **The seed-Forth VM** has one `PT_LOAD` segment of 16 MiB starting
   at `0x400000`. The original seed's code, dictionary, data stack,
   I/O scratch byte, token buffer, and sysvars live in that segment.
   The seed's own machine code makes no `mmap` call; Linux zero-fills
   the segment past the on-disk image. Loading the compiler adds its
   fixed buffers, tables, and default 32 KiB arena inside the segment.

2. **The compiler's optional workspaces** are additional anonymous mappings.
   The parser arena is
   8 MiB for `tools/tcc-compile.fth`, or a fixed 17 MiB for the experimental
   `tools/gcc-direct-cc.py` driver, both through `cc-arena-map`.
   Parsing allocates descriptors, recursive
   contexts, lexer marks, and fixup nodes here. This extends the
   loaded Forth program's workspace without changing the original
   seed image or moving its dictionary and default fixed buffers. The direct-GCC
   driver also selects separately mapped source buffers, macro arrays, and
   stable object records as described below.

3. **A legacy compiled program's heap** is a 256 MiB anonymous
   mapping created by the emitted `calloc` shim. It belongs to the
   generated executable, not to the compiler process. M2-Planet
   uses it for self-compiles; `free` is a no-op. The native TinyCC
   seed instead uses its compiled portable libc's bounded static
   heap and allocator, not this legacy shim.

## The seed-Forth memory map (`PT_LOAD` covers `0x400000..0x1400000`)

The picture puts higher addresses at the top; `^` and `v` mark
which way a region fills.

```text
 mmap-chosen +--------------------------------------+ outside seed PT_LOAD
             | compiler scratch arena: 8/17 MiB    | cc-arena-map, opt-in
             +--------------------------------------+

0x1400000 +-----------------------------------------+ end of the 16 MiB PT_LOAD
          | unused tail                             |
          |                                         |
          | ^ compiler tables: macros, macro        |
          |   scratch, includes, symbols, scopes,   |
          |   globals, fixups and code (~6 MiB)     |
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

The round addresses above `0x414000` are nominal region starts. Dictionary
headers and definitions occupy the gaps, so precise default buffer addresses
are returned by `cc-in-default-buf`, `cc-src-default-buf`, and `cc-out-default-buf`.
The public input/source words are accessors selecting either those default
slabs or the opt-in mapped workspace; their stack effects are unchanged.

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
| `0x402406` — `0x40A405` | 32 KiB | Default compiler **arena**, `cc-arena-base`; later low-heap definitions follow it before the HERE-jump. The native driver switches active allocation to a separate mapping. | `cc-alloc` in default mode | Chs 21, 34 |
| `0x410000` — `0x410FFF` | 4K  | data stack: pushes start just below `0x411000` and grow *down* through this page.  Nothing guards it — the whole segment is RWX — so a deep stack would run on down into the low dictionary heap.  `HERE` is jumped *past* the stack before the C compiler's big buffers are created | seed code (`rbp` pushes) | Chs 13, 14 |
| `0x411000`              | —   | initial data-stack base (grows *down* in `rbp`) | seed code | Chs 13, 14 |
| `0x412000`              | 1   | I/O scratch byte (`emit`/`key` buffer) | seed code | Ch 16 |
| `0x412800` — `0x412FFF` | 2K  | token buffer (`read_word` assembles here; a token is at most 255 bytes, and `report_token` appends `?` and a newline) | seed code | Chs 13, 17 |
| `0x413000`              | 8   | `STATE` sysvar    | seed init + `:` / `;` | Chs 10, 13 |
| `0x413008`              | 8   | `LATEST` sysvar (head of dictionary)   | seed init + `:` | Chs 10, 13, 17 |
| `0x413010`              | 8   | `HERE` sysvar (next-byte-to-write)     | seed init + `,`, `:`, `;`, `compile_call` (REPL and `[lit]`) | Chs 2, 13 |
| `0x413018`              | 8   | `LAST_FOUND` sysvar (latest hit from `find`) | `find_code` | Chs 13, 17 |
| `0x413020` — `0x413FFF` | ~4K | rest of the sysvar page, unused | — | Ch 13 |
| `cc-in-default-buf .. +1048575` | 1 MiB | C compiler's **input buffer** `cc-in-buf` (stdin slurped once)  | `cc-load-stdin` | Ch 21 |
| `cc-src-default-buf .. +2097151` | 2 MiB | C compiler's **source buffer** `cc-src-buf` (preprocessed source, read by the lexer) | `cc-preprocess` | Chs 21, 22 |
| `cc-out-default-buf .. +1048575` | 1 MiB | C compiler's **output buffer** `cc-out-buf` (ELF bytes accumulated) | `cc-emit-*` | Ch 21 |
| after the output slab — *(grows up)* | ~6 MiB | Remaining compiler dictionary/code and tables: 4,096-entry macro table, 256 KiB macro pool, 2 MiB scratch, 1 MiB include pool, 8,192-row symbols/scopes, globals and fixups; allocated in numeric library order, with optional direct object/ABI/linker layers afterward | seed dictionary compiler and `cc-*` | Chs 22, 24, 26, 31, 34 |
| *(end of buffers)* — `0x13FFFFF` | remainder | genuinely unused tail of the 16 MiB `PT_LOAD` | — | Ch 13 |

The default arena comes from `[lit] 32768 constant cc-arena-cap`
and `create cc-arena-base cc-arena-cap allot`. It is created in the
low dictionary heap before `030-cc-io.fth` calls `skip-vm-pages`.
The definitions after the arena still occupy low-heap space; the
arena is not the final object before the jump.

After the jump to `0x414000`, dictionary headers account for the
small gaps between the buffer ranges in the table. Every later
fixed compiler buffer and word continues upward in load order.
The post-output region includes Forth code and dictionary headers, not just
table payload. The workspace capacity test loads every compiler library plus
the archive and linker and checks the final HERE against `0x1400000`. Its exact end
changes when a definition or its name changes; it is not an ABI.

Both compiler profiles reserve the larger preprocessor tables when
loaded. Their **enforced limits** differ: the default keeps 1,024
macros and a 64 KiB macro text limit; direct mode permits 4,096 and
256 KiB. The shared include pool is 1 MiB. The default uses four
256 KiB slots; direct mode packs live file contents into that same
pool and tracks up to thirty-two nested include levels. These default buffers are `create … allot` data inside the existing seed
segment. The direct-GCC driver explicitly switches its macro arrays to a
4,608-entry anonymous mapping; the pool, includes and scratch stay at the
existing sizes.

A compiled program's global *arrays* do not occupy the compiler's
globals-data buffer: their zero-initialized storage is represented
by a size until the output ELF's `p_memsz` asks the loader for it
(Ch 26 §5).

## The optional native compiler arena

`cc-arena-map` asks Linux for an anonymous private read/write mapping,
then replaces `cc-arena-start`, `cc-arena-limit`, and `cc-arena-ptr`.
`cc-alloc` keeps its bump-allocation interface and rounds allocation
sizes to eight-byte multiples, but checks against this active base and limit rather
than always against `cc-arena-base`. Mapping failure or exhaustion
still produces error 10.

| Range | Size | Region | Owner |
|---|---|---|---|
| `mmap`-chosen | 8 MiB in the direct TinyCC driver; 17 MiB in the direct-GCC driver | Compiler scratch arena, outside the seed `PT_LOAD` | `cc-arena-map` and `cc-alloc` |

The original 32 KiB slab remains in the dictionary; it is simply no
longer the active allocator region. The additional mapping belongs
to the compiler process and disappears when that process exits.
The generated ELF contains neither that scratch mapping nor the
compiler's dictionary. Ch 34 explains the native data structures
that need the larger workspace. The direct-GCC bound rounds the complete original `c-typeck.c` arena
requirement of 16,988,648 bytes up to a whole MiB. Neither driver grows the mapping dynamically.

## Bounded direct-GCC translation storage

IO selection maps one 10 MiB region split into 3 MiB raw, 3 MiB expanded,
and 4 MiB output slices. The macro mapping is 221,184 bytes: six arrays of 4,608 cells, eight
bytes each. Stable object records use a separate 655,360-byte mapping for 5,120 records,
selected by `cc-om-direct-workspace`; the 128-byte layout is unchanged.
Five label arrays hold 1,024 entries each. Two global-fixup arrays hold 17,920
each. The object mapping holds a 4 MiB text slice, the original two 256 KiB
non-text slices, and 20,992 forty-byte relocation records. These
workspaces belong to the compiler, not to any generated program.

The original `c-typeck.c` failure at stable record 4,097 is distinct from the
ELF writer's text capacity. Source, macro, record, output, object-section and
parser-arena bounds remain independent. The driver does not turn a capacity
failure into an automatic retry with a bigger allocation. Mapping selection is
idempotent within a process, and normal translation initialization resets
logical counts without allocating another mapping. Default selection restores
the old dictionary-backed buffers and capacities.

The shared mapping helper checks positivity and page-rounding overflow before
one Linux `mmap`, and checks its result before publishing a new active base.
Allocation errors retain each workspace's existing diagnostic code. The Python
driver only publishes successful Forth output, preserving a prior destination
when mapping or compilation fails. See `tests/gcc/workspace-capacity-check.py`
for exact/one-past, round, reset, layout and failure checks.

## The legacy runtime heap (compiled-program memory)

The default C compiler emits a `calloc` shim that runs *inside compiled
programs*, not inside the seed.  This shim mmaps a 256 MiB
anonymous private region on its first allocation and bumps a
pointer through it.  Ch 26 walks the shim's machine code.

| Range | Size | Region | Owner |
|---|---|---|---|
| `mmap`-chosen | 256 MiB | `heap_base..heap_pos` (lazy zero-fill by Linux) | the compiled program's `calloc` |

There is no overlap with the seed's `0x400000..0x1400000` mapping:
this 256 MiB lives wherever Linux's `mmap` decides, typically
high in the virtual address space.

## The allocations side by side

The original 1,772-byte seed relies on the ELF loader for its one
16 MiB segment. Loading Forth can add behavior without changing
those bytes: the direct compiler uses the library's `syscall6`
wrapper to request its larger arena. That is a compiler extension,
not a new seed primitive.

The 256 MiB legacy heap serves a different lifetime and purpose.
It exists inside a generated program such as M2-Planet, whose own
self-compile allocates type tables, function tables, and source
buffers. The native TinyCC image instead compiles the portable
libc allocator with its bounded static heap and real `free`/`realloc`
implementation. Do not count either generated program's allocator
as scratch storage used while Forth compiles that program.

The shared design principle is *one region, one owner and cursor*;
it is not a promise that every mode makes the same number of
mapping calls.

## Where to look for confirmation

| Address | Authority |
|---|---|
| Sysvar layout      | `000-seed.hex0:60` (the conventions comment above `_start`); the four cells are initialised at `:67`–`:71`, and the `state`/`latest` primitives (`:484`–`:504`) export their addresses |
| Data-stack base    | `000-seed.hex0:64` (`mov rbp, 0x411000`) |
| Token buffer       | `000-seed.hex0:398` (`read_word`) |
| I/O scratch        | `000-seed.hex0:267` (`emit_code`) and `:288` (`key_code`) |
| Source buffer base | `020-cc-arena.fth` and `030-cc-io.fth` |
| Compiler scratch mmap: 8 MiB TinyCC / 17 MiB direct GCC | `020-cc-arena.fth` `cc-arena-map`, selected by `tools/tcc-compile.fth` (Ch 34) or `tools/gcc-direct-cc.py` |
| Macro/include capacities | `040-cc-prep.fth` `cc-macro-cap`, `cc-macro-pool-cap`, `cc-prep-inc-pool`, and `cc-prep-direct-depth` (Ch 22) |
| 256 MiB heap mmap  | `090-cc-emit.fth` `cc-emit-calloc-shim` (Ch 26) |
