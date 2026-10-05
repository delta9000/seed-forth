# Correctly rounded decimal input: atof

Original binutils 2.30 `binutils/stabs.c` reads stabs floating constants
(`c=r<value>`) with `atof`, and objdump links `stabs.o`. libiberty's
`strtod.c` replacement also calls `atof`. The runtime previously had no
floating input at all ([README.md](README.md)), so objdump's link failed on
`atof`. `decimal.c` adds `atof` alone; `strtod` and its end pointer and
`ERANGE` reporting are not supplied, so libiberty keeps its own `strtod.o`.

## Accepted text

After C-locale white space and an optional sign, `atof` reads the longest
decimal prefix: digits with at most one `.`, at least one digit, then an
optional `e`/`E` exponent that is used only when at least one digit follows
its optional sign. Case-insensitive `inf`/`infinity` and `nan` give infinity
and a quiet NaN with the sign applied. Text with no digits gives `+0.0`.
Hexadecimal floating input is not recognized: `0x10` reads the decimal prefix
`0` and gives `0.0`, where glibc gives 16. No consumer on this path writes it.

## Rounding

The result is the binary64 value nearest the exact decimal, ties to even,
with gradual underflow; overflow gives infinity. The conversion is exact
integer arithmetic, with no floating operation:

1. Up to 800 significant digits are kept. When a nonzero digit is dropped,
   a final `1` digit is appended instead (sticky digit). A decimal that lies
   exactly half-way between two doubles needs at most 768 significant
   digits, so the appended digit decides exactly the ties the dropped
   digits would have. Leading and (without a dropped digit) trailing zeros
   only move the decimal exponent.
2. With the value in `[10^(n-1), 10^n)`, `n > 310` is infinity and
   `n < -324` is zero before any big arithmetic. The exponent text saturates
   at one billion.
3. The digits become a natural number `num`, and the decimal exponent a
   power of ten in `num` or in `den`, as base-2^32 numbers of at most 160
   limbs. Scaling by a power of two puts `num/den` in `[2^62, 2^64)`, and 64
   steps of restoring division give the quotient and whether a remainder
   exists.
4. The quotient is rounded to 53 bits, or fewer below 2^-1022, using its
   discarded bits and the remainder as sticky; a carry to 2^53 renormalizes
   and a subnormal rounding up to 2^-1022 becomes the smallest normal.

`atof` does not change errno. It keeps two static numbers, so it is not
reentrant, like the rest of the single-threaded runtime.

## Gate

`tests/gcc/binutils-runtime-check.py` (see [FILE-METADATA.md](FILE-METADATA.md))
feeds 4,397 lines to `tests/gcc/decimal-input-check.c`, which prints the bits
of `atof` for each. The Forth build must match host glibc at `-O0` and `-O2`
and Python's correctly rounded `float()` on every line. Inputs include the
largest and smallest normal and subnormal boundaries, overflow and underflow
just across them, `2^53 + 1`, white space, signs and malformed exponents,
a 401-digit integer and a 400-zero fraction, saturated exponents, 120 exact
half-way points (normal, subnormal and near overflow), each also with a `1`
appended after 50 and after 900 further zeros, and 4,000 random decimals of
up to 900 digits with exponents from -1250 to 330. Hexadecimal input is checked
only against the documented `0.0`.
