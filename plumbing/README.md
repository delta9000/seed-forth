## Parser generators without host plumbing

`lexers.kaem` builds oyacc 6.6, ordinary Heirloom lex 070527 and its
five-member `libl.a`, then flex 2.5.11. The stage runs only project-built
kaem, seed-cc, seed-ar, make 3.82 and the stage-1 file tools, plus the
seed-cc-built [lexer-prepare.c](lexer-prepare.c). Python is used only for
reference builds and verification, outside the native stage.

From the repository root:

```sh
./seed-forth < tools/seed-cc-start.fth
mkdir -p build-out/plumbing/bin
build-out/seed-cc/seed-cc -static vendor/mescc-tools/Kaem/kaem.c vendor/mescc-tools/Kaem/variable.c vendor/mescc-tools/Kaem/kaem_globals.c vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.c -o build-out/plumbing/bin/kaem
build-out/plumbing/bin/kaem --verbose --strict --file plumbing/stage1.kaem
build-out/plumbing/bin/kaem --verbose --strict --file plumbing/lexers.kaem
```

The initial `mkdir` above prepares the kaem output directory; after stage 1,
all stage commands use built tools. First cache stage-1 archives as described
in [the plumbing status](../gcc-direct/PLUMBING.md), and the three lexer
archives in `build-out/lexer-inputs/archives/` as described in the
[recorded recipe](../gcc-direct/README.md#recorded-parser-generator-recipe).
[lexers.SOURCES](lexers.SOURCES) pins the exact archives and repository
reference files from [sources.json](../gcc-direct/lexer-inputs/sources.json).
The native stage uses the repository's pinned reference files directly;
the Python reference needs a copy of `recipe-reference/` in its inputs tree.

Outputs are `build-out/plumbing/bin/{oyacc,lex,flex}`. Ordinary lex form
files remain in `build-out/plumbing/src/heirloom-devtools-070527/lex/`;
`lexer-prepare lexconfig` records that absolute path in a generated header,
and `main-unit.c` includes that header before unchanged upstream `main.c`.
Retain that source directory when using lex. The stage requires fresh
`oyacc-6.6`, `heirloom-devtools-070527` and
`flex-d160f0247ba1611aa59d28f027d6292ba24abb50` directories under
`build-out/plumbing/src/`; it fails if any already exists. For a rebuild,
remove only those three scratch directories first. Other plumbing stages
and installed tools are independent.

### Source preparation and configuration

The preparation reproduces [lexers.py](../gcc-direct/lexers.py) and
[prepare-lexer-sources.py](../gcc-direct/prepare-lexer-sources.py): unpack
pinned originals, apply unchanged `scan_l.patch` then `yyin.patch`, copy
unchanged `scan.lex.l`, remove shipped `parse.c`, `parse.h`, `scan.c` and
`skel.c`, then regenerate the skeleton from original `flex.skl`. No shipped
parser/scanner C becomes a build input. Provenance and licenses for the
patches and restricted temporary scanner remain in
[PROVENANCE.md](../gcc-direct/lexer-inputs/PROVENANCE.md).

The built `lexer-prepare patch` applies each full unified hunk at its unique,
exact context, allowing line offsets (the first historical patch needs -1)
but no fuzz. It consumes the original patch payloads, checks hunk counts,
and rejects missing or ambiguous context. `skeleton` emits the same header,
line escaping and terminator as `mkskel.sh`. `ascii` requires exactly one
UTF-8 U+0160 and transliterates it to S in the attribution comment, then
checks that all bytes are ASCII. `scanner` replaces every `yylex` with
`flexscan`, matching Python's byte replacement. The Heirloom intermediate
is retained before flex-tmp regenerates original patched `scan.l`.
[lexers.PREPARED](lexers.PREPARED) checks patched sources and skeleton before
flex compilation; [lexers.GENERATED](lexers.GENERATED) checks all generated
parser/scanner C, parser header, ASCII input and `libl.a` at the end.

The per-tool Makefiles contain simple direct commands, with objects before
archives. Fixed configuration reflects the original Python recipe's probes
with this compiler/runtime: oyacc enables only `HAVE_PROGNAME` and empty
`__dead`; its attribute, asprintf, pledge, reallocarray, strlcpy and `-w`
probes fail. Flex enables string.h, sys/types.h, unistd.h, stdbool.h and
`STDC_HEADERS`; malloc.h fails. Its config also supplies `VERSION "2.5.11"`.
Heirloom uses `unix=1`, as in the original recipe. GNU make 3.82 must retain
its default `SHELL`: changing it disables the direct-command fast path.
There are no shell metacharacters in expanded recipe lines.

### Recorded equivalence (2026-10-06)

Both builds completed in this checkout, using the current Forth compiler:

```sh
cp -r gcc-direct/lexer-inputs/recipe-reference build-out/lexer-inputs/
python3 gcc-direct/lexers.py build-out/lexer-inputs build-out/lexers-python
python3 tests/gcc/plumbing-lexers-check.py build-out/lexers-python
```

The comparison checks prepared sources, all six generated C intermediates
(including `skel.c`), `parse.h`, ASCII input, `libl.a`, and fixed configuration
against the actual reference probe results. All bytes agree; the ordinary
five-member archive retains SHA-256
`d5a855998abc0a3bbb84a714b49d0dbf1e507910f528711b55aca16d07694212`.
The built preparation tool also matched the original patch/skeleton outputs
and rejected incorrect patch context in a targeted check.

Ten consumer cases passed, comparing generated C byte for byte as well as
stdout/stderr; oyacc's header and verbose report also match. GCC's
`c-parse.y` is prepared from `gcc/c-parse.in` using the original Makefile's
warning line and sed rules, removing ObjC blocks and C markers. The
`c-parse.in` SHA-256 is
`3bd54640653c969ea5b6673fbcf31895f94dcbf445676c913c13070bdcb5ffbb`.
Scanners use GCC 4.0.4, binutils 2.30, and the prepared flex inputs. Each pair
runs sequentially in the same directory with identical input/output names,
so `#line` filename spelling agrees. Generated C SHA-256 values:

| Consumer | SHA-256 (both builds) |
|---|---|
| gcc-c-parse | `f8e1b2f552778b15e9788614d2922dd85f5f44d0a9673912661f1bdfe6730e08` |
| gcc-gengtype | `7d88ec03bd79716e6cd9e2ea25d43e18a6e003cc3d66eaf1d98ef55679d127cf` |
| binutils-arlex | `418eff5841f2d10d9c4f05f04cebd9250e0d98039c436166abb3a1565f958ef3` |
| binutils-deflex | `1f6ab5fcc0c0aeb2d740eb2f524576eb23cc8fce5cb8f70fc0be111573d253a4` |
| binutils-syslex | `50cf8173e7f4e605805010c21d5fdbe6e7f7a57afba1772857d0c8768ba45814` |
| binutils-itbl-lex | `2a7cb89af15f7dd9e5dbff67095e8689a847998867b6ecebb46970976d1e7ea6` |
| binutils-bfin-lex | `c5601a293420671ba60dd826bd8f426ca29ebaac62443a42e15b349d0c616b17` |
| binutils-ldlex | `a66acb9cc4a829e8a21c058af8e588e1c560a66b7d496a3ed35027e732811419` |
| flex-scanner | `4cb3e1ce267d106449d734cec1a48d2b4213522f1f781c2591a918e028bd2a53` |
| heirloom-bootstrap-scanner | `48a6e083b06fcdd5c57c97c6be9ed02e7d3f5a72d6023c7b0d50bc1a9ec7e52a` |

The check retains its copied inputs, generated files, input/output hashes and
commands in `build-out/plumbing/lexer-equivalence/report.json`; `--work DIR`
selects another fresh evidence directory. It requires the project's GCC and
binutils source caches under `build-out/direct-gcc-inputs/gcc-source/` and
`build-out/stage-b-inputs/binutils-source/`.

A fresh complete stage passed the execution audit, including every prepared
and generated hash check and `flex -V` reporting 2.5.11:

```sh
python3 tests/gcc/plumbing-lexers-audit.py
```

This Linux x86-64 audit uses Landlock to deny executable access outside
`seed-forth`, `build-out/seed-cc/`, `build-out/plumbing/`, and `/tmp` (the
native driver's private copies of the verified seed). It first requires
`/bin/sh` execution to fail with permission denied, then executes kaem with
the inherited restriction. Source reads remain unrestricted. The audit
requires the same fresh package directories as a normal stage run. It is a
verification harness, not a dependency of `lexers.kaem`. Wide/EUC lex
variants and a complete GCC bootstrap are outside this stage's evidence.

Final requested checks ran once: `tools/check-links.py` passed (zero problems).
`./check-all.sh` reported 15 PASS, 1 FAIL, 0 SKIP. Its sole failure was the
unrelated i386 pnut reference helper `build-out/pnut/m2-pnut`, terminated with
"Bad system call" during `06a-pnut` in this restricted execution environment.
The amd64 pnut, direct TinyCC and handoff checks passed, as did all earlier
compiler, source/book and bootstrap checks. No pnut sources were changed.
