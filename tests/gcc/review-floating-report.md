# Independent scalar binary64 review

This is the historical binary64-stage report, retained alongside its original
results. Later named/variadic argument and binary32 stages supersede several
boundaries listed below. The conditional-values stage also supersedes both
mixed-ternary rejections; the current runner accepts those forms and the
[conditional gate](conditional-values-README.md) checks their execution.

The measured scalar extension passes its independent host interoperability and
exact-literal oracles. The unchanged full GCC 4.0.4 `libiberty/hashtab.c` compiles
with the Forth compiler, and its original `htab_collisions` returns the same
binary64 bits as an independent host calculation. This proves the previously
blocked function and translation unit, not a complete GCC bootstrap.

## Reproduction and results

Run from the repository root:

```
python3 tests/gcc/review-floating-check.py --report tests/gcc/review-floating-results.json
python3 tests/gcc/review-floating-literals.py --report tests/gcc/review-floating-literal-results.json
```

The first command requires the pinned GCC tree in
`build-out/direct-gcc-inputs/gcc-source`; `--source-root` selects another copy
with the same verified input hashes. Host C compilation and linking are used
only for independent test oracles. The reviewed target objects are always
produced by Forth. Neither runner changes compiler/book source or Git state.

- 2,521 runtime checks at host `-O0`, repeated at `-O2`
- 22 explicit unsupported-value/operator/ABI rejection cases
- 144 original `htab_collisions` counter pairs at `-O0` and again at `-O2`
- 124 literal decoder results checked against exact Python integer rationals
- Those 124 positive literals plus seven source unary signs compiled through
  the actual lexer/parser and checked through XMM0 at both host optimization levels
- 20 decoder diagnostic cases and 12 source-level diagnostic cases
- Compiler inputs unchanged during each recorded run; exact hashes are in the
  two result files

The unchanged source SHA256 is
`64dfaa8263d2b9c1737cb442824e0437b001dbafef92fc985c4431b5700ad802`.
The unchanged `include/hashtab.h` SHA256 is
`4ea28b4fd9a06f5ac81e5f0f10e15dbafd39b262bfa1ef85618a7a2b2c1a859c`.
The host unit oracle supplies the otherwise unused seed `stderr` accessor and
`xcalloc`; it exercises the original collision query only. The actual GCC
configured Makefile/`genmodes` continuation is a separate driver proof.

## What the runtime review establishes

The test fixture accepts floating data through `double *` and returns through
XMM0, keeping the current argument ABI restriction explicit. Host calls into
Forth functions check all supported signed and unsigned integer widths in both
conversion directions. Boundaries include the integer precision transition at
2^53, both halves of uint64, and unsigned values that a signed SSE conversion
would misinterpret. Floating-to-integer inputs are finite and their truncated
values are representable; there are no undefined out-of-range cast assertions.

Arithmetic and comparison checks cover positive/negative zero, normal values,
minimum/maximum subnormal values, minimum normal, maximum finite, infinities,
and quiet NaNs. NaN arithmetic results are compared by classification, while
loads, stores, unary sign, and call returns must preserve exact payload bits.
Local, initialized, global, array, and structure-field storage are checked.
Compound arithmetic, mixed integer/double arithmetic, truth tests, short-circuit
side effects, and loop conditions are checked. MXCSR control bits are preserved.

The reverse call direction uses host functions returning binary64 with only
integer/pointer arguments. Forth direct, indirect, nested, and seventh-GP-argument
call paths consume these results. This checks both sides of the XMM0 bridge
without implying support for floating arguments.

## Representation and ABI review

The raw 64-bit RDI/RCX and frame-slot representation is coherent: storage and
expression staging preserve bits, typed conversion knows both source and
destination, and SSE2 is entered only for arithmetic/conversion. The external
return boundary uses XMM0. New scratch registers are caller-saved.

The primary [AMD64 psABI source](https://gitlab.com/x86-psABIs/x86-64-ABI/-/raw/master/x86-64-ABI/low-level-sys-info.tex)
classifies `double` as SSE and assigns its result to XMM0. Future mixed calls
must allocate GP and vector registers independently; integer position is not
vector position. `%al` describes vector argument usage for variadic or
prototype-less calls, and must eventually match the new argument path. Zero
remains valid for the current integer/pointer-only calls. The current
rejection boundary avoids changing argument staging prematurely. MXCSR
control bits are callee-saved; status bits are caller-saved.

## Deliberate boundaries

The suite confirms rejection of floating parameters and fixed, indirect,
unprototyped, and variadic floating call arguments. Floating `va_arg` retains
its dedicated error 247. `float`/`long double` values, mixed integer/double
conditional arms, floating increment/decrement, static floating initializers,
invalid pointer conversions, remainder/bitwise/shifts, floating array indices,
and floating switch values reject with error 232.

Accepted literal syntax is positive unsuffixed decimal with a point or
exponent, including `.5`, `1.`, and `1e3`; the expression parser handles unary
signs. The decoder promises nearest-even rounding within 4096 token bytes,
768 significant mantissa digits (including trailing zeros), and absolute
explicit exponent at most 1,000,000. The independent oracle verifies exact
halfway cases with both parity choices, adjacent decimal neighbours, the
subnormal/normal transition, underflow, and overflow rejection. Hexadecimal
floating literals, suffixes, malformed spelling, and bounds violations fail
explicitly. No host floating parser produces target literals.

This is a bounded scalar checkpoint. It does not claim the floating argument
ABI, aggregate-by-value ABI, dynamic floating-environment conformance, NaN
payload selection for arithmetic, or full ISO C floating support. Default
native/TinyCC preservation gates are maintained and run by the implementation
owner separately from these floating-only oracles.

One prior review fixture was identified as obsolete: a test expecting
`int main(void){double d; return d;}` to reject now tests a supported conversion
and reads an uninitialized object. It must not serve as a floating rejection
fixture for this checkpoint; the implementation owner was notified.
