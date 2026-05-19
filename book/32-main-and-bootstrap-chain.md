# Chapter 32 — End to End: Main and the Bootstrap Chain

## Goal

By the end of this chapter the reader can:

- read `120-cc-main.fth`'s short `cc-main` and explain the order
  of operations end to end;
- run the full bootstrap chain (`tests/cc/stage-a-check.sh`) and
  understand each step;
- verify the byte-identical M1 output against the GCC-built
  M2-Planet reference and explain what the equality demonstrates.

## Source coverage

`120-cc-main.fth` (38 lines) — entire file.  The shell driver
`tests/cc/stage-a-check.sh` is *not* tangled (it lives outside
the literate program), but we read it here.

## Concepts introduced

- **`cc-main`'s nine-step driver.**  The composition of every
  piece of machinery built across Chs 21–31.
- **The pre-baked output path.**  A 12-byte `/tmp/cc-out\0`
  constant.
- **Auto-execution at load time.**  The bottom of the file calls
  `cc-main` directly, so loading `120-cc-main.fth` *is* running
  the compiler.
- **Stage A parity.**  `stage-a-check.sh` compiles M2-Planet
  with seed-forth + the C compiler and diffs the M1 output
  against a GCC-built reference.  Byte identity is the
  scientific result.

## Concepts carried in

- All of Parts I, II, III converge here.  Every named word in
  `cc-main` was defined earlier.

## Concepts deferred

- Nothing.  This is the end of the book proper; appendices
  follow.

---

The previous 31 chapters built a compiler one definition at a
time.  This one composes those definitions into a single
running program and ties the result to the bootstrap chain.

The compiler is one Forth program loaded as a chain of files.
The seed (`000-seed.hex0`) starts the Forth.  `010-lib.fth`
extends it.  `020-cc-arena.fth` through `110-cc-decl.fth` add
the C compiler's machinery.  `120-cc-main.fth` runs it.

The whole thing fits in 12 .fth files plus one 2,040-byte seed.

## 1. `cc-main`: nine words and a `bye`

```forth file=120-cc-main.fth
\ 120-cc-main.fth — main entry for the C-subset compiler.
\
\ Reads C source from stdin; emits ELF executable to /tmp/cc-out.
\
\ Load order (strict — do not rearrange):
\   010-lib.fth        — primitives, syscalls, control-flow, defining words
\   020-cc-arena.fth   — bump allocator (must load before 030-cc-io.fth)
\   030-cc-io.fth      — source buffer, output buffer, file I/O
\   040-cc-prep.fth    — preprocessor (#include, #define)
\   050-cc-lex.fth     — tokenizer (depends on 040-cc-prep.fth for macro lookup)
\   060-cc-types.fth   — type encoding (int, char, pointer, struct)
\   070-cc-sym.fth     — symbol table (parallel arrays, scope stack)
\   080-cc-elf.fth     — ELF header emission
\   090-cc-emit.fth    — x86-64 instruction encoders (codegen backend)
\   100-cc-expr.fth    — expression parser (depends on 090-cc-emit.fth)
\   110-cc-decl.fth    — declaration / statement parser (depends on 100-cc-expr.fth)
\   120-cc-main.fth    — entry point: cc-main

\ Pre-baked output path: "/tmp/cc-out\0"
create cc-out-path
[lit]  47 c, [lit] 116 c, [lit] 109 c, [lit] 112 c,    \ /tmp
[lit]  47 c, [lit]  99 c, [lit]  99 c, [lit]  45 c,    \ /cc-
[lit] 111 c, [lit] 117 c, [lit] 116 c, [lit]   0 c,    \ out\0

: cc-main
  cc-load-stdin
  cc-preprocess
  cc-out-init
  cc-globals-init
  cc-emit-elf-header
  cc-parse-program
  cc-finalize-globals
  cc-finalize-elf
  cc-out-path cc-write-output
  bye ;

cc-main
```

That's the whole compiler driver.  Nine words and a `bye`.

The load-order comment at the top is the contract: each file
depends on the ones above it.  `020-cc-arena.fth` must load
before `030-cc-io.fth` because the I/O buffers use `cc-alloc`
indirectly (struct descriptors live in the arena and are
referenced from `cc-sym-extra`).  `040-cc-prep.fth` must load
before `050-cc-lex.fth` because the lexer calls
`cc-macro-find-int`.  `080-cc-elf.fth` must load before
`110-cc-decl.fth` because the absolute-vaddr emitters
(`cc-emit-jmp-vaddr`, `cc-emit-call-vaddr`) reference
`cc-base-vaddr`.  And so on.

The shell driver concatenates the files in this order and pipes
them through `./seed-forth`.

## 2. The output-path constant

`cc-out-path` is a 12-byte buffer holding `/tmp/cc-out\0`:

```
/  t  m  p  /  c  c  -  o  u  t  \0
47 116 109 112 47 99 99 45 111 117 116 0
```

Each byte is laid out via `c,` (Ch 2).  This is the same
literate-bytes technique we saw for the keyword table (Ch 23
§2) and the libc-shim names (Ch 31 §8).

`cc-write-output` (Ch 21 §2) takes the buffer's address and
opens it with `O_WRONLY|O_CREAT|O_TRUNC` mode `0755`.  Hard-
coding the path keeps the seed simple — the compiler doesn't
need to know how to parse command-line arguments — at the cost
of one fixed output location per invocation.  Test drivers
work around this by running the compiler, then `cp /tmp/cc-out`
to wherever they need.

## 3. The nine steps

Read `cc-main` as a sequence of phases:

1. **`cc-load-stdin`** (Ch 21 §2) — slurp the entire C source
   into `cc-src-buf` via chunked `read()`.  Ends when
   `read` returns 0.
2. **`cc-preprocess`** (Ch 22 §8) — rewrite the source in
   place: handle `#include`s, register `#define`s in the macro
   table, expand built-in macros (`NULL`, `EOF`, etc.).
   Resets `cc-src-pos` so the lexer rewinds.
3. **`cc-out-init`** (Ch 21 §2) — zero `cc-out-pos`.
4. **`cc-globals-init`** (Ch 26 §5) — zero
   `cc-globals-pos`, `cc-gfixup-count`, and the globals
   buffer itself.
5. **`cc-emit-elf-header`** (Ch 25 §1) — write 120 bytes of
   ELF64_Ehdr + Elf64_Phdr at offset 0.  `p_filesz` and
   `p_memsz` start as 0 and will be back-patched.
6. **`cc-parse-program`** (Ch 31 §8) — the big one.  Six
   sub-steps:
   - Emit the 26-byte entry stub.
   - Emit the 11 libc shims and register their symbols.
   - Register the `memset` external prototype.
   - Register the 11 libc typedefs (`FILE`, `uint8_t`, ...).
   - Walk every top-level declaration in the preprocessed
     source, emitting function bodies as we go.
   - Patch the entry stub's `call <main>` rel32.
7. **`cc-finalize-globals`** (Ch 31 §7) — append
   `cc-globals-buf` to `cc-out-buf`, then walk every
   recorded fixup patching `movabs rdi, imm64` placeholders
   with the now-known global vaddrs.
8. **`cc-finalize-elf`** (Ch 25 §1) — patch the program
   header's `p_filesz` (and `p_memsz` if the output is large)
   to the final `cc-out-pos`.
9. **`cc-write-output`** (Ch 21 §2) — open `/tmp/cc-out` with
   `O_WRONLY|O_CREAT|O_TRUNC` mode 0755, write all of
   `cc-out-buf`, close.

Then `bye` (Ch 1 use; Ch 16 asm) — `exit(0)`.

The trailing call to `cc-main` after the colon definition is
the auto-execution.  Loading `120-cc-main.fth` defines `cc-main`
and then *calls* it.  This is why the build script can simply
concatenate all 12 files and pipe them into `./seed-forth` —
the last file ends with `cc-main`, which means the very last
token the seed processes is a call to the compiler driver.

## 4. Stage A: the parity proof

`tests/cc/stage-a-check.sh` is the verification harness.  Read
it as a five-step proof:

```sh
#!/usr/bin/env bash
# (paraphrased from tests/cc/stage-a-check.sh)
set -euo pipefail

# 1. Build seed-forth (2,040 hand-coded bytes -> ELF).
./build.sh

# 2. Build the GCC-compiled M2-Planet reference.
make -C vendor/M2-Planet
cp vendor/M2-Planet/bin/M2-Planet /tmp/seed-bootstrap/m2-ref

# 3. Use seed-forth + cc-*.fth to compile M2-Planet's monolith.
./tests/cc/build-m2planet-monolith.sh  # produces /tmp/cc-out
cp /tmp/cc-out /tmp/seed-bootstrap/cc-out-v1

# 4. Have both M2-Planet binaries (cc-out-v1 = our compiler's output,
#    and m2-ref = GCC's output) compile M2-Planet itself, then compare
#    the resulting .M1 assembly outputs.  Note the flags here are
#    M2-Planet's own, not our compiler's; our compiler is a single-
#    input stdin → /tmp/cc-out tool with no flags.
/tmp/seed-bootstrap/cc-out-v1 --architecture amd64 --expand-includes \
    -f M2libc/bootstrappable.c -f cc.c ... \
    -o /tmp/seed-bootstrap/self-v1-amd64.M1

/tmp/seed-bootstrap/m2-ref --architecture amd64 --expand-includes \
    -f M2libc/bootstrappable.c -f cc.c ... \
    -o /tmp/seed-bootstrap/self-ref-amd64.M1

# 5. Diff.  If they're byte-identical, the proof holds.
cmp /tmp/seed-bootstrap/self-v1-amd64.M1 \
    /tmp/seed-bootstrap/self-ref-amd64.M1
```

The key claim is in step 5.  Our 2,040-hand-coded-byte seed,
loaded through `000-seed.hex0`'s ELF + Forth interpreter,
extended via `010-lib.fth`, run through the 8,000-line C
compiler in `020-cc-arena.fth` through `120-cc-main.fth`,
compiles a 10,000+-line real-world C program (M2-Planet) into
byte-identical M1 output as if GCC had done it.

That equality is what makes the bootstrap *auditable*.  Every
byte of every layer above the 2,040-byte seed exists in this
book.  Every byte at the bottom is hand-encoded and explained
(Part II).  The byte-identity check rules out any silent
deviation between the seed-forth path and the GCC path.

## 5. The wider chain

Stage A is one rung of a longer ladder.  The full Guix Full
Source Bootstrap chain looks roughly like:

```
   stage0-posix's 229-byte hex0-seed
     ↓ (hand-decoded bytes → first hex assembler)
   hex0  →  hex1  →  hex2  →  M1  →  M2-Planet
     ↓
   M2-Planet (8 KB of C) compiles MesCC
     ↓
   MesCC (~1 MB) compiles TinyCC
     ↓
   TinyCC compiles GCC
     ↓
   GCC compiles everything else.
```

This book covers the *seed-forth* arm of that diagram —
alternate path from `hex0-seed` to M2-Planet via a 2,040-byte
Forth implementation rather than via the hex-stack chain.
Both arms produce byte-identical M2-Planet, which means the
seed-forth chain is a *drop-in alternative* for that segment
of the bootstrap.

The Prologue had a longer treatment of the diagram.  By now
you've seen every component along the seed-forth path:

- Ch 13–20: the 2,040-byte seed itself (`000-seed.hex0`).
- Ch 1–12: the seed's first extension (`010-lib.fth`) —
  ~280 lines of Forth that turn the seed's 32 primitives into
  a usable language.
- Ch 21–32: the C-subset compiler — ~7,000 lines of Forth
  that turn a usable language into a useful tool.

`tests/cc/bootstrap-chain.sh` (the bigger sibling of
`stage-a-check.sh`) extends the verification to stages B–G,
covering M2-Planet's self-hosting and the subsequent
TinyCC / MesCC links.  It takes minutes to run; `stage-a-check.sh`
takes seconds.

## 6. What this proves

Three things, in order of increasing strength.

**Correctness.**  The compiler's output, fed back through
itself (via M2-Planet), produces the same bytes as the
reference compiler.  Any miscompilation by seed-forth's C
compiler would produce a diff.  None do.

**Reproducibility.**  Same input bytes in, same output bytes
out, deterministically.  This is what makes the chain
*auditable*: anyone with the same source can re-derive every
byte.

**Bootstrap closure.**  The 2,040 hand-coded bytes of
`000-seed.hex0` are the only thing in this chain that doesn't
have a higher-level explanation.  Every byte above them is in
this book.  Every byte below them is in stage0-posix's
own bootstrap from its own 229-byte hex0-seed.  Closure means
you can read every line that produces every executable in your
toolchain.

That last property is what motivates the project.  Modern
software bootstraps are circular: GCC is compiled by GCC,
which was compiled by GCC.  Stepping outside that circle
requires either trusting a binary blob or recreating the chain
from scratch.  This book recreates one arm of that chain in a
form that fits in a single reader's working memory.

## Try it

```sh
./build.sh                       # 2,040-byte seed → ./seed-forth
./test.sh                        # unit tests across all layers
tests/cc/stage-a-check.sh        # the byte-identical proof
tests/cc/bootstrap-chain.sh      # the full closure (slower)
```

If `stage-a-check.sh` reports
`self-v1-amd64.M1 == self-ref-amd64.M1`, you have reproduced
the project's central claim.

To compile a small program by hand, concatenate the twelve .fth
files (stripped of Forth comments) onto stdin first, then append
the C source.  The last .fth file (`120-cc-main.fth`) ends by
calling `cc-main`, which slurps whatever's left on stdin as the C
input, compiles, writes `/tmp/cc-out`, and exits:

```sh
./build.sh
{
  cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 040-cc-prep.fth \
      050-cc-lex.fth 060-cc-types.fth 070-cc-sym.fth 080-cc-elf.fth \
      090-cc-emit.fth 100-cc-expr.fth 110-cc-decl.fth 120-cc-main.fth \
    | sed -e 's/\\.*$//' -e 's/([^)]*)//g'
  echo 'int main(void) { return 42; }'
} | grep -v '^[[:space:]]*$' | ./seed-forth
chmod +x /tmp/cc-out && /tmp/cc-out
echo $?      # 42
```

`tests/cc/build-m2planet-monolith.sh` runs the same pattern at
full scale.

## Exercises

1. **★★** Run `tests/cc/bootstrap-chain.sh` and time each step.  Which
   is slowest?  Could you speed it up without breaking
   byte-identity?

2. **★★★** Add a primitive to `000-seed.hex0` (say, `mod` from Ch 15's
   exercises).  Rebuild and run `./test.sh` plus
   `stage-a-check.sh`.  What invariants might you have
   broken?

3. **★★★** The `cc-out-path` is hard-coded to `/tmp/cc-out`.  Modify
   the compiler to read a path from stdin's first line (the
   seed doesn't expose argv directly; a stdin-prefix is the
   minimal change).  What's the smallest patch?

4. **★★★** Sketch what it would take to extend the compiler to a
   different target architecture (RISC-V, ARM64).  Which files
   change?  Which are reusable?  Hint: only `090-cc-emit.fth`
   and the ELF header in `080-cc-elf.fth` need rewriting;
   everything else is target-agnostic.

5. **★★★** The full chain is *reproducible* end-to-end.  Construct a
   diff that proves you've changed the seed-forth output
   without breaking the parity claim.  (Hint: most changes
   *do* break it; the trick is finding one that doesn't.)

## Takeaways

- `cc-main` is nine words and a `bye`.  Every layer of
  scaffolding this book covered was for *those nine words* —
  and the byte-identical M1 output they produce.
- Stage A parity with GCC is the proof of correctness: same
  bytes in, same bytes out, no hidden steps.
- The bootstrap chain is reproducible end-to-end.  This book
  is the manual for one segment of it — the seed-forth arm
  from `hex0-seed` to M2-Planet.

You have reached the end of the main book.

What you did: walked from 2,040 hand-encoded bytes to a C
compiler whose stage-A output is byte-identical to M2-Planet
built with GCC.  Every byte between the seed and the M1 output
was earned — argued for in source you have now read.  Both
stories the prologue promised — the Forth story (a language
small enough to host its own compiler) and the bootstrap story
(a chain auditable because the seed is small enough to read) —
converge here.  They are the same story told from two ends.

The four appendices that follow are the reference cards a reader
will want on a second pass:

- **[A — The 32 seed primitives](A1-32-seed-primitives.md):** every
  primitive in one table.
- **[B — The memory map](A2-memory-map.md):** every fixed address
  the book referenced.
- **[C — The reproducibility chain](A3-reproducibility-chain.md):**
  hex0 → seed → M2-Planet with commands and expected hashes.
- **[D — Worked exercises](A4-worked-exercises.md):** three
  exercises walked end to end.

Turn the page.
