# Edition and evidence

The repository's current README is the reader gateway and can evolve with
this teaching edition. Historical README claims in these books still refer
to the pinned source revision below. An [exact copy of that README](source-edition/README-bbcc173.md.txt)
is retained as evidence; the manuscript checker verifies its original Git
blob identity rather than expecting the live gateway to remain unchanged.

## Source boundary

This teaching draft describes `delta9000/seed-forth` at commit
[`bbcc1732152af2d884737272eed870d2410ffe8e`](https://github.com/delta9000/seed-forth/tree/bbcc1732152af2d884737272eed870d2410ffe8e).
The `plumbing` branch pointed to that commit when checked on
2026-10-07. Moving upstream branches do not
silently change the edition.

The original implementation and literate book are inherited unchanged.
The teaching manuscripts live under `books/`; the repository README is
their reader gateway. There is no promise
that a checkout of `master`, a different Forth, or a later compiler profile
has the same behavior.

## Reading-route edition

The [hybrid narrative](HYBRID-NARRATIVE.md) and [route map](narrative-map.csv)
plan five capabilities: H1 Forth result, H2 simple C ELF, H3 objects/System V/
link/runtime, H4 generators/GCC/output tools, and H5 hosted closure/rebuild.
They change learning order, not the implementation pin or the 77 stable
editorial units. C19's first story can appear early under supplied contracts;
its complete implementation and the S11–S19 byte audit keep their full scope.
Existing chapter/exercise draft states do not change merely because a passage
moves onto the main route or becomes depth.

Direct GCC has its own production branch. M2/M1/hex2, pnut and private-ABI
TinyCC are useful alternate tracks, not compulsory executable ancestors.
The direct target still uses shared LP64 declaration machinery from `115`
and initializer traversal from `118`; G01 now states their profile/interface
roles, while G03/G09 now supply shared mechanism drafts alongside
the System V/object providers. Source provenance,
loaded definitions, selected providers and executed producers are distinct.

For each proposed milestone, distinguish required production inputs, supplied
but initially unopened teaching components, comparison/test controls, and
optional routes. Preview, paper derivation, observed fixture execution and
independent learner performance remain separate evidence states. The new
first-reader setup, H3 two-file fixture and H4 generator lesson are not yet
validated runnable checkpoints; this sequencing plan has no observed learning
benefit or new execution result.

## Current first-result and direct-profile entrances

[Two small results](FIRST-RESULTS.md) and its [four feedback sets](practice/first-results-solutions.md)
now supply the H1/H2 paper entrance. They keep stack state, requested output,
stored bytes and process status separate, using C19's supplied layout rather
than claiming another executed executable. A clean-start operational route
still needs its own setup, reset, capture and execution record.

[G01: A program from two files](gcc-toolchain/chapters/01-a-program-from-two-files.md)
is a complete bounded profile entrance with seven [exercise/feedback sets](gcc-toolchain/practice/01-solutions.md).
Its bounded source/practice and model-assisted prerequisite reviews are complete. The chosen profile
is LP64 + AMD64 System V + ET_REL; the final `131` call provider, runtime-aware
`start.o`, distinct C-built `startup.o`, and lazy `libseed.a` inputs remain
visible. The `0x401...` placements are illustrative, not a fixture dump.
The command card has not been executed. G02–G25 now supply the planned mechanism and toolchain paper drafts, with seven original/changed practice sets each; their new execution, independent manuscript review and reader validation remain pending.

The bounded review checked all seven original and seven changed practice
sets, 48 relevant source identities and source/local links. A model-assisted
reader-role attempt exposed header/preprocessing and hexadecimal-byte
terminology gaps; the chapter corrections were read back. This is a
prerequisite/editorial check, not independent novice validation or observed
human learning. G01 rendered-layout review, clean-start setup and all fixture
execution remain unverified.

This adds no full-definition inventory. The chapter total is 437 (95 seed,
167 C, 175 G), plus four separate entrance prompts. Source-blob checks
now cover 72 pinned project files, including the added `141-archive.fth`,
`runtime/gcc-seed/startup.c` and `runtime/gcc-seed/environment.c`. The complete
colon-definition inventory remains 579 across fourteen earlier files.

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

The first twenty-two C-volume chapters use the same exact source revision.
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
[C20](c-compiler/chapters/20-complete-compiler-and-stage-a.md) now follows the
produced executable as an M2-Planet compiler, reconstructs the exact Stage-A
recipe and bounds its observed M1-output comparison. Eight complete practice/
feedback sets exist; source/practice review and final readback are complete.
[C21](c-compiler/chapters/21-assembler-input-and-expansion.md) and
[C22](c-compiler/chapters/22-two-pass-assembly-and-bootstrap-handoff.md) now
open the complete standalone Forth assembler and bounded source-built-tool
handoff. Their 10 and 12 main practice/feedback sets passed source/practice
review. This adds no observed execution or actual-reader learning result.

The source maps assign 579 colon definitions across fourteen non-preprocessor
compiler/assembler files, all 339 declarations in `100`/`110`, and 170 control/function/
program rows: 160 declarations plus ten top-level forms in `112`/`114`/`116`/
`120`. The separate preprocessor inventory remains 57 regions/331 declarations.
The separate [pipeline map](c-compiler/pipeline-map.csv) covers 33 regions and
273 lines across five complete shell recipe files; all have teaching homes.
The [assembler ledger](c-compiler/assembler-regions.csv) separately covers
785 lines in 42 regions: 99 declarations, including its 50 colon definitions,
plus two initialization forms. The source-blob check covers 72 pinned project
files. These are distinct
source-coverage counts, not execution counts. C20 covers the standalone
Stage-A recipe and attributed result; C21/C22 cover full bounded Forth
assembly and the source-built-tool handoff. Native/private-stack, System V,
full upstream implementations, broader bootstrap lineages and later target
providers retain separate homes.

Their source inspection does not resume or reproduce a compiler build.
The canonical `tri.c` is retained as a paper example; its output character
count is derived, and historical source/executable sizes are not relabeled
as new measurements. More workspace does not change a C data model or ABI.

## Claim ledger

| Claim used in this unit | Primary evidence at the pinned revision | Evidence kind | Limit |
|---|---|---|---|
| Stack effects of `dup`, `drop`, `swap`, `+`, `*`, `/` | [`000-seed.hex0`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0), `dup_code` through `star_code` | Inspected instructions and source comments | No execution or exhaustive correctness proof |
| `[lit]`, definition phases and outer-loop lookup | Same file, `colon_code`, `semicolon_code`, `bracket_lit_code`, `parse_decimal_code`, `repl` | Inspected source | Trusted token syntax; malformed input and resource limits are not made safe by the prose |
| `@`/`!` transfer a cell; `c@`/`c!` transfer a byte | Same file, `fetch_code`, `store_code`, `cfetch_code`, `cstore_code` | Inspected instructions | Valid readable/writable address assumed |
| `here` reads the cursor; `latest` returns a sysvar address | Same file, `here_code`, `latest_code`, `sysvar_init` | Inspected source | Layout is edition-specific |
| `here-addr`, `c,`, `and`, `or` and `-` definitions | [`010-lib.fth`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth), named definitions | Inspected source, with excerpt comparisons | All 63 colon definitions are quoted and checked across S1–S10; runtime execution remains unverified |
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
| C entry through default statements, functions and process entry | `020`–`120` core modules at the pin, source-map.csv, parser-map.csv, control-map.csv, named provider contracts and the actual loader | Inspected source, matched excerpts and manual state/byte derivations | C01–C19 paper route; C19 full technical/practice manuscript review complete. C20 now supplies a separately scoped recipe/comparison account; complete optional providers remain planned; no new compiler/example execution |
| A minimal C program has a predicted 556-byte image and exit value seven | C19 fixture `int main(void){return 7;}`; exact header, stub, eager runtime, function and finalizer definitions | Manual byte/layout and conditional target-state derivation | Output-buffer prediction only; one-write delivery, loading and execution have not been observed; unrelated to original seed byte coverage or a Stage-A artifact comparison |
| The standalone Stage-A recipe compares two M1 text files | Five pinned recipe scripts; [33-region map](c-compiler/pipeline-map.csv) | Complete recipe/source inspection | Does not compare the producer ELFs, enforce a published hash/size or explain every later bootstrap implementation |
| Standalone Stage A reported equal 2,367,260-byte M1 outputs | [Run 37474668625, check job](https://github.com/delta9000/seed-forth/actions/runs/37474668625/job/112306844449), head `764bdc4f4902d613145f361da6a7f33010dd37b4`; relevant recipe blobs match the teaching pin | Observed remote execution summary | Named self-source input/profile only; no downloadable output artifacts or Stage-A SHA-256 in the available log; no execution of new teaching examples |
| Published Stage-A artifact hashes identify historical outputs | Pinned [REPRODUCIBLE.md](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/REPRODUCIBLE.md#L301-L323) | Attributed historical record | Neither newly measured hashes nor a hash oracle enforced by the Stage-A script |
| Original Fibonacci source requests 29 character bytes and returns 55 | C20 optional retrieval, original prologue source | Source-derived program trace | Assumes admitted compilation, resources and successful target writes; no new execution or Stage-A input claim |
| Complete standalone Forth assembler mechanisms | `130-asm.fth` at the pin; [42-region ledger](c-compiler/assembler-regions.csv); 50 definition spans in source-map.csv | Source/practice-reviewed explanations of all 785 lines, 99 declarations and two initialization forms | Narrow grammar and unchecked quote/number paths remain; supplied ELF envelope and output-write success are separate contracts; no new execution |
| Expansion and assembly produce seven bytes; a supplied header/fixture describes 148 | C21/C22 worked fragments, pinned M2libc header/definitions and `m1-jump42.M1` | Manual text, layout, field and byte derivations | Arbitrary fragments are not runnable ELFs; predicted target exit is conditional; no file or execution observation |
| Source-built tools have distinct handoff comparisons | Pinned `bootstrap.sh` bounded step/helper spans and named test predicates in C22 | Inspected recipes, with historical CI summaries separately attributed to head `764bdc4f4902d613145f361da6a7f33010dd37b4` | Step 5 ELF route equality, step 6 M1-text equality and step 7 tool rebuilds are different checks; neither full script coverage nor a fresh run is claimed |
| H1/H2 distinguish state, output and process result | [FIRST-RESULTS.md](FIRST-RESULTS.md), pinned seed contracts and C19 layout | Source-derived entrance traces and four separate feedback sets | No fresh setup or observed fixture execution; supplied helper length is a layout premise |
| G01 supplies a bounded direct-profile and two-object story | Pinned driver, selected `123`/`131` paths, `140` relative/absolute rules, `122` startup, `141` archive and named runtime sources | Inspected source contracts and illustrative placement arithmetic; bounded source/practice and model-assisted prerequisite reviews complete | No actual new object dump, function size, final member set or file/run result; G02–G25 now have separate paper mechanism drafts |
| The seed image is described as 1,772 bytes | ELF `p_filesz` field and annotated source; source-byte count checked in this pass | Inspected source and static calculation | An exact byte-decoded copy was inspected as data; no manual build-script run or seed execution is claimed |

## Existing results are attributed results

C20 distinguishes inspected recipes, historical output records and the named
remote Stage-A observation. The independently passed C19 publication check
at `945282917f45cebf9e04d86492e7a64ef50393a8`, [run 37478538502](https://github.com/delta9000/seed-forth/actions/runs/37478538502),
remains a canonical repository result with the scope recorded in the
[coverage ledger](COVERAGE.md#existing-ci-is-separate-evidence). It does not
establish that these new manuscript examples ran. The C21/C22 checkpoint at
`0b7b2bd3fc64f2746249ac5194abf1506328fc0e` also passed its [canonical CI run](https://github.com/delta9000/seed-forth/actions/runs/37492966101).
That result does not validate the newly planned hybrid reading order or fixtures.

The pinned [GCC driver documentation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md)
retains the reported matching stages 2, 3 and 4 for the selected set of
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

## Maintenance at the plumbing pin

The move from `7d7e1996d1753118181d43e1a413960d3a1ec24b` to this pin
updates 3,067 existing source-link occurrences across Markdown and CSV. Unchanged
files retain verified spans; changed passages are located at this revision.
The 63 library and 67 complete C excerpts compared by the checker still match;
no quoted definition in that checked set needed a text change. The new README
copy has the same original Git blob as the previous copy, which is retained.
The default checker reads source from local Git so a different working checkout
does not silently become the teaching source.

The implementation changes used by these lessons are in `040`, `050`, `060`,
`100`, `115`, `118`, `121`, `122`, `123`, `125`, `126`, `127`, `128`, `129` and
`131`, plus the new `132-cc-long-double.fth`; the Python adapter
`tools/gcc-direct-cc.py`; and runtime `stdio.c`, `include/stdio.h`, `setbuf.c`,
`process.c` and the fork policy comment in `process-api.c`. Their source-account
changes include `gcc-direct/README.md`, `book/22-the-preprocessor.md`,
`book/23-the-lexer.md`, `book/24-types-and-symbols.md`,
`book/32-main-and-bootstrap-chain.md` and `book/40-direct-gcc-target.md`.
Other inherited-book edits, such as Chapter 19's comment correction, do not
change the teaching byte model.

C05–C07 and C12–C14 now explain diagnostic mapping, `_Bool` and opaque scalar
updates. G01/G03/G06/G08–G17 explain native driver alternatives, declaration
forms, envp and C exit, spelled filenames, exact static floating constants,
typed literal suffixes/extended hexfloat, aggregate varargs, boolean bitfields,
buffered streams, floating formatting and x87 computations. Changed feedback
for G10–G13/G15 follows those contracts; the integer, binary64 and pointer
traces retain their supplied formats and inputs. The complete earlier-file
inventories now have 579 colon definitions, 339 expression/declaration names,
and 331 declarations in 57 preprocessor regions over 2,300 lines. Layer 132
has a bounded teaching account, not a new exhaustive definition inventory.

G23/G25 distinguish the native plumbing route from the historical Python A–D
recipes. The pin's [plumbing record](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/plumbing/README.md#L115-L144)
reports 376/376 coreutils cases and the other scoped tool comparisons; its
[lexer-stage audit](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/plumbing/README.md#L258-L282) records a successful
restricted execution audit, followed by 15 PASS, 1 FAIL, 0 SKIP in the final
check-all run (the restricted i386 pnut reference helper failed). Those are
attributed records, not newly reproduced results. The retained coreutils
long-double patch description predates 132; its presence is not evidence that
132 lacks computing support, nor that the recipe was rerun without the patch.
Musl `qsort.c` and `SORT.md` are unchanged: G24 keeps the attributed tie-order
diagnosis and does not invent a new sort result.

## Updating the edition

When the implementation changes, compare the relevant definitions before
changing this pin. Update all dependent contracts, excerpts, traces,
exercises, hints, answers and coverage rows together. Retain a named older
edition when readers need it. A changed source link alone is not an update.
