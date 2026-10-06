# Bits and subtraction feedback

Return to [Chapter 3](../chapters/03-bits-and-subtraction.md). These hints and
solutions are available whenever you need them. All results are manual
derivations under the 64-bit chapter contract unless the problem explicitly
changes the width. `M=2^64`, `U=M-1`, and the stack top is at the right.

## S3-01 Trace and distinguish

**Hint 1.** Write 6 and 3 in binary to find which one-bits overlap.

**Hint 2.** In four low bits, 6 is `0110` and 3 is `0011`. Their AND is
`0010`. The real NAND still flips all 64 bits.

**Worked solution.** The two literals leave `[6, 3]`. Expanding `and`:

| Operation | Stack after |
|---|---|
| `nand` | `[U-2]` |
| `dup` | `[U-2, U-2]` |
| `nand` | `[2]` |

By contrast, `[lit] 6 0=` leaves `[0]` because the whole input is nonzero.
`nand` complements a bitwise AND; `0=` asks whether one entire cell is zero.
The functions differ even though some inputs can produce the same result.

**Common wrong path.** Giving 13 as the first NAND result complements only
four bits. In a 64-bit cell, the leading sixty zero bits are complemented too.

**Changed case.** Use 5 and 10 as the `and` inputs. Their one-bits do not
overlap, so the trace is `[5,10] -> [U] -> [U,U] -> [0]`. A zero result does
not mean either original number was zero.

## S3-02 Complete the construction

**Hint 1.** After the first `dup nand`, which original input is still buried?

**Hint 2.** The stack is `[a, ~b]`. Expose `a` without losing `~b`.

**Worked solution.** The missing word is `swap`:

```forth
: or   dup nand swap dup nand nand ;
```

The complete symbolic trace is
`[a,b] -> [a,b,b] -> [a,~b] -> [~b,a] -> [~b,a,a] -> [~b,~a] -> [a|b]`.
It gives the final NAND two complemented inputs, as the identity requires.

Without `swap`, the trace becomes
`[a,b] -> [a,b,b] -> [a,~b] -> [a,~b,~b] -> [a,b] -> [~(a&b)]`.
That is NAND of the original inputs, not OR. With two zero inputs it returns
`U`, while OR should return zero.

**Changed case.** Use `U` and zero. The correct OR and the broken definition
both return `U` here. This shows why one convenient test cannot establish
the intended function. The zero/zero case distinguishes them.

## S3-03 Diagnose a predicate bug

**Hint 1.** What does `and` promise: a test of whole numbers or an operation
at corresponding bit positions?

**Hint 2.** Each nonzero numeric condition needs the same all-ones flag before
the bitwise operation can serve as logical conjunction.

**Worked solution.** The word is following its contract. The low-bit patterns
`0010` and `0100` have no shared one-bit, so their AND is zero. Normalize the
conditions first:

```forth
[lit] 2 0= 0= [lit] 4 0= 0= and
```

| Operation | Stack after |
|---|---|
| `[lit] 2` | `[2]` |
| `0=` | `[0]` |
| `0=` | `[U]` |
| `[lit] 4` | `[U,4]` |
| `0=` | `[U,0]` |
| `0=` | `[U,U]` |
| `and` | `[U]` |

Both whole numbers are nonzero, so the canonical answer is true.

**Common wrong path.** Merely replacing `and` with `or` fails when exactly
one input is zero: it would still yield a nonzero value.

**Changed case.** Replace 4 with zero. The normalized flags are `[U,0]`, and
AND returns zero, correctly saying that both conditions do not hold.

## S3-04 Build a related word

**Hint 1.** The subtraction definition first builds the inverse of its top
input, then adds that to a lower input. This task ends before the last step.

**Hint 2.** Complement alone gives `U-x`; another one is needed to make
`x + inverse` a multiple of `M`.

**Worked solution.** One valid teaching definition is:

```forth
: negate-cell  dup nand [lit] 1 + ;
```

On zero: `[0] -> [0,0] -> [U] -> [U,1] -> [0]`.
The last addition wraps because `U+1=M`.

On five: `[5] -> [5,5] -> [U-5] -> [U-5,1] -> [M-5]`.
The unsigned result is 18446744073709551611. Its signed interpretation is -5.
It consumes one cell and produces one cell, with a temporary extra copy and
literal while it runs.

**Common wrong path.** Keeping the final `+` from the subtraction definition
would require an additional lower input and violate this one-input contract.

**Changed case.** Use `2^63`. The result is `M-2^63=2^63`, the same bit
pattern. The signed interpretation is `-2^63` both before and after; there is
no representable positive signed counterpart in this width. The modular
inverse equation remains valid.

## S3-05 Change the width

**Hint 1.** Substitute `M=256` and `U=255` throughout. Do not reuse the
64-bit all-ones value.

**Hint 2.** Complement of ten is 245. Adding one gives its eight-bit inverse,
246.

**Worked solution.** On the hypothetical eight-bit machine:

| Operation | Stack after |
|---|---|
| Start | `[3,10]` |
| `dup` | `[3,10,10]` |
| `nand` | `[3,245]` |
| Literal 1 | `[3,245,1]` |
| `+` | `[3,246]` |
| `+` | `[249]` |

Unsigned 249 is `256-7`, so its signed eight-bit interpretation is -7. The
inverse argument is unchanged in structure: `b+(U-b)+1=M`. The modulus,
all-ones value, result range and signed boundary change with the width.

Putting numeric 249 into a 64-bit cell gives fifty-six leading zero bits and the
eight-bit pattern `11111001`. As a signed 64-bit value that is positive 249.
Representing signed -7 at 64 bits requires the 64-bit pattern `M-7`, which has
leading ones. Width conversion therefore needs a stated rule; copying an
unsigned numeric value is not the same as preserving a signed interpretation.

**Changed case.** Start with `[10, 3]` and execute `-` at eight bits. Complement of 3 is 252;
adding one gives 253; adding 10 gives 263, which wraps to 7. The result is
positive seven under both interpretations. That easy case alone would not
reveal the width-conversion problem.

## What a correct attempt establishes

If you can solve a changed case and explain the key transition, you have
evidence about that capability under those conditions. Copying the worked
case, independent tracing, later recall and recognizing the principle in a
compiler are different checks. Use the [return check](return-check.md) after
some intervening work; it supplies another opportunity, not a certification.
