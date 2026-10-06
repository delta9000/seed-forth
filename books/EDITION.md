# Edition and evidence

## Source boundary

This teaching draft describes `delta9000/seed-forth` at commit
[`7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b).
The `direct-gcc-overlay` branch pointed to that commit when checked on
2026-10-06. The rewrite branch starts there; moving upstream branches do not
silently change the edition.

The original implementation and literate book are inherited unchanged.
Only paths under `books/` belong to this rewrite milestone. There is no promise
that a checkout of `master`, a different Forth, or a later compiler profile
has the same behavior.

## First-unit profile

The mechanism being described is the supplied x86-64 Linux seed. A cell holds
64 bits, memory is byte-addressed, cell loads and stores are little-endian,
and stack diagrams put the top at the right. Arithmetic keeps the low 64 bits
where specified. The seed's `/` is unsigned division, and `0=` returns either
zero or an all-ones cell. `[lit]` reads an unsigned decimal token; bare numeric
tokens are not interpreted as numbers by the seed's outer loop.

These are source-inspected contracts, not a claim that the examples were run.
The first unit is usable with pencil and paper. It assumes valid word inputs,
enough stack space and, for memory examples, a stated writable region. The
seed does not check all those preconditions for you. Hypothetical addresses in
memory exercises are paper examples, not a safe arbitrary-write recipe.

The seed's machine register layout, Linux executable loader, token reader and
native call encodings are deferred behind named interfaces. They are not
prerequisites for calculating the first three chapters' states.

## Claim ledger

| Claim used in this unit | Primary evidence at the pinned revision | Evidence kind | Limit |
|---|---|---|---|
| Stack effects of `dup`, `drop`, `swap`, `+`, `*`, `/` | [`000-seed.hex0`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0), `dup_code` through `star_code` | Inspected instructions and source comments | No execution or exhaustive correctness proof |
| `[lit]`, definition phases and outer-loop lookup | Same file, `colon_code`, `semicolon_code`, `lit_compile_code`, `parse_decimal`, `repl` | Inspected source | Trusted token syntax; malformed input and resource limits are not made safe by the prose |
| `@`/`!` transfer a cell; `c@`/`c!` transfer a byte | Same file, `fetch_code`, `store_code`, `cfetch_code`, `cstore_code` | Inspected instructions | Valid readable/writable address assumed |
| `here` reads the cursor; `latest` returns a sysvar address | Same file, `here_code`, `latest_code`, `sysvar_init` | Inspected source | Layout is edition-specific |
| `here-addr`, `c,`, `and`, `or` and `-` definitions | [`010-lib.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth), named definitions | Inspected source, with excerpt comparisons | Explains selected definitions, not the whole loaded library |
| Stack, byte and bit examples and exercise answers | Chapter and solution steps, plus document-check assertions | Derived from the stated model | An arithmetic assertion is not a seed execution |
| The seed image is described as 1,772 bytes | ELF `p_filesz` field and annotated source; source-byte count checked in this pass | Inspected source and static calculation | No seed binary was built or run in this pass |

## Existing results are attributed results

The pinned [GCC driver documentation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md)
and commit message report matching stages 2, 3 and 4 for the selected set of
54 files. A later teaching unit must explain those artifact identities,
environment controls and comparison rules before relying on that result.
This manuscript pass did not repeat that run. Matching rebuilds do not by
themselves prove that the compiler implements C correctly or that the source
is benign.

Historical Linux-chain work on a different lineage is not evidence that this
direct-GCC edition has completed the same path. The kernel volume remains
planned. Its eventual acceptance record must identify the inputs, toolchain,
kernel image and observed behavior, and distinguish entering a kernel from
starting userspace.

## Updating the edition

When the implementation changes, compare the relevant definitions before
changing this pin. Update all dependent contracts, excerpts, traces,
exercises, hints, answers and coverage rows together. Retain a named older
edition when readers need it. A changed source link alone is not an update.
