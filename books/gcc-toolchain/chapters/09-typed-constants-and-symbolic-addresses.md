# Typed constants and symbolic addresses

An unsigned addition can wrap before a comparison, even when the result is never
stored. How can a compiler evaluate that constant without losing its C type?

We will follow a numeric leaf, then a pointer leaf, through the same selected
initializer traversal. All arithmetic in these constant stories happens in the
builder; no generated program is executed.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G03 supplies types and shapes, G02 supplies relocation identities, and
[C14](../../c-compiler/chapters/14-expressions-and-constant-evaluation.md)
supplies conditional parsing and unevaluated expressions. A **symbolic value**
here consists of one symbol identity and an addend, not a guessed process
address.

## Floating static leaves

Layer 125 now carries binary32/binary64 encodings and extended constants in its
value records. Layer 128 performs exact ratio arithmetic and rounds once to the
selected width; integer-to-float conversion and width changes use those hooks,
while float-to-integer truncates toward zero and must fit (242). Static leaves
convert to the destination before object patching. For example `static float
x=1;` stores the binary32 encoding 0x3f800000. `_Bool` conversion tests nonzero,
including floating NaN. Relocations remain symbolic and cannot become floating
payloads. See [constant conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L61-L160),
[static leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L207-L248).

## Normalize before the next operator

For `0xffffffffU + 2U`, both operands are unsigned int. Four-byte normalization
makes the sum one. A following `> 2U` is therefore false. Keeping the
mathematical 4,294,967,297 in a Forth cell until a final store would make the
comparison wrong, although that wider cell has enough bits to hold it.

The evaluator returns value/type pairs and applies integer promotions and usual
arithmetic conversions at each operator. Shifts use the promoted left type.
Comparisons and logical operators yield int. Long long has the same eight-byte
width as long here but higher rank, so width alone does not choose the common
type.

Signed values are normalized by sign extension, unsigned by zero extension.
Full-range comparison checks sign bits before subtraction. The seed’s unsigned
division implements unsigned C division; signed division has a separate path
with truncation toward zero and overflow checks.

Sources: [typed records and integer
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L1-L266).

## Reject an impossible constant instead of substituting zero

The evaluator rechecks a numeric token’s spelling because the lexer’s
machine-word accumulation alone cannot prove representability. Malformed
suffixes, invalid octal digits, unsupported floating spellings and values beyond
the unsigned range must not become plausible integer prefixes.

Division by zero reports 124; invalid shift counts report 241; signed arithmetic
overflow reports 242; negative signed left operands are folded as two’s
complement with destination-width normalization; unsupported constant forms
report 240. Unsigned wrapping is intentional at the converted width. A caller
cannot infer a successful C value from a rejected operation.

Public constant parsing leaves the following delimiter pending and restores its
private record-pool watermark. Recursive array bounds or sizeof parsing must not
consume the enclosing declaration’s comma or permanently spend its temporary
records. Syntax state and workspace state need distinct restoration.

Sources: [literal and arithmetic
guards](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L267-L372),
[public constant entry
points](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L566-L610).

## Keep the destination symbolic

Supply a static array `long items[4]` and an initializer taking `items + 2`. The
symbol identifies items; the value becomes addend 16 because long elements
occupy eight bytes. It does not become object-record-ID plus sixteen. IDs
identify records and have no address arithmetic meaning.

Casting the symbolic pointer to long preserves the identity but changes
subsequent addition to byte arithmetic. Under that supplied cast, adding two
increases the addend by two rather than sixteen. Narrowing a symbolic value,
multiplying it, comparing pointers or combining two symbol identities rejects:
the selected single-symbol relocation representation cannot encode arbitrary
link-time expressions.

Member offsets and scalar subscripts can add to the same identity without
loading target memory. A parenthesized object remains an lvalue; a cast creates
a value. Taking an address through a pointer object would require reading that
object’s runtime contents and is rejected, even when it has a static
initializer.

Sources: [symbolic address leaves and
categories](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L249-L418),
[symbolic arithmetic and conditional
parsing](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L373-L565).

## Reuse the tree, replace the leaf action

The shared 118 initializer walker retains destination type, descriptor,
dimensions and byte offset in recursive frames. It visits array elements and
named struct fields; it uses the first union member, retains zeroed omissions,
handles supported brace elision and counts unsized outer arrays before
allocation. Strings decode escapes and concatenate; an exactly full fixed char
array need not have room for a closing NUL.

Object mode selects a static scalar leaf that parses the four-cell
value/type/descriptor/symbol result. A numeric leaf is converted and patches
data at the destination width. A symbolic eight-byte leaf emits an absolute
relocation with its addend. Character-array strings patch the selected data
reservation; string address leaves allocate read-only bytes and return their
record identity.

The native alternative emits initialization routines and queues them for entry.
The object adapter refuses that queue. Reusing its recursive traversal therefore
does not mean this object needs hidden executable initializer calls before main.

Sources: [strings and recursive
traversal](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L132-L280),
[object initializer
leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L178-L248).

## Parse the arm without performing its effects

For `1 ? -1 : 1U`, both arms contribute to the result type. The selected −1 is
converted to unsigned int even though the unsigned arm is not evaluated. A dead
arm is not missing syntax. For `1 || (1 / 0)`, the division tokens are parsed
under the skip state but the division is not performed.

The same skip state reaches symbolic identifier, string and address callbacks.
They preserve enough type/category information for checking but avoid object
allocation and relocation publication for discarded leaves. Index evaluation
inside a discarded address operand must inherit that state too.

sizeof uses the existing unevaluated parser, discarding temporary output rather
than executing it. This is different from runtime branching in generated code. A
source-derived constant value is not an observed result of running the target.

Sources: [skip state and entry
restoration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L484-L610),
[dead symbolic
leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L251-L279).

## Follow one initializer to its destination

Supply a static array of four longs and another static object initialized to the
address of its third element. The third element is two strides beyond the first.
At eight bytes per long, the symbolic address has base symbol `items` and addend
sixteen. The constant evaluator can derive that addend without knowing where the
linker will place `items`.

The shared initializer walker identifies the destination leaf's byte offset,
type and descriptor. The selected object consumer decides how that leaf becomes
section bytes and relocation metadata. For the pointer-valued leaf, the consumer
reserves the address-width field and records the symbolic obligation. It does
not turn the compiler's current builder pointer into the target address.

After G05's layout, supply `items` at 0x402000. The absolute symbolic result
becomes 0x402010. Moving that symbol to 0x403000 changes the result to 0x403010
while the prepared addend remains sixteen. The declaration's element stride
belongs to compilation; the symbol's final address belongs to linking. This is
the same separation that allowed G01 to leave its call unfinished.

The selected static consumer differs from an executable initializer queue. A
queued initializer would perform work when the generated program runs. A
relocation completes a stored field while linking. Both can arise from shared
traversal structure, but their completion events and required inputs differ.
Reading only the walker would not identify which one is selected.

Sources: [symbolic address leaves and
categories](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L249-L418),
[symbolic arithmetic and conditional
parsing](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L373-L565),
[strings and recursive
traversal](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L132-L280),
[object initializer
leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L178-L248).

## Normalize at the operation's type boundary

Supply the unsigned 32-bit constant 0xffffffff and add two under the stated
unsigned-int operation. The width gives a result of one. Keeping a wider
intermediate cell with value 0x100000001 until a later comparison would change
the expression's meaning. The Forth builder's cell width is not the C
expression's operation width.

Now compare the normalized result with one. The result is equal. An
implementation that postponed normalization could incorrectly compare the wider
value instead. The important transition occurs between the arithmetic operation
and its consumer, not only when a final value is stored in four bytes.

Signedness matters independently. A cell's high bits can represent a negative
signed value or a large unsigned value depending on the retained type. A source
evaluator must select the relevant operation and comparison, rather than using
one unqualified builder comparison everywhere. The chapter's arithmetic is a
supplied typed calculation, not a claim that every overflow expression is valid
C.

Sources: [typed records and integer
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L1-L266),
[literal and arithmetic
guards](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L267-L372),
[public constant entry
points](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L566-L610).

## Parse a dead branch without performing its work

A conditional constant expression still needs a syntactically valid unchosen
arm. Its tokens and relevant type structure cannot simply disappear from the
reader. But executing a dangerous operation in that unchosen arm would violate
the evaluator's skip contract. Parsing and evaluating are distinct obligations.

Follow the skip state through a nested operation rather than testing only the
outer conditional. A division-like operation in an unchosen arm must not become
a real evaluation merely because recursion enters its handler. Equally, skipping
evaluation must not erase the chosen arm's typed result or leak skip state into
the following initializer.

For an eventual observation, retain the expression, target type, selected arm,
resulting bytes and any relocation. A successful program run would be an
indirect oracle for the static field; a direct object inspection would isolate
its preparation. Neither new observation is recorded here. The chapter equips
the reader to predict both and to recognize whether the mismatch belongs to
traversal, typed evaluation, symbolic recording or final placement.

Sources: [skip state and entry
restoration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L484-L610),
[dead symbolic
leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L251-L279).

## Ask the symbolic value what work it still needs

The selected static expression record retains value, type, descriptor and symbol
identity. A numeric leaf has no unresolved symbol; a symbolic leaf carries one
lasting identity and an addend. Its numeric cell is not a process pointer that
can be dereferenced while the compiler runs.

Supply `items + 2` for an array of longs. The pointed-to stride gives addend
sixteen. Now supply an admitted cast to a long before adding two. The subsequent
integer arithmetic gives a two-byte addend adjustment. The symbol remains the
same, while the type changes the operation performed on the numeric part. This
is another case in which width equality does not preserve meaning.

Supply the difference of independently placed symbols instead.
One-symbol-plus-addend cannot retain both identities for a later consumer.
Rejecting that expression is honest about the selected representation. Guessing
a builder-time distance would silently replace target placement with unrelated
compiler memory.

| Leaf kind | Builder can settle now | Later consumer supplies |
|---|---|---|
| Typed integer arithmetic | Normalized value under admitted rules | Destination serialization |
| Address of one static symbol | Identity and byte addend | Symbol's final address |
| Array-element address | Stride-scaled addend | Base placement |
| Two independent symbols | Insufficient selected representation | Unsupported expression |

A conditional introduces two obligations at once. Both arms contribute type
information; only the selected arm contributes evaluated effects. In `1 ? -1 :
1U`, the unsigned arm changes the common type even though its value is unchosen.
The chosen minus one must be converted accordingly. Treating skip as “ignore
every fact from this arm” would preserve the wrong result type.

The shared initializer frame then tells the static consumer where that leaf
belongs. Missing leaves retain the allocated zero state; a symbolic pointer
produces relocation metadata. The alternate runtime queue is not a fallback
secretly used to repair unsupported object constants: object completion rejects
a leftover queue.

For a later observation, retain the resulting data bytes together with the
relocation, not one instead of the other. A zero placeholder can be a valid
unresolved address field. After linking, that field changes while its original
symbolic premises remain identifiable. The chapter has derived these transitions
with supplied addresses and types; it has not recorded a new object or relocated
pointer value.

Sources: [symbolic address leaves and
categories](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L249-L418),
[symbolic arithmetic and conditional
parsing](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L373-L565),
[strings and recursive
traversal](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L132-L280),
[object initializer
leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L178-L248),
[skip state and entry
restoration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L484-L610),
[dead symbolic
leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L251-L279).

## Restore two kinds of temporary state at the delimiter

The constant evaluator uses a bounded private record pool. Each record has four
cells: value, type, descriptor and symbol identity. Recursive operations can
create intermediate records before the final result is converted for its
destination. The public integer interface returns fewer fields than the static
symbolic interface because their consumers need different information.

At entry, retain the pool watermark. At successful return, restore it after
making the result available. A following initializer can reuse those temporary
records. This is not a request to reuse the lasting object symbol record: that
identity must survive into relocation finalization. Temporary constant records
and lasting object records have different lifetimes even when one contains a
reference to the other.

The token reader has another boundary. The enclosing declaration owns its comma
or closing delimiter. Constant parsing must leave that delimiter pending.
Restoring a watermark cannot repair a consumed separator; restoring the token
reader cannot reclaim leaked constant records. Both completion contracts matter.

Supply a declaration with two initialized leaves separated by a comma. The first
constant parse finishes, restores its private pool and leaves the comma for the
declaration walker. The walker consumes the separator, then invokes the
evaluator for the second leaf. If the first evaluator consumed the comma itself,
the next phase could begin on the wrong token. If it retained its temporary
records indefinitely, many such leaves could overflow the bounded pool despite
simple individual expressions.

This reading sequence also explains why malformed spellings are checked again.
The lexer retains text while accumulating a machine-word value. That
accumulation alone cannot prove the literal was representable. Before publishing
a typed constant, the evaluator validates digits, base and suffix, using bounds
before multiplication. Accepting an integer prefix of a rejected spelling would
publish a false successful result.

The source-backed public interfaces therefore establish type, lifetime and
reader-position contracts together. The chapter's symbolic addends and
normalized arithmetic depend on them. A future static-initializer check should
retain both the expected data/relocation and rejection status for invalid
inputs. No such new compilation or pool-exhaustion experiment was executed here.

Sources: [typed records and integer operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L1-L266), [literal and arithmetic guards](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L267-L372), [public constant entry points](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L566-L610), [symbolic address leaves and categories](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L249-L418), [symbolic arithmetic and conditional parsing](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L373-L565), [strings and recursive traversal](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L132-L280), [object initializer leaves](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/123-cc-object-program.fth#L178-L248).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](08-target-headers-and-honest-feature-probes.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/09-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G9-01 — Wrap at the right time

Derive (0xffffffffU+2U)>2U in this profile. Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G9-02 — Retain rank

Why is equal long/long-long width insufficient to select the common type?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G9-03 — Scale an addend

Give the symbolic representation for items+2 when elements are eight bytes.
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G9-04 — Reject two identities

Why not evaluate the difference of arbitrary independent symbols as one current
relocation? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G9-05 — Keep the dead arm typed

What type/value follows from 1 ? -1 : 1U? Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G9-06 — Choose a static leaf

Where does object-mode initialization put a symbolic pointer obligation? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G9-07 — Preserve a delimiter

Why restore the constant pool and leave the comma pending? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

## What this mechanism makes available

You can now teach static constant/addend lowering and shared initializer leaf
needed by the object task. Use the state transitions above to justify that
explanation, rather than treating a source filename or a successful later
milestone as a substitute for the mechanism.

Continue to [G10: Floating values and
conversion](10-floating-values-and-conversion.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
