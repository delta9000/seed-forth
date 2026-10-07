# Variadic cursors and argument classes

After a named integer parameter, a function receives an integer, a double and
another integer. Can one cursor through six registers retrieve them all?

We will walk the actual va_list fields on paper. The answer requires independent
register banks and a shared overflow area, rather than treating every ellipsis
argument as a word on one stack.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G04 supplies fixed-call transport and G10 supplies floating classes. A
**variadic** function has a fixed prefix and an ellipsis tail. The caller uses
default promotions for that tail, while the callee’s va_arg type tells it which
class to consume. A wrong requested type cannot be repaired by inspecting the
stored bits.

## A two-eightbyte tail record

Supply gp_offset=32 and an admitted sixteen-byte INTEGER record. Two GP slots
remain, so retrieval uses reg_save_area+32 and advances gp_offset to 48. Change
only gp_offset to 40: one slot is insufficient, so the whole record comes from
overflow and gp_offset stays 40. This is a derived state, not an executed
varargs fixture. See [record retrieval](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L490-L523).

## Use the record the header actually declares

stdarg.h declares __seed_va_list_tag with unsigned int gp_offset and fp_offset
at offsets zero and four, then overflow_arg_area and reg_save_area pointers at
eight and sixteen. The record is 24 bytes, aligned eight, and va_list is an
array of one record. In a parameter declaration that array adjusts to a pointer,
not a by-value record copy.

The provider checks this descriptor’s size, alignment, field count, offsets and
types before using its generated access instructions. A familiar typedef name is
not enough. va_start, va_arg, va_copy and va_end expand to recognized target
intrinsics rather than ordinary linkable C functions.

A variadic invocation reserves 22 eight-byte frame slots for the 176-byte
register-save area, aligned for the XMM slots. Six GP values occupy eight-byte
positions; eight XMM values occupy sixteen-byte positions. Only the low eight
bytes of each XMM save slot carry a double payload.

Sources: [array identity and intrinsic
macros](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/include/stdarg.h#L1-L18),
[save area and descriptor
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L1-L66).

## Advance the bank selected by the requested type

Supply one named INTEGER parameter and no named floating parameters. The
starting gp_offset is 8; fp_offset is 48. An unnamed int reads reg_save_area+8
and advances gp_offset to 16. A following double reads reg_save_area+48 and
advances fp_offset to 64, leaving gp_offset at 16. A following long reads the
next GP position and advances gp_offset to 24.

The logical source sequence has three arguments, but it produced two
independently advancing offsets. A counter “argument number two” cannot locate
the double by multiplying two by eight. Its class determines the bank and
stride.

The selected aggregate planner supplies the actual named GP, FP and stack
consumption used by va_start. It accounts for hidden return pointers and
multi-eightbyte named records. The simple one-int example does not justify
applying gp_offset=8 to every signature with one named parameter.

Sources: [start and GP/SSE cursor
paths](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L67-L157),
[named-argument variadic
offsets](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L451-L544).

## Let either bank overflow on its own

GP retrieval compares gp_offset with 48. Once exhausted it reads the overflow
area and advances by eight. Double retrieval compares fp_offset with 176; once
its bank is exhausted it uses the same overflow area and advances by eight.
Exhausting GP does not force a still-available XMM argument onto the stack.

Supply gp_offset=48, fp_offset=48 and an eight-aligned overflow pointer O.
Request a long: it reads O and moves overflow to O+8, leaving fp_offset
unchanged. Request a double next: it still reads the XMM save area, leaving
overflow at O+8. Only a spilled double follows the stack cursor.

The caller and callee must agree on the promoted types. Narrow integer tails
promote, and float tails become double. va_arg requesting float is therefore
outside this supported retrieval surface; the provider admits promoted integers,
pointers, double and the separate X87 transport.

Sources: [bank exhaustion and result-type
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L93-L191).

## Copy a cursor without copying its arguments

va_copy copies the three eight-byte words making up the 24-byte record. The two
records then advance independently while pointing into the same invocation-owned
save area and overflow storage. Copying the record does not create another copy
of every argument.

va_end produces its supported no-op void result; it does not free the caller’s
argument storage or authorize using the cursor after its invocation ends. Array
decay in a va_list parameter means an ordinary passing operation can share
cursor state; use va_copy when an independent traversal is intended.

The intrinsic checks the actual descriptor and rejects unsupported requested
result types. It also runs through the static-initializer category guard, so a
builtin spelling does not smuggle evaluated varargs access into an object’s
constant initializer.

Sources: [copy, end and intrinsic
dispatch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L192-L234).

## Leave wider transport’s boundary explicit

Long double uses class X87 and always retrieves from overflow storage aligned to
sixteen, consuming sixteen bytes. It returns an address to the opaque object
instead of a binary64 payload. Layer 132 separately supplies long-double arithmetic and conversion.

The final 131 provider also supplies aggregate va_arg. An INTEGER record uses
consecutive GP save slots only if every eightbyte fits; otherwise the whole
record uses aligned overflow storage. Other admitted classes use overflow.
Named offsets alone do not establish tail retrieval: its separate provider and
classifier do. Records with float/double members remain unsupported. G15 opens
that classifier and hidden-result rules.

The paper walk has shown which field changes for each admitted type. A future
runtime test should interleave banks, exhaust each independently, copy a cursor
and inspect lifetime-sensitive cases. Correct printf output for three integers
alone would leave the floating and overflow contracts untested.

Sources: [X87 overflow
retrieval](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L158-L191),
[aggregate-varargs
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L1-L6).

## Walk two cursors through one argument sequence

Supply a variadic function with one named integer argument, followed by an int
and a double. At va_start, the named integer has already consumed one eight-byte
general-register slot, so the general cursor begins at eight. Supply a floating
cursor at forty-eight, the start of the floating-save region. These offsets name
positions in the register-save area, not addresses of source-language arguments
in a single contiguous C array.

Request the int. The general cursor selects its general-register save slot and
advances from eight to sixteen. The floating cursor stays forty-eight. Request
the double next. The floating cursor selects its floating-register slot and
advances from forty-eight to sixty-four. The general cursor stays sixteen. One
source argument sequence has two independently advancing register cursors.

Now reverse the request types without changing the actual supplied arguments.
The cursor mechanism cannot infer that the caller meant a different type. It
follows the requested classification and can read a different region. A
correctly maintained va_list does not make an incorrect va_arg type valid. The
caller, named signature and variadic consumer must preserve their type
agreement.

The save area has space beyond the actual number of floating registers used by a
particular call. The caller supplies the floating-register count in AL for the
ABI. This selected entry provider saves all eight XMM registers unconditionally;
it does not branch on AL to shorten that save. Area capacity and initialized
argument count are different facts. A large save buffer is not a license to
request arguments that were never passed.

Sources: [array identity and intrinsic
macros](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/include/stdarg.h#L1-L18),
[save area and descriptor
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L1-L66),
[start and GP/SSE cursor
paths](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L67-L157),
[named-argument variadic
offsets](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L451-L544).

## Reach overflow without merging the classes

Continue requesting general-class values until the general-register slots are
exhausted. The next general argument comes from the overflow area and advances
that pointer under the selected width/alignment rules. A remaining
floating-register value can still use its own save region. General exhaustion
does not exhaust the floating cursor.

Likewise, exhausting floating destinations need not invalidate general
destinations. The call planner classified and staged these inputs before CALL;
the callee's saved representation lets va_arg retrace those class decisions. The
two halves must agree about promotion and classification even though they run in
different translation units.

An ordinary float in a variadic position is promoted to double before this
boundary. An ordinary narrow integer is subject to the admitted default integer
promotions. The consumer requests the promoted type, not simply the type
originally written in the caller's expression. G10's distinction between storage
width and numeric conversion matters here.

Sources: [bank exhaustion and result-type
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L93-L191).

## Copy traversal state without duplicating the arguments

va_copy produces another cursor state referring to the same argument storage.
Advancing one copy must not advance the other. Supply an original general offset
sixteen and a copied offset sixteen; after one int request through the original,
its offset is twenty-four while the copy remains sixteen. The underlying saved
value has not been duplicated by that cursor arithmetic.

The array-of-one va_list shape matters to C declarations and parameter passing.
It is not interchangeable with an arbitrary pointer typedef just because uses
often look pointer-like. The selected twenty-four-byte record keeps two offsets
and two pointers in defined locations.

X87 arguments will use a separately aligned overflow path in G15. General
aggregate varargs remain outside this chapter's supported consumer. Keep that
limit even after learning aggregate calls: adding a class to a fixed-signature
call planner does not automatically add a matching variadic retrieval
implementation. The cursor states here are supplied paper inputs, with runtime
checks pending.

Sources: [copy, end and intrinsic
dispatch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L192-L234),
[X87 overflow
retrieval](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L158-L191),
[aggregate-varargs
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L1-L6).

## Read the cursor record as four pieces of state

The va_list record contains two four-byte offsets followed by two eight-byte
pointers. On the selected layout, offsets are at zero and four, the overflow
pointer at eight, and the save-area pointer at sixteen. The record extent is
twenty-four and its alignment eight. The C va_list declaration is an array of
one such record, not four interchangeable Forth cells.

The offsets are relative to the save area. The pointers identify actual argument
storage for the current invocation. Copying the record copies this traversal
state; it does not allocate a second set of saved arguments. The original and
copied offsets can diverge while both still read the same earlier argument
bytes.

| Field | What it identifies | What advancement changes |
|---|---|---|
| General offset | Next admitted general save slot | General cursor only |
| Floating offset | Next admitted floating save slot | Floating cursor only |
| Overflow pointer | Next stack argument location | Stack traversal |
| Save-area pointer | Base of saved register representation | Shared argument storage identity |

Supply GP offset forty-eight and FP offset forty-eight. General slots are
exhausted. A long comes from overflow O and advances that pointer by eight. A
following double can still use the floating region and advance FP to sixty-four.
A single “all registers exhausted” flag would lose this state distinction.

For the wider X87 overflow case opened fully in G15, supply O as 0x1008. Round
to 0x1010 for sixteen-byte alignment, consume sixteen bytes, and obtain next
0x1020. The alignment gap belongs to traversal; it is not part of the value's
payload. Integer-only cursor arithmetic cannot be reused blindly for this class.

Named aggregate parameters can affect where va_start begins, because the
selected planner knows their class consumption. A separate 131 hook supplies unnamed
aggregate retrieval with whole-record GP-fit or aligned-overflow placement;
unsupported floating-member classes remain rejected.

A future cursor fixture should retain the declared named parameters, actual
promoted argument types, initial cursor record and each requested type. The
request sequence is part of the contract; the cursor cannot infer it from source
spelling. Our offsets and pointer addresses are supplied states and
calculations, not captured live varargs storage.

Sources: [array identity and intrinsic
macros](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/include/stdarg.h#L1-L18),
[save area and descriptor
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L1-L66),
[start and GP/SSE cursor
paths](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L67-L157),
[named-argument variadic
offsets](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L451-L544),
[bank exhaustion and result-type
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L93-L191),
[copy, end and intrinsic
dispatch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L192-L234).

## A builtin still needs a real descriptor

The stdarg macros expand to names recognized by the selected compiler.
Recognition routes parsing into specialized intrinsic handling; it does not
create linkable functions named va_start or va_arg. The generated instructions
access the cursor record directly, so its exact descriptor matters.

The provider verifies the record tag, size, alignment, field count, field
offsets, field types and nonunion shape. A user-created lookalike with a
familiar typedef name but different layout cannot be accepted merely because
ordinary C syntax parses. The intrinsic's generated field accesses would
otherwise read or overwrite unrelated state.

For va_start, the last named parameter is checked against the selected signature
and frame slot. A named long double can occupy more frame space than an integer
parameter; the final planner supplies the relevant slot and consumed-class
offsets. Counting source parameters alone would not give the right overflow
start.

A variadic entry reserves and aligns its register-save area. This implementation
saves six general registers and all eight XMM registers unconditionally. The
caller still supplies the ABI's floating count in AL, but this particular save
loop does not use it to skip stores. Keep the actual entry implementation
distinct from a possible optimization used by another ABI-conforming compiler.

Retrieval first chooses an address under the requested type's class, then loads
or returns the value using the appropriate representation. General slots advance
eight bytes. Floating save slots advance sixteen while double payloads use only
their low eight bytes. Overflow advances under its admitted type/alignment rule.
The cursor's stride is not always the payload width.

va_copy copies the record's three eight-byte words. The two traversals share
invocation-owned argument storage but own their current offsets separately.
va_end validates the admitted operand and supplies its no-op void result. It
does not end the underlying frame's lifetime early or make a copied list usable
after that invocation has ended.

The intrinsic dispatch also checks the static-initializer category, preventing a
builtin spelling from introducing evaluated argument access into a constant
leaf. This ties the runtime cursor lesson back to G09's selected static
consumer. Builtin recognition is a parser/semantic interface, not a way around
phase rules.

A future record should therefore retain both declarations and actual cursor
transitions. A correctly printed integer sequence can leave descriptor
rejection, independent floating exhaustion and wider overflow alignment
untested. The chapter's field offsets and retrieval walks are supplied
derivations, with no new live variadic invocation.

Sources: [array identity and intrinsic macros](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/include/stdarg.h#L1-L18), [save area and descriptor checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L1-L66), [start and GP/SSE cursor paths](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L67-L157), [named-argument variadic offsets](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L451-L544), [bank exhaustion and result-type checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L93-L191), [copy, end and intrinsic dispatch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L192-L234), [X87 overflow retrieval](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/126-cc-varargs.fth#L158-L191), [aggregate-varargs boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L1-L6).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](11-decimal-literals-rounded-once.md) remains available for a
specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/12-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G12-01 — Locate fields

Give all four field offsets and total va_list record size. Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G12-02 — Walk mixed classes

Use the one-named-int model to retrieve int, double, long. Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G12-03 — Exhaust one bank

At gp=48 and fp=48, retrieve long then double from overflow O. Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G12-04 — Apply promotions

An unnamed float is passed. Which admitted type retrieves its promoted value?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G12-05 — Copy the cursor

Does va_copy allocate and duplicate every argument? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G12-06 — Align wider overflow

A long-double overflow cursor is 0x1008. Give address and next cursor. Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G12-07 — Bound aggregate support

Does a named record’s effect on va_start imply unnamed aggregate va_arg? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

## What this mechanism makes available

You can now supply the selected variadic call contract before its runtime use.
Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G13: Streams and bounded
formatting](13-streams-and-bounded-formatting.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
