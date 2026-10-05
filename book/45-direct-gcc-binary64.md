# 45. Binary32 and binary64 scalar values

The first floating operation needed by the unchanged GCC source is small:
`htab_collisions` converts two unsigned counters to `double`, divides them,
and returns the result. Implementing that function requires a real floating
value model. Giving `double` an eight-byte size alone would send integer bits
to the wrong register and produce the wrong arithmetic.

This layer implements binary32 and binary64 values in the existing System V mode. A
`double` keeps its exact 64-bit payload in the expression register RDI and
in the compiler's existing eight-byte stack/frame cells. Ordinary loads,
stores, argument-independent temporaries and nonlocal-return snapshots can
therefore preserve it without a separate floating evaluation stack. SSE2
operations briefly move operands into XMM0/XMM1 and move the result back.
A function result crosses the ABI boundary in XMM0.

The next measured consumer is the unchanged GCC 4.0.4 `gcc/ggc-page.c`.
`ggc_collect` converts an unsigned allocation counter to `float`, computes a
percentage threshold, and compares it with another counter. Its `float`
objects occupy four bytes, align to four, and carry raw binary32 payloads in
the low half of the expression cell. The storage hook selects unsigned
four-byte transport without changing the expression's C type. Neighboring
array elements and record fields are never read or overwritten as doubles.

## Type-aware conversion

A conversion needs both the source and destination types. Converting an
integer to binary64 performs a numeric conversion; assigning one double to
another preserves its payload. The source/destination hooks now serve casts,
assignments, local initializers and returns. Their defaults retain the prior
integer encoders, including the native/TinyCC route's machine bytes.

Signed integers use `cvtsi2ss` or `cvtsi2sd` after normalization to their declared width.
The high half of unsigned 64-bit values is halved with a sticky low bit, converted, then
doubled exactly, avoiding a signed interpretation or double rounding under
the default nearest-even mode. Conversion back truncates toward zero with
`cvttss2si` or `cvttsd2si`; unsigned 64-bit values use a split at 2^63. Finite conversions whose truncated
result is representable are supported. The implementation does not add a
portable result for C's out-of-range or nonfinite integer conversions.

Binary32 integer conversions round directly to 24-bit precision; they never
pass through binary64, which could double-round a large integer. The unsigned
high-half algorithm likewise converts the sticky half at its final precision.
`cvtss2sd` widens exactly and `cvtsd2ss` narrows with one binary32 rounding.
For binary32-to-unsigned64, exact widening permits reuse of the binary64
split. Arithmetic and narrowing assume the normal nearest-even SSE environment
with gradual underflow; changing the floating environment is not provided.

## Arithmetic, truth and storage

Addition, subtraction, multiplication and division use scalar SSE2. Relational
and equality comparisons account for unordered values: NaN never compares
equal or ordered, and `!=` remains true. Truth testing ignores the sign bit
when recognizing zero, so both signed zeros are false and NaNs are true.
Unary minus flips the sign bit without changing the remaining payload.
Loads/stores and same-type assignment preserve payload bits, including
signed zeros and quiet NaNs. An integer with float uses float; either scalar floating type with double
uses double. Binary32 arithmetic uses ADDSS/SUBSS/MULSS/DIVSS, so every
operation rounds to binary32. Compound assignments compute at their common
type and then convert once to their destination. This is genuine single
precision, not binary64 computation with a smaller store.

The existing [qualifier subset](A6-c-subset.md) is unchanged: qualifier spelling
is accepted without general const-write enforcement. Scalar float lvalues
retain their address, width and descriptor metadata; the volatile-memory
probes observe ordinary four-byte accesses, not an expanded optimizer or
synchronization contract.

The caller reads XMM0 after restoring its persistent stack state. That
restoration uses general-purpose registers only, preserving the result.
The callee writes XMM0 before the standard callee-save/frame epilogue.
Direct and indirect calls use the same result hook. No XMM register remains
a live expression temporary across another call.

## Checked boundaries

Binary32/binary64 values, returns, named parameters and outgoing scalar arguments are
supported. Unnamed and unspecified-prototype float arguments promote to double. [Chapter 48](48-direct-gcc-aggregate-abi.md) owns the shared call
plan and [chapter 42](42-direct-gcc-varargs.md) supplies variadic retrieval.
K&R definitions with declared float parameters reject with232: their incoming
ABI values are promoted doubles, so accepting them requires a separate entry
conversion. Ordinary unspecified-prototype outgoing calls still promote float
to double correctly. Long-double computation and static floating initializers
remain rejected.
Floating increment/decrement remains rejected. Conditional arithmetic arms use
the common type and convert only the selected value: integer with float gives
float, and either type with double gives double. Separate conversion tails
preserve branch laziness even when one conversion changes the payload format.
Same-type float and double arms preserve the selected payload. Floating
members are valid scalar lvalues, but their enclosing record's by-value ABI
remains outside the INTEGER/MEMORY aggregate subset. Integer-only operators, array subscripts and switch scrutinees
reject floating operands. Floating type declarations, pointers and `sizeof`
remain available without executing an unsupported operation.

Floating tokens are scanned as complete preprocessing numbers so malformed
suffixes or hexadecimal floating forms cannot be split into accepted integer
fragments. [Ch 46](46-direct-gcc-float-literals.md) provides the source-only,
bounded decimal decoder and its exact nearest-even rounding contract through
`cc-f64-parse-fwd`. The decoder performs no host floating evaluation. Binary32 `f`/`F` suffixes
remain rejected with248: parsing as binary64 then narrowing would incorrectly
double-round certain decimal literals. Explicitly converting an unsuffixed
double literal to float has C's specified two-type semantics.

The independent `tests/gcc/review-floating-check.py` gate compares Forth-built
objects with host ABI oracles at O0 and O2. It exercises conversion boundaries,
zeros/subnormals/nonfinite values, comparisons/truth, memory and nested direct
and indirect XMM0 returns. Its original-source check compiles the unchanged
pinned `libiberty/hashtab.c` translation unit. Host tools supply the independent
oracle; the production compiler and object bytes come from Forth source.

The `tests/gcc/binary32-values-check.py` gate compares deterministic bit vectors
and randomized operands against independent host O0/O2 compilation. It covers
integer widths, direct signed/unsigned64 rounding, binary32/binary64 conversion,
subnormals, signed zeros, quiet NaNs, mixed arithmetic, assignment, qualified
memory, four-byte arrays/fields, and both directions of the scalar ABI. A
Forth-only separate-object executable checks calls, stack overflow arguments,
and variadics; negative cases check output preservation. These are component
proofs, not a linked GCC compiler or a same-epoch configuration bootstrap.

## Canonical source

```forth file=127-cc-binary64.fth
\ 127-cc-binary64.fth — binary32/binary64 scalar System V values.
\ Raw payloads occupy RDI/RCX and eight-byte expression/frame slots.
\ Binary32 storage is four bytes; arithmetic rounds at its own precision.
\ XMM0/XMM1 are transient arithmetic registers; XMM0 carries ABI results.
\ Long double and static floating initializers remain checked boundaries.
\ No native/TinyCC mode is changed.

: cc-f64-type? ( type -- flag )
  dup ty-ptr 0= swap ty-base ty-double = and cc-target-sysv @ and ;
: cc-f32-type? ( type -- flag )
  dup ty-ptr 0= swap ty-base ty-float = and cc-target-sysv @ and ;
: cc-fp-type? ( type -- flag ) dup cc-f32-type? swap cc-f64-type? or ;
: cc-fp-scalar-check ( type -- )
  dup cc-fp-type? if, drop else, cc-sysv-check-scalar-default then, ;
' cc-fp-scalar-check is cc-sysv-check-scalar

\ The integer storage emitter sees binary32 as an unsigned four-byte
\ payload. This hook changes no expression type and does no conversion.
: cc-fp-storage-type ( type -- storage-type )
  cc-sysv-value-type-check
  dup cc-f32-type? if, drop ty-uint [lit] 0 ty-make then, ;
' cc-fp-storage-type is cc-emit-type-check-fwd

: cc-f64-parse-unavailable ( address length -- bits ) 2drop [lit] 248 cc-die ;
defer cc-f64-parse-fwd
' cc-f64-parse-unavailable is cc-f64-parse-fwd

\ Scan a complete pp-number, retaining its spelling. Integer tokens return
\ to the original lexer unchanged; malformed floating forms reach128's
\ checked grammar instead of being split into plausible integer tokens.
variable cc-f64-scan-start
variable cc-f64-scan-prev
variable cc-f64-scan-seen
variable cc-f64-scan-hex
: cc-f64-number-char? ( char -- flag )
  dup ident-cont? over [char] . = or if, drop true exit, then,
  dup [char] + = swap [char] - = or
  cc-f64-scan-prev @ dup [char] e = over [char] E = or
  over [char] p = or swap [char] P = or and ;
: cc-f64-lex ( -- handled? )
  cc-target-sysv @ 0= cc-eof? or if, [lit] 0 exit, then,
  cc-peek-char digit? cc-peek-char-2 digit? swap [char] . = and or
  0= if, [lit] 0 exit, then,
  cc-src-pos @ cc-f64-scan-start !
  cc-peek-char-2 dup [char] x = swap [char] X = or
  swap [char] 0 = and cc-f64-scan-hex !
  [lit] 0 cc-f64-scan-prev ! [lit] 0 cc-f64-scan-seen !
  begin, cc-eof? 0= cc-peek-char cc-f64-number-char? and while,
    cc-next-char
    dup [char] . = if, true cc-f64-scan-seen ! then,
    cc-f64-scan-hex @ if,
      dup [char] p = over [char] P = or
    else, dup [char] e = over [char] E = or then,
    if, true cc-f64-scan-seen ! then,
    cc-f64-scan-prev !
  repeat,
  cc-f64-scan-seen @ 0= if,
    cc-f64-scan-start @ cc-src-pos ! [lit] 0 exit,
  then,
  cc-src-buf cc-f64-scan-start @ + tok-str-addr !
  cc-src-pos @ cc-f64-scan-start @ - tok-str-len !
  tk-float tok-kind ! [lit] 0 tok-num ! true ;
' cc-f64-lex is cc-sysv-lex-number-fwd
: cc-f64-literal ( -- handled? )
  cc-target-sysv @ tok-kind @ tk-float = and 0= if, [lit] 0 exit, then,
  tok-str-addr @ tok-str-len @ cc-f64-parse-fwd cc-emit-movabs-rdi-imm64
  ty-double [lit] 0 ty-make [lit] 0 cc-mark-typed-value true ;
' cc-f64-literal is cc-value-literal-fwd

: cc-fp-xmm0-from-rdi
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 110 cc-emit-byte [lit] 199 cc-emit-byte ;
: cc-fp-xmm1-from-rcx
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 110 cc-emit-byte [lit] 201 cc-emit-byte ;
: cc-fp-xmm1-from-rax
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 110 cc-emit-byte [lit] 200 cc-emit-byte ;
: cc-fp-rdi-from-xmm0
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 126 cc-emit-byte [lit] 199 cc-emit-byte ;
: cc-fp-prefix ( type -- )
  cc-f32-type? if, [lit] 243 else, [lit] 242 then, cc-emit-byte ;
: cc-fp-signed-from-rdi ( type -- )
  cc-fp-prefix [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 42 cc-emit-byte [lit] 199 cc-emit-byte ;
: cc-fp-truncate-rdi ( type -- )
  cc-fp-prefix [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 44 cc-emit-byte [lit] 248 cc-emit-byte ;
: cc-fp-sse ( opcode type -- )
  cc-fp-prefix [lit] 15 cc-emit-byte cc-emit-byte [lit] 193 cc-emit-byte ;
: cc-fp-jcc ( opcode -- patch )
  [lit] 15 cc-emit-byte cc-emit-byte cc-out-pos @ [lit] 0 cc-emit-4le ;
: cc-fp-flip-sign ( type -- )
  [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte [lit] 186 cc-emit-byte
  [lit] 255 cc-emit-byte
  cc-f32-type? if, [lit] 31 else, [lit] 63 then, cc-emit-byte ;
: cc-fp-u64-to-value ( type -- )
  >r
  cc-emit-test-rdi [lit] 137 cc-fp-jcc
  r> swap >r >r
  \ High unsigned half: round the sticky half, then double exactly.
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 209 cc-emit-byte [lit] 232 cc-emit-byte
  [lit] 131 cc-emit-byte [lit] 231 cc-emit-byte [lit] 1 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 9 cc-emit-byte [lit] 248 cc-emit-byte
  r@ cc-fp-prefix [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 42 cc-emit-byte [lit] 192 cc-emit-byte
  r@ cc-fp-prefix [lit] 15 cc-emit-byte
  [lit] 88 cc-emit-byte [lit] 192 cc-emit-byte
  r> cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  cc-fp-signed-from-rdi r> cc-patch-rel32-to-here ;
: cc-fp-double-to-u64
  [lit] 72 cc-emit-byte [lit] 184 cc-emit-byte
  [lit] 4890909195324358656 cc-emit-8le cc-fp-xmm1-from-rax
  [lit] 102 cc-emit-byte [lit] 15 cc-emit-byte
  [lit] 46 cc-emit-byte [lit] 193 cc-emit-byte
  [lit] 130 cc-fp-jcc >r
  ty-double [lit] 0 ty-make dup >r
  [lit] 92 swap cc-fp-sse r@ cc-fp-truncate-rdi r> cc-fp-flip-sign
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  ty-double [lit] 0 ty-make cc-fp-truncate-rdi r> cc-patch-rel32-to-here ;

: cc-fp-width-convert ( source destination -- )
  2dup = if, 2drop exit, then,
  swap cc-fp-prefix [lit] 15 cc-emit-byte [lit] 90 cc-emit-byte
  [lit] 192 cc-emit-byte drop ;
: cc-fp-convert ( source destination -- )
  2dup cc-fp-type? swap cc-fp-type? or 0= if,
    cc-emit-convert-value-default exit,
  then,
  dup cc-fp-type? if,
    over cc-fp-type? if,
      cc-fp-xmm0-from-rdi 2dup cc-fp-width-convert
      cc-fp-rdi-from-xmm0 nip cc-emit-convert-rdi exit,
    then,
    over cc-const-integer? 0= if, [lit] 232 cc-die then,
    over cc-emit-convert-rdi
    over ty-unsigned? [lit] 2 cc-npick ty-size [lit] 8 = and if,
      dup cc-fp-u64-to-value
    else, dup cc-fp-signed-from-rdi then,
    cc-fp-rdi-from-xmm0 nip cc-emit-convert-rdi
  else,
    dup ty-base ty-void = over ty-ptr 0= and if, 2drop exit, then,
    dup cc-const-integer? 0= if, [lit] 232 cc-die then,
    cc-fp-xmm0-from-rdi
    dup ty-unsigned? over ty-size [lit] 8 = and if,
      swap ty-double [lit] 0 ty-make cc-fp-width-convert
      cc-fp-double-to-u64
    else, swap cc-fp-truncate-rdi then,
    cc-emit-convert-rdi
  then, ;
' cc-fp-convert is cc-emit-convert-value
: cc-fp-convert-right ( source destination -- )
  2dup cc-fp-type? swap cc-fp-type? or 0= if,
    cc-emit-convert-right-default exit,
  then,
  [lit] 72 cc-emit-byte [lit] 135 cc-emit-byte [lit] 207 cc-emit-byte
  cc-fp-convert
  [lit] 72 cc-emit-byte [lit] 135 cc-emit-byte [lit] 207 cc-emit-byte ;
' cc-fp-convert-right is cc-emit-convert-right
: cc-fp-initialize ( source destination -- )
  2dup cc-fp-type? swap cc-fp-type? or if, cc-fp-convert else, 2drop then, ;
' cc-fp-initialize is cc-value-init-fwd
: cc-fp-return
  cc-native-return-type @ cc-fp-type? if,
    cc-fp-xmm0-from-rdi
  else, cc-emit-mov-rax-rdi then, ;
' cc-fp-return is cc-value-return-fwd
: cc-fp-result ( type -- )
  dup cc-fp-type? if, cc-fp-rdi-from-xmm0 then, cc-emit-convert-rdi ;
' cc-fp-result is cc-sysv-result-value-fwd

: cc-fp-common-type ( left right -- type )
  2dup cc-fp-type? swap cc-fp-type? or if,
    over cc-fp-type? over cc-fp-type? and 0= if,
      over cc-fp-type? if, dup else, over then,
      cc-const-integer? 0= if, [lit] 232 cc-die then,
    then,
    cc-f64-type? swap cc-f64-type? or if, ty-double else, ty-float then,
    [lit] 0 ty-make
  else, cc-expr-common-type-default then, ;
' cc-fp-common-type is cc-expr-common-type
: cc-fp-comparison ( op -- )
  cc-expr-common @ cc-f64-type? if, [lit] 102 cc-emit-byte then, [lit] 15 cc-emit-byte
  [lit] 46 cc-emit-byte [lit] 193 cc-emit-byte
  dup [char] > = if, drop [lit] 151 else,
  dup pt-ge = if, drop [lit] 147 else,
  dup [char] < = if, drop [lit] 146 else,
  dup pt-le = if, drop [lit] 150 else,
  dup pt-eq-eq = if, drop [lit] 148 else,
  pt-bang-eq = if, [lit] 149 else, [lit] 232 cc-die then,
  then, then, then, then, then,
  dup [lit] 15 cc-emit-byte cc-emit-byte [lit] 192 cc-emit-byte
  dup [lit] 146 = over [lit] 150 = or over [lit] 148 = or if,
    [lit] 15 cc-emit-byte [lit] 155 cc-emit-byte [lit] 194 cc-emit-byte
    [lit] 32 cc-emit-byte [lit] 208 cc-emit-byte
  then,
  [lit] 149 = if,
    [lit] 15 cc-emit-byte [lit] 154 cc-emit-byte [lit] 194 cc-emit-byte
    [lit] 8 cc-emit-byte [lit] 208 cc-emit-byte
  then,
  [lit] 15 cc-emit-byte [lit] 182 cc-emit-byte [lit] 248 cc-emit-byte ;
: cc-fp-binop
  cc-expr-left-type @ cc-fp-type? cc-expr-right-type @ cc-fp-type? or 0= if,
    cc-native-binop-emit-default exit,
  then,
  cc-fp-xmm0-from-rdi cc-fp-xmm1-from-rcx
  cc-expr-op-row @ bo-op + @
  dup [char] + = if, drop [lit] 88 else,
  dup [char] - = if, drop [lit] 92 else,
  dup [char] * = if, drop [lit] 89 else,
  dup [char] / = if, drop [lit] 94 else,
    cc-fp-comparison exit,
  then, then, then, then,
  cc-expr-common @ cc-fp-sse cc-fp-rdi-from-xmm0 ;
' cc-fp-binop is cc-native-binop-emit

: cc-fp-test
  cc-last-expr-type @ cc-fp-type? if,
    \ Clear only the sign in a scratch value; both signed zeros are false.
    cc-last-expr-type @ cc-f64-type? if, [lit] 72 cc-emit-byte then,
    [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
    cc-last-expr-type @ cc-f64-type? if, [lit] 72 cc-emit-byte then,
    [lit] 209 cc-emit-byte [lit] 224 cc-emit-byte
    cc-last-expr-type @ cc-f64-type? if, [lit] 72 cc-emit-byte then,
    [lit] 133 cc-emit-byte [lit] 192 cc-emit-byte
  else, cc-emit-test-rdi then, ;
' cc-fp-test is cc-value-test-fwd
: cc-fp-not
  cc-last-expr-type @ cc-fp-type? if,
    cc-fp-test
    [lit] 15 cc-emit-byte [lit] 148 cc-emit-byte [lit] 192 cc-emit-byte
    [lit] 15 cc-emit-byte [lit] 182 cc-emit-byte [lit] 248 cc-emit-byte
  else, cc-emit-not-zero-flag then, ;
' cc-fp-not is cc-value-not-fwd
: cc-fp-negate
  cc-last-expr-type @ cc-fp-type? if, cc-last-expr-type @ cc-fp-flip-sign else, cc-emit-neg-rdi then, ;
' cc-fp-negate is cc-value-negate-fwd
: cc-fp-complement
  cc-last-expr-type @ cc-fp-type? if, [lit] 232 cc-die then, cc-emit-not-rdi ;
' cc-fp-complement is cc-value-complement-fwd
\ Conditional arms use cc-fp-common-type and selected-arm conversions in100.
: cc-fp-ternary ;
' cc-fp-ternary is cc-value-ternary-fwd

: cc-fp-integer-use ( type -- )
  cc-fp-type? if, [lit] 232 cc-die then, ;
' cc-fp-integer-use is cc-value-integer-use-fwd
' cc-fp-integer-use is cc-value-static-init-fwd
```

## Exercises

1. Explain why an eight-byte storage size does not determine a return register
2. Add an integer-conversion edge near2^53 and predict the nearest-even result
3. Trace a double result through a nested call and persistent stack restoration
4. Design mixed GP/SSE argument allocation with independent register counters

## Takeaways

- Type-aware conversion distinguishes numeric conversion from payload transport
- Binary32/binary64 temporaries reuse the existing persistent evaluation storage
- Unsupported ABI classes and operations fail before publishing an artifact
