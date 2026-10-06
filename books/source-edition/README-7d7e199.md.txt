# Seed Forth to M2-Planet and TinyCC

This directory contains a minimal x86-64 Linux Forth seed and the Forth-coded
C-subset compiler needed to reach M2-Planet compatibility and, with
an opt-in extension, compile TinyCC directly.

The trust root is `000-seed.hex0`: an annotated hex0 file that encodes a
1772-byte hand-written ELF/Forth image.  The seed is intentionally small: it
provides only the primitives needed to load the numbered Forth files and
compile a M2-Planet monolith.  The main check is
byte-identical M1 output against a GCC-built M2-Planet reference.

## Get the sources

Platform: **amd64 (x86-64) Linux only**.  You need `git`, `bash` and
coreutils; `python3` for the book checks and `gcc` for the comparisons
against GCC-built references (`check-all.sh` skips those steps without
them; `verify.sh` requires gcc).  About 400 MB of disk with every
build output.

```sh
git clone https://github.com/delta9000/seed-forth
cd seed-forth
git -c url.https://github.com/oriansj/mescc-tools.git.insteadOf=https://git.savannah.nongnu.org/git/mescc-tools.git \
    submodule update --init --recursive       # ~25 s with the clone
```

The `-c url…insteadOf=…` part matters: `vendor/stage0-posix`'s own
`.gitmodules` fetches its nested `mescc-tools` from
`git.savannah.nongnu.org`, which is often slow or unreachable (a
`CONNECT tunnel failed` or timeout aborts the whole recursive update).
The rewrite fetches the same pinned commit (`5adfbf3`) from the
GitHub mirror, for this one command only; nothing is saved to your
git config.  If savannah works for you, a plain
`git submodule update --init --recursive` does the same.

**If a recursive update already failed part-way**, run the command
above again with `--force` added.  A failed run can leave submodules
registered at the right commit but with empty working trees
(`vendor/stage0-posix/bootstrap-seeds` in particular), and `git`
won't repopulate them without `--force`; `build.sh` then reports
`hex0 assembler not found` even though the submodule looks
initialised.

**Minimal checkout.**  `bootstrap.sh`, `check-all.sh` and `verify.sh`
need only these; the stage0-posix steps (`handoff`, `stage0-check`)
then report SKIP instead of failing:

```sh
git submodule update --init --recursive vendor/M2-Planet vendor/mescc-tools
git submodule update --init vendor/stage0-posix
git -C vendor/stage0-posix submodule update --init bootstrap-seeds
```

`vendor/pnut` (pnut at `abc34a5`, no nested submodules) supplies the TinyCC archive, kit patches, and portable-libc sources used by
the direct route. It is also needed by `tests/pnut/sf-pnut-check.sh` and
`tests/pnut/sf-pnut-amd64-check.sh`, which build pnut with the Forth C
compiler (and go on to TinyCC); both controls report SKIP without it:

```sh
git submodule update --init vendor/pnut
```

## Bootstrap it (no GCC)

From the repository root, with the submodules fetched as above:

```sh
./bootstrap.sh                 # ~30 s; output in ./build-out/out (BUILDROOT= to move it)
```

What you get, all in `build-out/out/` with a `SHA256SUMS` file:

| Artifact | What it is |
|----------|------------|
| `seed-forth` | the 1,772-byte Forth, assembled from `000-seed.hex0` by stage0-posix's 229-byte `hex0-seed` |
| `cc-out-v1` | M2-Planet, compiled by the Forth C compiler (`020`–`120-cc-*.fth`) |
| `M1`, `hex2` | mescc-tools' assembler and linker, compiled by M2-Planet and assembled by the Forth assembler `130-asm.fth` |
| `cc-out-v2`, `cc-out-v3` | M2-Planet self-hosted: v1's self-compile assembled by `M1`+`hex2`, and again |

The script fails unless v2 and v3 compile M2-Planet to byte-identical
`.M1` (the self-hosting fixed point), `M1`/`hex2` rebuild themselves
byte for byte, and a `hello.c` built by v3 runs.

What you trust: the 229-byte `hex0-seed`; this repository's `.hex0` and
`.fth` sources; the pinned C and M1 *sources* of `vendor/M2-Planet` and
`vendor/mescc-tools` (no binary from them is run); the Linux kernel; and
the host `bash` and `cat` (bash, not `sed`, strips M2-Planet's
`#include "..."` lines).  `mkdir`/`rm`/`mv` only manage files; `cmp`,
`wc`, `sha256sum` only check and report.  No host C compiler, assembler
or linker runs, and nothing is compared with a GCC-built binary.  The
header of `bootstrap.sh` states this precisely.  The comparisons
against GCC-built references (Stage A, the x86 and amd64 chains,
M2-Planet test-suite parity, mescc-tools byte-identity) are a separate
script, `./verify.sh` (~6½ min, needs gcc), which also runs the two
stage0-posix checks below.

### Hand off to stage0-posix and live-bootstrap

```sh
./handoff.sh                   # amd64 + x86, ~4½ min; output in ./build-out/handoff
ARCHES=amd64 ./handoff.sh      # amd64 only, ~75 s
```

This needs stage0-posix's nested submodules (`AMD64`, `x86`, `M2-Planet`,
`M2libc`, `mescc-tools`, `mescc-tools-extra`, `M2-Mesoplanet`), which the
recursive update in [Get the sources](#get-the-sources) fetches;
without them `handoff.sh` exits 77 (SKIP).  The x86 part also needs a
kernel that runs 32-bit i386 programs (IA-32 emulation); without it
x86 is skipped (exit 77) after amd64 passes.

`handoff.sh` puts the Forth route where stage0-posix's hex1 → hex2 →
M0 → `cc_amd64` → M2 phases would be: `cc-out-v3` compiles stage0's
Phase-5 input (M2-Planet `bd2fe4b`) into `artifact/M2`, and the
Forth-route `M1`/`hex2` stand in for `M0`/`hex2-0`.  Then
stage0-posix's own AMD64 recipe runs unchanged from Phase 6, and all
19 binaries it builds (M2-Planet, blood-elf, M1, hex2, kaem,
M2-Mesoplanet, mescc-tools-extra) match stage0-posix's
`amd64.answers`.  Of stage0-posix's seed binaries only `hex0-seed`
runs.  With `cc-out-v2` itself in the `M2` slot, 12 of 19 match, and
all 19 one generation later.  live-bootstrap reads exactly that set
at stage0-posix's `after.kaem` hook, so from there you continue with
live-bootstrap as usual; `REPRODUCIBLE.md` says what to do by hand.
The same stand-ins, cross-built for i386 by the same amd64 tools,
drive stage0-posix's x86 recipe to all 19 `x86.answers` binaries:
x86 is live-bootstrap's supported architecture.  The seed itself is
x86-64, so this needs an amd64 kernel that also runs 32-bit programs;
a pure-i386 machine would need a 32-bit port of the seed (see
`REPRODUCIBLE.md`).

**Diverse double-compiling.**  `tests/cc/stage0-check.sh` (~60 s)
runs stage0-posix's chain from its seeds, then rebuilds M2-Planet
`0a67a68` with stage0's recipe starting once from stage0's
`cc_amd64`-built M2 and once from the Forth-built `cc-out-v1`.  One
generation later both give the same binary, byte for byte, also when
each side links only with its own M1/hex2/blood-elf (the Forth side's
built by the Forth route), and the two sides rebuild identical
M1, hex2 and blood-elf.  No binary is shared from the seed on; they
share the `hex0-seed` file, the C/M1 sources, the kernel and bash.
amd64 only.

### Directly to TinyCC, without a pnut executable

The opt-in LP64 extension compiles the pinned, patched TinyCC 0.9.27
and portable-libc C sources directly in Forth. It replaces the pnut
compiler executable in this route. The vendored pnut kit remains the
source of the TinyCC archive, compatibility patches, and portable libc;
its provenance and licenses remain relevant. The legacy default and
pnut routes below remain independent controls.

From the repository root, the default route starts with raw pinned inputs:

```sh
./build.sh
python3 tools/tcc_inputs.py
./seed-forth < tools/tcc-ladder-start.fth
```

For the actual host entry plus inventory and helper checks, run
`tests/tcc/kernel-route-check.sh`. It resets the known generated route
outputs and performs the raw-input bootstrap. `tests/tcc/sf-tcc-check.sh`
is an independent prepared-source fixed-point check (optional fresh
`BUILDROOT`), not the default launcher's source supplier.

Host setup verifies/copies 50 pinned raw archive/libc/tool inputs plus
local sources and fixtures. Forth builds the exact-patch and archive
helpers; those generated programs unpack the original TinyCC archive and
apply the checked patches. All 440 prepared-file pins are verified before
Forth compiles TinyCC and portable libc. Include handling, macro expansion,
parsing, instruction generation, initialization, and ELF output are all in
Forth. No pnut executable, host C compiler, `cpp`, assembler, linker,
host libc, or object file participates.

The direct seed is 870,752 bytes, SHA-256
`7411c326d30ff5a0ebadfe36d6218b6e46d2e8357f76d3a003e74ed9aee2fc3a`.
It uses LP64 object storage and a private all-stack ABI. Its restricted
bootstrap float mode transports eight-byte integer bits, and unsupported
`localtime`, `ldexp`, or `longjmp` calls report their names and exit 125.
This seed is the intermediate compiler, not a claim of general floating
arithmetic in Forth.

The rebuilt TinyCC reaches the same `tcc-boot2 = tcc-boot3` executable
and object fixed points as the pnut control. Its 305,496-byte executable
hash remains
`514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1`.
All 136 portable-libc checks pass, and separate acceptance tests exercise
real float/double/long-double arithmetic, bitfields, variable-length
arrays, and block-scope enums in the rebuilt compiler.

The earlier prepared-source isolation test also rebuilt the pinned seed
from the original Forth seed in a root with no `/bin` or `/usr`; its
stronger syscall-audited gate reports SKIP here because tracing is denied.
That narrower proof is separate from raw-input guest validation; see the
exact scope and current results in [HOST-TOOLS.md](HOST-TOOLS.md).
A fresh raw-input QEMU test also passed the actual K0 → K1 handoff and
K1's independent seed/TinyCC rebuild. A longer GNU/Linux attempt was
interrupted before completion; full Linux validation remains pending.
The [KVM handoff instructions](k1/README.md#full-linux-validation-with-kvm)
include the archive pins and exact completion markers.

[The direct-route instructions](tests/tcc/README.md) separate source
preparation, compiler execution, and fixed-point checks.
[Chapter 34](book/34-direct-tinycc.md) explains the extension and contains
its canonical source; [REPRODUCIBLE.md](REPRODUCIBLE.md) records the pins.

### Control routes to TinyCC through pnut

The Forth C compiler also builds [pnut](https://github.com/udem-dlteam/pnut)
(`vendor/pnut`, `pnut.c` exactly as shipped), and pnut's TinyCC kit
builds tcc-0.9.27 from there.  There are two routes:

```sh
tests/pnut/sf-pnut-amd64-check.sh    # amd64 route, ~10 s, no gcc
SF_PNUT_TCC=1 tests/pnut/sf-pnut-check.sh   # i386 route (needs IA-32 emulation), ~2 min
```

- **i386 route** (`sf-pnut-check.sh`): SF builds a pnut that emits i386
  code.  pnut's own kit then runs unchanged to its published
  `tcc-boot2 = tcc-boot3` hash.  An M2-Planet-built pnut builds the same
  `pnut-exe`.
- **amd64 route** (`sf-pnut-amd64-check.sh`): every program is an x86-64
  ELF.  SF builds `pnut.c` for `target_x86_64_linux` and pnut self-hosts
  (g2 = g3).  pnut's kit, adapted for x86_64, then builds tcc-0.9.27 with
  `TCC_TARGET_X86_64` up to `tcc-boot2 = tcc-boot3`.  `tcc-boot2` then
  builds and runs 64-bit arithmetic, printf and hello-world tests and
  portable_libc's own test suite.  It also builds a pnut that rebuilds
  pnut64-g2 byte for byte. Every stage's sha256 is pinned in
  `tools/amd64.recipe`.
  `./verify.sh` adds a reference comparison: a gcc-built tcc, seeded the
  same way, reaches the same `tcc-boot2`.

The amd64 route can also be launched without the convenience shell script:

```sh
./seed-forth < tools/amd64-start.fth
```

After initial seed/source/descriptor setup, it needs no host Bash, grep,
cat/copy/move/hash utility, Git/archive tool or patch program. The seed
builds its own narrow runner, pnut builds the include flattener and patch
helper, and bintools extracts the source archive. This passes in a fresh
root with only the seed executable and no `/bin` or `/usr`. Linux remains
a prerequisite. [HOST-TOOLS.md](HOST-TOOLS.md) defines and tests the exact
boundary; the optional GCC15 continuation has a larger boundary.

pnut's kit supports only i386, so the amd64 route carries its own changes
in [`patches/amd64/`](patches/amd64/README.md).  Upstream sources are
pinned by hash, and nothing is sent upstream.  There are 11 unified diffs,
each with a header that explains it:

- **pnut** (1): `HEAP_SIZE` goes up by a third, only for the pnut that
  compiles tcc.
- **tcc** (4): two work around pnut limits (a block-scope `enum`, a VLA).
  The other two fix bugs in tcc-0.9.27's own x86_64 `-static` linking
  (the PLT and GOT are never filled).  A gcc-built tcc-0.9.27 makes the
  same crashing binary without them.
- **portable_libc** (6): x86_64 `crt1`, tcc's x86_64 `stdarg.h`,
  `assert.h` and `abort`.  Also `printf`'s `l`/`ll` modifiers and unsigned
  conversions, and `puts`' newline.

The tcc source is the tarball vendored in pnut (`kit/tcc-0.9.27.tar.gz`).
The script checks its sha256 before unpacking it.  `REPRODUCIBLE.md`
("Past M2-Planet on amd64 alone") lists the pins and every hash.

### On to GCC 15.2, on amd64

[`gcc64/run-gcc64.sh`](gcc64/README.md) carries the amd64 route's
`tcc-boot2` on through musl-1.1.24 to GCC 15.2.0, with no host compiler,
assembler or linker:

```
tcc-boot2 -> tcc + musl-1.1.24 (fixed point) -> binutils-2.30 -> gcc-4.0.4
  (gcc-B = gcc-C) -> musl, gmp, mpfr, mpc -> gcc-4.7.4 -> binutils-2.41
  -> gcc-10.5.0 -> gcc-15.2.0 (its own 3-stage bootstrap: stage2 = stage3)
```

```sh
gcc64/run-gcc64.sh --fetch      # sources into build-out/gcc64-cache, every sha256 checked
gcc64/run-gcc64.sh              # all 13 stages, ~1.5 h on 4 cores; output in build-out/gcc64
VERIFY_GCC64=1 ./verify.sh      # the same as verify.sh's opt-in step 10
```

Every compiler, assembler and linker is built by the stage before it,
and each GCC compiles and runs C tests (and C++ from 4.7.4 on).  The
fixed points are enforced, and every key output is pinned in
`gcc64/HASHES`; most hashes embed the build path, so they are checked in
full only at the canonical `BUILDROOT`.  Sources are pinned by sha256 in
`gcc64/SOURCES`, not vendored.  Patches (most from live-bootstrap, some
ours for tcc on x86_64) are in [`patches/gcc64/`](patches/gcc64/README.md).
Still trusted from the host: build glue (bash, make, sed, coreutils,
tar, xz, patch, python3 for one text substitution, ...), host bison and
m4 as code generators for gcc-4.0.4, and the tarballs' pregenerated
`configure` scripts.  `gcc64/README.md` has the trust statement, the
open issues and the plan for replacing the glue with chain-built tools.

## Quick Start

From the repository root, with the submodules fetched as in
[Get the sources](#get-the-sources):

```sh
./check-all.sh                 # build, legacy/native tests, book, Stage-A, bootstrap, pnut controls, direct route, handoff
./verify.sh                    # ~6½ min, needs gcc: every GCC-reference comparison + stage0-posix checks
```

`check-all.sh` is a wrapper that runs sixteen steps
with per-step OK/SKIP/FAIL output (logs in `${TMPDIR:-/tmp}/check-all-*.log`); Stage-A and the small assembler
checks are skipped (not failed) if `gcc` isn't installed.  The last
five steps run `./bootstrap.sh`, `tests/pnut/sf-pnut-check.sh` (the
Forth C compiler builds pnut unmodified, and that pnut agrees with an
M2-Planet-built one), `tests/pnut/sf-pnut-amd64-check.sh` (the amd64
pnut control on to tcc-0.9.27), `tests/tcc/kernel-route-check.sh`
(the actual direct kernel/ladder host entry), and `./handoff.sh` (its main route only, on
bootstrap.sh's output), which need no gcc; the pnut steps are skipped
without `vendor/pnut`, the handoff step if stage0-posix's nested
submodules are not checked out.  For diagnosing a failure, the
individual commands are:

```sh
./build.sh
./test.sh
tests/tcc/native-check.sh
tests/tcc/kernel-route-check.sh   # actual host entry; QEMU guest checks are separate
tests/tcc/sf-tcc-check.sh         # independent prepared-source fixed-point check
tools/tangle.sh verify --strict
tools/check-numbers.py
tools/check-tryit.py
tools/gen-index.py --check
tools/check-links.py           # book links + heading anchors (mdBook slug rules)
tests/cc/stage-a-check.sh
./bootstrap.sh
BOOTSTRAP_OUT=build-out/out tests/pnut/sf-pnut-check.sh   # SF_PNUT_TCC=1: on to tcc-0.9.27
tests/pnut/sf-pnut-amd64-check.sh                         # amd64 route to tcc-0.9.27
BOOTSTRAP_OUT=build-out/out ARCHES=amd64 ROUTE_B=0 ./handoff.sh
```

`--recursive` is needed because `vendor/M2-Planet`,
`vendor/mescc-tools` and `vendor/stage0-posix` carry nested submodules
(`M2libc`, `M2libc`, and `bootstrap-seeds` plus the stage0-posix
sources, respectively).  CI (`.github/workflows/check.yml`) runs
`check-all.sh`, `verify.sh` and a book build with the link check on
every push and pull request.

`build.sh` assembles `000-seed.hex0` with stage0-posix's 229-byte
`hex0-seed` — the same trust-root assembler Guix uses for its Full
Source Bootstrap.  No `xxd` / `vim` dependency.  Override with
`HEX0=/path/to/your/hex0 ./build.sh` to use a different assembler.

`stage-a-check.sh` builds `cc-out-v1` with seed-forth (in its `BUILDROOT`,
with a private `/tmp` when `unshare -rm` works), uses it to compile
M2-Planet for `amd64`, and compares that `.M1` output byte-for-byte with the
GCC-built M2-Planet reference.

If you already have populated upstream checkouts elsewhere:

```sh
M2_PLANET=/tmp/M2-Planet tests/cc/stage-a-check.sh
```

For every comparison against GCC-built references (Stage A, the
per-arch closure chain, M2-Planet's test suite, mescc-tools), plus
`stage0-check.sh` and the full `handoff.sh`, run:

```sh
./verify.sh                    # or tests/cc/bootstrap-chain.sh for the chain alone
```

## File Map

| Path | Role |
|------|------|
| `000-seed.hex0` | Annotated hand-coded seed Forth ELF. |
| `build.sh` | Strips comments/whitespace from `000-seed.hex0` and writes `seed-forth`. |
| `010-lib.fth` | Forth helpers: syscalls, booleans, comparisons, control-flow combinators, defining words. |
| `020-cc-arena.fth` .. `116-cc-prog.fth` | C-subset compiler layers loaded by seed-forth (the parser is `100-cc-expr.fth` expressions, `110-cc-decl.fth` declarations, `112-cc-stmt.fth` statements, `114-cc-func.fth` functions, `116-cc-prog.fth` file scope and entry stub). |
| `115-cc-native.fth`, `117-cc-native-program.fth`, `118-cc-native-init.fth`, `119-cc-native-runtime.fth` | Opt-in direct TinyCC declarations, private stack ABI, initializers and Linux boundary; canonical source in book Ch 34. |
| `120-cc-main.fth` | Default compiler entry point; reads C from stdin and writes `/tmp/cc-out`. |
| `test.sh` / `test-*.fth` | Local unit/smoke tests for layers 010–070; the upper layers (080–116) are exercised end-to-end by `tests/cc/`. |
| `bootstrap.sh` | The GCC-free build: hex0-seed → seed-forth → M2-Planet, M1, hex2 → self-hosted M2-Planet fixed point. |
| `verify.sh` | Every comparison against GCC-built references (runs the `tests/` scripts below), then `tests/cc/stage0-check.sh` and `handoff.sh`; with `VERIFY_GCC64=1` also `gcc64/run-gcc64.sh`. |
| `handoff.sh` | The Forth route in place of stage0-posix's hex1/hex2/M0/`cc_amd64`/`cc_x86` phases; stage0-posix's own recipes then reproduce all 19 `amd64.answers` and all 19 `x86.answers` binaries. |
| `tests/cc/*.sh` | M2-Planet monolith build, Stage-A parity, full bootstrap-chain, the stage0-posix cross-check (`stage0-check.sh`), and GCC reference (`build-gcc-refs.sh`) scripts. |
| `tests/asm/*.sh` | `130-asm.fth` checks against GCC-built mescc-tools, small fixtures up to M2-Planet, M1 and hex2. |
| `tests/cc/G*.c`, `M*.c`, headers | Small tracked cases that document the C subset. |
| `vendor/M2-Planet`, `vendor/mescc-tools` | Pinned upstream submodules used by the checks. |
| `vendor/stage0-posix` | Pinned upstream containing the `hex0-seed` assembler `build.sh` uses. |
| `vendor/pnut` | Pinned pnut (`abc34a5`), the C compiler `tests/pnut/sf-pnut-check.sh` builds with the Forth C compiler, unmodified. |
| `tests/tcc/` | Direct source preparation, native compiler tests, full `sf-tcc-check.sh` bootstrap, rebuilt-feature checks, and source-only closure verifier. |
| `tools/tcc-start.fth`, `tools/tcc-compile.fth` | Original-seed launcher and Forth compiler driver for staged direct TinyCC sources. |
| `tests/pnut/` | `sf-pnut-check.sh` (i386 route to TinyCC) and `sf-pnut-amd64-check.sh` (amd64 route; its test programs in `tests/pnut/amd64/`). |
| `patches/amd64/` | Our patches for the amd64 route: pnut's heap size, four tcc-0.9.27 patches, six portable_libc patches (see its README). |
| `gcc64/` | `run-gcc64.sh`, the amd64 chain from `tcc-boot2` to GCC 15.2 via musl, its build helpers, `SOURCES` (source pins) and `HASHES` (artifact pins); see its README. |
| `patches/gcc64/`, `tests/gcc64/` | That chain's patches (musl, tcc, gcc-4.0.4, and live-bootstrap's gcc-4.7.4/10.5.0 ones) and test programs. |

Generated binaries such as `seed-forth`, `/tmp/cc-out` and `build-out/` are not source.

## Reading Order

The checked-in files are the source of record.  Start with `000-seed.hex0`, which
annotates the hand-written ELF bytes, then read the numbered `.fth` files in
lexical order.  The C-compiler loader globs `010-lib.fth` plus
`[0-9][0-9][0-9]-cc-*.fth` in numeric order, with the executing
`120-cc-main.fth` held until last by `tools/compiler-layers.sh`. Optional
library layers numbered after 120 must be defined before main reads C input.
The assembler `130-asm.fth` (book Ch 33) lives outside that pattern:
it loads on `010-lib.fth` alone.

## Seed Vocabulary

The seed dictionary currently exposes:

`bye` `emit` `key` `dup` `drop` `swap` `>r` `r>` `@` `!` `c@` `c!`
`+` `nand` `0=` `find` `here` `,` `execute` `:` `;` `lit` `branch`
`0branch` `[lit]` `syscall6` `/` `r@` `*` `state` `latest` `'`

Everything above this layer is built in Forth.

## Memory Layout

| Region | Purpose |
|--------|---------|
| `0x400000` | ELF load base. |
| `0x400078` | Entry point. |
| `0x401000` | Initial `HERE`. |
| `0x410000..0x411000` | Seed data stack. |
| `0x412000` | Single-byte I/O scratch. |
| `0x412800` | Token buffer. |
| `0x413000` | Sysvars: `STATE`, `LATEST`, `HERE`, `LAST_FOUND`. |
| `0x414000+` | Forth-level compiler buffers. |

The ELF program header maps 16 MiB so the Forth compiler can allocate source,
preprocessor, symbol, output, and fixup buffers without needing `mmap`.

## AI Research & Authorship

This project is an experiment in **AI-collaborative systems engineering**. The primary research goal was to investigate whether a diverse ensemble of Large Language Models (LLMs) could successfully bridge the "semantic gap" between high-level architectural intent and the byte-perfect, hand-encoded machine code required for a bootstrap seed.

The implementation—including the ELF/Forth primitives in `000-seed.hex0`, the layered compiler design, and the verification pipeline—is a collective synthesis artifact produced by the human author in collaboration with:

- **Anthropic:** Claude Opus 4.7 (1M ctx) / Claude Sonnet 4.6
- **Google:** Gemini 3 Pro / Gemma 4 31B-it
- **OpenAI:** GPT-5.5 (Codex CLI)
- **DeepSeek:** 4 Pro / Flash
- **Alibaba:** Qwen 3.6 35B-A3B
- **Moonshot:** Kimi K2.6
- **MiniMax:** 2.7

This repository serves as a proof-of-concept that LLMs can be utilized to navigate the extreme constraints of low-level bootstrap chains, providing an expressive and auditable path from a tiny hex seed to a self-hosting C environment.

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

## Invariants

- `./build.sh` must produce a 1772-byte `seed-forth`.
- `./test.sh` must pass.
- `tests/cc/stage-a-check.sh` must report `self-v1-amd64.M1 == self-ref-amd64.M1`.
- `./bootstrap.sh` must reach the v2 == v3 fixed point with no GCC in provenance.

See `REPRODUCIBLE.md` for the full fixed-point chain.

## Reading the book

The 34-chapter book lives under `book/` as Markdown.  Render it
with [mdBook](https://rust-lang.github.io/mdBook/):

```sh
cargo install mdbook --version 0.4.40 --locked   # one-time; or unpack the
                              # x86_64-unknown-linux-gnu release tarball from
                              # github.com/rust-lang/mdBook/releases (CI does)
mdbook serve                  # live preview at http://localhost:3000
mdbook build                  # static HTML in docs/ (gitignored)
tools/check-links.py --html docs   # links + anchors, cross-checked with the render
```

The Markdown sources in `book/` are the source of record — every
`file=…` fenced code block tangles back to the actual `.fth` /
`.hex0` file via `tools/tangle.sh verify --strict`.
