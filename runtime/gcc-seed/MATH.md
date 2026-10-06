# Binary64 math library

`math.c` is the `-lm` library: original seed-forth MIT code, not copied or
adapted from glibc, musl, fdlibm or any other libm. `fpclass.c` holds the
operations a C program may use without `-lm` (the classification helpers
behind the `math.h` macros, and `frexp`, `ldexp`, `scalbn`, `modf` and
`copysign`, which glibc also exports from libc). `math.c` stays one file
because the driver builds exactly that file for `-lm`
([MATH-LINKING.md](MATH-LINKING.md)); it depends on nothing but `errno`.

Machine contract: AMD64 LP64, IEEE binary64, round to nearest/ties to even,
gradual underflow (no FTZ/DAZ), independently rounded operations (no
contraction or excess precision). Union access interprets the representation.
There is no floating-point environment: no `fenv.h`, no other rounding modes,
no exception flags; `math_errhandling` is `MATH_ERRNO`. Only `double`
functions exist (no `float`/`long double` variants).

## Interface

| Group | Functions | Result |
|---|---|---|
| exact, libc | `frexp ldexp scalbn modf copysign` | exact (`ldexp`/`scalbn` round once into subnormals) |
| exact, `-lm` | `fabs floor ceil trunc round rint nearbyint lround lrint llround llrint fmod remainder fmin fmax fdim` | exact |
| `-lm` | `sqrt` | correctly rounded |
| `-lm` | `exp exp2 expm1 log log2 log10 log1p pow cbrt hypot sin cos tan asin acos atan atan2 sinh cosh tanh` | one final rounding of a double-double; measured below 0.501 ulp |

Macros: `HUGE_VAL`, `INFINITY`, `NAN`; `FP_NAN FP_INFINITE FP_ZERO
FP_SUBNORMAL FP_NORMAL` (glibc's values 0-4); `fpclassify isnan isinf
isfinite isnormal signbit isunordered islessgreater` (helper calls, argument
evaluated once) and `isgreater isgreaterequal isless islessequal` (plain
comparisons); `MATH_ERRNO MATH_ERREXCEPT math_errhandling`; the POSIX
constants `M_E M_LOG2E M_LOG10E M_LN2 M_LN10 M_PI M_PI_2 M_PI_4 M_1_PI M_2_PI
M_2_SQRTPI M_SQRT2 M_SQRT1_2`, each parsing to the binary64 nearest its value.

Limits of the header:

- `HUGE_VAL`/`INFINITY` are `(1.0 / 0.0)` and `NAN` is `(-(0.0 / 0.0))`:
  the Forth compiler's constant folder rejects overflow and division by zero,
  so they work in expressions but **not in static initializers**
  (`static double x = HUGE_VAL;` is a compile error). `INFINITY` and `NAN`
  have type `double`, not `float`. `HUGE_VALF`/`HUGE_VALL` are absent.
- The classification macros take `double` (or `float`, promoted); a
  `long double` argument is not supported (the compiler only moves long
  doubles).

## Algorithms

Exact operations work on the bit pattern. `floor`/`ceil`/`trunc`/`round`/
`rint` mask or carry into the fraction field; `fmod` and `remainder` run
binary long division on the integer significands (at most ~2100 shift/subtract
steps) and keep the quotient's last bit for `remainder`'s ties-to-even;
`ldexp`/`scalbn` rebuild the significand and round once when the result is
subnormal. `sqrt` is the restoring digit-by-digit square root on the integer
significand: a 54-bit root plus the nonzero-remainder flag decide the one
rounding (an exact tie is impossible for a square root).

Every other function evaluates a double-double (unevaluated sum hi + lo) with
relative error of order 2^-63 or better and rounds it once: hi + lo, or
`seed_finish` when a power-of-two scale is still pending, which also rounds
subnormal results directly from hi and lo (no double rounding).
Building blocks: Knuth's two-sum, Dekker's exact product with Veltkamp
splitting, and double-double add/multiply/divide.

- `log`: x = 2^k m, m in [0.75, 1.5), c = i/128 nearest m (i = 96..192),
  z = (m - c)/(m + c) formed as a double-double, |z| < 2^-8.5;
  log x = k ln 2 + ln c + 2 atanh z with atanh z = z + z^3/3 + ... + z^9/9
  (omitted tail below 2^-89 relative). `log2`/`log10` multiply by a
  double-double 1/ln 2 or 1/ln 10; exact powers of two give their exponent.
  `log1p` takes log of the exact sum 1 + x = sh + sl and adds sl/sh.
  Identity: DLMF 4.6.4, https://dlmf.nist.gov/4.6.E4.
- `exp2` core: n = nearest(64 y), 2^y = 2^(n div 64) 2^((n mod 64)/64)
  e^t with t = (y - n/64) ln 2, |t| <= ln 2/128, e^t - 1 by its Taylor series
  to t^7/7! (tail below 2^-75). `exp` multiplies x by a double-double 1/ln 2
  first; `pow` forms y log2|x| as a double-double. `expm1` uses the series
  directly for |x| < 0.005 and e^x - 1 in double-double otherwise.
  `sinh`, `cosh` and `tanh` combine e^x, 1/e^x and expm1 in double-double
  (expm1 forms avoid cancellation near 0). Series: DLMF 4.2.19.
- `pow`: special cases follow C99 Annex F.9.4.4; then 2^(y log2|x|) with the
  sign for odd integral y. Exactly representable results (`pow(10, 15)`,
  `pow(3, 20)`, `pow(2, -1074)`, `pow(x*x, 0.5)`) are returned exactly because
  the pre-rounding error is far below the distance to any rounding boundary.
- `cbrt`: |x| = m 2^(3q), m in [1, 8); Newton from (m+2)/3, then one
  correction y + (m - y^3)/(3 y^2) with y^3 exact as a double-double.
  Exact cubes return exactly (`cbrt(27) = 3`).
- `hypot`: scale both by the larger exponent, x^2 + y^2 exactly as a
  double-double, double-double square root, scale back with one rounding.
- `sin`/`cos`/`tan`: |x| <= pi/4 is used directly. Below 2^20, Cody-Waite
  reduction with pi/2 split into three 33-bit pieces (n < 2^20 keeps every
  n*piece exact) and a rounded fourth. From 2^20 to the largest double,
  Payne-Hanek: the 53-bit significand times nine 32-bit words of 2/pi chosen
  at the binary point (40 words, 1280 bits of 2/pi), giving the quadrant and
  192 fraction bits, so even the closest double to a multiple of pi/2
  (|r| ~ 2^-61) keeps over 120 correct bits. Kernels: Taylor series of sin
  to r^21 and cos to r^22 (leading coefficients as double-doubles); `tan` is
  a double-double quotient.
- `atan`/`atan2`/`asin`/`acos`: one core computes atan(min/max) for a
  double-double ratio t in [0, 1]: c = i/32 nearest t, d = (t - c)/(1 + t c),
  atan t = atan c + atan d with atan d by Taylor to d^13 (|d| <= 1/64);
  then pi/2 - a, pi - a by quadrant. `asin x = atan(x / sqrt(1 - x^2))` and
  `acos` similarly, with 1 - x^2 = (1 - x)(1 + x) exact as a double-double.

Constants and tables (ln 2, 1/ln 2, 1/ln 10, pi/2, pi, 3pi/4, the Cody-Waite
pieces, log(i/128), 2^(j/64), atan(i/32), 2/pi words, and the double-double
1/6, 1/120, 1/24, 1/720) are stored as binary64 bit patterns between the
`BEGIN/END GENERATED TABLES` markers of `math.c`. `tests/gcc/math-constants.py`
derives every one from first principles - pi by Machin's formula in integer
arithmetic, logarithms/exponentials/arctangents by Python Decimal at 80 and
120 digits (both must agree), double-doubles as hi = RN(v), lo = RN(v - hi) -
and fails if the block in `math.c` differs. It also checks each `M_*`
literal. The remaining polynomial coefficients are plain `1.0 / k` or
`1.0 / k!` expressions (exact factorials up to 22!), correctly rounded by the
compiler. No coefficient comes from another library or from host libm.

## Special values and errno

All results for NaN, infinities, zeros, subnormals and domain edges follow
C99 Annex F and agree with glibc 2.43 bit for bit, except the sign/payload of
NaN results (ours: NaN inputs propagate quieted via x + x or x + y; invalid
operations give the AMD64 default NaN 0xfff8000000000000, as glibc mostly
does). Every errno value agrees with glibc over the whole test set:

- `EDOM` (NaN result): `sqrt`, `log`, `log2`, `log10` of x < 0;
  `log1p(x < -1)`; `asin`/`acos` of |x| > 1; `sin`/`cos`/`tan` of infinity;
  `pow(x < 0, non-integer finite y)`; `fmod`/`remainder` with x infinite or
  y zero (and neither NaN).
- `ERANGE`: poles - `log*(±0)` = -inf, `log1p(-1)` = -inf, `pow(±0, y < 0)`
  = inf (but `pow(±0, -inf)` = inf leaves errno alone, like glibc);
  overflow to ±inf from finite arguments (`exp`, `exp2`, `expm1`, `pow`,
  `sinh`, `cosh`, `hypot`, `fdim`, `ldexp`, `scalbn`); underflow **to zero**
  of a nonzero result (`exp`, `exp2`, `pow`, `atan2`, `ldexp`, `scalbn`).
  Nonzero subnormal results do not set errno (glibc's policy; the previous
  exp/log-only runtime set ERANGE for every subnormal exp result).
- Otherwise errno is preserved. Out-of-range or NaN `lround`/`lrint`/
  `llround`/`llrint` return LONG_MIN (the AMD64 indefinite integer) without
  errno, as glibc on x86-64.
- `fmin`/`fmax` ignore one quiet NaN, return NaN for a signaling one
  (IEEE 754-2008 minNum/maxNum, as glibc), and return the second argument
  when the two compare equal (so `fmax(0.0, -0.0)` is -0.0, as glibc).

## Accuracy

Measured by `math-oracle-check.py` on the 3,821,267-record fixture set (the
Forth-built production output is first required to equal host GCC -O0 and -O2
builds of the same sources bit for bit). "True" errors come from Python
Decimal at 60+ digits (pi from Machin's formula; trigonometric arguments are
reduced directly at 460 digits) for every record whose result differs from
glibc and for every 16th other record.

| Function | Records | Differ from glibc | Max distance from glibc (ulp) | Truth-checked | Max seed error (ulp) | Max glibc error (ulp) |
|---|---:|---:|---:|---:|---:|---:|
| `acos` | 72345 | 21 | 1 | 4148 | 0.5000 | 0.518 |
| `asin` | 72345 | 48 | 1 | 4161 | 0.5000 | 0.508 |
| `atan` | 62042 | 26 | 1 | 7023 | 0.5000 | 0.504 |
| `atan2` | 63764 | 31 | 1 | 872 | 0.5000 | 0.510 |
| `cbrt` | 41040 | 20160 | 3 | 21404 | 0.5000 | 2.825 |
| `cos` | 93285 | 103 | 8 | 5925 | 0.5000 | 7.955 |
| `cosh` | 92408 | 6903 | 1 | 11840 | 0.5002 | 1.103 |
| `exp` | 68071 | 34 | 1 | 3834 | 0.5000 | 0.502 |
| `exp2` | 70667 | 44 | 1 | 4542 | 0.5000 | 0.504 |
| `expm1` | 87609 | 4647 | 1 | 9637 | 0.5004 | 0.803 |
| `hypot` | 95254 | 201 | 1 | 6117 | 0.5000 | 0.738 |
| `log` | 60541 | 26 | 1 | 3576 | 0.5000 | 0.506 |
| `log10` | 59075 | 7698 | 2 | 10168 | 0.5000 | 1.548 |
| `log1p` | 98644 | 4039 | 1 | 9978 | 0.5000 | 0.756 |
| `log2` | 60541 | 66 | 1 | 3335 | 0.5000 | 0.533 |
| `pow` | 197001 | 130 | 1 | 11677 | 0.5000 | 0.506 |
| `sin` | 93285 | 77 | 1 | 5905 | 0.5000 | 0.513 |
| `sinh` | 92408 | 14457 | 2 | 18909 | 0.5001 | 1.710 |
| `tan` | 93285 | 183 | 14 | 5998 | 0.5000 | 14.361 |
| `tanh` | 92408 | 17751 | 2 | 22463 | 0.5004 | 2.015 |

The 2,155,249 exact-function records (1,097,042 of them `sqrt`: random bit
patterns over every exponent, subnormals, exact squares, and squares of
rounding midpoints) differ from glibc in no bit and no errno. Every errno of
the 3,821,267 records equals glibc's. NaN results may differ from glibc in
sign or payload only (for example glibc returns +NaN for `acos(2)`, the seed
the AMD64 default -NaN).

glibc's 8 and 14 ulp `cos`/`tan` errors are arguments next to
5319372648451847 * 2^717, within about 2^-60 of a multiple of pi/2; the seed
Payne-Hanek reduction and the independent 460-digit Decimal reduction agree
there. The seed maxima above 0.5 (`expm1`, `sinh`, `cosh`, `tanh`, at most
0.5005) come from the ~2^-64 relative error of their double-double paths.

Exact functions (`sqrt` and the rounding/remainder/bit operations) match both
the Fraction/integer references in `math-check.py` and glibc on every record.
Exact mathematical cases return exactly: `pow(2, 10) = 1024`, `pow(10, 15)`,
`pow(3, 20)`, `pow(k*k, 0.5) = k`, all `exp2(k)`, `log2(2^k) = k`,
`log10(10^n) = n` (n = 0..22), `cbrt(k^3) = k`, `hypot(3, 4) = 5` (and the
other listed Pythagorean triples at all scales), `exp(0) = 1`, `log(1) = +0`,
`sin(±0) = ±0`, `acos(1) = +0`, `atan2` signed zeros. glibc itself is not
exact for some of these (`cbrt(27)` is 3.0000000000000004 there).

The error bound is measured, not proved: the analysis above (double-double
evaluation, bounded series tails, exact reductions) motivates it, and the
oracle check enforces |error| < 0.501 ulp on every record it evaluates. A
correctly rounded result is not guaranteed; in rare hard cases the result
is the other neighbour of the true value, still within the bound. The worst
`pow` record, `pow(1 - 2^-53, 1.5)`, is 2^-107 above a rounding midpoint and
rounds down.

## GCC consumer

GCC 4.0.4 `genautomata.c:6714` evaluates
`exp(log(max_occ_cycle_num - min_occ_cycle_num + 1.0) / automata_num)` and
needs `-lm`; the call sits in `units_to_automata_heuristic_distr`, which the
supported command line never reaches (`split_argument` stays 0, the `-split`
option is not implemented, so `automata_num` is 0 and `create_automata` skips
the heuristic). Linking the unchanged translation unit is the integration
requirement; numerical behaviour is established by the fixture above. For
the composed root `exp(log(n)/k)` over n = 1..2999, k = 1..11 (32,989 cases)
the seed and glibc results differ in 30 cases and fall on different sides of
a nearby integer in 1 (the previous exp/log runtime had 39 such near-integer
side disagreements in its 2,136 composed records). `exp(log(9)/2)` is 3.0000000000000004 in both. Nothing is
forced to an integer and GCC is not modified to hide differences. libiberty `floatformat.c` includes `math.h`
and uses `ldexp`, `frexp`, `isnan`, `INFINITY` and `NAN`; these resolve from
libc without `-lm`.

## Tests and provenance

- `python3 tests/gcc/math-constants.py` - re-derives the tables and `M_*`.
- `python3 tests/gcc/math-link-check.py` - archive mechanics, libc-resident
  `fpclass.o`, `-nostdlib`, ordering and failure modes.
- `python3 tests/gcc/math-check.py` - Forth-only: builds
  `tests/gcc/math-fixture.c` with `-lm`, feeds the deterministic records of
  `tests/gcc/math_records.py`, and checks exact functions against Fraction/
  integer references and approximate functions against the special-value,
  exact-case and errno contract. No host compiler, linker or libm.
- `python3 tests/gcc/math-oracle-check.py --production-output DIR` - host
  oracles only (host GCC builds, glibc, Decimal), as described above.

Host GCC, glibc and Decimal are oracles only; no production byte depends on
them. References consulted: NIST DLMF 4.2.19 and 4.6.4 (2026-10-03), C99
Annex F, IEEE 754-2008; Cody-Waite and Payne-Hanek reduction, Dekker/Knuth
error-free transformations and Veltkamp splitting are used as published
algorithms with original code and project-derived constants.
