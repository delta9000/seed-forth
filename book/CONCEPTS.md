# Concept index, rung map, and dependency graph

This file does three jobs:

1. **Concept index** — every named idea in the book and the chapter
   that introduces it.  Use this when you want to remind yourself
   what "the consumed-slot property" means or which chapter first
   talks about lvalues.

2. **Rung map** — the main artifacts the book builds, in the order
   later chapters start treating them as machinery.

3. **Dependency graph** — for each chapter, which previous chapters
   it requires.  Use this when you skip around: a chapter's row names
   what its prose assumes you have read.  (Authors: the writing-order
   rule built on this graph is in [`book/WRITING.md`](https://github.com/delta9000/seed-forth/blob/master/book/WRITING.md).)

## Rung map

The book is source-ordered, but the learning path is a ladder.  Each
span builds one artifact that later chapters stop explaining from
first principles and start using as a primitive.

| Rung | Built in | Artifact | Treated as machinery by |
|---|---:|---|---|
| Forth vocabulary | Chs 1-12 | `010-lib.fth` helpers | Parts II and III |
| Seed VM | Chs 13-20 | `seed-forth` interpreter | Part III |
| Compiler buffers | Ch 21 | input/source/output buffers, `cc-die`, arena | Chs 22-32 |
| Preprocessed source | Ch 22 | flattened C stream + macro table | Chs 23-32 |
| Token stream | Ch 23 | `tok-*` cells of the lexer-state block, putback, mark/reset | Chs 24-31 |
| Type/symbol database | Ch 24 | type words + symbol slots | Chs 26-31 |
| Code emitter | Chs 25-26 | ELF and x86-64 encoders | Chs 27-31 |
| Expression compiler | Chs 27-28 | value/lvalue codegen | Chs 29-31 |
| Declaration/statement/function compiler | Chs 29-31 | complete C-subset parser | Ch 32 |
| Proof harness | Ch 32 | Stage-A `.M1` parity | Appendices |
| Assembler | Ch 33 | `130-asm.fth`: M1 expander + two-pass hex2 linker | `bootstrap.sh`, `handoff.sh` (builds `M1` and `hex2`) |
| Direct TinyCC compiler | Ch 34 | LP64 parser, private ABI, initializers, and native runtime | direct TinyCC boot0 → boot3 |

## Capability ladder

What the compiler can do after each Part III chapter.  Pairs with
the rung map above (which shows what each rung *is*); this table
shows what the artifact can *do* at each step.

| Ch | After this chapter, the compiler can ... |
|---:|---|
| 21 | accept stdin into `cc-in-buf`, emit and back-patch into `cc-out-buf`, allocate variable scratch from the arena, and fail with a line number and a code |
| 22 | flatten C source: project includes splice in, macros (object-like and function-like) expand, `#if` groups are kept or dropped |
| 23 | produce one C token at a time into the `tok-*` cells on demand, put one back, or mark and reset to look further ahead |
| 24 | look up names and C types, push/pop scopes, lay out struct descriptors |
| 25 | emit a valid 120-byte ELF prologue and the core x86-64 instruction encoders |
| 26 | emit function calls with forward fixups, libc shims, string literals, and global-address placeholders |
| 27 | lower binary expressions (arithmetic, comparison, bitwise, logical) through one repeated fold |
| 28 | lower primary, unary, postfix, ternary, and assignment with lvalue tracking and a non-lvalue record temporary marker |
| 29 | parse declarations: scalar, pointer, and array locals, structs (self-referential), function-pointer locals, struct locals, and `return` |
| 30 | lower every C control statement: `if`/`else`, `while`, `for`, `do`/`while`, `switch`, `break`, `continue`, `goto` |
| 31 | assemble whole translation units: functions with parameters, scopes, enums, typedefs, file-scope globals, entry stub.  Output is now a runnable ELF. |
| 32 | self-host M2-Planet and verify byte-identical `.M1` against the GCC-built reference.  Stage-A is closed. |

Ch 33 adds no compiler capability.  It gives the compiler's output a
GCC-free way to become an ELF: `130-asm.fth` assembles M2-Planet's
`.M1`, and then mescc-tools' `M1` and `hex2`, which take over.

Ch 34 adds an opt-in profile: LP64 storage, aligned structs/unions,
stack arguments and varargs, bounded initializers, and a finite Linux
runtime. Its four new native files contain 893 lines; the shared
compiler extensions remain covered in their original chapters.

## Topic → chapter quick reference

If you want to know how a specific feature is built, this index
points to the chapter that owns it.  Entries are grouped by area
and given in source order within each area.

### Forth, library and primitives

- *Stack model, dictionary lookup* — Chs 1, 17
- *`nand` and derived logic* — Chs 1 (use), 3 (logic), 15 (machine code)
- *Two's complement subtraction* — Ch 4
- *Linux syscalls from Forth* — Ch 5
- *`digit?`, `alpha?`, `space?`* — Ch 6
- *Comparisons `= < > <= >=`* — Ch 7
- *Stack shufflers `nip rot 2dup 2drop`* — Ch 8
- *Little-endian writers `c, ,4 ,8`* — Chs 2, 9
- *IMMEDIATE flag, STATE, `constant`* — Ch 10
- *Control-flow combinators `if, then, begin, while, repeat,`* — Ch 11
- *`allot skip-vm-pages create variable defer is bytes-eq`* — Ch 12

### Seed VM

- *ELF header, single PT_LOAD, entry stub* — Ch 13
- *Stack/return-stack/memory primitives in machine code* — Ch 14
- *`+ nand 0= / *` in machine code* — Ch 15
- *`emit key syscall6` in machine code* — Ch 16
- *Dictionary header layout, `find ' execute`, `read_word` (comment skipping, `token?`)* — Ch 17
- *`: ; [lit] lit_code compile_call`, subroutine threading* — Ch 18
- *`branch 0branch`, consumed-slot property, inline cells* — Ch 19
- *Decimal parse, REPL loop* — Ch 20

### Compiler infrastructure

- *Lexer-state block, `cc-die` and error codes, bump arena, input/source/output buffers, back-patching* — Ch 21
- *Shared helpers: `ident-start?`, `cell[]`, `cc-name-find`* — Ch 21
- *Preprocessor: `#include "…"`, object-like and function-like
  `#define`, `#undef`, conditional compilation* — Ch 22
- *Tokenizer, keyword table, punctuation IDs, putback, mark/reset* — Ch 23
- *Type encoding, symbol table, struct descriptors* — Ch 24
- *ELF header emission for compiled output* — Ch 25
- *Instruction encoders (mov, push/pop, call, ret, idiv)* — Ch 25
- *Forward calls, fixup lists* — Ch 26
- *C-escape decoding (`cc-decode-escape`)* — Ch 23; *string literal storage* — Ch 26
- *Libc shims (eleven: putchar, exit, getchar, fputs, fputc, fopen,
  fclose, fwrite, fread, calloc, free; eight more emitted only when
  called: malloc, open, read, write, close, strlen, memcpy,
  strrchr)* — Chs 26, 31
- *File-scope globals with deferred vaddrs; global arrays in a bss* — Chs 26, 31
- *Constant expressions (compile-time evaluation)* — Chs 27, 28
- *`movabs rdi, imm64` and wide-immediate fixups* — Ch 26

### C grammar

- *Binary expressions, the precedence cascade* — Ch 27
- *Logical operators with short-circuit codegen* — Ch 27
- *Primary expressions, postfix chain (`.` `->` `[]` `()` `++` `--`)* — Ch 28
- *Unary operators (`* & ! - ~`, prefix `++`/`--`, `sizeof`)* — Ch 28
- *Ternary `?:` and lvalue tracking* — Ch 28
- *Assignment (`=`, `+=`, `-=`, etc.)* — Ch 28
- *Declarations, pointers, arrays* — Ch 29
- *Structs, struct pointers, self-referential structs* — Ch 29
- *Function-pointer locals, struct locals* — Ch 29
- *Typedefs and function-pointer typedefs* — Ch 31
- *Enums and enum constants* — Ch 31
- *File-scope globals, static globals* — Ch 31
- *`if` / `else`* — Ch 30
- *`while`, `for` (with step rewind)* — Ch 30
- *`do` / `while`* — Ch 30
- *`switch` / `case` / `default` with fall-through* — Ch 30
- *`break`, `continue`, `goto`, labels* — Ch 30
- *`return` and implicit return* — Chs 29, 31
- *Function definitions, parameter spill, scopes* — Ch 31
- *Forward function calls and prototype fixups* — Ch 31
- *Top-level classification (`cc-top-classify`: definition, prototype or variable) and the end-of-program check for undefined functions* — Ch 31
- *The `main` entry stub at `0x400078`* — Ch 31

### The assembler

- *M1 and hex2 formats: `DEFINE`, sigils, strings, labels* — Ch 33
- *Macro expansion into a second buffer (`asm-expand-pass`)* — Ch 33
- *Two-pass assembly: count to place labels, then emit* — Ch 33
- *One handler for six sigils (`asm-do-ref`), `%target>base`* — Ch 33
- *Assembler capacity checks and exit codes 230–243* — Ch 33, Appendix G
- *Why the assembler loads `010-lib.fth` alone* — Ch 33

### The direct TinyCC extension

- *LP64 storage versus private all-stack calling convention* — Ch 34
- *Separate struct-tag namespace, aligned structs/unions, anonymous members* — Ch 34
- *Static initializer routines with constant-expression guards and ordinary fixups* — Ch 34
- *Finite Linux primitive boundary and fail-closed seed-only operations* — Ch 34
- *Restricted floating bit transport versus rebuilt TinyCC's genuine floating arithmetic* — Ch 34
- *Source preparation versus compiler execution and executable closure* — Ch 34

### Reading the proof

- *Stage-A parity check* — Ch 32, Appendix C
- *Byte-identity vs ELF-identity (why parity is on `.M1`)* — Ch 32
- *Fixed-point closure across self-compiles* — Ch 32, `tests/cc/bootstrap-chain.sh`
- *Reproducibility pins for M2-Planet, mescc-tools, stage0* — Appendix C, `REPRODUCIBLE.md`
- *Compiler exit codes (`die N`) and what each means* — Appendix G
- *Building `M1` and `hex2` without GCC (`bootstrap.sh` steps 3–5, 7)* — Ch 33

### Patterns that recur at every scale

- *Emit, remember, patch* — Ch 11, 19, 21, 25, 26, 30, 31
- *Small tables, linear search, newest wins* — Chs 17, 22, 24, 30, 31, 33
- *One buffer per responsibility* — Chs 21, 22, 26, 31, 33
- *Deferred words (`defer`/`is`) for forward references* — Chs 12, 22, 27, 30
- *Fixup-on-the-stack* — Chs 11, 19, 26, 30

## Concept index

Each row: **concept** — first introduced in *Ch N*; used by *(Ch M,
Ch O, …)*.  Concepts not listed under a "used by" appear only in
their introducing chapter.

### Vocabulary and conventions

- **Stack (data stack)** — Ch 1; *every chapter*
- **Return stack** — Ch 4; *Ch 8, Ch 14, Ch 18, Ch 26*
- **Stack-effect notation `( a b -- c )`** — Ch 1; *every chapter*
- **Forth boolean convention (`-1`/`0`)** — Ch 6; *Chs 7, 11, 19, 27, 30*
- **RPN / postfix evaluation** — Ch 1; *Chs 4, 8, 27*
- **Dictionary entry layout** (`link/flags/name-len/name/body`) —
  Ch 10; *Chs 12, 17, 18, 23, 24*
- **Cells (8-byte) and bytes (1-byte)** — Ch 2; *Chs 9, 14, 17, 21*

### Forth primitives (treated as black boxes in Part I)

- **`nand`** — Ch 1 (use); Ch 15 (machine code)
- **`+`, `dup`, `drop`, `swap`** — Ch 1 (use); Ch 14–15 (machine code)
- **`>r`, `r>`, `r@`** — Ch 4 (use); Ch 14 (machine code)
- **`@`, `!`, `c@`, `c!`** — Ch 2 (use); Ch 14 (machine code)
- **`/`, `*`, `0=`** — Ch 6–7 (use); Ch 15 (machine code)
- **`here-addr`, `c,`** — Ch 2 (definitions); Ch 9, 11, 12 (use)
- **`skip-vm-pages`** — Ch 12 (definition); Ch 21 (use)
- **`emit`, `key`** — Ch 1 (sketched); Ch 16 (machine code)
- **`syscall6`** — Ch 5 (wrapper use); Ch 16 (machine code)
- **`find`, `'`, `execute`, `read_word`** — Ch 17
- **`:`, `;`, `[lit]`, `lit`, `compile_call`** — Ch 10 (`:` used in
  `constant`); Chs 18, 20 (machine code)
- **`branch`, `0branch`** — Ch 19; *Ch 11 uses their xts*
- **`state`, `latest`** — Ch 10; *Chs 12, 18, 20*

### Forth-level ideas

- **Two's complement** — Ch 4
- **Functional completeness of NAND** — Ch 3
- **De Morgan's law as code** — Ch 3
- **Range-check trick `(c-base)/range == 0`** — Ch 6
- **Sign-extraction via `/2^63`** — Ch 7
- **Little-endian writers (`,4`, `,8`)** — Ch 9; *Chs 10, 11, 12, 21*
- **The IMMEDIATE flag** — Ch 10; *Chs 11, 12, 18, 20*
- **STATE (interpret vs compile mode)** — Ch 10; *Chs 11, 12, 18, 20*
- **The 19-byte runtime body** (`sub rbp,8; mov [rbp],rdi; movabs
  rdi,V; ret`) — Ch 10; *Ch 12, Ch 14*
- **Fixup-on-the-stack** — Ch 11; *Ch 19 (the underlying mechanism),
  Ch 30 (same idea in the C compiler's output)*
- **Emit, remember, patch** — Ch 11; *Chs 19, 21, 25, 26, 30, 31*
- **`call,` (compile a 5-byte rel32 CALL)** — Ch 10; *Chs 11, 26*
- **`[char]` (character literals compiled as `[lit]` bytes)** — Ch 10;
  *Chs 22–31*
- **Early return with `exit,` (return stack must be clean)** — Ch 11;
  *Chs 12, 23, 24*
- **Deferred words (`defer`/`is`: call a word defined later)** — Ch 12;
  *Chs 22, 27, 30*

### Seed VM internals (Part II)

- **ELF + program header** — Ch 13; *Ch 25*
- **The data-stack-in-`rdi`/`rbp` convention** — Ch 13; *Chs 14–20*
- **The sysvar page at `0x413000`** — Ch 13; *Chs 17, 18, 20*
- **The token buffer at `0x412800`** — Ch 13; *Ch 17, Ch 20*
- **The I/O scratch byte at `0x412000`** — Ch 13; *Ch 16*
- **The 16 MiB single segment** — Ch 13; *Ch 21*
- **`DIV` unsigned, `IDIV` signed** — Ch 15
- **In-line cell after CALL site** (`lit_code`) — Ch 18; *Ch 19*
- **Consumed-slot property** (branches return *to* destination, not
  past slot) — Ch 19
- **Comment skipping and loud token errors** (`read_word`,
  `report_token`: `token?`, exit status 2 on a bad `[lit]` or an
  over-long token) — Ch 17; *Ch 18, Ch 20*

### C compiler ideas (Part III)

- **Bump allocator** — Ch 21
- **Failing with a line and a code (`cc-die`, `cc-check-cap`)** — Ch 21;
  *Chs 22–31, Appendix G*
- **Lexer state as one block (mark / reset look-ahead)** — Ch 21;
  *Chs 23, 29–31*
- **Source buffer / output buffer / back-patching** — Ch 21;
  *Chs 25, 26, 30, 31*
- **One buffer per responsibility** — Ch 21; *Chs 22, 26, 31, 33*
- **Small tables, linear search, newest wins** — Ch 17; *Chs 22,
  24, 30, 31, 33*
- **Macro table (parallel arrays)** — Ch 22
- **Token kinds (`KW_*`, `ID`, `PUNCT`, `NUM`, `STR`, `CHR`)** —
  Ch 23; *Chs 27–31*
- **Compact type encoding (one word per type)** — Ch 24;
  *Chs 27–31*
- **Struct descriptor (16 + 40·N legacy, 32 + 48·N LP64 bytes)** — Ch 24; *Ch 28*
- **Symbol table (parallel arrays)** — Ch 24; *Chs 26–31*
- **Scope stack (push/pop count)** — Ch 24; *Chs 30, 31*
- **System V AMD64 calling convention** — Ch 25; *Chs 26, 28, 31*
- **Frame pointer `rbp` + local-at-`-8n` addressing** — Ch 25;
  *Chs 26, 28, 31*
- **Lvalue vs rvalue** — Ch 28
- **Precedence cascade** (one function per level; not precedence
  climbing) — Ch 27
- **Fixed 256-byte function frame** — Ch 31 (every function
  reserves the same 32-slot slab, checked by `cc-fn-add-slots`; no
  per-function back-patch)
- **Stage-A parity (byte-identical M1 output)** — Ch 32

### Assembler ideas (Part IV)

- **M1 macro (`DEFINE name value`, textual substitution)** — Ch 33
- **Sigil (`! @ ~ % $ &`: field width, absolute or end-of-field
  relative)** — Ch 33
- **Label table (name slice + address, newest wins)** — Ch 33
- **Two-pass assembly (pass 1 counts, pass 2 emits)** — Ch 33;
  *contrast with emit, remember, patch (Chs 11, 26, 30)*
- **Self-contained program (depends on `010-lib.fth` only)** — Ch 33

## Dependency graph

Each chapter lists its hard prerequisites.  Use this if you skip
around: if you jump to Ch N, the chapters in its row are the ones
whose content the prose will assume you already know.

```
Ch 0   (prologue)         — none
Ch 1   stacks/words       — none
Ch 2   here/c,            — Ch 1
Ch 3   logic from nand    — Ch 1
Ch 4   over/subtract      — Ch 1
Ch 5   syscalls           — Ch 1
Ch 6   classifiers        — Chs 1, 3, 4
Ch 7   comparisons        — Chs 1, 4, 6
Ch 8   stack shufflers    — Chs 1, 4
Ch 9   memory writers     — Chs 1, 2, 4
Ch 10  immediate/constant — Chs 1, 2, 9
Ch 11  control flow       — Chs 1, 2, 4, 9, 10
Ch 12  defining words     — Chs 2, 3, 4, 7, 9, 10, 11
        (---- Part I complete; 010-lib.fth fully literate ----)
Ch 13  ELF + entry        — Ch 1                              (opens seed)
Ch 14  stack prims        — Chs 1, 13
Ch 15  arith prims        — Chs 14
Ch 16  I/O prims          — Chs 5, 14
Ch 17  dictionary         — Chs 10, 13, 14
Ch 18  colon compiler     — Chs 10, 17
Ch 19  branches           — Chs 11, 18
Ch 20  parser + REPL      — Chs 17, 18, 19
        (---- Part II complete; 000-seed.hex0 fully literate ----)
Ch 21  arena + I/O bufs   — Chs 5, 9, 11, 12, 13
Ch 22  preprocessor       — Chs 6, 12, 21
Ch 23  lexer              — Chs 6, 12, 21, 22
Ch 24  types + symbols    — Chs 12, 21
Ch 25  ELF + codegen 1    — Chs 11, 13, 21
Ch 26  codegen 2          — Chs 24, 25
Ch 27  expressions 1      — Chs 12, 23, 24, 25, 26
Ch 28  expressions 2      — Chs 24, 26, 27
Ch 29  decls + structs    — Chs 24, 25, 26, 28
Ch 30  statements         — Chs 11, 12, 26, 27, 28, 29
Ch 31  functions          — Chs 24, 25, 26, 27, 28, 29, 30
Ch 32  main + bootstrap   — *all previous*
        (---- Part III complete; legacy driver fully literate ----)
Ch 33  assembler          — Chs 5, 6, 11, 12, 21, 32          (Part IV)
        (---- 130-asm.fth fully literate ----)
Ch 34  direct TinyCC      — Chs 23–31                         (Part V)
        (---- four native files fully literate; all -cc- files covered ----)
```

## Reading orders

The book is written for **source order**, but a curious reader has
two valid alternatives:

- **Top-down ("what is this?"):** prologue → Ch 32 (skim) → Ch 1 →
  Ch 13 → Ch 21.  Gives you the shape of the whole machine before
  diving into any layer.

- **VM-first ("how does the seed work?"):** prologue → Chs 1, 13–20
  → Chs 2–12 → Part III.  Forth's primitives become machine code
  first, then you see them used.

Source order (the default) is best for someone who has decided to
follow the project from the bottom up and wants every concept earned.

## Experimental direct-GCC components

These chapters extend the existing route; they do not establish a complete GCC
bootstrap. Their current implementation and limits are in [DIRECT-GCC.md](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/DIRECT-GCC.md).

| Chapter | Prerequisites | Executable proof |
| --- | --- | --- |
| [35: objects](35-direct-gcc-objects.md) | 21, 25, 34 | Separate objects with symbol and relocation tables |
| [36: calls](36-direct-gcc-calls.md) | 24, 31, 34, 35 | Scalar System V interoperability and original GCC ffs |
| [37: linking](37-direct-gcc-linker.md) | 13, 21, 35 | Separate C objects linked by Forth into a running program |
| [38: syscall boundary](38-direct-gcc-runtime.md) | 5, 35–37 | Forth-built process entry, errno storage, and Linux calls |
| [39: runtime](39-direct-gcc-libc.md) | 36–38 | Forth-built allocation, memory, and string execution |
| [40: target headers](40-direct-gcc-target.md) | 22, 34, 36 | Explicit target facts and original historical ANSI declarations |
| [41: typed constants](41-direct-gcc-constants.md) | 28, 34–36 | LP64 constant arithmetic and symbolic address initializers |
| [42: variadic lists](42-direct-gcc-varargs.md) | 34, 36, 37 | Array-based System V lists across separately compiled units |
| [43: streams](43-direct-gcc-stdio.md) | 35–39, 42 | Forth-built file I/O and bounded formatted generator output |
| [44: archives](44-direct-gcc-archives.md) | 35, 37 | Indexed archives and selection driven by unresolved symbols |
| [45: binary32/binary64 values](45-direct-gcc-binary64.md) | 24, 28, 36 | Typed floating operations and the scalar return boundary |
| [46: floating literals](46-direct-gcc-float-literals.md) | 1–12, 45 | Exact integer ratios rounded to binary64 without a host parser |
| [47: bitfields](47-direct-gcc-bitfields.md) | 24, 28, 36, 45 | Record layout, integer promotions, and preserving bitfield stores |
| [48: aggregate ABI](48-direct-gcc-aggregate-abi.md) | 28, 36, 45, 47 | Record byte transport, argument locations, register rollback, and result lifetimes |
