# 5. Comparisons and characters

[Previous: Return stack and shuffles](04-return-stack-and-shuffles.md) · [Practice help](../practice/05-solutions.md) · [Next: Memory updates and writers](06-memory-updates-and-writers.md)

The byte 57 represents the digit `9` in ASCII. The next byte, 58, represents
`:`. How can the library distinguish them using subtraction, division, and a
zero test? And why can a similar-looking subtraction test give a wrong answer
when comparing two signed numbers?

We will build predicates: words that answer a question with a flag. By the
end, you should be able to explain equality across all cell patterns, trace a
sign test, recognize the domain of the library's ordering comparisons, and
classify ASCII bytes without a branch or loop.

## Bring three contracts with you

You need [Chapter 1's](01-values-and-words.md) stack notation, colon definitions,
`[lit]` and unsigned division; [Chapter 3's](03-bits-and-subtraction.md)
modular subtraction, signed interpretation, canonical flags and `or`; and
[Chapter 4's](04-return-stack-and-shuffles.md) `over`. No memory access or
control-flow mechanism is needed here. A byte input means a cell containing
an unsigned value from 0 through 255.

A quick check: why does `[48, 0] over` leave `[48, 0, 48]`, while `[48, 0] dup`
leaves `[48, 0, 0]`? What does `[lit] 0 [lit] 1 -` represent as unsigned, and
as signed? If copying the second item or interpreting that subtraction is
uncertain, revisit the linked chapters. Those are the two places a later
trace is most likely to become confusing.

Already comfortable with these contracts? Attempt S5-01 and S5-02, then read
the byte-range proof and `space?` trace. The overflow boundary matters even
if familiar Forth names make the definitions look routine.

**Edition and evidence.** This is the Linux/x86-64 seed at
[commit 7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b).
All examples below are manual derivations from inspected source, not executed
observations. Assume the named library words are available when tracing a
call. These excerpts explain their behavior; they are not a build procedure.

## Make each answer the same kind of flag

Keep Chapter 3's symbols: `M = 2^64` and `U = M-1`. Introduce `H = 2^63`, half
of `M`. These are mathematical abbreviations, not names you can type into the
seed. A cell interpreted as unsigned lies between zero and `U`. Under the
signed two's-complement interpretation, patterns below `H` are nonnegative;
patterns from `H` through `U` represent values from `-H` through -1.

A **canonical flag** is either zero for false or `U` for true. The all-ones
pattern `U` also represents signed -1. The library names it:

```forth
: true  [lit] 0 0= ;
```

The primitive `0=` returns `U` for a zero input and zero for any nonzero
input. A second `0=` therefore normalizes an arbitrary numeric condition:

| Input | After first `0=` | After second `0=` |
|---|---|---|
| `0` | `U` | `0` |
| Any nonzero cell | `0` | `U` |

This matters when composing tests. Chapter 3 showed that bitwise operations
inspect matching bit positions, not whole-number truth. For canonical flags,
`or` gives `U` when either input is `U` and zero otherwise. Both inputs and
the result obey one convention. A raw numeric answer of 1 is nonzero, but it
is not yet an all-ones flag.

## Equality survives wrapping

The library supplies:

```forth
: =   - 0= ;
: <>  = 0= ;
```

Both have stack effect `( a b -- flag )`. Starting with `[57, 57]`, `-`
leaves `[0]` and `0=` leaves `[U]`. Starting with `[57, 58]`, subtraction
wraps to `U`, then `0=` leaves zero. The difference need not be a small
positive number for equality to work.

Here is the all-cell argument. Subtraction produces `(a-b) modulo M`, with
`a` and `b` regarded as unsigned representatives from zero through `M-1`.
That result is zero exactly when their mathematical difference is a multiple
of `M`. Their difference lies strictly between `-M` and `M`, so the only
possible such multiple is zero. Thus the two original bit patterns must be
equal. No signed-overflow restriction is needed for `=`.

`<>` reverses the canonical equality answer: equal patterns produce zero;
different patterns produce `U`. Equality works on addresses, character codes,
and signed or unsigned interpretations because the test concerns the whole
cell pattern. It does not decide which unequal value is earlier in an order.

## Read the top bit using unsigned division

The source gives `H` a Forth name and uses it in a sign test:

```forth
: 2^63  [lit] 9223372036854775808 ;
: 0<  2^63 / 0= 0= ;
```

`2^63` is one word name. Calling it pushes the value `H`; it is not an
exponentiation expression being evaluated by the input reader. The unsigned
decimal literal fits in a cell even though it exceeds the largest positive
signed value.

For every unsigned cell `x`, division by `H` has only two possible quotients:

- From zero through `H-1`, the quotient is zero
- From `H` through `M-1`, the quotient is one, because even the largest input
  is less than `2H`

These intervals coincide with a clear or set top bit. Dividing the unsigned
pattern therefore extracts the bit that indicates negativity under the
signed interpretation. The division itself is still unsigned.

| Original cell pattern | Signed interpretation | Quotient by `H` | Final `0<` flag |
|---|---|---|---|
| `0x0000000000000000` | 0 | 0 | `0` |
| `0x7FFFFFFFFFFFFFFF` | `H-1` | 0 | `0` |
| `0x8000000000000000` | `-H` | 1 | `U` |
| `0xFFFFFFFFFFFFFFFF` | -1 | 1 | `U` |

Hexadecimal here describes the cell pattern, not a literal syntax for the
seed. For `[U]`, the expanded trace is `[U, H]` after `2^63`, `[1]` after
`/`, `[0]` after the first `0=`, and `[U]` after the second. Omitting the last
test would answer the opposite question. Keeping the raw quotient would give
the correct zero/nonzero distinction but the wrong true representation.

This sign test is valid for every cell pattern. The restriction comes next,
when subtraction supplies the pattern being tested.

## The ordering test has a boundary

**The library's `<` is not a correct signed comparison for every pair of
64-bit signed operands.** It tests the sign of a wrapped subtraction. If the
mathematical signed difference does not fit, wrapping can reverse that sign.

Consider the largest signed value against -1, before adopting any general
rule:

```text
left operand:    0x7FFFFFFFFFFFFFFF =  9223372036854775807 = H-1
right operand:   0xFFFFFFFFFFFFFFFF =                   -1
true difference:                                      H
stored result:   0x8000000000000000 = signed -H
```

Mathematically, `H-1` is not less than -1. But the stored difference has its
top bit set. Testing that bit returns true. No division fault occurs; the
program produces a well-formed flag with the wrong signed-order meaning.

With that limitation visible, inspect the definition:

```forth
: <   - 0< ;
```

Let `a` and `b` now mean the **signed interpretations** of the two operands.
This definition gives the correct signed comparison when the mathematical
difference `a-b` lies in `[-H, H-1]`. In that domain, subtraction preserves
the signed difference, so its top bit reliably answers whether `a < b`.
Outside that domain, it cannot be relied on.

For `[48, 57]`, the mathematical difference is -9, which fits. The stored
pattern is `M-9`; dividing it by `H` gives one; the two zero tests produce
`U`. Reversing the inputs gives a difference of 9, a quotient of zero, and a
final flag of zero. Selected small characters and counts can satisfy this
condition. Their names alone do not establish it: callers must supply bounds.
We have not established that every comparison elsewhere in the project is
safe.

The remaining definitions transform this bounded comparison:

```forth
: >   swap < ;
: <=  > 0= ;
: >=  < 0= ;
```

Within the valid domain, `>` asks whether `b < a`; `<=` negates that answer;
`>=` negates `a < b`. Swapping matters to the domain too: `>` and `<=` use
the signed difference `b-a`, while `<` and `>=` use `a-b`.

A convenient **shared sufficient condition** is that `a` and `b` are strictly
less than `H` apart. Both differences then fit, and all four relationships
hold. For example, any pair in 0 through 255 meets that condition. At exactly
`H` apart, one difference is `-H`, which fits, but the other is `H`, which
does not. Do not extend the shared condition to include that endpoint.

These words also do not provide general unsigned ordering. A large unsigned
pattern may represent a negative signed value. Equality, sign detection, and
ordering are three different contracts, despite sharing some operations.

**Pause point.** Save the MAX-versus-minus-one example and the sentence
“equality tolerates wrapping; ordering needs a difference bound.” On return,
explain which step creates the wrong ordering answer before continuing.

## Move a byte range down to zero

For this chapter, the character mapping is the ASCII mapping used by the
supplied library:

| Meaning | Decimal byte values |
|---|---|
| Digits `0` through `9` | 48 through 57 |
| Uppercase letters `A` through `Z` | 65 through 90 |
| Lowercase letters `a` through `z` | 97 through 122 |

The numeral character `0` has byte value 48, not numeric value zero. These
are byte classifications for this profile, not Unicode character properties
or locale-aware tests.

The digit definition does not call `<`:

```forth
: digit?  [lit] 48 - [lit] 10 / 0= ;
```

Its contract is `( c -- flag )`. Subtracting 48 moves the desired interval
to zero through nine. Unsigned integer division by ten maps every value in
that interval to zero. The final `0=` recognizes that zero quotient.

Predict the four boundary cases before reading their derived states:

| Byte `c` | ASCII character | After subtracting 48 | After unsigned `/ 10` | Final flag |
|---:|---|---|---|---|
| 47 | `/` | `U` | 1844674407370955161 | `0` |
| 48 | `0` | 0 | 0 | `U` |
| 57 | `9` | 9 | 0 | `U` |
| 58 | `:` | 10 | 1 | `0` |

The first row explains why unsigned division is essential. Subtraction of
48 from 47 wraps to `U`; `/` divides that large unsigned value. It does not
reinterpret it as signed -1.

Here is the full first-row trace with an older stack item, 99:

```text
start            [99, 47]
[lit] 48         [99, 47, 48]
-                [99, U]
[lit] 10         [99, U, 10]
/                [99, 1844674407370955161]
0=               [99, 0]
```

The character is consumed and replaced by one flag. The older item survives.
Nothing prints a character or changes memory.

### Why every byte falls into the right case

The examples expose the edges; the domain argument covers every input from
0 through 255. Write `d` for the stored result of `c-48`:

1. If `0 <= c < 48`, wrapping gives `d = M-48+c`, between `M-48` and `M-1`.
   Every such value exceeds ten, so the unsigned quotient is nonzero and the
   flag is false
2. If `48 <= c <= 57`, then `d` is zero through nine. Its quotient by ten is
   zero and the flag is true
3. If `58 <= c <= 255`, then `d` is ten through 207. Its quotient is at least
   one and the flag is false

The three cases exhaust the byte domain. There is no signed-ordering
assumption hidden here: large wrapped results are deliberately rejected by
**unsigned** division. The divisor ten is nonzero.

Compare a hypothetical division that interprets the difference as signed and
truncates toward zero. On input 47 it would compute `-1 / 10 = 0`, falsely
accepting `/` as a digit. That changed primitive breaks the argument. A gforth
session is not an execution of this seed profile, and this chapter claims no
compatibility setup for it. Check the arithmetic contract before transporting
the definition to another implementation.

## Combine two letter ranges

The other contiguous ranges use the same construction:

```forth
: alpha-lower?  [lit] 97 - [lit] 26 / 0= ;
: alpha-upper?  [lit] 65 - [lit] 26 / 0= ;
: alpha?  dup alpha-lower? swap alpha-upper? or ;
```

There are 26 accepted values in each range. For byte inputs below the base,
the wrapped difference is at least `M-97` or `M-65`, respectively, and hence
well above 26. Inside the range, it is zero through 25. Above the range, it
is at least 26. This is the same three-case argument, with different bounds.

`alpha?` must test one input twice. For byte 65, representing `A`:

| After | Stack, top right | Reason |
|---|---|---|
| Start | `[65]` | One character |
| `dup` | `[65, 65]` | Keep a copy for the second test |
| `alpha-lower?` | `[65, 0]` | Below 97; wrapped difference rejects it |
| `swap` | `[0, 65]` | Expose the saved character |
| `alpha-upper?` | `[0, U]` | At the uppercase lower boundary |
| `or` | `[U]` | At least one canonical flag is true |

The gap matters: byte 91, `[`, lies above `Z` and below `a`. Neither range
accepts it. Replacing both ranges with one broad 65-through-122 interval
would incorrectly accept that gap.

## Keep the character until the last equality test

The library's whitespace set is **exactly** space (32), tab (9), line feed
(10), and carriage return (13). It excludes byte 11, vertical tab, and byte
12, form feed. Do not read `space?` as a promise to recognize every C
whitespace character or every Unicode whitespace character.

The four values do not form one contiguous range, so the library combines
four equality tests:

```forth
: space?  dup [lit] 32 - 0= over [lit]  9 - 0= or
          over [lit] 10 - 0= or  swap [lit] 13 - 0= or ;
```

Each `- 0=` is the equality mechanism already proved. The definition spells
it out rather than calling `=`; in the source file, these classifiers appear
before the named comparison words. Our learning order followed their
contracts instead of that file order.

Trace byte 10. Rows group an already-explained equality test into one step:

| After | Stack, top right |
|---|---|
| Start | `[10]` |
| `dup [lit] 32 - 0=` | `[10, 0]` |
| `over` | `[10, 0, 10]` |
| `[lit] 9 - 0= or` | `[10, 0]` |
| `over` | `[10, 0, 10]` |
| `[lit] 10 - 0= or` | `[10, U]` |
| `swap` | `[U, 10]` |
| `[lit] 13 - 0=` | `[U, 0]` |
| `or` | `[U]` |

Before the last test, the repeating state is `[c, accumulated-flag]`.
`over` copies the character from beneath that flag. `dup` would copy the
flag instead. At the last test, `swap` exposes the remaining character
without keeping another copy. Thus the final result is one flag, as promised.

All four tests run even when an earlier one is true. `or` combines results;
it does not skip evaluation. Nothing here requires a loop or an untaught
conditional mechanism.

## Practice

Use paper, a text editor, or spoken traces. The [feedback companion](../practice/05-solutions.md)
has graduated hints, worked answers and changed cases. Keep it accessible;
an independent attempt and a supported attempt tell you different things.

### S5-01 — Equality and flag representation

Trace `=` separately from `[U, U]` and `[U, 0]`. Explain why wrapping does
not invalidate the second answer. Then trace `0= 0=` from `[1]` and `[0]`.
Why would leaving the quotient 1 directly from the sign-bit division violate
the canonical-flag contract?

### S5-02 — Check the opposite extreme

Use signed inputs `a=-H` and `b=1`, represented by `0x8000000000000000` and
`0x0000000000000001`. Derive the stored result of `-`, then the library's `<`
flag. Compare it with mathematical signed ordering and identify the failed
precondition. Does `=` on these same inputs still work? Finally, explain why
the pair 48 and 57 is safe for all four ordering definitions.

### S5-03 — Complete a different range

On paper, define a teaching word `octal-digit? ( c -- flag )` for byte inputs.
It should accept ASCII `0` through `7`, values 48 through 55. Complete:

```forth
: octal-digit?  [lit] ___ - [lit] ___ / 0= ;
```

Trace byte inputs 47, 48, 55 and 56. Explain rejection below the base as well
as above the range. Why is 55 not the divisor?

### S5-04 — Diagnose an extra value

A copy of `space?` mistakenly uses `over` in place of its final `swap`.
Starting with `[99, 13]`, trace the changed ending after the first three
tests. Give the entire final stack. Does getting the right topmost flag
establish the promised `( c -- flag )` effect? Repair the ending.

### S5-05 — Combine categories independently

ASCII underscore has byte value 95. Define a teaching word
`demo-name-start? ( c -- flag )` that accepts a byte exactly when `alpha?`
accepts it or it equals 95. Use `dup`, `swap`, `alpha?`, `=`, `or` and a
literal. Trace 95 and 91. Preserve older stack items. This is a specified
teaching category, not a claim about all legal identifiers in another language.

## Check, return, and continue

If an answer differs, locate the first disputed state. A wrong quotient calls
for the unsigned contract; an extra final character calls for the `over` versus
`swap` distinction; a wrong ordering flag calls for checking the mathematical
difference before applying the sign test. Use the matching hint, then try the
changed case without copying the solution.

For a delayed revisit after other material, return to S5-02 and S5-05 with
their answers closed. Explain a failure boundary as well as a successful
case. If you stop now, save the state `[10, U]` before `space?`'s final
`swap`: on resuming, finish that trace and explain why no character remains.

You can now distinguish whole-cell equality, a sign bit, bounded ordering,
and byte membership. Next, [Memory updates and writers](06-memory-updates-and-writers.md)
returns to stored values and byte emission, carrying these precise stack
contracts forward.

## Source and evidence

The exact library definitions are in
[`010-lib.fth`, character classifiers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L71-L95)
and [comparison operators](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L97-L137).
The primitive contracts come from
[`zeq_code` and unsigned `divide_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L212-L237),
with the unsigned literal reader in
[`parse_decimal_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L633-L662).
The domain arguments and examples are derived under those contracts. No
build, seed execution, timing comparison, or whole-project range audit is
claimed. See the [edition record](../../EDITION.md) for the shared boundary.
