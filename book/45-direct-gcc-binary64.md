# 45. Binary64 values and scalar returns

The first floating operation needed by the unchanged GCC source is small:
`htab_collisions` converts two unsigned counters to `double`, divides them,
and returns the result. Implementing that function requires a real floating
value model. Giving `double` an eight-byte size alone would send integer bits
to the wrong register and produce the wrong arithmetic.

This stage implements binary64 values in the existing System V mode. A
`double` keeps its exact 64-bit payload in the expression register RDI and
in the compiler's existing eight-byte stack/frame cells. Ordinary loads,
stores, argument-independent temporaries and nonlocal-return snapshots can
therefore preserve it without a separate floating evaluation stack. SSE2
operations briefly move operands into XMM0/XMM1 and move the result back.
A function result crosses the ABI boundary in XMM0.

## Type-aware conversion

A conversion needs both the source and destination types. Converting an
integer to binary64 performs a numeric conversion; assigning one double to
another preserves its payload. The source/destination hooks now serve casts,
assignments, local initializers and returns. Their defaults retain the prior
integer encoders, including the native/TinyCC route's machine bytes.

Signed integers use `cvtsi2sd` after normalization to their declared width.
The high half of unsigned 64-bit values is halved with a sticky low bit, converted, then
doubled exactly, avoiding a signed interpretation or double rounding under
the default nearest-even mode. Conversion back truncates toward zero with
`cvttsd2si`; unsigned 64-bit values uses a split at 2^63. Finite conversions whose truncated
result is representable are supported. The implementation does not add a
portable result for C's out-of-range or nonfinite integer conversions.

## Arithmetic, truth and storage

Addition, subtraction, multiplication and division use scalar SSE2. Relational
and equality comparisons account for unordered values: NaN never compares
equal or ordered, and `!=` remains true. Truth testing ignores the sign bit
when recognizing zero, so both signed zeros are false and NaNs are true.
Unary minus flips the sign bit without changing the remaining payload.
Loads/stores and same-type assignment preserve payload bits, including
signed zeros and quiet NaNs. Integer/double arithmetic uses the double common
type; compound assignments convert the final value to their destination.

The caller reads XMM0 after restoring its persistent stack state. That
restoration uses general-purpose registers only, preserving the result.
The callee writes XMM0 before the standard callee-save/frame epilogue.
Direct and indirect calls use the same result hook. No XMM register remains
a live expression temporary across another call.

## Checked boundaries

This first stage accepts binary64 values and returns with integer/pointer
parameters. Floating call arguments, floating parameter definitions,
`va_arg(double)`, scalar float/long-double computation, and static floating
initializers remain rejected. Double increment/decrement and ternary arms
that mix double with another type are also rejected until their lowering is
implemented. Integer-only operators, array subscripts and switch scrutinees
reject floating operands. Floating type declarations, pointers and `sizeof`
remain available without executing an unsupported operation.

Floating tokens are scanned as complete preprocessing numbers so malformed
suffixes or hexadecimal floating forms cannot be split into accepted integer
fragments. [Ch 46](46-direct-gcc-float-literals.md) provides the source-only,
bounded decimal decoder and its exact nearest-even rounding contract through
`cc-f64-parse-fwd`. The decoder performs no host floating evaluation.

The independent `tests/gcc/review-floating-check.py` gate compares Forth-built
objects with host ABI oracles at O0 and O2. It exercises conversion boundaries,
zeros/subnormals/nonfinite values, comparisons/truth, memory and nested direct
and indirect XMM0 returns. Its original-source check compiles the unchanged
pinned `libiberty/hashtab.c` translation unit. Host tools supply the independent
oracle; the production compiler and object bytes come from Forth source.

## Canonical source

```forth file=127-cc-binary64.fth
\ 127-cc-binary64.fth — binary64 values in the existing System V target.
\ Double payloads occupy RDI/RCX and eight-byte expression/frame slots.
\ XMM0/XMM1 are transient arithmetic registers; XMM0 carries ABI results.
\ Float, long double, floating parameters and static initializers remain
\ checked boundaries in this first stage. No native/TinyCC mode is changed.

: cc-f64-type? ( type -- flag )
  dup ty-ptr 0= swap ty-base ty-double = and cc-target-sysv @ and ;
: cc-f64-scalar-check ( type -- )
  dup cc-f64-type? if, drop else, cc-sysv-check-scalar-default then, ;
' cc-f64-scalar-check is cc-sysv-check-scalar

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
' cc-f64-lex is cc-lex-extra-fwd
: cc-f64-literal ( -- handled? )
  cc-target-sysv @ tok-kind @ tk-float = and 0= if, [lit] 0 exit, then,
  tok-str-addr @ tok-str-len @ cc-f64-parse-fwd cc-emit-movabs-rdi-imm64
  ty-double [lit] 0 ty-make [lit] 0 cc-mark-typed-value true ;
' cc-f64-literal is cc-value-literal-fwd

: cc-f64-xmm0-from-rdi
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 110 cc-emit-byte [lit] 199 cc-emit-byte ;
: cc-f64-xmm1-from-rcx
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 110 cc-emit-byte [lit] 201 cc-emit-byte ;
: cc-f64-xmm1-from-rax
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 110 cc-emit-byte [lit] 200 cc-emit-byte ;
: cc-f64-rdi-from-xmm0
  [lit] 102 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 126 cc-emit-byte [lit] 199 cc-emit-byte ;
: cc-f64-signed-from-rdi
  [lit] 242 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 42 cc-emit-byte [lit] 199 cc-emit-byte ;
: cc-f64-truncate-rdi
  [lit] 242 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 44 cc-emit-byte [lit] 248 cc-emit-byte ;
: cc-f64-sse ( opcode -- )
  [lit] 242 cc-emit-byte [lit] 15 cc-emit-byte cc-emit-byte [lit] 193 cc-emit-byte ;
: cc-f64-jcc ( opcode -- patch )
  [lit] 15 cc-emit-byte cc-emit-byte cc-out-pos @ [lit] 0 cc-emit-4le ;
: cc-f64-flip-sign
  [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte [lit] 186 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 63 cc-emit-byte ;
: cc-f64-u64-to-double
  cc-emit-test-rdi [lit] 137 cc-f64-jcc >r
  \ High unsigned half: round the sticky half, then double exactly.
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 209 cc-emit-byte [lit] 232 cc-emit-byte
  [lit] 131 cc-emit-byte [lit] 231 cc-emit-byte [lit] 1 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 9 cc-emit-byte [lit] 248 cc-emit-byte
  [lit] 242 cc-emit-byte [lit] 72 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 42 cc-emit-byte [lit] 192 cc-emit-byte
  [lit] 242 cc-emit-byte [lit] 15 cc-emit-byte
  [lit] 88 cc-emit-byte [lit] 192 cc-emit-byte
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  cc-f64-signed-from-rdi r> cc-patch-rel32-to-here ;
: cc-f64-double-to-u64
  [lit] 72 cc-emit-byte [lit] 184 cc-emit-byte
  [lit] 4890909195324358656 cc-emit-8le cc-f64-xmm1-from-rax
  [lit] 102 cc-emit-byte [lit] 15 cc-emit-byte
  [lit] 46 cc-emit-byte [lit] 193 cc-emit-byte
  [lit] 130 cc-f64-jcc >r
  [lit] 92 cc-f64-sse cc-f64-truncate-rdi cc-f64-flip-sign
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  cc-f64-truncate-rdi r> cc-patch-rel32-to-here ;

: cc-f64-convert ( source destination -- )
  2dup cc-f64-type? swap cc-f64-type? or 0= if,
    cc-emit-convert-value-default exit,
  then,
  dup cc-f64-type? if,
    swap dup cc-f64-type? if, 2drop exit, then,
    dup cc-const-integer? 0= if, [lit] 232 cc-die then,
    dup cc-emit-convert-rdi
    dup ty-unsigned? swap ty-size [lit] 8 = and if,
      cc-f64-u64-to-double
    else, cc-f64-signed-from-rdi then,
    drop cc-f64-rdi-from-xmm0
  else,
    nip dup ty-base ty-void = over ty-ptr 0= and if, drop exit, then,
    dup cc-const-integer? 0= if, [lit] 232 cc-die then,
    cc-f64-xmm0-from-rdi
    dup ty-unsigned? over ty-size [lit] 8 = and if,
      cc-f64-double-to-u64
    else, cc-f64-truncate-rdi then,
    cc-emit-convert-rdi
  then, ;
' cc-f64-convert is cc-emit-convert-value
: cc-f64-convert-right ( source destination -- )
  2dup cc-f64-type? swap cc-f64-type? or 0= if,
    cc-emit-convert-right-default exit,
  then,
  [lit] 72 cc-emit-byte [lit] 135 cc-emit-byte [lit] 207 cc-emit-byte
  cc-f64-convert
  [lit] 72 cc-emit-byte [lit] 135 cc-emit-byte [lit] 207 cc-emit-byte ;
' cc-f64-convert-right is cc-emit-convert-right
: cc-f64-initialize ( source destination -- )
  2dup cc-f64-type? swap cc-f64-type? or if, cc-f64-convert else, 2drop then, ;
' cc-f64-initialize is cc-value-init-fwd
: cc-f64-return
  cc-native-return-type @ cc-f64-type? if,
    cc-f64-xmm0-from-rdi
  else, cc-emit-mov-rax-rdi then, ;
' cc-f64-return is cc-value-return-fwd
: cc-f64-result ( type -- )
  dup cc-f64-type? if, drop cc-f64-rdi-from-xmm0 else, cc-emit-convert-rdi then, ;
' cc-f64-result is cc-sysv-result-value-fwd

: cc-f64-common-type ( left right -- type )
  2dup cc-f64-type? swap cc-f64-type? or if,
    over ty-ptr over ty-ptr or if, [lit] 232 cc-die then,
    2drop ty-double [lit] 0 ty-make
  else, cc-expr-common-type-default then, ;
' cc-f64-common-type is cc-expr-common-type
: cc-f64-comparison ( op -- )
  [lit] 102 cc-emit-byte [lit] 15 cc-emit-byte
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
: cc-f64-binop
  cc-expr-left-type @ cc-f64-type? cc-expr-right-type @ cc-f64-type? or 0= if,
    cc-native-binop-emit-default exit,
  then,
  cc-f64-xmm0-from-rdi cc-f64-xmm1-from-rcx
  cc-expr-op-row @ bo-op + @
  dup [char] + = if, drop [lit] 88 else,
  dup [char] - = if, drop [lit] 92 else,
  dup [char] * = if, drop [lit] 89 else,
  dup [char] / = if, drop [lit] 94 else,
    cc-f64-comparison exit,
  then, then, then, then,
  cc-f64-sse cc-f64-rdi-from-xmm0 ;
' cc-f64-binop is cc-native-binop-emit

: cc-f64-test
  cc-last-expr-type @ cc-f64-type? if,
    \ Clear only the sign in a scratch value; both signed zeros are false.
    [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
    [lit] 72 cc-emit-byte [lit] 209 cc-emit-byte [lit] 224 cc-emit-byte
    [lit] 72 cc-emit-byte [lit] 133 cc-emit-byte [lit] 192 cc-emit-byte
  else, cc-emit-test-rdi then, ;
' cc-f64-test is cc-value-test-fwd
: cc-f64-not
  cc-last-expr-type @ cc-f64-type? if,
    cc-f64-test
    [lit] 15 cc-emit-byte [lit] 148 cc-emit-byte [lit] 192 cc-emit-byte
    [lit] 15 cc-emit-byte [lit] 182 cc-emit-byte [lit] 248 cc-emit-byte
  else, cc-emit-not-zero-flag then, ;
' cc-f64-not is cc-value-not-fwd
: cc-f64-negate
  cc-last-expr-type @ cc-f64-type? if, cc-f64-flip-sign else, cc-emit-neg-rdi then, ;
' cc-f64-negate is cc-value-negate-fwd
: cc-f64-complement
  cc-last-expr-type @ cc-f64-type? if, [lit] 232 cc-die then, cc-emit-not-rdi ;
' cc-f64-complement is cc-value-complement-fwd
: cc-f64-ternary
  cc-expr-left-type @ cc-f64-type? cc-expr-right-type @ cc-f64-type? <> if,
    [lit] 232 cc-die
  then, ;
' cc-f64-ternary is cc-value-ternary-fwd

: cc-f64-integer-use ( type -- )
  cc-f64-type? if, [lit] 232 cc-die then, ;
' cc-f64-integer-use is cc-value-integer-use-fwd
' cc-f64-integer-use is cc-value-static-init-fwd
```

## Exercises

1. Explain why an eight-byte storage size does not determine a return register
2. Add an integer-conversion edge near2^53 and predict the nearest-even result
3. Trace a double result through a nested call and persistent stack restoration
4. Design mixed GP/SSE argument allocation with independent register counters

## Takeaways

- Type-aware conversion distinguishes numeric conversion from payload transport
- Binary64 temporaries reuse the existing persistent evaluation storage
- Unsupported ABI classes and operations fail before publishing an artifact
