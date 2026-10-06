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

C01 opens the contract of `cc-main` and the main-last loader before C02 opens
the storage mechanisms. Later units must explain the preprocessing, parsing,
type, emission and finalization operations invoked by that driver. Reading a
call's name is not the same as auditing its implementation.

The inventory currently covers every colon definition in `020` and `030`.
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
ordinary walking, include storage, paths and parent restoration. It states
the macro and conditional interfaces that C04/C05 must subsequently open.
The inventory uses `drafted` for a represented region, `partial` where its
listed later interface is still pending, and `planned` for a future teaching
home. A planned manuscript path is a destination, not an available chapter.

Some source regions serve more than one mechanism. The interface notes
preserve those connections instead of pretending that a copied declaration
alone finishes its later behavior. Comments and top-level bindings belong to
the surrounding region. Definition counts and source-line coverage do not
measure learnability or runtime correctness.

## What the checks establish

The [document checker](../check.py) verifies pinned source blobs, definition
names and spans, inventory completeness for the two files above, the full
preprocessor region/declaration partition, and complete
named Forth excerpts shown in the new C chapters. It also checks local links,
exercise/solution IDs and selected paper calculations.

These checks can catch a stale snippet, missing definition or broken reference.
They cannot establish runtime behavior or that a reader can use the mechanism
independently. [Validation](../VALIDATION.md) records those distinct obligations.
The [whole-book migration map](../COVERAGE.md) keeps the later source material
visible without relabeling planned teaching as completed work.
