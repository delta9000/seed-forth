# Chapter 32 — End to End: Main and the Bootstrap Chain

```text
Missing capability: the built compiler has not been tied to the bootstrap proof.
New pattern: compose the load-order driver and shell checks that compare against GCC-built M2-Planet.
Artifact after this chapter: the Stage-A harness and byte-identical .M1 parity check.
Proof link: the proof is direct parity of emitted .M1 text, not identity of compiler ELFs.
```

Thirty-one chapters have defined words.  This one calls them.
`120-cc-main.fth` is a 37-line file: a 12-byte `/tmp/cc-out\0` constant,
a colon definition `cc-main` that runs nine words from Chs 21–31 in
order and then `bye`, and a bare `cc-main` on the last line, so
that loading the file runs the compiler.

The second half of the chapter reads `tests/cc/stage-a-check.sh`,
a shell script outside the literate program.  It feeds the twelve
`.fth` files and M2-Planet's source through `./seed-forth`, then
checks that the resulting M2-Planet binary emits the same `.M1`
text as GCC-built M2-Planet when both compile M2-Planet's own
sources.  That is a parity check, not a fixed point; the fixed
point (v2 == v3) is a separate stage, covered in §5.

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

The load-order comment at the top says each file depends on the
ones above it.  Some edges are stricter than the
code needs.  The comment says `020-cc-arena.fth` must load before
`030-cc-io.fth`, but `030` uses nothing from `020`.  The real
consumers of `cc-alloc` come later: `090-cc-emit.fth`
(`cc-add-fixup-to-list`) and `110-cc-decl.fth` (struct
descriptors, switch cases).  `040-cc-prep.fth` must load
before `050-cc-lex.fth` because the lexer calls
`cc-macro-find-int`.  `080-cc-elf.fth` must load before
`100-cc-expr.fth` and `110-cc-decl.fth` because their string-literal
and absolute-vaddr emitters (`cc-emit-jmp-vaddr`,
`cc-emit-call-vaddr`) read `cc-here-vaddr`.  And so on.

## 2. The output-path constant

`cc-out-path` is a 12-byte buffer holding `/tmp/cc-out\0`:

```
/  t  m  p  /  c  c  -  o  u  t  \0
47 116 109 112 47 99 99 45 111 117 116 0
```

Each byte is laid out with `c,` (Ch 2), as in the keyword table
(Ch 23 §2) and the libc-shim names (Ch 31 §8).

`cc-write-output` (Ch 21 §2) takes the buffer's address and
opens it with `O_WRONLY|O_CREAT|O_TRUNC` mode `0755`.  A fixed
path means the compiler never parses command-line arguments, at
the cost of one fixed output location.  Test drivers
work around this by running the compiler, then `cp /tmp/cc-out`
to wherever they need.

## 3. The nine steps

Read `cc-main` as a sequence of phases:

1. **`cc-load-stdin`** (Ch 21 §2): slurp the entire C source
   into `cc-in-buf` with `cc-read-all`.  Ends when `read`
   returns 0; a source that fills the 1 MiB buffer is error 20.
2. **`cc-preprocess`** (Ch 22 §8): rewrite `cc-in-buf` into
   `cc-src-buf`: splice in `#include`s, register `#define`s in
   the macro table, prime the built-in macros (`NULL`, `EOF`,
   etc.).  Resets `cc-src-pos` and `cc-src-line` so the lexer
   starts at the top.
3. **`cc-out-init`** (Ch 21 §2): zero `cc-out-pos`.
4. **`cc-globals-init`** (Ch 26 §5): zero
   `cc-globals-pos`, `cc-gfixup-count`, and the globals
   buffer itself.
5. **`cc-emit-elf-header`** (Ch 25 §1): write 120 bytes of
   ELF64_Ehdr + Elf64_Phdr at offset 0.  `p_filesz` and
   `p_memsz` start as 0 and will be back-patched.
6. **`cc-parse-program`** (Ch 31 §8): the big one, in seven
   sub-steps:
   - Emit the 26-byte entry stub.
   - Emit the 11 libc shims and register their symbols.
   - Register the `memset` external prototype.
   - Register the 11 libc typedefs (`FILE`, `uint8_t`, ...).
   - Walk every top-level declaration in the preprocessed
     source, emitting function bodies as we go.
   - Die (194, 195) if a used function never got a body or there
     is no `main`.
   - Patch the entry stub's `call <main>` rel32.
7. **`cc-finalize-globals`** (Ch 31 §7): append
   `cc-globals-buf` to `cc-out-buf`, then walk every
   recorded fixup patching `movabs rdi, imm64` placeholders
   with the now-known global vaddrs.
8. **`cc-finalize-elf`** (Ch 25 §1): patch the program
   header's `p_filesz` (and `p_memsz` if the output is large)
   to the final `cc-out-pos`.
9. **`cc-write-output`** (Ch 21 §2): open `/tmp/cc-out` with
   `O_WRONLY|O_CREAT|O_TRUNC` mode 0755, write all of
   `cc-out-buf`, close.

Then `bye` (used since Ch 1, defined in Ch 16) calls `exit(0)`.

Because the last token of `120-cc-main.fth` is a call to
`cc-main`, a build script only has to concatenate the twelve files
and pipe them into `./seed-forth`.  Whatever follows on stdin is
the C source that `cc-load-stdin` reads.

**tri.c, one last time.**  Chs 27–31 each disassembled one slice of
tri.c's binary.  Here are all nine steps on the whole program:

```sh
{ cat 010-lib.fth [0-9][0-9][0-9]-cc-*.fth; cat <<'C'
#define ROWS 4
struct tri { int rows; int stars; };
struct tri t;

void line(int pad, int n) {
    while (pad > 0) { putchar(' '); pad = pad - 1; }
    while (n > 0) { putchar('*'); n = n - 1; }
    putchar('\n');
}

int main() {
    int w[ROWS];
    int r;
    t.rows = ROWS;
    for (r = 0; r < t.rows; r = r + 1) {
        w[r] = 1 + r * 2;
        line(t.rows - 1 - r, w[r]);
        t.stars = t.stars + w[r];
    }
    if (t.stars == ROWS * ROWS) return t.stars;
    return 1;
}
C
} | ./seed-forth
chmod +x /tmp/cc-out && /tmp/cc-out
echo "exit: $?"                  # prints "exit: 16"
wc -c < /tmp/cc-out              # prints: 1241
```

```
   *
  ***
 *****
*******
exit: 16
1241
```

Nothing is stripped on the way in.  The seed's reader skips the
Forth comments itself (Ch 17), and once `cc-main` runs, the rest of
stdin is read raw, so `(int pad, int n)` reaches the compiler
intact.  Measured between
the steps, `cc-load-stdin` read 484 bytes and `cc-preprocess` cut
them to 470 (the `#define` line is gone, its newline kept) with
`ROWS` as the eighth macro.  The header is 120 bytes, and
`cc-parse-program` took the output to 1,225 bytes of code plus 16
bytes of globals, which `cc-finalize-globals` appended.
`cc-finalize-elf` wrote the resulting 1,241 into `p_filesz`
(`d9 04 00 00` at offset 0x60).  Run it again and `sha256sum
/tmp/cc-out` gives the same `d15b9d90…ca5ac8a`.

tri.c is a teaching program, not evidence.  It is not part of
Stage A or of any test script, and nothing compares its bytes with
GCC's.  GCC, given the same source with `#include <stdio.h>` added,
prints the same triangle and exits 16, but that is a check of
behaviour, done by hand.  The evidence is the same pipeline with
M2-Planet's source in place of tri.c's 22 lines.

## 4. Stage A: the parity proof

`tests/cc/stage-a-check.sh` runs five steps:

```sh
#!/usr/bin/env bash
# (paraphrased from tests/cc/stage-a-check.sh)
set -euo pipefail

# 1. Build seed-forth (1,772 hand-coded bytes -> ELF).
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

The claim rests on step 5.  The 1,772-byte seed, extended by
`010-lib.fth` and running the 6,715 lines of compiler Forth in
`020-cc-arena.fth` through `120-cc-main.fth`, compiles a real-world C program (M2-Planet: 8,479 lines across the
11 files of the self-compile source set) into a binary.  That
binary, compiling M2-Planet's sources, emits the same `.M1` text
as GCC-built M2-Planet does.

The comparison is on the emitted `.M1`, not on the two compiler
ELFs: those differ, because GCC and this compiler generate
different machine code for the same C.  What matches is their
output.

That equality is what makes this segment auditable.  Every byte
of the seed-forth arm above the 1,772-byte seed is either quoted as
literate source in this book or emitted by source this book walks.
The byte-identity check rules out silent deviation between the
seed-forth path and the GCC reference at the `.M1` handoff.

## 5. The wider chain

Stage A is one rung of a longer ladder.  The full Guix Full
Source Bootstrap chain looks roughly like:

```
   stage0-posix's 229-byte hex0-seed
     ↓ (hand-decoded bytes → first hex assembler)
   hex0  →  hex1  →  hex2  →  M1  →  M2-Planet
     ↓
   M2-Planet (~8,500 lines of C) compiles MesCC
     ↓
   MesCC (~1 MB) compiles TinyCC
     ↓
   TinyCC compiles GCC
     ↓
   GCC compiles everything else.
```

This book covers the *seed-forth* arm of that diagram: an
alternate path from `hex0-seed` to M2-Planet via a 1,772-byte
Forth implementation rather than via the hex-stack chain.  The two
arms do not agree by default.  The default `cc-out-v1` matches the
GCC-built reference, not a stage0-built M2-Planet: stage0's
toolchain skips one `sub_rsp, imm` optimization that GCC-built
M2-Planet takes.  Build `cc-out-v1` with `STAGE0_COMPAT=1` and its
`.M1` matches a stage0-built M2-Planet compiled from the same
M2-Planet source (Appendix C).  In that mode the seed-forth arm is
a drop-in alternative for that segment of the bootstrap.

The Prologue drew this diagram in more detail.  By now you've
seen every component along the seed-forth path:

- Ch 13–20: the 1,772-byte seed itself (`000-seed.hex0`).
- Ch 1–12: the seed's first extension (`010-lib.fth`),
  ~470 lines of Forth that turn the seed's 32 primitives into
  a usable language.
- Ch 21–32: the C-subset compiler, 6,715 lines of Forth
  (`020-cc-arena.fth` through `120-cc-main.fth`, by `wc -l`)
  that turn a usable language into a useful tool.

`tests/cc/bootstrap-chain.sh` (the bigger sibling of
`stage-a-check.sh`) runs sub-stages A–G once per architecture
(`x86` and `amd64` by default).  A is the parity check above.  B
assembles v1's `.M1` with M1 + hex2 into `cc-out-v2`.  C checks
that v1 and v2 compile a one-line `tiny.c` identically.  D has v2
self-compile; its difference from v1's `.M1` is recorded, not
failed.  E assembles that into `cc-out-v3`.  F is the fixed
point: v3's self-compile must equal v2's byte for byte.  G has v3
compile, link and run a `hello.c`.  A final stage compiles every
program in M2-Planet's own test suite with v1 and with the GCC
reference (x86 output): each must produce the same bytes from both,
or be rejected by both, or the stage fails.  Nothing past
M2-Planet (no MesCC, no TinyCC) is run.  It takes minutes;
`stage-a-check.sh` takes seconds.

Stages B and E assemble with mescc-tools' `M1` and `hex2`, which
are built with GCC.  `130-asm.fth` is a Forth replacement for that
pair, and the one source file no chapter teaches: a 689-line M1
macro expander and two-pass hex2 linker that loads on
`010-lib.fth` alone, reads M1 text on stdin and writes an ELF to
`/tmp/asm-out`.  `tests/asm/m2planet-check.sh` feeds it M2-Planet's
libc and the `self-v1-amd64.M1` from Stage A and checks that its
output is byte-identical to what mescc-tools produces from the same
input; the other `tests/asm/` scripts run it on small fixtures and
on inputs it must reject (Appendix G).

## 6. What this proves

Three things, in order of increasing strength.

**Correctness.**  The compiler produced by seed-forth emits the same
M2-Planet `.M1` text as the GCC-built reference compiler on the same
stage-A input.  A miscompilation in a code path that M2-Planet's
self-compile exercises would produce a diff.  None do.  That is
narrower than "no miscompilations": Chs 28, 30 and 31 describe bugs
that changed no Stage-A byte, because M2-Planet never ran the code
they broke.  The test gates in those chapters, and the test-suite
parity stage of `bootstrap-chain.sh`, cover what Stage A misses.

**Reproducibility.**  Same input bytes in, same output bytes
out, deterministically.  This is what makes the chain
*auditable*: anyone with the same source can re-derive every
byte.

**Bootstrap closure.**  The 1,772 hand-coded bytes of
`000-seed.hex0` are the only bytes in the seed-forth arm that do not
come from a higher-level source language.  This book explains that
arm up to the M2-Planet-compatible compiler it produces; the
canonical downstream chain continues in M2-Planet, mescc-tools,
MesCC, TinyCC, and GCC.  Closure means you can keep following source
all the way down instead of trusting an unexplained binary jump.

That last property is what motivates the project.  Modern
software bootstraps are circular: GCC is compiled by GCC,
which was compiled by GCC.  Stepping outside that circle
requires either trusting a binary blob or recreating the chain
from scratch.  This book recreates one arm of that chain in a
form that fits in a single reader's working memory.

## Try it

**Small check:** the manual compile below builds a tiny `return 42`
program through the full Forth compiler pipeline.

**Layer check:** build the seed and run the cross-layer unit suite.

```sh
./build.sh                       # 1,772-byte seed → ./seed-forth
./test.sh                        # unit tests across all layers
```

**Bootstrap relevance:** these are the proof commands.  Stage-A is
the byte-identical `.M1` parity check; `bootstrap-chain.sh` extends
that closure through the slower downstream stages.

```sh
tests/cc/stage-a-check.sh        # the byte-identical proof
tests/cc/bootstrap-chain.sh      # the full closure (slower)
```

If `stage-a-check.sh` reports
`self-v1-amd64.M1 == self-ref-amd64.M1`, you have reproduced
the project's central claim.

To run the small check, concatenate the twelve `.fth` files onto
stdin first, exactly as they are, then append the C source.  The last `.fth` file (`120-cc-main.fth`) ends by calling
`cc-main`, which slurps whatever's left on stdin as the C input,
compiles, writes `/tmp/cc-out`, and exits.

`tests/cc/build-m2planet-monolith.sh` already does exactly this
pipeline at full scale, with nothing between `cat` and the seed.
For the toy `return 42` case, the same shape distilled to one
terminal:

```sh
./build.sh
{ cat 010-lib.fth [0-9][0-9][0-9]-cc-*.fth; echo 'int main(void) { return 42; }'; } \
    | ./seed-forth
chmod +x /tmp/cc-out && /tmp/cc-out
echo $?      # 42
```

The pattern `010-lib.fth [0-9][0-9][0-9]-cc-*.fth` names the library,
then globs the eleven `-cc-` files (`020-cc-arena.fth` through
`120-cc-main.fth`) in numerical (load) order, which names all
twelve files without listing them.  The `-cc-` infix matters: it skips
`130-asm.fth`, which is not part of the C-compiler vocabulary and
would corrupt the compile if fed in.  If you find yourself editing
this pipeline, edit `build-m2planet-monolith.sh` instead.  It is the version the
test suite exercises, and a divergence between the two would go
unnoticed until Stage-A broke.

## Exercises

1. **★★ Verify.** Run `tests/cc/bootstrap-chain.sh` and time each step.  Which
   is slowest?  Could you speed it up without breaking
   byte-identity?

2. **★★★ Extend.** Add a primitive to `000-seed.hex0` (say, `mod` from Ch 15's
   exercises).  Rebuild and run `./test.sh` plus
   `stage-a-check.sh`.  What invariants might you have
   broken?

3. **★★★ Modify.** The `cc-out-path` is hard-coded to `/tmp/cc-out`.  Modify
   the compiler to read a path from stdin's first line (the
   seed doesn't expose argv directly; a stdin-prefix is the
   minimal change).  What's the smallest patch?

4. **★★★ Extend.** Sketch what it would take to extend the compiler to a
   different target architecture (RISC-V, ARM64).  Which files
   change?  Which are reusable?  Hint: `090-cc-emit.fth` and the
   ELF header in `080-cc-elf.fth` are the obvious rewrites, but
   not the only ones.  `100-cc-expr.fth` emits raw x86 bytes
   inline (assignment's `72 137 207` is `mov rdi, rcx`), and
   `110-cc-decl.fth` holds the entry stub, `cc-emit-jmp-vaddr`
   and friends, and the rdi/rbx register conventions.  The
   front end (`020`–`070`) is reusable.

5. **★★★ Verify.** The full chain is *reproducible* end-to-end.  Construct a
   diff that proves you've changed the seed-forth output
   without breaking the parity claim.  (Hint: most changes
   *do* break it; the trick is finding one that doesn't.)

## After this chapter

`cc-main` runs every Part III layer in load order.
`stage-a-check.sh` builds M2-Planet with it and confirms that the
result, compiling M2-Planet's sources, emits `.M1` text
byte-identical to the GCC-built reference: two different compilers,
the same output on the same input.  `bootstrap-chain.sh` goes on to
assemble that output, reach the v2 == v3 fixed point, and compare
M2-Planet's test suite.

You can read both scripts, explain why the proof compares emitted
`.M1` rather than the compiler ELFs, and trace any byte in the
seed-forth arm back to its source.

## Takeaways

- `cc-main` is nine words and a `bye`, and loading `120-cc-main.fth` runs it on whatever C source follows on stdin.
- Stage A shows that the M2-Planet built by this compiler emits the same `.M1` as GCC-built M2-Planet, which covers every code path M2-Planet's self-compile exercises and leaves the rest to the test gates.
- This book is the manual for one arm of the bootstrap chain, from 1,772 hand-coded bytes to an M2-Planet-compatible compiler.

That is the end of the main book.  You started from 1,772
hand-encoded bytes and read, in source, every step to a C compiler
whose Stage-A `.M1` output matches M2-Planet built with GCC.  The
Prologue named two things that had to work together: a mechanical
test that fluent-looking code cannot fake, and a literate program
that keeps a human able to read every line.  Stage A is the first;
the thirty-two chapters you just read are the second.

What that leaves you with is concrete.  Pick any of the 1,241 bytes
of tri.c's binary and you can name the Forth word that wrote it, the
chapter that walks that word, and the seed primitives underneath.
Run `stage-a-check.sh` and you can watch the M2-Planet built by GCC
and the one this book's compiler built emit the same `.M1`, byte for
byte.  And when someone asks where your compiler came from, you can
point to a file of hex you have read, and to every line of source
between it and the output.

The appendices are reference cards for a second pass:

- **[A — The 32 seed primitives](A1-32-seed-primitives.md):** every
  primitive in one table.
- **[B — The memory map](A2-memory-map.md):** every fixed address
  the book referenced.
- **[C — The reproducibility chain](A3-reproducibility-chain.md):**
  hex0 → seed → M2-Planet with commands and expected hashes.
- **[D — Worked exercises](A4-worked-exercises.md):** three
  exercises walked end to end.
- **[E — Further reading](A5-further-reading.md):** Forth,
  compilers, bootstrap, ELF/x86-64: the older work this book
  stands on.
- **[F — The C subset](A6-c-subset.md):** types, operators,
  statements, and the features that are *not* in this compiler.
- **[G — Compiler exit codes](A7-error-codes.md):** status codes
  mapped to failure modes for when something dies on you.
