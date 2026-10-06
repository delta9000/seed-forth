# C compiler source map

The [definition inventory](source-map.csv) provides precise navigation from
this teaching draft to the implementation at
[`7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b).
Each row names a source file, its Git blob identity, a Forth definition, its
line span and its teaching owner. Line numbers are locators within that
immutable file, not an edition identifier by themselves.

## Current coverage

| Source | Definitions mapped | Teaching owner | Other state explained alongside them |
|---|---:|---|---|
| `020-cc-arena.fth` | 6 | [C02](chapters/02-buffers-arenas-and-failure.md) | Eight-cell lexer state, diagnostic strings/digits, dictionary arena and selected arena state |
| `030-cc-io.fth` | 29 | [C02](chapters/02-buffers-arenas-and-failure.md) | Default and selected buffers, read scratch state, cursor/length cells, name-lookup scratch and optional workspace policy |
| `050-cc-lex.fth` | 39 | [C06](chapters/06-tokens-and-lookahead.md) | Token kinds, keyword/punctuation tables, borrowed spelling, current-record validity and snapshots |
| `060-cc-types.fth` | 52 | [C07](chapters/07-types-and-stable-descriptors.md) | Type/profile flags, suffix state, aggregate headers, movable field tables and named provider interfaces |
| `070-cc-sym.fth` | 19 | [C08](chapters/08-names-and-lexical-scope.md) | Ten parallel columns, symbol kinds, qualifier metadata, deferred lookup/fixup hooks and scope counts |
| `080-cc-elf.fth` | 3 | [C09](chapters/09-instructions-inside-an-executable.md) | File/target coordinates, every ELF field and bounded size finalization |
| `090-cc-emit.fth` | 119 | [C09](chapters/09-instructions-inside-an-executable.md), [C10](chapters/10-calls-literals-and-deferred-addresses.md), [C11](chapters/11-a-bounded-legacy-runtime.md) | Encoder families/hooks, function and global fixups, data/BSS storage and all legacy runtime bodies |

C01 opens the contract of `cc-main` and the main-last loader before C02 opens
the storage mechanisms. C03–C08 open preprocessing, lexing, type storage and name visibility. C09–C11
open emission/finalization and the bounded runtime. Later units still must
explain the complete parsing, declaration, statement and function flows
invoked by the driver. Reading a
call's name is not the same as auditing its implementation.

The inventory currently covers all 267 colon definitions in `020`, `030`,
`050`, `060`, `070`, `080` and `090`.
It does not yet claim a complete word inventory for all compiler layers.
Small accessors may share one explanation; substantial state transitions get
worked examples. Definitions need not be copied in full into the prose to
have an explanatory home.

## Preprocessor regions and deliberate deferrals

The [preprocessor region inventory](preprocessor-regions.csv) partitions all
2,256 lines of `040-cc-prep.fth` into 57 contiguous regions and accounts for
325 declared words, constants, variables, buffers and deferred entries.
Its primary teaching homes are C03, C04 and C05. This is a separate source-line
partition, not a machine-code byte audit.

[C03](chapters/03-preprocessing-regions-and-includes.md) opens regions, sinks,
ordinary walking, include storage, paths and parent restoration. [C04](chapters/04-macro-expansion-and-rescanning.md) opens macro records,
argument storage and rescanning; [C05](chapters/05-conditionals-and-profile-extensions.md)
opens conditional, computed-include and location/profile mechanisms.
All fifty-seven regions now have drafted explanatory homes. C06 subsequently opens the lexer interface. The expression evaluator and
later target providers retain explicitly named implementation homes; their
remaining internals are not completed by calling them from this layer.
The inventory vocabulary is `drafted` for a represented region, `partial`
where a listed teaching interface is still pending, and `planned` for a future
home. These are manuscript states, not execution or correctness results.

Some source regions serve more than one mechanism. The interface notes
preserve those connections instead of pretending that a copied declaration
alone finishes its later behavior. Comments and top-level bindings belong to
the surrounding region. Definition counts and source-line coverage do not
measure learnability or runtime correctness.

## Executable, emission and runtime ownership

The [emission inventory](emission-map.csv) assigns all 150 named declarations
in `080` and `090`, including the non-colon storage/policy/hook names. C09 owns
93, C10 owns 41 and C11 owns 16. These source declaration counts are distinct
from emitted instruction bytes or generated runtime names: sixteen runtime
emitters supply nineteen names.

The C10 explanations also open selected patch consumers in `112`, `114` and
`116`, so a deferred-address promise has a complete local resolution trace.
That does not claim those whole parser/control/function modules are already
rewritten. Their remaining mechanisms retain later teaching homes.

## What the checks establish

The [document checker](../check.py) verifies pinned source blobs, definition
names and spans, inventory completeness for the seven files above, the full
preprocessor region/declaration partition, the emission declaration inventory,
and complete
named Forth excerpts shown in the new C chapters. It also checks local links,
exercise/solution IDs and selected paper calculations.

These checks can catch a stale snippet, missing definition or broken reference.
They cannot establish runtime behavior or that a reader can use the mechanism
independently. [Validation](../VALIDATION.md) records those distinct obligations.
The [whole-book migration map](../COVERAGE.md) keeps the later source material
visible without relabeling planned teaching as completed work.
