# Signatures, declarators, and ranked arrays

Two files can agree on a spelling while disagreeing about what the function
receives. Where does the compiler keep the interface that a name alone cannot
express?

Begin with `int answer(void);`, then change the shape of one declaration. We
will follow the shared native parser into the selected System V signature and
array providers. Nothing here selects the private TinyCC calling convention.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G02 supplied lasting object identity.
[C07](../../c-compiler/chapters/07-types-and-stable-descriptors.md) and
[C15](../../c-compiler/chapters/15-declarations-and-recursive-records.md) supply
type words, stable descriptors and recursive declarations for the depth
sessions. Locally, a **descriptor** is compiler metadata describing a compound
type; it is separate from the bytes of a target C object. A **prototype** gives
parameter types, while a definition additionally needs parameter names for its
body.

## Additional declaration forms

The selected System V provider now admits function-type typedefs and
block-scope function declarations, retaining and checking signatures. `_Bool`
is a one-byte unsigned scalar of lowest rank. Empty parentheses on a function
definition mean zero parameters when checked against a prior prototype. K&R
float parameter entry conversion remains rejected by the aggregate provider.
See [function typedefs](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L315-L344),
[block declarations and definition entry](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1263-L1357).

## Read outward from the name

For `int answer(void);`, the name denotes a function with no parameters and an
int result. A signature record retains that result type and descriptor,
parameter count, flags, and parameter type/descriptor pairs. Parameter names
occupy a separate part of the record. Changing a name does not change a
parameter's type; omitting a prototype parameter name does not remove its
position.

Contrast `int answer();`. Empty parentheses leave the parameters unspecified in
this C90-oriented profile. `(void)` explicitly says zero. At a call, an
unspecified declaration requires default promotions; it cannot enforce the same
zero-argument contract. This is why G01 chose `(void)`.

A function pointer carries a tagged signature descriptor too. `int (*p)(void)`
declares a pointer object whose pointed-to function returns int; `int *p(void)`
declares a function returning a pointer. Parentheses change the construction
order. The address carrier is eight bytes in both pointer cases, but its use
still needs the retained signature.

Sources: [signature
fields](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L54-L78),
[parameter lists and
signatures](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L377-L585).

## Give recursive parsing its own frame

`115` uses `cc-nctx` to hold the current declaration's type, descriptor, name,
storage and array facts across token reads. A nested aggregate gets a fresh
context and restores the enclosing one. Without that restoration, finishing an
inner field could replace the outer name or dimensions.

Base keywords are counted before the base is chosen. This permits admitted
orders such as `unsigned const char` and `long unsigned long`. Qualifiers are
recorded while scanning; System V hooks check the keyword set instead of
inheriting every permissive native combination. Two longs select long long in
LP64, whose rank differs from long even though both occupy eight bytes.

Storage specifiers are contextual. A declaration can contain them in the
admitted positions; a type name inside sizeof cannot become a declaration merely
because it shares the parser. The type-name provider temporarily clears the
storage context and restores qualification fields after recursive parsing. A
saved lexer mark restores the reader, not newly allocated descriptors or symbol
rows.

Sources: [native contexts and counted
bases](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L1-L250),
[type-name
context](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L587-L644).

## Build a layout before allocating an instance

For a paper LP64 record `struct pair { char mark; long value; };`, char occupies
byte zero. Long needs alignment eight, so its offset is eight. The record's
extent becomes sixteen and its alignment eight. Seven intervening bytes are
padding. A union instead starts each member at zero and uses the largest extent,
then rounds its final size to its required alignment.

The aggregate builder installs a forward descriptor before reading fields, so
pointers to the still-being-defined tag can retain its identity. Tags occupy a
namespace separate from ordinary identifiers. A pointer to an incomplete record
needs a pointer width; a by-value instance needs a complete size.

Anonymous member promotion copies field records with the enclosing byte offset
added. Qualifications are keyed by field-record address; when a field table
grows and moves, the hook re-keys those entries. Descriptor identity can remain
stable while its mutable table moves. G14 will add bitfield metadata without
redefining that distinction.

Sources: [field layout, promotion and tag
construction](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L388-L481),
[ordinary and tag
namespaces](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L10-L30).

## Retain a row instead of flattening its shape

Supply `long grid[2][3]`. Each long is eight bytes; one row is 24 and the full
object is 48. After ordinary array decay, a pointer to the first row advances by
24 when incremented. A pointer to one long advances by eight. Equal pointer
storage widths do not make their strides equal.

The System V array node retains element type and descriptor, count, inner
dimension and qualifier set. Higher ranks build real element-array nodes instead
of losing suffixes. Rank is bounded independently at 64; size multiplication is
checked against the target's 1 GiB object limit before multiplying. A tiny
element type does not remove the rank limit.

Qualifying a shared node makes a qualified copy rather than mutating a typedef
used elsewhere. For `const long grid[2][3]`, decay carries const to the row
element. `long (*const p)[3]` instead qualifies the pointer object.
Redeclaration comparisons inspect row shape and nested qualifier sets, and
assignment may add the permitted outer qualifier but may not silently discard
it.

Sources: [bounded ranked arrays and
qualification](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L79-L218),
[shape
compatibility](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L709-L819).

## Keep storage production separate from declaration shape

The shared parser installs local, global, typedef, function and tag records
through different consumers. A typedef supplies metadata; it does not reserve an
instance. A local reserves frame storage, while a static object needs lasting
object identity and section storage. The selected `123` adapter gives
extern-only, tentative and initialized declarations their object contracts.

For an unsized initialized array, `118` first scans the initializer to count
outer elements, restores the lexer and then allocates the sized object. The
recursive initializer frame carries type, descriptor, dimensions, byte offset,
element index and brace state. Arrays advance by element size; structs visit
their field records; a union starts with its first member. Missing elements keep
zero bytes.

This shared traversal is required on the direct GCC route even though its
original file describes native bootstrap initialization. G09 opens the selected
static leaf: in object mode it patches data and emits relocations instead of
queuing executable initialization routines. Source provenance and selected
behavior are separate questions.

Sources: [symbol/storage and declaration
consumers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L500-L642),
[initializer frames and
inference](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L15-L131),
[recursive child
traversal](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L179-L280).

## Compare what the compiler actually retains

Within a translation unit, System V redeclaration checks compare result types
and signatures recursively, including function pointers and record identity. An
unspecified declaration is compared using default-promotion compatibility. A
later known prototype must not pretend that earlier incompatible calls had the
correct interface.

C90 implicit external calls also need persistent identity after their visible
block symbol disappears. The target keeps a separate implicit record for its
name, unspecified-int signature and unfinished calls/addresses. A later
file-scope object cannot silently replace that external function. This is
another instance of G02's lifetime problem: visible rows and lasting obligations
have different owners.

Across separately compiled files, the bounded linker resolves names without
comparing these C signatures. A successful G05 link therefore cannot certify
that `int answer(void)` and `long answer(void)` agree. Repair the declarations
and rebuild the affected objects; linking cannot reconstruct lost source-level
type facts.

Sources: [signature compatibility and implicit
records](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L866-L990).

## Follow a type through a declaration and a use

Supply two declarations: an array of two rows of three longs, and a pointer to
one row of three longs. Read the first from its identifier outward. It names an
array; each element is another array; that inner array's elements are longs.
Read the second from its parenthesized identifier outward. It names a pointer;
the pointed-to thing is an array of three longs. The shared base keyword does
not erase these different constructions.

Now supply a use that advances each expression by one element after the admitted
array-to-pointer conversion. The first expression starts at the first row, so
its next element is the next row, twenty-four bytes later. The second pointer
also advances twenty-four bytes. A pointer to the first scalar long advances
only eight. On paper, use base address 0x1000: the next row is at 0x1018 and the
next scalar at 0x1008. These are illustrative object addresses, not addresses
chosen by the compiler's allocator.

A useful diagnosis begins when the first row advance is incorrectly predicted as
eight. Reopening machine pointer width will not repair it: every pointer here
occupies eight bytes. The missing fact is the pointed-to element's descriptor.
Reopening the row node and its count repairs the prediction. This is how a
retained source shape becomes a later expression contract.

Qualifiers create another layer. A const element prevents the admitted store
through that element expression. A const pointer prevents changing that pointer
object. Both declarations can describe eight-byte pointers, and both can use the
same row size. Their writable places differ. Track the qualifier at the level
where it is attached rather than writing one undifferentiated “const” flag
beside the whole declaration.

Sources: [bounded ranked arrays and
qualification](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L79-L218),
[shape
compatibility](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L709-L819).

## Keep recursive work inside its frame

Return to the record with a char and a long. While parsing `mark`, the context
owns that field's name and type. While parsing `value`, it owns another name and
type. The enclosing record descriptor owns the field list that receives both
completed entries. This lets each field's temporary parsing state change without
losing the previously published field.

A nested record adds an additional context. Before entering it, save the
enclosing declaration's information; while inside it, construct the nested
fields; on leaving it, restore the enclosing state and attach the resulting
descriptor where the enclosing declaration requires it. Restoring the token
reader alone would not restore this context. Conversely, restoring the context
does not rewind all arena allocations. These are different state owners with
different recovery operations.

Consider a forward tag used through a pointer before its body appears. The
pointer can retain the tag descriptor because a pointer has a known size. The
tag's body later completes that descriptor's layout. Creating a wholly unrelated
descriptor at completion would break the earlier reference. This resembles G02's
lasting identity, but the thing being identified is a type, not a linkable
symbol.

The initializer walker receives the completed shape after declaration parsing.
For a nested array, it needs the outer count, inner element shape and byte
offset together. Flattening only the total byte size would lose where each
initializer belongs. Its scan to infer an unsized outer count is therefore a
preparation step before storage assignment, followed by a traversal with the
sized descriptor. Keep the shared traversal separate from the selected consumer
that writes constants or schedules execution.

Sources: [native contexts and counted
bases](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L1-L250),
[type-name
context](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L587-L644),
[field layout, promotion and tag
construction](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L388-L481),
[ordinary and tag
namespaces](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L10-L30),
[symbol/storage and declaration
consumers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L500-L642),
[initializer frames and
inference](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L15-L131),
[recursive child
traversal](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L179-L280).

## Compare interfaces before comparing names

Supply a caller that sees `int answer(void)` and a callee definition with that
same interface. The two translation units each retain enough local metadata to
construct the agreed call and return. G02's object symbol retains the linkable
name. The linker can match that name and fill a field, but this object's ELF
symbol table is not a serialized C signature checker.

Now change the caller's declaration while leaving the callee's source untouched.
A successful name match would no longer establish that both sides agree about
argument or result handling. The first question is what each compiler invocation
knew locally. This is why a cross-file teaching fixture must preserve its
declarations as well as its object symbols. It also explains why the later
implicit-function-pointer lint can reveal a semantic defect after linking
succeeds.

For a later observation, retain the preprocessed declaration from each
translation unit and the generated argument/result evidence. Avoid treating a
symbol listing as an interface proof. The paper examples establish shape
arithmetic and the selected parser's contracts; they do not record a new run of
a mismatched-interface program.

Sources: [signature
fields](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L54-L78),
[parameter lists and
signatures](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L377-L585),
[signature compatibility and implicit
records](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L866-L990).

## Change a declaration without changing its storage width

Supply two pointer objects, one pointing to a long and one pointing to a
three-long row. Each pointer occupies eight bytes. Give both the same
illustrative address 0x1000. Advance each by one pointed-to element. The scalar
pointer becomes 0x1008, while the row pointer becomes 0x1018. Equal stored
addresses and equal pointer widths have produced different arithmetic because
the retained element shapes differ.

Now supply two row pointers with the same stride, but qualify the pointed-to
elements in only one. Their address arithmetic agrees. Their admitted stores do
not. This time it is qualifier ownership rather than shape that distinguishes
their uses. A comparison based only on byte size or on pointer subtraction would
miss it.

Finally, retain a function-pointer object's eight-byte width while changing the
pointed-to signature's result type. A later call needs that signature to adapt
the return. The object writer's name and width cannot supply it after the parser
discards it. G04 will consume the retained call metadata, while G02's symbol
interface continues to serve link identity.

| Retained layer | Consumer that needs it | What size alone misses |
|---|---|---|
| Array element descriptor | Pointer stride and subscripting | Row extent |
| Qualifier at the element level | Store/compatibility checks | Whether this place is writable |
| Function signature | Argument/result planning | How a call crosses the ABI |
| Tag descriptor identity | Later completion and field lookup | Which incomplete record becomes complete |

Take the native parser in two reading sessions. First follow one base type and
declarator into a published declaration, stopping before all recursive
alternatives. On the second session, enter the ranked-array and aggregate paths
with that simple record in hand. Note every temporary context that is saved and
restored and every descriptor that persists. A recursive parser becomes easier
to reason about when its temporary work is distinct from its lasting product.

The initializer traversal is another consumer of that lasting product. A
correctly sized object with a lost row shape could still receive leaves at wrong
offsets. This shows why a layout calculation and a traversal calculation are
separate practice tasks. The paper examples supply both their element sizes and
dimensions; a future compiled fixture should retain actual descriptors or
emitted storage evidence before reporting agreement.

Sources: [field layout, promotion and tag
construction](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L388-L481),
[ordinary and tag
namespaces](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L10-L30),
[bounded ranked arrays and
qualification](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L79-L218),
[shape
compatibility](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L709-L819),
[symbol/storage and declaration
consumers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth#L500-L642),
[initializer frames and
inference](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L15-L131),
[recursive child
traversal](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/118-cc-native-init.fth#L179-L280).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](02-objects-symbols-and-relocation-records.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/03-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G3-01 — Distinguish two lists

What does (void) promise that empty declaration parentheses do not? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G3-02 — Derive a record

Derive mark/value offsets and size for the supplied char/long pair. Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G3-03 — Walk one row

For `long grid[2][3]`, derive row and whole sizes and the stride of a decayed
row pointer. Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G3-04 — Place the qualifier

Compare const long (*a)[3] and long (*const b)[3]. Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G3-05 — Restore the owner

An inner record declaration overwrites cc-nctx. What must happen on return?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G3-06 — Choose the initializer producer

Why is using 118 on the direct route not evidence of private TinyCC runtime
initialization? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G3-07 — Locate a missing check

Two objects resolve answer by name but used different result types. Which
boundary must be repaired? Explain which supplied rule determines your answer.
Keep any prediction separate from a claim that the corresponding program or
build was run.

## What this mechanism makes available

You can now teach selected scalar declarations and shared 115/118
declaration/initializer interfaces. Use the state transitions above to justify
that explanation, rather than treating a source filename or a successful later
milestone as a substitute for the mechanism.

Continue to [G04: A shared scalar argument
planner](04-a-shared-scalar-argument-planner.md). The [series map](../README.md)
also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
