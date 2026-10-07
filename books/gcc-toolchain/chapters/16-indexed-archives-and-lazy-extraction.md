# Indexed archives and lazy extraction

An archive member that appears earlier than its consumer can still be selected
during a rescan. Why does the same argument not make an earlier archive on the
command line available forever?

Follow start.o’s initializer demand through one archive, then move that archive
before its consumer. The story separates a fixed point inside one archive from
command-order search across inputs.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G02 supplies object identities and G05 supplies strong/weak resolution. An
**archive index** maps exported names to member-header positions; it is not a
machine address. Extraction selects a whole object member. The model below
supplies named exports and dependencies rather than a measured libseed.a
selection dump.

## Native archive updates

The Python archive adapter's fresh-output restrictions remain its contract.
Native seed-ar additionally replaces the first same-basename member in place
and appends new members, rewriting the whole archive/index through Forth. It
accepts r without c; members have no dates, so u always replaces. A fresh archive
still matches the Python adapter's bytes. See [the differences](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/SEED-CC.md#L89-L106).

## Build an envelope with an index

The Forth builder reads and validates ordinary object inputs, collects their
global/weak definitions and copies their bytes. Local names do not enter the
index. A regular ar envelope has an eight-byte magic, fixed member headers,
decimal metadata fields and even-byte member padding. Long names use the
supported GNU name table.

The index count and offsets are big-endian four-byte fields, unlike the
little-endian ELF objects inside the members. Mixing those byte orders would
send a reader to the wrong header. Member names and offsets identify archive
contents; the object linker still owns symbol placement after extraction.

The deterministic writer plans offsets before emission, then writes index, long
names and members in retained order. Fresh creation is its supported operation.
The driver’s archive adapter rejects incremental replacement instead of claiming
full GNU ar behavior.

Sources: [indexed deterministic archive
construction](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L1-L221),
[fresh-archive adapter
contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L126-L134).

## Validate the envelope before following an index

The reader checks the whole archive envelope and index: member spans, declared
sizes, decimal/octal fields, padding, long-name references, index member offsets
and name terminators. A malformed offset is not accepted merely because it
points somewhere inside an object payload.

Unselected members are not all passed through the ELF linker. Their outer
envelope is validated, while their payload’s object validation is deferred until
selection. This is the intended lazy boundary. Thin archives and unsupported
encodings remain rejected.

Selected member bytes are copied into linker-owned mappings, so closing the
archive cannot invalidate chosen symbol-name spans. The source archive’s
identity is retained separately for output alias checking, even if no member
supplied a needed name.

Sources: [envelope/index validation and archive
lifetime](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L222-L382).

## Let one demand introduce another

Supply archive order environment.o, startup.o, spare.o. startup.o defines
__seed_init_runtime and requires environ; environment.o defines environ; spare.o
has no needed export. Before scanning, eager start.o requires
__seed_init_runtime.

The first pass skips environment.o because environ is not yet demanded. It
selects startup.o, whose complete symbol table introduces environ. On the next
pass it selects environment.o. A later pass adds nothing and finishes. The
selected order is startup.o then environment.o, despite their original archive
order.

The loop marks each selected member once and repeats until no new member is
selected. Finite member count bounds this selection process under valid inputs.
The fixed point concerns membership and unresolved demands inside this archive;
it is unrelated to G25’s compiler-byte comparison.

Sources: [strong demand and repeated member
selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L413).

## Use strength at the demand boundary

Only a strong unresolved global name triggers extraction. An undefined weak name
alone does not pull a member. A member’s weak definition may nevertheless
satisfy an already strong unresolved name. Local symbols never appear in the
global-demand index.

When selected, the entire object enters the linker. If one selected function
needs a second name elsewhere in that object, that name still needs resolution
even if the first program path never executes the second function. Lazy member
selection is not function-level dead-code removal.

Likewise, a competing runtime provider can replace an entire unselected member
without collision, but supplying one of its names while still requiring another
from that same member can select both definitions and expose a duplicate strong
symbol. Names, members and runtime paths must not be conflated.

Sources: [strength and index
selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L398),
[member granularity and command-order
behavior](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L66).

## Close one archive before moving to the next input

Put libhelpers.a before consumer.o. At that first position no current strong
demand may select its answer member. consumer.o later introduces answer, but the
driver does not reopen earlier archives automatically. Put the library after its
consumer, or explicitly repeat it at a later input position, to give the demand
a search opportunity.

Within one archive, newly selected members justify rescanning because that
search is still active. Across input positions, command order is a separate
contract. All -L directories inform -l lookup even when the directory option
appears later, but the found archive is still searched at the -l position.
Directory collection is not archive extraction.

The default driver links eager start.o before user inputs and libseed.a
afterward. That order makes main demand visible even if an archive supplies
main. Explicit libm lookup has its separately documented source-built fallback;
no host shared library directory appears in this static route.

Sources: [library path and extraction
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L51-L66).

## Rescan the archive when a new need appears

Supply an archive with member A defining `helper` and referring to `support`,
member B defining `support`, and member C defining an unrelated function. Before
reaching the archive, supply an object that needs `helper`. The index offers A
as a provider, so the linker selects A. A's undefined use adds `support` to the
current needs. Another scan selects B. C remains unselected.

This is a fixed point inside this archive: after adding selected members, scan
again until no current need selects another member. The completed state contains
the original object, A and B. It is not the entire archive simply because the
archive appeared on the command line. Lazy extraction changes which source-built
runtime objects actually enter the executable.

Swap A and B's physical positions within the archive while retaining a correct
index. The iterative selection should still reach the needed member closure
under this model. That does not make the whole command line order independent.
The algorithm has a rescan boundary tied to the current archive, not an
unrestricted promise to revisit all earlier inputs.

Sources: [envelope/index validation and archive
lifetime](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L222-L382).

## Move the need across the command-line boundary

Place the same archive before the original object that introduces `helper`. At
that earlier point, supply no strong unresolved need for `helper`. The archive
contributes neither A nor B. Later, the object adds the need, but the already
passed archive is not automatically reopened. The final unresolved state
therefore differs even though the command line names the same files.

Place the archive after that object and the original two-pass closure works
again. This is why “all providers exist somewhere among the inputs” is too weak
a linkability statement. Required definitions must be offered under the command
line's selection rules. G01's runtime ordering belongs to the actual successful
contract, not incidental command formatting.

Weak and strong identities add another distinction. A strong need can be
satisfied by an admitted weak provider, but a weak undefined symbol does not
itself drive extraction in the same way. Preserve the binding alongside the name
when tracing the unresolved set. Treating every name in an undefined listing as
the same demand would select too many members.

Sources: [strong demand and repeated member
selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L413).

## Validate the index before trusting the shortcut

An indexed archive maps names to member locations. Those locations must lead to
valid member headers and payload spans. The index's integer byte order differs
from the ELF member format, so a reader cannot apply one little-endian routine
to every number merely because all members target AMD64.

Once selected, a member is consumed as an entire object. The linker does not
extract one symbol's byte range and discard the object's other definitions or
relocations. That whole-member rule explains why selecting A creates its use of
`support`, and why an unexpected duplicate definition can arrive with a needed
helper.

An eventual observation should retain the ordered input list, archive index,
selected-member list and unresolved transitions. A final executable alone cannot
reveal why an unneeded runtime object was omitted. The paper archive supplies
its member graph and names explicitly; no new archive was generated or
extraction report recorded for this lesson.

Sources: [indexed deterministic archive
construction](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L1-L221),
[fresh-archive adapter
contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L126-L134),
[strength and index
selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L398),
[member granularity and command-order
behavior](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L66).

## An extracted member changes more than the needed name

Supply a member selected because it defines one required function. That member
also defines another strong global and refers to a third function from an unused
body. Whole-object inclusion brings both facts into the link. The
duplicate-definition check and unresolved set must see them even if the final
program never calls that unused body.

Archive selection therefore works on members, not on reachability of individual
instructions. The index is a shortcut from a needed name to an owning member.
After selection, the ordinary object consumer validates and exposes that
member's complete symbol/relocation obligations. Treating the index as a
function extractor would bypass those obligations.

Selected member bytes need a lifetime independent of closing the archive input.
The linker retains their mappings and borrowed name spans as its own inputs. A
valid index followed by a dangling name pointer would still make later
resolution invalid. Bounds and ownership are both required at the handoff.

| Archive operation | Immediate product | Next owner |
|---|---|---|
| Read index | Name/member-offset associations | Archive selector |
| Match strong unresolved need | Chosen member identity | Extraction |
| Copy/retain member | Independent object bytes | Ordinary object consumer |
| Add member obligations | Expanded symbol/use state | Same-archive rescan |
| Reach no-new-member state | Local selection closure | Remaining command-line inputs |

The final row names the fixed point precisely. It closes this archive's
extraction search under current needs. It does not close every need that a
future command-line input might introduce, and it is unrelated to G25's
compiler-generation comparison. Two loops reaching a fixed point can have
entirely different state domains.

A weak unresolved name alone does not trigger the same demand. A selected member
may still supply a weak definition for a strong need under resolution rules, but
extraction demand and provider precedence must be kept distinct. This avoids
both missing a permitted provider and extracting unnecessary members.

A prospective trace should save command order, the index, selected members, new
obligations and their retained object identities. That evidence could explain
why an archive placed too early remained unused. The chapter has derived its
startup/environment and helper graphs on paper; no archive manipulation or new
link-selection trace was performed.

Sources: [envelope/index validation and archive
lifetime](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L222-L382),
[strong demand and repeated member
selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L413),
[strength and index
selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L398),
[member granularity and command-order
behavior](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L66),
[library path and extraction
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L51-L66).

## Use the archive index as a map, then verify the destination

An archive contains headers, naming conventions, padding and member payloads
around its embedded objects. The index maps global names to member locations,
with its own big-endian count and offsets. The member objects then use their
ELF64 little-endian representation. A file reader crosses a format boundary
before reaching the object consumer.

The archive parser must validate each header and payload extent before
interpreting a selected object. A name match with an out-of-range offset is a
malformed map, not an unresolved C function. Unsupported archive variants remain
outside the bounded reader; familiar ar suffixes do not authorize arbitrary
encodings.

For a selected member, keep the archive location and retained object identity
separately. After copying the bytes into linker-owned storage, the ordinary
object consumer can validate its sections, symbols and relocations. Closing the
archive input should not invalidate any name spans needed by later symbol
resolution.

Supply the startup/environment graph from the chapter. The initial unresolved
initializer selects startup. That whole object introduces environ. Rescanning
selects environment. An unrelated spare member remains absent. At completion,
the selected object set is larger than the first directly needed member but
smaller than the whole archive.

Now add an unused function inside startup that refers to another required name.
Because selection occurs by whole member, that use joins the unresolved set even
if main never reaches the function. A later instruction-level dead-code analysis
is not part of this member-selection contract. The link must close the exposed
object obligations.

Move the archive before the consumer that first needs its names. Its scan now
happens with a different unresolved set. It can complete without selection and
is not automatically revisited after later objects add needs. Local same-archive
rescans and global command-order revisits are different policies; the inspected
source supplies the former.

Weak binding must remain beside every relevant name. Strong unresolved demand
triggers extraction; a weak use alone does not. Provider precedence then chooses
among definitions that have actually entered the link. A provider cannot win
resolution if its containing member was never selected.

For a later observation, retain the exact ordered command inputs, archive index,
selection passes, newly introduced uses and final unresolved set. The final
executable's symbols can confirm what arrived but may not explain every omitted
member. Our graphs and order changes are supplied paper cases, with no new
archive or extraction run.

Sources: [indexed deterministic archive construction](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L1-L221), [fresh-archive adapter contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L126-L134), [envelope/index validation and archive lifetime](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L222-L382), [strong demand and repeated member selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L413), [strength and index selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/141-archive.fth#L384-L398), [member granularity and command-order behavior](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L45-L66), [library path and extraction order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/gcc-direct/README.md#L51-L66).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](15-aggregate-values-and-x87-transport.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/16-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G16-01 — Separate byte orders

Which archive fields use big-endian four-byte values despite little-endian ELF
payloads? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G16-02 — Trace a rescan

Give selection order for environment/startup/spare in the supplied model.
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G16-03 — Use strong demand

Does an unresolved weak name alone pull a member? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G16-04 — Keep whole members

A selected object contains an unused function’s strong reference. May it be
ignored just because that function will not run? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G16-05 — Respect input order

Why can libhelpers before consumer leave answer unresolved? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G16-06 — Preserve lifetime

Why copy selected member bytes before closing the archive? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G16-07 — Name the fixed point

What does “no new archive member” establish? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

## What this mechanism makes available

You can now teach member selection needed by runtime link; revisit member
identity before comparisons. Use the state transitions above to justify that
explanation, rather than treating a source filename or a successful later
milestone as a substitute for the mechanism.

Continue to [G17: Frozen driver, configure, and source
census](17-frozen-driver-configure-and-source-census.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
