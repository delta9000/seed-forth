# Exact floating printf conversions

gawk prints every non-integer value through `%.6g` (its default `OFMT` and
`CONVFMT`), coreutils `seq` and `printf` use `%f` and `%g`, and many
configure scripts and test suites print measured values. The printf family
(`printf`, `fprintf`, `sprintf`, `snprintf`, `vprintf`, `vfprintf`,
`vsprintf`, `vsnprintf`) therefore converts binary64 and x87 extended80
values with `%e %E %f %F %g %G %a %A`, byte-for-byte as glibc does.

`floatfmt.c` produces the text and `stdio.c` pads and writes it. The private
interface between the two is `include/seed-float.h`; programs must not use it.

## Accepted directives

- Flags `-`, `+`, space, `#` and `0`, in any order and combination. `-`
  overrides `0`; `+` overrides space. `0` pads after the sign (and after
  `0x` for `%a`); infinities and NaNs are padded with spaces.
- Field width and precision as digits or `*` (a negative `*` width means
  `-` with its absolute value; a negative `*` precision means none).
  A `.` alone is precision 0.
- Length modifiers: none or `l` read a `double` (`float` arguments arrive
  promoted). `L` and, as in glibc, `ll` read a `long double`.
- Default precision is 6 for `e`, `f` and `g`. For `a` it is the shortest
  exact hexadecimal fraction.

Positional arguments (`%1$f`) are not supported; like every unsupported
directive they fail with `EINVAL` before consuming the argument.

## Spellings

`inf`, `-inf`, `nan` and `-nan` (sign bit set), upper case for `F E G A`.
`-0.0` keeps its sign: `%g` gives `-0`. Exponents have at least two digits
for `e` and at least one for `a` (`0x1p+0`). `%a` of a binary64 normal is
`0x1.<hex>p<exp>`, of a subnormal `0x0.<hex>p-1022`, and of zero `0x0p+0`.
For extended80 the leading hexadecimal digit is the top four bits of the
64-bit significand (`%La` of 1.0 is `0x8p-3`), as glibc prints it; a
subnormal uses exponent -16385. Invalid extended80 encodings (pseudo-NaN,
pseudo-infinity, unnormal) print as NaN.

## Exactness

A finite nonzero value is `M * 2^E`. With base-10^9 limbs the integer
`M * 2^E` (for `E >= 0`) or `M * 5^-E` (with the decimal point `-E` digits
from the right) is expanded to every one of its decimal digits: at most 767
significant digits for binary64 and 11,495 for extended80. The requested
digits are then rounded once on the exact expansion: up when the first
dropped digit exceeds 5 or is 5 followed by any nonzero digit, down when it
is below 5, and to an even last digit when it is exactly 5 with nothing
after it. This is glibc's result in the default round-to-nearest mode; the
runtime has no `fesetround`, so other rounding modes are not modelled.

- `%e` keeps precision+1 significant digits; a carry (9.99 to 10.0) raises
  the exponent.
- `%f` keeps all integer digits and `precision` fraction digits. Digits
  beyond the exact expansion are zeros, so `%.1100f` of the smallest
  subnormal prints its exact 1,074 fraction digits and then zeros.
- `%g` with precision P (0 means 1) finds the exponent X that style `e`
  would print, then uses style `f` with precision P-1-X when P > X >= -4,
  otherwise style `e` with precision P-1. Without `#`, trailing fraction
  zeros and a trailing point are removed.
- `%a` rounds the hexadecimal fraction to the precision, ties to even. A
  binary64 leading `1` may become `2` (`%.0a` of 1.5 is `0x2p+0`); an
  extended80 leading `f` that rounds up becomes `0x1` with the exponent
  raised by 4.

glibc compatibility quirk, reproduced deliberately: with `#`, when the exact
exponent selects style `f` with no fraction digits (X = P-1) and rounding
carries into one more integer digit, glibc prints style `e` with no fraction
digits. `%#g` of 999999.5 is `1.e+06` and `%#.3g` of 999.6 is `1.e+03`,
where ISO C would give `1.00000e+06` and `1.00e+03`. Without `#` the two
readings print the same text.

## Output, lengths and errors

Results longer than `INT_MAX` fail with `EOVERFLOW` (75), as for other
conversions. `snprintf` truncation counts the full length. Padding and
zero runs are written in bounded blocks, so huge widths and precisions do
not need large buffers. The digit buffers are static: the formatter is not
reentrant, which suits the single-threaded runtime (a signal handler must
not call printf while printf runs, as with any non-async-signal-safe
function).

## Tests

`tests/gcc/printf-float-check.py` builds `tests/gcc/printf-float-check.c`
twice: with the Forth compiler against this runtime (production) and with
host GCC against glibc (expected-output oracle only). Each section prints
one line per case; the two outputs must be byte-identical. At scale 1 it
compares 1,502,212 lines:

- 800,000 random binary64 bit patterns (every exponent, subnormals, short
  significands) with random flags, widths, precisions 0..60 and all eight
  conversions;
- every precision 0..60 for `%e %f %g` and 0..16 for `%a` on 1,500 values;
- exact ties `m * 2^-k` (k up to 69) at and around their last digit, and
  integer ties such as 25 and 125 under `%e` and `%g`;
- all 32 flag sets with four widths and six precisions on 24 special values
  (zeros, subnormal and normal boundaries, `DBL_MAX`, infinities, NaNs),
  and `*` widths/precisions from -25 to 25;
- 4,000 random extended80 values (normals, subnormals, specials) with `L`;
- `%.1100f` and `%.800e` of the smallest subnormal, `%.400f` of `DBL_MAX`,
  5,000-column fields, `snprintf`/`vsnprintf` truncation at sizes 0..11,
  and each of `printf`, `fprintf`, `sprintf`, `vsprintf`.

`--scale N` multiplies the random sections; a scale-8 run compared
10,907,782 lines with no difference. `stdio-oracle-check.py` adds floating
cases to its host-libc comparison of the Forth-built `stdio.o`.
