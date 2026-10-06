# Learning path

## Reader and purpose

The starting reader can perform ordinary integer arithmetic and follow a short
program one step at a time. No Forth, assembly, operating-system or compiler
knowledge is assumed. Programming experience is helpful but does not stand in
for knowledge of stack notation or addresses.

The first unit has a concrete outcome: explain how a small vocabulary can
transform values and write bytes, while keeping the data stack and memory
state straight. Later units reuse those capabilities to explain the
library, its control-flow words and finally the machine code that implements
the seed. The complete first-volume paper route is drafted; the operational
setup, execution and reader-validation obligations remain explicit.

## First-unit dependency graph

Read each arrow as “needed before,” not “executes before.”

```text
ordinary integer arithmetic
  -> S1: cell values, top-right stack notation, explicit literals
       -> S1: word contracts, left-to-right execution, composition
            -> S2: address/value distinction, byte/cell access
                 -> S2: cursor indirection and the c, invariant
            -> S3: bit patterns, nand and boolean masks
                 -> S3: modular negation and operand-ordered subtraction
```

S2 precedes S3 in the reading route because it gives a tangible use for the
stack model and a break from pure arithmetic. S3 needs S1, not an unmentioned
memory trick. This is a conceptual graph; the source begins with `here-addr`
and `c,` for library load-order reasons.

| Unit | Observable outcome | Assumed or taught first | Practice and feedback |
|---|---|---|---|
| [Start here](seed-forth/chapters/00-start-here.md) | Pick a route and tell a predicted state from an observed run | Ordinary arithmetic; no tool installation | Three route questions and recoverable starting point |
| [S1 Values and words](seed-forth/chapters/01-values-and-words.md) | Trace a defined word and diagnose operand-order or stack-depth errors | Cells and notation taught in S1 | S1 exercises, [feedback](seed-forth/practice/01-solutions.md) |
| [S2 Addresses and bytes](seed-forth/chapters/02-addresses-and-bytes.md) | Trace `c,` across the stack, memory and HERE cell | S1 stack operations; addresses and byte order taught before use | S2 exercises, [feedback](seed-forth/practice/02-solutions.md) |
| [S3 Bits and subtraction](seed-forth/chapters/03-bits-and-subtraction.md) | Derive `and`, `or` and subtraction; distinguish truth from a mask | S1 composition; binary and wraparound refreshed locally | S3 exercises, [feedback](seed-forth/practice/03-solutions.md) |
| [Return check](seed-forth/practice/return-check.md) | Select and apply the right contract after intervening material | S1–S3 | Mixed prompts with separate answer section |


## Second-unit dependency graph

```text
S1 + S3 -> S4: two stacks, balanced borrowing, reusable shuffles
S3 + S4 -> S5: comparisons and character classes, including space?
S2 + S3 + S4 -> S6: read-modify-write helpers and multi-byte writers
```

The XOR extension in S4 uses S3's bit operations; it is not a hidden new
prerequisite. The character-class combinations in S5 use `over`, so the
shuffle mechanism must precede them even though some simpler predicates do
not need it. S6's exact byte-width work builds on S2 rather than reopening
addresses without warning.

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [S4 Return stack and shuffles](seed-forth/chapters/04-return-stack-and-shuffles.md) | Trace temporary borrowing, helper-call boundaries and reusable shuffles | S4 exercises, [feedback](seed-forth/practice/04-solutions.md) |
| [S5 Comparisons and characters](seed-forth/chapters/05-comparisons-and-characters.md) | Explain equality, bounded signed order and byte-range classification | S5 exercises, [feedback](seed-forth/practice/05-solutions.md) |
| [S6 Memory updates and writers](seed-forth/chapters/06-memory-updates-and-writers.md) | Trace a cell update and four/eight-byte emission with truncation limits | S6 exercises, [feedback](seed-forth/practice/06-solutions.md) |
| [Second return check](seed-forth/practice/return-check-2.md) | Select the right stack, comparison or memory contract without a chapter-specific cue | Four mixed prompts with separate answers |


## Library-completion dependency graph

```text
S2 + S3 + S4 + S5 -> S7: Linux I/O and raw error/progress contracts
S2 + S6 -> S8: local dictionary/ISA bridge and definition phases
S3 + S4 + S6 + S8 -> S9: immediate control flow and balanced early return
S2 + S4 + S5 + S6 + S8 + S9 -> S10: storage, deferred dispatch and byte sequences
```

S7 uses the sign-test contract from S5 to describe raw negative results and
S4's call-state distinction. S8 teaches the small dictionary and instruction
interfaces it needs locally; it does not require the later full byte audit.
S9 needs return-stack discipline before an early exit can be safe. S10 names
the increment/decrement helpers before its token and byte loops use them.

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [S7 Linux I/O](seed-forth/chapters/07-linux-io-contracts.md) | Trace syscall arguments and distinguish a return value from complete requested work | S7 exercises, [feedback](seed-forth/practice/07-solutions.md) |
| [S8 Definition phases](seed-forth/chapters/08-defining-words-and-phases.md) | Explain a created word's layout and distinguish its three relevant times | S8 exercises, [feedback](seed-forth/practice/08-solutions.md) |
| [S9 Control-flow patching](seed-forth/chapters/09-control-flow-by-patching.md) | Trace emitted slots, fixups and runtime branch paths separately | S9 exercises, [feedback](seed-forth/practice/09-solutions.md) |
| [S10 Storage and byte sequences](seed-forth/chapters/10-storage-deferred-words-and-bytes.md) | Build a small library-level artifact while accounting for storage and binding lifetimes | S10 exercises, [feedback](seed-forth/practice/10-solutions.md) |
| [Third return check](seed-forth/practice/return-check-3.md) | Select the relevant phase, lifetime or progress contract without a chapter-specific cue | Four mixed questions with separate answers |


## First machine-code audit dependencies

```text
S2 + S6 + S8 -> S11: file mapping, instruction key, headers and startup
S4 + S11 -> S12: cached-top invariant and physical stack/memory primitives
S3 + S5 + S12 -> S13: arithmetic instructions and width-specific boundaries
```

The early contracts now become audit targets. The source's execution order
still does not dictate the learning order: knowing the stack invariant first
lets each primitive become a small preservation argument. The
[byte ledger](seed-forth/AUDIT.md) counts the exact regions covered, with
header ownership kept separate from earlier primitive-body explanations.

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [S11 Executable and entry](seed-forth/chapters/11-executable-and-entry.md) | Decode the headers and startup, separating file positions, virtual memory and physical allocation | S11 exercises, [feedback](seed-forth/practice/11-solutions.md) |
| [S12 Physical stacks and memory](seed-forth/chapters/12-physical-stacks-and-memory.md) | Reconstruct logical values and prove each shown transition preserves the stated representation invariant | S12 exercises, [feedback](seed-forth/practice/12-solutions.md) |
| [S13 Arithmetic instruction bytes](seed-forth/chapters/13-arithmetic-in-instruction-bytes.md) | Explain each arithmetic result from actual instruction and register widths | S13 exercises, [feedback](seed-forth/practice/13-solutions.md) |
| [Fourth return check](seed-forth/practice/return-check-4.md) | Diagnose mapping, live-region, register-width and truncation mistakes | Four mixed questions with separate answers |


## I/O, dictionary, and compiler audit dependencies

```text
S7 + S12 + S13 -> S14: physical syscall and exit bodies
S8 + S10 + S12 + S14 -> S15: headers, lookup, token input and errors
S8 + S9 + S10 + S13 + S15 -> S16: native definition and literal compiler
```

S15 needs the borrowed-token lifetime taught in S10, not just byte decoding.
S16 uses phase separation and physical register-width rules before opening
the compiler. Its numeric parser and the outer loop remain named interfaces
for S18; that deferral is not a circular prerequisite.

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [S14 Physical I/O and exit](seed-forth/chapters/14-physical-io-and-exit.md) | Audit the exact register/stack boundary and distinguish successful input from stale scratch data | S14 exercises, [feedback](seed-forth/practice/14-solutions.md) |
| [S15 Dictionary and input](seed-forth/chapters/15-dictionary-and-token-input.md) | Reconstruct every initial header and trace lookup, token lifetime and failure paths | S15 exercises, [feedback](seed-forth/practice/15-solutions.md) |
| [S16 Native colon compiler](seed-forth/chapters/16-native-colon-compiler.md) | Derive a created entry while preserving compiler data and inline-literal return ownership | S16 exercises, [feedback](seed-forth/practice/16-solutions.md) |
| [Fifth return check](seed-forth/practice/return-check-5.md) | Select the right input, identity, phase or boundary contract | Four mixed questions with separate answers |

## Closing-audit dependencies

```text
S9 + S12 + S13 + S16 -> S17: inline branch targets and return ownership
S13 + S14 + S15 + S16 + S17 -> S18: decimal parsing and outer dispatch
S11 through S18 -> S19: complete seed ledger and integrated new-entry capstone
```

S17 uses S13's full-width test and flag discipline after physical stack
cleanup. S18 joins the input, error, phase and return contracts instead of
assuming that a token automatically means a number. S19 integrates existing
mechanisms; its predicted runtime entry is not an additional region of the
seed file.

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [S17 Inline branch operands](seed-forth/chapters/17-inline-branch-operands.md) | Track both paths of a conditional branch without confusing target cells and saved return addresses | S17 exercises, [feedback](seed-forth/practice/17-solutions.md) |
| [S18 Decimal parser and REPL](seed-forth/chapters/18-decimal-parser-and-repl.md) | Explain conversion, overflow limits, lookup and phase dispatch for a complete input sequence | S18 exercises, [feedback](seed-forth/practice/18-solutions.md) |
| [S19 Audit synthesis and capstone](seed-forth/chapters/19-audit-synthesis-and-capstone.md) | Derive a new dictionary entry and relate a runtime trace to the exact byte ledger | S19 exercises, [feedback](seed-forth/practice/19-solutions.md) |
| [Sixth return check](seed-forth/practice/return-check-6.md) | Select the correct branch, parser, layout and evidence contract without a topic cue | Four mixed questions with separate answers |
| [Reference and recovery routes](seed-forth/REFERENCE.md) | Find a primitive contract or repair a specific missing prerequisite | All 32 primitive cards, memory map and library navigation |

## Interfaces opened in stages

| Interface | Initial contract | Later explanation and remaining audit |
|---|---|---|
| `: name ... ;` | Define a word from the stated sequence, using the explicit literal syntax | S8 opens the phases; S15–S16 now audit headers and native compilation; S18 completes outer-loop dispatch and numeric parsing |
| A data stack | Words consume and produce the documented topmost cells | S4 separates data and return stacks; S12 now audits the cached-top representation and primitive bodies |
| `@ ! c@ c!` | Access the stated valid memory location with the stated width | S11 states the mapping contract and S12 audits access encodings; operating-system internals remain trusted |
| `here` / `latest` | Their distinct value/address contracts at this pinned seed | S11 opens startup and mapping; S15 now audits dictionary and token input |

These interfaces reduce prerequisites without hiding a proof obligation. The
first unit asks what follows if the contracts hold; later chapters open the
needed mechanisms in stages, and the full audit asks how every relevant
source instruction realizes them. Source links are available now for readers who want
that second question early, but exercises do not require solving it early.

## C-volume entry and representation units

The [compiler volume](c-compiler/README.md) offers a contract-based entrance.
C01 teaches the C syntax it uses and checks four small Forth contracts; it
does not require memorizing S19 or reading every seed-audit chapter first.
C02 supplies a local reading key for shuffles, temporary return storage,
branch/loop syntax, bounded comparisons, I/O and deferred behavior, with
short links to the corresponding seed explanations when needed.

```text
local Forth contract bridge -> C01: C example, chosen profile, builder/target
C01 + C02's local library-contract bridge -> C02: buffers, arena, ownership
C02 -> C03: active regions, output sinks and nested include lifetimes
C03 -> C04: macro records, arguments and rescans
C03 + C04 + local evaluator/profile contracts -> C05: conditionals and extensions
C05 -> C06: token records and reversible lookahead
C02 + local type/bit contracts -> C07: type identity and stable descriptors
C02 + C06 + C07 -> C08: names, reusable symbols and scope visibility
C02 + C07 + local instruction/ELF bridge -> C09: executable byte encodings
C02 + C06 + C07 + C08 + C09 -> C10: calls, literals and delayed addresses
C09 + C10 + local Linux request/result contract -> C11: bounded legacy runtime
```

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [C01 Compiler entry and profile](c-compiler/chapters/01-compiler-entry-and-profile.md) | Derive the recurring C program and separate source, builder, image and generated execution | Five exercises and [feedback](c-compiler/practice/01-solutions.md) |
| [C02 Buffers, arenas, and failure](c-compiler/chapters/02-buffers-arenas-and-failure.md) | Account for cursor, capacity, storage lifetime and I/O evidence at each boundary | Five exercises and [feedback](c-compiler/practice/02-solutions.md) |
| [C03 Preprocessing regions and includes](c-compiler/chapters/03-preprocessing-regions-and-includes.md) | Trace changing input owners into one persistent output sink | Five exercises and [feedback](c-compiler/practice/03-solutions.md) |
| [C mixed return check](c-compiler/practice/return-check.md) | Choose the right ownership, capacity, profile or evidence contract without a chapter-specific cue | Four mixed questions, hints and separate answers |
| [C04 Macro expansion and rescanning](c-compiler/chapters/04-macro-expansion-and-rescanning.md) | Reconstruct definition recipes and preserve raw/expanded arguments through rescan and suppression boundaries | Five exercises and [feedback](c-compiler/practice/04-solutions.md) |
| [C05 Conditional preprocessing and profiles](c-compiler/chapters/05-conditionals-and-profile-extensions.md) | Trace group decisions and separate computed includes, logical locations and profile selection | Six exercises and [feedback](c-compiler/practice/05-solutions.md) |
| [Second C mixed check](c-compiler/practice/return-check-2.md) | Choose the relevant lifetime, membership, conditional or provenance state | Four mixed questions, hints and separate answers |
| [C06 Tokens and lookahead](c-compiler/chapters/06-tokens-and-lookahead.md) | Trace kind-dependent payloads, borrowed spelling and exact snapshot boundaries | Seven exercises and [feedback](c-compiler/practice/06-solutions.md) |
| [C07 Types and descriptors](c-compiler/chapters/07-types-and-stable-descriptors.md) | Separate type bits, scalar representation, aggregate identity, table movement and object layout | Seven exercises and [feedback](c-compiler/practice/07-solutions.md) |
| [C08 Names and scope](c-compiler/chapters/08-names-and-lexical-scope.md) | Trace name borrowing, lookup policy, row reuse and count-based visibility | Eight exercises and [feedback](c-compiler/practice/08-solutions.md) |
| [Third C mixed check](c-compiler/practice/return-check-3.md) | Identify the exact state restored or preserved across token, type and name boundaries | Four mixed questions, hints and separate answers |
| [C09 Executable instructions](c-compiler/chapters/09-instructions-inside-an-executable.md) | Derive encoded bytes, field widths, instruction effects and ELF mapping under named premises | Eight exercises and [feedback](c-compiler/practice/09-solutions.md) |
| [C10 Calls, literals and addresses](c-compiler/chapters/10-calls-literals-and-deferred-addresses.md) | Follow argument staging and the full lifetime of relative/absolute patches and data placement | Nine exercises and [feedback](c-compiler/practice/10-solutions.md) |
| [C11 Bounded legacy runtime](c-compiler/chapters/11-a-bounded-legacy-runtime.md) | Predict each runtime operation's actual request, return and limit | Eight exercises and [feedback](c-compiler/practice/11-solutions.md) |
| [Fourth C mixed check](c-compiler/practice/return-check-4.md) | Separate instruction fields, patch metadata, runtime units and typed storage effects | Four mixed questions, hints and separate answers |

The preprocessor's macro and conditional handlers are named interfaces in
C03. C04/C05 now open those mechanisms; the earlier include exercise
does not secretly require solving them first. The [source map](c-compiler/SOURCE-MAP.md)
keeps both the current explanations and the deferred regions inspectable.

## What the next units must earn

The next C units teach places, values and delayed loads before precedence
and short-circuit parsing. That order gives each operator a known state model
to preserve or consume. Complete expression/evaluator closure and declaration
construction follow, then statement/function integration. The later compiler still needs complete type/parser/emitter chapters,
a named end-to-end artifact comparison and its assembler/extended-profile
handoffs. Existing repository results have their own evidence scope.

Both volumes' new examples need an authorized, named execution profile and a
fresh-reader setup check before derived results can be relabeled as observed.
The [full coverage map](COVERAGE.md) allocates the remaining original material.
A planned unit is not required reading that already exists.

## How to use practice

Try a prediction before opening feedback when that helps expose your current
model. If you cannot start, use the first hint or the worked example right
away. If the error is a missing convention, repair that convention before
adding a harder problem. If you can explain representative cases accurately,
skip redundant steps and try a changed boundary or the return check.

After feedback, use a changed input rather than immediately copying the same
answer. At a later session, return to a mixed problem without its solution
open. Those are opportunities to check independent performance and retention,
not claims that a fixed practice schedule guarantees either. Keep normal
navigation and reference aids available; this is not a test of memorizing file
names.
