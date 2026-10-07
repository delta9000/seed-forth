# Equal sort keys and unequal bytes

Two registers receive equal sort keys. Either order is legal, yet only one order
matches the next compiler generation’s bytes. How can an ordinary library choice
affect a compiler fixed point?

Solve a two-record sorting puzzle, then follow the pinned heapsort-to-smoothsort
account. This chapter attributes the reported result to its source record; it
does not rerun or universally prove the comparison.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G23 supplies controlled generation inputs. A **comparator** returns negative,
zero or positive ordering; zero can identify different elements with equal keys.
A **stable sort** preserves relative input order for equal keys. The documented
smoothsort is not a general stable sort, even though it leaves already sorted
equal runs in place.

## Let equality retain different identities

Supply records A=(key 4,payload RBP) and B=(key 4,payload RAX), with a
comparator that reads only key. Comparing A with B returns zero. Both A,B and
B,A satisfy that ordering. They remain different records because their payload
identities differ.

Suppose a code generator writes register names in sorted order. A,B can produce
(%rbp,%rax); B,A can produce (%rax,%rbp). In the reported address case, both
represent the same legal effective-address choice, but their textual assembly
and resulting instruction encodings can differ.

A sorted-key test cannot select which equal element comes first unless its
comparator or sorting contract includes that tie rule. Comparing only keys in a
test would miss the generation difference. Preserve full record/pointer
identities when investigating it.

Sources: [GCC equal-key consumer and recorded
difference](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29).

## Find the runtime crossing that makes ties visible

The first Stage C cc1 executes on the source-built seed runtime. It builds stage
2, whose GCC executable runs on musl when building stage 3. With the runtime’s
earlier heapsort, seven executables differed between those generations by
equivalent equal-key choices.

The reported example is simplify_plus_minus in simplify-rtx.c, using
commutative_operand_precedence that gives registers equal precedence. The
compiler’s source-level comparator therefore leaves tie order to qsort.
Replacing only the Stage C cc1’s linked sorting implementation with musl’s
smoothsort made the later products agree in the recorded account.

This result does not show that heapsort violated its C interface or that every
byte difference is harmless. It shows one diagnosed runtime input that mattered
to the exact Stage D lineage. Source equality and public function-contract
validity do not force deterministic tie order across different implementations.

Sources: [runtime replacement
account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29),
[fixed-point tie
diagnosis](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L547-L559).

## Give the replacement its own provenance

The selected qsort.c comes from musl 1.1.24 with its recorded SHA-256, MIT
notice and original attribution. The direct Forth driver compiles that source as
an ordinary runtime member. No host libc qsort object becomes a production input
merely because the algorithm originated in another libc.

One adaptation replaces musl’s internal trailing-zero helper with a portable
loop. For nonzero inputs it computes the same result; for zero it returns word
width rather than looping forever. The source records that smoothsort’s normal
calls do not request zero and retains an instrumented observation of that
premise.

sort.c now contains the project’s bsearch, not the earlier heapsort
implementation. Algorithm source identity, adaptation and immediate compiler
producer must all accompany “musl’s sort”; a familiar name is not sufficient
provenance.

Sources: [source and producer
provenance](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L1-L12),
[helper adaptation and caller
preconditions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L40-L56).

## Follow an element rotation without borrowing allocation

Smoothsort organizes a sequence of Leonardo heaps and uses sift/trinkle
operations to restore their ordering while exploiting existing order. Its
worst-case comparison behavior is O(n log n), with near-linear behavior on
nearly sorted inputs according to the pinned account.

cycle rotates complete elements through a fixed 256-byte stack buffer, handling
elements wider than that in chunks with memcpy. Leonardo-number state and the
buffer provide bounded auxiliary storage; the routine allocates no heap objects
and has no global state or unbounded recursion. A comparator can call qsort on
another array without sharing this invocation’s heap state.

The caller still supplies enough storage and a consistent comparator. Invalid
extents, mutation of the elements being ordered and inconsistent ordering are
outside the contract. Zero/one count or zero width returns without comparator
calls. General equal keys need not keep input order; “already sorted runs stay
put” is a narrower fact.

Sources: [algorithm, space and stability
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L31-L56),
[local helper and rotation
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/qsort.c#L1-L80).

## Test ordering, permutation and generation separately

The recorded production gate checks permutations, many patterns, byte records,
identities, nested callbacks, comparison bounds and protected-region boundaries.
An independent selection-sort reference checks byte records without demanding
general equal-key stability. Identical keys with distinct identities remain
inspectable.

The optional host oracle namespaces and Forth-compiles the frozen source, then
links independent host clients and compares full tie placement. Its host objects
and libc are comparison support, not runtime production ancestors. Runtime
interface checks do not by themselves establish GCC generation equality; that
uses G25’s installed-file predicate.

The fixed-point account is useful precisely because it retains a cause and a
bounded changed input. Do not replace it with “smoothsort always makes compilers
reproducible” or “equal compiler outputs prove correct compilation.” Both
statements exceed the recorded result.

Sources: [production and oracle verification
scope](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L58-L91).

## Make equality of keys visibly different from identity

Supply three records with key seven and payload identities A, B and C. The
comparator observes only the key, so every pair compares equal. Both A B C and C
A B satisfy the comparator's ordering requirement and preserve the three
records. A general sorting contract need not choose the same order among them.

Now let a downstream generator print each payload in sorted traversal order. The
first traversal prints A B C; the second prints C A B. The sort can be lawful
under its comparison contract while the generated bytes differ. The byte
consumer observes information that the comparator deliberately ignored.

Check permutation as well as key order. A B B also has ordered equal keys, but
it lost C and duplicated B. That is a sorting failure under the supplied record
set. Equal-key freedom permits different orders, not loss or duplication. An
oracle that checks only nondecreasing keys would miss this defect.

Sources: [GCC equal-key consumer and recorded
difference](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29).

## Follow the reported tie into machine output

The pinned diagnosis concerns GCC's choices among equal-comparing operands.
Different traversal orders can select different operand arrangements that still
express the documented equivalent effective address. The emitted assembly text
and corresponding bytes can then differ. Equivalence must be established for
that particular change, not inferred for every possible displacement or operand
mismatch.

The recorded seven-executable mismatch was traced across the runtime transition:
the earlier producer used the seed runtime's sorting algorithm, while later
generations used musl's. Source code identity alone did not hold that
algorithmic behavior constant. The producer graph needed its runtime edge.

The reported intervention relinks Stage C cc1 with the identified musl
smoothsort source compiled by Forth. This changes the executing earlier
producer's runtime algorithm. It does not copy a host libc object into
production and does not rewrite the final unequal executable bytes until they
match. The prepared source and resulting object remain part of the lineage.

Sources: [runtime replacement
account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29),
[fixed-point tie
diagnosis](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L547-L559).

## State the useful property narrowly

The adapted smoothsort leaves already sorted runs in place under the documented
behavior. That helps the reported equal-key case. It is not a general
stable-sort guarantee for arbitrary input permutations. General stability would
require preserving relative identities of equal keys across every admitted
input, a stronger property than this local case.

The source adaptation and license account also remain explicit. The source-built
object has an upstream origin, modifications for the admitted compiler and a
named executable producer. A test can compare behavior without becoming the
producer of that object. Optional host-supported sorting checks belong to the
evidence branch of the graph.

For a future diagnosis, retain the comparator, input identities, output
permutation, affected code choices and executable differences. Then retain the
changed runtime object's provenance and the subsequent generation comparison.
The chapter's equal-key records are supplied paper states; the seven-executable
diagnosis and relink outcome are attributed to the pinned account rather than
newly observed.

Sources: [source and producer
provenance](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L1-L12),
[helper adaptation and caller
preconditions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L40-L56),
[algorithm, space and stability
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L31-L56),
[local helper and rotation
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/qsort.c#L1-L80).

## A lawful ordering can still be a changed production input

The comparator supplies an ordering of keys, while the generator's output can
expose whole records. When distinct records share a key, the comparator has
deliberately left their relative order open. Changing the sorting algorithm can
choose another lawful order and therefore another output byte sequence. The
lawful behavior is part of the explanation, not a reason to ignore the mismatch.

In the recorded GCC diagnosis, equivalent register-order choices became distinct
assembly/encoding bytes in seven executables. The resulting address behavior was
explained for those choices. Another mismatch could change an accessed
displacement or value and require a different diagnosis. Byte inequality is a
signal to investigate, not a universal verdict of either correctness or error.

| Comparison question | Appropriate identity | What it can miss |
|---|---|---|
| Are keys ordered? | Comparator results | Lost/duplicated equal payloads |
| Is the result a permutation? | Complete record identities | Tie order differences |
| Does a sorted run stay in place? | Input/output positions for that run | General stability |
| Are generated files equal? | Exact output bytes | Semantic equivalence |
| Are these choices equivalent? | Concrete address/value behavior | Unrelated changes |

The adapted smoothsort includes a portable count-trailing-zeros helper in place
of an internal musl dependency. The documented nonzero-call assumption and its
verification account are specific. Source provenance retains the upstream file,
license and the adaptation. Compiling that source with Forth preserves a
source-built production object while changing the earlier producer's runtime
algorithm.

The source-built sorting check and optional host-supported oracle have different
graphs. The former builds its client through Forth and retains artifacts; the
latter links the frozen implementation into host clients and uses host support
for comparison. Their results should not be merged into a claim that host libc
supplied production bytes.

The reported relink changed the runtime object in Stage C cc1 and left the rest
of that stated intervention unchanged. Later generations then agreed under the
retained predicate. This manuscript explains the documented cause, with the
sorted/equal paper examples supplied locally. It does not rerun the sorting
tests, verify their millions of keys afresh or reproduce the seven-executable
intervention.

Sources: [GCC equal-key consumer and recorded
difference](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29),
[runtime replacement
account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29),
[fixed-point tie
diagnosis](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L547-L559),
[source and producer
provenance](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L1-L12),
[helper adaptation and caller
preconditions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L40-L56),
[algorithm, space and stability
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L31-L56),
[local helper and rotation
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/qsort.c#L1-L80).

## Retain the intervention without calling every sort stable

The original seed-runtime heapsort exchanged two equal elements in a case where
musl smoothsort left them. GCC's comparator assigned equal precedence to the
relevant register operands. The later code generator exposed their order in
assembly. The source account connects these facts to seven unequal compiler
executables containing the documented equivalent choices.

A legal qsort result can therefore be an unsuitable uncontrolled input to an
exact byte comparison. The comparison is asking which bytes were produced, while
the sort contract allows more than one tied order. Neither statement is wrong.
The reproducibility account needs to control the producing algorithm or narrow
its accepted relation explicitly.

The reported intervention changed the qsort object linked into the earlier Stage
C cc1. That object was compiled by Forth from identified musl source with its
retained notice and helper adaptation. The record says the rest of that
intervention was unchanged. It did not borrow a host libc executable
implementation or normalize the final compiler files after generation.

Smoothsort's sorted-run behavior helps this reported case, but general equal-key
stability remains unclaimed. Distinct equal records can change positions under
other inputs. A test expecting stable output for every tie would ask more than
the stated contract. A test checking only ordered keys would ask too little to
catch duplication or loss.

The source-built test therefore checks complete permutations and surrounding
bytes as well as order, varied record widths/offsets, nested callbacks and other
bounded cases. The optional host oracle compares the same frozen implementation
under host clients and retains host tools separately. Neither test's existence
gives a fresh result in this manuscript; the reader can inspect their stated
scope and producer separation.

The count-trailing-zeros helper adaptation also has a precise assumption. The
algorithm does not request zero in the relevant source account, while the
replacement still defines a bounded zero result rather than looping forever. Its
retained instrumented observation supports that historical assumption on the
named run. It is not a new proof over all future input.

When diagnosing another byte mismatch, begin again with concrete records,
comparator, producer runtime and affected output. Equivalent RBP/RDX
arrangements in this recorded example do not make changed displacements or lost
values harmless elsewhere. The investigation needs to establish its own semantic
relation.

This chapter's equal-key models let a reader distinguish ordering, permutation,
stability, semantics and exact bytes. The reported relink and successful later
agreement retain the pinned source account. No sorting test, host oracle or
seven-executable rebuild was repeated for the book.

Sources: [GCC equal-key consumer and recorded difference](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29), [runtime replacement account](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L14-L29), [fixed-point tie diagnosis](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L547-L559), [source and producer provenance](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L1-L12), [helper adaptation and caller preconditions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L40-L56), [algorithm, space and stability limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/SORT.md#L31-L56), [local helper and rotation source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/qsort.c#L1-L80).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](23-rebuild-lineage-and-controlled-paths.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/24-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G24-01 — Keep equal identities

The supplied comparator returns zero for A/B. Which output orders are legal?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G24-02 — Connect order to bytes

Why can swapping RBP/RDX alter compiler bytes without the reported address
behavior changing? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G24-03 — Locate the runtime change

Which runtime builds stage 2’s code and which runs the next compiler? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G24-04 — Reject false stability

Is this smoothsort generally stable for equal keys? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G24-05 — Preserve provenance

Does compiling musl qsort.c with Forth introduce a host libc object? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G24-06 — Retain permutation

Why check identities beyond sorted keys? Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G24-07 — Bound the reported fix

What does the recorded seven-executable diagnosis establish? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

## What this mechanism makes available

You can now resolve a small equal-key sorting puzzle before interpreting
reproducibility. Use the state transitions above to justify that explanation,
rather than treating a source filename or a successful later milestone as a
substitute for the mechanism.

Continue to [G25: Fixed-point evidence and toolchain
capstone](25-fixed-point-evidence-and-toolchain-capstone.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
