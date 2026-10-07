# From compiler to toolchain

Begin with [a program from two files](chapters/01-a-program-from-two-files.md). Two small functions let us ask what an object leaves unfinished, how a linker finishes a call, and who supplies the process’s first instruction.

The series follows the [hybrid narrative](../HYBRID-NARRATIVE.md) in its planned G01–G25 order at the [shared source edition](../EDITION.md). H3 opens objects, System V and runtime; H4 follows generators, GCC and source-built output tools; H5 reaches hosted closure and the bounded rebuild predicate. Shared native declarations and initializer traversal belong to this direct route; TinyCC and M2 executable routes remain optional alternatives.

All twenty-five chapters are paper drafts, each with seven exercises and a separate hints/solutions/changed-check companion: **175 GCC-toolchain exercise pairs**. G01 retains its earlier bounded source/practice and model-assisted prerequisite reviews. G02–G25 have not received an independent manuscript or reader review. New examples and command cards remain unexecuted; later results are attributed to the pinned repository records, not freshly reproduced.

| Unit | Chapter | Practice |
|---|---|---|
| G01 | [A program from two files](chapters/01-a-program-from-two-files.md) | [Hints, solutions and changed checks](practice/01-solutions.md) |
| G02 | [Objects, symbols, and relocation records](chapters/02-objects-symbols-and-relocation-records.md) | [Hints, solutions and changed checks](practice/02-solutions.md) |
| G03 | [Signatures, declarators, and ranked arrays](chapters/03-signatures-declarators-and-ranked-arrays.md) | [Hints, solutions and changed checks](practice/03-solutions.md) |
| G04 | [A shared scalar argument planner](chapters/04-a-shared-scalar-argument-planner.md) | [Hints, solutions and changed checks](practice/04-solutions.md) |
| G05 | [Linking independently built objects](chapters/05-linking-independently-built-objects.md) | [Hints, solutions and changed checks](practice/05-solutions.md) |
| G06 | [Raw syscalls, startup, and runtime control](chapters/06-raw-syscalls-startup-and-runtime-control.md) | [Hints, solutions and changed checks](practice/06-solutions.md) |
| G07 | [Source-built allocation and byte operations](chapters/07-source-built-allocation-and-byte-operations.md) | [Hints, solutions and changed checks](practice/07-solutions.md) |
| G08 | [Target headers and honest feature probes](chapters/08-target-headers-and-honest-feature-probes.md) | [Hints, solutions and changed checks](practice/08-solutions.md) |
| G09 | [Typed constants and symbolic addresses](chapters/09-typed-constants-and-symbolic-addresses.md) | [Hints, solutions and changed checks](practice/09-solutions.md) |
| G10 | [Floating values and conversion](chapters/10-floating-values-and-conversion.md) | [Hints, solutions and changed checks](practice/10-solutions.md) |
| G11 | [Decimal literals rounded once](chapters/11-decimal-literals-rounded-once.md) | [Hints, solutions and changed checks](practice/11-solutions.md) |
| G12 | [Variadic cursors and argument classes](chapters/12-variadic-cursors-and-argument-classes.md) | [Hints, solutions and changed checks](practice/12-solutions.md) |
| G13 | [Streams and bounded formatting](chapters/13-streams-and-bounded-formatting.md) | [Hints, solutions and changed checks](practice/13-solutions.md) |
| G14 | [Bitfield layout and preserving stores](chapters/14-bitfield-layout-and-preserving-stores.md) | [Hints, solutions and changed checks](practice/14-solutions.md) |
| G15 | [Aggregate values and X87 transport](chapters/15-aggregate-values-and-x87-transport.md) | [Hints, solutions and changed checks](practice/15-solutions.md) |
| G16 | [Indexed archives and lazy extraction](chapters/16-indexed-archives-and-lazy-extraction.md) | [Hints, solutions and changed checks](practice/16-solutions.md) |
| G17 | [Frozen driver, configure, and source census](chapters/17-frozen-driver-configure-and-source-census.md) | [Hints, solutions and changed checks](practice/17-solutions.md) |
| G18 | [Source generators must have builders](chapters/18-source-generators-must-have-builders.md) | [Hints, solutions and changed checks](practice/18-solutions.md) |
| G19 | [The cc1 milestone and its tests](chapters/19-the-cc1-milestone-and-its-tests.md) | [Hints, solutions and changed checks](practice/19-solutions.md) |
| G20 | [Building the downstream binutils](chapters/20-building-the-downstream-binutils.md) | [Hints, solutions and changed checks](practice/20-solutions.md) |
| G21 | [A freestanding GCC driver toolchain](chapters/21-a-freestanding-gcc-driver-toolchain.md) | [Hints, solutions and changed checks](practice/21-solutions.md) |
| G22 | [Hosted closure with libgcc and musl](chapters/22-hosted-closure-with-libgcc-and-musl.md) | [Hints, solutions and changed checks](practice/22-solutions.md) |
| G23 | [Rebuild lineage and controlled paths](chapters/23-rebuild-lineage-and-controlled-paths.md) | [Hints, solutions and changed checks](practice/23-solutions.md) |
| G24 | [Equal sort keys and unequal bytes](chapters/24-equal-sort-keys-and-unequal-bytes.md) | [Hints, solutions and changed checks](practice/24-solutions.md) |
| G25 | [Fixed-point evidence and toolchain capstone](chapters/25-fixed-point-evidence-and-toolchain-capstone.md) | [Hints, solutions and changed checks](practice/25-solutions.md) |

The first story in each chapter supplies its immediate contracts; later sections open the mechanisms and limitations. The [learning path](../LEARNING-PATH.md) and [narrative map](../narrative-map.csv) retain full-depth prerequisites. The sequence ends at the recorded direct GCC 4.0.4 toolchain and controlled file/member comparisons. A fresh operational setup, observed teaching fixtures, independent learning evidence and direct-GCC-to-Linux boot remain separate work.
