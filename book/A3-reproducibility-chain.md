# Appendix C — Reproducibility: the full hex0 → seed → M2-Planet chain

The bootstrap story is auditable end-to-end: every link in this
chain produces byte-identical output from byte-identical input,
and every link's source is human-readable in this repository or
in a vendored upstream.

This appendix walks the chain from the trust-root assembler
(`hex0-seed` from stage0-posix, 229 bytes) up to the byte-identity
proof against M2-Planet built with GCC.  Each stage names the
exact command and the artifact it produces.

The book proper covers the *middle* of this chain: the seed-Forth
binary at one end and the C compiler's M2-Planet self-compile
output at the other.  The links *before* and *after* are mentioned
in passing in the prologue and Ch 32; this appendix consolidates
them.

## The chain

```
  stage0-posix's hex0-seed        ← 229 bytes; the trust root
              │
              │ (assembles)
              ▼
  000-seed.hex0   (2,040 bytes of annotated hex)
              │
              │  hex0-seed 000-seed.hex0 seed-forth
              ▼
  seed-forth      (2,040-byte x86-64 ELF; this book's subject)
              │
              │  cat 010-lib.fth 020-cc-arena.fth … 120-cc-main.fth m2planet.c | seed-forth
              ▼
  /tmp/cc-out     (an x86-64 ELF that is a C compiler)
              │
              │  cc-out --architecture amd64 -f m2planet-sources… > out.M1
              ▼
  out.M1          (M2-Planet self-compile, in M1 assembly)
              │
              │  M1 + hex2 from mescc-tools
              ▼
  cc-out-v2       (a second-generation M2-Planet binary)
              │
              │  cc-out-v2 self-compiles M2-Planet again
              ▼
  cc-out-v3       (third generation; must equal cc-out-v2 byte for byte)
```

Stage A — *byte-identity against the GCC reference* — is the
proof the book builds toward.  Stages B–G — assembling, running
the compiled compiler, reaching a fixed point — are what
`tests/cc/bootstrap-chain.sh` covers.

## Reproducing each stage

All commands run from the repository root.

### Stage 0 — assemble the seed

```sh
./build.sh
```

What this does: invokes `vendor/stage0-posix/.../hex0-seed
000-seed.hex0 seed-forth`, producing a 2,040-byte ELF executable.

Expected output:
```
Built seed-forth (2040 bytes) using vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
```

Sanity check:
```sh
wc -c seed-forth      # 2040
file seed-forth       # ELF 64-bit LSB executable, x86-64
```

### Stage 1 — run the Forth and library tests

```sh
./test.sh
```

What this does: feeds curated input to `./seed-forth` and checks
exit codes and stdout.  Includes the literate-program tangle
verifier (`tools/tangle.sh verify`), all seed primitives, the
`010-lib.fth` definitions, and the REPL paths.

Expected: every line prints `PASS:`; final exit code 0.

### Stage 2 — compile M2-Planet with seed-forth's C compiler

```sh
./tests/cc/build-m2planet-monolith.sh
```

What this does: concatenates M2-Planet's `.c` source files into a
single monolith (stripping `#include "..."` lines since the
preprocessor has no `#ifndef`/`#endif`), then pipes it through
`seed-forth` loading `010-lib.fth` through `120-cc-main.fth`.
The output is `/tmp/cc-out` — an x86-64 ELF binary that is
itself a working M2-Planet-compatible C compiler.

Expected:
```sh
[ -x /tmp/cc-out ] && echo "compiled"
```

### Stage A — the byte-identity proof

```sh
./tests/cc/stage-a-check.sh
```

What this does:

1. builds `cc-out-v1` from Stage 2 above (cached if present);
2. builds `m2-ref` via `make` in `vendor/M2-Planet` (GCC builds the
   reference);
3. runs both compilers on the *same* M2-Planet source set;
4. diffs the resulting `.M1` files.

Expected output:
```
stage-a-check: PASS (amd64 .M1 byte-identical)
```

A single byte of difference fails the check and exits non-zero.

### Stage B–G — the full fixed-point bootstrap

```sh
./tests/cc/bootstrap-chain.sh
```

What this does: runs stages B (M1+hex2 assemble v1's output →
`cc-out-v2`), C–D (v2 sanity + self-compile), E–F (v3 = v2's
self-compile assembled; v3 must equal v2 byte-for-byte at the
fixed point), and G (compile `hello.c` end-to-end and run it).

This script takes longer (minutes) and exercises the full chain.

## What "byte-identical" means here

The `.M1` files compared in Stage A are *textual* M1 assembly
(mescc-tools format), not raw ELF.  Byte-identity at the M1 stage
is equivalent to byte-identity at the eventual ELF stage, because
M1 + hex2 are deterministic.

Two reasons M1 (not ELF) is the comparison point:

1. ELF output depends on `mtime` and toolchain version in some
   headers; M1 is plain text and toolchain-independent.
2. The point of the bootstrap chain is the *compiler*, not the
   *assembler*: if our cc emits the same `.M1` as GCC's cc emits,
   our compiler is correct.

## What the chain proves and does not prove

It proves: starting from 229 bytes of hex0 assembler (the
stage0-posix trust root), you can build a 2,040-byte Forth, use it
to compile a 1,300-line C compiler, and that C compiler produces
byte-identical M1 output to GCC-built M2-Planet.  Every byte is
auditable.

It does *not* prove: that the resulting compiler is bug-free, that
M2-Planet is bug-free, that the kernel running this is not
compromised, or that the broader Guix Full Source Bootstrap chain
beyond M2-Planet is auditable.  See `REPRODUCIBLE.md` for the
caveats and the stage0-byte-identity option.

The chain is *one segment* of a larger one.  See
[bootstrappable.org](https://bootstrappable.org) for the rest.
