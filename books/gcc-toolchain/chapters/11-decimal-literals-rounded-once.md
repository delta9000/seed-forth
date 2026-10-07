# Decimal literals rounded once

A decimal literal can sit exactly halfway between two binary values. How can a
Forth parser choose the right neighbor without first rounding the decimal
through a host floating type?

Follow 1.25 as an exact ratio, then a smaller supplied halfway model. The
decoder uses integer operations and emits a binary64 encoding; these are paper
derivations.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G10 distinguishes payload from conversion. A **significand** holds a binary
value’s significant digits; an exponent scales it by a power of two. **Ties to
even** selects the neighbor with even last retained bit at an exact halfway
point. The smaller precision used below is a teaching model, clearly separate
from binary64’s 53 significant bits.

## Select precision before the one rounding

The shared exact-ratio engine now selects 23, 52 or 63 fraction bits for
binary32, binary64 or extended80. Extended results carry an explicit integer
bit and sign/exponent in a sixteen-byte object. Extended normal exponents run
from −16382 to 16383, with minimum subnormal spacing 2^−16445. Extended overflow
produces infinity; the binary64 overflow exercise still reports overflow.
Existing 1.25 and miniature midpoint traces retain their binary64/teaching
formats. See [format selection and rounding](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L266-L364)
and [typed suffix selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L61-L75).

## Retain every decimal digit until the ratio exists

For spelling 1.25, the mantissa integer is 125 and two fractional digits give
decimal scale −2. The exact ratio is 125/100. Dividing both by 25 shows 5/4, so
in normalized binary it is 1.01 times 2^0. There is no remainder after those
bits; the binary64 encoding is 0x3FF4000000000000.

The parser records significant digits, fractional digit count and signed decimal
exponent separately. Leading zero mantissa digits do not spend significant-digit
count, while later zeroes do. Scale is exponent−fractional-count. Positive scale
multiplies the numerator by powers of ten; negative scale multiplies the
denominator.

The two big integers use up to 2048 little-endian 32-bit limbs, each in an
eight-byte Forth cell. Zero has no used limbs; readers do not inspect bytes
beyond the used prefix. Multiply-by-ten plus carry fits the wider cell without
requiring floating arithmetic.

Sources: [big-integer representation and
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L31-L130),
[decimal grammar and scale
fields](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L132-L248).

## Normalize using exact integer comparison

The decoder compares numerator and denominator bit lengths to propose a binary
exponent, then shifts one side until their ratio lies in [1,2). If the first
comparison leaves it below one, it doubles the numerator and decreases the
exponent. The exact ratio is preserved while its representation changes.

The quotient builder begins with leading significand one and subtracts the
denominator. Each step doubles the remainder, doubles the quotient prefix, then
subtracts the denominator and adds one when the remainder reaches it. At every
step the remainder is exact and below the denominator.

After the required retained bits, it compares twice the remainder with the
denominator. Below means round down; above means round up. Equality rounds
upward only when the retained quotient is odd. This avoids a host parser’s first
rounding followed by the target’s second rounding.

Sources: [normalization, quotient and exact
remainder](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L250-L314).

## Let a smaller midpoint show the rule

In a supplied three-significant-bit model near one, adjacent values are 1.00₂=1
and 1.01₂=1.25. Their midpoint is 1.125. The lower retained significand is
binary 100, decimal four, which is even, so an exact midpoint rounds to one.

Between 1.25 and 1.5 the midpoint is 1.375. The lower retained significand is
101, decimal five, odd. Ties to even therefore chooses the upper significand
110, giving 1.5. “Always choose the lower value at a tie” would fail this second
example.

Binary64 performs the same decision after 52 fractional quotient bits. If
rounding produces a 54th significant bit, the implementation shifts the quotient
and increases the exponent. This carry is not discarded. The smaller model
explains the rule without claiming the real decoder uses only three bits.

Sources: [rounding and significand
carry](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L266-L575).

## Choose subnormal spacing before rounding

Normal binary64 values have a leading implicit one and exponents down to −1022.
Below that, subnormal values have fixed spacing 2^−1074. The decoder shortens
its quotient construction for that region instead of constructing a normal
result and repeatedly shifting an already-rounded significand.

At exactly half the minimum positive subnormal, 2^−1075, ties to even chooses
zero. A value above that midpoint in the same boundary branch rounds to the
minimum subnormal. A normal quotient carry that raises the exponent beyond 1023
reports overflow instead of emitting an invented finite value.

The decoder checks coarse decimal order before constructing huge powers; very
small values can return zero, while obvious overflow rejects. The grammar and
exponent limits are still checked first. An absurd malformed spelling is not
admitted simply because its numerical prefix looks tiny.

Sources: [normal/subnormal decoding
boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L270-L575).

## Bound the grammar and workspace

The spelling requires a point or decimal exponent. Unary sign belongs to the
expression parser. A token may contain at most 4096 bytes, at most 768 mantissa
digits from the first nonzero through the last digit, and exponent magnitude at
most one million. The typed wrapper accepts f/F and l/L suffixes, selecting 4- and 16-byte
formats before rounding; unsuffixed spelling selects 8. Hexfloat with a p
exponent is admitted for extended precision. The raw binary64 decoder rejects
hexfloat and suffixes not removed by its caller.

Checked remaining scale fits the big-integer workspace; the source explains its
checked 65536-bit workspace bound. Limb append checks capacity independently. A
workspace failure, malformed token and overflow have distinct messages even
though they terminate through the decoder’s error boundary.

The resulting word is a raw target encoding, never a host floating value. G10
emits and later computes with it. A future differential test could compare exact
encodings for halfway, subnormal and carry cases, but no such new test was run
to write this lesson.

Sources: [decoder
diagnostics](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L9-L30),
[grammar limits and workspace
argument](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L132-L265).

## Remove decimal notation before rounding

Read 1.25 as decimal digits with a scale. Its exact ratio is 125/100, which
reduces to 5/4. Because that denominator is a power of two, the value has a
finite binary representation: one plus one quarter. No decimal-to-binary
approximation is needed before deciding its binary64 bits.

Contrast a ratio with a factor of five still in its denominator after reduction.
It need not have a finite binary expansion. The reader must retain enough exact
integer information to locate the nearest representable binary value. Computing
a host double first would make the host conversion an unrecorded numerical
producer, and could introduce an earlier rounding step.

The source's multi-limb integers give the conversion a bounded exact workspace.
Their limit is part of the parser's input contract. “Exact ratio” means exact
within the admitted digit and workspace bounds, not unlimited mathematical
arithmetic. Decimal scaling, numerator/denominator comparison and bit production
must all respect those bounds.

Sources: [big-integer representation and
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L31-L130),
[decimal grammar and scale
fields](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L132-L248).

## Make the halfway rule visible with fewer bits

Supply a teaching format with three significant binary bits. Near one, its
adjacent values include 1.00, 1.01 and 1.10 in binary, or 1, 1.25 and 1.5 in
decimal. The midpoint between one and 1.25 is 1.125. It is equally close to both
endpoints. Ties-to-even selects the endpoint whose retained least significant
bit is even: one.

The midpoint between 1.25 and 1.5 is 1.375. This time the even endpoint is 1.5.
The rule does not always round a halfway input downward. It selects by retained
parity after the neighboring candidates are known. The two supplied cases expose
that difference without requiring a reader to write fifty-three significant
bits.

These teaching bits are not the format produced by the repository. Binary64
applies the same rounding principle at its own precision and exponent
boundaries. To transfer the explanation, identify the retained significand, the
discarded information and whether the remainder is below, above or exactly at
halfway. A “has discarded bits” flag alone cannot distinguish those cases.

Sources: [rounding and significand
carry](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L266-L575).

## Carry through the bottom and top boundaries

At the subnormal bottom, spacing is fixed rather than changing with each
normalized exponent. Half the smallest positive binary64 subnormal is 2 to the
power −1075. The tie is between zero and the smallest subnormal. The even rule
selects zero. A result of zero can therefore be a correct rounding outcome for a
positive admitted mathematical input.

At the other boundary, rounding can carry out of the retained significand. The
exponent and range decision must see that carry. Clamping the significand first
and deciding range afterward would lose information about which representable
result is required. Follow the source's range handling rather than inventing an
arbitrary saturation policy.

A future numerical record should distinguish accepted spelling, exact prepared
ratio, rounded payload and rejection behavior at parser limits. A host numerical
oracle can help compare outputs, but would remain an oracle with its own
conversion behavior. The chapter's 1.25 and three-bit examples are exact paper
derivations; the extreme boundary is a mathematical application of the stated
rule. No new exhaustive literal sweep was run.

Sources: [normal/subnormal decoding
boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L270-L575).

## Let the remainder decide the final bit

For a rounded significand, keep the integer quotient q, remainder r and
denominator D. The quotient contains the proposed retained bits. The remainder
describes the exact part that was not retained. Compare twice r with D: smaller
is below halfway, greater is above halfway, and equality is the tie case.

At a tie, inspect q's retained low bit. An even q stays; an odd q advances. This
is more precise than saying “round to nearest” because nearest alone leaves two
equally near choices. It is also more precise than “round if there is a
remainder,” which would round some below-halfway cases incorrectly.

Use a supplied miniature quotient four and denominator eight. Remainder three
gives twice-r six, below eight, so the quotient stays four. Remainder four gives
equality, and the even quotient stays four. Change only the quotient to five at
that exact tie: it advances to six. These are integer teaching states, not
actual parser intermediates captured from binary64 conversion.

| Supplied relation | Decision before carry handling |
|---|---|
| 2r less than D | Keep q |
| 2r greater than D | Increase q |
| 2r equal to D and q even | Keep q |
| 2r equal to D and q odd | Increase q |

The increase can carry beyond the retained significand width. Keep that carry
long enough to adjust the exponent, then apply range handling. A correctly
decided rounding direction can still produce a wrong encoding if its carry is
discarded. The source's production of sign/exponent/fraction bits is the final
serialization step after this arithmetic.

At the bottom, fixed subnormal spacing changes how the scale is interpreted. At
the top, exponent range limits still apply after rounding. Input spelling limits
and multi-limb workspace bounds apply earlier. Place these checks in order
rather than treating every rejected literal as the same numerical overflow.

A future comparison should retain both accepted input text and target bits.
Printing a decimal approximation of the resulting double could hide a one-bit
mismatch. A host conversion oracle must be named separately from the
integer-only production calculation. The exact ratio, miniature quotient and
midpoint examples here are paper derivations, with no newly generated exhaustive
conversion report.

Sources: [big-integer representation and
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L31-L130),
[decimal grammar and scale
fields](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L132-L248),
[normalization, quotient and exact
remainder](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L250-L314),
[rounding and significand
carry](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L266-L575),
[normal/subnormal decoding
boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L270-L575).

## Separate a spelling limit from a rounding limit

The decoder first has to establish what decimal number the token spells. It
scans digits and decimal/exponent structure under a bounded grammar. It does not
accept suffixes or hexadecimal floating spellings simply because their
mathematical values could be represented as binary64. Acceptance is a
source-language question before exact ratio conversion begins.

The decimal mantissa and scale then supply integer numerator and denominator
work. The bounded multi-limb representation retains exact arithmetic within its
admitted workspace. A long sequence of significant digits can require more
workspace even when the final floating value is small. A large exponent can
require scale handling even when the token contains few digits. These are
independent resource questions.

Only after an exact admitted ratio is available does the binary rounding
question arise. The decoder determines the binary scale, produces retained
quotient information and compares the exact remainder. It rounds once to the
target encoding. A host double read followed by another conversion would create
a different numerical producer and potentially an earlier rounding event.

Supply 1.25 and a different spelling of the same exact ratio within the admitted
grammar. The decoder should derive the same target encoding even though the
source bytes differ. Source identity and numerical value identity are both
useful, but they answer different questions. The source manifest should keep the
actual spelling; the numerical comparison can compare target bits.

Now supply the three-bit midpoint model from earlier. Its format is deliberately
smaller than binary64. It makes quotient parity visible without pretending the
repository emits that teaching format. Transferring the rule requires using the
real precision, exponent and subnormal scale, not copying the miniature bit
count into the implementation account.

Overflow handling follows rounding because a carried significand can change the
exponent. Underflow handling likewise must see the exact position relative to
the smallest spacing. A zero result at the precise bottom tie does not imply the
input was spelled zero, and a rejected spelling does not imply numerical
overflow. Preserve the stage at which each decision occurs.

For a later decoder record, retain accepted/rejected spelling, selected limits,
produced payload and the independent comparison input. Do not rely solely on a
formatted decimal display of the result; it can conceal an encoding difference.
The integer-only production and any host numerical oracle retain separate
identities. No literal sweep, extreme-exponent run or new differential report
was created for the manuscript.

Sources: [big-integer representation and operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L31-L130), [decimal grammar and scale fields](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L132-L248), [normalization, quotient and exact remainder](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L250-L314), [rounding and significand carry](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L266-L575), [normal/subnormal decoding boundaries](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L270-L575), [decoder diagnostics](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L9-L30), [grammar limits and workspace argument](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/128-cc-float-literal.fth#L132-L265).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](10-floating-values-and-conversion.md) remains available for a
specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/11-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G11-01 — Construct a ratio

Give mantissa, scale and exact ratio for 1.25. Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G11-02 — Round an even midpoint

Use the three-bit model at 1.125. Explain which supplied rule determines your
answer. Keep any prediction separate from a claim that the corresponding program
or build was run.

### G11-03 — Compare a remainder

What do 2r<D, 2r>D and 2r=D each mean? Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G11-04 — Preserve a carry

Rounding grows the significand beyond its normal retained width. What happens?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G11-05 — Reach the smallest spacing

What happens at exactly 2^−1075? Explain which supplied rule determines your
answer. Keep any prediction separate from a claim that the corresponding program
or build was run.

### G11-06 — Retain grammar limits

Is an exponent magnitude of one million equivalent to unlimited exponent text?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G11-07 — Name the producer

What did Forth produce: a host double or target bits? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

## What this mechanism makes available

You can now name decimal-literal production support before relevant source
input. Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G12: Variadic cursors and argument
classes](12-variadic-cursors-and-argument-classes.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
