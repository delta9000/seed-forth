# Correctly rounded floating input: strtod, strtof, strtold, atof

Original binutils 2.30 `binutils/stabs.c` reads stabs floating constants
with `atof`; gawk 3.0.4 converts every numeric-looking field and string with
`strtod`; coreutils `seq`, `printf` and `sort -g` parse their operands with
`strtod`/`strtold`. `decimal.c` supplies all four functions. `atof(s)` is
`strtod(s, NULL)`.

## Accepted text

After C-locale white space (space, `\t \n \v \f \r`) and an optional sign,
the longest prefix of one of these forms is converted:

- decimal: digits with at most one `.`, at least one digit, then an optional
  `e`/`E` exponent that is used only when at least one digit follows its
  optional sign (`1e+` converts `1`);
- hexadecimal: `0x` or `0X`, hexadecimal digits with at most one `.` and at
  least one digit, then an optional `p`/`P` binary exponent under the same
  rule. `0x` without a hexadecimal digit converts the `0` alone;
- `inf` or `infinity` in any case (the longer one when it matches);
- `nan` in any case, optionally followed by `(n-char-sequence)` of letters,
  digits and `_`. As in glibc, a sequence that is entirely one
  `strtoul(..., 0)` number sets the NaN payload (masked to the fraction bits
  below the quiet bit); any other sequence is consumed without a payload.
  An unclosed `(` is not consumed.

The sign applies to every form, including NaN. When no form matches, the
result is `+0` and the end pointer is the original argument. Decimal
points other than `.` (locales) are not supported.

## Rounding

The result is the value of the chosen format (binary32, binary64, or x87
extended80 with its 64-bit significand) nearest the exact input, ties to
even, with gradual underflow; values beyond the largest finite value after
rounding become infinity. The conversion is exact integer arithmetic, with
no floating operation:

1. Significant digits are kept up to a limit that exceeds the longest
   decimal half-way point of the format (120 for binary32, 800 for binary64,
   11,600 for extended80; the half-way points need at most 112, 768 and
   about 11,520). When a nonzero digit is dropped, a final `1` digit is
   appended instead, which decides exactly the ties the dropped digits
   would have. Hexadecimal input keeps 40 significant digits and appends a
   sticky low bit the same way.
2. With the value in `[10^(n-1), 10^n)`, an `n` beyond the format's range
   is infinity or zero before any big arithmetic. Exponent text saturates
   at 10^8.
3. The value becomes `num/den` with base-2^32 numbers of up to 1,800 limbs.
   Its binary exponent `e` is found exactly. The number of result bits is
   the precision, or fewer for a subnormal; scaling by a power of two puts
   `num/den` in `[2^(p-1), 2^p)`, and `p` steps of restoring division give
   the significand. Twice the remainder compared with `den` decides the
   rounding; a carry to `2^p` moves to the next binade (a subnormal that
   rounds up to `2^emin` becomes the smallest normal).

## errno and the end pointer

`*end` (when `end` is not NULL) points just past the converted text. errno
is set only to `ERANGE`, following glibc:

- overflow: the result is `+-HUGE_VAL` (infinity);
- underflow: the result is inexact and tiny after rounding, meaning that
  rounding the exact value to the full precision with an unbounded exponent
  gives a magnitude below the smallest normal. A result that rounds to zero
  from a nonzero input is underflow. Exact subnormals (`0x1p-1074`) and
  values that round up to the smallest normal from at least
  `2^emin - 2^(emin-p-1)` do not set errno;
  `2.2250738585072012e-308` (rounds to `DBL_MIN`, but would not at
  unbounded exponent) does.

Successful conversions leave errno unchanged. `strtold` returns an x87
extended80 value; the runtime supports long double only for data movement
(storage, arguments, `printf("%Lg")`), and builds the value from its bytes.

The functions keep three static big numbers, so they are not reentrant,
like the rest of the single-threaded runtime.

## Gates

`tests/gcc/strtod-check.py` builds `tests/gcc/strtod-check.c` with the
Forth compiler (production) and with host GCC against glibc (expected-output
oracle only). The fixture generates its own inputs from a seeded generator,
with an independent exact decimal expander for half-way points, and prints
for each input the result bits, errno and end offset of `strtod`, `atof`,
`strtof` and (for every extended80 case) `strtold`. At scale 1 it checks
340,132 inputs; the outputs must be byte-identical:

- 200,000 random decimals of 1 to 800 digits, with and without a point,
  exponents from -350 to 349 (some to +-5000), signs, white space and
  trailing garbage;
- 100,000 random hexadecimal inputs of up to 45 digits, both cases, binary
  exponents up to +-16,500;
- 40,000 exact half-way points between adjacent binary32, binary64 and
  extended80 values (normal, subnormal, near overflow), each exact, truncated,
  one unit below, or followed by zeros and a final `1`;
- 132 special inputs: the `DBL_MIN`/`FLT_MIN`/`LDBL_MIN` and maximum
  boundaries, all the infinity/NaN spellings and payload forms, malformed
  exponents and prefixes, 2,000-digit inputs.

A scale-10 run checked 3,400,132 inputs with no difference.
`tests/gcc/binutils-runtime-check.py` keeps its original `atof` gate: 4,397
lines compared with host glibc at `-O0`/`-O2` and with Python's correctly
rounded `float()`, and hexadecimal `0x10` and `0x1p3` now convert to 16 and 8.
