# Comparisons and characters feedback

Return to [Chapter 5](../chapters/05-comparisons-and-characters.md). Use a hint,
a worked comparison, or the full solution whenever it helps. All results are
manual derivations under the pinned 64-bit seed contract, not observed runs.
The stack top is at the right. `M=2^64`, `H=2^63`, and `U=M-1`; these symbols
are explanation notation rather than seed words.

## S5-01 — Equality and flag representation

**Hint 1.** Expand `=` into `- 0=`. Ask whether the stored difference is zero,
not whether its signed interpretation is negative.

**Hint 2.** `U-U` is zero, while `U-0` is `U`. For normalization, the second
zero test sees the result of the first, not the original input.

**Worked solution.** The equality traces are:

| Starting stack | After `-` | After `0=` |
|---|---|---|
| `[U, U]` | `[0]` | `[U]` |
| `[U, 0]` | `[U]` | `[0]` |

The first pair contains equal patterns; the second does not. In the second
row the stored difference is all ones, not zero, so equality is false.
Interpreting that pattern as signed -1 would not change the zero test.

More generally, modular subtraction of two cell patterns yields zero only
when they are the same pattern. Choosing signed interpretations can change
how we order unequal cells, but not whether their bits match.

The normalization traces are:

```text
start       [1]          [0]
first 0=    [0]          [U]
second 0=   [U]          [0]
```

The quotient 1 from the sign-bit division says “the bit is set.” Its cell has
only the low bit set. Canonical true, `U`, has every bit set. They are both
nonzero, but keeping 1 would break the promised representation and the
all-ones-mask property used when composing flags.

**Common wrong path.** Treating `0=` as bitwise complement gives the wrong
intermediate result for 1. The actual first result is zero, not `U-1`.

**Changed case.** Close the worked trace and use equality inputs `[0, U]`.
Subtraction now gives 1, because `0-U` modulo `M` is 1; equality still returns
zero. Then normalize 57: `[57] -> [0] -> [U]`. A different nonzero input must
reach the same canonical true value.

**Check your explanation.** It should distinguish bit-pattern equality,
nonzero numeric conditions, and canonical flags, rather than treating the
three as interchangeable.

## S5-02 — Check the opposite extreme

**Hint 1.** First compute the unbounded signed difference. Check whether it
lies in `[-H, H-1]` before looking at its stored pattern.

**Hint 2.** The unsigned pattern for `-H` is `H`. Subtracting one from that
pattern leaves `H-1`, whose top bit is clear.

**Worked solution.** The mathematical signed calculation is:

```text
-H - 1 = -9223372036854775809
```

That is one below the smallest representable signed value. The cell
calculation instead leaves:

```text
0x8000000000000000 - 0x0000000000000001
    = 0x7FFFFFFFFFFFFFFF
```

This stored pattern is `H-1`, or signed 9223372036854775807. Expanding the
remaining sign test:

| After | Stack |
|---|---|
| `-` | `[H-1]` |
| `2^63` | `[H-1, H]` |
| `/` | `[0]` |
| First `0=` | `[U]` |
| Second `0=` | `[0]` |

The library's `<` therefore returns false, although mathematically `-H < 1`
is true. The problem occurs before sign extraction: the difference failed
the representable-signed-difference precondition. `0<` correctly reports the
sign of the pattern it actually receives.

Equality still works. Expanding `=` on the same inputs gives difference
`H-1`, then `0=` returns zero. The patterns are unequal. There is no
contradiction: equality only needs to distinguish zero from nonzero, while
this ordering construction needs the sign of a representable difference.

For inputs 48 and 57, the two directional differences are -9 and 9. Both
fit in `[-H, H-1]`, so `<`, `>`, `<=` and `>=` all have their intended signed
meaning. The argument uses the actual bounds, not a rule that all “counts”
or “characters” are automatically safe.

**Common wrong path.** Replacing the stored result with the unbounded
negative difference makes the paper trace follow a different arithmetic
machine. Keep both values visible and identify the point where they diverge.

**Changed case.** Compare `a=-H` with `b=0`. Their signed difference is `-H`,
which does fit. `<` returns `U`, correctly. But `>` swaps the operands and
tries a mathematical difference of `H`, which does not fit. Its stored
pattern is again `H`, interpreted as signed `-H`, so `>` also returns `U`,
incorrectly. Thus this source implementation can make both comparisons true
at that boundary.

This does not weaken the common sufficient condition: the pair is exactly
`H` apart, not strictly less than `H` apart. It demonstrates why the strict
endpoint matters and why the one-direction domain must not be silently
reused for every derived word.

## S5-03 — Complete a different range

**Hint 1.** The first constant is the lower endpoint. The divisor is the
number of accepted consecutive values, including both endpoints.

**Hint 2.** Subtracting 48 should map 48 through 55 to zero through seven.
There are eight values in that interval.

**Worked solution.** A valid teaching definition is:

```forth
: octal-digit?  [lit] 48 - [lit] 8 / 0= ;
```

It uses the exact unsigned-division contract of this seed. Its boundary
traces are:

| Input byte | After subtracting 48 | After unsigned `/ 8` | Final flag |
|---:|---|---|---|
| 47 | `U` | `H/4-1`, or 2305843009213693951 | `0` |
| 48 | 0 | 0 | `U` |
| 55 | 7 | 0 | `U` |
| 56 | 8 | 1 | `0` |

Here `H/4-1` is explanation notation for the integer quotient; it is not
part of the Forth definition. Since `U = 2^64-1`, division by eight drops
the remainder seven and leaves `2^61-1`.

For any byte below 48, the difference wraps into the interval `M-48`
through `M-1`; every value there is greater than eight. The quotient is
nonzero, so all such bytes are rejected. For any byte above 55, the
unwrapped difference is at least eight, so it too gives a nonzero quotient.
Only differences zero through seven yield zero.

The divisor is eight because division must map precisely eight consecutive
nonnegative differences to zero. Using 55 would instead accept differences
zero through 54: byte values 48 through 102. An upper endpoint and a span
are different quantities.

**Common wrong path.** Reasoning that 47 produces signed -1 and then a zero
quotient imports a signed-division rule. The seed divides unsigned `U`.

**Changed case.** Without copying the trace, design a two-byte-value range
accepting ASCII `0` and `1`, codes 48 and 49. The body becomes
`[lit] 48 - [lit] 2 / 0=`. Inputs 47, 48, 49 and 50 give flags
`0, U, U, 0`. Explain the first rejection using the wrapped difference.
This is a range of two accepted byte values, not a two-byte character encoding.

## S5-04 — Diagnose an extra value

**Hint 1.** After the first three tests, the original character is still
beneath the accumulated flag. Keep the older 99 visible too.

**Hint 2.** For input 13, the first three equalities all fail. Compare the
results of `over` and `swap` on `[99, 13, 0]`.

**Worked solution.** Neither space, tab nor line feed has byte value 13, so
the state before the changed operation is `[99, 13, 0]`. The broken ending is:

| After | Stack |
|---|---|
| First three tests | `[99, 13, 0]` |
| Mistaken `over` | `[99, 13, 0, 13]` |
| `[lit] 13` | `[99, 13, 0, 13, 13]` |
| `-` | `[99, 13, 0, 0]` |
| `0=` | `[99, 13, 0, U]` |
| `or` | `[99, 13, U]` |

The topmost flag is correct, but the original 13 remains. The word has
performed `( c -- c flag )`, not its promised `( c -- flag )`. A caller
using the promised effect would have an extra value to contend with.

Restore `swap` at the last stage:

```text
[99, 13, 0]  -> swap ->  [99, 0, 13]
[lit] 13 - 0=       ->  [99, 0, U]
or                 ->  [99, U]
```

The character is consumed and the older 99 is preserved. An equivalent
repair could remove the retained character after the final `or`, but restoring
`swap` directly recovers the source's intended lifetime: retain copies only
while another test still needs the character.

**Common wrong path.** Reporting only `[U]` ignores the very thing being
debugged. When verifying stack effects, account for every surviving value,
including any older stack items in the stated starting condition.

**Changed case.** Reattempt with input `[99, 11]`. All four equality tests
fail. The broken version leaves `[99, 11, 0]`, and the correct version leaves
`[99, 0]`. Byte 11 is not in this library's four-value whitespace set.

## S5-05 — Combine categories independently

**Hint 1.** Follow the same lifetime pattern as `alpha?`: make one copy,
consume one in the first test, expose the other, and combine the flags.

**Hint 2.** After `dup alpha?`, the stack is `[c, alphabetic-flag]`. The
remaining character must become the lower operand of an equality with 95.

**Worked solution.** One valid teaching definition is:

```forth
: demo-name-start?  dup alpha? swap [lit] 95 = or ;
```

Trace with an older 99 underneath to check preservation:

| After | Underscore input | Gap input |
|---|---|---|
| Start | `[99, 95]` | `[99, 91]` |
| `dup` | `[99, 95, 95]` | `[99, 91, 91]` |
| `alpha?` | `[99, 95, 0]` | `[99, 91, 0]` |
| `swap` | `[99, 0, 95]` | `[99, 0, 91]` |
| `[lit] 95` | `[99, 0, 95, 95]` | `[99, 0, 91, 95]` |
| `=` | `[99, 0, U]` | `[99, 0, 0]` |
| `or` | `[99, U]` | `[99, 0]` |

Both 95 and 91 lie between the uppercase and lowercase letter ranges, so
`alpha?` rejects both. Equality accepts only 95. The final `or` combines two
canonical flags, consumes them, and leaves one canonical answer. The original
character has been consumed; the older 99 remains.

**Common wrong path.** Omitting `swap` would test the alphabetic flag against
95 rather than testing the original character. The equality operands, not
merely the number of stack items, need checking.

**Changed case.** Use byte 122, `z`, and byte 123, `{`. For 122, `alpha?`
returns `U`, equality with 95 returns zero, and the final answer is `U`.
For 123, both tests return zero. The changed pair checks the end of a letter
range rather than underscore's isolated equality.

**Acceptance criteria.** A correct alternative uses the specified byte
category, returns exactly one canonical flag, preserves older items, and
explains both acceptance routes and a rejected gap value. It need not use
the same word order if its trace establishes those properties.

## Returning after other work

Try S5-02's changed case and S5-05's changed pair with these answers closed.
Then reopen the relevant solution and compare the first differing state.
If normalization slipped, revisit S5-01; if a saved character slipped,
retrace S5-04 before expanding an entire classifier. Help used during a trace
is useful practice, and a later fresh trace is a separate check of what you
can now reconstruct.
