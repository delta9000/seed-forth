# Appendix B — The memory map

Two memory regimes appear in this book:

1. **The seed-Forth VM** — one `PT_LOAD` segment of 16 MiB starting
   at virtual address `0x400000`.  Everything the seed needs — code,
   dictionary headers, the heap that `HERE` walks across, the data
   stack, the I/O scratch byte, the token buffer, and the sysvars
   — lives inside this one segment.  No `mmap` calls; the kernel
   zero-fills the part of the segment that extends past the on-disk
   image.

2. **The C compiler's runtime heap** — a 256 MiB anonymous mmap that
   compiled programs allocate from with a bump-allocator `calloc`
   shim.  Sized to host M2-Planet self-compiles without ever calling
   `free` (which is a no-op).  This region is *outside* the seed's
   16 MiB and is allocated lazily by Linux on first touch.

## The seed-Forth memory map (`PT_LOAD` covers `0x400000..0x1400000`)

Addresses sorted; sizes in bytes unless noted.  "Owner" is what
*writes* to the region.  "Introduced" is the chapter that first
explains the region in detail.

| Range | Size | Region | Owner | Introduced |
|---|---|---|---|---|
| `0x400000` — `0x40003F` | 64    | ELF header (`Elf64_Ehdr`)         | seed image | Ch 13 |
| `0x400040` — `0x400077` | 56    | program header (`Elf64_Phdr`)     | seed image | Ch 13 |
| `0x400078` — `0x400084` | 13    | `_start` (init `rbp`, clear `rdi`) | seed image | Ch 13 |
| `0x400085` — `0x4000CC` | 72    | sysvar init (6× `mov [imm32], imm32`) | seed image | Ch 13 |
| `0x4000CD` — `0x4000D1` | 5     | `jmp repl`                        | seed image | Ch 13 |
| `0x4000D2` — `0x40078F` | ~1.7K | the 32 primitive bodies + dictionary entries | seed image | Chs 14–20 |
| `0x4007F0` — `0x400FFF` |  2K | unused tail of file image (padding to page boundary) | — | Ch 13 |
| `0x401000` — `0x40FFFF` | 60K | dictionary heap (`HERE` walks here as `010-lib.fth` loads + REPL definitions) | seed code | Chs 2, 17 |
| `0x410000` — `0x410FFF` | 4K  | data-stack underflow guard region (stack initialised at top) | seed code | Ch 13 |
| `0x411000`              | —   | initial data-stack base (grows *down* in `rbp`) | seed code | Chs 13, 14 |
| `0x412000`              | 1   | I/O scratch byte (`emit`/`key` buffer) | seed code | Ch 16 |
| `0x412800` — `0x4128FF` | 256 | token buffer (`read_word` assembles here) | seed code | Chs 13, 17 |
| `0x413000`              | 8   | `STATE` sysvar    | seed init + `:` / `;` | Chs 10, 13 |
| `0x413008`              | 8   | `LATEST` sysvar (head of dictionary)   | seed init + `,` | Chs 10, 13, 17 |
| `0x413010`              | 8   | `HERE` sysvar (next-byte-to-write)     | seed init + `c,` | Chs 2, 13 |
| `0x413018`              | 8   | `LAST_FOUND` sysvar (latest hit from `find`) | `find_code` | Chs 13, 17 |
| `0x413020`              | 8   | `NUMBER_HOOK` sysvar (REPL miss path)  | seed init (zero); user-installable | Chs 13, 20 |
| `0x413028`              | 8   | `INPUT_FD` sysvar (stdin by default)   | seed init | Ch 13 |
| `0x414000` — `0x513FFF` | 1 MiB | C compiler's **source buffer** (stdin slurped once)  | `cc-load-stdin` | Ch 21 |
| `0x514000` — `0x613FFF` | 1 MiB | C compiler's **output buffer** (ELF bytes accumulated) | `cc-emit-*` | Ch 21 |
| `0x614000` — `0x61BFFF` | 32K | C compiler's **arena** (struct descriptors, fixup overflow) | `cc-alloc` | Ch 21 |
| `0x61C000` — `0x13FFFFF` | ~14 MiB | unused tail of the 16 MiB `PT_LOAD` | — | Ch 13 |

The numbers in the bottom rows come from `020-cc-arena.fth` and
`030-cc-io.fth`: the source buffer is sized to `[lit] 4276224
here-addr !` (= `0x414000`), and the arena is `[lit] 32768
constant cc-arena-cap`.  These are not separately mmapped; they
are `create … allot`'d inside the existing `PT_LOAD` segment.

## The C-compiler runtime heap (compiled-program memory)

The C compiler emits a `calloc` shim that runs *inside compiled
programs*, not inside the seed.  This shim mmaps a 256 MiB
anonymous private region at compiled-program startup and bumps a
pointer through it.  Ch 26 walks the shim's machine code.

| Range | Size | Region | Owner |
|---|---|---|---|
| `mmap`-chosen | 256 MiB | `heap_base..heap_pos` (lazy zero-fill by Linux) | the compiled program's `calloc` |

There is no overlap with the seed's `0x400000..0x1400000` mapping
— this 256 MiB lives wherever Linux's `mmap` decides, typically
high in the virtual address space.

## The two regimes side by side

The seed-Forth VM packs everything into 16 MiB because the seed
itself is *2,040 bytes*: spending another mmap call would add
five instructions of overhead the budget cannot afford.

The compiled program's heap is 256 MiB because M2-Planet allocates
type tables, struct tables, function tables, and source buffers
during its own self-compile, and the simplest allocator that gets
the job done is "bump until the mmap is full, then crash."  Free
is a no-op.

Both regimes share one principle: *one mmap, one bump pointer*.
The seed avoids mmap entirely (it gets its segment from the
kernel's ELF loader); compiled programs make one mmap call at
startup and never another.

## Where to look for confirmation

| Address | Authority |
|---|---|
| Sysvar layout      | `000-seed.hex0:48` (header comment) and `:683+` (sysvar accessors) |
| Data-stack base    | `000-seed.hex0:181` (`mov rbp, 0x411000`) |
| Token buffer       | `000-seed.hex0:259` (`read_word`)  |
| I/O scratch        | `000-seed.hex0:78` (`emit_code`) and `:108` (`key_code`) |
| Source buffer base | `020-cc-arena.fth` and `030-cc-io.fth` |
| 256 MiB heap mmap  | `090-cc-emit.fth` `cc-emit-calloc-shim` (Ch 26) |
