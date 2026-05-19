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

**Sysvar** — one of six cells on the page at `0x413000`: `STATE`,
`LATEST`, `HERE`, `LAST_FOUND`, `NUMBER_HOOK`, `INPUT_FD`.  Ch 13
initialises them; Ch 17 and Ch 20 use them.

**TOS / 2OS** — top of stack / second-on-stack.  In the seed, TOS
is cached in `rdi`; 2OS is at `[rbp]`.

**Word** — a named entry in the dictionary.  Identified by its
name; called by its xt.  May be a primitive or a colon definition
or a `create`d data word.

**xt (execution token)** — the address of a word's body.  This is
what `'` returns and what `execute` calls.  Equivalent to a
function pointer.

## Seed-forth specifics

**The 32 primitives** — listed in Appendix A.  Their bodies live at
fixed offsets in `000-seed.hex0` and are reached via dictionary
headers in the `--- name @ 0xNNN ---` block.

**The 19-byte runtime body** — the prologue shared by `constant`,
`variable`, and `create`: `sub rbp, 8 ; mov [rbp+0], rdi ; movabs
rdi, V ; ret`.  Loads a constant `V` as the new TOS.  Ch 10, Ch 12.

**`[lit]`** — the seed's only number-pushing word, immediate by
nature.  Reads the next whitespace-delimited token, parses it as
decimal, and either pushes the value (interpret mode) or appends
`CALL lit_code` + 8 inline bytes (compile mode).  Ch 20.

**`comma-call`** — emits a 5-byte `CALL rel32` to a given xt at
HERE.  Defined in `010-lib.fth` (Ch 11) using `,4` for the rel32.

**`bytes-eq`** — compares two byte ranges for equality.  No
short-circuit because the seed lacks `exit`; accumulates the
running flag in a variable.  Ch 12.

**Consumed-slot property** — `branch_code` and `0branch_code`
return *to* their destination, not past the inline 8-byte slot.
This is what makes a single 13-byte sequence (5-byte CALL + 8-byte
target) work as a forward branch.  Ch 19.

**The fixup-on-the-stack pattern** — when `if,` is parsed, it
pushes the address of the not-yet-resolved 8-byte branch target
slot onto the data stack.  `then,` pops it and writes the current
HERE there.  Same idea generalises to `else,`, `begin,`, `while,`,
`repeat,`.  Ch 11.

**`NUMBER_HOOK`** — sysvar pointing at an optional xt that the REPL
calls on a `find` miss before printing `?`.  Lets higher layers add
auto-number-parsing.  Ch 20.

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
16-byte-aligned at `call` sites.  Ch 26.

**`call rel32`** — a 5-byte instruction: `E8` + 4-byte signed
displacement.  Target = current `rip` + 5 + rel32.  `comma-call`
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
output has two (code + data).  Ch 13, Ch 25.

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
once it's known.  Used for ELF segment sizes, frame sizes, forward
jumps, function calls to not-yet-defined functions.  Ch 21, Ch 30,
Ch 31.

**Codegen** — the pass that emits machine code.  In this compiler,
codegen is the *only* output pass: there's no IR, no SSA, no
register allocator.  Expressions produce bytes directly.

**Eval stack (evaluation stack)** — the runtime stack used by
compiled expression code to hold intermediate results.  This
compiler uses the x86 hardware stack (`push rax` / `pop rax`)
rather than allocating registers.  Slow but simple.

**Frame** — a function's stack region: saved `rbp`, locals,
spilled parameters.  Addressed as `[rbp - 8n]` for local n.
Ch 26, Ch 31.

**Identifier / keyword / punctuator** — the three main token
classes from the lexer.  Identifiers get looked up in the symbol
table; keywords drive parser dispatch; punctuators are operators.
Ch 23.

**Lexer** — the pass that turns source bytes into a stream of
tokens.  Skips whitespace and comments; recognises identifiers,
keywords, numeric literals, string/char literals, punctuation.
Ch 23.

**Lvalue / rvalue** — an *lvalue* has an address you can take or
write to (variable, deref, struct field); an *rvalue* has only a
value (literal, expression result).  Assignment requires the LHS
to be an lvalue.  Ch 28.

**M2-Planet** — the next link in the bootstrap chain after this C
compiler.  A larger C compiler written in a subset of C; we
compile it with `cc-out` and the resulting binary is what compiles
MesCC, and so on toward a self-hosting GCC.  Ch 32.

**Parser** — the pass that consumes tokens and emits machine code
directly (no AST in this compiler).  Two recursive-descent flavours:
precedence climbing for expressions (Ch 27), keyword dispatch for
statements and declarations (Chs 29–31).

**Precedence climbing** — an expression-parsing technique that uses
a single recursive function parameterised by minimum precedence,
in place of one function per precedence level.  Ch 27.

**Preprocessor** — the pass that handles `#include`, `#define`, and
conditional compilation before the lexer sees the source.  Ch 22.

**Prologue / epilogue** — the boilerplate at function entry / exit.
Prologue: `push rbp ; mov rbp, rsp ; sub rsp, FRAMESIZE` plus
register-arg spills.  Epilogue: `mov rsp, rbp ; pop rbp ; ret`.
Ch 26, Ch 31.

**Stage-A check** — `tests/cc/stage-a-check.sh`.  Builds M2-Planet
using `cc-out`, diffs the M1 output against a GCC-built reference.
Byte-identical = the proof of correctness.  Ch 32.

**Stage0-posix** — the previous link in the bootstrap chain.
Provides `hex0-seed`, which is what assembles `000-seed.hex0` into
the seed-forth binary.  Maintained at github.com/oriansj/stage0-posix.

**Struct descriptor** — a 16-byte header + N 40-byte field records
describing a C struct's layout.  Ch 24.

**Symbol table** — parallel arrays of name / kind / type / value
indexed by an integer symbol id.  Linear scan for lookup;
truncated on scope pop.  Ch 24.

**Type encoding** — every C type fits in one 64-bit word: base
kind in bits 16–31, pointer depth in bits 0–7.  Struct types
carry an out-of-band descriptor pointer in the symbol's val slot.
Ch 24.

## Bootstrapping

**Bootstrappable Builds** — the umbrella project at
bootstrappable.org tracking efforts to reduce binary-blob
dependence in software builds.

**`cc-out`** — the output path of our C compiler.  The driver in
`120-cc-main.fth` is hard-coded to write to `/tmp/cc-out`; tests
and the bootstrap chain copy or rename this file as needed.  See
Ch 32.

**Entry stub** — the 26-byte prologue at vaddr `0x400078` that our
compiled binaries begin with: argc/argv setup, `call <main>`, exit
syscall.  Emitted by `cc-emit-entry-stub` in `110-cc-decl.fth`.
Ch 31 §8.

**Full Source Bootstrap** — the Guix project's chain from ~512
bytes of hex up to a self-hosting GCC, entirely from auditable
source.  This book covers the segment from stage0's `hex0-seed`
through M2-Planet's output.

**hex0** — a minimal assembler format: each line is hex bytes plus
optional `;`-introduced comments.  No labels, no macros.  Assembled
by stage0-posix's `hex0-seed`.

**hex2** — a slightly richer hex assembler in the stage0 family
that supports labels and rel32 patching.  M1 output is fed to hex2
to produce flat binaries downstream of M2-Planet.

**M1** — the macro-assembly format that M2-Planet emits.  Each
M2-Planet output is a sequence of mnemonic lines (`PUSH_RAX`, `ADD
RAX,RCX`, label definitions, etc.) consumed by `M1` (a small
assembler in mescc-tools) to produce hex2-input.

**Macro table** — the preprocessor's parallel-array storage for
`#define`s: 256 entries × name/body/length triples plus a 16 KiB
name pool.  Ch 22 §4.

**mescc-tools** — the small toolchain (`M1`, `hex2`, `blood-elf`,
`get_machine`) that turns M2-Planet's `.M1` output into a working
ELF binary.  Maintained at github.com/oriansj/mescc-tools.

**Monolith** — the concatenated single-file form of M2-Planet's C
source produced by `tests/cc/build-m2planet-monolith.sh`.  Our
compiler has no `#ifndef`/`#endif` support, so includes must be
inlined manually before compilation.  See Ch 32 §4.

**Reproducible build** — same inputs produce byte-identical outputs.
Required for any link in the bootstrap chain to be auditable.

**Trusting trust** — Ken Thompson's 1984 paper "Reflections on
Trusting Trust" — the founding articulation of why a compiler can't
be trusted without auditing the binary that built it.  The
bootstrap chain is the answer to this paper.
