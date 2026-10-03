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

Commit source, tests, and this status on this branch in small increments before
lengthy validation, then commit the measured results. Verify the remote commit
before considering a checkpoint durable. Preserve additional reviewed work
manifests in the private checkpoint repository. Local build directories are
scratch space, not backups.

At this initial checkpoint, only the original baseline was checked out and its
Git objects verified. No compiler edits, fresh bootstrap tests, or reconstructed
GCC results have been produced. Prior unpublished hashes and test observations
are historical evidence only; they do not validate new reconstruction bytes.

Use the repository's build and test instructions in README.md and check-all.sh.
Run focused tests during implementation, independent review at coherent gates,
and applicable aggregate checks for the final composed source state. Report
passed, failed, skipped, and never-run checks distinctly.
