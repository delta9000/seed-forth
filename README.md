# Seed Forth to M2-Planet

This directory contains a minimal x86-64 Linux Forth seed and the Forth-coded
C-subset compiler needed to reach M2-Planet compatibility.

The trust root is `000-seed.hex0`: an annotated hex0 file that encodes a
2040-byte hand-written ELF/Forth image.  The seed is intentionally small: it
provides only the primitives needed to load the numbered Forth files and
compile a M2-Planet monolith.  The main check is
byte-identical M1 output against a GCC-built M2-Planet reference.

## Quick Start

From the repository root:

```sh
git submodule update --init
./build.sh
./test.sh
tests/cc/stage-a-check.sh
```

`stage-a-check.sh` builds `/tmp/cc-out` with seed-forth, uses it to compile
M2-Planet for `amd64`, and compares that `.M1` output byte-for-byte with the
GCC-built M2-Planet reference.

If you already have populated upstream checkouts elsewhere:

```sh
M2_PLANET=/tmp/M2-Planet tests/cc/stage-a-check.sh
```

For the slower end-to-end closure check, run:

```sh
tests/cc/bootstrap-chain.sh
```

## File Map

| Path | Role |
|------|------|
| `000-seed.hex0` | Annotated hand-coded seed Forth ELF. |
| `build.sh` | Strips comments/whitespace from `000-seed.hex0` and writes `seed-forth`. |
| `010-lib.fth` | Forth helpers: syscalls, booleans, comparisons, control-flow combinators, defining words. |
| `020-cc-arena.fth` .. `110-cc-decl.fth` | C-subset compiler layers loaded by seed-forth. |
| `120-cc-main.fth` | Compiler entry point; reads C from stdin and writes `/tmp/cc-out`. |
| `test.sh` / `test-*.fth` | Local unit/smoke tests for layers 010–070; the upper layers (080–110) are exercised end-to-end by `tests/cc/`. |
| `tests/cc/*.sh` | M2-Planet monolith build, Stage-A parity, and full bootstrap-chain scripts. |
| `tests/cc/G*.c`, `M*.c`, headers | Small tracked cases that document the C subset. |
| `vendor/M2-Planet`, `vendor/mescc-tools` | Pinned upstream submodules used by the checks. |

Generated binaries such as `seed-forth` and `/tmp/cc-out` are not source.

## Reading Order

The checked-in files are the source of record.  Start with `000-seed.hex0`, which
annotates the hand-written ELF bytes, then read the numbered `.fth` files in
lexical order.  The full compiler loaders glob `[0-9][0-9][0-9]-*.fth`,
so the filenames carry the load order.

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
| `0x413000` | Sysvars: `STATE`, `LATEST`, `HERE`, `LAST_FOUND`, `NUMBER_HOOK`, `INPUT_FD`. |
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

- `./build.sh` must produce a 2040-byte `seed-forth`.
- `./test.sh` must pass.
- `tests/cc/stage-a-check.sh` must report `self-v1-amd64.M1 == self-ref-amd64.M1`.

See `REPRODUCIBLE.md` for the full fixed-point chain.
