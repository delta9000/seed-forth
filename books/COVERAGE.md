# Coverage and learning-dependency map

This is the editorial map for a new teaching edition in `books/`. It does not replace the canonical literate `book/` tree or change its sources. Four volumes are a **provisional editorial structure**: Seed and Forth, A C Compiler in Forth, From Compiler to Closed Toolchain, and Kernels and Linux.

**Edition:** `direct-gcc-overlay`, commit `7d7e1996d1753118181d43e1a413960d3a1ec24b`, inspected October 6, 2026. All source destinations in [coverage.csv](coverage.csv) are pinned to that commit. A floating branch name is not an edition identifier.

## Current result

**Volume 1, Seed and Forth, has a complete draft teaching path.** Its [opening](seed-forth/chapters/00-why-inspect-a-seed.md), [route guide](seed-forth/chapters/00-start-here.md), chapters S01–S19, separate feedback, six mixed return checks and [compact reference](seed-forth/REFERENCE.md) cover the seed and its first library. The [audit ledger](seed-forth/source-audit.csv) assigns an explanation to all **76 regions / 1,772 original file bytes**, including all 32 dictionary headers. All **63 library colon definitions and 11 constant-created names** have substantive teaching homes.

The [S19 capstone](seed-forth/chapters/19-audit-synthesis-and-capstone.md) derives a fresh 32-byte `inc` entry and its predicted stack/control behavior. Those are predicted **process-memory bytes**, not an observed execution or additional bytes in the original seed file. The hand-encoded native Forth colon compiler is distinct from the **C compiler written in Forth**. Volume 2 now has drafted chapters C01–C08, reaching the bounded preprocessor, lexer, types/descriptors and symbol/scope mechanisms; the remainder of that volume and Volumes 3–4 remain planned. No complete C-compiler, toolchain or kernel manuscript, or newly verified chain, is claimed.

Draft completeness is a teaching-coverage claim. The new examples have not been executed, the fresh-reader installation route has not been tested, and no real-reader learning validation, universal correctness proof, or security proof is claimed. The first volume supports source reading and paper derivation under its explicit Linux/x86-64, storage, input and call assumptions. It links the pinned build entry without presenting that link as a tested setup tutorial.

The [C-volume entrance](c-compiler/README.md) leads through [C01: the compiler/profile contract](c-compiler/chapters/01-compiler-entry-and-profile.md), [C02: buffers, arenas and failure](c-compiler/chapters/02-buffers-arenas-and-failure.md), [C03: preprocessing regions and includes](c-compiler/chapters/03-preprocessing-regions-and-includes.md), [C04: macro expansion and rescanning](c-compiler/chapters/04-macro-expansion-and-rescanning.md), and [C05: conditionals and profile extensions](c-compiler/chapters/05-conditionals-and-profile-extensions.md). 

The representation route continues with [C06: tokens and lookahead](c-compiler/chapters/06-tokens-and-lookahead.md), [C07: types and stable descriptors](c-compiler/chapters/07-types-and-stable-descriptors.md), and [C08: names and lexical scope](c-compiler/chapters/08-names-and-lexical-scope.md). Eight feedback companions supply 48 chapter exercises. The [first mixed return check](c-compiler/practice/return-check.md) revisits C01–C03, a [second mixed check](c-compiler/practice/return-check-2.md) combines macro lifetime, conditional selection and source identity; and a [third mixed check](c-compiler/practice/return-check-3.md) contrasts token rollback, descriptor growth and symbol visibility. The draft now explains infrastructure, all 57 source regions of the bounded preprocessor, all 39 lexer definitions, 52 type-layer definitions and 19 symbol definitions. C09 onward and the closing bootstrap comparisons remain planned at this checkpoint.

## How to read coverage and evidence

[coverage.csv](coverage.csv) is the exact source crosswalk: one row for every original prologue/numbered chapter, appendix and navigator, plus the supporting implementation/closure records. Its live columns contain current scope and actual remaining obligations. Earlier milestone snapshots stay in revision history rather than being repeated as stale scope columns.

The exact `migration_status` vocabulary is:

- `draft_covered`: all substantive teaching mechanisms of the mapped item are represented in draft. This does not require identical wording, the original narrative order, or copying every optional exercise one-for-one
- `partial`: some mapped teaching or reference content exists, but an explicit part remains elsewhere or unwritten
- `planned`: a home and prerequisites are assigned, but replacement teaching content is not yet drafted

`rewrite_concern` preserves the source issue or editorial policy behind a choice; `remaining_scope` is the authoritative list of what is still owed. These are migration states, **not test results**. `evidence_status` separately distinguishes pinned source inspection, manual derivation, static disassembly, recorded CI and the unexecuted new examples. A complete draft can still require editorial revision, execution and reader testing. Optional legacy extensions are listed as supplementary work where they remain useful; they do not turn represented core mechanisms back into unexplained ones.

The inventory retains **50 prologue/numbered chapters (00–49), seven appendices (A1–A7), eight Markdown navigators/editorial files, and `playground.fth`**: 66 original items. Eleven additional records cover the seed, library, compiler arena/I/O/preprocessor/lexer/type/symbol sources, direct-GCC closure documentation, sorting, and historical route context, for 77 source rows. That source-row count is independent of the 77-unit editorial graph. No original source item is silently dropped.

### Existing CI is separate evidence

The following automatic canonical repository runs passed at their named rewrite checkpoints. They do not establish execution of the new teaching examples, a fresh-reader setup test, or results for later unlisted commits. The described implementation remains pinned to the edition above.

| Checkpoint | Confirmed canonical run |
|---|---|
| `819de4d346c38623d8db741323bc92293273690a` | [37416564070](https://github.com/delta9000/seed-forth/actions/runs/37416564070) |
| `d63b29b3f7f563bafb0de6056309e70cc0964e41` | [37417624921](https://github.com/delta9000/seed-forth/actions/runs/37417624921) |
| `bff03516d3b7202bb2ecbb0457192ec61cb9d9eb` | [37419018142](https://github.com/delta9000/seed-forth/actions/runs/37419018142) |
| `705e3f73a5f74c636b0f016d1e8f840acf6d747a` | [37420513780](https://github.com/delta9000/seed-forth/actions/runs/37420513780) |
| `030bb0c8e5c8805f889bc00c3f8bb165e3631bbf` | [37422538095](https://github.com/delta9000/seed-forth/actions/runs/37422538095) |
| `e4ebf723dbe8a251e19906aaca90454c7b51aa57` | [37425847949](https://github.com/delta9000/seed-forth/actions/runs/37425847949) |
| `b52175e665123da15bcef216a482daa471b4609f` | [37428414147](https://github.com/delta9000/seed-forth/actions/runs/37428414147) |
| `67d35652c230b0fe744be50b0f9fdb42977ccdd1` | [37429742852](https://github.com/delta9000/seed-forth/actions/runs/37429742852) |

Native instruction listings were also checked by bounded GNU objdump 2.44 disassembly of source-decoded bytes. A static decoder reads the byte stream as data; that observation is not a running-seed trace. Manual predictions remain predictions until their exact inputs and environment are executed and recorded.

## Four books with independent outcomes

1. **Seed and Forth (`seed-forth`)**: begin with small stack programs, make bytes and state visible, construct a useful library, and then open the full 1,772-byte seed. The draft now finishes with a reader-built paper capstone, complete source/byte explanations and a precise statement of the trusted Linux/CPU/input boundary
2. **A C Compiler in Forth (`c-compiler`)**: enter with a pinned seed/library or an equivalent refresher; follow one C program through buffers, preprocessing, tokens, types, emitted instructions, and execution. Finish the legacy compiler/M2-Planet comparison, the Forth assembler handoff, and a distinctly labeled direct TinyCC extension
3. **From Compiler to Closed Toolchain (`gcc-toolchain`)**: enter with the compiler mechanisms and a new direct-GCC target contract. Build the conceptual path through objects, ABI, runtime, generators, `cc1`, binutils, hosted musl/libgcc, and the recorded GCC 4.0.4 fixed point
4. **Kernels and Linux (`kernels-linux`)**: begin from an explicitly identified direct-chain toolchain. The proposed finish is a newly evidenced kernel/Linux path with a chosen user-visible acceptance criterion. The current direct-GCC-to-Linux outcome is **pending**, and the technical route and scope still require their own pinned source inventory

An independent volume needs an entry artifact, how to obtain or rebuild it, a short prerequisite diagnostic/primer, local references, explicit trusted interfaces, and an outcome it actually finishes. Volume 1 now supplies its source pin, entry assumptions, paper route and local reference; a tested execution/setup route remains outstanding. Volume 2 now supplies its contract bridges, profile comparison, infrastructure/preprocessor/representation route and local source maps; its later teaching and tested setup remain outstanding. Volumes 3–4's entry packages are planned. Readers may use a pinned entry artifact without redoing every earlier derivation, while an audit route follows its full provenance.

## Learning order is not source order

The source files remain authoritative and unchanged. The new order follows what a reader must be able to do next:

- Stack effects and the explicit-literal contract precede pointer arithmetic. Byte, cell, address, and stored pointer are separate ideas before `HERE` is changed
- Bit patterns and wraparound precede signed interpretations and range checks. A small-width drawing must say it illustrates a 64-bit operation; it must not silently replace the machine's width
- Subtraction can be derived without first explaining the CPU return stack. `over` and `rot` wait for a proper two-stack trace
- A word's operational contract may be used before its implementation is opened. Every such deferral names the later unit that discharges it
- Dictionary-emission idioms precede the full ELF/encoding audit. S08 supplies the small header, immediate-dispatch, CALL, literal, and push-body contracts it uses locally; the machine-code pass then derives the complete seed account
- The compiler's internal data stack/registers, generated program's registers, private TinyCC ABI, and direct-GCC System V ABI are distinct machines and profiles
- In the toolchain book, scalar argument planning and floating representation move before the variadic/aggregate cases that use them. Ranked arrays stay with type identity; archive order stays with linking

The numbering below is an editorial route, not a requirement to alter file load order. Compiler startup still follows the actual loader contract, including the executing main layer last. Canonical chapter numbers remain source IDs, not new chapter numbers.

## Prerequisite bridges and deliberate deferrals

| Bridge | What the reader must be able to do | Where it is discharged |
|---|---|---|
| Entry → S01 | Read small decimal numbers and follow a left-to-right state trace; no Forth assumed | S01 supplies stack direction, effects, words, and explicit literals |
| S01 → S02 | Distinguish the stack's value from a byte-addressed memory location | S02 supplies a labeled memory picture and fetch/store contracts |
| S01/S03 → S04 | Track word calls, cell width, and bitwise operations for the optional application | S04 teaches owned return-stack temporaries, shuffles, the helper-call boundary, and optional XOR |
| S03/S04 → S05 | Track modular subtraction, canonical flags, unsigned division, and `over` | S05 distinguishes equality, sign detection, bounded ordering, and ASCII membership; `space?` uses S04's `over` |
| S02/S03/S04/S05 → S07 | Distinguish buffer addresses, signed error cells, calls, and the `0<` sign predicate | S07 teaches Linux request/result contracts and raw-error classification without requiring an untaught retry loop |
| S02/S06 (including S03/S04) → S08 | Distinguish bytes emitted now from code executed later | S08 supplies minimal dictionary/ISA contracts locally and keeps its three phases separate; S11 is not an unstated prerequisite |
| S03/S04/S06/S08 → S09 | Keep compile-time fixups separate from runtime data and owned return-stack temporaries | S09's conditionals/loops and `exit,` cleanup use S04's ownership discipline |
| S02/S04/S05/S06/S08/S09 → S10 | Track storage, bounded counts, input lifetime, generated bodies, and both stacks | S10 defines `1+`/`1-` before token/copy loops, then integrates named data, deferred dispatch, and byte comparison; the paper capstone needs no printer |
| S02/S06/S08 → S11 | Distinguish bytes/addresses, little-endian fields, xts and relative calls | S11 supplies the instruction key, ELF mapping and startup; the later physical audit uses its actual coordinate system |
| S04/S11 → S12 | Preserve logical stack and call ownership while tracking physical registers/memory | S12 derives the cached-TOS/dummy invariant and accounts for ten bodies; dictionary headers are opened separately in S15 |
| S03/S05/S12 → S13 | Track modular values, flags/comparison limits, and cached-TOS state | S13 explains five arithmetic bodies, partial-byte writes, unsigned DIV and low-half IMUL; headers are S15's separate responsibility |
| S07/S12/S13 → S14 | Track kernel-result meaning, cached-stack restoration, partial-register writes and ZF | S14 opens all I/O/exit bodies without promoting returned stack shape into successful I/O |
| S08/S10/S12/S14 → S15 | Keep header identity, borrowed bytes, physical stack state and real input/error limits separate | S15 reconstructs every header and opens all eleven dictionary/input/error bodies/helpers; S18 subsequently opens the complete REPL use |
| S08/S09/S10/S13/S15 → S16 | Distinguish compile/runtime state, copied names, operand widths, input results and xts | S16 opens the native colon/literal compiler and introduces DF=0 locally for REP MOVSB; S18 subsequently opens the decimal-parser contract |
| S09/S12/S13/S16 → S17 | Separate branch call targets, inline program targets, saved flags and owner state | S17 opens all 34 branch bytes and restores the exact pre-call return-stack shape |
| S13/S14/S15/S16/S17 → S18 | Combine byte grammar, raw-input limits, lookup and native compilation | S18 opens all 168 decimal-parser/REPL bytes, including failure and EOF behavior |
| S11–S18 → S19 | Reconcile library contracts and every assigned native region | S19 adds no file bytes; it derives a fresh runtime-memory word and a bounded audit conclusion |
| Entry → C01 | Read small state traces; distinguish values from addresses, definition from execution, and allocation from initialization | C01 supplies a four-contract diagnostic/bridge and the C syntax used by `tri.c`; targeted seed refreshers are available, but S19 is not an entry prerequisite |
| C01 → C02 | Read shuffles, balanced return borrowing, compiled choices/loops/exits, bounded comparisons, stored updates, raw I/O and deferred selection | C02 supplies a local contract bridge; S04/S05/S06/S07/S09/S10 are targeted equivalent refresher routes, not six mandatory whole-chapter prerequisites |
| C02 → C03 | Distinguish a borrowed span from owned bytes, input from output positions, capacity from accepted length, and live storage from reusable storage | C03 derives regions, shared sinks, retained newlines, literal includes and physical search paths; C04 opens macro storage/rescanning and C05 opens conditional/location interfaces |
| C03 → C04 | Keep input regions, parked sinks, persistent definitions and temporary byte ownership separate | C04 derives stored recipes, argument prescan, substitution/rescan, busy state, token shadows and the final-token tail rule |
| C03/C04 → C05 | Distinguish membership from replacement value; keep scratch text alive until its consumer returns | C05 supplies local evaluator/profile contracts; C06 opens its lexer snapshot dependency, while the evaluator implementation remains a later lesson |
| C02/C05 → C06 | Track the flattened source span, byte cursor, retained spelling and limited state restoration | C06 derives token validity, byte boundaries, one-token replay and the eight-cell mark; floating recognition/decoding stays behind named target interfaces |
| C02 → C07 | Distinguish an address from a stored pointer, reserved storage from initialized bytes, and builder metadata from generated objects | C07 teaches bit/type notation and the numeric-token contract locally; C06 is helpful background rather than an additional prerequisite |
| C02/C06/C07 → C08 | Keep borrowed token names, descriptor identity, field-record addresses and arena lifetime separate | C08 derives symbol rows, namespace hooks, scope-count restoration, metadata and qualifier associations; later fixup/declaration providers stay separate |
| Compiler → toolchain | Name source/object/executable, symbol/relocation, ABI, host/builder/target, and profile | G01–G05 provide a new contract and a complete numerical two-object example |
| Scalar → variadic/record ABI | Track independent register banks, stack slots, alignment, snapshots, and result lifetime | G04, G10, G12, G15; X87 is deferred explicitly until G15 |
| `cc1` → closed toolchain | Distinguish emitted assembly, a runnable program, a hosted runtime, and a reproducible compiler generation | G20–G25 add downstream production tools, sysroot, lineage, and comparisons |
| Hosted toolchain → kernel | Distinguish a Linux process from bare/privileged entry and distinguish kernel entry from userspace success | K01–K07 must provide a new platform/boot contract; no silent carryover of hosted assumptions |

Exercises inherit these edges. For example, a write-all implementation waits until S09 teaches loops, XOR constructions name their shuffle prerequisites, and full floating variadic exercises wait until the needed class planner exists. Each major mechanism will pair prediction, a causal worked trace, a faded completion task, an independent task, and separate hints/solutions where those forms fit. Changed-width, changed-boundary, and changed-profile problems test meaningful adaptation rather than renamed examples. They are proposed assessments until a reader attempts them.

## Destination ledger

IDs below are stable editorial destinations. S00–S19 and C01–C08 now have drafted manuscripts; C09–C24 and all G/K units remain planned at this checkpoint. `entry` means the stated volume entrance; an equivalent entry bridge requires an explicit diagnostic/refresher, not an unexplained prerequisite. Named local bridges are required contracts supplied in that unit; their targeted refresher links are alternative ways to acquire those contracts. Listed prerequisites are conjunctive, with semicolons used in the CSV. The source column uses canonical chapter IDs; [coverage.csv](coverage.csv) supplies every exact path, immutable link, outcome, edge, migration status, and revision concern.

### Volume 1: Seed and Forth
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| S00 — Why inspect a seed? | entry | Explain the seed-local outcome, public provenance and trust/evidence boundaries; distinguish the later planned volumes. | 00 | drafted |
| S01 — Values and words | entry | Predict a data stack; read stack effects; use explicit literals and a colon-definition contract. | 01 | drafted |
| S02 — Addresses and bytes | S01 | Distinguish a value, its address, and a stored pointer; trace a byte write and HERE update. | 02 | drafted |
| S03 — Bits and subtraction | S01 | Derive and/or from cell-wide nand; trace canonical flags, complement, and subtraction modulo the cell width. | 01, 03, 04 | drafted |
| S04 — Two stacks and reusable shuffles | S01, S03 | Trace over, rot, nip, 2dup, and 2drop with owned return-stack temporaries; explain the helper-call boundary and optional XOR. | 01, 03, 04, 08 | drafted |
| S05 — Comparisons and character classes | S03, S04 | Distinguish equality, sign extraction, bounded signed ordering, and ASCII classifiers, including the over-dependent space? trace. | 06, 07 | drafted |
| S06 — Memory updates and little-endian writers | S02, S03, S04 | Trace +!, -!, ,4, and ,8 with exact operand order, truncation, and byte/cursor invariants. | 01, 02, 09 | drafted |
| S07 — Calling Linux through a contract | S02, S03, S04, S05 | Trace Linux wrapper arguments and raw counts/errors; distinguish requested work, partial progress, and tiny-I/O limits. | 05 | drafted |
| S08 — Words that create words | S02, S06 | Separate three defining-word phases using locally supplied header/ISA contracts; explain immediate metadata, calls, and character literals. | 01, 02, 09, 10 | drafted |
| S09 — Control flow by remembered addresses | S03, S04, S06, S08 | Trace all nine control-flow combinators with separate compile/runtime states and owned-temporary cleanup at early exits. | 04, 11, 19, A4 | drafted |
| S10 — Persistent storage and a classifier | S02, S04, S05, S06, S08, S09 | Introduce 1+/1- before loops; trace named storage, deferred dispatch, borrowed tokens, copying, and a byte-recognizer capstone. | 04, 07, 11, 12, A2 | drafted |
| S11 — From file bytes to an entry point | S02, S06, S08 | Decode both ELF headers and all startup instructions: five exact regions, 186 file bytes, under explicit loader/ISA assumptions. | 13, A1, A2 | drafted |
| S12 — The physical stacks and memory operations | S04, S11 | Reconstruct cached TOS, deeper cells and dummy state; account for ten stack/memory bodies totaling 119 bytes, excluding headers. | 01, 04, 08, 14, A1, A2 | drafted |
| S13 — Arithmetic in instruction bytes | S03, S05, S12 | Account for five arithmetic/logic bodies totaling 70 bytes, distinguishing flags, byte writes, unsigned division and retained product bits. | 01, 03, 04, 07, 15, A1 | drafted |
| S14 — The physical I/O boundary | S07, S12, S13 | Explain four I/O/exit bodies, 142 bytes, including result-independent cleanup, stale-input and NUL/EOF limits, and nonreturning exit. | 05, 16, A1, A7 | drafted |
| S15 — Dictionary identity and token input | S08, S10, S12, S14 | Reconstruct all 32 headers and eleven dictionary/input/error bodies/helpers: 43 regions, 816 bytes, with borrowed-token and stale-state boundaries. | 02, 06, 10, 12, 14, 15, 16, 17, 18, 19, A1, A7 | drafted |
| S16 — The native Forth colon compiler | S08, S09, S10, S13, S15 | Explain five native Forth colon-compiler bodies/helpers, 237 bytes, and derive a complete generated entry without confusing it with the later C compiler. | 02, 10, 12, 18, A1, A4 | drafted |
| S17 — Inline operands and branch returns | S09, S12, S13, S16 | Explain both branch bodies/34 bytes, including original-flag consumption, inline destinations and post-RET ownership. | 11, 19, A1 | drafted |
| S18 — Closing the parser and interpreter loop | S13, S14, S15, S16, S17 | Explain all 168 parser/REPL bytes: bounded byte grammar, wrapped values, separate flags, dispatch, continuation and exit limits. | 20, A1, A7 | drafted |
| S19 — Seed audit and reader-built capstone | S11, S12, S13, S14, S15, S16, S17, S18 | Reconcile all 76 regions/1772 file bytes; derive the 32-byte inc runtime entry and state the remaining evidence and trust boundaries. | 00, 20, A1 | drafted |

### Volume 2: A C Compiler in Forth
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| C01 — Compiler entry and profile contract | entry: local Forth-contract bridge | Derive tri.c's requested output, name its profile and load order, and separate the builder, emitted image and generated-program execution. | 21 | drafted |
| C02 — Buffers, arenas, and failure ownership | C01, local library-contract bridge | Trace all 35 arena/I/O definitions through spans, cursors, capacity, allocation lifetime, output patching, workspace selection and failure limits. | 21, A2, A7 | drafted |
| C03 — Preprocessing regions and includes | C02 | Trace nested literal includes, shared sinks, retained newlines, bounded search paths and live storage; name deferred macro/conditional/location mechanisms. | 22, A2, A7 | drafted |
| C04 — Macro expansion and rescanning | C03 | Derive stored macro recipes, raw/expanded argument lifetimes, substitution and rescans; distinguish busy state, token unavailability and tail calls. | 22, A2, A7 | drafted |
| C05 — Conditional preprocessing and profile extensions | C03, C04, local evaluator/profile contracts | Trace conditional selection, computed headers, physical/logical locations, continuation rules and independent profile/reset gates while preserving evaluator lifetime. | 22, A2, A7 | drafted |
| C06 — Tokens and reversible lookahead | C02, C05 | Derive valid token payloads and byte endpoints; distinguish replay from eight-cell rollback and retained spelling from decoded values across all 39 lexer definitions. | 23, A2, A7 | drafted |
| C07 — Types and stable descriptors | C02, local bit/type/token contracts | Pack types, preserve literal identity and profile sizes, trace stable headers and growing tables, and use named aggregate/array producer contracts across all 52 definitions. | 24, A2, A7 | drafted |
| C08 — Names and lexical scope | C02, C06, C07 | Trace all 19 symbol definitions: parallel records, namespace selection, scope-count restoration, metadata/fixup heads and qualifier lifetime. | 24, A2, A7 | drafted |
| C09 — Instructions inside an executable | C02, S11 | Derive representative instruction bytes, file/virtual addresses, and branch reference points. | 25 | planned |
| C10 — Calls, literals, and deferred addresses | C08, C09 | Resolve forward-call and global-address fixups while tracking data and BSS ownership. | 26 | planned |
| C11 — A bounded legacy runtime | C09, C10, S07 | Explain each shim's supported behavior and deviations from an ordinary libc contract. | 26 | planned |
| C12 — Precedence and short-circuit expressions | C06, C07, C10 | Trace recursive precedence, iterative associativity, and conditional evaluation on the recurring C example. | 27, A4 | planned |
| C13 — Places, values, and delayed loads | C08, C12 | Track an lvalue's identity until a load or store is actually required. | 28 | planned |
| C14 — Postfix, unary, and assignment | C13 | Trace nested assignment and postfix effects while preserving expression metadata; open constant evaluation and the saved-state preprocessor evaluator provider. | 28 | planned |
| C15 — Declarations and recursive records | C07, C08, C14 | Parse a declaration, pre-register a recursive record, and distinguish storage duration from visibility. | 29 | planned |
| C16 — Conditions and loops | C09, C12, C15 | Use ownership-scoped fixups for conditional and loop control flow. | 30 | planned |
| C17 — Switches, labels, and nonlocal control | C16 | Trace switch dispatch and goto without confusing their saved control state with a loop's. | 30 | planned |
| C18 — Functions and call-frame accounting | C08, C10, C14, C15, C17 | Trace parameters, nested calls, and frames under the named restricted calling convention. | 31 | planned |
| C19 — Translation units and process entry | C11, C18 | Connect declarations, globals, prototypes, function definitions, and the entry stub. | 31 | planned |
| C20 — The complete compiler and Stage-A comparison | C19 | Follow the complete byte path and identify the exact M1 outputs and inputs compared by Stage A. | 00, 32, A3 | planned |
| C21 — Assembler input and expansion | C02, C06, S10 | Expand M1 input and account for labels, fields, strings, and sigils. | 33 | planned |
| C22 — Two-pass assembly and bootstrap handoff | C20, C21 | Explain why both passes agree on addresses, then identify the source-built assembler handoff. | 33, A3 | planned |
| C23 — The direct TinyCC profile | C15, C18, C20 | Separate LP64 object layout and private stack calls from the legacy compiler and System V target. | 34 | planned |
| C24 — TinyCC initialization, runtime, and closure | C22, C23 | Track prepared-source provenance, initializers, bounded seed runtime, rebuilt TinyCC, and its specific fixed-point comparison. | 34, A3 | planned |

### Volume 3: From Compiler to Closed Toolchain
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| G01 — Entering the direct-GCC target | C24 or equivalent entry bridge | Pin builder/host/target roles and the direct-GCC profile without importing either earlier calling convention. | 35 | planned |
| G02 — Objects, symbols, and relocation records | G01 | Trace section bytes, stable symbol identities, BSS, and a relocation before placement is known. | 35 | planned |
| G03 — Signatures, declarators, and ranked arrays | G02, C07, C15 | Preserve type and signature identity through declarations, pointer shapes, and ranked array descriptors. | 36, 47 | planned |
| G04 — A shared scalar argument planner | G03, C18 | Assign integer arguments and results, protect temporaries, and account for stack alignment at every call. | 36, 48 | planned |
| G05 — Linking independently built objects | G02 | Validate, resolve, place, relocate, and publish a bounded ELF link with a complete numerical example. | 37 | planned |
| G06 — Raw syscalls, startup, and runtime control | G04, G05 | Trace the C-to-Linux bridge, errno, entry, and separately specified frame/nonlocal-return helpers. | 38 | planned |
| G07 — Source-built allocation and byte operations | G06 | Follow allocation extents, failure preservation, memory/string operations, and mapped/process interfaces. | 39 | planned |
| G08 — Target headers and honest feature probes | G03, C05 | Explain target predefines, selector hooks and which header branches they select without claiming unsupported GNU compatibility. | 40 | planned |
| G09 — Typed constants and symbolic addresses | G03, G02, C14 | Trace a typed constant record and relocation addend while parsing unevaluated branches safely. | 41 | planned |
| G10 — Floating values and conversion | G04, G09 | Separate payload transport, numeric conversion, storage width, and floating arithmetic. | 45 | planned |
| G11 — Decimal literals rounded once | G10 | Convert an exact decimal ratio to binary64 with rounding and subnormal boundary cases. | 46 | planned |
| G12 — Variadic cursors and argument classes | G04, G10 | Walk an interleaved register/overflow argument list; defer X87 details explicitly until G15. | 42 | planned |
| G13 — Streams and bounded formatting | G07, G12 | Trace stream position, partial-object I/O, sticky errors, and supported integer formatting. | 43 | planned |
| G14 — Bitfield layout and preserving stores | G03, G09, C13 | Trace allocation, promotion, extraction, and writes that preserve neighboring bits. | 47 | planned |
| G15 — Aggregate values and X87 transport | G04, G10, G12, G14 | Assign record arguments/results with register rollback, snapshots, hidden returns, and explicit alignment limits. | 42, 48 | planned |
| G16 — Indexed archives and lazy extraction | G02, G05 | Trace selection to a fixed point within one archive and explain command-line ordering. | 44 | planned |
| G17 — Frozen driver, configure, and source census | G05, G07, G08, G09, G11, G13, G15, G16 | Separate source capture, cache identity, configure observations, and Makefile-selected compilation work. | 49 | planned |
| G18 — Source generators must have builders | G17 | Track oyacc, Heirloom lex, flex, and GCC generators with source preparation and production/oracle separation. | 49 | planned |
| G19 — The cc1 milestone and its tests | G18 | Explain declaration failures despite successful linking and scope execution-torture evidence using host output tools. | 49 | planned |
| G20 — Building the downstream binutils | G18 | Connect regenerated parser/scanner inputs to Forth-built assembler/linker tools and their retained reports. | gcc-direct/README.md | planned |
| G21 — A freestanding GCC driver toolchain | G20 | Follow driver, cc1, as, and ld invocation provenance through a no-libc executable. | gcc-direct/README.md | planned |
| G22 — Hosted closure with libgcc and musl | G21 | Follow the sysroot, runtime libraries, startup objects, and a hosted program built by Stage C. | gcc-direct/README.md | planned |
| G23 — Rebuild lineage and controlled paths | G22 | Identify who builds GCC stages 2, 3, and 4 and hold embedded-path inputs constant. | gcc-direct/README.md | planned |
| G24 — Equal sort keys and unequal bytes | G23 | Explain why legal qsort tie ordering can change generated bytes and how the recorded runtime change affects the comparison. | runtime/gcc-seed/SORT.md | planned |
| G25 — Fixed-point evidence and toolchain capstone | G24 | Read file/member comparisons, retain provenance and assumptions, and distinguish recorded equality from general correctness. | A3 | planned |

### Volume 4: Kernels and Linux
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| K01 — A new kernel-route contract | G25 | Pin the exact direct-chain toolchain and decide the kernel route, entry artifacts, and acceptance criteria. | new material | planned |
| K02 — Loading an image and reaching entry | K01 | Specify loader, executable/image format, CPU mode, memory map, and entry-state obligations. | new material | planned |
| K03 — Memory and privileged execution | K02 | Explain the memory, exception, and interrupt mechanisms required by the selected teaching kernel. | new material | planned |
| K04 — A small observable kernel | K03 | Build a minimal coherent kernel story with an observable result and explicit device/platform assumptions. | new material | planned |
| K05 — The Linux build and boot boundary | K04 | Pin kernel configuration, compiler requirements, boot protocol, and image provenance. | new material | planned |
| K06 — Userspace and the initial filesystem | K05 | Trace init/startup and required userspace inputs rather than equating kernel entry with a usable system. | new material | planned |
| K07 — End-to-end direct-chain acceptance | K06 | Establish the selected user-visible Linux acceptance behavior with retained direct-chain provenance. | new material | planned |
| K08 — Lineage, trust, and the final handoff | K07 | Compare the completed route's actual dependencies with distinct historical ladders and state what remains trusted. | A3 | planned |

### Appendices and navigators

These destinations are reference obligations. They are not extra volumes and they are not marked complete merely because their topic appears in an early lesson.

| Existing source | New destination | Preservation and revision obligation |
|---|---|---|
| `book/A1-32-seed-primitives.md` | R-primitives; S11–S19 | Draft-covered: REFERENCE.md plus all native body/helper explanations and the byte budget |
| `book/A2-memory-map.md` | S10–S12; C02–C08; R-memory | Seed, buffers/preprocessor, lexer marks, type descriptors and symbol storage drafted; later generated-program, native and direct-GCC views remain incomplete |
| `book/A3-reproducibility-chain.md` | R-lineage; C20/C22/C24; G25; K08 | Preserve every existing lineage and comparison; add the direct-GCC ending separately; keep kernel lineage pending |
| `book/A4-worked-exercises.md` | R-solutions; S09/S16/C12 | Retain the three existing worked mechanisms, repair their premises/setup, and distribute expanded feedback by objective |
| `book/A5-further-reading.md` | R-reading | Preserve purpose-based routes with durable primary links and explicit versions |
| `book/A6-c-subset.md` | R-c-subsets | Give legacy, native TinyCC, and direct-GCC their own accepted/rejected/bounded contracts |
| `book/A7-error-codes.md` | S14/S15/S18; C02–C08; R-errors | Seed, infrastructure/preprocessor, lexical limits and type/symbol failures drafted; later compiler-phase/profile/assembler tables remain planned |
| `book/CONCEPTS.md` | N-concepts | Replace stale source-order graph with first-use, revisit, and actual prerequisite edges |
| `book/GLOSSARY.md` | N-glossary | Synchronize definitions with the profile and chapter that teaches them |
| `book/LEARNING_STORY_PLAN.md` | N-editorial | Carry forward useful outcome/trace goals; do not import obsolete rollout statuses |
| `book/README.md` | N-reading | Provide current entrances, independent outcomes, and honest completion status |
| `book/SUMMARY.md` | N-reading | Link existing text and visibly distinguish future units |
| `book/WORD-INDEX.md` | N-source | Preserve exact symbol-to-source navigation and generate new teaching links from explicit edition inputs |
| `book/WRITING.md` | N-editorial | Keep canonical tangle ownership separate from new-edition annotation/excerpt rules |
| `book/where-this-fits.md` | S00; R-lineage | Preserve historical context while narrowing correctness and lineage claims |
| `book/playground.fth` | R-playground | Retain by pinned link as an optional compatibility profile, with exact limitations |

## What is covered, and what remains

| Source group | Migration state | Boundary |
|---|---|---|
| Canonical Chapters 01–20 | `draft_covered` | Every substantive seed/library mechanism is represented across S01–S19; optional legacy extensions are supplementary, and new examples remain unexecuted |
| Canonical Chapter 21; `020-cc-arena.fth` and `030-cc-io.fth` | `draft_covered` | C01/C02 represent the entry/infrastructure mechanisms and all 35 colon definitions, including selectable storage and failure limits |
| Canonical Chapter 22; `040-cc-prep.fth` | `draft_covered` | C03–C05 cover all 57 regions and 325 declaration homes; C06 now opens lexer marking, while later evaluator/target providers remain planned |
| Canonical Chapter 23; `050-cc-lex.fth` | `draft_covered` | C06 explains all 39 lexer definitions, eight token kinds, 34 keywords, decoding boundaries and replay/snapshot contracts; later floating providers remain interfaces |
| Canonical Chapter 24 | `draft_covered` | C07/C08 explain type/descriptor and symbol/scope mechanisms, including actual profile, growing-table and ownership boundaries |
| `060-cc-types.fth` | `draft_covered` | C07 explains all 52 definitions and supporting representations; later declaration, member-lookup and target producers remain named interfaces |
| `070-cc-sym.fth` | `draft_covered` | C08 explains all 19 definitions, ten columns, six kinds, scope markers, qualifiers and deferred interfaces; later consumers/providers remain explicit |
| Canonical prologue 00 | `partial` | S00 preserves seed motivation, provenance and trust boundaries; the original C/Fibonacci demonstration moves to planned C20 |
| `000-seed.hex0` and `010-lib.fth` | `draft_covered` | Every seed region and every library definition has a teaching home; execution and reader validation remain separate |
| Appendix A1 | `draft_covered` | [REFERENCE.md](seed-forth/REFERENCE.md), body/helper explanations and S19 supply the complete seed-contract reference and byte budget |
| Appendices A2–A5 and A7 | `partial` | Seed-side material is represented; exact later-volume and supplementary obligations are retained below and in the CSV |
| Chapters 25–49 and Appendix A6 | `planned` | Later C passes, assembler, bootstrap comparisons, full subset catalogues, TinyCC and direct-GCC teaching still need their mapped manuscripts; supplied provider contracts do not migrate those chapters |
| Navigation/editorial files | `partial` | Complete first-volume routes and the C01–C08 entrance/source maps exist; the edition-wide glossary, bibliography, later routes and generated index remain incomplete |
| `playground.fth` | `planned` | Retained as a pinned optional compatibility profile, not promoted into a tested seed execution route |

The remaining first-volume release work is explicit: test the fresh-reader setup route in the named profile; execute and record the new examples and relevant boundary cases if authorized; conduct target-reader review; and revise from those observations. These are real unfinished verification and usability obligations, not missing byte-region ownership. This map does not authorize builds or tests by itself.

The old appendices cross volume boundaries:

- **A2 memory map:** the seed view is in REFERENCE.md and S10–S12; C02 adds arena/I/O buffers and lexer-state storage; C03–C05 add include pools, macro arrays/text, temporary sinks, token shadows, conditional/location records and their lifetimes. C06–C08 add token snapshots, stable descriptors/current tables, symbol columns, scope markers and qualifier nodes. Later compiler records, full native/target allocation, generated-program storage and the complete cross-profile reference remain R-memory work for Volumes 2–3
- **A3 reproducibility:** seed identity/trust distinctions and the inspected build entry are present; actual M2/assembler/pnut/TinyCC recipes and comparisons remain C20/C22/C24, direct-GCC closure G25, and kernel/route lineage K08/R-lineage
- **A4 worked exercises:** seed return/exit mechanisms and new feedback are present; the C precedence exercise remains C12/R-solutions. The old worked variants are not all copied one-for-one
- **A5 reading:** seed chapters cite the relevant implementation, ISA, ELF and Linux sources; the full purpose-based Forth/related-project bibliography and compiler/bootstrap/ABI reading routes remain R-reading
- **A7 diagnostics:** seed reporting, token/numeric failures, continuation and EOF are in S14/S15/S18 and REFERENCE.md. C02–C05 add infrastructure/preprocessor reporting, capacities, raw-I/O limits, macro/include/group failures, line-control/continuation errors and the evaluator's leftover-token interface; C06–C08 add actual lexical validation limits, suffix/descriptor/member and symbol/scope failure contracts. Later parser/emitter/native/direct-GCC/assembler diagnostic tables remain R-errors work

No kernel/Linux completion follows from finishing the seed manuscript. The historical ladder and current direct-GCC route remain distinct, and the current direct-GCC-to-Linux outcome is still pending.

## Current C-compiler coverage boundary

C01 supplies the independent entrance rather than requiring the entire seed audit. Its `tri.c` trace derives requested characters and return value on paper. The driver sequence, profile widths, load order and initial executable contract are entry contracts; the full parser, emitter, driver integration and compiler bootstrap still belong to their planned units.

C02 explains the six colon definitions in `020-cc-arena.fth` and the 29 in `030-cc-io.fth`, together with the declarations they use. The [definition map](c-compiler/source-map.csv) supplies an immutable span, source-blob identity and C02 home for each of the **35 definitions**. Coverage includes the 64-byte lexer state block, exact-capacity distinctions, negative-read behavior, rounded allocation versus initialization, unchecked patches, partial field emission, one-shot file writes, name lookup, and cached 3/7/4-MiB workspace selection. These contracts are explained; successful I/O or generated-program behavior has not been observed here.

C03 opens the first coherent part of `040-cc-prep.fth`: active-region cursors, the four-cell sink, file walkers, newline accounting, literal include frames, physical search paths, fixed-slot versus packed live storage, profile bounds, and final reader reset. Its worked three-file case preserves parents while all children append to one output. It does not equate a saved pointer with preserved bytes or flattened line counts with original-file locations.

The [preprocessor region map](c-compiler/preprocessor-regions.csv) partitions all **2,256 source lines and 325 declarations into 57 regions**. All **57 regions now have drafted explanations** across C03–C05: 17 primary homes in C03, 23 in C04 and 17 in C05. Shared-interface notes retain the cross-chapter explanations. This is a source-mechanism teaching account, not a machine-code audit or an execution result. The ledger's `drafted` label and this map's `draft_covered` whole-item label describe different levels of that account.

C04 derives persistent macro recipes, newest-first lookup/undefinition, borrowed raw arguments, prescanned arguments, scratch reserve/retain/release, substitution and replacement rescanning. Its direct-profile sections open selective prescan, stringizing/pasting, shadow metadata and final-token tail rescanning. Ordinary name/body spans live in the pool; the dynamic location entries introduced in C05 use static names and empty bodies. The exact `ID(N)` trace and five exercises keep byte counts, busy intervals and ownership visible without treating normalized token spelling as exact output.

C05 completes conditional selection, the evaluator-call lifetime, computed include operands, physical versus logical location, dynamic macros, bounded `#line`, local continuation/parameter rules, predefines and pass/configuration reset. Its six exercises vary membership, inactive nested groups, guarded includes, virtual filenames, target/workspace combinations and continuation owners. Direct preprocessing, target-enabled locations, larger workspace and typed preprocessing evaluation are separate gates; LP64 preprocessing-constant mode is not equivalent to either direct preprocessing or System V selection.

The completed preprocessor account deliberately uses these named external contracts:

| Contract used now | What is supplied in the draft | Later implementation home |
|---|---|---|
| Lexer state marking/restoration | C02's eight-cell state and C05's successful evaluator-return preservation contract | C06 now opens all `050-cc-lex.fth` definitions, including replay/mark/reset and their limits |
| `cc-pp-eval ( a u -- n )` and `cc-pp-eval-text` | C05 gives the caller lifetime, supported small-expression model, remaining-identifier rule, end-of-input check and the provider's state-preservation outline | C14 opens the constant-expression/provider mechanism in `100-cc-expr.fth`; G09 develops typed target constants and conversions |
| Target predefines and selectors | C05 explains the bounded `124` hook effects, dynamic tags and separate LP64/System V/workspace choices used by its traces | G01–G04 develop the full target/ABI machinery; G08 owns target-header/predefine integration |
| Whole compiler pipeline | C01 names the driver contract; C03–C05 finish the preprocessing transformation under its explicit interfaces | C06–C08 open tokens, types and names; C09 onward still owes instruction emission, parsing, runtime and bootstrap closure |

Using a supplied contract is not a missing explanation of the preprocessor's own call site. It also does not migrate the whole provider module or require a reader to learn a later parser first. These interfaces avoid a circular learning dependency while preserving the obligations of the later lessons. C06–C08 now discharge the base lexer/type/symbol-layer obligations; their later provider interfaces remain bounded contracts.

The [source-map guide](c-compiler/SOURCE-MAP.md), eight feedback companions and three mixed return checks make the current route navigable. They are source-inspected, manually derived drafts with technical review. New compiler examples, fresh-reader setup and target-reader learning remain unverified by execution or reader observation. The implementation's bounded grammar, macro-lookahead/token-joining limitations and flattened-diagnostic caveats remain explicit; draft coverage does not turn those limitations into claimed fixes.

### Representation and reversible-state boundary

The [definition map](c-compiler/source-map.csv) now names every colon definition in five implementation files: **145 definitions** in total. Their teaching homes are 6 arena plus 29 I/O definitions in C02, 39 lexer definitions in C06, 52 type definitions in C07, and 19 symbol definitions explained in C08. Supporting constants, tables, scratch state, buffers and deferred entries belong with those definitions; the separate 040 region ledger remains complete.

C06 derives the classified token record, all kind/keyword/punctuation IDs, integer spelling/value, borrowed string bodies versus decoded character values, comment and EOF boundaries, one-token replay and eight-cell snapshots. Its seven exercises include separate answer-free changed-case prompts. A lexer mark excludes source bytes/length, arena/output/symbol effects and other saved marks. The 121→127 floating-token hook and 128 decoder remain later G10/G11 implementations, with the active-target contract supplied locally.

C07 derives type packing, profile-dependent scalar results, suffix/literal selection, the 56-byte stable descriptor, separate growing field tables, recursive identity and array-node readers. Its seven exercises likewise expose changed-case attempts separately from feedback. All 52 definitions have teaching homes. The local token and bit contracts permit entry from C02; reading the whole lexer lesson is not silently required.

C08 explains ten physical columns behind each symbol ID, kind-aware payloads including tagged global-storage slots, newest-first lookup versus namespace policy, scope markers that restore only a live count, profile-selected metadata, writable fixup-head cells and qualifier-list keys. Its eight exercises and answer-free changed cases separate reusable symbol identity, stable descriptor identity, current field-record location and borrowed source bytes. All 19 definitions and their supporting declarations have teaching homes.

| Representation interface used now | Drafted contract | Later implementation home |
|---|---|---|
| Field layout and recursive completion | C07 compares legacy slot layout with native LP64 placement while preserving stable descriptor identity | C15 opens declaration producers; C23 opens native extensions |
| Field lookup and expression metadata | C07 derives `cc-find-field`'s named interface and distinguishes the generated-object address from the builder record | C13/C14 open the expression implementation |
| Ranked/qualified array construction | C07 derives the supplied System V node/qualification contract; accessors alone do not validate nodes | G03 opens the full array/declarator representation |
| Field stride and advanced aggregates | C07 names default 40/48-byte records and the explicit 72-byte provider, plus the moved-table hook | G14 opens bitfields; G15 opens aggregate transport |
| Scope and fixup consumers | C08 explains symbol lifetime and supplied provider behavior; later clients must preserve kind/profile and writable-cell meanings | C10/C15/C18 and G03/G04 open the relevant producers, calls and target policy |

These examples explain the representation used at the current boundary. They do not complete the named provider modules, establish a generated program's execution, or supply a general rollback transaction.

## Complete seed file-byte account

The [audit guide](seed-forth/AUDIT.md) and [exact source ledger](seed-forth/source-audit.csv) partition the pinned file into **76 nonoverlapping regions totaling 1,772 bytes**. Every region now has a drafted explanation. The partition excludes zero-filled mapped memory, runtime dictionary entries, stack storage and sysvars from the file-byte count.

| Unit | Owned regions | File bytes | Explanation status |
|---|---:|---:|---|
| S11 | 5: both ELF headers and three startup sections | 186 | Drafted |
| S12 | 10: stack and memory primitive bodies | 119 | Drafted |
| S13 | 5: arithmetic and logic primitive bodies | 70 | Drafted |
| S14 | 4: I/O and exit primitive bodies | 142 | Drafted |
| S15 | 43: all 32 headers/421 bytes and eleven dictionary/input/error bodies/helpers/395 bytes | 816 | Drafted |
| S16 | 5: native colon/semicolon/literal bodies and call-emission helper | 237 | Drafted |
| S17 | 2: branch bodies | 34 | Drafted |
| S18 | 2: decimal parser and REPL | 168 | Drafted |
| Total | 76 | 1,772 | All regions draft-covered |

An independent category sum gives the same result: ELF headers 120, startup 66, dictionary headers 421, primitive bodies 760, six unnamed helpers 322, and REPL 83. Thus metadata totals 541 bytes and instruction regions 1,231. The CSV groups the REPL under its `helper` kind, while S19 names it separately; these are classification conventions, not an extra routine or a missing one.

Header ownership never moves into an earlier body chapter: S15 counts each of the 421 header bytes once. S17's 34 bytes and S18's 168 bytes close the four regions that were pending at the preceding checkpoint. S19 adds **no** original file-byte ownership. Its `inc` entry is a checked prediction of 32 newly generated process-memory bytes starting at `0x401000`, beyond the original file-backed end.

Complete drafted byte coverage makes every region inspectable. It does not certify all arguments, inputs, tool observations, hardware behavior or system assumptions. Execution, reproducibility, semantic correctness, security and learner performance each need their own evidence.

## Library-definition register

This register accounts for every colon definition in the pinned [`010-lib.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth). Each name has one primary teaching home; later reuse does not count it again. “Draft” means an actual contract/excerpt or mechanism is present, at the depth stated in the last column. It does not claim that every definition has its own full machine-code proof, independent exercise, or executed test. The source's 63 colon definitions are distinct from its 11 additional names made with `constant` and from the seed's primitives.

| Home | Count | Colon definitions | Draft coverage and boundary |
|---|---:|---|---|
| S02 | 2 | `here-addr`, `c,` | Address/cursor contracts, exact definitions, and stack/memory trace |
| S03 | 3 | `and`, `or`, `-` | Bitwise/modular derivations and full representative stack traces |
| S04 | 5 | `over`, `nip`, `rot`, `2dup`, `2drop` | Shuffle compositions, two-stack traces, ownership and helper-call boundaries |
| S05 | 14 | `digit?`, `alpha-lower?`, `alpha-upper?`, `alpha?`, `space?`, `true`, `=`, `<>`, `2^63`, `0<`, `<`, `>`, `<=`, `>=` | Domain-aware equality, sign/order and ASCII contracts; derived boundary and combined-predicate traces |
| S06 | 4 | `+!`, `-!`, `,4`, `,8` | Complete representative update/writer traces, operand-order diagnosis, truncation and decoding |
| S07 | 5 | `open`, `read`, `write`, `close`, `die` | All wrapper definitions and argument/result contracts; representative expansion and error/partial-I/O reasoning |
| S08 | 9 | `immediate`, `ret,`, `push-imm64,`, `push-body,`, `constant`, `call,`, `tib`, `char`, `[char]` | Local dictionary/ISA contracts, defining phases, body and call layouts, input effects and character limits |
| S09 | 9 | `if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,`, `until,`, `again,`, `exit,` | All definitions; complete representative compile/runtime layouts; post-test and early-return contracts |
| S10 | 12 | `1+`, `1-`, `allot`, `skip-vm-pages`, `create`, `variable`, `defer`, `is`, `token`, `bytes,`, `s,`, `bytes-eq` | Step helpers before loops; storage and dispatch layouts; token ownership/copy and byte-comparison traces; profile-specific cursor jump is an explicitly bounded depth section |
| Total | 63 | Every colon definition in the pinned library | Draft library-level teaching coverage; source/execution debt remains above |

The constant-created names have their own accountability:

| Home | Names created with `constant` | What must remain distinct |
|---|---|---|
| S08 | `lit-xt`, `tab`, `nl`, `bl`, `lparen`, `backslash` | Captured code address versus execution; named byte values versus tokens the reader can return |
| S09 | `branch-xt`, `0branch-xt` | Load-time capture of branch-code addresses versus generated program destinations |
| S10 | `fetch-xt`, `execute-xt`, `defer-code-size` | Primitive addresses and the 29-byte body-size value versus the mutable dispatch-cell contents |

The library's immediate-marking calls are also substantive: S08 explains what `immediate` changes; S09 explains why each control-flow helper runs while its caller is being compiled. An all-names inventory would be incomplete teaching if it omitted those load-time effects. S11–S16 now explain executable/startup bytes, all 32 headers, and the assigned primitive/helper bodies. S17/S18 now complete the branch and decimal-parser/REPL explanations; S19 reconciles the whole audit.

## Giving the GCC story its actual ending

Chapter 49 is the `cc1` milestone. It cannot serve as the whole direct-GCC ending because its recorded execution tests use host output tools as an oracle. The pinned [direct-GCC driver documentation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md) supplies the additional editorial scope:

1. **G17–G19: capture, generators, and compiler proper.** Keep source snapshots, configuration facts, Makefile-selected units, declaration checks, and test outcomes distinct. Give generated C a named builder: oyacc → Heirloom lex → flex, plus GCC's own source generators. Retain preparation patches, licenses, and generated-input provenance
2. **G20: binutils.** Explain regeneration and Forth-built assembler/linker outputs, not merely that their sources compiled or configure returned success. Teach the meaning of retained failed and successful invocations
3. **G21: the driver chain.** Follow `gcc`, `cc1`, `collect2`, `as`, and `ld` through a freestanding executable. The documented tool paths and successful execs belong to this specific boundary; a no-header program does not establish a hosted sysroot
4. **G22: Stage C.** Explain target headers and libraries in the musl sysroot, the Forth-built GCC driver/compiler, GCC-built `libgcc`/`libgcov`/crt objects, musl's `libc.a` and startup objects, and the hosted program used by the recorded recipe
5. **G23–G25: Stage D.** Stage-C GCC builds stage 2; stage 2 builds stage 3; stage 3 builds stage 4. The recorded recipe requires stages 2, 3, and 4 to agree. Source/build/prefix paths are controlled; archive comparisons are member-wise because container timestamps differ. Every comparison must name its artifact set and normalization/comparison rule
6. **G24: why a legal difference mattered.** The [source-built sorting account](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/SORT.md) explains how equal-comparing values may be reordered differently, giving equivalent code but unequal bytes. Teach the reported heapsort-to-musl-smoothsort change as part of the recorded fixed-point lineage, not a universal theorem that one sort is stable or a fresh verification of these results

Old “in progress” paragraphs and later closure sections coexist in operator documentation. The new narrative must identify chronological milestones rather than combine incompatible statuses. It must also retain remaining orchestration/source-transformation and platform trust. “No host compiler supplies production objects” does not mean no host tools, operating system, or hardware are trusted.

The planned Volume 3 conclusion is the bounded direct-GCC 4.0.4 toolchain result. The historical TinyCC → `gcc64` ladder to newer GCC releases is a different route. Historical hex0-to-kernel/Linux accounts are context, not evidence that this new direct-GCC-to-Linux path has completed. Volume 4 begins with that open obligation.

## Source annotations and synchronization policy

The canonical `book/` and implementation files remain unchanged. The new teaching edition may quote pinned, attributed excerpts, but it must not introduce `file=`/`chunk=` fences that silently claim ownership of canonical sources. Its conceptual order need not match canonical tangle order.

For each future excerpt or diagram, retain the source commit, file, symbol/section, profile, and purpose. Prefer stable symbol/section anchors with line ranges as supplemental locators. Mark omitted code and schematic models explicitly; do not make a shortened excerpt appear executable. A trace needs its starting state, width, signedness, byte order, stack direction, and named evidence type. A prospective command needs host/target/profile, working directory, inputs, expected behavior, and an honest run status.

If source annotation changes are later authorized, propose them separately: exact target, educational reason, effect on generated sources, and verification needed. A manuscript-only rewrite does not authorize implementation repairs. The preprocessor's documented lookahead, token-joining and diagnostic boundaries remain implementation limitations in its completed draft account. Other static concerns, such as long-double alignment and linker close-state handling, remain qualified concerns until their later source explanations are checked; none is an execution failure observed here.

Changes propagate through dependencies. A cell-width change reaches number examples, masks, memory maps, instruction encodings, solutions, and ABI explanations. A descriptor change reaches glossary, parser traces, field/array examples, recaps, and practice. A moved unit reaches first-use terms, prerequisite edges, next/previous navigation, index, and solutions. A profile or endpoint change reaches volume entrances, source links, run instructions, evidence ledgers, and trust claims.

Before marking an item `draft_covered`, check that all substantive mechanisms and limitations have source-corresponding explanations, appropriate worked traces/practice, and sound prerequisite links. Preserve explicit homes for cross-volume material and note worthwhile optional legacy exercises; do not confuse exact prose/exercise replication with substantive teaching coverage. Before calling its examples executed, retain the exact commands, inputs, environment, outputs, and failures. Before calling the book independently learnable, obtain appropriate reader evidence; an editorial map or expert read-through cannot establish that result.
