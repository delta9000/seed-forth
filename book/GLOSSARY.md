# Glossary

Quick definitions for terms used across the book.  Sorted by topic
inside each section.  When a chapter introduces a term in depth, the
glossary entry points there.

If you encounter a term in a chapter and you're not sure what it
means, search this file first.  If it isn't here, it's either
obvious from context, defined inline, or worth adding to this file
when you encounter it.

## Forth

**Cell** — the seed's native word size, 8 bytes (64 bits).  All
arithmetic and most memory operations move cells.  Single-byte
operations (`c@`, `c!`, `c,`) are the explicit exception.

**Data stack** — the LIFO that holds operands and results.  Grows
*down* in this seed (lower addresses are deeper into the stack).
TOS is cached in register `rdi`; the rest live at `[rbp]`, `[rbp+8]`,
`[rbp+16]`, ...  Initial top at `0x411000`.  Ch 13 sets it up;
Ch 14 explains the convention.

**Deferred word** — a word defined by `defer NAME` whose body runs
the xt stored in a cell after its code; `' REAL is NAME` fills the
cell.  Lets a word call one that is defined later in the file, which
mutually recursive parsers need.  Ch 12; used in Chs 22, 27, 30.

**Dictionary** — the linked list of named definitions.  Each entry is
`link(8) flags(1) name-len(1) name(N) body(M)` (Ch 10).  New entries
are added by `:`, `create`, `variable`, `constant`.  Lookup is
linear from newest to oldest via `find_code` (Ch 17).

**Forth boolean** — `-1` (all bits set) for true, `0` for false.
`0=` canonicalises any zero/non-zero value to `-1`/`0` (Ch 6).

**HERE** — the next-byte-to-write pointer in the dictionary area.
Maintained in the sysvar at `0x413010`.  Accessed via `here-addr`
(returns the address of the sysvar) or `here` (returns the
contents).  Advanced by `c,`, `,`, `,4`, `,8`, `allot`.  Ch 2.

**Immediate word** — a word with bit 0 of its flags byte set.  Runs
*at parse time* even when STATE=1 (i.e. ignores compile mode).
Ch 10 toggles the flag with `immediate`.  All control-flow
combinators in Ch 11 are immediate.

**Interpret mode** — STATE=0.  The REPL executes each parsed word
immediately.  Default mode after `bye` would resume.

**Compile mode** — STATE=1.  The REPL emits `CALL xt` (a 5-byte
relative-call instruction) into the body of the current colon
definition instead of executing the parsed word.  Immediate words
bypass this and run anyway.

**LATEST** — sysvar at `0x413008` holding the head of the dictionary
(the link cell of the most recently defined word).  `latest`
returns the *address* of this sysvar (so you can `@` or `!` it).

**Primitive** — a word whose body is hand-written x86-64 machine
code in `000-seed.hex0`, as opposed to a colon definition.  The
seed has 32 primitives total (Appendix A).

**Return stack** — the LIFO the CPU uses for `CALL` / `RET`, plus
the user's own `>r` / `r>` borrows for temporary stashing.  Lives
on the regular x86 stack starting at `rsp`.  Ch 4.

**RPN (reverse Polish notation)** — operator after operands.  `2 3 +`
not `2 + 3`.  Maps directly onto stack execution: each operand
pushes; each operator pops its operands and pushes its result.
Ch 1.

**Stack-effect notation** — `( before -- after )` documents what a
word consumes and produces.  Spaces separate items; rightmost is
TOS.  E.g. `swap ( a b -- b a )`.  Ch 1.

**STATE** — sysvar at `0x413000`; 0 in interpret mode, 1 in compile
mode.  Set to 1 by `:` and reset to 0 by `;`.  Ch 10.

**Sysvar** — one of four consecutive cells on the page at
`0x413000`: `STATE`, `LATEST`, `HERE`, `LAST_FOUND`.  Ch 13
initialises them; Ch 17 and Ch 20 use them.  `010-lib.fth` finds
`HERE`'s cell as `latest [lit] 8 +`.

**TOS / 2OS** — top of stack / second-on-stack.  In the seed, TOS
is cached in `rdi`; 2OS is at `[rbp]`.

**Under-TOS** — the cell immediately below TOS, i.e. 2OS viewed
positionally rather than as a slot index.  Used in Chs 14, 15,
16, 20 to describe binary operations that fold the under-TOS
slot into `rdi` (e.g. `add rdi, [rbp] ; add rbp, 8`).
Synonymous with 2OS.

**Word** — a named entry in the dictionary.  Identified by its
name; called by its xt.  May be a primitive or a colon definition
or a `create`d data word.

**xt (execution token)** — the address of a word's code: the first
byte after its name in the dictionary header, for the seed's
primitives and for colon definitions alike.  This is what `'`
returns, what `execute` calls and what a compiled `CALL` targets.
Equivalent to a function pointer.

## Seed-forth specifics

**The 32 primitives** — listed in Appendix A.  Each is one unit in
`000-seed.hex0`: a dictionary header (`;; --- name @ 0xNNN`)
directly followed by its code (`;; ----- name_code @ 0xNNN`), at a
fixed offset.

**The 19-byte runtime body** — the prologue shared by `constant`,
`variable`, and `create`: `sub rbp, 8 ; mov [rbp+0], rdi ; movabs
rdi, V ; ret`.  Loads a constant `V` as the new TOS.  Ch 10, Ch 12.

**`[lit]`** — the seed's only number-pushing word, immediate by
nature.  Reads the next whitespace-delimited token, parses it as
decimal, and either pushes the value (interpret mode) or appends
`CALL lit_code` + 8 inline bytes (compile mode).  A token that is
not unsigned decimal is fatal: the seed prints it with `?` and exits
with status 2.  Ch 18, Ch 20.

**`call,`** — emits a 5-byte `CALL rel32` to a given xt at
HERE.  Defined in `010-lib.fth` (Ch 10) using `,4` for the rel32.

**`[char]`** — immediate; compiles the first byte of the next token
as a literal, the same 13 bytes `[lit] N` emits.  Characters that
cannot be tokens (blank, tab, newline, `(`, `\`) are the constants
`bl`, `tab`, `nl`, `lparen`, `backslash`.  Ch 10.

**`exit,`** — immediate; compiles a `ret` for early return from the
word being defined.  Legal wherever the return stack is as the word
found it (no `>r` pending).  Ch 11.

**`bytes-eq`** — compares two byte ranges for equality, returning
with `exit,` at the first mismatch.  Ch 12.

**Consumed-slot property** — `branch_code` and `0branch_code`
return *to* their destination, not past the inline 8-byte slot.
This is what makes a single 13-byte sequence (5-byte CALL + 8-byte
target) work as a forward branch.  Ch 19.

**The fixup-on-the-stack pattern** — when `if,` is parsed, it
pushes the address of the not-yet-resolved 8-byte branch target
slot onto the data stack.  `then,` pops it and writes the current
HERE there.  Same idea generalises to `else,`, `begin,`, `while,`,
`repeat,`.  Ch 11.

**Emit, remember, patch** — the recurring shape behind fixups:
emit incomplete bytes, remember where the missing value belongs,
and patch that location when the value becomes known.  First named
in Ch 11; scaled up in Chs 21, 25, 26, 30, and 31.

**The I/O scratch byte at `0x412000`** — one byte shared by `emit`
(write) and `key` (read).  Used because `read(2)` and `write(2)`
need a buffer address.  Ch 16.

**The token buffer at `0x412800`** — where `read_word` assembles
the current whitespace-delimited token.  Used by `:`, `find`, `'`,
`[lit]`.  Ch 13, Ch 17.

## x86-64 machine

**ABI (System V AMD64)** — the Linux calling convention this
codebase outputs to.  First six integer/pointer args in `rdi`,
`rsi`, `rdx`, `rcx`, `r8`, `r9`; return value in `rax`; stack
16-byte-aligned at `call` sites.  Ch 25 introduces the encoders;
Ch 26 walks the call-site shims.

**`call rel32`** — a 5-byte instruction: `E8` + 4-byte signed
displacement.  Target = current `rip` + 5 + rel32.  `call,`
emits this.

**`DIV` / `IDIV`** — unsigned / signed 64-bit divide.  Dividend in
`RDX:RAX` (128 bits!); quotient to `RAX`, remainder to `RDX`.  The
seed's `/` primitive uses `DIV` (unsigned), which is what makes
Ch 7's sign-bit-from-divide trick work.

**`Elf64_Ehdr` / `Elf64_Phdr`** — the 64-byte ELF header and the
56-byte program header.  Ch 13 walks them field by field.

**Endianness** — x86-64 is little-endian.  All multi-byte values in
memory and in ELF have low bytes first.  The seed's `,4`, `,8`
writers are little-endian (Ch 9).

**Frame pointer** — `rbp` in System V function bodies.  In the *C
compiler's output*, `rbp` is the C frame pointer.  In the *seed
itself*, `rbp` is the data-stack pointer — different uses, same
register, in different contexts.

**imm32 / imm64** — a 32-bit or 64-bit immediate operand embedded
in an instruction.  `movabs rdi, imm64` is the long form that loads
a full 64-bit constant into `rdi`.

**ModR/M** — the byte in an x86 instruction that encodes registers
and memory addressing modes.  You won't need to compute it by hand,
but the seed's instruction encoders do.  Ch 25.

**`movabs`** — Intel mnemonic for `mov r64, imm64` (opcode `48 B?`
where `?` selects the register).  10 bytes total (REX + opcode +
8-byte immediate).  Used in the 19-byte runtime body.

**`PT_LOAD`** — an ELF segment type meaning "map this into memory."
The seed has one `PT_LOAD` covering all 16 MiB; the C compiler's
output also has exactly one, covering code and data alike
(`080-cc-elf.fth`).  Ch 13, Ch 25.

**`rax`, `rbp`, `rdi`, `rsi`, `rdx`, `r10`** — the registers most
referenced in this book.  In seed-forth: `rdi` is TOS cache,
`rbp` is data-stack pointer, `rax`/`rcx`/`rdx` are scratch.  In
compiler output: System V conventions apply.

**`rel32`** — a 32-bit signed displacement.  Used by `call` and
`jmp` for PC-relative targets within ±2 GiB.

**Sign extension** — `mov rdi, eax` zero-extends; `movsxd rdi, eax`
sign-extends.  The seed doesn't sign-extend (no negatives in the
seed's own arithmetic); the C compiler does where needed.

**`syscall`** — the x86-64 instruction that traps into the kernel.
Syscall number in `rax`; arguments in `rdi/rsi/rdx/r10/r8/r9`;
result in `rax`.  Ch 5 wraps it; Ch 16 reads the wrapper.

## C compiler

**Arena** — a bump allocator with no per-allocation free.  Used for
struct descriptors and other small overflow.  Ch 21.

**Back-patching** — emitting a placeholder byte sequence (typically
zeros), recording its offset, and later writing the resolved value
once it's known.  Used for ELF segment sizes, forward jumps inside
`if`/`while`/`for`, and function-call sites whose target isn't yet
emitted.  Ch 21 (concept), Ch 25 (`p_filesz`), Ch 30 (forward
jumps), Ch 31 (forward function calls).  Function frames are *not*
back-patched — see "Fixed 256-byte function frame" in CONCEPTS.

**`cc-die` / error code** — the one word every compiler failure ends
in.  It writes `cc: line N: error C` to stderr and exits with status
C.  N is the line the reader had reached in the preprocessed source;
C names the failure, from a range owned by the file that detected it.
`cc-check-cap` is the bounds check built on it.  Ch 21, Appendix G.

**Codegen** — the pass that emits machine code.  In this compiler,
codegen is the *only* output pass: there's no IR, no SSA, no
register allocator.  Expressions produce bytes directly.

**Eval stack (evaluation stack)** — the runtime stack used by
compiled expression code to hold intermediate results.  This
compiler uses the x86 hardware stack (`push rdi` to save the left
operand, `pop rdi` / `pop rcx` to recover it) rather than
allocating registers.  Slow but simple.

**Frame** — a function's stack region: saved `rbp`, locals,
spilled parameters.  Addressed as `[rbp - 8n]` for local n.  Always
256 bytes, 32 slots (`cc-frame-slots`); a 33rd dies with code 162.
Ch 25 (encoders), Ch 31 (per-function layout).

**Identifier / keyword / punctuator** — the three main token
classes from the lexer.  Identifiers get looked up in the symbol
table; keywords drive parser dispatch; punctuators are operators.
Ch 23.

**Lexer** — the pass that turns source bytes into a stream of
tokens.  Skips whitespace and comments; recognises identifiers,
keywords, numeric literals, string/char literals, punctuation.
Ch 23.

**Lexer state / mark** — everything the reader and lexer change as
they advance (source position, line, current token, putback flag),
kept in one 64-byte block, `cc-lex-state`.  A parser that must look
several tokens ahead copies it away with `cc-lex-mark` and back with
`cc-lex-reset`.  Ch 21 (block), Ch 23 (mark/reset).

**Lvalue / rvalue** — an *lvalue* has an address you can take or
write to (variable, deref, struct field); an *rvalue* has only a
value (literal, expression result).  Assignment requires the LHS
to be an lvalue.  The expression parser records which one `rdi`
holds in `cc-last-lvalue-kind`: `lv-value`, `lv-local`, or a
pending deref (`lv-deref`, `lv-deref-byte`) that
`cc-emit-materialize` loads only when the value is needed.  Ch 28.

**M2-Planet** — the next link in the bootstrap chain after this C
compiler.  A larger C compiler written in a subset of C; we
compile it with `cc-out` and the resulting binary is what compiles
MesCC, and so on toward a self-hosting GCC.  Ch 32.

**Parser** — the pass that consumes tokens and emits machine code
directly (no AST in this compiler).  Two recursive-descent flavours:
a precedence cascade for expressions (Ch 27), keyword dispatch for
statements and declarations (Chs 29–31).

**One buffer per responsibility** — the Part III memory discipline:
raw input, preprocessed source, emitted ELF bytes, string/global
storage, and fixup arrays each have a clear owner and cursor.  Ch 21
names the pattern; later compiler chapters reuse it.

**Small tables, linear search, newest wins** — the bootstrap-friendly
lookup pattern used by the dictionary, macro table, symbol table, and
label table.  Capacity is fixed, lookup walks linearly, and later
entries shadow earlier ones when that is the language rule.  Ch 17
introduces it; Chs 22, 24, 30, and 31 reuse it.

**Precedence cascade** — the expression-parsing technique this
compiler uses: plain recursive descent with one function per
precedence level, each parsing its operands by calling the next
tighter level and looping over its own operators.  Which operators
belong to which level, and the encoder each one calls, is one table
(`cc-binops`).  Ch 27.

**Precedence climbing** — the alternative Ch 27 does *not* use: a
single recursive function parameterised by minimum precedence,
driven by a table, in place of one function per precedence level.
Contrast **Precedence cascade**.

**Preprocessor** — the pass before the lexer that splices in
`#include`d files, records `#define`s and expands every macro use
(object-like and function-like), and keeps or drops lines by
`#if`, `#ifdef`, `#ifndef`, `#elif`, `#else` and `#endif`.  No
directive and no macro name reaches the lexer.  Ch 22.

**Prologue / epilogue** — the boilerplate at function entry / exit.
Prologue: `push rbp ; mov rbp, rsp ; sub rsp, FRAMESIZE` plus
register-arg spills.  Epilogue: `mov rsp, rbp ; pop rbp ; ret`.
Ch 25 (encoders), Ch 31 (emitted per function).

**Stage-A check** — `tests/cc/stage-a-check.sh`.  Builds M2-Planet
using `cc-out`, diffs the M1 output against a GCC-built reference.
Byte-identical = the proof of correctness.  Ch 32.

**Stage0-posix** — the previous link in the bootstrap chain.
Provides `hex0-seed`, which is what assembles `000-seed.hex0` into
the seed-forth binary.  Maintained at github.com/oriansj/stage0-posix.

**Struct descriptor** — a 16-byte header + N 40-byte field records
describing a C struct's layout.  Ch 24.

**Putback** — handing the current token back to the lexer so the next
`cc-next-token-keep` returns it again (`cc-putback-token`).  One token
deep.  Ch 23.

**Symbol table** — parallel arrays of name / kind / type / value
indexed by an integer symbol id, plus two extra cells read through
meaning-named accessors (array length, struct descriptor, call and
address fixup lists).  Hashed lookup (`cc-name-hash` buckets, newest
first); truncated on scope pop.  Ch 24.

**Type encoding** — every C type fits in one 64-bit word: base
kind in bits 16–31, pointer depth in bits 0–7.  Struct types
carry an out-of-band descriptor pointer: in the tag symbol's val and
in a struct variable's struct-desc cell.
Ch 24.

## Bootstrapping

**`asm-out`** — the output path of the Forth assembler.
`130-asm.fth` writes its ELF to the fixed path `/tmp/asm-out`, mode
0755; `bootstrap.sh` renames it.  Ch 33 §12.

**Bootstrappable Builds** — the umbrella project at
bootstrappable.org tracking efforts to reduce binary-blob
dependence in software builds.

**`cc-out`** — the output path of our C compiler.  The driver in
`120-cc-main.fth` is hard-coded to write to `/tmp/cc-out`; tests
and the bootstrap chain copy or rename this file as needed.  See
Ch 32.

**Entry stub** — the 26-byte prologue at vaddr `0x400078` that our
compiled binaries begin with: argc/argv setup, `call <main>`, exit
syscall.  Emitted by `cc-emit-entry-stub` in `116-cc-prog.fth`.
Ch 31 §8.

**Full Source Bootstrap** — the Guix project's chain from a
few hundred bytes of hex (stage0-posix's `hex0-seed`: 229 bytes on
x86-64) up to a self-hosting GCC, entirely from auditable source.  This book covers the segment from stage0's `hex0-seed`
through M2-Planet's output.

**hex0** — a minimal assembler format: each line is hex bytes plus
optional `;`-introduced comments.  No labels, no macros.  Assembled
by stage0-posix's `hex0-seed`.

**hex2** — the linker format and tool of the stage0 family: hex
bytes, `:label` declarations, and sigil references that write a
label's address, absolute or relative, into a 1- to 4-byte field.
M1 output is fed to hex2 to produce flat binaries downstream of
M2-Planet.  `130-asm.fth` implements the amd64 subset.  Ch 33 §1.

**M1** — the macro-assembly format that M2-Planet emits: hex2 plus
`DEFINE name value` macros (`DEFINE mov_rax, 48C7C0`), numeric
sigils (`%60`), and strings (`"hi"` becomes `68 69 00`).  mescc-tools'
`M1` rewrites it into hex2 text; `130-asm.fth` expands it and links
it in one program.  Ch 33 §1, §11.

**Macro table** — the preprocessor's parallel-array storage for
`#define`s: 1,024 entries of name, body, parameter count and a busy
flag, with names and bodies copied into a 64 KiB pool.  A
function-like macro's body stores each parameter as a two-byte
marker.  Ch 22 §2.

**mescc-tools** — the small toolchain (`M1`, `hex2`, `blood-elf`,
`get_machine`) that turns M2-Planet's `.M1` output into a working
ELF binary.  Maintained at github.com/oriansj/mescc-tools.

**Monolith** — the concatenated single-file form of M2-Planet's C
source produced by `tests/cc/build-m2planet-monolith.sh`.  Our
compiler has no `#ifndef`/`#endif` support, so includes must be
inlined manually before compilation.  See Ch 32 §4.

**Reproducible build** — same inputs produce byte-identical outputs.
Required for any link in the bootstrap chain to be auditable.

**Sigil** — the first character of an M1/hex2 reference token:
`!` `@` `~` (1, 2, 3 bytes, relative to the end of the field), `%`
(4 bytes relative, or `%target>base`), `$` `&` (2, 4 bytes
absolute).  Followed by a label or a number, whose value must fit
the field (hex2's bounds for a label, M1's for a number; 4-byte
fields are unchecked).  One handler, `asm-do-ref`, serves all six.
Ch 33 §9.

**Trusting trust** — Ken Thompson's 1984 paper "Reflections on
Trusting Trust" — the founding articulation of why a compiler can't
be trusted without auditing the binary that built it.  The
bootstrap chain is the answer to this paper.

**Two-pass assembly** — read the whole input twice: pass 1 only
counts bytes, to give every label its address; pass 2 emits, with
every forward and backward reference known.  The assembler's
alternative to emit, remember, patch.  Ch 33 §10.
