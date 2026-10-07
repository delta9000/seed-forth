# Objects, symbols, and relocation records

An unfinished call needs more than four empty bytes. How can its destination
keep the same identity while the compiler forgets a local scope and the object
writer rearranges its symbols?

Follow G01's `main.o` toward the file boundary. We will build a small paper
object record, then open the section, name, relocation and publication
mechanisms behind it. The addresses and counts supplied below are illustrative
inputs, not a dump of the two-file fixture.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

Keep G01's LP64/System V/ET_REL contracts. A **section offset** counts bytes
from one section's beginning; a **file offset** counts from the file's
beginning. Neither is a final process address. [S02's address
bridge](../../seed-forth/chapters/02-addresses-and-bytes.md) and [C10's deferred
fields](../../c-compiler/chapters/10-calls-literals-and-deferred-addresses.md)
are optional refreshers. A Forth cell is eight bytes, while a serialized ELF
record has its own field widths.

## Give the field a section and a name

Supply a `.text` fragment with an E8 opcode at section offset 16 and four
reserved bytes at offsets 17–20. Its end is 21. Supply an undefined global
function named `answer`, represented by writer handle 1. A relocation can now
say: target `.text`, offset 17, kind PLT32, handle 1, addend −4.

The call cannot run yet. Offset 17 locates a place to overwrite in this object;
handle 1 identifies the destination's record. The addend is the adjustment to
apply once that destination has an address. These three numbers have different
jobs even if two happen to be equal.

The writer accepts relocations only into `.text` or `.data`, and requires the
whole field to fit already reserved bytes. Four bytes beginning at 17 fit end 21
exactly. Beginning at 18 would require end 22 and fails. A BSS reservation
cannot host this relocation: there are no file-backed bytes to patch there.

Sources: [relocation width, ownership and
bounds](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L297-L330).

## Reserve storage without inventing file bytes

The four payload roles are `.text` for instructions, `.rodata` for read-only
data, `.data` for initialized writable data and `.bss` for memory-only zero
storage. Each has a length and alignment. Selecting a section changes which
cursor emission uses; it does not join the four cursors into one final address
space.

Suppose `.data` has length 5 and a following object needs alignment 8 and size
4. Alignment reserves three zero bytes, returning the next useful offset 8;
reserving the object advances length to 12. The required alignment becomes at
least 8. In `.bss` the same arithmetic advances the memory extent, without
copying twelve payload bytes into the file. Trying to emit a byte directly into
BSS fails.

The accepted alignment is a nonzero power of two through 4096. This is a writer
contract, independent of the linker's larger alignment limit. Byte, four-byte
and eight-byte writers store little-endian low bytes; they do not validate a C
expression's signed overflow. The constant evaluator and relocation consumer
have separate checks.

Sources: [section cursors, reservation, alignment and
patching](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L150-L222).

## Keep two stable identities before numbering the file

Parser symbol IDs can be reused after a block ends. `123` therefore retains a
separate object record, including name, binding, kind, section, offset, size,
alignment, type/descriptor, flags and eventual writer identity. A block-static
object must not acquire another block's storage merely because both used the
same parser row number.

The object adapter's flags distinguish extern-only, tentative, initialized,
block-static, referenced and anonymous records. A later definition can replace
an extern-only state. Strings receive read-only storage and their own records.
Storage finalization places surviving tentative objects in BSS; initialized
objects already have data reservations. Function uses become relative
relocations at finalization, including the calls still waiting on a definition.

The writer then supplies a second identity: its API handle. It copies a symbol's
name into owned string storage, so the caller may reuse its name buffer. At
build time it assigns **ELF indexes**, emitting locals first and globals/weak
symbols second. A relocation retains the stable handle until serialization
translates it to that final index. Rearranging the symbol table must not
rearrange a call's meaning.

Sources: [persistent object
records](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L28-L104),
[storage, export and
calls](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L414-L457),
[copied symbol names and
definitions](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L224-L296).

## Let one reorder expose the distinction

Create global `answer` first (handle 1), local `private` second (handle 2), and
global `main` third (handle 3). Supply valid definitions for the two defined
names. The file's row zero is the null symbol. The two passes serialize
`private` as index 1, `answer` as index 2 and `main` as index 3. The first
nonlocal index is 2.

Our relocation's handle 1 becomes ELF index 2. It still names `answer`. A reader
who copied handle 1 directly into the file would instead name `private`; its
relocation could be well formed yet have the wrong destination. Identity must be
translated at the consumer boundary.

Each ELF symbol occupies 24 bytes, unlike the writer's eight-cell internal row.
Each RELA record also occupies 24 bytes: eight-byte offset, eight-byte packed
kind/index information, and eight-byte explicit signed addend. For −4, that last
field is `FC FF FF FF FF FF FF FF`. The original zero call field is not an
implicit addend.

Sources: [local-first symbols and RELA
serialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L370-L410).

## Build the envelope after the records agree

The fixed ten-section table has a null row, four payload rows, two relocation
rows, the symbol table, the symbol-name strings and the section-name strings.
Section names are strings; section roles are the numbered contract the linker
validates. Relocation rows link to the symbol table and identify the section
they patch. The symbol table links to its own string table and records the
local/nonlocal boundary.

`cc-obj-build` begins a 64-byte ELF header with ELF64, little-endian, AMD64 and
ET_REL facts. It emits the three file-backed payloads, records BSS metadata
without its payload, emits symbols before relocations so final indexes exist,
then the strings. Finally it aligns and emits ten 64-byte section headers and
patches the header's section-table offset. Section-table order need not equal
payload-file order.

There are no executable program headers or chosen process entry. The ELF family
name still does not make this file a process image. This writer intentionally
excludes arbitrary sections, TLS, COMDAT, dynamic linkage and exception-unwind
machinery.

Sources: [section metadata
initialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L331-L358),
[object envelope and build
order](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L411-L450).

## Bound each resource separately

The default workspace keeps text, data/rodata, symbols, names and relocation
records under independent capacities. The direct workspace uses mapped backing
and raises the relevant limits: text to 4 MiB, each data section to 2 MiB,
relocations to 20,992, symbol rows to 8,192 and name bytes to 77,824. BSS has
its own 1 GiB memory limit. These are selected limits in source, not
measurements made for this lesson.

The comments attribute larger capacities to complete GCC/binutils units. They do
not prove those units fit every other compiler table. `123` has its own
stable-record table, which is not the writer's symbol table. A source may fit
its emitted text and still overflow records or name storage.

Workspace selection occurs before initialization and emission. Selecting another
buffer is not a migration of a live object. Bounds checks reject high-bit counts
before signed comparisons and use remaining space before pointer arithmetic.
Keep the original source assumptions about valid readable name spans and bounded
input; a checked count is not a universal memory-safety proof.

Sources: [independent workspaces and
capacities](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L32-L125),
[adapter record
capacity](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L7-L32).

## Publish only a complete object

A finished output buffer is still builder memory. `cc-obj-write` validates and
builds before creating a sibling temporary file. The temporary uses exclusive
creation, so an existing temporary is not owned and must not be unlinked by a
failed attempt. The write loop retries EINTR and accumulates positive partial
writes; zero progress or another failure abandons the owned temporary.

Closing also matters. The object writer marks its descriptor invalid immediately
after the close attempt, because Linux can release it even when close reports an
error. Only a successful close and rename publish the final path. Special-file
destinations are rejected. This publication state is reset separately from
section metadata.

That is stronger than C19's one-write legacy path, but it remains an inspected
implementation. No new file or failure transcript has been observed here. G05
will validate the stored object as a consumer rather than trusting its
producer's intention.

Sources: [temporary ownership and
publication](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L451-L507).

## Walk the record through three owners

Put three columns on paper: parser, object adapter, file writer. Start in the
parser column with the name `answer` and its function signature. This
information lets the compiler check a call while it is compiling the caller. It
does not give the caller a final destination address. In the adapter column,
record an undefined function with lasting identity. In the writer column, record
the copied name and the handle that relocations can retain. At this point, none
of the three columns needs the function's final virtual address.

Now let the parser finish a scope. Its live symbol prefix can shrink, permitting
a later declaration to reuse a row. Cross out that row's earlier parser
ownership; do not cross out the adapter record or the writer's copied name.
Those records survive because an object use can outlive the declaration walker
that first encountered it. This is a concrete reason for the extra tables.
“Stable symbol” is incomplete unless we say stable across which event.

Next serialize the local-first table. Add a fourth column headed file index.
Give `answer` index 2 in the supplied example, while leaving its writer handle 1
intact in the third column. At this transition the writer rewrites the
relocation's representation of identity. It does not ask the parser to resolve
the name again. The adapter's lasting record and the writer's local-first
translation solve different lifetime problems.

Finally, imagine a linker reading only the finished file. It has no access to
these earlier three columns. The serialized relocation must therefore contain
enough information to locate its symbol in the file's table. An internal
pointer, reused parser row or unconverted writer handle would be meaningless to
that reader. The file is an interface between independently running tools, not a
memory image of the compiler's tables.

Sources: [persistent object
records](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L28-L104),
[storage, export and
calls](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L414-L457),
[copied symbol names and
definitions](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L224-L296),
[local-first symbols and RELA
serialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L370-L410).

## Reconcile the section ledger

Use four rows headed text, read-only data, initialized data and BSS. For each,
record length and required alignment. Make the worked text length 21, rodata
length zero, data length 12 after our aligned reservation, and BSS length 32.
These are supplied lengths, not values collected from G01's sources. The rows
describe 65 bytes of section extent, but that sum is not a prediction of a
65-byte file.

There are three reasons the sum cannot be used as a file-size oracle. BSS
contributes memory extent without a payload. The ELF envelope, names, symbols,
relocation records and section headers contribute file bytes outside those four
extents. Alignment between emitted file components can add further padding. A
zero-length section still has a metadata row in this writer's fixed layout.

Keep a separate file cursor while reading `cc-obj-build`. The emitted text
starts at one file offset, but its call field is still text-relative offset 17
in the relocation record. Later emission of names and section headers does not
alter that 17. The section header tells the consumer where the text payload
resides in the file; the relocation's target-section relationship tells it which
payload to patch. This two-step lookup is why one coordinate cannot replace the
other.

For BSS, inspect the header's type and size rather than seeking thirty-two
freshly emitted zero bytes. The writer has described a memory obligation for the
eventual executable and loader. It has not already fulfilled that obligation by
writing a zero-filled payload. G05 will carry the extent into an executable
segment whose memory size can exceed its file size.

Sources: [section cursors, reservation, alignment and
patching](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L150-L222),
[section metadata
initialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L331-L358),
[object envelope and build
order](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L411-L450).

## Plan an observation that can disagree

A later object-inspection session should retain both the original source and the
actual output before asking whether the paper state agrees. Inspect the file's
identity, payload sections, symbol order and relocation records separately. A
report that merely says “ELF64” has not checked whether handle translation
selected `answer`, whether the field ends inside text, or whether −4 is explicit
in RELA.

Our three-symbol state is a deliberately supplied writer model. A real
compilation may add strings, runtime uses, local labels or other symbol records.
Consequently, its final index for `answer` need not be 2. The meaningful
comparison asks whether the relocation names `answer` after the actual
local-first ordering. Keeping the distinction prevents an innocent extra symbol
from being mistaken for a writer failure.

Publication requires a different observation. To test preservation of an
existing output, retain the old bytes, arrange a bounded failure and inspect the
final path and temporary ownership afterward. Seeing a correct object in memory
does not exercise a partial write, failed close or rename. The chapter has
inspected those source branches; it has not supplied such a failure transcript.
Keep a format check and a publication check as separate entries in the eventual
record.

Sources: [temporary ownership and
publication](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L451-L507).

## Change one record, then ask which consumer notices

Supply a valid object containing our text field, then change only the
relocation's target offset from seventeen to eighteen while retaining text
length twenty-one. The symbol row, name and addend remain valid. The changed
field now asks for one byte beyond the text extent. This failure belongs to
field ownership and bounds before any destination placement is relevant.

Change only the relocation's symbol identity instead. Choose another valid
symbol index. The record can remain structurally in bounds while describing the
wrong destination. A consumer can perform exactly the prescribed arithmetic and
still produce the wrong call for the intended source. This is why the
local-first identity walk is part of teaching the writer, rather than an
optional detail after checking ELF magic.

Change only the symbol name's caller buffer after creating the writer record.
The copied writer name should retain its earlier bytes under the inspected
ownership contract. The eventual consumer never sees the reused caller buffer.
By contrast, changing the writer's owned string storage itself would change the
object being built. A copied name solves one lifetime boundary; it does not make
all builder memory immutable.

These three changes give different predictions. Keep them in a small ledger:

| Changed input | First relevant contract | Predicted issue |
|---|---|---|
| Field offset 18 with text end 21 | Whole-field bounds | Rejection before relocation is recorded |
| A different valid symbol identity | Identity translation | Well-formed obligation with another meaning |
| Caller name buffer reused after creation | Copied-name ownership | Existing writer name remains intact |

The first case expects a checked failure. The second expects a changed meaning,
which requires comparison with the intended source to diagnose. The third
expects preservation. A single test oracle such as “object accepted” cannot
distinguish all three.

When reading the source again, begin at the public operation that consumes the
changed input. Follow its guard before its table mutation. For identity
translation, continue through the symbol passes and relocation serialization.
For name lifetime, locate the copying operation and the stored string offset.
This reading sequence turns the broad claim “the writer checks its inputs” into
three specific questions that can be answered from its mechanisms.

The ledger is a supplied failure model. It is not an account of a malformed file
being written or fed to the linker. A later observed record should identify
whether the producer rejected construction or a separately altered stored file
reached consumer validation. Those are different experiments even when both
concern the same four-byte field.

Sources: [persistent object
records](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L28-L104),
[storage, export and
calls](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L414-L457),
[copied symbol names and
definitions](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L224-L296),
[local-first symbols and RELA
serialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/081-cc-object.fth#L370-L410).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](01-a-program-from-two-files.md) remains available for a
specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/02-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G2-01 — Locate the obligation

For text end 21, derive the first and last bytes of a four-byte relocation at
offset 17. Would offset 18 fit? Name the coordinate. Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G2-02 — Align before reserving

Starting with data length 5, align to 8 and reserve four bytes. Give padding,
object offset and new length. Explain which supplied rule determines your
answer. Keep any prediction separate from a claim that the corresponding program
or build was run.

### G2-03 — Translate identity

Use the three-handle worked state. What file index must a relocation to handle 1
contain, and why? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G2-04 — Count memory and file bytes

Reserve 32 bytes in BSS. Which extent grows? Can cc-obj-byte supply its payload?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G2-05 — Keep the addend explicit

A PLT32 field contains four zero bytes and its RELA addend is −4. Which supplies
the adjustment? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G2-06 — Preserve an old output

A partial write succeeds, then close reports failure. Is the final path ready to
publish? Identify the owned resource. Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G2-07 — Bound the claim

An inspector verifies ET_REL and ten sections. Does that establish final
placement or execution? List the remaining boundaries. Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

## What this mechanism makes available

You can now separate one definition/use into two objects; inspect symbols and
one relocation. Use the state transitions above to justify that explanation,
rather than treating a source filename or a successful later milestone as a
substitute for the mechanism.

Continue to [G03: Signatures, declarators, and ranked
arrays](03-signatures-declarators-and-ranked-arrays.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
