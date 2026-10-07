# Aggregate values and X87 transport

Passing a record by value must pass its bytes, even when expression evaluation
represents it by an address. Who makes the copy, and what happens when only one
argument register is left for a two-word record?

We will place a small integer record, force a rollback to stack storage and then
follow a memory return. Long double uses the same address representation but a
distinct X87 transport contract.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G04 supplies scalar plans, G10 floating classes, G12 variadic cursors and G14
record layout. An **eightbyte** is an ABI classification chunk, not a
declaration that every member has eight-byte storage. A snapshot is an owned
copy whose bytes survive later argument evaluation.

## A long-double computing state

For supplied `long double x=1.0L; x+=2.0L;`, the numeric result is three.
Layer 132 loads extended payloads, performs the operation and pops the result
into a private sixteen-byte frame object; the assignment stores the ten-byte
payload into x. The argument ABI remains sixteen-aligned stack transport, and
a result still crosses st(0). Exact literal/static bytes come from 125/128,
not a host floating parser. See [operators and owned results](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/132-cc-long-double.fth#L109-L193)
and [static initialization](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/132-cc-long-double.fth#L201-L239).

## Classify the bytes behind the address

The record expression carrier contains an address. The classifier recursively
visits members, nested records, unions and arrays, checking real element types
and offsets. It cannot classify only the first member or assume a naturally
laid-out parser always guarantees aligned input metadata.

An admitted aligned integer record of up to sixteen bytes uses one or two
INTEGER eightbytes. Larger or unaligned admitted records use MEMORY. Scalar
float/double use SSE independently. Binary32/binary64 record members and vector
classes are unsupported rather than quietly assigned to INTEGER.

Long double is represented as a sixteen-byte opaque object aligned sixteen. An
object containing only admitted long-double leaves in that sixteen-byte shape
can classify X87; mixed leaves force MEMORY. Classification rejects unsupported
leaves even inside nested arrays. This is a bounded classifier, not the entire
AMD64 aggregate ABI.

Sources: [recursive classifier and
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L1-L79).

## Require enough registers for the whole value

Supply five earlier INTEGER scalars followed by a sixteen-byte two-long record.
Five GP registers are consumed, leaving one. The record needs two. The planner
places the entire record on the stack and consumes no part of that last
register. A following scalar can therefore use R9.

Splitting the record between R9 and stack would violate the selected
whole-argument placement. That is the rollback rule: test the whole register
demand before committing. INTEGER and SSE counters are independent; the argument
index cannot double as the register index.

Each argument record retains type, descriptor, size, class, first register or
stack marker, stack offset and snapshot frame slot. Stack objects align to eight
or sixteen according to class and are rounded to whole slots. Named parameter
planning consumes the same locations, making the caller and callee agree.

Sources: [argument records and whole-value
location](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L96-L177).

## Snapshot before another expression can change it

Suppose the first by-value argument is record r and a later argument expression
mutates r. The first argument must retain the value captured when its evaluation
completed. Saving only r’s address would allow the later call to change the
bytes eventually passed as the first value.

The selected planner copies argument bytes to a zeroed frame snapshot, then
places that snapshot. Zeroed padding avoids reading past a short record when
loading a whole ABI word. This is distinct from copying the caller’s live stack
span to protect temporary state across the call.

Outgoing stack copies occur before register loads because REP MOVSB uses GP
argument registers. On callee entry, register parameters are spilled before
stack copying for the same reason. The two sides must use ownership-aware
sequencing, not just the same nominal type.

Sources: [snapshot and outgoing-copy
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L158-L273),
[entry register spill
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376).

## Return to caller-owned storage when registers are insufficient

Small INTEGER record results use RAX and, when needed, RDX. The callee stages
the bytes to avoid overreading the original object; the caller stores result
registers into its own result slot and keeps its address as the expression
carrier.

A MEMORY result uses a hidden caller-owned destination pointer as the first
INTEGER argument, consuming a GP register before explicit arguments. The callee
copies the complete result into that object and returns its address in RAX. This
is not a pointer to a dead callee local. A single long parameter following a
hidden return pointer therefore begins at RSI rather than RDI.

Result capture occurs before restoration can disturb it. Function plans retain
the hidden destination in a frame slot. The result’s type/descriptor remain
available until the copy finishes, so changing expression metadata too early
cannot silently shorten it.

Sources: [caller result
capture](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L262-L273),
[small and hidden
returns](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L377-L411).

## Separate X87 transport and computation

Long-double arguments use sixteen-aligned stack copies, even when GP or XMM
registers remain. Results use x87 st(0); the callee loads the ten-byte extended
payload, and the caller stores it into its sixteen-byte result object. Its
padding and ABI allocation size differ from the encoded precision.

Layer 131's transport-only defaults are now replaced by layer 132 for long
double computation: +, −, *, /, comparisons, truth tests, numeric conversions,
unary operations, updates and exact static initialization. Bitwise operators
and remainder on long double remain rejected. Results live in owned frame
objects rather than remaining on the x87 stack.

Records cross prototyped, unprototyped and variadic calls with unchanged default
promotions, and va_arg retrieves INTEGER, MEMORY and admitted X87 records.
K&R float entry conversion still rejects. Unsupported floating record members
and vector classes remain separate limits.

Sources: [opaque long-double
identity](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L253-L278),
[signature form
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L122-L132),
[X87 scalar-use and variadic
completion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L413-L544).

## Roll back a partial record assignment

Supply a call in which five earlier general-class arguments have consumed RDI
through R8. Only R9 remains available. The next supplied record needs two
integer-class chunks. One free register is insufficient for the record's
complete register assignment, so its entire value goes to the stack under the
selected rule.

Leave R9 available for a later scalar argument. This is the point of rollback: a
tentative assignment of the record's first chunk must not permanently consume
that register after the whole-record assignment fails. A greedy
one-chunk-at-a-time algorithm would leave the record split across incompatible
locations and deprive the later scalar of its rightful register.

Write the destination plan before writing moves. The five early scalars have
register destinations, the record has a stack extent, and the later scalar has
R9. The record's two chunks still describe its value, but no longer describe two
independently assignable arguments. Classification units and source-language
values are related without being identical.

This case extends G04's scalar planner rather than replacing its alignment and
lifetime contracts. The overflow region must remain aligned; inner evaluations
must preserve already staged values; the caller's stack state must be restored
after return. Adding aggregate classification cannot excuse losing any of those
earlier obligations.

Sources: [argument records and whole-value
location](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L96-L177).

## Snapshot the value at the argument boundary

An aggregate expression denotes several bytes. Evaluating another argument can
alter the storage from which those bytes came. The selected call path therefore
snapshots the aggregate value it has evaluated, preserving what will be supplied
when the call finally transfers arguments.

Supply a record source whose first chunk is one and second chunk is two, then a
later argument evaluation that changes the original second chunk to nine. The
supplied earlier value remains the snapshot containing one and two. The staging
object and the original source object are different owners after that snapshot.
This example exposes the mechanism without claiming a universal source
evaluation order for all C calls.

A returned small record likewise uses the selected result chunks and must become
a coherent expression value before a later operation overwrites result
registers. An address pointing at old scratch storage is insufficient if that
storage's lifetime has ended. Follow the producer's result representation into
the expression consumer and its owned snapshot.

Sources: [snapshot and outgoing-copy
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L158-L273),
[entry register spill
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376).

## Let hidden inputs remain visible in the plan

A larger memory-return value uses caller-supplied destination storage. Its
hidden pointer occupies the designated first integer input position. That shifts
the positions available to explicit arguments. A source signature listing only
those explicit arguments cannot describe the machine call plan until the return
convention is applied.

Keep destination lifetime as well as position. The callee writes into storage
owned by the caller, and the caller consumes the completed result after return.
The pointer is not a returned heap allocation merely because it crosses a
function boundary. Its storage strategy belongs to the caller's expression and
frame planning.

Long double has its own X87 transport: stack argument space with sixteen-byte
alignment and an X87 result boundary. Copying its admitted bytes and returning
through ST0 do not establish broad X87 arithmetic support. Records with
unsupported floating member classifications remain rejected by this provider. A
later inspection should record the declared type, classification, rollback
decision and actual transport; these supplied aggregate states are still paper
examples.

Sources: [caller result
capture](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L262-L273),
[small and hidden
returns](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L377-L411),
[opaque long-double
identity](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L253-L278),
[signature form
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L122-L132),
[X87 scalar-use and variadic
completion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L413-L544).

## Protect incoming values before copying the stack

At function entry, some parameters arrive in general registers and others in the
stack argument region. The selected aggregate copier itself uses general
registers. Consequently, copying a stack parameter before saving the incoming
register parameters could destroy an input that has not yet reached its local
destination.

The entry provider spills register parameters first, then performs the stack
copies. This ordering is not merely a performance choice. It establishes that
the byte copier owns its temporary registers only after the original parameter
values have durable frame locations. An eventual inspection can check both the
correct local bytes and this required preservation order.

A hidden memory-return pointer is another incoming register value. It identifies
caller-owned storage in which the callee must complete the result. Explicit
arguments shift after that position is occupied. Returning a pointer to a callee
local cannot substitute for this convention because its lifetime ends with the
callee frame.

| Value boundary | Owner that must preserve it | Completion |
|---|---|---|
| Evaluated record argument | Caller snapshot | Transported as the captured bytes |
| Incoming register parameter | Callee entry provider | Spilled before clobbering copies |
| Stack parameter | Callee frame copy | Local destination populated |
| MEMORY return destination | Caller | Callee has completed result bytes |
| Small record return chunks | Result adapter | Expression obtains a durable value |

Return classification and argument classification cooperate with the scalar
rules rather than replacing them. A result pointer can consume a general
position; a record can roll back tentative positions; later scalar arguments can
still use remaining positions. Planning destinations before generating moves
lets the implementation honor these interactions.

X87 transport similarly needs an explicit stack class and result boundary.
Sixteen-byte argument alignment can add padding beyond the value's payload.
Returning through ST0 is the transport contract; layer 132 supplies computation.
Unsupported floating record members remain an admission limit even though
separate scalar floating values use XMM registers.

For a later fixture, retain the type layout, destination plan, snapshots, entry
spills and result ownership. Comparing only the final record bytes could conceal
an expired-source read that happened to survive. Comparing only register
assignments could miss lost stack-copy values. These are supplied contracts and
inspection questions; no new aggregate caller/callee program was run.

Sources: [argument records and whole-value
location](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L96-L177),
[snapshot and outgoing-copy
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L158-L273),
[entry register spill
order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376),
[caller result
capture](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L262-L273),
[small and hidden
returns](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L377-L411),
[opaque long-double
identity](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L253-L278),
[signature form
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L122-L132),
[X87 scalar-use and variadic
completion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L413-L544).

## Read the classifier before counting registers

The aggregate classifier walks nested records, unions and array elements. It
examines real member types and offset alignment, not only the enclosing byte
extent. An object of sixteen bytes can require a different class from another
object of sixteen bytes. Equal size does not establish equal ABI transport.

The walk notices long-double leaves separately from other leaves. An aligned
sixteen-byte object containing only the admitted long-double shape can use X87.
Mixing other leaves with that shape forces MEMORY under the selected rule.
Binary32/binary64 record members and vector classes remain unsupported rather
than being silently treated as integer chunks.

The resulting class is stored in a call plan together with type, descriptor,
byte size, register/stack destination and snapshot slot. The argument's source
index is therefore independent of its register index. A hidden memory-return
pointer can spend the first general position before explicit arguments; an
earlier record can spend two positions; another record can spend none after
whole-value rollback.

The caller first captures evaluated values into owned snapshots. It then copies
outgoing stack bytes before filling general registers, because the copier uses
those registers. The callee performs the complementary ordering: spill incoming
register values before stack copies use the same temporary registers.
Destination agreement without these preservation steps would still lose values.

Result handling must happen before restoration disturbs its carriers. For a
small integer record, the caller captures RAX/RDX into its result storage. For
MEMORY, the callee writes the hidden caller-owned destination. For X87, the
result crosses ST0 and is stored into the admitted opaque object. Each supplies
an expression with a durable owner.

The record expression's internal carrier is an address, but the ABI passes the
record's bytes. Passing that address as an ordinary pointer would change the
interface into reference-like behavior. This distinction is especially visible
when later argument evaluation mutates the original record after the earlier
snapshot was taken.

Signature forms now admit unspecified/variadic record calls and aggregate
va_arg. Classifier admission remains bounded: binary32/binary64 record members
and vectors are not supplied. The wider signature support does not remove
those class limits.

The paper two-long example and rollback case let a reader derive the plan
without a complete generated-function audit. A future execution can inspect
actual spills, snapshots, result storage and target status. No new record
program or X87 transport has been observed for these manuscripts.

Sources: [recursive classifier and limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L1-L79), [argument records and whole-value location](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L96-L177), [snapshot and outgoing-copy order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L158-L273), [entry register spill order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376), [caller result capture](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L262-L273), [small and hidden returns](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L377-L411), [opaque long-double identity](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L253-L278), [signature form limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L122-L132), [X87 scalar-use and variadic completion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L413-L544).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](14-bitfield-layout-and-preserving-stores.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/15-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G15-01 — Classify a record

Classify a naturally aligned two-long sixteen-byte record under the admitted
integer rules. Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G15-02 — Roll back registers

Five GP scalars precede the two-eightbyte record. Where does it go? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G15-03 — Snapshot a value

Why not retain only r’s address when a later argument mutates r? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G15-04 — Order copies

Why spill register parameters before stack copies? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G15-05 — Allocate a hidden result

A MEMORY return precedes one explicit long argument. Which register carries that
argument? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G15-06 — Transport long double

Does a long-double argument use XMM0 when available? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G15-07 — Protect result lifetime

Why is returning a pointer to a callee local not the MEMORY return model?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now identify aggregate abi support before dependent production workload.
Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G16: Indexed archives and lazy
extraction](16-indexed-archives-and-lazy-extraction.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
