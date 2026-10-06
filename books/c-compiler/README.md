# A C Compiler in Forth

A source program and an executable are different kinds of object. This book
follows one small program, `tri.c`, through the representations between them:
owned byte spans, expanded source, tokens, type and name records, instructions,
and a finished image. At each boundary, ask what must be preserved and who
keeps the required state alive.

Start with [Compiler entry and profile](chapters/01-compiler-entry-and-profile.md).
It teaches the C syntax needed for the recurring example and provides a short
Forth diagnostic with targeted refreshers. You do not need to memorize the
first volume's machine-code audit before entering here.

## Available teaching route

1. [Compiler entry and profile](chapters/01-compiler-entry-and-profile.md):
   derive the triangle, separate builder and generated program, and choose the
   exact profile before making a size or calling-convention claim
2. [Buffers, arenas, and failure ownership](chapters/02-buffers-arenas-and-failure.md):
   trace byte spans, cursors, capacity, lifetime, allocation, emission and the
   limits of I/O and error handling
3. [Preprocessing regions and includes](chapters/03-preprocessing-regions-and-includes.md):
   preserve input ownership while nested files contribute to one output sink
4. [Macro expansion and rescanning](chapters/04-macro-expansion-and-rescanning.md):
   preserve definitions and arguments while replacement text is scanned again
5. [Conditional preprocessing and profile extensions](chapters/05-conditionals-and-profile-extensions.md):
   select active groups and distinguish physical, logical and diagnostic locations
6. [Tokens and reversible lookahead](chapters/06-tokens-and-lookahead.md):
   classify borrowed bytes and restore exactly the reader/token state you saved
7. [Types and stable descriptors](chapters/07-types-and-stable-descriptors.md):
   separate encoded types, aggregate identity, current field tables and object layout
8. [Names and lexical scope](chapters/08-names-and-lexical-scope.md):
   track borrowed names, reusable IDs and the visibility restored by a scope count
9. [Instructions inside an executable](chapters/09-instructions-inside-an-executable.md):
   derive file bytes, instruction effects and the exact executable envelope
10. [Calls, literals and deferred addresses](chapters/10-calls-literals-and-deferred-addresses.md):
    preserve unresolved destinations until their relative or absolute fields can be patched
11. [A bounded legacy runtime](chapters/11-a-bounded-legacy-runtime.md):
    follow the actual requests and results behind nineteen familiar-looking names
12. [Places, values, and delayed loads](chapters/12-places-values-and-delayed-loads.md):
    preserve destination identity and decide when a result needs a memory read
13. [Precedence and short-circuit expressions](chapters/13-precedence-and-short-circuit.md):
    preserve operands through recursive parsing and select generated execution paths
14. [Expressions, stores, and values computed now](chapters/14-expressions-and-constant-evaluation.md):
    close postfix/unary/assignment/comma grammar and distinguish runtime emission from immediate evaluation
15. [Declarations and recursive records](chapters/15-declarations-and-recursive-records.md):
    build the descriptors, names and storage records supplied to earlier traces
16. [Conditions and loops](chapters/16-conditions-and-loops.md):
    trace conditional destinations, loop exits and the reader state needed to replay a step
17. [Switches, labels, and nonlocal control](chapters/17-switches-labels-and-nonlocal-control.md):
    separate selection from fallthrough and restore the saves crossed by each exit
18. [Functions and call-frame accounting](chapters/18-functions-and-call-frame-accounting.md):
    follow copied arguments into frame slots and back to the caller
19. [Translation units and process entry](chapters/19-translation-units-and-process-entry.md):
    join declarations and finalization, then derive a whole small program's image and entry path
20. [The complete compiler and Stage-A comparison](chapters/20-complete-compiler-and-stage-a.md):
    follow the produced compiler into its next output, then identify exactly what a recorded comparison establishes
21. [Assembler input and expansion](chapters/21-assembler-input-and-expansion.md):
    follow definitions and quoted strings into exact expanded text while preserving the borrowed names
22. [Two-pass assembly and bootstrap handoff](chapters/22-two-pass-assembly-and-bootstrap-handoff.md):
    count positions, resolve fields, supply the executable envelope and identify the source-built tool comparisons

These twenty-two chapters provide 167 exercises and separate feedback
companions. Try a
prediction, use a hint when a step is missing, then attempt a changed case
without copying the worked answer. The purpose is to explain a mechanism,
not to memorize the order of source filenames.

The [first mixed return check](practice/return-check.md) revisits all three
chapters without giving each problem a chapter title as its cue.

The [second mixed check](practice/return-check-2.md) revisits replacement
ownership, conditional state and source identity.

The [third mixed check](practice/return-check-3.md) combines token snapshots,
type identity, table movement and name visibility. The newer chapters also
provide answer-free changed-case prompts so you can keep feedback closed
while finding the task.

The [fourth mixed check](practice/return-check-4.md) joins instruction fields,
patch ownership, runtime results and typed storage.

The [fifth mixed check](practice/return-check-5.md) joins place identity,
short-circuit phases, declaration storage and successful reader restoration.

The [sixth mixed check](practice/return-check-6.md) combines loop destinations,
switch cleanup, replayed tokens, unresolved uses and whole-image placement.

Places and values precede operator parsing, so operators use an already-taught
state model. Statements and functions then use it to build a complete paper
program. C20 then follows the exact artifacts and comparisons of Stage A;
C21/C22 open that representation, its assembler and the source-built handoff. The
[coverage map](../COVERAGE.md#volume-2-a-c-compiler-in-forth) assigns the later
control, function, assembler and bootstrap units. Planned
units are not chapters that already exist.

## Current review boundary

The [C16–C19 unit record](DRAFTS.md) distinguishes the completed C16–C18
technical and reading-flow checks, C19's complete reference/practice review,
and the bounded reader attempts. C19 and the sixth mixed check have passed
source-derived checks. C20's full recipe, evidence account and eight exercise
sets have also received independent source-based review. C21/C22 add a reviewed
expansion/two-pass unit and 22 more exercise sets. All twenty-two chapters
remain teaching drafts;
source and model-assisted reviews do not establish real-reader learning.

## Profile and evidence

The first route uses the pinned legacy direct-ELF compiler: the Forth builder
emits an executable image directly. Optional direct TinyCC and System V routes
have their own storage, calling, preprocessing and runtime contracts. Loading
their definitions does not silently make the default path equivalent to them.
The [entry chapter](chapters/01-compiler-entry-and-profile.md#name-the-compiler-profile)
provides the comparison before the distinction matters in a trace.

All implementation claims use the [edition pin](../EDITION.md). The chapters
contain inspected source and paper derivations, not transcripts of newly run
compilers. C20 separately reads an identified existing CI comparison record.
The new examples and fresh-reader setup remain unexecuted; there
has been no real-reader validation. Existing repository CI has its own
[validation record](../VALIDATION.md) and does not execute these exercises.

The legacy compiler/M2-Planet recipe and its finite M1 comparison now have an
explanatory home. The Forth assembler and its source-built handoff are now drafted as well.
The separately identified native/TinyCC profile and its closure remain planned
closing units. A current direct-GCC-to-Linux outcome
requires its own evidence in the later kernel volume.

## Find the implementation

The [source map](SOURCE-MAP.md) connects explanations to exact definitions and
immutable source spans. It is a reading aid, not a second source authority.
The original implementation and literate `book/` tree are unchanged; this
teaching edition is not input to their tangler.
