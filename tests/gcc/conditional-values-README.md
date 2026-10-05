# Conditional expression typing

This source-driven component repair addresses unchanged GCC 4.0.4
`ggc-common.c` (MIN of double and integer70) and `tree-ssa-loop-im.c`
(`condition ? (void *)0 : record_pointer` followed by member access).
It changes compiler semantics, never those input sources or preprocessing.

## Contract

- Evaluate the condition once and only the selected arm. Convert that arm to
  the common scalar type after both types are known. Float/integer uses float;
  double with either uses double; integer usual conversions retain LP64
  signedness and width. Nested conditionals round at each common type.
- Preserve compatible pointer types, array/record/function descriptors and
  unioned qualifier metadata. Recognized null constants select the other
  pointer type in both orders. Ordinary void*/object-pointer combinations
  have void* type, even if the runtime void* happens to be zero.
- Recognize numeric/character zero literals, grouping, and chains of integral
  zero casts, optionally ending in unqualified void*. Never infer constancy from a runtime
  zero, comma expression, pointer cast to integer, or selected runtime arm.
- Keep the existing aggregate copy join, record compatibility checks, qualified
  array rejection, native/TinyCC defaults and unsupported floating-record ABI.
  General scalar const-write enforcement is an existing unsupported feature.

This is not full C conditional conformance. General zero integer constant
expressions (e.g. 1-1), enum zeros and unary-computed zeros retain conservative
rejection in pointer conditionals. Host-valid negative fixtures establish the
1-1 and qualified-array boundaries. The independent static constant evaluator
is unchanged. The pre-existing permissive assignment grammar for the third
operand is unchanged as well.

## Focused proof

Run serially under a whole-group timeout, with unique output and private /tmp
and /dev when sharing an executor:

    python3 tests/gcc/conditional-values-check.py --work /unique/output

The runner builds host C90 pedantic O0/O2 oracles, Forth producer/host caller
and host producer/Forth caller at both optimization levels, and a Forth-only
separate-object executable. Tests cover both arm orders, nested binary32
rounding, signed/unsigned32/64 conversions, signed-zero and quiet-NaN payloads,
unused invalid dereferences, side effects, pointer descriptors, record copies
and output-preserving rejection. Previous mixed-floating rejection witnesses
in binary32-values-check.py and review-floating-check.py are now positive
compile checks; the execution proof lives here.

The isolated baseline is source identity
`a09c9cd3526f061c3cc1255030378f426532db17b985184e08326922903815d8`.
Broader ranked arrays and adjusted function parameters are separate reviewed
components, not silently included in this baseline.

## Original-unit confirmation

At compiler identity
`ef39c1e504be6ee1abeac880fa61a9cf0a1ea2cd2592509dd893d14500f23e5d`,
both complete unchanged raw units compile using their exact historical
a535 configure/include context: ggc-common.o is 29,552 bytes and
tree-ssa-loop-im.o is 116,728 bytes. The replay verifies all 114/162 frozen
original/config/toolchain inputs and all candidate compiler inputs before and
after, emits independent ELF inspection, and records clean whole-group exits.
These are two historical-config object proofs, not a new configure epoch,
integration result, completed GCC executable, or full bootstrap.

## Qualified cast provenance correction

The first conditional checkpoint incorrectly treated `(const void *)0` as a
null pointer constant. Such qualified-pointee void pointers keep their void
pointer type; they must not adopt a record, array, or function pointer's type
through a conditional. The corrected cast hook receives the target's saved
qualification flag from the return stack so a nested operand cast cannot
replace it. Qualified integer zero casts remain recognized, including
`(void *)(const int)0` with an unqualified outer target.

The existing flattened qualifier metadata does not distinguish a qualifier on
the pointer from a qualifier on its pointee. Top-level-qualified void-pointer
zero casts such as `(void *const)0` and a const pointer typedef therefore retain
a conservative, host-valid rejection boundary when record/array/function
pointer provenance would be required. Ordinary qualified void-pointer/object-
pointer combinations remain usable as void pointers. This correction does
not add general scalar const enforcement or general integer constant folding.

`conditional-qualified-null-check.py` separately checks strict host C90 O0/O2
validity, both conditional orders, nested casts, typedef qualifications,
accepted integral-qualification controls, and output preservation. The earlier
failed checkpoint and independent review evidence remain historical records.
