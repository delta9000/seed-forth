\ 128-cc-float-literal.fth -- exact, bounded decimal-to-binary64 decoding.
\ Only integer Forth operations participate in parsing or rounding. The
\ returned cell is an IEEE binary64 encoding, not a host floating value.
\ Requires 010 and 020; production loads it after the scalar value layer.

create cc-f64-error-prefix s, cc-f64-literal: bl c,
here cc-f64-error-prefix - constant cc-f64-error-prefix-len
create cc-f64-error-malformed s, malformed nl c,
here cc-f64-error-malformed - constant cc-f64-error-malformed-len
create cc-f64-error-suffix s, suffix-unsupported nl c,
here cc-f64-error-suffix - constant cc-f64-error-suffix-len
create cc-f64-error-hex s, hexfloat-unsupported nl c,
here cc-f64-error-hex - constant cc-f64-error-hex-len
create cc-f64-error-token s, token-limit nl c,
here cc-f64-error-token - constant cc-f64-error-token-len
create cc-f64-error-digits s, digit-limit nl c,
here cc-f64-error-digits - constant cc-f64-error-digits-len
create cc-f64-error-exponent s, exponent-limit nl c,
here cc-f64-error-exponent - constant cc-f64-error-exponent-len
create cc-f64-error-overflow s, overflow nl c,
here cc-f64-error-overflow - constant cc-f64-error-overflow-len
create cc-f64-error-workspace s, workspace-limit nl c,
here cc-f64-error-workspace - constant cc-f64-error-workspace-len
: cc-f64-fail ( address length -- )
  cc-f64-error-prefix cc-f64-error-prefix-len cc-err-write
  cc-err-write [lit] 248 die ;
: cc-f64-malformed
  cc-f64-error-malformed cc-f64-error-malformed-len cc-f64-fail ;
: cc-f64-overflow
  cc-f64-error-overflow cc-f64-error-overflow-len cc-f64-fail ;

\ Big integers are a used-limb count followed by 128 little-endian limbs.
\ Each 32-bit limb occupies a cell, so multiply-by-ten plus carry fits
\ comfortably in an unsigned seed cell. Zero has no used limbs. Bytes
\ outside the used prefix are never read. Operations preserve this form.
[lit] 128 constant cc-f64-limb-cap
[lit] 4294967296 constant cc-f64-radix
[lit] 4294967295 constant cc-f64-mask
[lit] 1032 constant cc-f64-big-size
create cc-f64-n cc-f64-big-size allot
create cc-f64-d cc-f64-big-size allot
variable cc-f64-bi-a
variable cc-f64-bi-b
variable cc-f64-bi-i
variable cc-f64-bi-m
variable cc-f64-bi-carry
: cc-f64-bi-cell ( big index -- address ) [lit] 1 + [lit] 8 * + ;
: cc-f64-bi-get ( big index -- limb )
  over @ over > if, cc-f64-bi-cell @ else, 2drop [lit] 0 then, ;
: cc-f64-bi-zero ( big -- ) [lit] 0 swap ! ;
: cc-f64-bi-trim ( big -- )
  begin, dup @ while,
    dup dup @ 1- cc-f64-bi-cell @ if, drop exit, then,
    [lit] 1 over -!
  repeat, drop ;
: cc-f64-bi-append ( limb big -- )
  dup @ cc-f64-limb-cap >= if,
    cc-f64-error-workspace cc-f64-error-workspace-len cc-f64-fail
  then,
  2dup dup @ cc-f64-bi-cell ! [lit] 1 swap +! drop ;
: cc-f64-bi-muladd ( big multiplier carry -- )
  cc-f64-bi-carry ! cc-f64-bi-m ! cc-f64-bi-a !
  [lit] 0 cc-f64-bi-i !
  begin, cc-f64-bi-i @ cc-f64-bi-a @ @ < while,
    cc-f64-bi-a @ cc-f64-bi-i @ cc-f64-bi-cell
    dup @ cc-f64-bi-m @ * cc-f64-bi-carry @ +
    dup cc-f64-radix / cc-f64-bi-carry !
    cc-f64-mask and swap !
    [lit] 1 cc-f64-bi-i +!
  repeat,
  cc-f64-bi-carry @ if,
    cc-f64-bi-carry @ cc-f64-bi-a @ cc-f64-bi-append
  then, ;
: cc-f64-bi-compare ( a b -- comparison )
  cc-f64-bi-b ! cc-f64-bi-a !
  cc-f64-bi-a @ @ cc-f64-bi-b @ @ < if, true exit, then,
  cc-f64-bi-a @ @ cc-f64-bi-b @ @ > if, [lit] 1 exit, then,
  cc-f64-bi-a @ @ cc-f64-bi-i !
  begin, cc-f64-bi-i @ while,
    [lit] 1 cc-f64-bi-i -!
    cc-f64-bi-a @ cc-f64-bi-i @ cc-f64-bi-get
    cc-f64-bi-b @ cc-f64-bi-i @ cc-f64-bi-get
    2dup < if, 2drop true exit, then,
    > if, [lit] 1 exit, then,
  repeat, [lit] 0 ;
: cc-f64-bi-subtract ( a b -- )
  \ Caller proves a >= b. The signed temporary is in [-2^32, 2^32-1].
  cc-f64-bi-b ! cc-f64-bi-a !
  [lit] 0 cc-f64-bi-carry ! [lit] 0 cc-f64-bi-i !
  begin, cc-f64-bi-i @ cc-f64-bi-a @ @ < while,
    cc-f64-bi-a @ cc-f64-bi-i @ cc-f64-bi-get
    cc-f64-bi-b @ cc-f64-bi-i @ cc-f64-bi-get -
    cc-f64-bi-carry @ - dup 0< if,
      cc-f64-radix + [lit] 1 cc-f64-bi-carry !
    else, [lit] 0 cc-f64-bi-carry ! then,
    cc-f64-bi-a @ cc-f64-bi-i @ cc-f64-bi-cell !
    [lit] 1 cc-f64-bi-i +!
  repeat,
  cc-f64-bi-a @ cc-f64-bi-trim ;
: cc-f64-bi-bits ( big -- bits )
  dup @ 0= if, drop [lit] 0 exit, then,
  dup @ 1- dup [lit] 32 * >r cc-f64-bi-get
  begin, dup while, [lit] 2 / r> 1+ >r repeat, drop r> ;
: cc-f64-bi-shift ( big count -- )
  begin, dup while,
    >r dup [lit] 2 [lit] 0 cc-f64-bi-muladd r> 1-
  repeat, 2drop ;
: cc-f64-bi-ten-power ( big count -- )
  begin, dup while,
    >r dup [lit] 10 [lit] 0 cc-f64-bi-muladd r> 1-
  repeat, 2drop ;

\ The grammar is ((digits '.' digits?) | ('.' digits) | digits)
\ followed by an optional e/E and signed decimal exponent. A point or
\ exponent is mandatory. A unary sign belongs to the expression parser.
\ Limit: 4096 token bytes; 768 digits from the first nonzero mantissa
\ digit through its last digit; exponent magnitude at most 1,000,000.
variable cc-f64-p
variable cc-f64-left
variable cc-f64-point
variable cc-f64-any-digit
variable cc-f64-significant
variable cc-f64-fractional
variable cc-f64-exponent
variable cc-f64-exponent-negative
variable cc-f64-has-exponent
variable cc-f64-scale
variable cc-f64-order
variable cc-f64-e
variable cc-f64-q
: cc-f64-peek ( -- character )
  cc-f64-left @ if, cc-f64-p @ c@ else, [lit] 0 then, ;
: cc-f64-advance
  [lit] 1 cc-f64-p +! [lit] 1 cc-f64-left -! ;
: cc-f64-mantissa
  begin, cc-f64-left @ while,
    cc-f64-peek dup digit? if,
      [char] 0 - true cc-f64-any-digit !
      cc-f64-point @ if, [lit] 1 cc-f64-fractional +! then,
      dup cc-f64-significant @ or if,
        [lit] 1 cc-f64-significant +!
        cc-f64-significant @ [lit] 768 > if,
          cc-f64-error-digits cc-f64-error-digits-len cc-f64-fail
        then,
        cc-f64-n [lit] 10 rot cc-f64-bi-muladd
      else, drop then,
      cc-f64-advance
    else,
      [char] . = if,
        cc-f64-point @ if, cc-f64-malformed then,
        true cc-f64-point ! cc-f64-advance
      else, exit, then,
    then,
  repeat, ;
: cc-f64-read-exponent
  cc-f64-peek dup [char] e = swap [char] E = or 0= if, exit, then,
  true cc-f64-has-exponent ! cc-f64-advance
  cc-f64-peek dup [char] - = if,
    true cc-f64-exponent-negative !
  then,
  dup [char] - = swap [char] + = or if, cc-f64-advance then,
  cc-f64-peek digit? 0= if, cc-f64-malformed then,
  begin, cc-f64-peek digit? while,
    cc-f64-exponent @ [lit] 10 * cc-f64-peek [char] 0 - +
    dup [lit] 1000000 > if,
      cc-f64-error-exponent cc-f64-error-exponent-len cc-f64-fail
    then, cc-f64-exponent ! cc-f64-advance
  repeat,
  cc-f64-exponent-negative @ if,
    [lit] 0 cc-f64-exponent @ - cc-f64-exponent !
  then, ;
: cc-f64-spelling ( address length -- )
  dup [lit] 4096 > if,
    cc-f64-error-token cc-f64-error-token-len cc-f64-fail
  then,
  cc-f64-left ! cc-f64-p !
  cc-f64-left @ [lit] 2 >= if,
    cc-f64-p @ c@ [char] 0 =
    cc-f64-p @ 1+ c@ dup [char] x = swap [char] X = or and if,
      cc-f64-error-hex cc-f64-error-hex-len cc-f64-fail
    then,
  then,
  [lit] 0 cc-f64-point ! [lit] 0 cc-f64-any-digit !
  [lit] 0 cc-f64-significant ! [lit] 0 cc-f64-fractional !
  [lit] 0 cc-f64-exponent ! [lit] 0 cc-f64-exponent-negative !
  [lit] 0 cc-f64-has-exponent !
  cc-f64-n cc-f64-bi-zero cc-f64-d cc-f64-bi-zero
  [lit] 1 cc-f64-d cc-f64-bi-append
  cc-f64-mantissa
  cc-f64-any-digit @ 0= if, cc-f64-malformed then,
  cc-f64-read-exponent
  cc-f64-left @ if,
    cc-f64-peek dup [char] f = over [char] F = or
    over [char] l = or swap [char] L = or if,
      cc-f64-error-suffix cc-f64-error-suffix-len cc-f64-fail
    then, cc-f64-malformed
  then,
  cc-f64-point @ cc-f64-has-exponent @ or 0= if, cc-f64-malformed then, ;

\ Exact x = N/D * 2^e. Initial decimal order rejects obvious overflow
\ and zero before constructing powers. Remaining scale is -1091..308.
\ Therefore D has at most 3625 bits; normalization and twice-remainder
\ need at most 3626, below the checked 4096-bit workspace.
: cc-f64-normalize
  cc-f64-n cc-f64-bi-bits cc-f64-d cc-f64-bi-bits - cc-f64-e !
  cc-f64-e @ 0< if,
    cc-f64-n [lit] 0 cc-f64-e @ - cc-f64-bi-shift
  else, cc-f64-d cc-f64-e @ cc-f64-bi-shift then,
  cc-f64-n cc-f64-d cc-f64-bi-compare 0< if,
    cc-f64-n [lit] 1 cc-f64-bi-shift [lit] 1 cc-f64-e -!
  then, ;
: cc-f64-quotient ( fractional-bits -- )
  \ N/D is in [1,2). At every step q is the integer prefix and
  \ 0 <= N < D is the exact remainder; no sticky bit is approximated.
  [lit] 1 cc-f64-q ! cc-f64-n cc-f64-d cc-f64-bi-subtract
  begin, dup while,
    >r cc-f64-n [lit] 1 cc-f64-bi-shift
    cc-f64-q @ [lit] 2 * cc-f64-q !
    cc-f64-n cc-f64-d cc-f64-bi-compare 0< 0= if,
      cc-f64-n cc-f64-d cc-f64-bi-subtract [lit] 1 cc-f64-q +!
    then, r> 1-
  repeat, drop
  cc-f64-n [lit] 1 cc-f64-bi-shift
  cc-f64-n cc-f64-d cc-f64-bi-compare
  dup [lit] 0 > swap 0= cc-f64-q @ [lit] 1 and and or if,
    [lit] 1 cc-f64-q +!
  then, ;
: cc-f64-decode ( address length -- bits )
  cc-f64-spelling
  cc-f64-significant @ 0= if, [lit] 0 exit, then,
  cc-f64-exponent @ cc-f64-fractional @ - cc-f64-scale !
  cc-f64-significant @ cc-f64-scale @ + 1- cc-f64-order !
  cc-f64-order @ [lit] 308 > if, cc-f64-overflow then,
  cc-f64-order @ [lit] 0 [lit] 324 - < if, [lit] 0 exit, then,
  cc-f64-scale @ 0< if,
    cc-f64-d [lit] 0 cc-f64-scale @ - cc-f64-bi-ten-power
  else, cc-f64-n cc-f64-scale @ cc-f64-bi-ten-power then,
  cc-f64-normalize
  cc-f64-e @ [lit] 0 [lit] 1075 - < if, [lit] 0 exit, then,
  cc-f64-e @ [lit] 0 [lit] 1075 - = if,
    \ Exactly half the minimum subnormal rounds to even zero.
    cc-f64-n cc-f64-d cc-f64-bi-compare 0= if,
      [lit] 0 else, [lit] 1 then, exit,
  then,
  cc-f64-e @ [lit] 0 [lit] 1022 - < if,
    cc-f64-e @ [lit] 1074 + cc-f64-quotient cc-f64-q @ exit,
  then,
  [lit] 52 cc-f64-quotient
  cc-f64-q @ [lit] 9007199254740992 = if,
    cc-f64-q @ [lit] 2 / cc-f64-q ! [lit] 1 cc-f64-e +!
  then,
  cc-f64-e @ [lit] 1023 > if, cc-f64-overflow then,
  cc-f64-e @ [lit] 1023 + [lit] 4503599627370496 *
  cc-f64-q @ [lit] 4503599627370496 - + ;

: cc-f64-parse ( address length -- bits ) cc-f64-decode ;
' cc-f64-parse is cc-f64-parse-fwd
