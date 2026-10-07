# Linking independently built objects

Two objects both count their first instruction from zero. Where will those two
zeroes live after linking, and how does a call between them acquire a usable
distance?

We will place a deliberately small pair of supplied objects. This numerical
model opens the linker behind G01; it is not a measurement of that fixture.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G02 supplies sections, symbols and RELA records. A **strong** global definition
outranks a weak definition; two strong definitions of one global name conflict.
A local belongs to its owning object. Keep file offsets and virtual addresses
distinct: the fixed target base is 0x400000. No host linker supplies production
bytes in this path.

## Validate before trusting an offset

The linker accepts the writer's ten-role ELF64/AMD64 ET_REL contract, rather
than every ELF object a host compiler might emit. It validates the header, table
spans, section types/flags, alignments, record sizes, links and local/nonlocal
boundary. Strings must terminate inside their validated tables. A successful
check of the magic bytes alone is far too small a contract.

Bounds use subtraction before pointer arithmetic: first establish offset ≤ file
length, then require size ≤ length−offset. This avoids treating an overflowing
offset+size as a valid end. BSS is memory-only, so it does not need a payload
span, but its size and alignment remain bounded.

The input object owns mapped file bytes and symbol-name spans until release.
Selected archive members are copied into their own mappings. Input device/inode
identities are tracked separately, including archives, so output alias checking
does not depend only on whichever members were selected.

Sources: [input spans, headers and section
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L62-L257).

## Choose a definition before choosing its address

Global lookup hashes a name into an open-addressed table kept at most half full.
A chosen row includes the symbol and its owning object. Equal spelling is
compared by length and bytes, not hash value alone. Local symbols bypass global
selection and resolve within their owner.

An undefined record may be replaced by a definition. A strong definition
replaces a weak one; a later weak definition does not displace an existing
strong definition. Two strong definitions reject with 252. If only an unresolved
weak reference remains, resolving that reference can yield zero; a strong
reference still fails with 253. Weakness is attached to the use as well as to
candidate providers.

None of this compares C parameter signatures. Selection establishes the
provider's name and owner, leaving the source interface agreement from G03/G04
as a separate premise.

Sources: [global registration and symbol
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L260-L376),
[resolved values and
entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L403-L445).

## Give both zeroes a place

Supply object A text size 21 and alignment 16, then object B text size 16 and
alignment 16. Let all other payload sections be empty with alignment one. A
starts at file offset 4096, hexadecimal 0x1000. Its exclusive text end is
0x1015. B aligns forward to 0x1020 and ends at 0x1030. The eleven intervening
bytes are padding.

A symbol at B text offset zero resolves to 0x400000+0x1020=0x401020. A call
field at A text offset 17 resolves to P=0x401011. Those section-relative offsets
were converted through their separate placements. Subtracting the raw offsets
zero and seventeen would miss the placement gap.

The layout runs four passes across objects: all text, all rodata, all data, all
BSS. Text and rodata share RX; a page-aligned boundary starts RW data and BSS.
Data advances file size; BSS advances only memory size. In our empty-data model
the RW start is offset 0x2000. This padding is a predicted consequence of the
layout, not user code.

Sources: [four placement passes and payload
copies](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L378-L418).

## Patch the field its consumer will read

For the supplied call, S=0x401020, P=0x401011 and A=−4. The relative field
becomes S+A−P=11, bytes `0B 00 00 00`. The CPU adds it at P+4=0x401015 and
reaches 0x401020. The linker overwrites four existing bytes; it does not append
another call.

The admitted relocation kinds are 64, PC32, PLT32, 32 and 32S. Absolute kinds
use S+A. PC32 and PLT32 use S+A−P. The 32 kind checks zero extension; 32S and
the relative kinds check sign extension. Eight-byte arithmetic is modulo 2^64
before the narrow representability check. A signed displacement outside the
four-byte range is rejected rather than silently shortened.

Every relocation also validates its target field and symbol index. The stored
addend comes from RELA, not from the old field bytes. The static treatment of
PLT32 does not manufacture a dynamic procedure-linkage table.

Sources: [relocation kinds, widths and range
checks](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L448-L514).

## Name an actual entry and describe loading

The requested entry name must resolve to a definition inside text, with its
offset strictly below that section's extent. Merely exporting main does not
choose it as the process entry; the default driver asks for _start. Our model
can supply _start at A text offset zero, giving entry 0x401000.

The output is ET_EXEC with two page-congruent load segments. The first is
readable/executable, the second readable/writable; their file and memory extents
distinguish initialized data from BSS. Loading uses program headers, so the
output needs no runtime section table. There is no dynamic loader in this
bounded link.

That envelope tells Linux where to map and begin under the stated AMD64
contract. It does not prove that the instructions at the requested entry obey
startup's ABI or eventually terminate. A text symbol can have the right location
and the wrong behavior.

Sources: [entry
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L433-L445),
[executable program
headers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L516-L553).

## Finish the write before replacing the destination

Link orchestration lays out, checks unresolved names, finds entry, copies
sections, applies relocations and constructs headers before creating output.
Alias checking compares device/inode identity, catching hardlinks as well as
equal path spellings. A sibling temporary is created exclusively and positive
partial writes advance its cursor; EINTR retries.

Only successful close and rename publish. The linker cleanup differs from the
object writer: `lnk-abandon-output` attempts close, including when reached after
a close error. Retain that source detail instead of borrowing the writer's
explicit invalidation policy. It is a static close-state concern, not an
observed failure in this chapter.

A missing answer therefore fails before publication, even if both source
compilations succeeded. Retain failed status and old output identity in a future
test. An old executable still present at the path is not evidence that this
failed link produced a new one.

Sources: [alias checks, temporary output and
orchestration](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L554-L609).

## Finish the call from the consumer's coordinates

Return to G02's illustrative call field at text-relative offset 17. Supply an
executable text base of 0x401000. The field's process address P is therefore
0x401011. Give the destination symbol address S as 0x401020 and the explicit
addend A as −4. For this relative relocation, compute S + A − P: 0x401020 − 4 −
0x401011 = 11. Four little-endian bytes for that result are 0B 00 00 00.

The processor reaches the same destination from another viewpoint. The CALL
opcode precedes this four-byte field. Its next-instruction address is P + 4, or
0x401015. Adding the stored displacement eleven reaches 0x401020. The RELA
adjustment and the CPU's next-instruction rule agree because each accounts for
the field width at its own boundary. Subtracting four again from the already
computed eleven would double-count the adjustment.

Move only the callee sixteen bytes later. S increases by sixteen and the
relative value becomes twenty-seven. Move both caller and callee sixteen bytes
later instead: S and P both increase by sixteen, so their difference stays
eleven. These are supplied placement changes. They illustrate the calculation
without asserting that the linker may arbitrarily move one fragment
independently of its layout algorithm.

For an absolute relocation, cancellation would not apply in the same way. The
result describes an address rather than a displacement from P. Keep the
relocation kind beside every numerical prediction. A field's width alone cannot
tell us whether the encoded number is absolute, signed-relative or subject to
another check.

Sources: [global registration and symbol
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L260-L376),
[resolved values and
entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L403-L445),
[relocation kinds, widths and range
checks](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L448-L514).

## Make validation precede interpretation

Imagine a relocation record whose symbol index is outside the associated symbol
table. Its relocation kind and addend might look plausible. The consumer must
reject the index before using it to read a symbol row. Otherwise the subsequent
address calculation would be based on unrelated bytes. Format validation
supplies the right to interpret a region; successful arithmetic cannot
retroactively validate the region that supplied its inputs.

Likewise, a section offset and size must fit the file before the consumer
follows them. A string name must terminate within its own string-table extent. A
relocation's field must fit the target section and its width must be one this
linker supports. An executable that later fails to start would be too late an
oracle for these boundary checks: the file consumer already has enough
information to reject the malformed input.

Name resolution introduces a different class of failure. Two independent strong
definitions of one global name do not become valid because both symbol rows are
in bounds. A missing required definition does not become resolved because its
name is well formed. Local symbols retain their object's namespace; they do not
compete as global providers merely because their spellings match.

Follow the phases in their order: validated records permit resolution; resolved
identities permit layout-dependent addresses; final addresses permit
range-checked relocation; finished output permits publication. A later phase
depends on the earlier one but establishes a different property. This gives us a
way to report the first rejected promise without calling every failure a bad ELF
file.

Sources: [input spans, headers and section
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L62-L257),
[four placement passes and payload
copies](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L378-L418).

## Draw the executable's two extents

Place file-backed writable data and BSS in the writable segment. The data has
bytes in the file; BSS increases the required process memory beyond those bytes.
Read file size and memory size as separate segment fields. The extra memory is
part of the loader's contract, not an additional read from the object file's
absent BSS payload.

The executable also needs an entry address whose symbol resolves into the chosen
image. G01's runtime provides the real `_start`; finding a symbol named `main`
does not itself tell the loader to construct C arguments or perform exit. The
linker can place startup code and publish entry metadata. The startup code
supplies the actual first instructions and the call into main.

A future inspection should preserve the input objects, selected archive members,
final symbol addresses, program headers and patched field. Then a separate
target run can record exit status. If the field equals eleven but the entry is
wrong, the arithmetic check can pass while execution fails. If execution returns
the expected status, that one program still does not validate every rejection
branch. Our complete numerical example is a derivation from supplied placement,
with those observations pending.

Sources: [entry
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L433-L445),
[executable program
headers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L516-L553),
[alias checks, temporary output and
orchestration](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L554-L609).

## Make the relocation kind part of the numerical question

Keep the supplied target address 0x401020 and addend −4. In the relative call,
subtracting the field address 0x401011 yields eleven. In an absolute eight-byte
relocation, the same target and addend would instead yield 0x40101C. The two
fields cannot be compared as unqualified numbers simply because both depend on
the same symbol.

The chosen relocation kind tells the consumer what calculation to perform and
what range the result must fit. A relative result can be negative when the
destination precedes the next instruction. Its four-byte encoding uses the
admitted signed range. An absolute field can require the full address-width
representation. Writing the low four bytes of an out-of-range result would
produce a plausible-looking field while violating the relocation contract.

Move the whole text model together and the relative displacement stays the same,
as we derived earlier. The absolute address changes. This gives a useful changed
problem: identical instruction-field bytes do not imply identical process
addresses. Relative coordinates intentionally describe a relationship between
two placements.

| Number | Meaning in the supplied example | Owner of the choice |
|---|---|---|
| 17 | Text-relative field start | Object producer |
| −4 | Explicit adjustment | Relocation producer |
| 0x401011 | Field process address P | Link layout |
| 0x401020 | Chosen definition address S | Resolution plus layout |
| 11 | Relative field result | Relocation application |

Before doing the arithmetic, validate the file regions that supply the symbol
and relocation. Before applying the result, establish that the whole patch field
is inside its target payload. These guards protect interpretation and storage.
They do not decide whether the caller's C declaration matched the chosen callee;
G03 retains that separate source-interface obligation.

After applying relocations, inspect entry and segment metadata before planning a
run. Entry is a resolved text definition under the requested name. File-backed
and memory-only extents supply the loading contract. Publication then moves the
complete new image to the final path. An older surviving file after a failed
attempt can have valid metadata without being this link's result.

A future record can therefore fail at several useful checkpoints while retaining
earlier facts: valid object but unresolved strong symbol, resolved names but
out-of-range displacement, complete image but failed publication, stored
executable but failed loading. Report the first failed boundary and the artifact
identity at that boundary. The paper model supplies a successful bounded
calculation, not observations of these failure paths.

Sources: [global registration and symbol
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L260-L376),
[resolved values and
entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L403-L445),
[relocation kinds, widths and range
checks](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L448-L514),
[entry
validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L433-L445),
[executable program
headers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L516-L553).

## Read the producer and consumer guards in opposite directions

Begin at the completed field and work backward. Eleven came from a relative
rule. That rule needed S, A and P. S required a chosen symbol definition plus
its owning section placement. P required the target section's placement plus the
field offset. A was already explicit in the input. Every operand has an earlier
owner.

Now read forward from the input. The ELF identity admits this file family. Valid
section spans admit its payloads. Valid symbol and string spans admit name
resolution. Resolution chooses a provider; layout supplies addresses; relocation
checks its result's range and patches the field. Publication supplies a final
file. The backward trace and forward trace should meet at the same ownership
facts.

Use the eleven-byte gap after A as a check on this meeting. A's exclusive end is
0x1015. B requires a sixteen-byte boundary, so its start is 0x1020. The gap is
not an extra symbol value or relocation adjustment. It belongs to layout. If a
backward trace subtracts it separately after using B's final address, it counts
layout twice.

Read-only data enters the nonwritable layout, while initialized writable data
and BSS enter the writable extent. The two-segment executable is a bounded
choice of this linker, not every possible ELF image. Section roles in the input
become segment loading obligations in the output. Retain both coordinates when
checking an eventual executable inspector report.

The source's validation and output path can be studied without building the
complete GCC toolchain. The paper fixture supplies the object extents and
selected definitions needed for the arithmetic. A later run needs actual files
and statuses in addition. If its symbol addresses differ from our supplied
addresses, first redo the same rule with its measured inputs; only then compare
the resulting field. This is how the lesson transfers without pretending its
illustrative placement was a dump.

Sources: [input spans, headers and section validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L62-L257), [global registration and symbol validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L260-L376), [resolved values and entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L403-L445), [relocation kinds, widths and range checks](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L448-L514), [entry validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L433-L445), [executable program headers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L516-L553).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](04-a-shared-scalar-argument-planner.md) remains available for
a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/05-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G5-01 — Place text

Derive A/B starts, B’s virtual address and the gap in the supplied layout.
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G5-02 — Close the call

Derive the model call’s field bytes and CPU destination. Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G5-03 — Choose the provider

A weak definition precedes a strong definition of answer. Which survives?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G5-04 — Resolve weak uses

An undefined weak use has no provider. Contrast an undefined strong use. Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G5-05 — Preserve BSS

Add sixteen BSS bytes after an aligned data end. Which final extent grows?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G5-06 — Reject a false entry

The requested name is main but the driver contract requested _start. Can name
resolution silently substitute main? Explain which supplied rule determines your
answer. Keep any prediction separate from a claim that the corresponding program
or build was run.

### G5-07 — Report publication

A failed link leaves an older file at the output path. What may be claimed?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now place two objects and apply their one named relocation. Use the
state transitions above to justify that explanation, rather than treating a
source filename or a successful later milestone as a substitute for the
mechanism.

Continue to [G06: Raw syscalls, startup, and runtime
control](06-raw-syscalls-startup-and-runtime-control.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
