# Bitfield layout and preserving stores

Three bits share an allocation unit with a neighbor. How can assigning one field
preserve the neighbor even when the new value has too many bits?

We will update a supplied unit, then follow the descriptor information that
makes the update possible. This is the AMD64 little-endian integer bitfield
provider selected by the direct profile.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G03 supplies field records, G09 supplies static leaves and
[C12](../../c-compiler/chapters/12-places-values-and-delayed-loads.md) supplies
place/value separation. A **unit** is the four- or eight-byte storage accessed
for a field; field width counts bits inside that unit. Bit zero is the low-order
bit.

## Boolean bitfields

`_Bool` bitfields use a one-byte allocation unit and allow width at most one
(zero width only for unnamed fields). Stores load and write that byte while
preserving other bits; conversion yields 0/1. For example assigning 2 to a
one-bit `_Bool` field stores 1. Other integer-field exercises retain their
4/8-byte units. See [admission](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L35-L76)
and [preserving stores and static conversion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L119-L181).

## Describe a field before reading its unit

A System V field record expands to 72 bytes. Its ordinary type, descriptor, name
and byte offset stay distinct from bit width at +48 and shift at +56; the second
array dimension is retained at +64. These are compiler metadata bytes, not
seventy-two bytes per target field.

Named int/unsigned-int fields use natural four-byte allocation units;
long/unsigned-long and admitted long-long variants use eight-byte units.
Consecutive fields share a unit when they fit. A zero-width unnamed field
advances the bit position to its next natural-unit boundary. A union starts its
fields at bit position zero.

The bounded provider rejects named zero-width fields, unsupported types,
arrays/functions, enum-origin fields and widths above the base unit. It also
rejects widths 33–63, retaining its explicit supported range rather than
implying every width up to 64 works. Final record size and padding are checked
against the target object-size limit.

Sources: [record extension, type guards and
layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L1-L107).

## Extract only the field’s signed value

Supply a 32-bit unit 0xA6 and an unsigned field of width three at shift one.
Shift right one and mask three bits: (0xA6>>1)&7 = 3. The rest of the unit is
not the field’s value.

For a signed three-bit field whose extracted payload is binary 111, sign
extension gives −1, not seven. The provider first shifts the unit and then
truncates/extends according to field signedness and width. A subsequent
expression promotion is another step.

Fields narrower than 32 bits promote to int here, including an unsigned
three-bit field whose full range fits int. A full-width unsigned 32-bit field
remains unsigned int. The underlying unit width does not alone determine
expression type.

Sources: [field extraction, truncation and
promotion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L109-L160).

## Clear just the destination bits

Let the same unit be 0xA6, with field width three and shift one. Assign five.
The low field mask is 7; shifted mask is 0x0E. Clearing those positions gives
0xA6 & ~0x0E = 0xA0. New field bits are (5&7)<<1 = 0x0A. OR produces 0xAA.

The low neighbor bit and high bits remain as before. Assigning thirteen has the
same stored low-three-bit payload as five, because 13&7=5. A raw store of five
into the entire unit would destroy every neighbor. A raw OR without clearing
would fail to remove old one bits.

The emitted preserving store loads the unit, clears the destination mask,
inserts the truncated new bits and stores at the base type’s width. The value
expression and the destination address are separate carriers. The unit can be
wider than the field without making the assignment affect all its bits.

Sources: [preserving read-modify-write
store](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L119-L148).

## Apply the same rule to static bytes

Named fields consume initializer elements; unnamed and zero-width fields
influence layout without consuming a value. The initializer callback either
invokes the runtime field store for a local object or evaluates a static
constant and patches the containing data unit. Static leaves reject symbolic
addresses because a bitfield has no address relocation representation.

The static preserving mask keeps initialized neighbor bits in the data
reservation. Missing fields remain in the original zeroed object. A bitfield
address cannot be taken as an ordinary pointer to a byte-addressable object; its
use hook rejects that form.

This reuses 118’s named-field traversal while adding a field-specific leaf. It
does not require making every bitfield a separate object symbol. G02’s symbol
identities refer to whole stored objects, while the bitfield descriptor
identifies a bit range inside one.

Sources: [static and local initializer
callbacks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L161-L193).

## Keep volatility and atomicity separate

Volatile accesses use ordinary unit loads and preserving read-modify-write
stores. They provide neither atomicity nor inter-thread synchronization. A
compound update can perform an operand load and another preserving-store load;
do not present it as exactly one indivisible memory transaction.

Neighbor preservation is a single-threaded value property under the supplied
valid-storage model. Another writer changing the unit between load and store can
invalidate an inter-thread story. The source’s explicit limitation is more
informative than attaching general concurrency guarantees to the volatile
spelling.

G15’s aggregate classifier sees these fields through the same record layout and
base-type rules. Bitfield support is required for actual later sources, but one
successful masking puzzle is not evidence that every aggregate call or source
program was compiled.

Sources: [volatile and synchronization
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L1-L8).

## Label the bits before changing a field

Write the byte 0xA6 in binary as 10100110. Label positions from the least
significant bit upward. A three-bit field beginning at position one occupies
positions one, two and three. Shift the unit right by one and keep three low
bits: the extracted payload is 011, or three.

Now assign five, whose three-bit payload is 101. The field mask is 0x0E. Clear
those positions in the old unit to obtain 0xA0, shift the new payload left by
one to obtain 0x0A, then combine them to obtain 0xAA. The other five bits retain
their old values. This is a read-modify-write contract for the allocation unit.

Assign thirteen next. Under the admitted narrowing operation, the low three bits
are again 101, so the stored unit is again 0xAA. Equal final units do not mean
the source values were equal; they mean the field's storage width retained the
same payload. A later load interprets those bits using the field's signedness
and promotion rules.

If the field is signed, the extraction must extend its sign according to the
field width. Interpreting the same raw three-bit payload as unsigned would yield
a different value for a payload whose high bit is set. Storage preservation and
expression-value interpretation are two successive steps, not one unqualified
shift.

Sources: [preserving read-modify-write
store](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L119-L148),
[static and local initializer
callbacks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L161-L193).

## Let layout own the unit boundaries

The declaration builder decides the field's allocation unit, byte offset, width
and bit position. The expression consumer later uses that metadata. Inferring a
field's location from the previous field's spelling would duplicate the layout
algorithm and could disagree about padding or a new unit boundary.

A zero-width field has a layout role rather than an ordinary addressable value
role. An unnamed field can consume bits without creating a named member
expression. These cases require the builder to track placement independently of
lookup. The field-record extensions retain enough information for later
expressions without treating every declaration as a standalone byte object.

The selected width policy is explicit: intermediate widths thirty-three through
sixty-three are rejected, while the full sixty-four-bit case has a separate
admitted path. General knowledge that an eight-byte allocation unit exists
cannot erase this parser/provider limit. The chapter teaches what this source
accepts, not every arrangement a different C compiler could lay out.

Sources: [record extension, type guards and
layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L1-L107),
[field extraction, truncation and
promotion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L109-L160).

## Preserve neighboring fields through updates

For an update expression, keep the extracted old value when the expression needs
to return it, compute the new payload under the admitted type rules, then merge
the stored bits into the original allocation unit. Returning the new payload for
a postfix expression would be an expression-result error even if the memory bits
were correct.

Assignment must also retain the distinction between the source value and the
stored narrowed field value. Replacing the unit with the new payload alone
destroys adjacent fields. A future test should seed the other bits with a
visible pattern, perform the field update and inspect both the expression result
and the full unit. A unit initially full of zeros can conceal a destructive
store.

Volatile ownership requires the selected access behavior, but does not turn the
read-modify-write sequence into an atomic operation. Another actor changing the
unit would require an additional contract absent from this lesson. Our 0xA6
state is an isolated supplied unit. No concurrent test, target layout dump or
executed bitfield update has been recorded here.

Sources: [static and local initializer
callbacks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L161-L193),
[volatile and synchronization
limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L1-L8).

## Give the expression a value and the storage a mask

A field declaration publishes layout metadata. A later field expression
publishes a value category and promoted type. A store uses the layout metadata
again to change only the specified bit range. These are successive consumers of
the same field identity, not a single operation whose result can be inferred
from the target unit width.

An unsigned three-bit field can represent zero through seven. Under the selected
narrow-field rule, that range fits int, so its expression promotion is int. The
underlying declaration's unsigned spelling does not automatically mean every
expression using it has unsigned-int type. This matters when the expression
enters arithmetic or a variadic position.

The field-record metadata occupies seventy-two builder bytes. The target field
can occupy three bits in a much smaller unit. Treating those extents as equal
would confuse compiler representation with compiled storage, the same mistake
G03 avoided for descriptors.

| Boundary | Information needed | Typical wrong substitution |
|---|---|---|
| Layout | Unit, offset, position and width | Previous member spelling alone |
| Extraction | Mask plus signedness | Whole-unit signedness |
| Promotion | Declared range and selected rule | Metadata-record size |
| Store | Old unit and narrowed new payload | New payload as the full unit |
| Address request | Independent byte-addressable object | Arbitrary bit position as a pointer |

An unnamed zero-width separator advances placement to a natural-unit boundary
and consumes no initializer element. This is why initializer traversal must
consult the builder's field role rather than incrementing one value per
declaration indiscriminately. Anonymous and named fields participate differently
in lookup and initialization even when both affect layout.

Ordinary pointers cannot name these bit ranges under the selected provider.
Address-taking is rejected because there is no independent byte object with the
expected pointer representation. It is a representation limit, not evidence that
the field has no physical storage.

For a later store observation, seed neighboring bits with a nonzero pattern,
retain the expression's old/new result and inspect the entire unit. That test
can expose both a destructive merge and an incorrect postfix result. Our field
state has isolated ownership; preserving neighbors is not an atomic
concurrent-update guarantee. No new target field dump or update execution is
recorded here.

Sources: [record extension, type guards and
layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L1-L107),
[field extraction, truncation and
promotion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L109-L160),
[preserving read-modify-write
store](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L119-L148),
[static and local initializer
callbacks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L161-L193).

## Let an unnamed field change placement without changing lookup

A record can contain declarations that affect storage without making a named
member available. An unnamed bitfield can occupy a range; an unnamed zero-width
field can move the next field to a natural-unit boundary. Their layout role must
be retained even though lookup cannot produce an ordinary expression for their
names.

The builder tracks its current bit end and the declared allocation unit. If the
next admitted field would cross that unit, it aligns the starting bit position
before adding width. A union starts its member placement from zero instead.
Target byte offset and within-unit shift are then recorded separately for named
fields.

The descriptor's total extent and alignment must still fit the target
object-size limit after padding. A bounded array product earlier in declaration
parsing does not automatically bound a later sum or final tail alignment. The
bitfield layer performs its selected layout check after extending the aggregate.

Field metadata uses the extended record while retaining ranked-array information
in another cell. Anonymous promotion copies the full field record and adjusts
enclosing byte offsets. That gives later member expressions the same width/shift
metadata without re-running the inner declaration layout. Qualifier ownership
also has to follow moved field records rather than stale addresses.

Extraction uses an ordinary typed unit load, then shift and truncation/sign
extension. A preserving store first obtains the narrowed new value, prepares its
positioned bits and clears only that field mask in the old unit. Even a compound
update can require more than one load under the documented volatile behavior; no
atomicity follows.

The expression type can then differ from the declared field base through
narrow-field promotion. An unsigned three-bit payload fits int. That promoted
expression can enter arithmetic or a variadic call under int rules. A layout
listing alone would not show the later promotion, and a numerical result alone
would not show neighbor preservation.

Unsupported declarations and address requests remain checked limits. Enum
provenance cannot silently become ordinary signed-int bit semantics, unsupported
intermediate widths reject, and a bit range does not provide an independent
ordinary object pointer. A reader should retain rejection as a result rather
than inventing a layout that this compiler never admits.

The chapter's 0xA6 unit exposes extraction and merge arithmetic with visible
neighboring bits. A future compiler fixture should retain declared layout,
actual target unit, expression result and rejected variants. No new bitfield
declaration or volatile update was compiled or run.

Sources: [record extension, type guards and layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L1-L107), [field extraction, truncation and promotion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L109-L160), [preserving read-modify-write store](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L119-L148), [static and local initializer callbacks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L161-L193), [volatile and synchronization limits](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth#L1-L8).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](13-streams-and-bounded-formatting.md) remains available for a
specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/14-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G14-01 — Separate metadata

Do 72-byte field records imply 72-byte target fields? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G14-02 — Extract a field

Derive the supplied 0xA6 field value. Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G14-03 — Preserve a unit

Assign five to width three/shift one in 0xA6. Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G14-04 — Handle a zero width

What does an unnamed zero-width declaration change? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G14-05 — Choose promotion

What is the expression type of an unsigned three-bit field? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G14-06 — Reject an address

Why reject taking an ordinary pointer to this bitfield? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G14-07 — Bound volatile behavior

Does the preserving store establish atomic neighbor updates? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

## What this mechanism makes available

You can now teach bitfield storage interface when the actual source first needs
it. Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G15: Aggregate values and X87
transport](15-aggregate-values-and-x87-transport.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
