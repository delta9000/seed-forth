# Bits and subtraction

The seed can add two cells, but it has no primitive named `-`. It also lacks
primitive `and` and `or` words. The library supplies all three without adding
machine instructions to the seed. How can a word that flips bits help us
subtract numbers?

This chapter builds that connection one step at a time. By the end, you should
be able to trace the actual library definitions, explain why they work for
64-bit cells, and catch a tempting mistake: treating every nonzero value as
if it were an all-ones mask.

**Starting point.** You need [Chapter 1's](01-values-and-words.md) top-right
stack notation, `dup`, `swap`, `+`, explicit `[lit]` literals, and the idea of
keeping the low 64 bits after addition. You do not need the return stack or
machine instructions. [Chapter 2](02-addresses-and-bytes.md) gave these values
a memory representation; here we inspect the bits inside one value.

**Status.** Traces below are manual derivations using the pinned seed's
contracts, not observed executions. Four-bit pictures are labeled teaching
models. Real seed words operate on all 64 bits.

## A quick route check

If you already know bitwise logic, explain these before deciding what to skip:

- Why does `dup nand` complement a cell?
- Why can two nonzero cells produce zero under bitwise `and`?
- In `a b`, which operand must we complement and increment to compute `a-b`?

If you can justify all three, inspect the source definitions and attempt
S3-03 through S3-05. If not, the next two sections give the missing rules.

## One bit first, then a cell

A **bit** is a digit whose value is zero or one. Binary place values double
as we move left. The four-bit pattern `1100` means
`1×8 + 1×4 + 0×2 + 0×1`, which is decimal 12. The rightmost bit contributes
one; the next contributes two; then four and eight. A 64-bit cell extends the
same scheme to 64 places.

The following operations compare corresponding bit positions. `AND` sets an
output bit only when both input bits are one. `OR` sets it when at least one
input is one. `NOT`, or **complement**, changes zero to one and one to zero.
`NAND` means “NOT of AND.” The spelling `a & b` below means bitwise AND,
`a | b` means bitwise OR, and `~a` means complement within the stated width.
These are explanation symbols, not extra Forth words.

| Input bit a | Input bit b | a AND b | a NAND b |
|---|---|---|---|
| 0 | 0 | 0 | 1 |
| 0 | 1 | 0 | 1 |
| 1 | 0 | 0 | 1 |
| 1 | 1 | 1 | 0 |

The seed's primitive has the contract `nand ( a b -- ~(a & b) )`.
It performs that one-bit rule independently at every position in the cell.
There is no carry from one bit position to another, unlike addition.

Here is a **four-bit model**, useful for seeing all positions at once:

```text
 a        1100     decimal 12
 b        1010     decimal 10
 AND      1000     decimal  8
 NAND     0111     decimal  7, only in this four-bit model
```

For the real 64-bit seed, 12 and 10 have sixty leading zero bits. NAND flips
those zeros to ones too. Its result is therefore not 7: it is sixty leading
ones followed by `0111`. Declaring the width is part of stating the operation.

Let `M = 2^64` (two raised to the sixty-fourth power) and `U = M-1`. `U` is the unsigned value of the all-ones cell,
18446744073709551615. For any unsigned cell value `x`, complement is `U-x`.
So the real NAND result for 12 and 10 is `U-8`. We will use `U` in traces to
make the reasoning visible without repeating twenty-digit numbers. `U` is a
symbol in the prose, not a predefined Forth word.

## Complement without a new primitive

Apply the truth table with identical inputs. A bit AND itself is unchanged:
zero stays zero and one stays one. NAND then flips it. Consequently,
NAND of `x` with itself is `~x`.

The stack already has a way to obtain two copies:

```forth
dup nand
```

Starting with `[x]`, `dup` produces `[x, x]`; `nand` consumes both copies
and leaves `[~x]`. The net effect is one cell in, one cell out. No extra
temporary stack or memory address is needed.

This is also a useful distinction between a mechanism and its name. We can
recognize a repeated sequence as complement even before defining a word for
it. The selected library uses the sequence directly.

## Deriving AND

NAND almost gives us AND. It introduces one unwanted complement. Complement
the result again to remove it. The actual library definition is:

```forth
: and  nand dup nand ;
```

Predict the final value for inputs 12 and 10, then follow this **64-bit**
trace. Rows show the stack after each operation; the top is at the right.

| Step | Operation | Stack after | Reason |
|---|---|---|---|
| 0 | Start | `[12, 10]` | Two operands |
| 1 | `nand` | `[U-8]` | The AND is 8, so NAND complements 8 |
| 2 | `dup` | `[U-8, U-8]` | Make identical inputs |
| 3 | `nand` | `[8]` | Complement `U-8` to recover 8 |

The numerical example suggests a rule; the algebra explains why the rule
does not depend on these numbers. Write `t = ~(a & b)`. The remaining
`dup nand` computes `~t`, so the whole definition gives `~~(a & b) = a & b`.
Each original bit is flipped twice. The argument applies to every cell,
provided the word has its required two inputs.

This proves the identity under the stated bitwise model. It does not prove
every property of the seed executable. That larger claim would need an
argument about its implementation and environment as well.

## Deriving OR while keeping the stack straight

A bit of `a OR b` is zero only when both inputs are zero. If we complement
both inputs first, those two original zeros become two ones. NAND of the
complements then produces zero in exactly that case. Thus:

```text
a OR b = NOT ((NOT a) AND (NOT b))
```

This is one of De Morgan's identities. We have just justified it from the
condition for a zero output, rather than asking you to memorize the name.

The library definition is:

```forth
: or   dup nand swap dup nand nand ;
```

The first complement acts on `b`, because `b` is on top. A `swap` exposes
`a` for the second complement. The final NAND combines them.

| Step | Operation | Stack after | What changed |
|---|---|---|---|
| 0 | Start | `[a, b]` | Inputs |
| 1 | `dup` | `[a, b, b]` | Copy b |
| 2 | `nand` | `[a, ~b]` | Complement b |
| 3 | `swap` | `[~b, a]` | Expose a |
| 4 | `dup` | `[~b, a, a]` | Copy a |
| 5 | `nand` | `[~b, ~a]` | Complement a |
| 6 | `nand` | `[a | b]` | Complement the AND of the complements |

For 12 and 10, OR is binary `1110`, or decimal 14. In the real 64-bit
calculation, each complemented input has leading ones. The final NAND flips
their common leading ones back to zeros. That is why this final result agrees
with the four-bit picture even though the intermediate complements do not.

The `swap` is not decoration. Without it, the second `dup nand` complements
`~b` back to `b`, leaving `a` uncomplemented. A plausible-looking sequence
then computes the wrong function. Keep the stack trace beside the Boolean
identity: both constraints must hold.

## True values and masks

The seed's `0=` has a different contract: `( x -- flag )`. It returns `U`
if the entire input cell is zero, and zero otherwise. It tests a value; it
does not complement each bit of that value.

For input 5, `dup nand` gives `U-5`, while `0=` gives zero. On input zero,
both happen to produce `U`. One matching example would therefore hide an
important difference.

The pair zero/`U` is useful for combining predicates with bitwise logic.
Every bit of `U` agrees that the answer is true, and every bit of zero agrees
that it is false. An all-ones cell can also serve as a **mask**: ANDing any
cell with `U` preserves all its bits, while ANDing it with zero clears them.

Arbitrary nonzero numbers are not interchangeable with `U` for this purpose.
Two is binary `0010` and four is `0100` in a four-bit picture. Both numbers
are nonzero, yet their bitwise AND is zero because no position contains two
ones. It would be a mistake to infer that `and` means “both whole numbers
are nonzero.”

When that is the question, normalize each value first. Applying `0=` twice
returns zero for zero and `U` for any nonzero input:

```forth
[lit] 2 0= 0= [lit] 4 0= 0= and
```

The derived final stack is `[U]`, assuming `and` has been defined and the
starting stack is empty. Each pair of tests converts a numeric condition to
the same canonical flag convention before the flags are combined.

## Subtraction is addition with a modular inverse

We now have the missing ingredient for subtraction: complement. Recall that
addition keeps the low 64 bits. A result equal to `M` therefore becomes zero.
For any cell value `b`:

```text
b + (U-b) + 1 = U+1 = M
```

So `~b + 1`, calculated within the cell width, is the value that adds to `b`
to produce zero. It is the **additive inverse modulo M**. “Modulo M” here
means that whole multiples of `M` are discarded and we keep a result between
zero and `M-1`.

To obtain `a-b`, add that inverse to `a`. The library does precisely this:

```forth
: -  dup nand [lit] 1 + + ;
```

Starting with `[7, 2]`, here is the full derived trace:

| Step | Operation | Stack after | Reason |
|---|---|---|---|
| 0 | Start | `[7, 2]` | a=7, b=2 |
| 1 | `dup` | `[7, 2, 2]` | Duplicate the subtracted operand |
| 2 | `nand` | `[7, U-2]` | Complement 2 |
| 3 | `[lit] 1` | `[7, U-2, 1]` | Supply the missing one |
| 4 | `+` | `[7, M-2]` | Form the additive inverse of 2 |
| 5 | `+` | `[5]` | 7+M-2=M+5; retain the low 64 bits |

Notice the jobs of the two additions. The first forms the inverse of the top
operand. The second combines that inverse with the lower operand. They are
not redundant copies of the same step.

No return-stack operation appears. Subtraction does not need the temporary
storage mechanism used by the nearby `over` definition in the source. This
is one reason to order lessons by their dependencies rather than by source
adjacency.

## The same bits can have two interpretations

Reverse the inputs: `[2, 7]` produces the unsigned cell value `M-5`, or
18446744073709551611. Interpreted as a signed two's-complement 64-bit number,
the same pattern represents -5. A negative signed value `-k` is represented
by `M-k` for `1 <= k <= 2^63`.

The bits do not change when we change the interpretation. But not every
operation ignores that choice: the seed's `/` treats its operands as unsigned.
Feeding it the pattern for signed -5 does not ask for signed division.
Likewise, later comparison algorithms will need their own range assumptions.

For another boundary, the pattern with only the top bit set represents
unsigned `2^63`, or signed `-2^63`. Complementing and adding one gives the same
pattern again. There is no signed positive `2^63` in a 64-bit two's-complement
cell. The modular rule still holds; an unbounded signed-arithmetic expectation
would not.

The seed's literal parser accepts unsigned decimal tokens. A negative number
in an explanatory stack picture is an interpretation, not permission to type
`[lit] -5`. To construct that pattern using these words, use
`[lit] 0 [lit] 5 -` after defining `-`.

## The trade we have made

The seed pays for one bitwise primitive and the ordinary stack operations.
The library pays for compositions that use them. This makes selected
definitions small enough to reason about as short sequences, while the
machine-level implementation of the primitive can be audited separately.

That design does not establish that this primitive set is uniquely minimal,
or that a derived word runs as fast as a dedicated instruction. No timing or
minimality claim is needed for the learning result: the shown contracts are
sufficient to derive these three useful operations.

## Practice

Use the contracts while attempting a problem if needed. Hints and worked
answers are in the [feedback companion](../practice/03-solutions.md). After
feedback, try its changed case before deciding which section needs another
look.

### S3-01 Trace and distinguish

Starting with an empty stack, trace `[lit] 6 [lit] 3 and` using the definition
of `and`. Give every intermediate stack in terms of `U`. Then trace
`[lit] 6 0=`. Explain why the two uses of a complement-like operation do not
mean the same thing.

### S3-02 Complete the construction

Complete `: or  dup nand ____ dup nand nand ;`. Explain the missing word's
job using symbolic stacks. For a contrasting case, explain what the broken
definition computes on inputs zero and zero if the blank is omitted.

### S3-03 Diagnose a predicate bug

A program treats numeric 2 and numeric 4 as true because they are nonzero,
then combines them with `and`. It obtains zero. Is the library word broken?
Give a sequence using only `[lit]`, `0=` and the defined `and` that answers
whether both original numbers are nonzero. Trace the flags.

### S3-04 Build a related word

Define a teaching word `negate-cell` with contract `( x -- inverse )`, using
only `dup`, `nand`, `[lit] 1` and `+`. Trace input zero, then input 5. State
both the unsigned result and signed interpretation for input 5. Do not assume
that this new word already exists in `010-lib.fth`.

### S3-05 Change the width

For an explicitly hypothetical eight-bit machine with the same word contracts
but `M=256` and `U=255`, begin with stack `[3, 10]` and trace `-` on paper. Give the unsigned result and
its signed two's-complement interpretation. What changes, and what stays the
same, in the inverse argument? Why would copying the unsigned eight-bit
answer into a 64-bit seed cell not automatically preserve the signed value?

## Stop and return

You can now explain three constructions: complement from duplication and
NAND, AND/OR from complement, and subtraction from a modular inverse. Keep the
truth-versus-mask counterexample beside them; it prevents a useful rule from
being stretched beyond its contract.

For a short stopping point, save the trace `[7, 2] -> [5]` and label the
different roles of its two additions. On return, try `[2, 7]` without opening
that trace. Then use the [mixed return check](../practice/return-check.md),
which also revisits addresses and the byte writer. Continue the reading route
with [Return stack and shuffles](04-return-stack-and-shuffles.md).

## Source and evidence

The definitions of `and`, `or` and `-` are excerpts from
[`010-lib.fth`, lines 25–42](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L25-L42).
The primary primitive evidence is
[`nand_code` and `zeq_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L200-L222),
with addition in `plus_code` immediately before them. The symbolic and numeric
arguments above are derived from those inspected contracts. No source file
was changed and no seed execution is claimed. Full scope is in the
[edition record](../../EDITION.md).
