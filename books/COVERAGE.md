# Coverage and learning-dependency map

This is the editorial map for a new teaching edition in `books/`. It does not replace the canonical literate `book/` tree or change its sources. Four volumes are a **provisional editorial structure**: Seed and Forth, A C Compiler in Forth, From Compiler to Closed Toolchain, and Kernels and Linux.

**Edition:** `direct-gcc-overlay`, commit `7d7e1996d1753118181d43e1a413960d3a1ec24b`, inspected October 6, 2026. All source destinations in [coverage.csv](coverage.csv) are pinned to that commit. A floating branch name is not an edition identifier.

The current paper draft now adds [the H1/H2 paper entrance](FIRST-RESULTS.md) and [G01: a program from two files](gcc-toolchain/chapters/01-a-program-from-two-files.md). G01 is a complete bounded profile entrance; its bounded source/practice and model-assisted prerequisite reviews are complete. The earlier reviewed C01–C20 checkpoint extended through C22. C21/C22 are source/practice-reviewed paper drafts, with 22 new main exercise/feedback sets and complete standalone-assembler coverage. Execution, rendered-layout review and actual-reader outcomes remain unverified. C20 has eight complete exercise/feedback sets and all 33 recipe regions have teaching homes; its source/practice review and final readback are complete. C16–C19 technical/practice manuscript reviews and the sixth mixed-check source review are complete; C16–C18 also received first-reading flow review. These are source/manuscript checks, not execution or human-reader validation. [Earlier continuation-draft notes](c-compiler/DRAFTS.md) preserve the preceding checkpoint history.

## Main capability route and complete coverage

The [hybrid narrative](HYBRID-NARRATIVE.md) and [unit-by-unit route map](narrative-map.csv)
add a main route through five capabilities: **H1 Forth result → H2 simple C
ELF → H3 objects/System V/link/runtime → H4 generators/GCC/output tools →
H5 hosted closure/rebuild**. H labels organize first sessions and future
fixtures; they do not add to the 77 stable unit IDs. FIRST-RESULTS now supplies
the H1/H2 paper bridge and G01 drafts the bounded H3 entrance; operational
setup and observed fixtures remain pending. The currently written S/C chapters, all exercises and source homes
remain intact.

The unit graph below governs complete implementation/reference work and its
depth exercises. The narrative map separately states which contracts a first
session teaches or supplies. H2 therefore uses C01's profile contract and
C19's early whole-program story without requiring the whole C implementation
first. S11–S19 remain a complete source-byte audit with its own earned
capstone; moving that audit to depth does not reduce its learning objective.
Existing mixed checks still require their actual mechanisms.

The direct-GCC main route now enters the drafted G01 from the C19
builder/target capability and a locally supplied direct-profile bridge. M2/M1/hex2, pnut and private-ABI TinyCC
remain alternate executable routes, with their full teaching and lineage
obligations preserved. A short C20/C22 comparison case illustrates dependency replacement; the
full M2/assembler lab is optional for the main route. Shared native/LP64 declarations and initializer traversal are
still required mechanisms in direct GCC: G01 states their interface roles,
and the planned deeper homes below retain their implementations.

Every milestone must distinguish required production inputs, temporarily
supplied teaching components, comparison controls and optional routes. An
unopened implementation can remain a real production dependency. Host shell,
Python, make, text tools, Linux and source acquisition retain their actual
recipe roles. The narrative is a plan: new setup/fixture execution and
representative-reader validation remain outstanding.

## Current result

**Volume 1, Seed and Forth, has a complete draft teaching path.** Its [opening](seed-forth/chapters/00-why-inspect-a-seed.md), [route guide](seed-forth/chapters/00-start-here.md), chapters S01–S19, separate feedback, six mixed return checks and [compact reference](seed-forth/REFERENCE.md) cover the seed and its first library. The [audit ledger](seed-forth/source-audit.csv) assigns an explanation to all **76 regions / 1,772 original file bytes**, including all 32 dictionary headers. All **63 library colon definitions and 11 constant-created names** have substantive teaching homes.

The [S19 capstone](seed-forth/chapters/19-audit-synthesis-and-capstone.md) derives a fresh 32-byte `inc` entry and its predicted stack/control behavior. Those are predicted **process-memory bytes**, not an observed execution or additional bytes in the original seed file. The hand-encoded native Forth colon compiler is distinct from the **C compiler written in Forth**. Volume 2 now has drafted chapters C01–C22, reaching the default compiler, a complete predicted process-entry path, the Stage-A recipe/evidence story and the complete bounded Forth assembler with its source-built-tool handoff; the remainder of that volume, G02–G25 and Volume 4 remain planned. Volume 3 now has its bounded G01 entrance draft. No complete C-compiler, toolchain or kernel manuscript, or newly verified chain, is claimed.

Draft completeness is a teaching-coverage claim. The new examples have not been executed, the fresh-reader installation route has not been tested, and no real-reader learning validation, universal correctness proof, or security proof is claimed. The first volume supports source reading and paper derivation under its explicit Linux/x86-64, storage, input and call assumptions. It links the pinned build entry without presenting that link as a tested setup tutorial.

The [C-volume entrance](c-compiler/README.md) leads through [C01: the compiler/profile contract](c-compiler/chapters/01-compiler-entry-and-profile.md), [C02: buffers, arenas and failure](c-compiler/chapters/02-buffers-arenas-and-failure.md), [C03: preprocessing regions and includes](c-compiler/chapters/03-preprocessing-regions-and-includes.md), [C04: macro expansion and rescanning](c-compiler/chapters/04-macro-expansion-and-rescanning.md), and [C05: conditionals and profile extensions](c-compiler/chapters/05-conditionals-and-profile-extensions.md). 

The representation route continues with [C06: tokens and lookahead](c-compiler/chapters/06-tokens-and-lookahead.md), [C07: types and stable descriptors](c-compiler/chapters/07-types-and-stable-descriptors.md), and [C08: names and lexical scope](c-compiler/chapters/08-names-and-lexical-scope.md). The emission route adds [C09: instructions inside an executable](c-compiler/chapters/09-instructions-inside-an-executable.md), [C10: calls, literals and deferred addresses](c-compiler/chapters/10-calls-literals-and-deferred-addresses.md), and [C11: a bounded legacy runtime](c-compiler/chapters/11-a-bounded-legacy-runtime.md). 

The parser route now continues through [C12: places and delayed loads](c-compiler/chapters/12-places-values-and-delayed-loads.md), [C13: precedence and short-circuiting](c-compiler/chapters/13-precedence-and-short-circuit.md), [C14: expressions and constant evaluation](c-compiler/chapters/14-expressions-and-constant-evaluation.md), and [C15: declarations and recursive records](c-compiler/chapters/15-declarations-and-recursive-records.md). Twenty-four C feedback companions support **187 C chapter exercises**; together with the seed volume, the seed/C routes retain **282 main exercises**. G01 adds seven, for **289 chapter exercises** overall; the four H1/H2 entrance prompts are separate. Mixed return-check questions are counted separately. Six mixed checks revisit the C route: [source and storage](c-compiler/practice/return-check.md), [macros and source identity](c-compiler/practice/return-check-2.md), [restoring the right state](c-compiler/practice/return-check-3.md), [bytes, patches and runtime results](c-compiler/practice/return-check-4.md), [one spelling, different consumers](c-compiler/practice/return-check-5.md), and [where this path finishes](c-compiler/practice/return-check-6.md). Each contains four questions, for 24 C mixed questions. The source ledgers account for all 57 preprocessor regions and **576 colon definitions across fourteen compiler/assembler files**. The parser ledger retains 333 declarations; the new control/function/program ledger has **170 rows: 160 declarations plus ten top-level forms**. C20 explains the exact standalone Stage-A recipe and its separately attributed result; C21/C22 explain the standalone assembler; C23/C24 draft the alternate direct TinyCC profile, its initializers and runtime, and the recipe's attributed fixed point as unreviewed paper chapters.

The integrated route adds [C16: conditions and loops](c-compiler/chapters/16-conditions-and-loops.md), [C17: switches and labels](c-compiler/chapters/17-switches-labels-and-nonlocal-control.md), [C18: functions and frames](c-compiler/chapters/18-functions-and-call-frame-accounting.md), and [C19: translation units and process entry](c-compiler/chapters/19-translation-units-and-process-entry.md). C19 derives a 556-byte output-buffer layout for `int main(void){return 7;}` and a conditional exit-value trace. This is a predicted artifact, not a stored-file observation, program execution or Stage-A comparison.

[C20: the complete compiler and Stage-A comparison](c-compiler/chapters/20-complete-compiler-and-stage-a.md) follows the produced M2-Planet executable through its next compilation, then identifies the two compared M1 text files. Its [eight feedback sets](c-compiler/practice/20-solutions.md) and [pipeline map](c-compiler/pipeline-map.csv) explain producer/input/output ownership and evidence limits. The map partitions **273 lines into 33 regions across five shell scripts**; these recipe regions are separate from the 576 Forth definitions. All 33 regions have substantive teaching homes. Source/practice review and final readback are complete; the new examples remain unexecuted.

[C21: assembler input and expansion](c-compiler/chapters/21-assembler-input-and-expansion.md) derives an exact intermediate text; [C22: two-pass assembly and bootstrap handoff](c-compiler/chapters/22-two-pass-assembly-and-bootstrap-handoff.md) places names, emits bytes and distinguishes the handoff comparisons. Their [ten](c-compiler/practice/21-solutions.md) and [twelve](c-compiler/practice/22-solutions.md) feedback sets accompany a [42-region ledger](c-compiler/assembler-regions.csv) covering all **785 lines, 99 declarations and two initialization forms** of `130-asm.fth`. Its 50 colon definitions are included in the 576-definition total. The new seven-byte fragment and supplied-header 148-byte fixture are paper derivations.

## The drafted first-results and G01 entrances

[Two small results](FIRST-RESULTS.md) supplies the H1 stack/output request and
byte-store bridge, the H2 C/function/entry primer, and C19's supplied 556-byte
layout/patch problem. Its [four feedback sets](practice/first-results-solutions.md)
are entrance practice, additional to the chapter exercise inventory.
Operational seed setup, reset/capture instructions and observed runs remain
pending.

[G01](gcc-toolchain/chapters/01-a-program-from-two-files.md) follows a declared
`answer()` across two translation units, one unfinished CALL, a stable
object-symbol/relocation contract, a linker's illustrative relative field
and an absolute-pointer contrast. It distinguishes LP64, System V, ET_REL,
Forth cells and machine-value carriers. Its actual startup story includes
eager `start.o`, C-built `startup.o`, `environment.o` and lazy `libseed.a`;
its selected ordinary scalar call uses the final `131` provider. The seven
[exercise/feedback sets](gcc-toolchain/practice/01-solutions.md) test those
bounded contracts. Bounded source/practice and model-assisted prerequisite reviews are complete.

The full object writer, declaration/initializer traversal, call/frame planner,
linker, runtime and archive mechanisms remain G02–G17 obligations. G01's
source-derived command card and predicted exit seven are unexecuted; no
actual object size, field offset, symbol-table index, function length or
complete archive-member selection is supplied. Current checks cover **71
pinned project blobs**, while the definition inventory is now
**617 definitions across seventeen files** after C23/C24 added `117`–`119`. Inspecting three extra source files is not a complete-module
coverage claim.

## How to read coverage and evidence

[coverage.csv](coverage.csv) is the exact source crosswalk: one row for every original prologue/numbered chapter, appendix and navigator, plus the supporting implementation/closure records. Its live columns contain current scope and actual remaining obligations. Earlier milestone snapshots stay in revision history rather than being repeated as stale scope columns.

The exact `migration_status` vocabulary is:

- `draft_covered`: all substantive teaching mechanisms of the mapped item are represented in draft. This does not require identical wording, the original narrative order, or copying every optional exercise one-for-one
- `partial`: some mapped teaching or reference content exists, but an explicit part remains elsewhere or unwritten
- `planned`: a home and prerequisites are assigned, but replacement teaching content is not yet drafted

`rewrite_concern` preserves the source issue or editorial policy behind a choice; `remaining_scope` is the authoritative list of what is still owed. These are migration states, **not test results**. `evidence_status` separately distinguishes pinned source inspection, manual derivation, static disassembly, recorded CI and the unexecuted new examples. A complete draft can still require editorial revision, execution and reader testing. Optional legacy extensions are listed as supplementary work where they remain useful; they do not turn represented core mechanisms back into unexplained ones.

The inventory retains **50 prologue/numbered chapters (00–49), seven appendices (A1–A7), eight Markdown navigators/editorial files, and `playground.fth`**: 66 original items. Twenty-five additional records cover the seed, library, compiler infrastructure through statement/function/program/driver sources, the standalone assembler, five Stage-A recipe scripts, direct-GCC closure documentation, sorting, and historical route context, for **91 source rows**. That source-row count is independent of the 77-unit editorial graph. No original source item is silently dropped.

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
| `976f5a5fadbf49285ae800f61e217931a4848903` | [37432365973](https://github.com/delta9000/seed-forth/actions/runs/37432365973) |
| `4ba55cabf64894a0a4b41149495ff04fb66006de` | [37436370123](https://github.com/delta9000/seed-forth/actions/runs/37436370123) |
| `764bdc4f4902d613145f361da6a7f33010dd37b4` | [37474668625](https://github.com/delta9000/seed-forth/actions/runs/37474668625) |
| `945282917f45cebf9e04d86492e7a64ef50393a8` | [37478538502](https://github.com/delta9000/seed-forth/actions/runs/37478538502) |
| `0b7b2bd3fc64f2746249ac5194abf1506328fc0e` | [37492966101](https://github.com/delta9000/seed-forth/actions/runs/37492966101) |

Native instruction listings were also checked by bounded GNU objdump 2.44 disassembly of source-decoded bytes. A static decoder reads the byte stream as data; that observation is not a running-seed trace. Manual predictions remain predictions until their exact inputs and environment are executed and recorded.

## Four books with independent outcomes

1. **Seed and Forth (`seed-forth`)**: begin with small stack programs, make bytes and state visible, construct a useful library, and then open the full 1,772-byte seed. The draft now finishes with a reader-built paper capstone, complete source/byte explanations and a precise statement of the trusted Linux/CPU/input boundary
2. **A C Compiler in Forth (`c-compiler`)**: enter with a pinned seed/library or an equivalent refresher; follow one C program through buffers, preprocessing, tokens, types, emitted instructions, and execution. Use the early default-compiler result on the main route; retain complete implementation depth, the M2-Planet comparison/Forth-assembler branch and a distinctly labeled direct TinyCC alternate track
3. **From Compiler to Closed Toolchain (`gcc-toolchain`)**: enter through the drafted [G01 two-file story](gcc-toolchain/chapters/01-a-program-from-two-files.md), retrieving the C19 capability and direct-profile bridge. It explicitly supplies the needed frontend/provider interfaces while retaining their complete mechanisms in the later depth units. Build the conceptual path through objects, ABI, runtime, generators, `cc1`, binutils, hosted musl/libgcc, and the recorded GCC 4.0.4 fixed point
4. **Kernels and Linux (`kernels-linux`)**: begin from an explicitly identified direct-chain toolchain. The proposed finish is a newly evidenced kernel/Linux path with a chosen user-visible acceptance criterion. The current direct-GCC-to-Linux outcome is **pending**, and the technical route and scope still require their own pinned source inventory

An independent volume needs an entry artifact, how to obtain or rebuild it, a short prerequisite diagnostic/primer, local references, explicit trusted interfaces, and an outcome it actually finishes. Volume 1 now supplies its source pin, entry assumptions, paper route and local reference; a tested execution/setup route remains outstanding. Volume 2 now supplies its contract bridges, profile comparison, source-to-predicted-program route, Stage-A recipe/evidence account, complete bounded assembler and source-built handoff, and local source maps; its later teaching and tested setup remain outstanding. Volume 3 now supplies the bounded G01 paper entrance; its operational setup and remaining depth are owed. Volume 4's entry package remains planned. Readers may use a pinned entry artifact without redoing every earlier derivation, while an audit route follows its full provenance.

## Learning order is not source order

The source files remain authoritative and unchanged. The new order follows what a reader must be able to do next:

- Stack effects and the explicit-literal contract precede pointer arithmetic. Byte, cell, address, and stored pointer are separate ideas before `HERE` is changed
- Bit patterns and wraparound precede signed interpretations and range checks. A small-width drawing must say it illustrates a 64-bit operation; it must not silently replace the machine's width
- Subtraction can be derived without first explaining the CPU return stack. `over` and `rot` wait for a proper two-stack trace
- A word's operational contract may be used before its implementation is opened. Every such deferral names the later unit that discharges it
- Dictionary-emission idioms precede the full ELF/encoding audit. S08 supplies the small header, immediate-dispatch, CALL, literal, and push-body contracts it uses locally; the machine-code pass then derives the complete seed account
- The compiler's internal data stack/registers, generated program's registers, private TinyCC ABI, and direct-GCC System V ABI are distinct machines and profiles
- In the toolchain book, scalar argument planning and floating representation move before the variadic/aggregate cases that use them. Ranked arrays stay with type identity; archive order stays with linking

The numbering below preserves editorial/source-navigation IDs. The capability route can select earlier first sessions under named supplied contracts; it does not require altering file load order. Compiler startup still follows the actual loader contract, including the executing main layer last. Canonical chapter numbers remain source IDs, not new chapter numbers.

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
| C02/C07 → C09 | Keep output pointers, file offsets, target addresses, widths and type-selected storage separate | C09 supplies a local instruction/ELF bridge; the seed physical audit is optional background, not an S11 prerequisite |
| C02/C06/C07/C08/C09 → C10 | Distinguish valid patch fields, decoded strings, symbol head cells and target values | C10 opens the complete call/address/global/string patch lifetimes with bounded consumer excerpts; full parser/function/driver policy remains later |
| C09/C10 → C11 | Distinguish a Linux request from actual progress and a generated call from builder execution | C11 supplies local request/result and register contracts; C02 and S07 are targeted refreshers for those contracts |
| C06/C07/C08/C09/C10 → C12 | Track tokens, type/descriptor state, resolved names and emitted-address conventions | C12 supplies primary/literal-index bridges and the place/value model before binary parsing; C15 later constructs the local/declaration premises |
| C06/C09/C10/C12 → C13 | Keep token replay, byte/fixup ownership and operand materialization separate | C13 supplies unary-operand/assignment-arm contracts, then precedence, association and runtime short-circuit/ternary skeletons; C14 completes the recursive grammar |
| C06/C10/C12/C13 → C14 | Track parser recursion, call/fixup ownership, generated state and pending destinations | C14 opens full postfix/unary/assignment/comma behavior, the 110 cast/type-query handshake and constant/evaluator closure; its local type-query contracts avoid a backwards C15 prerequisite |
| C06/C07/C08/C12/C14 → C15 | Reuse token ownership, descriptors, symbols and the type-query/expression mechanisms | C15 constructs declarations and completely explains local switch-unwind/return definitions; C17 now opens switch creation/exit policy and C18 now integrates whole default frames, with later native providers still separate |
| C06/C09/C10/C13/C15 → C16 | Track pending tokens, branch-field origins, lists and expression/declaration consumers | C16 supplies its recursive statement and switch-depth contracts locally; C17 opens the remaining switch/label clients |
| C06/C09/C10/C14/C15/C16 → C17 | Separate emitted selection, saved-register obligations and lexical ownership | C17 explains the complete local switch/label/goto machinery, including LP64 trampoline creation and legacy limitations |
| C06/C08/C09/C10/C14/C15/C16/C17 → C18 | Join source names, slot allocation, emitted calls and nested control obligations | The first call story retrieves C09/C14 and supplies its coordinates; later reference sessions open complete 114 ownership |
| C02/C06/C08/C09/C10/C11/C14/C15/C18 → C19 | Distinguish builder metadata, output bytes, target state and completion events | The first story supplies its entry/layout bridge; later sessions complete enums, typedefs, prototypes, globals, registration and the executing final file |
| C19 → C20 | Distinguish a complete paper derivation from observed artifacts and comparisons | C20 supplies the producer/artifact and shell-reading bridge, three exact input lists, physical output path, M1 comparator and bounded recorded evidence |
| C02/C06 contracts → C21 | Distinguish text characters, bytes, borrowed slices, cursor state and Forth storage operations | C21 supplies the Forth storage/byte bridge locally; S10 is an equivalent optional refresher, not a mandatory seed-volume reread |
| C20/C21 → C22 | Preserve expanded text, distinguish address roles and name each producer/artifact | C22 supplies field-end arithmetic and little-endian/range contracts, then separates supplied ELF input, assembly-route equality and later fixed points |
| C19 capability → direct toolchain | Distinguish builder/target, then acquire object/symbol/relocation, LP64, System V and selected-provider contracts | G01 now supplies the bounded two-object/profile bridge; G02/G04/G05/G06 retain complete implementation depth without requiring the TinyCC or M2 executable route |
| Scalar → variadic/record ABI | Track independent register banks, stack slots, alignment, snapshots, and result lifetime | G04, G10, G12, G15; X87 is deferred explicitly until G15 |
| `cc1` → closed toolchain | Distinguish emitted assembly, a runnable program, a hosted runtime, and a reproducible compiler generation | G20–G25 add downstream production tools, sysroot, lineage, and comparisons |
| Hosted toolchain → kernel | Distinguish a Linux process from bare/privileged entry and distinguish kernel entry from userspace success | K01–K07 must provide a new platform/boot contract; no silent carryover of hosted assumptions |

Exercises inherit these edges. For example, a write-all implementation waits until S09 teaches loops, XOR constructions name their shuffle prerequisites, and full floating variadic exercises wait until the needed class planner exists. Each major mechanism will pair prediction, a causal worked trace, a faded completion task, an independent task, and separate hints/solutions where those forms fit. Changed-width, changed-boundary, and changed-profile problems test meaningful adaptation rather than renamed examples. They are proposed assessments until a reader attempts them.

## Destination ledger

IDs below are stable editorial destinations for full-depth prerequisite work; [narrative-map.csv](narrative-map.csv) separately records first-session contracts. S00–S19, C01–C24 and G01 have drafted manuscripts: 45 drafted and 32 planned units in the 77-unit graph. G02–G25 and all K units remain planned. C23/C24 are unreviewed drafts. G01 bounded source/practice and model-assisted prerequisite reviews are complete. C19's full technical/practice manuscript review is complete; unit manuscript state is separate from review and execution state. `entry` means the stated volume entrance; an equivalent entry bridge requires an explicit diagnostic/refresher, not an unexplained prerequisite. Named local bridges are required contracts supplied in that unit; their targeted refresher links are alternative ways to acquire those contracts. Listed prerequisites are conjunctive, with semicolons used in the CSV. The source column uses canonical chapter IDs; [coverage.csv](coverage.csv) supplies every exact path, immutable link, outcome, edge, migration status, and revision concern.

### Volume 1: Seed and Forth
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| S00 — Why inspect a seed? | entry | Explain the seed-local outcome, public provenance and trust/evidence boundaries; distinguish the later planned volumes. | 00, A3 | drafted |
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
| S19 — Seed audit and reader-built capstone | S11, S12, S13, S14, S15, S16, S17, S18 | Reconcile all 76 regions/1772 file bytes; derive the 32-byte inc runtime entry and state the remaining evidence and trust boundaries. | 00, 20, A1, A3 | drafted |

### Volume 2: A C Compiler in Forth
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| C01 — Compiler entry and profile contract | entry: local Forth-contract bridge | Derive tri.c's requested output, name its profile and load order, and separate the builder, emitted image and generated-program execution. | 21, A6 | drafted |
| C02 — Buffers, arenas, and failure ownership | C01, local library-contract bridge | Trace all 35 arena/I/O definitions through spans, cursors, capacity, allocation lifetime, output patching, workspace selection and failure limits. | 21, A2, A7 | drafted |
| C03 — Preprocessing regions and includes | C02 | Trace nested literal includes, shared sinks, retained newlines, bounded search paths and live storage; name deferred macro/conditional/location mechanisms. | 22, A2, A6, A7 | drafted |
| C04 — Macro expansion and rescanning | C03 | Derive stored macro recipes, raw/expanded argument lifetimes, substitution and rescans; distinguish busy state, token unavailability and tail calls. | 22, A2, A6, A7 | drafted |
| C05 — Conditional preprocessing and profile extensions | C03, C04, local evaluator/profile contracts | Trace conditional selection, computed headers, physical/logical locations, continuation rules and independent profile/reset gates while preserving evaluator lifetime. | 22, A2, A6, A7 | drafted |
| C06 — Tokens and reversible lookahead | C02, C05 | Derive valid token payloads and byte endpoints; distinguish replay from eight-cell rollback and retained spelling from decoded values across all 39 lexer definitions. | 23, A2, A6, A7 | drafted |
| C07 — Types and stable descriptors | C02, local bit/type/token contracts | Pack types, preserve literal identity and profile sizes, trace stable headers and growing tables, and use named aggregate/array producer contracts across all 52 definitions. | 24, A2, A6, A7 | drafted |
| C08 — Names and lexical scope | C02, C06, C07 | Trace all 19 symbol definitions: parallel records, namespace selection, scope-count restoration, metadata/fixup heads and qualifier lifetime. | 24, A2, A7 | drafted |
| C09 — Instructions inside an executable | C02, C07, local instruction/ELF bridge | Derive integer instruction bytes, frame/branch coordinates, typed widths and every field of the 120-byte ELF envelope under bounded contracts. | 25, 26, A2, A7 | drafted |
| C10 — Calls, literals, and deferred addresses | C02, C06, C07, C08, C09 | Stage restricted calls; complete function/address/global/string patch lifetimes, decoded literals and data/BSS placement with separate owners and completion events. | 25, 26, 28, 30, 31, A2, A6, A7 | drafted |
| C11 — A bounded legacy runtime | C09, C10, local Linux I/O contract | Trace all sixteen runtime emitters/nineteen callable names, request/result units, heap state and memory bounds without claiming hosted-libc equivalence. | 26, 31, A2, A6, A7 | drafted |
| C12 — Places, values, and delayed loads | C06, C07, C08, C09, C10, local primary/literal-index contracts | Track all nine metadata cells/five kinds, local/global/function/field/index producers, publication and materialization, with exact default/provider boundaries. | 28, A2, A6, A7 | drafted |
| C13 — Precedence and short-circuit expressions | C06, C09, C10, C12, local unary-operand/assignment-arm contracts | Trace runtime operator tables, precedence and association, logical/conditional fixups and the complete local LP64 binary pipeline. | 27, 28, A2, A4, A6, A7 | drafted |
| C14 — Postfix, unary, assignment, and evaluator closure | C06, C10, C12, C13, local type-query contracts | Complete postfix/call/unary/update/assignment/comma parsing, casts/sizeof and typed local branches; derive constant evaluation and exact successful PP reader restoration. | 27, 28, 29, A2, A6, A7 | drafted |
| C15 — Declarations and recursive records | C06, C07, C08, C12, C14, local switch/return contracts | Construct local/static/array/record/function-pointer declarations, close recursive-identity and missing-forward boundaries, and explain every local unwind/return branch without claiming later integration. | 29, 30, A2, A6, A7 | drafted |
| C16 — Conditions and loops | C06, C09, C10, C13, C15, local statement/switch contracts | Trace recursive if ownership, while/do/for destinations, exact step replay and dispatcher boundaries while separating builder state from generated paths. | 30, A2, A6, A7 | drafted |
| C17 — Switches, labels, and nonlocal control | C06, C09, C10, C14, C15, C16 | Reconstruct switch selection/fallthrough/cleanup, label identity and workspace, commit-on-colon lookahead, and separate legacy versus LP64 goto completion. | 29, 30, A2, A6, A7 | drafted |
| C18 — Functions and call-frame accounting | C06, C08, C09, C10, C14, C15, C16, C17 | Join definition publication, parameter records/spills, fixed frames, full call/return and scope lifetimes; distinguish balanced calls from actual alignment and later native providers. | 29, 31, A2, A6, A7 | drafted |
| C19 — Translation units and process entry | C02, C06, C08, C09, C10, C11, C14, C15, C18, local entry/driver contracts | Derive full default translation-unit construction, global/name completion and a predicted 556-byte image/exit path while distinguishing buffer, write, load, execution and bootstrap evidence. | 31, 32, A2, A6, A7 | drafted |
| C20 — The complete compiler and Stage-A comparison | C19 | Reconstruct both compiler producers, the three ordered input lists, physical output paths and exact M1 comparison; bound static, historical and observed evidence. | 00, 32, A3 | drafted |
| C21 — Assembler input and expansion | C02, C06, local Forth storage/byte contracts | Derive exact expanded text, borrowed-slice lifetimes, cursor/capacity behavior and narrow quote/number/definition contracts; preserve unresolved fields for assembly. | 33, A2, A7 | drafted |
| C22 — Two-pass assembly and bootstrap handoff | C20, C21 | Derive label positions, six field forms and emitted bytes; preserve pass invariants, supplied ELF input and output limits; identify each source-built-tool comparison. | 32, 33, A2, A3, A7 | drafted |
| C23 — The direct TinyCC profile | C15, C18, C19, local producer/profile bridge | Separate LP64 object layout and private stack calls from the legacy compiler and System V target. | 34 | drafted |
| C24 — TinyCC initialization, runtime, and closure | C23, local source/generation/comparison bridge | Track prepared-source provenance, initializers, bounded seed runtime, rebuilt TinyCC, and its specific fixed-point comparison. | 32, 34, A3 | drafted |

### Volume 3: From Compiler to Closed Toolchain
| ID and unit | Prerequisites | Observable outcome | Canonical source | Status |
|---|---|---|---|---|
| G01 — A program from two files | C19, local direct-profile bridge | Follow declaration/use through one object relocation and illustrative link; distinguish LP64/System V/ET_REL, selected scalar result/alignment, real startup/runtime/archive inputs and unexecuted evidence. | 34, 35, 36, 37, 38, 44, A2, A3, A6, A7 | drafted |
| G02 — Objects, symbols, and relocation records | G01 | Trace section bytes, stable symbol identities, BSS, and a relocation before placement is known. | 35 | planned |
| G03 — Signatures, declarators, and ranked arrays | G02, C07, C15 | Open shared 115 native declarations and selected 118 initializer structure alongside type/signature identity, symbols, pointer shapes and ranked arrays. | 34, 36, 47 | planned |
| G04 — A shared scalar argument planner | G03, C18 | Assign integer arguments and results, protect temporaries, and account for stack alignment at every call. | 34, 36, 48 | planned |
| G05 — Linking independently built objects | G02 | Validate, resolve, place, relocate, and publish a bounded ELF link with a complete numerical example. | 37 | planned |
| G06 — Raw syscalls, startup, and runtime control | G04, G05 | Trace the C-to-Linux bridge, errno, entry, and separately specified frame/nonlocal-return helpers. | 38 | planned |
| G07 — Source-built allocation and byte operations | G06 | Follow allocation extents, failure preservation, memory/string operations, and mapped/process interfaces. | 39 | planned |
| G08 — Target headers and honest feature probes | G03, C05 | Explain target predefines, selector hooks and which header branches they select without claiming unsupported GNU compatibility. | 40 | planned |
| G09 — Typed constants and symbolic addresses | G03, G02, C14 | Trace shared 118 initializer traversal into selected static constant/relocation providers; distinguish it from executable runtime queues and preserve unevaluated-branch contracts. | 34, 41 | planned |
| G10 — Floating values and conversion | G04, G09 | Separate payload transport, numeric conversion, storage width, and floating arithmetic. | 45 | planned |
| G11 — Decimal literals rounded once | G10 | Convert an exact decimal ratio to binary64 with rounding and subnormal boundary cases. | 46 | planned |
| G12 — Variadic cursors and argument classes | G04, G10 | Walk an interleaved register/overflow argument list; defer X87 details explicitly until G15. | 42 | planned |
| G13 — Streams and bounded formatting | G07, G12 | Trace stream position, partial-object I/O, sticky errors, and supported integer formatting. | 43 | planned |
| G14 — Bitfield layout and preserving stores | G03, G09, C12 | Trace allocation, promotion, extraction, and writes that preserve neighboring bits. | 47 | planned |
| G15 — Aggregate values and X87 transport | G04, G10, G12, G14 | Assign record arguments/results with register rollback, snapshots, hidden returns, and explicit alignment limits. | 42, 48 | planned |
| G16 — Indexed archives and lazy extraction | G02, G05 | Trace selection to a fixed point within one archive and explain command-line ordering. | 44 | planned |
| G17 — Frozen driver, configure, and source census | G05, G07, G08, G09, G11, G13, G15, G16 | Separate source capture, cache identity, configure observations, and Makefile-selected compilation work. | 49 | planned |
| G18 — Source generators must have builders | G17 | Track oyacc, Heirloom lex, flex, and GCC generators with source preparation and production/oracle separation. | 49 | planned |
| G19 — The cc1 milestone and its tests | G18 | Explain declaration failures despite successful linking and scope execution-torture evidence using host output tools. | 49 | planned |
| G20 — Building the downstream binutils | G18 | Connect regenerated parser/scanner inputs to Forth-built assembler/linker tools and their retained reports. | gcc-direct/README.md | planned |
| G21 — A freestanding GCC driver toolchain | G19, G20 | Follow driver, cc1, as, and ld invocation provenance through a no-libc executable. | gcc-direct/README.md | planned |
| G22 — Hosted closure with libgcc and musl | G21 | Follow the sysroot, runtime libraries, startup objects, and a hosted program built by Stage C. | gcc-direct/README.md | planned |
| G23 — Rebuild lineage and controlled paths | G22 | Identify who builds GCC stages 2, 3, and 4 and hold embedded-path inputs constant. | gcc-direct/README.md | planned |
| G24 — Equal sort keys and unequal bytes | G23 | Explain why legal qsort tie ordering can change generated bytes and how the recorded runtime change affects the comparison. | runtime/gcc-seed/SORT.md | planned |
| G25 — Fixed-point evidence and toolchain capstone | G24 | Read file/member comparisons, retain provenance and assumptions, and distinguish recorded equality from general correctness. | A3 | planned |

### Shared direct-route mechanisms and alternate profiles

C23 now retrieves C15/C18/C19 plus a local producer/profile bridge. C24
retrieves C23 plus a local source/generation/comparison bridge. Neither has
a blanket C20/C22 reading gate. Both are drafted; neither has yet received
a source/practice review. A full cross-route comparison exercise must
still name the relevant complete C20/C22 prerequisites.

G01 now supplies the bounded entrance contracts; complete implementation
homes below remain planned, not additional drafted modules. Canonical
Chapter 34 is split by mechanism so its TinyCC demonstration can be optional
without hiding code used by the direct-GCC production driver.

| Mechanism | Required direct-route home | Distinct alternate-track obligation |
|---|---|---|
| `115` LP64 sizes/alignment and native declarator/declaration machinery | G01 introduces the profile contract; G03 opens complete shared declaration/symbol/storage mechanisms | C23 retains private-call/whole-program TinyCC behavior |
| Shared native call metadata/hooks | G04/G15 explain selected System V parameter/result/frame providers and shared interfaces | C23 retains the private all-stack calling sequence |
| `118` scalar/array/record initializer traversal | G03 opens structure and G09 follows selected static constants/object relocations | C24 retains the executable runtime-initializer path used by TinyCC and its closure; object mode rejects leftover queued initialization |
| `117`/`119` private program/runtime entry | G01/G04/G06 distinguish actual selected object/startup providers and retain any reused hooks | C23/C24 retain private program construction and Linux argument/runtime behavior |
| Profile preprocessing and target headers | G01 supplies selectors; C03–C05/G08/G09 retain needed mechanisms before their tasks | A filename or shared source origin does not imply a TinyCC executable ancestor |

The pinned [System V selector](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L1256-L1265)
uses native declaration machinery; the [object initializer path](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L179-L181)
uses `cc-ni-value`. The [object completion contract](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L436-L443)
rejects a remaining runtime initializer queue. Entire `115`–`119` files
therefore cannot be dismissed as optional merely because they also serve the
TinyCC branch. Full source-region inventories for these planned modules are
still owed.

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
| `book/A2-memory-map.md` | S10–S12; C02–C19/C21/C22; R-memory; G01 | Seed/compiler storage, emitted coordinates, runtime heap, expression snapshots and declaration state drafted; default statement/function/program and assembler buffer/table views are drafted; full native/direct-GCC views remain incomplete |
| `book/A3-reproducibility-chain.md` | S00/S19; C20/C22/C24; G25; K08; R-lineage; G01 | Seed, standalone Stage-A and bounded source-built assembler handoff drafted; stage0/handoff, pnut/TinyCC and broader GCC/kernel lineages remain separately owned |
| `book/A4-worked-exercises.md` | R-solutions; S09/S16/C13 | Draft-covered: conditional exit, native colon return and left association are represented with corrected premises and separate feedback |
| `book/A5-further-reading.md` | R-reading | Preserve purpose-based routes with durable primary links and explicit versions |
| `book/A6-c-subset.md` | C01/C03–C07/C10–C19; R-c-subsets; G01 | Partial: preprocessing, types, expressions and local declarations are source-bounded; default statement/top-level contracts are drafted; full native/direct-GCC reference obligations remain |
| `book/A7-error-codes.md` | S14/S15/S18; C02–C19/C21/C22; R-errors; G01 | Seed and local compiler mechanisms through expressions/declarations/return have bounded failure accounts; default statement/function/program and assembler 230–247 failures are drafted; later-profile tables remain incomplete |
| `book/CONCEPTS.md` | N-concepts | Replace stale source-order graph with first-use, revisit, and actual prerequisite edges |
| `book/GLOSSARY.md` | N-glossary | Synchronize definitions with the profile and chapter that teaches them |
| `book/LEARNING_STORY_PLAN.md` | N-editorial | Carry forward useful outcome/trace goals; do not import obsolete rollout statuses |
| `book/README.md` | N-reading | Provide current entrances, independent outcomes, and honest completion status |
| `book/SUMMARY.md` | N-reading | Link existing text and visibly distinguish future units |
| `book/WORD-INDEX.md` | N-source | Preserve exact symbol-to-source navigation and generate new teaching links from explicit edition inputs |
| `book/WRITING.md` | N-editorial | Keep canonical tangle ownership separate from new-edition annotation/excerpt rules |
| `book/where-this-fits.md` | S00/S19; R-lineage | Preserve historical context while narrowing correctness and lineage claims |
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
| Canonical prologue 00 | `partial` | S00/S19 preserve seed motivation, provenance and trust boundaries; C20 derives the Fibonacci result and compiler endpoint; JONESFORTH/sectorforth context remains R-lineage |
| `000-seed.hex0` and `010-lib.fth` | `draft_covered` | Every seed region and every library definition has a teaching home; execution and reader validation remain separate |
| Appendix A1 | `draft_covered` | [REFERENCE.md](seed-forth/REFERENCE.md), body/helper explanations and S19 supply the complete seed-contract reference and byte budget |
| Appendix A4 | `draft_covered` | All three original worked mechanisms have substantive homes; optional variants and execution/reader evidence remain separate |
| Appendices A2/A3/A5/A6/A7 | `partial` | Exact remaining cross-volume, reference and verification obligations are retained below and in the CSV |
| Canonical Chapters 25/26; `080-cc-elf.fth` and `090-cc-emit.fth` | `draft_covered` | C09–C11 cover all 150 declarations, including 122 colon definitions; selected later patch consumers are opened without claiming their whole modules |
| Canonical Chapters 27–29; `100-cc-expr.fth` and `110-cc-decl.fth` | `draft_covered` | C10/C12–C15 account for all 333 declarations, including 177 colon definitions; local return/unwind definitions are explained, and C16–C19 now supply their default statement/function/program context; later native providers remain planned |
| Canonical Chapters 30/31 | `draft_covered` | C16–C19 and earlier retrieved mechanisms cover default statement/function/program construction and local LP64 branches; C19 source/manuscript review is complete, and full separately implemented providers remain planned |
| Canonical Chapter 32 | `partial` | C19 explains the driver; C20 explains Stage-A and bounded A–G/evidence distinctions; C22 explains assembly/source-built-tool handoff; stage0/DDC/handoff and pnut/TinyCC context remains C24/R-lineage |
| Canonical Chapter 33; `130-asm.fth` | `draft_covered` | C21/C22 explain the complete bounded assembler: all 785 lines/42 regions, 99 declarations including 50 colon definitions, two initializations, supplied-envelope trace and exact handoff predicates; broader lineage and execution remain separate |
| Canonical Chapters 34/35/36/37/38/44 | `partial` | G01 supplies only LP64/profile, object/use, selected scalar call/result, illustrative relocation, actual startup and archive-selection contracts; full writers/providers/link/runtime/archive and TinyCC closure remain owed |
| Canonical Chapters 39–43 and 45–49 | `planned` | Named runtime/target/floating/aggregate/generator modules are future homes, not taught merely because G01 identifies their providers |
| `112`, `114`, `116` and `120` sources | `draft_covered` | All 160 declarations and ten top-level forms have explanatory homes; the C19 source/manuscript review is complete; execution and reader evidence remain separate |
| Five Stage-A recipe scripts | `draft_covered` | C20 explains every one of 33 regions/273 lines; recipe coverage is separate from Forth definitions, the broader bootstrap implementations and recorded execution |
| Navigation/editorial files | `partial` | Complete first-volume routes, C01–C22 source maps, FIRST-RESULTS and the bounded G01 entrance exist; the edition-wide glossary, bibliography, later routes and generated index remain incomplete |
| `playground.fth` | `planned` | Retained as a pinned optional compatibility profile, not promoted into a tested seed execution route |

The remaining first-volume release work is explicit: test the fresh-reader setup route in the named profile; execute and record the new examples and relevant boundary cases if authorized; conduct target-reader review; and revise from those observations. These are real unfinished verification and usability obligations, not missing byte-region ownership. This map does not authorize builds or tests by itself.

The old appendices cross volume boundaries:

- **A2 memory map:** the seed view is in REFERENCE.md and S10–S12; C02 adds arena/I/O buffers and lexer-state storage; C03–C05 add include pools, macro arrays/text, temporary sinks, token shadows, conditional/location records and their lifetimes. C06–C08 add token snapshots, stable descriptors/current tables, symbol columns, scope markers and qualifier nodes. C09–C11 add builder/file/target coordinates, data/BSS placement and the separate generated-process heap. C12–C15 add expression snapshots, call/destination staging, constant-reader state and declaration bookkeeping. C16–C19 add replay marks, control/label nodes, fixed call frames and top-level state. C21/C22 add fresh-load allocation, raw/expanded/output buffers, borrowed definition/label records and target-IP coordinates. Full native/target storage and the cross-profile reference remain R-memory work for Volumes 2–3
- **A3 reproducibility:** S00/S19 supply seed identity/trust distinctions; C20 supplies the standalone Stage-A recipe, exact compared representations, compatibility modes, bounded A–G context and separately attributed historical/CI evidence. C21/C22 now explain assembly and the bounded source-built-tool handoff with its exact comparisons; pnut/TinyCC and native closure remain C24; stage0/DDC/handoff/live-bootstrap and older gcc64 provenance remain R-lineage. Direct-GCC closure remains G25, and kernel/route lineage remains K08/R-lineage
- **A4 worked exercises:** seed return/exit mechanisms and new feedback are present; C13 supplies the complete precedence/left-association mechanism and feedback. All three original mechanisms are draft-covered; optional old variants are not copied one-for-one
- **A5 reading:** seed chapters cite the relevant implementation, ISA, ELF and Linux sources; the full purpose-based Forth/related-project bibliography and compiler/bootstrap/ABI reading routes remain R-reading
- **A6 C subset:** C01/C03–C07/C10–C15 supply profile-scoped preprocessing, lexical/type, runtime, expression and local-declaration behavior, including actual rejection/unchecked boundaries. C16–C19 now explain the bounded default statement/top-level routes. The full native/direct-GCC reference and historical comparison context remain R-c-subsets work; a local accepted path is not whole-program conformance
- **A7 diagnostics:** seed reporting, token/numeric failures, continuation and EOF are in S14/S15/S18 and REFERENCE.md. C02–C05 add infrastructure/preprocessor reporting, capacities, raw-I/O limits, macro/include/group failures, line-control/continuation errors and the evaluator's leftover-token interface; C06–C08 add actual lexical validation limits, suffix/descriptor/member and symbol/scope failure contracts. C09–C11 add encoding premises, fixup/storage capacities, unresolved-use checks and distinct runtime result/failure policies. C12–C15 add expression, type-query, constant-evaluation and local-declaration/return failure boundaries. C16–C19 now distinguish default control/function/program failures and unchecked limits. C21/C22 add the complete local assembler 230–247 account, no 248/249 sites, phase/stale-output limits and the precise seventeen-case gate scope. Native/direct-GCC tables remain R-errors work

No kernel/Linux completion follows from finishing the seed manuscript. The historical ladder and current direct-GCC route remain distinct, and the current direct-GCC-to-Linux outcome is still pending.

## Current C-compiler coverage boundary

C01 supplies the independent entrance rather than requiring the entire seed audit. Its `tri.c` trace derives requested characters and return value on paper. Its driver sequence, profile widths, load order and initial executable contract are entry contracts. C02–C19 now open infrastructure through the default statement/function/driver pipeline. C20 now supplies the bounded Stage-A recipe/evidence account; later providers remain planned; C19's full technical/practice manuscript review is complete.

C02 explains the six colon definitions in `020-cc-arena.fth` and the 29 in `030-cc-io.fth`, together with the declarations they use. The [definition map](c-compiler/source-map.csv) supplies an immutable span, source-blob identity and C02 home for each of the **35 definitions**. Coverage includes the 64-byte lexer state block, exact-capacity distinctions, negative-read behavior, rounded allocation versus initialization, unchecked patches, partial field emission, one-shot file writes, name lookup, and cached 3/7/4-MiB workspace selection. These contracts are explained; successful I/O or generated-program behavior has not been observed here.

C03 opens the first coherent part of `040-cc-prep.fth`: active-region cursors, the four-cell sink, file walkers, newline accounting, literal include frames, physical search paths, fixed-slot versus packed live storage, profile bounds, and final reader reset. Its worked three-file case preserves parents while all children append to one output. It does not equate a saved pointer with preserved bytes or flattened line counts with original-file locations.

The [preprocessor region map](c-compiler/preprocessor-regions.csv) partitions all **2,256 source lines and 325 declarations into 57 regions**. All **57 regions now have drafted explanations** across C03–C05: 17 primary homes in C03, 23 in C04 and 17 in C05. Shared-interface notes retain the cross-chapter explanations. This is a source-mechanism teaching account, not a machine-code audit or an execution result. The ledger's `drafted` label and this map's `draft_covered` whole-item label describe different levels of that account.

C04 derives persistent macro recipes, newest-first lookup/undefinition, borrowed raw arguments, prescanned arguments, scratch reserve/retain/release, substitution and replacement rescanning. Its direct-profile sections open selective prescan, stringizing/pasting, shadow metadata and final-token tail rescanning. Ordinary name/body spans live in the pool; the dynamic location entries introduced in C05 use static names and empty bodies. The exact `ID(N)` trace and five exercises keep byte counts, busy intervals and ownership visible without treating normalized token spelling as exact output.

C05 completes conditional selection, the evaluator-call lifetime, computed include operands, physical versus logical location, dynamic macros, bounded `#line`, local continuation/parameter rules, predefines and pass/configuration reset. Its six exercises vary membership, inactive nested groups, guarded includes, virtual filenames, target/workspace combinations and continuation owners. Direct preprocessing, target-enabled locations, larger workspace and typed preprocessing evaluation are separate gates; LP64 preprocessing-constant mode is not equivalent to either direct preprocessing or System V selection.

The completed preprocessor account deliberately uses these named external contracts:

| Contract used now | What is supplied in the draft | Later implementation home |
|---|---|---|
| Lexer state marking/restoration | C02's eight-cell state and C05's successful evaluator-return preservation contract | C06 now opens all `050-cc-lex.fth` definitions, including replay/mark/reset and their limits |
| `cc-pp-eval ( a u -- n )` and `cc-pp-eval-text` | C05 gives the caller lifetime, supported small-expression model, remaining-identifier rule, end-of-input check and the provider's state-preservation outline | C14 now opens the complete local constant-expression/provider mechanism in `100-cc-expr.fth`, including typed PP; G09 still owns the separate target static-constant/relocation provider |
| Target predefines and selectors | C05 explains the bounded `124` hook effects, dynamic tags and separate LP64/System V/workspace choices used by its traces | G01–G04 develop the full target/ABI machinery; G08 owns target-header/predefine integration |
| Whole compiler pipeline | C01 names the driver contract; C03–C05 finish the preprocessing transformation under its explicit interfaces | C06–C19 open the default source-to-image mechanisms, including full statements and function/driver integration; C20 now explains the standalone recipe and attributed comparison evidence; C21/C22 open assembly and its bounded handoff; C23+ and later volumes own separate providers/lineages |

Using a supplied contract is not a missing explanation of the preprocessor's own call site. It also does not migrate the whole provider module or require a reader to learn a later parser first. These interfaces avoid a circular learning dependency while preserving the obligations of the later lessons. C06–C08 now discharge the base lexer/type/symbol-layer obligations; their later provider interfaces remain bounded contracts.

The [source-map guide](c-compiler/SOURCE-MAP.md), twenty-two feedback companions and six mixed return checks make the current route navigable. The chapter manuscripts are source-inspected, manually derived drafts. C01–C22 have completed their reported technical/practice manuscript reviews; G01 bounded source/practice and model-assisted prerequisite reviews are complete. The mixed checks supply paper cases rather than execution evidence. New compiler examples, fresh-reader setup and target-reader learning remain unverified by execution or reader observation. The implementation's bounded grammar, macro-lookahead/token-joining limitations and flattened-diagnostic caveats remain explicit; draft coverage does not turn those limitations into claimed fixes.

### Representation and reversible-state boundary

The [definition map](c-compiler/source-map.csv) now names **617 colon definitions across seventeen files**: 145 in the five infrastructure/representation files, 122 in 080/090, 177 in 100/110, 82 in 112/114/116/120, 41 in the 117/118/119 private TinyCC program, initializer and runtime files, and 50 in the standalone 130 assembler. The first 145 have these homes: 6 arena plus 29 I/O definitions in C02, 39 lexer definitions in C06, 52 type definitions in C07, and 19 symbol definitions explained in C08. Supporting constants, tables, scratch state, buffers and deferred entries belong with those definitions; the separate 040 region ledger remains complete.

C06 derives the classified token record, all kind/keyword/punctuation IDs, integer spelling/value, borrowed string bodies versus decoded character values, comment and EOF boundaries, one-token replay and eight-cell snapshots. Its seven exercises include separate answer-free changed-case prompts. A lexer mark excludes source bytes/length, arena/output/symbol effects and other saved marks. The 121→127 floating-token hook and 128 decoder remain later G10/G11 implementations, with the active-target contract supplied locally.

C07 derives type packing, profile-dependent scalar results, suffix/literal selection, the 56-byte stable descriptor, separate growing field tables, recursive identity and array-node readers. Its seven exercises likewise expose changed-case attempts separately from feedback. All 52 definitions have teaching homes. The local token and bit contracts permit entry from C02; reading the whole lexer lesson is not silently required.

C08 explains ten physical columns behind each symbol ID, kind-aware payloads including tagged global-storage slots, newest-first lookup versus namespace policy, scope markers that restore only a live count, profile-selected metadata, writable fixup-head cells and qualifier-list keys. Its eight exercises and answer-free changed cases separate reusable symbol identity, stable descriptor identity, current field-record location and borrowed source bytes. All 19 definitions and their supporting declarations have teaching homes.

| Representation interface used now | Drafted contract | Later implementation home |
|---|---|---|
| Field layout and recursive completion | C07 compares legacy slot layout with native LP64 placement while preserving stable descriptor identity | C15 now opens legacy declaration producers; C23 still owns the full native extension |
| Field lookup and expression metadata | C07 derives `cc-find-field`'s named interface and distinguishes the generated-object address from the builder record | C12 now opens the representation/producers and C14 integrates complete postfix/assignment parsing |
| Ranked/qualified array construction | C07 derives the supplied System V node/qualification contract; accessors alone do not validate nodes | G03 opens the full array/declarator representation |
| Field stride and advanced aggregates | C07 names default 40/48-byte records and the explicit 72-byte provider, plus the moved-table hook | G14 opens bitfields; G15 opens aggregate transport |
| Scope and fixup consumers | C08 explains symbol lifetime; C10 now opens the list walkers and completion events while preserving writable-cell meanings | C15 now opens local declarations; C18 now opens complete default function policy; C23/G03/G04 retain full native/target policy |

These examples explain the representation used at the current boundary. They do not complete the named provider modules, establish a generated program's execution, or supply a general rollback transaction.

### Instruction emission, completion events and runtime

The [emission inventory](c-compiler/emission-map.csv) assigns all **150 declarations** in `080-cc-elf.fth` and `090-cc-emit.fth`: 93 homes in C09, 41 in C10 and 16 in C11. Its **122 colon definitions** also appear in the shared definition map: three in 080 and 119 in 090. These are source declarations and emitters, not a count of original seed bytes or proof that an emitted program ran.

C09 derives a 23-byte local subtraction fragment, encoding fields, displacement boundaries, flags, branches, frames, integer width/extension/conversion, and the complete 120-byte ELF envelope with final-size rules. It supplies its own instruction bridge. C10 separates call displacements, absolute function addresses, inline decoded strings and data/BSS addresses, then opens the distinct list/array owners and completion events. Function definitions, late shims, local string wrappers, global finalization and ELF finalization finish different promises.

C11 explains all sixteen runtime emitters and nineteen callable names, eleven eager bodies plus eight demand-driven names. The manually derived eager region is 376 bytes, including calloc's sixteen inline state bytes; it is not a compiled-program size observation. Request size, actual progress, returned unit, stack scratch, mapped heap payload and inline state are kept distinct. Native and System V runtimes remain later C24/G06/G07 obligations.

C10's bounded consumer explanations give real partial coverage to canonical 28/30/31: default call/string behavior, the two patch walkers, function/late-shim resolution and global placement. C11 adds the entry and eager/late runtime registration account. C12–C15 now complete expression and local-declaration mechanisms. C16–C19 now open complete default statement, function and translation-unit machinery. Bounded excerpts of separately implemented providers do not complete their modules.

### Places before precedence, with parser closure now drafted

C12 teaches the place/value representation before C13 consumes it in binary and short-circuit parsing. C12 starts from supplied names, one field and a literal index; C15 later constructs those local records. C14 closes the full postfix/unary/call/update/assignment/comma grammar, cast/type-query/sizeof handshake, builder arithmetic, constant parser and successful preprocessing-evaluator return. C15 explains declarations, recursive records, slot/static storage and every branch of the local switch-unwind/return definitions.

The [parser declaration ledger](c-compiler/parser-map.csv) assigns all **333 declarations** in `100-cc-expr.fth` and `110-cc-decl.fth`: **260 in 100 and 73 in 110**, comprising **177 colon definitions, 74 variables, 60 deferred entries, 20 constants and two created objects**. Primary homes are **C10: 6, C12: 78, C13: 57, C14: 135, C15: 57**. Each declaration has a substantive explanation or an explicitly bounded current-file default/caller contract; a callback does not stand in for an unexplained local algorithm.

Canonical 27 is now draft-covered by C13's runtime precedence and C14's compile-time evaluation. Canonical 28 is covered by C10/C12–C14, including its local LP64 branches and final bindings. Canonical 29 is covered by C14/C15: C15 explains the complete local `cc-emit-switch-unwind` and `cc-parse-return` behavior using stated saved-register obligations. C17 now derives switch obligation creation and discharge; C18 now integrates parameters, locals, prologue and return into complete default frames. These later explanations discharge the earlier local-contract deferrals without claiming the separate native providers.

The fifth mixed check contrasts equal values with different destination identities, generated short-circuiting with builder-time suppression, comma declarations with pointer depth, and exact successful reader restoration. It adds four paper questions to the separate return-check count. The four new chapters contribute **32 main exercises**: C12 eight, C13 seven, C14 ten and C15 seven.

The default statement/function/program integration is now drafted in C16–C19. C20 now opens the standalone artifact/build/Stage-A recipe and attributed comparison; C21/C22 now explain assembly and its bounded tool handoff; C23/C24 now draft the native/TinyCC closure. C23/G03/G04 still own full native declarators, signatures and call planning; G02/G09 own objects, relocations and target static constants; G10/G14/G15 own floating, bitfield and aggregate providers. The local LP64 algorithms in 100/110 are drafted, while those separately implemented providers remain bounded interfaces. The newly integrated C16–C19 mechanisms are described below; C23/C24 are drafted as an alternate route.

### Statements, functions and translation-unit closure

The [control/function/program ledger](c-compiler/control-map.csv) has **170 rows**: 160 named declarations, including 82 colon definitions, plus eight top-level initializations, one deferred binding and one driver invocation. Its file counts are 112: 78 rows (71 declarations plus seven forms), 114: 12 declarations, 116: 76 rows (75 declarations plus one form), and 120: four rows (two declarations plus two forms). Primary chapter homes are C16: 25, C17: 53, C18: 12 and C19: 80. Retrieved mechanisms retain explicit links to C10/C11; each row identifies the state owner, semantic purpose and depth of explanation.

C16 closes branch/loop destinations, nested list ownership, for-step capture and full lexer-state replay, plus the statement dispatcher. C17 closes switch selection and cleanup, the separate label table, legacy definition-time goto resolution and the LP64 depth/trampoline algorithm. C18 closes all 114 definitions: name publication, both prototype heads, parameter records/spills, fixed frames, body/return integration and scope restoration. Its nested-call trace distinguishes stack balance from the actual alignment precondition.

C19 now contains the whole 116/120 account: enums, typedefs, reversible classification, prototype reuse, scalar/array/global producers, data/BSS finalization, eager/late/external registrations, final checks, entry-call patching and load-time driver execution. C19's full technical/practice manuscript review and the sixth mixed-check source review are complete. The ledger's `taught` marks describe explanatory homes; they do not certify review, execution, conformance or learning.

The opening `return 7` trace derives main at offset 522, a 34-byte function, final output cursor 556 and entry displacement 388. Its predicted target returns seven to the entry stub, which requests exit; seven is not printed. A populated output buffer is not evidence that the one-write path stored a complete file, a loader accepted it or the generated program ran. C20 explains exact Stage-A inputs/artifact identities and scoped historical/remote evidence; C22 adds assembly and source-built tools. Canonical Chapter 32 remains partial for pnut/TinyCC and stage0/DDC/handoff lineage, even though its default driver and assembly mechanisms have explanatory homes.

The new chapters contribute **32 main exercises** (8/8/9/7). The sixth C return check contributes four separately counted questions. Full native/private-stack function drivers, System V scheduling and other later target providers remain C23/G homes. C21/C22 below discharge the bounded assembler teaching obligation; the current direct-GCC-to-Linux obligation is unchanged.

## Stage-A recipe and evidence boundary

C20's [pipeline map](c-compiler/pipeline-map.csv) assigns all **33 regions / 273 lines** of five complete recipe files: `stage-a-check.sh` has ten regions/78 lines, `build-m2planet-monolith.sh` eleven/106, `build-gcc-refs.sh` seven/50, `compiler-layers.sh` one/10 and `build.sh` four/29. All regions are taught at the recipe level. Source-blob checks now cover **71 pinned project files**; the definition inventory now contains **576 colon definitions across fourteen compiler/assembler files**. Source identities, recipe regions and definitions are different counts.

The chapter supplies eight main exercise/feedback sets. It distinguishes 31 loaded Forth files (010 plus 30 selected compiler layers), the four-header/nine-C-file monolith, and the eleven ordered comparison arguments. It follows conditional seed reuse/build, fresh host references, the wrapper's fixed-path/private-view/fallback behavior, the two M2-Planet invocations and the exact M1 `cmp`. The loaded optional providers are not thereby selected or fully taught.

The [observed check job](https://github.com/delta9000/seed-forth/actions/runs/37474668625/job/112306844449) reports standalone M1 equality at **2,367,260 bytes** at head `764bdc4f4902d613145f361da6a7f33010dd37b4`. Its relevant recipe blobs match the teaching pin. The surviving log supplies selected summaries, no downloadable output artifacts and no Stage-A SHA-256. Pinned `REPRODUCIBLE.md` hashes remain separately attributed historical records; C19's image and C20's Fibonacci/example answers remain derivations. New examples were not executed to write this chapter.

C20's bounded A–G map identifies M1 generation equality, same-generation cross-route ELF comparisons and generated-program behavior as different predicates. It does not complete `bootstrap.sh`, `bootstrap-chain.sh`, the assembler, stage0/DDC/handoff/live-bootstrap, pnut/TinyCC, old gcc64 or direct-GCC/kernel implementations. C22 now discharges their bounded assembly/handoff portion. Original 32 remains partial for C24/R-lineage; A3 remains partial for C24/G25/K08/R-lineage. Original 00 retains its historical Forth-landmark context in R-lineage. C20's full source/practice review and final readback are complete; migration coverage and review/observed execution/reader outcomes stay separate.

## Complete bounded assembler and source-built-tool handoff

[C21](c-compiler/chapters/21-assembler-input-and-expansion.md) and [C22](c-compiler/chapters/22-two-pass-assembly-and-bootstrap-handoff.md) explain all of `130-asm.fth`. The [assembler ledger](c-compiler/assembler-regions.csv) partitions **785 lines into 42 regions**, with primary homes C21: 22 and C22: 20. Its **99 declarations** comprise 50 colon definitions, 34 variables, eight created objects and seven constants. Two top-level initialization forms set the allocation and default-base state. These are additional inventory dimensions, not 101 extra colon definitions or executed forms.

C21 follows definitions and direct quotes into an exact 35-byte expanded text, then opens raw/expanded ownership, cursor and capacity boundaries, one-pass newest-preceding substitution and unchecked quote/number paths. C22 reuses that unchanged text to derive seven bytes, preserving the complete label table across rewind. It opens all six sigils, explicit label differences, actual numeric/label bounds, low-byte emission, duplicate labels, diagnostics and output-write limits. A separate worked input supplies the actual 120-byte header and derives a 148-byte fixture; the assembler itself does not manufacture or validate an ELF envelope.

The handoff explains how the Forth assembler makes runnable M2-Planet, M1 and hex2 tools, and names the exact step-5 ELF route comparison, step-6 M1-text fixed point, separate step-7 tool rebuilds and step-8 behavior check. Test recipes are cited for their actual inputs and predicates; no whole-file test/bootstrap/handoff script is counted as taught merely because its comparison is named. Small-fixture and self-compile M2libc inputs retain separate pins and definition tables.

Both chapters and all 22 main exercise/feedback pairs passed source/practice review. Existing CI summaries remain attributed to their observed head, distinct from the teaching source pin; no new assembler or example execution, rendered-layout validation or real-reader outcome is claimed. Original 33's complete local implementation and bounded handoff are draft-covered; optional legacy implementation-extension exercises are supplementary, while broader stage0/DDC/handoff and TinyCC/GCC/kernel histories remain assigned to original 32/A3 and their future units.

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
3. **G21: the joined driver chain, after both G19 and G20.** Follow `gcc`, `cc1`, `collect2`, `as`, and `ld` through a freestanding executable. The documented tool paths and successful execs belong to this specific boundary; a no-header program does not establish a hosted sysroot
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
