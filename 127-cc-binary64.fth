\ 127-cc-binary64.fth — binary32/binary64 scalar System V values.
\ Raw payloads occupy RDI/RCX and eight-byte expression/frame slots.
\ Binary32 storage is four bytes; arithmetic rounds at its own precision.
\ XMM0/XMM1 are transient arithmetic registers; XMM0 carries ABI results.
\ Long double moves as X87 data (121, 131). Static binary32/binary64
\ initializers are exact compile-time constants (125, 128).
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
  cc-const-float-spelling swap cc-emit-movabs-rdi-imm64
  [lit] 0 cc-mark-typed-value true ;
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
\ Admit floating updates while retaining other targets' scalar-use checks.
: cc-fp-change-check
  cc-last-expr-type @ cc-fp-type? 0= if, cc-change-check-default then, ;
' cc-fp-change-check is cc-change-check-fwd

\ ++/-- use a same-width 1.0 and retain the operand's floating type.
\ RAX/XMM1 are scratch; the shared lvalue path owns address and old value.
: cc-fp-change-value
  cc-change-type @ cc-fp-type? 0= if, cc-change-value-default exit, then,
  cc-fp-xmm0-from-rdi
  [lit] 72 cc-emit-byte [lit] 184 cc-emit-byte
  cc-change-type @ cc-f32-type? if,
    [lit] 1065353216
  else, [lit] 4607182418800017408 then,
  cc-emit-8le cc-fp-xmm1-from-rax
  cc-change-delta @ [lit] 1 = if, [lit] 88 else, [lit] 92 then,
  cc-change-type @ cc-fp-sse cc-fp-rdi-from-xmm0
  cc-change-type @ cc-emit-convert-rdi ;
' cc-fp-change-value is cc-change-value-fwd

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
\ C99 _Bool: any nonzero scalar converts to 1, and so does a NaN, which
\ compares unequal to zero. A floating value is zero exactly when its bits
\ without the sign are zero; an integer or pointer is tested at its width.
: cc-bool-type? ( type -- flag ) dup ty-ptr 0= swap ty-base ty-bool = and ;
: cc-bool-convert ( source -- )
  dup cc-bool-type? if, drop exit, then,
  dup cc-fp-type? if,
    cc-f32-type? 0= if, [lit] 72 cc-emit-byte then,
    [lit] 209 cc-emit-byte [lit] 231 cc-emit-byte    \ shl edi/rdi, 1
  else,
    ty-size
    dup [lit] 2 = if, [lit] 102 cc-emit-byte then,
    dup [lit] 8 = if, [lit] 72 cc-emit-byte then,
    [lit] 1 = if, [lit] 64 cc-emit-byte [lit] 132 else, [lit] 133 then,
    cc-emit-byte [lit] 255 cc-emit-byte              \ test dil/di/edi/rdi
  then,
  [lit] 64 cc-emit-byte [lit] 15 cc-emit-byte
  [lit] 149 cc-emit-byte [lit] 199 cc-emit-byte    \ setne dil
  cc-emit-zx-byte-rdi ;
: cc-fp-convert ( source destination -- )
  dup cc-bool-type? if, drop cc-bool-convert exit, then,
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
  2dup cc-fp-type? swap cc-fp-type? or over cc-bool-type? or if,
    cc-fp-convert
  else, 2drop then, ;
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
