# Coverage and learning-dependency map

This is the editorial map for a new teaching edition in `books/`. It does not replace the canonical literate `book/` tree or change its sources. Four volumes are a **provisional editorial structure**: Seed and Forth, A C Compiler in Forth, From Compiler to Closed Toolchain, and Kernels and Linux.

**Edition:** `direct-gcc-overlay`, commit `7d7e1996d1753118181d43e1a413960d3a1ec24b`, inspected October 6, 2026. All source destinations in [coverage.csv](coverage.csv) are pinned to that commit. A floating branch name is not an edition identifier.

## What exists, and what this map promises

The first manuscript milestone consists of [S1 / S01: Values and words](seed-forth/chapters/01-values-and-words.md), [S2 / S02: Addresses and bytes](seed-forth/chapters/02-addresses-and-bytes.md), and [S3 / S03: Bits and subtraction](seed-forth/chapters/03-bits-and-subtraction.md). `S1`–`S3` are the manuscript and exercise prefixes used in the [learning path](LEARNING-PATH.md); `S01`–`S03` are the same units' zero-padded editorial IDs here. The [start-here guide](seed-forth/chapters/00-start-here.md) provides their entrance; the proposed S00 below is a fuller future prologue, not another name for that guide. They are **draft, source-inspected, and manually traced**, not execution-verified. They introduce a deliberately small learning path. They do not finish canonical Chapters 1–4, the Forth library, or the seed audit.

All other teaching units below are **planned**. Volumes 2–4 are plans, not drafted books. A row assigning a source chapter to a new destination means that its mechanisms, limitations, examples, and practice have a home to be developed; it does not mean that text has migrated. In particular, early contracts for `:` or `nand` do not count as coverage of their complete machine-code implementation.

Root reader, edition, learning-path, and coverage documents are also drafted; navigator rows identify their limited coverage separately from chapter coverage.

The source inventory contains all **50 numbered/prologue chapters (00–49), seven appendices (A1–A7), eight Markdown navigation/editorial files, and `playground.fth`**. The CSV has one row for each of these 66 items, plus five source/context records for the seed, library, direct-GCC closure, sorting, and historical route status. No old chapter or appendix is silently dropped. Selected source excerpts are not a substitute for the full canonical listings.

### Reading the status fields

- `partial`: a specific part is taught in S01–S03, or a limited navigator/editorial replacement is drafted; the CSV states both that scope and the remaining debt. It never means “whole chapter migrated”
- `planned`: assigned a destination and prerequisites, but no replacement manuscript coverage is claimed
- `source-inspected`: grounded in the pinned implementation or document; it is not a claim that a command ran
- `manually traced`: predicted state changes derived from the stated contract; outputs remain predictions until the exact example is executed
- A repository's recorded build/test result remains a **reported result**, with its original profile and lineage. This rewrite has run no compiler builds, examples, regression suites, bootstrap, or kernel boot

Coverage, technical evidence, and learning evidence are separate. No real target-reader study is claimed. Completing this map establishes an editorial plan, not correctness or demonstrated learnability.

## Four books with independent outcomes

1. **Seed and Forth (`seed-forth`)**: begin with small stack programs, make bytes and state visible, construct a useful library, and then open the full 1,772-byte seed. The intended finish is a reader-built Forth capstone plus a complete source/byte audit and a precise statement of the trusted Linux/CPU/input boundary
2. **A C Compiler in Forth (`c-compiler`)**: enter with a pinned seed/library or an equivalent refresher; follow one C program through buffers, preprocessing, tokens, types, emitted instructions, and execution. Finish the legacy compiler/M2-Planet comparison, the Forth assembler handoff, and a distinctly labeled direct TinyCC extension
3. **From Compiler to Closed Toolchain (`gcc-toolchain`)**: enter with the compiler mechanisms and a new direct-GCC target contract. Build the conceptual path through objects, ABI, runtime, generators, `cc1`, binutils, hosted musl/libgcc, and the recorded GCC 4.0.4 fixed point
4. **Kernels and Linux (`kernels-linux`)**: begin from an explicitly identified direct-chain toolchain. The proposed finish is a newly evidenced kernel/Linux path with a chosen user-visible acceptance criterion. The current direct-GCC-to-Linux outcome is **pending**, and the technical route and scope still require their own pinned source inventory

An independent volume needs an entry artifact, how to obtain or rebuild it, a short prerequisite diagnostic/primer, local references, explicit trusted interfaces, and an outcome it actually finishes. Those entry packages are planned; a directory name does not supply them. Readers may use a pinned entry artifact without redoing every earlier derivation, while an audit route follows its full provenance.

## Learning order is not source order

The source files remain authoritative and unchanged. The new order follows what a reader must be able to do next:

- Stack effects and the explicit-literal contract precede pointer arithmetic. Byte, cell, address, and stored pointer are separate ideas before `HERE` is changed
- Bit patterns and wraparound precede signed interpretations and range checks. A small-width drawing must say it illustrates a 64-bit operation; it must not silently replace the machine's width
- Subtraction can be derived without first explaining the CPU return stack. `over` and `rot` wait for a proper two-stack trace
- A word's operational contract may be used before its implementation is opened. Every such deferral names the later unit that discharges it
- Dictionary-emission idioms precede the full ELF/encoding audit. The machine-code pass returns to the same states rather than introducing an unrelated story
- The compiler's internal data stack/registers, generated program's registers, private TinyCC ABI, and direct-GCC System V ABI are distinct machines and profiles
- In the toolchain book, scalar argument planning and floating representation move before the variadic/aggregate cases that use them. Ranked arrays stay with type identity; archive order stays with linking

The numbering below is an editorial route, not a requirement to alter file load order. Compiler startup still follows the actual loader contract, including the executing main layer last. Canonical chapter numbers remain source IDs, not new chapter numbers.

## Prerequisite bridges and deliberate deferrals

| Bridge | What the reader must be able to do | Where it is discharged |
|---|---|---|
| Entry → S01 | Read small decimal numbers and follow a left-to-right state trace; no Forth assumed | S01 supplies stack direction, effects, words, and explicit literals |
| S01 → S02 | Distinguish the stack's value from a byte-addressed memory location | S02 supplies a labeled memory picture and fetch/store contracts |
| S01/S03 → S04/S05 | Track operand order, cell width, unsigned values, and flags | S04 opens temporary return-stack use; S05 introduces division and signed-boundary limits before practice |
| S02/S06 → S08/S09 | Distinguish bytes emitted now from code executed later | S08's three-phase timeline; S09's separate compile/runtime traces |
| Library → byte audit | Read hex bytes, simple register moves, CALL/RET, offsets, and virtual addresses | S11 instruction key; S12 cached-TOS invariant; S16–S18 reopen deferred compiler/parser contracts |
| Seed → C compiler | Read the recurring C input; distinguish a C lvalue/type from a Forth value and distinguish builder from target | C01 refresher; C07/C13 make representation and lvalues explicit |
| Compiler → toolchain | Name source/object/executable, symbol/relocation, ABI, host/builder/target, and profile | G01–G05 provide a new contract and a complete numerical two-object example |
| Scalar → variadic/record ABI | Track independent register banks, stack slots, alignment, snapshots, and result lifetime | G04, G10, G12, G15; X87 is deferred explicitly until G15 |
| `cc1` → closed toolchain | Distinguish emitted assembly, a runnable program, a hosted runtime, and a reproducible compiler generation | G20–G25 add downstream production tools, sysroot, lineage, and comparisons |
| Hosted toolchain → kernel | Distinguish a Linux process from bare/privileged entry and distinguish kernel entry from userspace success | K01–K07 must provide a new platform/boot contract; no silent carryover of hosted assumptions |

Exercises inherit these edges. For example, a write-all implementation waits until S09 teaches loops, XOR constructions name their shuffle prerequisites, and full floating variadic exercises wait until the needed class planner exists. Each major mechanism will pair prediction, a causal worked trace, a faded completion task, an independent task, and separate hints/solutions where those forms fit. Changed-width, changed-boundary, and changed-profile problems test meaningful adaptation rather than renamed examples. They are proposed assessments until a reader attempts them.

## Destination ledger

IDs below are stable editorial destinations. Except S01–S03, they are not existing chapter filenames. `entry` means the stated volume entrance; `or equivalent entry bridge` requires an explicit diagnostic/refresher, not an unexplained prerequisite. Semicolon-separated prerequisites are conjunctive. The source column uses canonical chapter IDs; [coverage.csv](coverage.csv) supplies every exact path, immutable link, outcome, edge, migration status, and revision concern.

### Volume 1: Seed and Forth
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| S00 — Why inspect a seed? | entry | Distinguish an inspectable implementation, a compared artifact, and a correctness claim. | 00 | planned |
| S01 — Values and words | entry | Predict a data stack; read stack effects; use explicit literals and a colon-definition contract. | 01 | draft; partial source coverage |
| S02 — Addresses and bytes | S01 | Distinguish a value, its address, and a stored pointer; trace a byte write and HERE update. | 02 | draft; partial source coverage |
| S03 — Bits and subtraction | S01 | Derive and/or from cell-wide nand; trace canonical flags, complement, and subtraction modulo the cell width. | 01, 03, 04 | draft; partial source coverage |
| S04 — Two stacks and reusable shuffles | S01 | Trace over and rot with balanced temporary use of the return stack. | 01, 03, 04, 08 | planned |
| S05 — Comparisons and character classes | S03 | Derive unsigned range checks and state the subtraction-based signed-comparison limit. | 06, 07 | planned |
| S06 — Memory updates and little-endian writers | S02, S03, S04 | Trace +!, -!, ,4, and ,8, keeping cell arithmetic distinct from stored byte order. | 01, 02, 09 | planned |
| S07 — Calling Linux through a contract | S01, S02 | Map seven stack inputs to six syscall arguments and a number; reason about partial I/O and errors. | 05 | planned |
| S08 — Words that create words | S02, S06 | Separate defining constant, creating a constant, and running its result; explain immediate execution. | 10 | planned |
| S09 — Control flow by remembered addresses | S03, S06, S08 | Build and trace forward fixups and backward branches in separate compile-time and runtime states. | 11, A4 | planned |
| S10 — Persistent storage and a classifier | S04, S05, S07, S08, S09 | Use create, variable, defer/is, and byte comparison in a small integrated Forth program. | 12 | planned |
| S11 — From file bytes to an entry point | S02, S06 | Read a small instruction key and trace ELF file offsets into the mapped seed and initial registers. | 13 | planned |
| S12 — The physical stacks and memory operations | S04, S11 | Relate cached TOS and data-stack memory to decoded primitives without confusing the CPU return stack. | 04, 14 | planned |
| S13 — Arithmetic in instruction bytes | S03, S05, S12 | Explain the register effects and encodings of addition, nand, zero test, unsigned division, and multiplication. | 15 | planned |
| S14 — The physical I/O boundary | S07, S12 | Reopen emit/key/syscall6 and identify the seed's input-sentinel and error limitations. | 05, 16 | planned |
| S15 — Dictionary identity and token input | S08, S11, S12, S14 | Trace newest-first lookup, execution tokens, token buffers, and errors; distinguish lookup from an already compiled call. | 10, 17 | planned |
| S16 — Opening the colon compiler | S06, S08, S15 | Trace header creation, compile_call, semicolon, and explicit literal emission into a definition. | 02, 10, 18, A4 | planned |
| S17 — Inline operands and branch returns | S09, S12, S16 | Show return-stack state before and after an inline cell or branch target is consumed. | 11, 19 | planned |
| S18 — Closing the parser and interpreter loop | S13, S15, S16, S17 | Trace decimal parsing, immediate dispatch, and the REPL with the seed's actual number-input rules. | 20 | planned |
| S19 — Seed audit and reader-built capstone | S10, S11, S12, S13, S14, S15, S16, S17, S18 | Account for the complete seed and library mechanisms, trace one reader-built word, and state remaining trust assumptions. | 00, 20, A1 | planned |

### Volume 2: A C Compiler in Forth
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| C01 — Compiler entry and profile contract | S10, S19 or equivalent entry bridge | Read the recurring C example, name its compiler profile, and separate builder execution from generated-program execution. | 21 | planned |
| C02 — Buffers, arenas, and failure ownership | C01 | Follow input and output cursors, allocation lifetime, capacity, and error location. | 21 | planned |
| C03 — Preprocessing regions and includes | C02 | Trace owned include buffers into a flattened source stream. | 22 | planned |
| C04 — Macro expansion and rescanning | C03 | Follow token expansion, argument lifetime, suppression, and nested rescans. | 22 | planned |
| C05 — Conditional preprocessing and profile extensions | C04 | Trace conditional groups, line control, computed includes, and bounded profile-specific behavior. | 22 | planned |
| C06 — Tokens and reversible lookahead | C05 | Decode a token and restore all relevant lexer state after lookahead. | 23 | planned |
| C07 — Types and stable descriptors | C02 | Separate a type encoding from descriptor identity and mutable storage. | 24 | planned |
| C08 — Names and lexical scope | C07 | Trace parallel symbol records, lookup, and scope restoration. | 24 | planned |
| C09 — Instructions inside an executable | C02, S11 | Derive representative instruction bytes, file/virtual addresses, and branch reference points. | 25 | planned |
| C10 — Calls, literals, and deferred addresses | C08, C09 | Resolve forward-call and global-address fixups while tracking data and BSS ownership. | 26 | planned |
| C11 — A bounded legacy runtime | C09, C10, S07 | Explain each shim's supported behavior and deviations from an ordinary libc contract. | 26 | planned |
| C12 — Precedence and short-circuit expressions | C06, C07, C10 | Trace recursive precedence, iterative associativity, and conditional evaluation on the recurring C example. | 27, A4 | planned |
| C13 — Places, values, and delayed loads | C08, C12 | Track an lvalue's identity until a load or store is actually required. | 28 | planned |
| C14 — Postfix, unary, and assignment | C13 | Trace nested assignment and postfix effects while preserving expression metadata. | 28 | planned |
| C15 — Declarations and recursive records | C07, C08, C14 | Parse a declaration, pre-register a recursive record, and distinguish storage duration from visibility. | 29 | planned |
| C16 — Conditions and loops | C09, C12, C15 | Use ownership-scoped fixups for conditional and loop control flow. | 30 | planned |
| C17 — Switches, labels, and nonlocal control | C16 | Trace switch dispatch and goto without confusing their saved control state with a loop's. | 30 | planned |
| C18 — Functions and call-frame accounting | C08, C10, C14, C15, C17 | Trace parameters, nested calls, and frames under the named restricted calling convention. | 31 | planned |
| C19 — Translation units and process entry | C11, C18 | Connect declarations, globals, prototypes, function definitions, and the entry stub. | 31 | planned |
| C20 — The complete compiler and Stage-A comparison | C19 | Follow the complete byte path and identify the exact M1 outputs and inputs compared by Stage A. | 32, A3 | planned |
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
| G08 — Target headers and honest feature probes | G03, C05 | Explain which header branches the actual target selects without claiming unsupported GNU compatibility. | 40 | planned |
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
| `book/A1-32-seed-primitives.md` | R-primitives; S19 | Keep all primitive contracts, code/use sites, internal helpers, and byte budget with Volume 1 |
| `book/A2-memory-map.md` | R-memory | Split by seed, compiler scratch, generated program, native, and direct-GCC ownership/lifetime |
| `book/A3-reproducibility-chain.md` | R-lineage; C20/C22/C24; G25; K08 | Preserve every existing lineage and comparison; add the direct-GCC ending separately; keep kernel lineage pending |
| `book/A4-worked-exercises.md` | R-solutions; S09/S16/C12 | Retain the three existing worked mechanisms, repair their premises/setup, and distribute expanded feedback by objective |
| `book/A5-further-reading.md` | R-reading | Preserve purpose-based routes with durable primary links and explicit versions |
| `book/A6-c-subset.md` | R-c-subsets | Give legacy, native TinyCC, and direct-GCC their own accepted/rejected/bounded contracts |
| `book/A7-error-codes.md` | R-errors | Preserve phase/profile-scoped diagnostics and map a failure back to the responsible check |
| `book/CONCEPTS.md` | N-concepts | Replace stale source-order graph with first-use, revisit, and actual prerequisite edges |
| `book/GLOSSARY.md` | N-glossary | Synchronize definitions with the profile and chapter that teaches them |
| `book/LEARNING_STORY_PLAN.md` | N-editorial | Carry forward useful outcome/trace goals; do not import obsolete rollout statuses |
| `book/README.md` | N-reading | Provide current entrances, independent outcomes, and honest completion status |
| `book/SUMMARY.md` | N-reading | Link existing text and visibly distinguish future units |
| `book/WORD-INDEX.md` | N-source | Preserve exact symbol-to-source navigation and generate new teaching links from explicit edition inputs |
| `book/WRITING.md` | N-editorial | Keep canonical tangle ownership separate from new-edition annotation/excerpt rules |
| `book/where-this-fits.md` | S00; R-lineage | Preserve historical context while narrowing correctness and lineage claims |
| `book/playground.fth` | R-playground | Retain by pinned link as an optional compatibility profile, with exact limitations |

## The first milestone's remaining coverage debt

| Canonical chapter | Covered by the pilot | Explicitly still owed |
|---|---|---|
| 01, stacks and words | S01's stack/cell model, explicit literals, and word/colon contracts | Return-stack implementation of `over`, complete shuffler family, full source walkthrough, environment-specific practice |
| 02, emission and HERE | S02's byte/cell/address distinction, pointer storage, and `c,` trace | Inline-literal implementation behind the contract, complete emission family, byte audit, old exercise reconciliation and execution checks |
| 03, logic | S03's nand, and/or derivations, flags, and complement | Optional XOR/named-helper constructions and their shuffle-dependent practice; complete old exercise reconciliation and execution checks |
| 04, return stack and subtraction | S03's subtraction model and operand order | Two-stack mechanism, balance, `over`, emitted-size tradeoff, and remaining practice |

All other canonical chapters and appendices remain planned replacement coverage. The new root reader/evidence/learning-path documents supply partial navigation and editorial coverage; they do not replace the complete old concept index, symbol index, or advanced profile reference. Related concepts in a pilot do not mark Chapters 09, 14, 15, 18, 20 or Appendix A migrated: their implementation and reference outcomes are separate debts. The first three chapters also do not establish a reusable teaching environment or verify the optional gforth route.

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

If source annotation changes are later authorized, propose them separately: exact target, educational reason, effect on generated sources, and verification needed. A manuscript-only rewrite does not authorize implementation repairs. Existing static concerns such as long-double alignment, macro lookahead, and linker close-state handling remain qualified concerns until the corresponding source behavior is checked; they are not execution failures observed here.

Changes propagate through dependencies. A cell-width change reaches number examples, masks, memory maps, instruction encodings, solutions, and ABI explanations. A descriptor change reaches glossary, parser traces, field/array examples, recaps, and practice. A moved unit reaches first-use terms, prerequisite edges, next/previous navigation, index, and solutions. A profile or endpoint change reaches volume entrances, source links, run instructions, evidence ledgers, and trust claims.

Before calling a mapped source chapter fully covered, check all of its mechanisms and limitations, source correspondence, worked traces, exercise premises, hints/solutions, recap, glossary/index references, and downstream prerequisites. Before calling its examples executed, retain the exact commands, inputs, environment, outputs, and failures. Before calling the book independently learnable, obtain appropriate reader evidence; an editorial map or expert read-through cannot establish that result.
