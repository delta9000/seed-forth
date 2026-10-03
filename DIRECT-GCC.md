# Direct Forth to GCC: work in progress

This branch develops an optional direct route from the repository's Forth C
compiler to GCC 4.0.4. The starting point is the merged, tested TinyCC route at
`550a0c58013de600f2bc2a7347baf16cd5d7b536` (PR #9). This branch does not yet build
GCC. Work below is a reconstruction; the earlier unpublished implementation is
not present in this checkout.

## Goal and boundary

A reader should be able to follow each step from the annotated seed and a bag
of pinned source archives to a working GCC, then use the existing kernel ladder.
The machine boundary remains AMD64 Linux and the existing 229-byte hex0
assembler plus the 1,772-byte Forth seed. The new route will implement C parsing,
code generation, object emission, and linking in Forth. Host C compilers may
provide independent test oracles; they must not provide bootstrap artifacts.

The first GCC source target is the original 4.0.4 tree at
`944765863eec87a9f37e297994fd2af960397138`. Original source provenance, licenses,
configuration probes, generated-file ancestry, and failure limits belong with
each executable proof. Successful compilation of selected source files is not
a complete compiler bootstrap or a self-rebuild.

## Stages

1. Add an isolated AMD64 System V ABI and ELF relocatable-object mode, with a
   small Forth linker. Preserve the existing native/TinyCC route.
2. Define the supported C dialect and implement shared type, layout, expression,
   call, aggregate, floating-point, and variadic semantics as measured sources
   require them. Unsupported cases must diagnose rather than silently degrade.
3. Supply a bounded, source-built runtime with true headers and implementations.
   Compile original GCC generators and regenerate their inputs from sources.
4. Execute genuine configuration probes and original build recipes. Compile the
   complete cc1 translation-unit cohort under one compiler/runtime epoch,
   inspect unresolved symbols, link, and execute real compiler tests.
5. Close the assembler, linker, runtime, and driver dependencies, rebuild GCC,
   and run integration and bootstrap comparisons. Document the later handoff.

Each stage needs an executable proof and an explanation of its invariants.
A small explicit internal representation may help later retargeting; this work
currently targets one native ABI and does not implement a virtual machine.

## Checkpoints and verification

The reconstructed Forth object writer, static linker, scalar System V mode,
relocatable storage, typed integer constants, and source-built runtime have
focused executable proofs. Separate C units share globals, string and function
addresses, genuine array typedefs, and variadic argument lists. The unchanged
GCC libiberty `ffs.c` and `hex.c` execute through the Forth object/linker path;
`hex.c` uses the original GCC headers. Host tools supply independent behavioral
and ABI comparisons only.

The runtime currently supplies allocation, memory/string operations, unbuffered
streams, and integer/pointer/string formatting. Historical ANSI headers use an
explicit bounded C90-oriented target profile. Binary64 literals, expressions,
storage and return values have executable proofs. Floating arguments and
aggregate value calling conventions remain unsupported; accepting declarations or taking
`sizeof` does not implement those value operations. The original GCC configure
probes now support a bounded, independently audited generator configuration.
Original `gencheck.c`, `gengenrtl.c`, and `errors.c` compile through actual
Makefile object rules and run with the Forth-built runtime. `gencheck` emits
all 164 source-defined checks; both complete `gengenrtl` outputs match an
independently host-built original generator. Those first two focused links
omit unused `BUILD_LIBIBERTY`. The subsequent `genmodes` proof builds seven
original C units, selects five original libiberty members into a real Forth
archive, and links with the Forth runtime. It consumes the complete i386 mode
definitions; all three outputs match the independently host-built original
generator byte-for-byte. Its source-closure review and later integration replay
identify their exact compiler and configuration inputs. This selected archive
does not claim the full 75-member library. A complete GCC build and self-rebuild
remain unfinished.

`tests/gcc/baseline-20261003/` records a fresh independent replay of the
surviving baseline, including the actual raw-input direct TinyCC fixed point.
Those results apply to its named source commit. New component tests are in
`tests/gcc/`; run `bash tests/gcc/check.sh` for their current combined gate.
Passing component tests alone does not prove all supported C semantics or
complete source/bootstrap closure.

Commit source, tests, and this status on this branch in small increments before
lengthy validation, then commit the measured results. Verify the remote commit
before considering a checkpoint durable. Preserve additional reviewed work
manifests in the private checkpoint repository. Local build directories are
scratch space, not backups.

## Verification scope at 2026-10-03 16:43 UTC

The accepted frozen compiler/runtime composition through implicit calls and
reviewed source-location macros passed the expanded direct-GCC component gate
and all sixteen `check-all.sh` steps. This includes both architecture handoffs,
book examples and consistency checks, the original default bootstrap, native
regressions, and the actual raw-input TinyCC executable/object fixed points.
The seed and TinyCC hashes remain unchanged. All 941 source files and 2,373
copied vendor files were rehashed after the final run; the exact source map
and test limits are in `tests/gcc/checkpoints/accepted-20261003T1643.json`.

The first full replay found a missing loader helper in the book-example
sandbox and missing vendor Git metadata in the isolated validation copy.
The helper-copy repair passed all 54 examples; adding the already pinned Git
metadata restored the handoff provenance queries. The repeated full aggregate
then passed. Neither repair supplied target compiler artifacts.

The newer archives, qsort, binary64, bitfields, declarator repairs and
preprocessor continuations are outside that full-pass composition. Their
focused owner and independent checks identify their own source hashes;
integration gates must cover them before a broader claim.
Configuration audit reports preserve the initial false endian/mkdir answers
as failed evidence, followed by the corrected original-probe replay. Full
GCC compilation, self-rebuild, `verify.sh`, and QEMU execution remain unclaimed
for this direct-GCC branch.

Run the repository's applicable aggregate checks against the final composed
source state. Report passed, failed, skipped, and never-run checks distinctly.
No prior unpublished hash or historical test observation validates reconstructed
source bytes. A remote commit that is not reachable from a branch is temporary
preservation only and may be garbage-collected; verify the branch reference
before describing any checkpoint as published.
