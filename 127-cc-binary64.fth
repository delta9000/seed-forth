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
