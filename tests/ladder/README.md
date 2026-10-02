# Generated-source closure checks

Stage 9's replay recipes historically copied **226 host-created text files,
7,097,638 bytes**, into upstream source trees. Most are configure answers
and gnulib wrapper headers. This inventory is separate from generated
parsers, scanners and tables already present in the pinned source archives.

## First three removals

These changes remove three inputs (3,168 bytes), leaving **223 fixtures,
7,094,470 bytes**. They do not replace the remaining configure answers or
close the parser-generator bootstrap cycle.

| Removed input | Original input and operation | Upstream provenance |
|---|---|---|
| Bash `signames.h` | The recipe already builds `mksignames` from `support/mksignames.c` and `support/signames.c`, then runs `./mksignames lsignames.h`. Copy its output to `signames.h` before compiling `trap.c`. | Bash 5.2.37 `Makefile.in:739–745` |
| Gawk `awklib/grcat.c` | Copy `awklib/eg/lib/grcat.c` from the pinned archive. | Gawk 5.3.1 `awklib/Makefile.in:707–709` |
| Gawk `awklib/pwcat.c` | Copy `awklib/eg/lib/pwcat.c` from the pinned archive. | Gawk 5.3.1 `awklib/Makefile.in:703–705` |

The gawk files were captured because upstream's build places links at new
paths. They were byte-for-byte duplicates of original archive members,
not generated C. The runner uses copies to avoid needing symlink support.
Bash's generated signal names depend on the chain's musl headers. The
remaining Bash `config.h` fixture is still a dependency of its generator.

The original archives and their SHA-256s are in `ladder/PACKAGES`:

- [Bash 5.2.37](https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz)
- [Gawk 5.3.1](https://ftp.gnu.org/gnu/gawk/gawk-5.3.1.tar.gz)

The regression test retains only the three old SHA-256 values, not the
removed bytes. It verifies absence from the source tree, recipe ordering,
original archive members and, when supplied chain tools, a complete fresh
replay of both packages against their unchanged `ladder/NAME/HASHES`.
Host Python supplies the independent verification harness and extracts
verified archives for that test; production extraction still belongs to
the seed-derived recipe chain.

The capture authoring tool preserves these operations too. Unchanged
regular archive members replace source-identical aliases; Bash's native
signal copy is recognized only when exactly one replayed `mksignames`
invocation wrote an identical `lsignames.h`. If that evidence is missing,
capture retains the fixture and the closure test rejects the regression.
Pure positive/negative checks exercise these rules without requiring
`strace`:

```sh
python3 tests/ladder/capture-copies-check.py
```

```sh
python3 tests/ladder/fixture-closure-check.py
python3 tests/ladder/fixture-closure-check.py --distfiles build-out/distfiles
python3 tests/ladder/fixture-closure-check.py \
  --distfiles build-out/distfiles \
  --cc build-out/pnut-amd64/gcc64/tc/bin/tcc \
  --runner build-out/amd64-runner \
  --work build-out/fixture-closure-check
```

`--work` must be new. The script never cleans a caller-supplied directory.
Without the archive/tool arguments, it explicitly reports which checks
were not run. The caller must supply seed-derived tools: accepting an
arbitrary executable pathname does not itself establish its provenance.

## Reproduce the full provenance inventory

Every remaining fixture has an upstream `Makefile.in` generation target.
This read-only audit checks every package archive against `ladder/PACKAGES`
and reports each fixture's bytes, SHA-256, original rule location,
dependencies and commands:

```sh
python3 tests/ladder/fixture-inventory.py \
  --distfiles build-out/distfiles --summary
python3 tests/ladder/fixture-inventory.py \
  --distfiles build-out/distfiles > build-out/fixture-provenance.json
```

Finding a rule is provenance evidence, not proof that its dependencies
have been removed. In particular, `config.h` targets eventually delegate
to `config.status` and configure probes. Wrapper rules substitute those
answers and include gnulib snippets. Moving the old answers into another
constant table would not close that dependency.

## Remaining order and trust boundaries

1. Finish removing acyclic duplicate/generated inputs from the current
   recipes while retaining their original executable pins.
2. Bootstrap an earlier configure-capable shell and utility set, from
   original C plus actual target checks, before production Bash and the
   gnulib-heavy tools. Ordinary configure currently needs tools whose own
   first builds consume the fixtures; rebuilding them afterward alone
   does not erase their ancestry.
3. Build a clean-lineage yacc/lex bridge and early m4 before the first
   grammar consumers. M4's interpreter is handwritten C. Bison 3.8.2 and
   flex 2.6.4 initially consume shipped generated C, including Bison's own
   grammar/scanners and flex's parser/scanner/skeleton. Their ordinary
   self-regeneration is insufficient for independent source closure.
4. Delete generated parser/scanner outputs before first compilation and
   regenerate from grammars. Stage 9 consumes Bash `y.tab.c`, gawk
   `awkgram.c` and `command.c`, and the tar/coreutils/patch date parsers.
   Later targets include findutils, bc, binutils and GCC 4.7/10 gengtype
   scanners. GCC 4.0.4's pinned git export already requires generation;
   its remaining debt is its generators' lineage.
5. The pinned Linux archive already supplies Kconfig `.l`/`.y` sources,
   and stage 12 generates their C with chain-installed tools. The
   remaining issue there is inherited generator ancestry, not a copied
   Kconfig parser fixture.

An established reference is [live-bootstrap revision
b1ceced7](https://github.com/fosslinux/live-bootstrap/tree/b1ceced7ea8a819a26f23796f6dd7ae8496a33a4):
oyacc 6.6, early Bash 2.05b, Heirloom lex, early flex and handwritten-reader
Bison passes. That is a candidate dependency lineage, **not a validated
seed-forth implementation**. Its early Bash patches target a different
libc and some reference steps carry configuration headers themselves.
Those details need review and real in-chain checks before adoption.

Executable closure and generated-source closure are separate claims.
Fixed points establish byte stability, not independent ancestry. Tarball
`configure`/`Makefile.in`, gperf/Unicode/opcode tables and documentation
are further generation classes not solved by this first removal.
