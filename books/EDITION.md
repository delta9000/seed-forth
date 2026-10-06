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

## First-volume profile

The mechanism being described is the supplied x86-64 Linux seed. A cell holds
64 bits, memory is byte-addressed, cell loads and stores are little-endian,
and stack diagrams put the top at the right. Arithmetic keeps the low 64 bits
where specified. The seed's `/` is unsigned division, and `0=` returns either
zero or an all-ones cell. `[lit]` reads an unsigned decimal token; bare numeric
tokens are not interpreted as numbers by the seed's outer loop.

These are source-inspected contracts, not a claim that the examples were run.
The first volume is usable with pencil and paper. It assumes valid word inputs,
enough stack space and, for memory examples, a stated writable region. The
seed does not check all those preconditions for you. Hypothetical addresses in
memory exercises are paper examples, not a safe arbitrary-write recipe.

The complete seed-byte audit is drafted. S11 opens the executable layout
and stated loader contract; S12–S18 open every primitive body and helper,
including dictionary/input, native compilation and the outer loop. S19 joins
them in a predicted new definition. Chapters 4 and 8–10 open the call/return, dictionary,
input and emission contracts needed for the library-level mechanisms. They are not
prerequisites for calculating the first three chapters' states.

## Compiler-volume entrance

The first nineteen C-volume chapters use the same exact source revision.
[C01](c-compiler/chapters/01-compiler-entry-and-profile.md) distinguishes the
legacy direct-ELF builder from the separate generated program and from the
optional TinyCC/System V profiles. [C02](c-compiler/chapters/02-buffers-arenas-and-failure.md)
opens both infrastructure files, including selectable workspace contracts.
[C03](c-compiler/chapters/03-preprocessing-regions-and-includes.md) opens
regions, sinks, literal includes, paths and input lifetimes.
[C04](c-compiler/chapters/04-macro-expansion-and-rescanning.md) and
[C05](c-compiler/chapters/05-conditionals-and-profile-extensions.md) complete
the preprocessor mechanisms, including the separate direct/location/workspace
gates. C06 opens tokens/lookahead, C07 type/descriptor representations and C08
name/scope records. C09–C11 open the executable envelope, encoders, calls,
patch resolution and legacy runtime. C12–C15 open places/values, operator
parsing, full expressions and constant evaluation, then declaration construction.
C16–C18 now integrate conditions/loops, switches/labels and fixed legacy
function frames. C19 now explains translation-unit forms, process entry and
the final driver. Its complete small-program story derives a 556-byte buffer
and a conditional exit-value trace, then its reference sessions open enums,
typedefs, prototypes, global storage, runtime registration and final checks.
C19's full technical/practice manuscript review is complete.

The source maps assign 526 colon definitions across thirteen non-preprocessor
compiler files, all 333 declarations in `100`/`110`, and 170 control/function/
program rows: 160 declarations plus ten top-level forms in `112`/`114`/`116`/
`120`. The separate preprocessor inventory remains 57 regions/325 declarations.
These are source-coverage units, not execution counts. Full native/private-stack,
System V and other target providers retain separate homes. C20 retains actual
artifact/build/Stage-A comparisons; a source-complete default driver account
does not complete those evidence obligations.

Their source inspection does not resume or reproduce a compiler build.
The canonical `tri.c` is retained as a paper example; its output character
count is derived, and historical source/executable sizes are not relabeled
as new measurements. More workspace does not change a C data model or ABI.

## Claim ledger

| Claim used in this unit | Primary evidence at the pinned revision | Evidence kind | Limit |
|---|---|---|---|
| Stack effects of `dup`, `drop`, `swap`, `+`, `*`, `/` | [`000-seed.hex0`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0), `dup_code` through `star_code` | Inspected instructions and source comments | No execution or exhaustive correctness proof |
| `[lit]`, definition phases and outer-loop lookup | Same file, `colon_code`, `semicolon_code`, `bracket_lit_code`, `parse_decimal_code`, `repl` | Inspected source | Trusted token syntax; malformed input and resource limits are not made safe by the prose |
| `@`/`!` transfer a cell; `c@`/`c!` transfer a byte | Same file, `fetch_code`, `store_code`, `cfetch_code`, `cstore_code` | Inspected instructions | Valid readable/writable address assumed |
| `here` reads the cursor; `latest` returns a sysvar address | Same file, `here_code`, `latest_code`, `sysvar_init` | Inspected source | Layout is edition-specific |
| `here-addr`, `c,`, `and`, `or` and `-` definitions | [`010-lib.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth), named definitions | Inspected source, with excerpt comparisons | All 63 colon definitions are quoted and checked across S1–S10; runtime execution remains unverified |
| Return-stack borrowing and helper-call boundary | `000-seed.hex0`, `to_r_code`, `r_from_code`, `r_at_code`; `010-lib.fth`, `over` and shufflers | Inspected source and derived two-stack traces | Word-boundary pictures omit each completed primitive call's short-lived return destination unless explicitly shown |
| Equality, sign extraction, bounded order and ASCII byte classes | `010-lib.fth`, `=`, `0<`, `<`, `digit?`, `alpha?`, `space?` | Inspected source and domain derivations | Shared signed-order safe domain is narrower than all cell pairs; character scope is the named byte sets |
| Cell updates and four/eight-byte writers | `010-lib.fth`, `+!`, `-!`, `,4`, `,8` | Inspected source and derived stack/memory/byte traces | Valid non-aliasing storage assumed; four-byte output truncates a wider input |
| Linux wrapper arguments and returned progress/errors | `000-seed.hex0`, `syscall6_code`, `emit_code`, `key_code`; `010-lib.fth`, `open`, `read`, `write`, `close`, `die` | Inspected implementation plus linked Linux interface documentation | Single raw calls; no invented retry, complete-transfer or safe-input guarantees |
| Created words and immediate phase selection | `000-seed.hex0`, dictionary/STATE/literal routines; `010-lib.fth`, `immediate`, push-body helpers, `constant`, `call,`, character words | Inspected source and derived layout/phase traces | Minimal ISA contracts are opened before the full machine-code audit; encodable displacements and valid storage assumed |
| Branch fixups and the countdown body | `010-lib.fth`, nine control-flow combinators; `000-seed.hex0`, branch primitives | Source-matched definitions and manual C/D/R traces | The 50-byte countdown is a derived body, not an executed compiled artifact |
| Named data, deferred binding and byte-sequence capstone | `010-lib.fth`, `allot` through `bytes-eq` | Inspected source and derived lifetime/stack/memory traces | Bounded lengths, owned storage, valid bound execution tokens and timely copying of borrowed TIB data assumed |
| All seed file bytes: headers, startup, primitive bodies and helpers | `000-seed.hex0`, S11–S18 regions enumerated in the byte ledger | Source-matched byte listings, GNU readelf/objdump 2.44 static decoding and manual state traces | All 1,772 bytes have drafted explanations: 120 ELF bytes, 421 dictionary-header bytes and 1,231 native-instruction bytes; coverage is not a correctness proof |
| A complete new `inc` definition | S19 capstone, using the inspected dictionary/compiler contracts | Predicted 32-byte entry, independently reconstructed by the document checker | Generated process-memory bytes, not an observed artifact or extra seed file bytes |
| Stack, byte and bit examples and exercise answers | Chapter and solution steps, plus document-check assertions | Derived from the stated model | An arithmetic assertion is not a seed execution |
| C entry through default statements, functions and process entry | `020`–`120` core modules at the pin, source-map.csv, parser-map.csv, control-map.csv, named provider contracts and the actual loader | Inspected source, matched excerpts and manual state/byte derivations | C01–C19 paper route; C19 full technical/practice manuscript review complete. Complete optional providers and C20 artifact comparisons remain planned; no new compiler/example execution |
| A minimal C program has a predicted 556-byte image and exit value seven | C19 fixture `int main(void){return 7;}`; exact header, stub, eager runtime, function and finalizer definitions | Manual byte/layout and conditional target-state derivation | Output-buffer prediction only; one-write delivery, loading and execution have not been observed; unrelated to original seed byte coverage or a Stage-A artifact comparison |
| The seed image is described as 1,772 bytes | ELF `p_filesz` field and annotated source; source-byte count checked in this pass | Inspected source and static calculation | An exact byte-decoded copy was inspected as data; no manual build-script run or seed execution is claimed |

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
