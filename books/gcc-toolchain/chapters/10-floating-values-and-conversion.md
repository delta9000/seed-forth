# Floating values and conversion

The bits for a floating value can fit in RDI, but adding those bits as integers
is not floating addition. Which operation changes the represented number, and
which merely moves its payload?

Follow 1.5 through storage, an arithmetic instruction and a return boundary.
Then disturb the width. The selected floating providers remain separate from the
native bootstrap’s restricted bit transport.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G04 supplies caller/callee transport and G09 supplies typed conversions.
**Binary32** and **binary64** describe four- and eight-byte floating encodings.
XMM registers hold the transient SSE operands/results; the ordinary expression
carrier can hold the raw payload without becoming its arithmetic interpretation.

## The computing provider follows transport

The final arithmetic provider is `132-cc-long-double.fth`; `131` remains the
call planner. Each x87 result is popped into a private sixteen-byte frame
object, so no x87 value survives a call, branch or expression boundary. Numeric
conversion to `_Bool` tests nonzero rather than byte truncation; float/double
increment and decrement use typed payload hooks. See [x87 conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/132-cc-long-double.fth#L1-L108)
and [binary32/binary64 updates](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L244-L290).

## Carry the encoding without converting its value

The selected provider carries raw binary32/binary64 payloads in RDI/RCX and
eight-byte expression slots. A float object still stores four bytes. Its storage
hook uses the unsigned four-byte emitter without changing the expression’s
floating type. This is a byte-width adapter, not an integer conversion.

For binary64 1.5, the payload is 0x3FF8000000000000, stored little-endian as `00
00 00 00 00 00 F8 3F`. MOVQ into XMM0 transports those bits. Numeric conversion
from integer one instead uses a conversion instruction that constructs floating
1.0. Confusing those operations would reinterpret integer bit pattern one as a
tiny floating number.

Typed loads and stores use the object width, while conversions between binary32
and binary64 change representation and can round. A wider internal slot does not
preserve arbitrary extra precision for binary32 arithmetic.

Sources: [payload and storage
hooks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L1-L25),
[transport and conversion
encodings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L67-L119).

## Select arithmetic at the operand type

The common-type hook chooses double if either admitted floating operand is
double, otherwise float for a floating/integer mixture. Operands are converted
to that type. Addition, subtraction, multiplication and division then select SSE
instructions with the precision-specific prefix. The result returns as payload
to the expression carrier.

A binary32 arithmetic step rounds at binary32 precision. Computing every step in
binary64 and shortening only at the final store would be another contract and
can change results. The four arithmetic operators do not grant bitwise
complement or integer-only operators meaning on float; unsupported uses reject.

Comparisons account for unordered NaN operands: ordered equality and
less/less-equal require the appropriate nonunordered test, while not-equal
includes unordered. The generated boolean is int. This is code emitted by Forth
now, consumed by SSE later under the stated target environment.

Sources: [common types, comparisons and
arithmetic](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L213-L265).

## Convert numbers instead of renaming bits

Integer-to-floating conversion normalizes the source integer first. Signed
integer conversion uses the signed SSE operation. For unsigned 64-bit values in
the high half, the implementation forms a sticky half and then doubles the
converted result, avoiding interpretation as a negative signed integer.

Floating-to-integer conversion uses truncation toward zero for admitted
representable values. Unsigned 64-bit conversion has a special boundary path
around 2^63; it is not just a signed conversion with an unsigned label.
Unsupported pointer/floating partner casts reject.

Do not promise a portable C result for out-of-range floating-to-integer
conversions. The source implements specific emitted instructions; successful
finite examples do not establish every exception, rounding-mode or NaN
conversion policy.

Sources: [unsigned boundary and width
conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L120-L212).

## Cross the ABI in the selected bank

A floating scalar return travels in XMM0, whereas an integer return travels in
RAX. The result hook moves the floating payload back into RDI and normalizes it
to the declared width. Thus RDI’s internal role remains consistent while the
public ABI distinguishes classes.

The final 131 planner assigns scalar float/double arguments to an independent
bank of eight XMM registers. Exhausting six INTEGER registers does not exhaust
that bank. Stack overflow slots still carry the object’s payload with the
selected width and placement rules. AL reports used vector registers for a
variadic call.

G12 opens those independent cursors. This chapter needs only the fact that the
carrier and the ABI register are not the same question. Two functions linked by
matching names can still disagree if one expects an integer class and the other
expects floating.

Sources: [return and result
hooks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L204-L212),
[separate scalar
banks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L133-L160).

## Keep spelling and wider formats bounded

The lexer scans a complete pp-number spelling and recognizes a floating token by
point or exponent, retaining its text. Integer spellings return to the ordinary
lexer. It does not split a malformed floating spelling into a plausible integer
prefix and ignore the rest.

The literal provider delegates to 128’s integer-only decimal decoder, then emits
a binary64 payload. At this pin the typed spelling wrapper strips f/F for binary32 and l/L for
extended precision; no suffix selects binary64. The extended decoder also
admits hexadecimal floating spelling with a required p exponent. The raw
binary64 decoder still rejects hexfloat and unstripped suffixes.

Long double keeps G15's sixteen-byte opaque representation, but layer 132 now
supplies x87 arithmetic, casts, tests and initialization. Layer 125 evaluates
static floating constants with layer 128's exact rounding hooks.

Sources: [number scan and literal
hook](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L27-L66),
[checked
spelling](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L210-L248),
[scalar-use
boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L403-L447).

## Give one value several representations

Supply the mathematical value one and a half. Its binary64 payload is
0x3ff8000000000000. That hexadecimal integer names bits, not an integer result
equal to one and a half. On little-endian storage, the eight payload bytes begin
with zeros and end with F8 3F. An eight-byte integer move can transport those
bits while doing no floating arithmetic.

Load the payload into a floating register and add another admitted floating
value. Now the selected operation interprets the payload under floating rules.
Store into a float destination instead: the target's four-byte format and
conversion determine new bits. Merely storing the low four bytes of the binary64
payload would not perform that conversion and would not preserve the value.

Convert the value to an admitted integer type. This is another numeric
operation, with its own range and truncation contract. Copying the original
payload into an integer register would yield a very large bit-pattern integer,
not the result of the numeric conversion. Track value, payload, storage width
and register class in separate columns.

A later check should therefore include at least two comparisons: numeric results
for conversion and exact bytes for transport. Equal numeric output can coexist
with different unused bits or representations. Equal copied bytes can coexist
with the wrong interpretation. Choosing the comparison requires knowing which
operation was requested.

Sources: [payload and storage
hooks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L1-L25),
[transport and conversion
encodings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L67-L119),
[common types, comparisons and
arithmetic](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L213-L265).

## Extend the call contract by class

G04 assigned integer-class arguments. Floating scalars use the selected
floating-register class, with results in XMM0. An interleaved call can consume
integer and floating destinations independently. Its floating-register count
also affects AL at the call boundary. Adding one floating argument is more than
appending one more integer slot.

Inside the callee, the declared parameter width still determines storage. A
double parameter occupies eight bytes; a float parameter occupies four. The
register used to carry it does not change that destination width. For an
unspecified or variadic position, default promotion can change the type before
classification. G12 will follow that change into the cursor layout.

For unsigned integer conversion, values above the signed range need the source's
selected strategy rather than a signed conversion blindly applied to the same
payload. The high-half path preserves a numeric value through admitted
intermediate operations. Its purpose is not to reinterpret unsigned bits as a
negative source number.

Sources: [unsigned boundary and width
conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L120-L212),
[return and result
hooks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L204-L212),
[separate scalar
banks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L133-L160).

## Preserve the profile's limits

The parser's accepted spelling, runtime arithmetic and static evaluation are
separate providers. Typed suffixes now select binary32 or extended80, and layer
125/128 supplies static floating leaves. Raw binary64 hexfloat remains outside
the admitted grammar.

Long double uses the later x87 transport/computation story. Layer 132 adds
its numeric operations; unsupported bitwise/remainder uses remain bounded. A toolchain
may later contain products compiled by GCC with broader behavior than the Forth
compiler that built the first GCC. Keep that producer transition visible when a
hosted fixture formats a floating value. This chapter's supplied payload and
conversions have not been executed as new fixtures.

Sources: [number scan and literal
hook](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L27-L66),
[checked
spelling](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L210-L248),
[scalar-use
boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L403-L447).

## Keep rounding and interpretation at their named steps

Supply a float value obtained from an admitted double literal through
conversion. The parser first supplies binary64 bits. The conversion then selects
binary32 representation. Later binary32 arithmetic can round again at its own
operation boundary. The existence of an eight-byte internal expression slot does
not mean every intermediate operation uses binary64 precision.

For storage, retain the floating type alongside the carrier. A float store
writes four bytes; a double store writes eight. A load adapts that
representation into the selected expression form. A call result crosses XMM0
before that internal adaptation. These are three distinct consumers of width and
class metadata.

NaN makes interpretation visible. Under the selected comparison rules, equality
excludes unordered, while not-equal includes it. Copying an unchanged payload
back into a register does not force numerical equality with itself. A
payload-identity check and a numerical-comparison check ask different questions.

| Requested operation | Meaning | Insufficient substitute |
|---|---|---|
| Payload move | Preserve encoding bits | Numeric conversion |
| Integer-to-float conversion | Preserve admitted numeric magnitude approximately | Bit reinterpretation |
| Float arithmetic | Operate at selected precision | Late-only storage rounding |
| Float comparison | Apply ordered/unordered rules | Byte equality |
| Floating return | Transfer through floating result bank | Integer-only ABI return |

The unsigned high-half conversion also concerns interpretation rather than
transport. When bit 63 marks unsigned magnitude, a signed conversion would give
it the wrong role. The source's half/sticky strategy arranges an admitted
intermediate magnitude and restores scale. Its correctness question is
numerical, so a direct payload-copy comparison would not be an appropriate
oracle.

Keep the selected provider in the ledger: typed suffix handling selects
precision before rounding, the constant evaluator converts static leaves, and
132 computes long-double expressions over the address representation.

A prospective fixture should choose accepted spellings and inspect results at
the boundary it tests: memory bytes for storage, numeric values for conversion
and comparison, register evidence for a call. The lesson has supplied such
questions and payloads; no new floating target or numerical oracle was run.

Sources: [common types, comparisons and
arithmetic](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L213-L265),
[unsigned boundary and width
conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L120-L212),
[return and result
hooks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L204-L212),
[separate scalar
banks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L133-L160),
[number scan and literal
hook](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L27-L66),
[checked
spelling](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L210-L248),
[scalar-use
boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L403-L447).

## Keep binary32 arithmetic narrower than its carrier

A useful way to read the provider is to follow one typed expression across five
events: accepted literal, numeric conversion, arithmetic, store and return. The
retained type tells each event which operation to choose. The expression's
internal eight-byte carrier provides transport capacity, while the type retains
the precision and storage obligations.

Supply a double literal converted to float. After conversion, a later float
operation follows the selected binary32 path. A wider temporary register does
not change that arithmetic into binary64. If the result is then converted back
to double, the wider destination represents the already rounded float result,
rather than recovering information lost earlier.

This is different from retaining the original double until one final float
store. The two paths can make different rounding decisions at intermediate
steps. The lesson does not invent a measured counterexample; it identifies the
operation boundary where such a difference would have to be checked. A future
discriminating fixture should choose values near that rounding boundary and
retain exact result bits.

At a call boundary, classification chooses a floating destination and AL reports
the used floating-register count. The callee's declared type still determines
its spill width and the precision of later operations. On return, XMM0 supplies
the floating ABI result, then the caller's expression adapter obtains its
internal representation. Changing register banks cannot be justified by the fact
that the internal carrier is another general register.

Unsigned integer conversion is also type-directed. Values in the high half of
the unsigned 64-bit range cannot pass through a signed interpretation unchanged.
The provider's special strategy preserves magnitude under its admitted numerical
conversion. A bit-preserving move has no such responsibility because it is
transport, not arithmetic.

The decoder and initializer have separate contracts. This pin admits f/F and
l/L through the typed wrapper and supplies static floating conversion. Long
double computation uses 132; unsupported record classes and raw binary64
hexfloat remain separate limits.

A later report should identify which of these five events it tested. Storing
correct bytes for 1.5 is a useful transport check; returning a correct sum tests
arithmetic and calling as well; an accepted initializer would test another
consumer. This chapter has supplied their mechanisms and distinctions without
executing a new floating fixture.

Sources: [payload and storage hooks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L1-L25), [transport and conversion encodings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L67-L119), [common types, comparisons and arithmetic](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L213-L265), [unsigned boundary and width conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L120-L212), [return and result hooks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L204-L212), [separate scalar banks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L133-L160), [number scan and literal hook](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L27-L66), [checked spelling](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L210-L248), [scalar-use boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L403-L447).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](09-typed-constants-and-symbolic-addresses.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/10-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G10-01 — Classify a move

Does moving 1.5’s payload into XMM0 numerically convert it? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G10-02 — Keep storage width

How many bytes does float store despite an eight-byte expression slot? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G10-03 — Choose precision

Why not do all float arithmetic as double until storage? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G10-04 — Separate return banks

Where do floating and integer scalar results cross the call boundary? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G10-05 — Treat unsigned values

Why special-case the high unsigned 64-bit half? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G10-06 — Handle unordered comparison

Can NaN equal itself under the selected comparison rules? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G10-07 — Bound literal support

Does float arithmetic imply acceptance of 1.0f by this decoder? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

## What this mechanism makes available

You can now state the workload-required floating interface without confusing
transport and conversion. Use the state transitions above to justify that
explanation, rather than treating a source filename or a successful later
milestone as a substitute for the mechanism.

Continue to [G11: Decimal literals rounded
once](11-decimal-literals-rounded-once.md). The [series map](../README.md) also
provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
