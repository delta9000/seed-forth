# Compiler and assembler source map

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
| `100-cc-expr.fth` | 142 | [C10](chapters/10-calls-literals-and-deferred-addresses.md), [C12](chapters/12-places-values-and-delayed-loads.md)–[C14](chapters/14-expressions-and-constant-evaluation.md) | Nine-cell metadata, grammar recursion, operator tables, store/call/type hooks and immediate evaluation |
| `110-cc-decl.fth` | 35 | [C14](chapters/14-expressions-and-constant-evaluation.md), [C15](chapters/15-declarations-and-recursive-records.md) | Type-query handshake, declaration prefixes, recursive descriptors, local/storage state and bounded return/switch helpers |
| `112-cc-stmt.fth` | 45 | [C16](chapters/16-conditions-and-loops.md), [C17](chapters/17-switches-labels-and-nonlocal-control.md) | Recursive statement dispatch, loop/token state, switch selection and cleanup, label storage and goto completion |
| `114-cc-func.fth` | 7 | [C18](chapters/18-functions-and-call-frame-accounting.md) | Function registration, copied parameters, fixed frames, body parsing and explicit/fallback return paths |
| `116-cc-prog.fth` | 29 | [C19](chapters/19-translation-units-and-process-entry.md) | File-scope products, prototypes, entry/runtime ordering, deferred-use closure, global placement and entry patch |
| `117-cc-native-program.fth` | 5 | [C23](chapters/23-the-direct-tinycc-profile.md) | Private parameters and definitions, the two-call entry stub, runtime hook and program order |
| `118-cc-native-init.fth` | 30 | [C24](chapters/24-tinycc-initialization-runtime-and-closure.md) | Recursive initializer frames, inference scan, static routines and their queue, local zeroing, string copies and target hooks |
| `119-cc-native-runtime.fth` | 6 | [C24](chapters/24-tinycc-initialization-runtime-and-closure.md) (bodies counted in [C23](chapters/23-the-direct-tinycc-profile.md)) | Thirteen kernel bodies, error normalization, pre-registered result types and three fail-closed bodies |
| `120-cc-main.fth` | 1 | [C19](chapters/19-translation-units-and-process-entry.md) | Output-path bytes, driver ordering and the final executing form |
| `130-asm.fth` | 50 | [C21](chapters/21-assembler-input-and-expansion.md), [C22](chapters/22-two-pass-assembly-and-bootstrap-handoff.md) | Standalone buffers/cursor, one-pass definitions and strings, numeric/label fields, two-pass accounting and output |

C01 opens the contract of `cc-main` and the main-last loader before C02 opens
the storage mechanisms. C03–C08 open preprocessing, lexing, type storage and name visibility. C09–C11
open emission/finalization and the bounded runtime. C12–C15 open expression
and declaration mechanisms. C16–C19 join statements, functions and the
top-level driver into a complete source-derived program trace. C20 explains
the actual compiler/Stage-A artifact recipe and reads an identified comparison
record. C23/C24 open the private TinyCC program, initializer and runtime files
`117`–`119`. Reading a call's
name is not the same as auditing its implementation.

The inventory currently covers all 617 colon definitions in `020`, `030`,
`050`, `060`, `070`, `080`, `090`, `100`, `110`, `112`, `114`, `116`, `117`,
`118`, `119`, `120` and `130`.
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
All fifty-seven regions now have drafted explanatory homes. C06 subsequently opens the lexer interface. C14 now opens the expression evaluator and its reader restoration. Later
target providers retain explicitly named implementation homes; their remaining
internals are not completed by calling them from this layer.
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
C16–C19 now supply the remaining explanations within those four control,
function and program source files. Their optional providers in other files
still retain later teaching homes.

## Expression and declaration ownership

The [parser inventory](parser-map.csv) assigns all 333 named declarations in
`100` and `110`: 177 colon definitions, 74 variables, 60 deferred entries,
20 constants and two created buffers. Primary homes are C10 for six names,
C12 for 78, C13 for 57, C14 for 135 and C15 for 57. Cross-mechanism notes keep
shared uses visible without counting one declaration several times.

C10 already opens call-pop and string-emission helpers; C12 explains places
and metadata; C13 owns operator tables and precedence; C14 closes grammar,
stores, immediate evaluation and the cross-file cast/type-query handshake.
C15 constructs declarations and opens the local switch/return helpers. Their
complete use inside statements and frames is explained in C17/C18.

A named provider's caller/default is distinct from its later full optional
implementation. The inventory's current home does not claim that all native
provider source files or complete control/function paths have been rewritten.

## Statements, frames and program completion

The [control and program inventory](control-map.csv) assigns all 160 named
declarations in `112`, `114`, `116` and `120`: 82 colon definitions, 32
variables, 40 created objects, five constants and one deferred entry. Ten
additional rows explain eight initialization forms, the statement-dispatch
binding and the final driver invocation. Each row records its state owner,
purpose, exact source span and teaching section. Primary row counts are C16:
25, C17: 53, C18: 12 and C19: 80.

The 170 rows are an annotation aid, not 170 separate lessons. A created table
and its data-initialization row may refer to overlapping source lines; this is
not a disjoint line partition. `taught` in this ledger means that an explanatory
home exists in the paper manuscript, not that reader learning or execution
has been demonstrated. The [unit record](DRAFTS.md) tracks independent review
separately.

C16 explains the distinct continue destinations and full-token restoration
needed for step replay. C17 separates emitted case order from selector order,
then follows saves across switch, loop and label exits. C18 joins names and
parameters to target frames. C19 connects file-scope metadata and storage to
entry, finalization and the output attempt. The local native branches are
explained where they appear; complete alternative function/call providers
remain later units.

## Complete recipes and their acceptance conditions

The [pipeline region inventory](pipeline-map.csv) covers all 273 lines of five
scripts in 33 contiguous regions: `stage-a-check.sh`, the monolith builder,
the reference builder, `compiler-layers.sh` and `build.sh`. These are shell
recipe regions, not additional Forth definitions. Each row separates inputs,
outputs, the acting process, an acceptance condition and the claim's limits.
Comments/setup are included in the partition; a comment does not itself
establish an observed result.

[C20](chapters/20-complete-compiler-and-stage-a.md) gives each region an
explanatory home. Its first reading follows two executable producers into the
two M1 text files compared by Stage A. Later sections open the three different
input lists, file wrapper and namespace fallback, reference dependencies,
source identities, failure classifications and the distinct later comparison
pairs. The row state `taught` means represented in the manuscript; run evidence
is kept separately in the chapter's identified CI account.

This companion does not claim to teach the entire upstream M2-Planet compiler,
bootstrap implementation, assembler or downstream GCC/Linux route. Their
current use as named inputs or contextual evidence does not replace the later
mechanism chapters.

## The standalone assembler

The [assembler region inventory](assembler-regions.csv) partitions all 785
lines of `130-asm.fth` into 42 contiguous regions. It accounts separately for
99 declarations (50 colon definitions, 34 variables, eight created objects and
seven constants) and two initialization forms. C21 owns 56 declarations and
C22 owns 43; the shared source file is not silently counted as a compiler layer.
It runs in a fresh seed process with `010-lib.fth` and an explicit caller
invocation.

The primary teaching story follows one 35-byte expansion into seven output
bytes. Later sessions explain each local mechanism, then identify the supplied
ELF envelope and exact assembler/handoff comparisons. Region notes distinguish
raw source ownership, expanded-token ownership, target-address counts, output
bytes and recorded evidence. All heading homes and related section links are
checked against the actual prose. These are represented mechanisms, not a
claim that any new assembler example has run or that every possible input is
accepted correctly.

## What the checks establish

The [document checker](../check.py) verifies pinned source blobs, definition
names and spans, inventory completeness for the seventeen files above, the full
preprocessor region/declaration partition, emission, parser and control/program declaration
inventories, the five-script and standalone-assembler region partitions,
bounded source-line locators, and complete
named Forth excerpts shown in the new C chapters. It also checks local links,
exercise/solution IDs and selected paper calculations.

These checks can catch a stale snippet, missing definition or broken reference.
They cannot establish runtime behavior or that a reader can use the mechanism
independently. [Validation](../VALIDATION.md) records those distinct obligations.
The [whole-book migration map](../COVERAGE.md) keeps the later source material
visible without relabeling planned teaching as completed work.
