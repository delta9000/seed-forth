\ 125-cc-consteval.fth — typed LP64 constants for the direct System V target.
\ Loading this layer preserves legacy and native/TinyCC constant semantics.
\ A private value record carries value, type, descriptor and relocation ID.
\ The public integer API returns ( value type ); the static API returns all
\ four cells. No machine code is executed to obtain a constant value.

[lit] 4096 constant cc-const-cap
create cc-const-values cc-const-cap [lit] 32 * allot
variable cc-const-used
: cc-const-type [lit] 8 + @ ;
: cc-const-desc [lit] 16 + @ ;
: cc-const-symbol [lit] 24 + @ ;
: cc-const-new ( value type descriptor symbol -- record )
  cc-const-used @ 1+ cc-const-cap [lit] 240 cc-check-cap
  cc-const-used @ [lit] 32 * cc-const-values + >r
  [lit] 1 cc-const-used +!
  r@ [lit] 24 + ! r@ [lit] 16 + ! r@ [lit] 8 + ! r@ ! r> ;
: cc-const-cells ( record -- value type descriptor symbol )
  dup @ swap dup cc-const-type swap dup cc-const-desc swap cc-const-symbol ;
: cc-const-int-type ty-int [lit] 0 ty-make ;
: cc-const-integer? ( type -- flag )
  dup ty-ptr if, drop [lit] 0 exit, then,
  ty-base
  dup ty-char = over ty-uchar = or over ty-short = or
  over ty-ushort = or over ty-int = or over ty-uint = or
  over ty-long = or over ty-ulong = or
  over ty-llong = or swap ty-ullong = or ;
: cc-const-check-integer ( record -- )
  dup cc-const-symbol swap cc-const-type cc-const-integer? 0= or if,
    cc-const-unsupported
  then, ;

\ Narrowing keeps low bits, then sign extends signed integer targets.
\ / is the seed's unsigned division, so a bit-63-set value stays intact.
: cc-const-convert ( value type -- value )
  dup cc-const-integer? 0= if, cc-const-unsupported then,
  dup ty-size [lit] 8 = if, drop exit, then,
  dup ty-unsigned? >r ty-size [lit] 8 * cc-pow2
  dup 1- rot and swap
  r> 0= if,
    over over [lit] 2 / and if, - else, drop then,
  else, drop then, ;
: cc-const-promote ( record -- record )
  dup cc-const-check-integer
  dup cc-const-type cc-expr-promote over [lit] 8 + ! ;
: cc-const-scalar? ( type -- flag )
  dup ty-ptr if, drop true else, cc-const-integer? then, ;
: cc-const-cast ( record type descriptor -- record )
  >r >r
  dup cc-const-type cc-const-scalar? r@ cc-const-scalar? and 0= if,
    cc-const-unsupported
  then,
  dup cc-const-type r@ cc-cast-types-fwd
  dup cc-const-symbol if,
    r@ ty-size [lit] 8 <> if, cc-const-unsupported then,
  else,
    dup cc-const-type cc-const-integer? if,
      dup @ over cc-const-type cc-const-convert over !
    then,
    r@ ty-ptr 0= if, dup @ r@ cc-const-convert over ! then,
  then,
  r> over [lit] 8 + ! r> over [lit] 16 + ! ;

\ 010's subtraction comparison is sufficient for compiler offsets, but
\ constants may straddle the entire signed or unsigned 64-bit range.
: cc-const-slt ( a b -- flag )
  2dup cc-xor 0< if, drop 0< else, < then, ;
: cc-const-ult ( a b -- flag )
  2dup cc-xor 0< if, nip 0< else, < then, ;
: cc-const-signed-min ( type -- value )
  ty-size [lit] 8 * 1- cc-pow2 cc-negate ;

\ The lexer retains the spelling but accumulates modulo2^64. Recheck the
\ digits before accepting that value, and reject floating or malformed
\ spellings instead of accepting their integer prefix as a constant.
variable cc-const-literal-base
variable cc-const-literal-value
variable cc-const-literal-u
variable cc-const-literal-l
variable cc-const-literal-digit
variable cc-const-literal-lchar
: cc-const-literal-check
  [lit] 10 cc-const-literal-base ! [lit] 0 cc-const-literal-value !
  [lit] 0 cc-const-literal-u ! [lit] 0 cc-const-literal-l !
  [lit] 0 cc-const-literal-digit ! [lit] 0 cc-const-literal-lchar !
  tok-str-addr @ tok-str-len @
  over c@ [char] 0 = if,
    [lit] 8 cc-const-literal-base !
    over 1+ c@ dup [char] x = swap [char] X = or if,
      swap [lit] 2 + swap [lit] 2 - [lit] 16 cc-const-literal-base !
    then,
  then,
  dup 0= if, cc-const-unsupported then,
  begin, dup while,
    over c@ dup cc-hex-digit? if,
      cc-hex-digit-val
      dup cc-const-literal-base @ >= if, cc-const-unsupported then,
      true over - cc-const-literal-base @ /
      cc-const-literal-value @ cc-const-ult if, cc-const-unsupported then,
      cc-const-literal-value @ cc-const-literal-base @ * + cc-const-literal-value !
      true cc-const-literal-digit !
    else,
      dup [char] u = over [char] U = or if,
        cc-const-literal-u @ if, cc-const-unsupported then,
        true cc-const-literal-u !
        cc-const-literal-l @ if, [lit] 3 cc-const-literal-l ! then,
      else,
        dup [char] l = over [char] L = or 0= if, cc-const-unsupported then,
        cc-const-literal-l @ dup [lit] 2 >= if, cc-const-unsupported then,
        1+ cc-const-literal-l !
        cc-const-literal-lchar @ if,
          dup cc-const-literal-lchar @ <> if, cc-const-unsupported then,
        else, dup cc-const-literal-lchar ! then,
      then, drop
      \ Digits cannot resume after a suffix; suffixes are U, L, LL and
      \ their combinations. Their spelling cannot exceed three letters.
      dup [lit] 3 > if, cc-const-unsupported then,
      over 1+ c@ digit? if, cc-const-unsupported then,
    then,
    swap 1+ swap 1-
  repeat, drop
  cc-const-literal-digit @ 0= if, cc-const-unsupported then,
  c@ dup ident-cont? swap [char] . = or if, cc-const-unsupported then, ;

defer cc-const-unary-fwd
defer cc-const-conditional-fwd

: cc-const-operand ( -- record )
  cc-next-token-keep
  tok-kind @ tk-num = if,
    cc-const-literal-check
    tok-num @ cc-integer-literal-type [lit] 0 [lit] 0 cc-const-new exit,
  then,
  tok-kind @ tk-chr = if,
    tok-num @ cc-const-int-type [lit] 0 [lit] 0 cc-const-new exit,
  then,
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< 0= if,
      dup cc-sym-kind-of sk-enum = if,
        cc-sym-val-of cc-const-int-type [lit] 0 [lit] 0 cc-const-new exit,
      then,
    then, drop
    cc-const-ident-fwd cc-const-new exit,
  then,
  tok-kind @ tk-str = if, cc-const-string-fwd cc-const-new exit, then,
  lparen cc-tok-punct? if,
    cc-next-token-keep
    cc-type-start? if,
      cc-parse-type-name
      cc-type-name-qualified @ cc-const-qualified @ or cc-const-qualified !
      cc-type-name-array @ if, cc-const-unsupported then,
      >r cc-cast-desc @ >r
      [char] ) cc-expect-punct-c
      cc-const-unary-fwd
      r> r> swap cc-const-cast exit,
    then,
    cc-putback-token cc-const-conditional-fwd
    [char] ) cc-expect-punct-c exit,
  then,
  cc-const-unsupported ;

: cc-const-unary ( -- record )
  cc-next-token-keep
  kw-sizeof cc-tok-kw? if,
    cc-native-sizeof ty-ulong [lit] 0 ty-make
    [lit] 0 [lit] 0 cc-const-new exit,
  then,
  [char] & cc-tok-punct? if,
    cc-const-address-fwd cc-const-new exit,
  then,
  [char] + cc-tok-punct? if,
    cc-const-unary cc-const-promote exit,
  then,
  [char] - cc-tok-punct? if,
    cc-const-unary cc-const-promote
    cc-cx-skip @ 0= if,
      dup cc-const-type ty-unsigned? 0= if,
        dup @ over cc-const-type cc-const-signed-min = if,
          [lit] 242 cc-die
        then,
      then,
      dup @ cc-negate over cc-const-type cc-const-convert over !
    then, exit,
  then,
  [char] ~ cc-tok-punct? if,
    cc-const-unary cc-const-promote
    dup @ cc-invert over cc-const-type cc-const-convert over ! exit,
  then,
  [char] ! cc-tok-punct? if,
    cc-const-unary dup cc-const-check-integer
    dup @ 0= cc-flag over !
    cc-const-int-type over [lit] 8 + ! exit,
  then,
  cc-putback-token cc-const-operand ;
' cc-const-unary is cc-const-unary-fwd

\ Binary temporaries are filled only after both recursive operands return.
variable cc-const-left
variable cc-const-right
variable cc-const-row
variable cc-const-common
variable cc-const-a
variable cc-const-b

: cc-const-op cc-const-row @ bo-op + @ ;
: cc-const-unsigned? cc-const-common @ ty-unsigned? ;
: cc-const-less
  cc-const-unsigned? if, cc-const-ult else, cc-const-slt then, ;
: cc-const-address? ( record -- flag )
  dup cc-const-symbol swap cc-const-type ty-ptr or ;
: cc-const-address-binary ( -- record )
  cc-const-op [char] + = cc-const-op [char] - = or 0= if,
    cc-const-unsupported
  then,
  cc-const-left @ cc-const-address? if,
    cc-const-right @ cc-const-address? if, cc-const-unsupported then,
  else,
    cc-const-op [char] - = if, cc-const-unsupported then,
    cc-const-left @ cc-const-right @ cc-const-left ! cc-const-right !
  then,
  cc-const-right @ cc-const-check-integer
  cc-const-left @ cc-const-type dup ty-ptr if,
    dup ty-ptr [lit] 1 = if,
      dup ty-base dup ty-void = swap ty-func = or if,
        cc-const-unsupported
      then,
    then,
    cc-const-left @ cc-const-desc cc-expr-pointee-size
    cc-const-right @ @ *
  else,
    cc-const-right @ cc-const-type cc-expr-common-type
    dup ty-size [lit] 8 <> if, cc-const-unsupported then,
    dup cc-const-left @ [lit] 8 + !
    cc-const-right @ @ swap cc-const-convert
  then,
  cc-cx-skip @ if, drop [lit] 0 else,
    cc-const-op [char] - = if, cc-negate then,
    cc-const-left @ @ +
  then,
  cc-const-left @ ! cc-const-left @ ;
: cc-const-check-result ( value -- value )
  cc-const-unsigned? 0= if,
    dup cc-const-common @ cc-const-convert over <> if, [lit] 242 cc-die then,
  then,
  cc-const-common @ cc-const-convert ;
: cc-const-add ( a b -- sum )
  2dup + >r
  cc-const-unsigned? 0= if,
    2dup cc-xor 0< 0= if,
      over r@ cc-xor 0< if, [lit] 242 cc-die then,
    then,
  then, 2drop r> cc-const-check-result ;
: cc-const-subtract ( a b -- difference )
  2dup - >r
  cc-const-unsigned? 0= if,
    2dup cc-xor 0< if,
      over r@ cc-xor 0< if, [lit] 242 cc-die then,
    then,
  then, 2drop r> cc-const-check-result ;
: cc-const-multiply ( a b -- product )
  cc-const-unsigned? 0= over 0= 0= and if,
    2dup cc-xor 0< >r
    cc-const-common @ cc-const-signed-min cc-abs
    r> 0= if, 1- then,
    over cc-abs / [lit] 2 cc-npick cc-abs cc-const-ult if,
      [lit] 242 cc-die
    then,
  then, * cc-const-check-result ;
: cc-const-divide ( a b -- value )
  cc-divisor
  cc-const-unsigned? if,
    cc-const-op [char] / = if, / else, 2dup / * - then,
  else,
    dup true = [lit] 2 cc-npick cc-const-common @ cc-const-signed-min = and if,
      [lit] 242 cc-die
    then,
    cc-const-op [char] / = if, cc-div else, cc-mod then,
  then, ;
: cc-const-shift ( a b -- value )
  dup 0< over cc-const-common @ ty-size [lit] 8 * >= or if,
    [lit] 241 cc-die
  then,
  cc-const-op pt-shl = if,
    cc-const-unsigned? 0= if,
      over 0< if, [lit] 242 cc-die then,
      cc-const-common @ cc-const-signed-min cc-abs 1-
      over cc-pow2 / [lit] 2 cc-npick cc-const-ult if,
        [lit] 242 cc-die
      then,
    then, cc-shl
  else,
    cc-const-unsigned? if, cc-pow2 / else, cc-sar then,
  then, cc-const-common @ cc-const-convert ;
: cc-const-evaluate ( a b -- value )
  cc-const-op
  dup [char] + = if, drop cc-const-add exit, then,
  dup [char] - = if, drop cc-const-subtract exit, then,
  dup [char] * = if, drop cc-const-multiply exit, then,
  dup [char] / = over [char] % = or if, drop cc-const-divide exit, then,
  dup pt-shl = over pt-shr = or if, drop cc-const-shift exit, then,
  dup [char] < = if, drop cc-const-less cc-flag exit, then,
  dup [char] > = if, drop swap cc-const-less cc-flag exit, then,
  dup pt-le = if, drop swap cc-const-less 0= cc-flag exit, then,
  dup pt-ge = if, drop cc-const-less 0= cc-flag exit, then,
  drop cc-const-row @ bo-eval + @ execute ;

: cc-const-binary-apply ( left right row -- left )
  cc-const-row ! cc-const-right ! cc-const-left !
  cc-const-left @ cc-const-address? cc-const-right @ cc-const-address? or if,
    cc-const-address-binary exit,
  then,
  cc-const-left @ cc-const-check-integer
  cc-const-right @ cc-const-check-integer
  cc-const-row @ bo-level + @ level-shift = if,
    cc-const-left @ cc-const-type cc-expr-promote
  else,
    cc-const-left @ cc-const-type cc-const-right @ cc-const-type cc-expr-common-type
  then, cc-const-common !
  cc-const-left @ @ cc-const-common @ cc-const-convert cc-const-a !
  cc-const-row @ bo-level + @ level-shift = if,
    cc-const-right @ @ cc-const-right @ cc-const-type cc-expr-promote cc-const-convert
  else,
    cc-const-right @ @ cc-const-common @ cc-const-convert
  then, cc-const-b !
  cc-cx-skip @ if, [lit] 0 else,
    cc-const-a @ cc-const-b @ cc-const-evaluate
  then,
  cc-const-row @ bo-level + @ dup level-rel = swap level-eq = or if,
    cc-const-int-type cc-const-common !
  then,
  cc-const-common @ cc-const-convert cc-const-left @ !
  cc-const-common @ cc-const-left @ [lit] 8 + ! cc-const-left @ ;
: cc-const-binary ( level -- record )
  dup 0= if, drop cc-const-unary exit, then,
  dup 1- cc-const-binary
  begin, over cc-binop? dup while,
    >r over 1- cc-const-binary r> cc-const-binary-apply
  repeat, drop cc-putback-token nip ;

: cc-const-logical-and ( -- record )
  level-bit-or cc-const-binary
  begin, cc-next-token-keep pt-and-and cc-tok-punct? while,
    dup cc-const-check-integer
    cc-cx-skip @ >r dup @ 0= if, true cc-cx-skip ! then,
    level-bit-or cc-const-binary
    r> cc-cx-skip ! dup cc-const-check-integer
    @ 0= 0= over @ 0= 0= and cc-flag over !
    cc-const-int-type over [lit] 8 + !
  repeat, cc-putback-token ;
: cc-const-logical-or ( -- record )
  cc-const-logical-and
  begin, cc-next-token-keep pt-or-or cc-tok-punct? while,
    dup cc-const-check-integer
    cc-cx-skip @ >r dup @ if, true cc-cx-skip ! then,
    cc-const-logical-and
    r> cc-cx-skip ! dup cc-const-check-integer
    @ 0= 0= over @ 0= 0= or cc-flag over !
    cc-const-int-type over [lit] 8 + !
  repeat, cc-putback-token ;
: cc-const-null? ( record -- flag )
  dup cc-const-type cc-const-integer? over cc-const-symbol 0= and swap @ 0= and ;
: cc-const-select ( condition yes no -- result )
  \ Two pointer arms need the same pointed-to type. A zero integer arm
  \ adopts the other pointer's type. Symbolic integer arms remain 64-bit.
  over cc-const-type ty-ptr over cc-const-type ty-ptr or if,
    over cc-const-null? if,
      dup cc-const-type [lit] 2 cc-npick [lit] 8 + !
      dup cc-const-desc [lit] 2 cc-npick [lit] 16 + !
    then,
    dup cc-const-null? if,
      over cc-const-type over [lit] 8 + !
      over cc-const-desc over [lit] 16 + !
    then,
    over cc-const-type [lit] 2 cc-npick cc-const-desc
    [lit] 2 cc-npick cc-const-type [lit] 3 cc-npick cc-const-desc
    cc-sysv-compatible-types 0= if, cc-const-unsupported then,
    rot @ if, drop else, nip then, exit,
  then,
  2dup cc-const-type swap cc-const-type cc-expr-common-type >r
  rot @ if, drop else, nip then,
  dup cc-const-symbol if,
    r@ ty-size [lit] 8 <> if, cc-const-unsupported then,
  else, dup @ r@ cc-const-convert over ! then,
  r> over [lit] 8 + ! ;
: cc-const-conditional ( -- record )
  cc-const-logical-or cc-next-token-keep
  [char] ? cc-tok-punct? if,
    dup cc-const-check-integer
    cc-cx-skip @ >r
    dup @ 0= if, true cc-cx-skip ! then,
    cc-const-conditional r@ cc-cx-skip ! >r
    [char] : cc-expect-punct-c
    dup @ if, true cc-cx-skip ! then,
    cc-const-conditional r> swap cc-const-select
    r> cc-cx-skip !
  else, cc-putback-token then, ;
' cc-const-conditional is cc-const-conditional-fwd

\ The object adapter parses address operands without emitting or loading
\ target memory. These callbacks share this evaluator's casts, unary
\ precedence and integer checks, including the current dead-arm state.
: cc-const-address-cast ( type descriptor -- value type descriptor symbol )
  cc-type-name-qualified @ cc-const-qualified @ or cc-const-qualified !
  >r >r cc-const-unary r> r> cc-const-cast cc-const-cells ;
: cc-const-address-unary ( -- value type descriptor symbol )
  cc-const-unary cc-const-cells ;
: cc-const-address-index ( -- value )
  cc-const-conditional dup cc-const-check-integer @ ;
' cc-const-address-cast is cc-om-address-cast-fwd
' cc-const-address-unary is cc-om-address-unary-fwd
' cc-const-address-index is cc-om-address-index-fwd

\ Each public parse restores its pool watermark. Nested sizeof array bounds
\ can therefore call the same API without corrupting their outer operands.
: cc-parse-static-const ( -- value type descriptor symbol )
  cc-const-used @ >r cc-cx-skip @ >r cc-const-qualified @ >r
  [lit] 0 cc-const-qualified !
  [lit] 0 cc-cx-skip !
  cc-const-conditional cc-const-cells
  r> cc-const-qualified ! r> cc-cx-skip ! r> cc-const-used ! ;
: cc-parse-integer-const ( -- value type )
  cc-parse-static-const
  swap drop if, cc-const-unsupported then,
  dup cc-const-integer? 0= if, cc-const-unsupported then, ;

' cc-parse-static-const is cc-parse-static-const-fwd
: cc-parse-target-const
  cc-target-sysv @ cc-cx-pp @ 0= and if,
    cc-parse-integer-const drop
  else, cc-parse-const-default then, ;
' cc-parse-target-const is cc-parse-const
