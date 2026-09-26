# Chapter 13 — The ELF and the Entry Point

```text
Missing capability: the 1,772 bytes of hex have to be made executable somehow.
New pattern: a minimal ELF64 header plus one PT_LOAD with R|W|X over the whole 16 MiB segment.
Artifact after this chapter: the boot prologue — ELF header, _start, sysvar init, jump to REPL.
Proof link: the C compiler's own ELF emission (Ch 25) reuses the same shape and the same addresses.
```

Eight bytes at file offset `0x0D0`, `BA 00 40 00 00 00 00 00`, are
the number `0x4000BA`: the address where `dup`'s dictionary header
will sit once the program runs.  Nothing computes that at run time.
It was typed by hand, like every other link in the dictionary, the
starting value of `LATEST`, and the address of `lit_code` baked into
`[lit]`.  There is no linker, no relocation table and no loader
fix-up.  If the file lands anywhere but where those numbers assume,
the first dictionary lookup follows a link into unmapped memory.  So
before any Forth runs, the file has to make the kernel keep one
promise: the byte at file offset `N` sits at address
`0x400000 + N`.

That promise costs 120 bytes of headers.  Another 66 bytes set up
two registers and four system variables and jump to the REPL.  All
of it is in lines 1–74 of `000-seed.hex0`, a file of 689 lines of
hand-assembled hex that the Stage-0 tool `hex0-seed` (from the Guix
Full Source Bootstrap) turns into the 1,772-byte `seed-forth` by
dropping everything after each `;` and writing the rest verbatim.

Part II reads those 1,772 bytes in the order the machine meets
them, and by the end of Ch 20 you will have read every one.  The
file is laid out for that: after the boot code, each primitive is
one unit, its dictionary header directly followed by its machine
code, and the units run in the order Chs 14–20 teach them, so each
chapter reads one contiguous stretch of the file.  A byte you have
read is a byte you no longer take on trust: this book's answer to
Thompson's "Reflections on Trusting Trust", applied at its smallest
scale.  Each chapter ends with a running count.  Keep `man 5 elf`
or `readelf -a` to hand for this one.

## 1. Why we start at the top

Every primitive in the next seven chapters is found by its address:
`dup_code` at `0x4000C7`, `nand_code` at `0x4001CE`, `lit_code` at
`0x4005A0`.  Every relative jump between them assumes the file is
loaded in one piece, and every absolute address assumes that piece
starts at `0x400000`.  The ELF header and the program header are
what make both assumptions true.  Read them first and every later "rel32 = …"
in this codebase will make sense.

## 2. The ELF magic and `Elf64_Ehdr`

The first 64 bytes of any ELF file are an `Elf64_Ehdr`.  Cross-
reference `man 5 elf` if you want a field-by-field formalism; the
seed's copy, one field per line, is the `<<elf-header>>` chunk at
the end of this chapter.  With the comments trimmed:

```
7F 45 4C 46    ; e_ident[0..3] = magic "\x7fELF"
02             ; e_ident[EI_CLASS]   = ELFCLASS64
01             ; e_ident[EI_DATA]    = ELFDATA2LSB   (little-endian)
01             ; e_ident[EI_VERSION] = EV_CURRENT
00             ; e_ident[EI_OSABI]   = ELFOSABI_NONE (System V)
00             ; e_ident[EI_ABIVERSION]
00 00 00 00 00 00 00 ; e_ident padding (zeros)
02 00          ; e_type    = ET_EXEC
3E 00          ; e_machine = EM_X86_64
01 00 00 00    ; e_version = 1
78 00 40 00 00 00 00 00 ; e_entry  = 0x400078
40 00 00 00 00 00 00 00 ; e_phoff  = 64
00 00 00 00 00 00 00 00 ; e_shoff  = 0  (no section headers)
00 00 00 00    ; e_flags
40 00          ; e_ehsize    = 64
38 00          ; e_phentsize = 56
01 00          ; e_phnum     = 1
00 00          ; e_shentsize = 0
00 00          ; e_shnum     = 0
00 00          ; e_shstrndx  = 0
```

Three of these fields matter for everything that follows.

**`e_entry = 0x400078`** is the address the kernel jumps to after
loading the image.  We will compute this address from the file
structure in §4.

**`e_phoff = 64`** says "the program-header table starts at file
offset 64."  Since the ELF header is itself 64 bytes, the program
header sits immediately after it, with no padding.

**`e_shoff = 0`** says "no section headers."  Sections are a
*linking* concept, and an executable does not need them.

Everything else is a constant the kernel checks before accepting the
file: it must be 64-bit (`02`), little-endian (`01`), an executable
(`02 00`), targeted at x86-64 (`3E 00`).

## 3. The single `Elf64_Phdr`

Bytes 64–119 are the one program header.  `PT_LOAD` with `R|W|X`
flags, mapping file offset `0` for 1,772 bytes to virtual address
`0x400000` for 16 MiB.

```
01 00 00 00              ; p_type   = PT_LOAD
07 00 00 00              ; p_flags  = R|W|X
00 00 00 00 00 00 00 00  ; p_offset = 0
00 00 40 00 00 00 00 00  ; p_vaddr  = 0x400000
00 00 40 00 00 00 00 00  ; p_paddr  = 0x400000  (ignored on Linux)
EC 06 00 00 00 00 00 00  ; p_filesz = 1772
00 00 00 01 00 00 00 00  ; p_memsz  = 0x1000000 (16 MiB)
00 10 00 00 00 00 00 00  ; p_align  = 0x1000
```

The two size fields differ on purpose.  On disk there are
`p_filesz` bytes (1,772); in memory the kernel reserves `p_memsz`
bytes (16 MiB) and zero-fills everything past the end of the file.
That is how `seed-forth` writes into `HERE` at
`0x401000` (just above the file image) without ever calling `mmap`.
The whole compile-time heap, the data stack at `0x411000`, the I/O
scratch byte at `0x412000`, the token buffer at `0x412800`, and the
sysvar page at `0x413000` are all *inside* this single mapping.

R|W|X is unusual; modern executables separate code (`R-X`) from
data (`R-W`).  The seed has one segment because it *writes new
machine code into the same region it executes from*: the REPL emits
`CALL` instructions at `HERE`, and they must be executable the
moment they are written.  Two segments would need an `mprotect`
syscall whenever `HERE` crossed a page, and the seed has no bytes to
spare for that.

`p_align = 0x1000` is the system page size.  Both `p_offset` and
`p_vaddr` are multiples of `0x1000`, which keeps the kernel happy.

## 4. `_start` at `0x400078`

Why is the entry point `0x400078`?

The file image starts at virtual address `0x400000` (from `p_vaddr`).
The ELF header is 64 bytes (`0x40`).  The program header is 56 bytes
(`0x38`).  Total: 120 bytes (`0x78`).  So the first byte after the
two headers lives at `0x400000 + 0x78 = 0x400078`.

That is `_start`:

```
48 BD 00 10 41 00 00 00 00 00   ; mov rbp, 0x411000
48 31 FF                        ; xor rdi, rdi
```

Two instructions, thirteen bytes.

`mov rbp, 0x411000` initialises the **data stack**.  Throughout the
seed, `rbp` is the data-stack pointer.  The stack grows *down*:
`sub rbp, 8` pushes a slot and `add rbp, 8` pops one.  The base `0x411000` is
17 pages above `0x400000`; the stack grows down toward the heap
(which starts at `0x401000` and grows up).  The sysvar page at
`0x413000` sits *above* the stack, out of its way.

`xor rdi, rdi` clears the **TOS register cache**: `rdi` holds the
top of the data stack, as Ch 14 explains.  The first real push
spills this zero harmlessly.

The comment block just above `_start` in the source lists these
conventions, together with one more that Ch 17 introduces: `rbx`
holds the length of the last token read.  Every routine in the file
keeps to them.

## 5. The sysvar init at `0x085`

Right after `_start`, four `mov [imm32], imm32` instructions seed
the sysvar page at `0x413000`.  Each is 12 bytes long, total 48
bytes.

```
48 C7 04 25 00 30 41 00 00 00 00 00   ; [STATE]       = 0
48 C7 04 25 08 30 41 00 17 06 40 00   ; [LATEST]      = 0x400617
48 C7 04 25 10 30 41 00 00 10 40 00   ; [HERE]        = 0x401000
48 C7 04 25 18 30 41 00 00 00 00 00   ; [LAST_FOUND]  = 0
```

`STATE = 0` boots us in interpret mode.  `HERE = 0x401000` puts the
first `:` definition on the page right above the ELF image.
`LAST_FOUND` starts at zero; `find_code` fills it on every hit.  The
four cells are consecutive, `0x413000` through `0x413018`, and the
rest of the page is free.  That order is a contract: `010-lib.fth`
finds HERE's cell as the one after LATEST's rather than typing in
its address (Ch 2).

The interesting one is `LATEST = 0x400617`, the link cell of the
dictionary header for `0branch`, the last word in the seed image.
The dictionary is a linked list of headers, each pointing back to
the previous one (Ch 17 has the picture), and its head is whoever
was defined last.  Rather than walk the chain at runtime to find it,
the seed hard-codes the answer.

The seed does this everywhere: anything that can be resolved at
assembly time is resolved then.  Adding a primitive means
recomputing this constant by hand; in exchange, startup is four
`mov`s and nothing else.

## 6. `JMP repl` at `0x0B5`

After the sysvar init, the entry-code section ends with one
unconditional jump.

```
;; ----- jmp_repl @ 0x0B5  enter the REPL (Ch 20) -----
E9 DF 05 00 00                            ; jmp repl  (rel32 = 0x699 - 0x0BA)
```

`E9` is the opcode for "`JMP` with a 32-bit signed displacement
relative to the *next* instruction."  The next instruction starts at
`0x0B5 + 5 = 0x0BA`.  The REPL lives at file offset `0x699` (virtual
address `0x400699`), the last routine in the file.  The displacement
is `0x699 - 0x0BA = 0x5DF`, encoded little-endian as `DF 05 00 00`.

You will see the arithmetic `target − (call_site + size)` throughout
Part II.  Every direct `CALL` and `JMP` in the seed uses a signed
displacement from the next instruction: 32 bits for the calls and
long jumps, 8 bits for the short jumps inside a routine.  All of them
are computed by hand, and the source spells each one out in its
comment, `(rel32 = target - next)`, so you can check the arithmetic
line by line.

That is the whole boot sequence: identify the file as an ELF, ask
for one 16 MiB segment, initialise two registers and four sysvars,
jump to the REPL.  It takes 66 bytes, 48 of them sysvar
initialisation.  The rest of the file is the 32 primitives, each a
dictionary header followed by its code, in the order the next seven
chapters read them.

## Canonical source

`000-seed.hex0` is hand-assembled and every `rel32` in it depends
on its exact byte order, so we declare the whole file as one root
block here, with every chunk reference in source order.  One chunk
per primitive holds its header and its code; the helpers and the
REPL have chunks of their own.  Subsequent chapters (Chs 14–20)
define the chunks they introduce, in the same order, so the file
and the book read front to back together.  Each chunk body ends with
the blank line that separates it from the next section, so
concatenation yields byte-identical source.

```hex0 file=000-seed.hex0
<<file-header-comment>>
<<elf-header>>
<<program-header>>
<<entry-point>>
<<sysvar-init>>
<<jmp-to-repl>>
<<dup>>
<<drop>>
<<swap>>
<<to-r>>
<<r-from>>
<<r-at>>
<<fetch>>
<<store>>
<<cfetch>>
<<cstore>>
<<plus>>
<<nand>>
<<zeq>>
<<divide>>
<<star>>
<<bye>>
<<emit>>
<<key>>
<<syscall6>>
<<find>>
<<here>>
<<comma>>
<<execute>>
<<read-word>>
<<read-char>>
<<report-token>>
<<state>>
<<latest>>
<<tick>>
<<colon>>
<<semicolon>>
<<compile-call>>
<<lit>>
<<bracket-lit>>
<<branch>>
<<zbranch>>
<<parse-decimal>>
<<repl>>
```

This chapter defines the first six of those chunks.

```hex0 chunk=file-header-comment
;; 000-seed.hex0 — x86-64 Linux Forth Seed
;;
;; This file is a synthesis artifact of AI-collaborative research.
;; Co-authored by an ensemble of LLMs (Claude, Gemini, Codex, DeepSeek,
;; Qwen, Kimi, Gemma, MiniMax) under human architectural direction.
;;
;; License: MIT (see /LICENSE)
;;
;; How to read this file: after the two ELF headers and the boot code,
;; each of the 32 primitives is one unit — its dictionary header (link,
;; flags, nlen, name) directly followed by its machine code, so a word's
;; execution token (xt) is simply the address of its code.  The units
;; appear in the order the book teaches them (Chs 14-20); the three
;; unnamed helpers and the REPL sit next to the words that use them.
;; Every line is one field or one instruction; the text after ';' is a
;; comment (hex0 ignores it).  Addresses are file offsets; the image
;; loads at 0x400000, so offset 0xNNN is address 0x400NNN.
;;
```

```hex0 chunk=elf-header
;; ===== ELF64 header (64 bytes) @ 0x000 =====
;; Layout reference: man 5 elf, Elf64_Ehdr
7F 45 4C 46                               ; e_ident[0..3]     = magic "\x7fELF"
02                                        ; e_ident[EI_CLASS] = ELFCLASS64
01                                        ; e_ident[EI_DATA]  = ELFDATA2LSB (little-endian)
01                                        ; e_ident[EI_VERSION] = EV_CURRENT
00                                        ; e_ident[EI_OSABI] = ELFOSABI_NONE (System V)
00                                        ; e_ident[EI_ABIVERSION] = 0
00 00 00 00 00 00 00                      ; e_ident padding (7 zero bytes)
02 00                                     ; e_type      = ET_EXEC
3E 00                                     ; e_machine   = EM_X86_64
01 00 00 00                               ; e_version   = 1
78 00 40 00 00 00 00 00                   ; e_entry     = 0x400078 (_start)
40 00 00 00 00 00 00 00                   ; e_phoff     = 64
00 00 00 00 00 00 00 00                   ; e_shoff     = 0 (no section headers)
00 00 00 00                               ; e_flags     = 0
40 00                                     ; e_ehsize    = 64
38 00                                     ; e_phentsize = 56
01 00                                     ; e_phnum     = 1
00 00                                     ; e_shentsize = 0
00 00                                     ; e_shnum     = 0
00 00                                     ; e_shstrndx  = 0

```

```hex0 chunk=program-header
;; ===== Program header (56 bytes) @ 0x040, one PT_LOAD =====
01 00 00 00                               ; p_type   = PT_LOAD
07 00 00 00                               ; p_flags  = R|W|X
00 00 00 00 00 00 00 00                   ; p_offset = 0
00 00 40 00 00 00 00 00                   ; p_vaddr  = 0x400000
00 00 40 00 00 00 00 00                   ; p_paddr  = 0x400000 (ignored on Linux)
EC 06 00 00 00 00 00 00                   ; p_filesz = 1772 (the whole file)
00 00 00 01 00 00 00 00                   ; p_memsz  = 0x1000000 (16 MiB; the kernel zero-fills past the file)
00 10 00 00 00 00 00 00                   ; p_align  = 0x1000

```

```hex0 chunk=entry-point
;; ===== Code at 0x400078 =====
;; Register and memory conventions used by every routine below:
;;   rbp      = data-stack pointer (grows down); rdi = top of stack (TOS)
;;   rsp      = return stack (the x86 call stack)
;;   rbx      = length of the last token read_word read
;;   0x411000 = data-stack base (first push lands at 0x410FF8)
;;   0x412000 = single-byte I/O scratch (emit, key)
;;   0x412800 = token buffer, TIB (read_word)
;;   0x413000 = sysvar page, 8 bytes each: STATE, LATEST, HERE, LAST_FOUND
;;              (0x413000, 0x413008, 0x413010, 0x413018)
;;
;; ----- _start @ 0x078  entry point: set up the data stack -----
48 BD 00 10 41 00 00 00 00 00             ; mov rbp, 0x411000
48 31 FF                                  ; xor rdi, rdi

```

```hex0 chunk=sysvar-init
;; ----- sysvar_init @ 0x085  STATE, LATEST, HERE, LAST_FOUND -----
48 C7 04 25 00 30 41 00 00 00 00 00       ; mov qword [STATE], 0
48 C7 04 25 08 30 41 00 17 06 40 00       ; mov qword [LATEST], 0x400617 (0branch header)
48 C7 04 25 10 30 41 00 00 10 40 00       ; mov qword [HERE], 0x401000
48 C7 04 25 18 30 41 00 00 00 00 00       ; mov qword [LAST_FOUND], 0

```

```hex0 chunk=jmp-to-repl
;; ----- jmp_repl @ 0x0B5  enter the REPL (Ch 20) -----
E9 DF 05 00 00                            ; jmp repl  (rel32 = 0x699 - 0x0BA)

```

## Try it

```sh
./build.sh                    # assembles 000-seed.hex0; you get a 1772-byte ELF.
wc -c ./seed-forth            # should print 1772
file ./seed-forth             # ELF 64-bit LSB executable, x86-64
readelf -h ./seed-forth       # confirms the header we just read
readelf -l ./seed-forth       # confirms the one PT_LOAD segment
```

Compare the `readelf -h` output to the hex you read in §2 field by
field.  `e_entry` should be `0x400078`; `e_phoff` should be `64`;
`e_phnum` should be `1`.

Now check the promise from the start of the chapter, and then let
the kernel keep it:

```sh
od -An -tx1 -j $((0xC7)) -N 9 ./seed-forth
# 48 83 ed 08 48 89 7d 00 c3   (dup_code, at file offset 0xC7)
echo bye | ./seed-forth; echo "exit status $?"
# prints "exit status 0"
```

The nine bytes at offset `0xC7` are the `dup_code` that Ch 14
reads, and the program header puts them at `0x4000C7`, the address
every hand-computed reference to `dup_code` assumes.  The second command is the whole boot
sequence end to end: the kernel accepted the headers, `_start` set
up the stacks and sysvars, the jump at `0x0B5` reached the REPL, and
the REPL understood the word `bye`.

## Exercises

1. **★★ Trace.** The entry point is at `0x400078`.  The header is 64 bytes plus one
   56-byte program header, 120 bytes in total.  Why is the entry at
   offset `0x78` (=120) and not, say, `0x100`?  What would change if
   the seed reserved padding for future program-header entries?

2. **★★ Trace.** `p_memsz = 16 MiB` but `p_filesz = 1772`.  What does the kernel do
   with the bytes between `1772` and `16 MiB`?  Trace what happens
   when seed-forth writes the first byte at `0x420000`: does the page
   exist before the write?  After?

3. **★★ Trace.** The sysvar `LATEST` is initialised at assembly time to the header
   of the `0branch` primitive (`0x400617`).  Why not initialise it to zero
   and have the REPL walk the chain to find the tail?  (Hint: count
   the syscalls and instructions involved in each option.)

4. **★★ Trace.** Two of the four sysvar `mov`s store zero into memory
   that, by the answer to Exercise 2, is already zero.  Which two?
   Delete them from a copy of `000-seed.hex0` and list every
   hand-computed number you then have to fix.  Is 24 bytes worth a
   boot sequence that no longer says what it assumes?

5. **★★★ Extend.** Why R|W|X for the single segment?  Sketch the changes needed to
   split it into R-X (code) + R-W (heap + sysvars + stack).  Where
   would `mprotect` calls have to go?  How many bytes does each one
   cost?

## Takeaways

- A 64-bit Linux ELF can be written by hand in 120 bytes (one
  `Elf64_Ehdr` + one `Elf64_Phdr`) and still satisfy the kernel.
- The seed maps one 16 MiB R|W|X segment that holds its code, stack,
  sysvars and heap, so it never needs `mmap` or `mprotect`.
- Every primitive in the next seven chapters is reachable from
  `_start` by direct address; the seed resolves at assembly time
  anything that can be resolved at assembly time.

**Running count: 186 of 1,772 bytes read (10%).**  The 120 header
bytes and 66 bytes of boot code are done.

The jump at `0x0B5` lands in a REPL that immediately calls other
routines, and the smallest of them are 9-byte bodies like `dup`.
Part I called them without ever asking where the stack actually
lives.  Ch 14 answers that, and the
top of the stack turns out not to be in memory at all.

Next: Chapter 14 — Stack Primitives in Machine Code.
