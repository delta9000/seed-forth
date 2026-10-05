# Measured binary64 exp and log

Status: original source implementation prepared and provisionally executed
in an isolated workspace. Forth compilation, linkage and execution passed
with the frozen, separately unreviewed binary64-argument compiler candidate.
Host/reference verification is a separate check. Independent math source and
120-digit Decimal boundary review passed; independent compiler acceptance
and the unchanged full generator integration gate remain separate. This is
not an accepted main-tree production implementation.

The measured source consumer is unmodified GCC 4.0.4 `gcc/genautomata.c:6714`:
`exp(log(max_occ_cycle_num - min_occ_cycle_num + 1.0) / automata_num)`.
This source call requires the genuine declarations and implementations when
compiling/linking the unchanged whole translation unit with the direct Forth
route. It is not executed by the supported normal command-line path:

- `initiate_automaton_gen` sets `split_argument = 0` at line 9745
- The `-split` option terminates with "not implemented yet" at line 9768;
  its proposed assignment is only a comment at line 9769
- `generate` assigns `automata_num = split_argument` at line 9526 (and caps
  it by the nonnegative number of units at 9527-9528)
- `create_automata` calls `units_to_automata_heuristic_distr` only when
  `automata_num != 0` at lines 6865-6867; that heuristic calls the estimator

A search of this pinned source finds no other live assignment to
`split_argument`. Thus the heuristic and its estimator are unreachable on
the supported normal CLI, including default i386 generation. Matching full
generator output is an additional source/compiler/link integration gate;
it is not numerical execution coverage for exp/log. Numerical evidence
comes from the dedicated runtime and composed-expression fixtures and the
independent Decimal checks. If this heuristic is enabled in a different
consumer or future source, values near its comparison boundaries can change
partitions and require an explicit assessment then. GCC source is unchanged.

The implementation is original project MIT code, not copied or adapted libm
source. Only `double exp(double)` and `double log(double)` are declared.
There are no long-double, x87, formatting, or other unused math helpers.
The machine contract is AMD64 LP64, IEEE binary64, nearest/ties-even rounding,
gradual underflow (no FTZ/DAZ), and independently rounded binary64 operations
(no contraction/excess precision). Union access interprets that representation.
No host library or generated code contributes production target bytes.

## Algorithms and offline mathematical reference

For log, extract x = m * 2^k and choose 0.75 <= m < 1.5. Subnormals are
normalized first by exact multiplication by 2^52. With z=(m-1)/(m+1),
|z|<=1/5. Evaluate 2*(z + z^3/3 + ... + z^33/33), then add k*ln(2)
using a high/low split. The omitted exact series tail is bounded by
2*(1/5)^35/(35*(1-1/25)), less than 2.1e-26.
The identity follows by subtracting the geometric-series integrals for
ln(1+z) and ln(1-z). NIST DLMF 4.6.4 records the same identity:
https://dlmf.nist.gov/4.6.E4 (consulted 2026-10-03).

For exp, choose integer k nearest x/ln(2), subtract k*ln(2) with a split,
then evaluate sum(r^j/j!, j=0..18) in Horner form and scale by 2^k.
For |r| <= ln(2)/2 + 2^-40, the exact Taylor tail is less than 2.1e-26;
the widened radius covers reduction rounding; this tail does not include
the rounding error of the evaluated polynomial.
The series follows from the exponential differential equation y'=y, y(0)=1;
NIST DLMF 4.2.19 records its entire power series:
https://dlmf.nist.gov/4.2.E19 (consulted 2026-10-03).
These formulas, bounds, constant derivation, and test sources are preserved
locally; reproducing the implementation does not require fetching web pages.
No third-party implementation license or source download is required.

The high ln(2) constant clears the low 21 fraction bits of rounded ln(2),
making its multiplication by the integer |k|<=1075 exact. The low constant
is the rounded residual from the real ln(2). The reciprocal and range limits
are independently rounded. Tests derive and verify the exact binary64 bits
using Python Decimal at two independent precisions. Decimal and host libm
are oracle tools only, never production-build inputs.

## Errors and limits

All ordinary successful calls preserve errno. NaNs return x+x (quieting a
signaling NaN according to the machine) and preserve errno; payload behavior
and floating-exception flags are not promised. log(+infinity)=+infinity;
log(+-0)=-infinity with ERANGE; negative inputs including -infinity yield
quiet NaN with EDOM. log(1)=+0. exp(+-0)=1, exp(+infinity)=+infinity,
and exp(-infinity)=+0; these preserve errno. Finite overflow gives +infinity
with ERANGE. Any subnormal or zero exp result for finite input sets ERANGE,
including exact subnormal results; this is the explicit bootstrap policy.

This is not a correctly rounded or complete ISO C libm and does not provide
fenv, alternate rounding modes, math_errhandling, or mathematical macros.
The numerical acceptance budget is relative error <= 2^-44 (about 5.69e-14)
for nonzero normal results, and absolute error <= two minimum subnormal units
for subnormal exp results. This is a deliberately loose validation budget,
not a claimed universally proven error bound. Zero/infinite/NaN behavior is
checked exactly. log(1) is exactly +0; log results for other positive binary64
inputs are normal. Exhaustive correct rounding is neither tested nor claimed.

The analytical part establishes exact normalization, exact high ln(2) products,
series tail bounds, and the range-limit brackets. The running-error model is
u=2^-53 per ordinary binary64 operation. log's reduced series has terms of
one sign and a ratio at most 1/25, so accumulation does not suffer cancellation;
for k=0, subtraction m-1 is exact by Sterbenz. Other k add a reduced logarithm
of magnitude below ln(1.5) to k*ln(2), limiting cancellation. exp's residual is
small and its polynomial remains positive. These observations motivate the
budget but do not substitute for a complete directed-rounding error proof.

The v1 host-only run at GCC -O0 and -O2 checked 14,349 log inputs across
every normal exponent encoding plus selected subnormals, 10,448 exp inputs
including every range-reduction boundary, and 2,106
integer/perfect-power/adjacent-integer composed inputs, plus 100,000
pseudorandom log and 100,000 pseudorandom exp inputs per optimization level.
A separate 100-digit Decimal oracle checked 2,316 cases per level, including
all 2,106 composed expressions; constants agree at 100 and 180 digits.
Maximum observed deviations from host libm were log 2 ulp, exp 1 ulp, and
composition 8 ulp. Both builds returned identical output bits and errno.
These measurements apply to the retained fixture and deterministic seeds;
they are not a guarantee over all binary64 values.

There were 39 fixture records whose comparison of the composed root with a
nearby integer differs from host libm (some inputs repeat). For example,
exp(log(9)/2) is exactly 3 here; that host produces 3.0000000000000004.
This is visible evidence of potential heuristic partition differences if
that heuristic is reached, not a waived test failure or evidence of complete
generator compatibility. The unchanged original genautomata output must be
compared after production FP-call integration, but its supported normal CLI
does not reach this math path and a match cannot validate numerical behavior.
Do not modify GCC, round its roots to integers, or hide numerical differences
to make that comparison pass.

The GCC expression is
valid here for positive representable cycle counts and positive automata
counts; this runtime cannot repair overflow in preceding GCC integer
subtraction or invalid source invariants.


## Reproduction and provenance boundary

- `python3 tests/gcc/math-oracle-check.py`: host GCC -O0/-O2 and Decimal checks
- `python3 tests/gcc/math-check.py`: Forth-only compilation/linkage/execution
- `python3 tests/gcc/math-oracle-check.py --production-output <results.txt>`:
  validates the production records and requires bit/errno equality with both
  host builds of this original implementation

Forth support still needs independent acceptance of the separate
binary64-argument compiler change. The provisional run uses frozen 126 and
131 files with SHA256 518a76ee39fae45f1f0b669d509e1bcfcf7e9203b257110ccc382f8a969acbc4
and 522fc596e9166a0e41273a3b57748d5a5afc39baba93b8feb6458379b4c585a7.
The math work does not change compiler files. The project baseline is identified by the lead's accepted c805 source
checkpoint; the exact compiler source identity is captured by the production
script rather than inferred from a dirty working-tree Git commit.

The v2 fixture extends v1 with each subnormal power of two and both adjacent
representable values (156 records), and 30 composed cases with cycle spans
1, 2, 3, 2^31-1 and 2^31 and automata counts through INT_MAX. Its source and
execution reports are distinct from the frozen v1 snapshot.

The v2 provisional Forth run emitted 27,089 records (14,505 log, 10,448 exp,
2,136 composed). All output bits and errno matched the host-built original
implementation at both optimization levels. It passed 2,344 Decimal checks
per level, with the same measured ulp maxima and 39 near-integer decision
disagreements. Production output SHA256 is
c8b6f17a005f6c8aa5056a3b75f66f6a3ee094ebf14c8cfd070443c112d59941.
