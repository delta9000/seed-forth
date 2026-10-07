\ 128-cc-float-literal.fth -- exact binary32/binary64/extended constants.
\ Only integer Forth operations participate in parsing or rounding. The
\ returned cell is an IEEE encoding or an extended-object address.
\ One exact ratio rounds literals and constant arithmetic for 125.
\ Requires 010 and 020; production loads it after the scalar value layer.
\ Hooks: cc-fp-decimal-fwd, cc-fp-integer-fwd, cc-fp-resize-fwd,
\ cc-fp-arith-fwd and cc-fp-truncate-fwd (all deferred words).

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

\ Big integers are a used-limb count followed by 2048 little-endian limbs.
\ Each 32-bit limb occupies a cell, so multiply-by-ten plus carry fits
\ comfortably in an unsigned seed cell. Zero has no used limbs. Bytes
\ outside the used prefix are never read. Operations preserve this form.
[lit] 2048 constant cc-f64-limb-cap
[lit] 4294967296 constant cc-f64-radix
[lit] 4294967295 constant cc-f64-mask
[lit] 16392 constant cc-f64-big-size
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
variable cc-f64-allow-hex
variable cc-f64-hex
variable cc-f64-p
variable cc-f64-left
variable cc-f64-point
variable cc-f64-any-digit
variable cc-f64-significant
variable cc-f64-format
variable cc-f64-fractional
variable cc-f64-exponent
variable cc-f64-exponent-negative
variable cc-f64-has-exponent
variable cc-f64-scale
variable cc-f64-order
variable cc-f64-e
variable cc-f64-q-carry
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
  cc-f64-peek cc-f64-hex @ if,
    dup [char] p = swap [char] P = or
  else, dup [char] e = swap [char] E = or then, 0= if, exit, then,
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
: cc-f80-hex-digit? ( character -- flag )
  dup digit? if, drop true exit, then,
  dup [char] a >= over [char] f <= and if, drop true exit, then,
  dup [char] A >= swap [char] F <= and ;
: cc-f80-hex-value ( character -- digit )
  dup digit? if, [char] 0 - exit, then,
  dup [char] a >= if, [char] a else, [char] A then, - [lit] 10 + ;
: cc-f80-hex-mantissa
  cc-f64-advance cc-f64-advance
  begin, cc-f64-left @ while,
    cc-f64-peek dup cc-f80-hex-digit? if,
      cc-f80-hex-value true cc-f64-any-digit !
      cc-f64-point @ if, [lit] 4 cc-f64-fractional +! then,
      dup cc-f64-significant @ or if,
      [lit] 1 cc-f64-significant +!
      cc-f64-significant @ [lit] 768 > if,
        cc-f64-error-digits cc-f64-error-digits-len cc-f64-fail
      then,
      cc-f64-n [lit] 16 rot cc-f64-bi-muladd
      else, drop then, cc-f64-advance
    else,
      [char] . = if,
        cc-f64-point @ if, cc-f64-malformed then,
        true cc-f64-point ! cc-f64-advance
      else, exit, then,
    then,
  repeat, ;
: cc-f64-spelling ( address length -- )
  dup [lit] 4096 > if,
    cc-f64-error-token cc-f64-error-token-len cc-f64-fail
  then,
  cc-f64-left ! cc-f64-p !
  [lit] 0 cc-f64-hex !
  cc-f64-left @ [lit] 2 >= if,
    cc-f64-p @ c@ [char] 0 =
    cc-f64-p @ 1+ c@ dup [char] x = swap [char] X = or and if,
      cc-f64-allow-hex @ 0= if,
        cc-f64-error-hex cc-f64-error-hex-len cc-f64-fail
      then, true cc-f64-hex !
    then,
  then,
  [lit] 0 cc-f64-point ! [lit] 0 cc-f64-any-digit !
  [lit] 0 cc-f64-significant ! [lit] 0 cc-f64-fractional !
  [lit] 0 cc-f64-exponent ! [lit] 0 cc-f64-exponent-negative !
  [lit] 0 cc-f64-has-exponent !
  cc-f64-n cc-f64-bi-zero cc-f64-d cc-f64-bi-zero
  [lit] 1 cc-f64-d cc-f64-bi-append
  cc-f64-hex @ if, cc-f80-hex-mantissa else, cc-f64-mantissa then,
  cc-f64-any-digit @ 0= if, cc-f64-malformed then,
  cc-f64-read-exponent
  cc-f64-hex @ cc-f64-has-exponent @ 0= and if, cc-f64-malformed then,
  cc-f64-left @ if,
    cc-f64-peek dup [char] f = over [char] F = or
    over [char] l = or swap [char] L = or if,
      cc-f64-error-suffix cc-f64-error-suffix-len cc-f64-fail
    then, cc-f64-malformed
  then,
  cc-f64-point @ cc-f64-has-exponent @ or 0= if, cc-f64-malformed then, ;

\ Exact x = N/D * 2^e. Initial decimal order rejects obvious overflow
\ and zero before constructing powers. Extended precision also admits
\ decimal orders through 4932 and down to -4951. The checked 65536-bit
\ workspace covers their ratios and full-range constant sums.
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
  [lit] 0 cc-f64-q-carry !
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
    cc-f64-q @ 0= cc-f64-q-carry !
  then, ;
\ A format names an encoding by its byte size: 8 selects binary64 and
\ 4 binary32, and 16 extended precision. One exact ratio serves all three
\ widths. Each caller selects its format before it rounds.
variable cc-f64-fraction
variable cc-f64-unit
variable cc-f64-emin
variable cc-f64-emax
variable cc-f64-sign
: cc-f64-use ( format -- )
  dup cc-f64-format !
  dup [lit] 16 = if,
    drop [lit] 63 cc-f64-fraction ! 2^63 cc-f64-unit !
    [lit] 16383 cc-f64-emax ! [lit] 0 [lit] 16382 - cc-f64-emin !
    [lit] 32768 cc-f64-sign ! exit,
  then,
  [lit] 4 = if,
    [lit] 23 [lit] 8388608 [lit] 127 [lit] 2147483648
  else,
    [lit] 52 [lit] 4503599627370496 [lit] 1023 2^63
  then,
  cc-f64-sign ! dup cc-f64-emax ! [lit] 1 swap - cc-f64-emin !
  cc-f64-unit ! cc-f64-fraction ! ;

: cc-f80-allocate ( significand sign-exponent -- bits )
  [lit] 16 cc-alloc dup >r [lit] 8 + ! r@ ! r> ;
: cc-f80-round ( -- bits )
  cc-f64-e @ [lit] 0 [lit] 16446 - < if, [lit] 0 [lit] 0 cc-f80-allocate exit, then,
  cc-f64-e @ [lit] 0 [lit] 16446 - = if,
    cc-f64-n cc-f64-d cc-f64-bi-compare 0= if, [lit] 0 else, [lit] 1 then,
    [lit] 0 cc-f80-allocate exit,
  then,
  cc-f64-e @ [lit] 0 [lit] 16382 - < if,
    cc-f64-e @ [lit] 16445 + cc-f64-quotient
    cc-f64-q @ dup 0< if, [lit] 1 else, [lit] 0 then, cc-f80-allocate exit,
  then,
  [lit] 63 cc-f64-quotient
  cc-f64-q-carry @ if, 2^63 cc-f64-q ! [lit] 1 cc-f64-e +! then,
  cc-f64-e @ [lit] 16383 > if, 2^63 [lit] 32767 cc-f80-allocate exit, then,
  cc-f64-q @ cc-f64-e @ [lit] 16383 + cc-f80-allocate ;
\ Round N/D * 2^e, with N/D in [1,2), once to the selected format.
: cc-f64-round ( -- bits )
  cc-f64-format @ [lit] 16 = if, cc-f80-round exit, then,
  cc-f64-emin @ cc-f64-fraction @ - 1- >r
  cc-f64-e @ r@ < if, r> drop [lit] 0 exit, then,
  cc-f64-e @ r> = if,
    \ Exactly half the minimum subnormal rounds to even zero.
    cc-f64-n cc-f64-d cc-f64-bi-compare 0= if,
      [lit] 0 else, [lit] 1 then, exit,
  then,
  cc-f64-e @ cc-f64-emin @ < if,
    cc-f64-e @ cc-f64-emin @ - cc-f64-fraction @ + cc-f64-quotient
    cc-f64-q @ exit,
  then,
  cc-f64-fraction @ cc-f64-quotient
  cc-f64-q @ cc-f64-unit @ [lit] 2 * = if,
    cc-f64-q @ [lit] 2 / cc-f64-q ! [lit] 1 cc-f64-e +!
  then,
  cc-f64-e @ cc-f64-emax @ > if, cc-f64-overflow then,
  cc-f64-e @ cc-f64-emax @ + cc-f64-unit @ *
  cc-f64-q @ cc-f64-unit @ - + ;

: cc-f64-decode ( address length -- bits )
  cc-f64-spelling
  cc-f64-n @ 0= if,
    cc-f64-format @ [lit] 16 = if, [lit] 0 [lit] 0 cc-f80-allocate else, [lit] 0 then, exit,
  then,
  cc-f64-hex @ if,
    cc-f64-normalize
    cc-f64-exponent @ cc-f64-fractional @ - cc-f64-e +! cc-f64-round exit,
  then,
  cc-f64-exponent @ cc-f64-fractional @ - cc-f64-scale !
  cc-f64-significant @ cc-f64-scale @ + 1- cc-f64-order !
  cc-f64-order @ cc-f64-format @ [lit] 16 = if, [lit] 4932 else, [lit] 308 then, > if,
    cc-f64-format @ [lit] 16 = if, 2^63 [lit] 32767 cc-f80-allocate exit, then,
    cc-f64-overflow
  then,
  cc-f64-order @ cc-f64-format @ [lit] 16 = if, [lit] 0 [lit] 4951 - else, [lit] 0 [lit] 324 - then, < if,
    cc-f64-format @ [lit] 16 = if, [lit] 0 [lit] 0 cc-f80-allocate else, [lit] 0 then, exit,
  then,
  cc-f64-scale @ 0< if,
    cc-f64-d [lit] 0 cc-f64-scale @ - cc-f64-bi-ten-power
  else, cc-f64-n cc-f64-scale @ cc-f64-bi-ten-power then,
  cc-f64-normalize cc-f64-round ;

: cc-f64-decimal ( address length format -- bits )
  dup [lit] 16 = cc-f64-allow-hex ! cc-f64-use cc-f64-decode ;
: cc-f64-parse ( address length -- bits ) [lit] 8 cc-f64-decimal ;

\ Constant arithmetic (125) uses the same ratio. An encoding splits into
\ a sign and integers M and E with magnitude M * 2^E. Each operation is
\ exact on those integers, so cc-f64-round is its only rounding step.
create cc-f64-t cc-f64-big-size allot
: cc-f64-bi-set ( value big -- )
  >r r@ cc-f64-bi-zero
  dup cc-f64-mask and r@ cc-f64-bi-append
  cc-f64-radix / r@ cc-f64-bi-append r> cc-f64-bi-trim ;
: cc-f64-bi-copy ( from to -- )
  cc-f64-bi-b ! cc-f64-bi-a ! [lit] 0 cc-f64-bi-i !
  begin, cc-f64-bi-i @ cc-f64-bi-a @ @ > 0= while,
    cc-f64-bi-a @ cc-f64-bi-i @ [lit] 8 * + @
    cc-f64-bi-b @ cc-f64-bi-i @ [lit] 8 * + !
    [lit] 1 cc-f64-bi-i +!
  repeat, ;
: cc-f64-bi-add ( a b -- )
  cc-f64-bi-b ! cc-f64-bi-a !
  [lit] 0 cc-f64-bi-carry ! [lit] 0 cc-f64-bi-i !
  begin,
    cc-f64-bi-i @ cc-f64-bi-a @ @ < cc-f64-bi-i @ cc-f64-bi-b @ @ < or
  while,
    cc-f64-bi-a @ cc-f64-bi-i @ cc-f64-bi-get
    cc-f64-bi-b @ cc-f64-bi-i @ cc-f64-bi-get + cc-f64-bi-carry @ +
    dup cc-f64-radix / cc-f64-bi-carry ! cc-f64-mask and
    cc-f64-bi-i @ cc-f64-bi-a @ @ < if,
      cc-f64-bi-a @ cc-f64-bi-i @ cc-f64-bi-cell !
    else, cc-f64-bi-a @ cc-f64-bi-append then,
    [lit] 1 cc-f64-bi-i +!
  repeat,
  cc-f64-bi-carry @ if,
    cc-f64-bi-carry @ cc-f64-bi-a @ cc-f64-bi-append
  then, ;
\ Multiply by a full cell in two 32-bit halves: big*hi*2^32 + big*lo.
: cc-f64-bi-times ( big value -- )
  over cc-f64-t cc-f64-bi-copy
  cc-f64-t over cc-f64-radix / [lit] 0 cc-f64-bi-muladd
  cc-f64-t cc-f64-bi-trim cc-f64-t [lit] 32 cc-f64-bi-shift
  over swap cc-f64-mask and [lit] 0 cc-f64-bi-muladd
  dup cc-f64-bi-trim cc-f64-t cc-f64-bi-add ;
: cc-f64-power ( n -- 2^n )
  [lit] 1 swap begin, dup while, swap [lit] 2 * swap 1- repeat, drop ;

: cc-f64-negative? ( bits -- flag )
  cc-f64-format @ [lit] 16 = if, [lit] 8 + @ then,
  cc-f64-sign @ and 0= 0= ;
\ A zero exponent field reads as field one without the hidden unit.
: cc-f64-unpack ( bits -- significand exponent )
  cc-f64-format @ [lit] 16 = if,
    dup @ swap [lit] 8 + @ [lit] 32767 and dup 0= if, drop [lit] 1 then,
    [lit] 16446 - exit,
  then,
  cc-f64-sign @ 1- and
  dup cc-f64-unit @ 1- and swap cc-f64-unit @ /
  dup if, swap cc-f64-unit @ + swap else, drop [lit] 1 then,
  cc-f64-emax @ - cc-f64-fraction @ - ;
\ Round N/D * 2^exponent and apply the sign; zero keeps its sign.
: cc-f64-pack ( exponent negative? -- bits )
  >r cc-f64-n @ if,
    cc-f64-normalize cc-f64-e +! cc-f64-round
  else, drop cc-f64-format @ [lit] 16 = if, [lit] 0 [lit] 0 cc-f80-allocate else, [lit] 0 then, then,
  r> if,
    cc-f64-format @ [lit] 16 = if,
      dup [lit] 8 + dup @ [lit] 32768 or swap !
    else, cc-f64-sign @ or then,
  then, ;
: cc-f64-one-denominator [lit] 1 cc-f64-d cc-f64-bi-set ;

\ An integer is its own ratio; the minimum signed value negates to its
\ unsigned magnitude.
: cc-f64-integer ( value signed? format -- bits )
  cc-f64-use
  over 0< and dup >r if, [lit] 0 swap - then,
  cc-f64-n cc-f64-bi-set cc-f64-one-denominator
  [lit] 0 r> cc-f64-pack ;
: cc-f64-third ( a b c -- a b c a ) >r over r> swap ;
variable cc-f80-resize-sign
variable cc-f80-resize-nan
: cc-f64-resize ( bits from to -- bits )
  dup [lit] 16 = cc-f64-third [lit] 16 <> and if,
    >r dup >r cc-f64-use
    dup cc-f64-negative? cc-f80-resize-sign !
    dup cc-f64-sign @ 1- and cc-f64-unit @ /
    cc-f64-emax @ [lit] 2 * 1+ = if,
      cc-f64-unit @ 1- and 0= if, 2^63 else, [lit] 13835058055282163712 then,
      cc-f80-resize-sign @ if, [lit] 65535 else, [lit] 32767 then,
      r> drop r> drop cc-f80-allocate exit,
    then, r> r>
  then,
  over [lit] 16 = over [lit] 16 <> and if,
    cc-f64-third [lit] 8 + @ [lit] 32767 and [lit] 32767 = if,
      >r drop dup [lit] 8 + @ [lit] 32768 and cc-f80-resize-sign !
      @ 2^63 <> cc-f80-resize-nan ! r> dup cc-f64-use
      [lit] 4 = if,
        cc-f80-resize-nan @ if, [lit] 2143289344 else, [lit] 2139095040 then,
      else,
        cc-f80-resize-nan @ if, [lit] 9221120237041090560 else, [lit] 9218868437227405312 then,
      then,
      cc-f80-resize-sign @ if, cc-f64-sign @ or then, exit,
    then,
  then,
  >r cc-f64-use
  dup cc-f64-negative? swap cc-f64-unpack
  swap cc-f64-n cc-f64-bi-set cc-f64-one-denominator
  swap r> cc-f64-use cc-f64-pack ;

variable cc-f64-a-negative
variable cc-f64-a-m
variable cc-f64-a-e
variable cc-f64-b-negative
variable cc-f64-b-m
variable cc-f64-b-e
: cc-f64-operands ( left right -- )
  dup cc-f64-negative? cc-f64-b-negative !
  cc-f64-unpack cc-f64-b-e ! cc-f64-b-m !
  dup cc-f64-negative? cc-f64-a-negative !
  cc-f64-unpack cc-f64-a-e ! cc-f64-a-m ! ;
: cc-f64-sign-of-product ( -- negative? )
  cc-f64-a-negative @ cc-f64-b-negative @ <> ;
: cc-f64-product ( -- bits )
  cc-f64-a-m @ cc-f64-n cc-f64-bi-set cc-f64-n cc-f64-b-m @ cc-f64-bi-times
  cc-f64-one-denominator
  cc-f64-a-e @ cc-f64-b-e @ + cc-f64-sign-of-product cc-f64-pack ;
: cc-f64-ratio ( -- bits )
  cc-f64-b-m @ 0= if, [lit] 124 cc-die then,
  cc-f64-a-m @ cc-f64-n cc-f64-bi-set cc-f64-b-m @ cc-f64-d cc-f64-bi-set
  cc-f64-a-e @ cc-f64-b-e @ - cc-f64-sign-of-product cc-f64-pack ;
\ Align both magnitudes to the smaller exponent; D holds the right one.
\ Exact cancellation is +0 under round to nearest; -0 + -0 stays -0.
: cc-f64-sum ( -- bits )
  cc-f64-a-e @ cc-f64-b-e @ 2dup > if, swap then, drop >r
  cc-f64-a-m @ cc-f64-n cc-f64-bi-set cc-f64-n cc-f64-a-e @ r@ - cc-f64-bi-shift
  cc-f64-b-m @ cc-f64-d cc-f64-bi-set cc-f64-d cc-f64-b-e @ r@ - cc-f64-bi-shift
  cc-f64-a-negative @ cc-f64-b-negative @ = if,
    cc-f64-n cc-f64-d cc-f64-bi-add cc-f64-a-negative @
  else,
    cc-f64-n cc-f64-d cc-f64-bi-compare dup 0= if,
      drop cc-f64-n cc-f64-bi-zero [lit] 0
    else, 0< if,
      cc-f64-d cc-f64-n cc-f64-bi-subtract cc-f64-d cc-f64-n cc-f64-bi-copy
      cc-f64-b-negative @
    else,
      cc-f64-n cc-f64-d cc-f64-bi-subtract cc-f64-a-negative @
    then, then,
  then,
  cc-f64-one-denominator r> swap cc-f64-pack ;
\ Extended nonfinite constant results use canonical quiet NaNs, as GCC's
\ constant folder does; finite arithmetic still rounds one exact ratio.
: cc-f80-nan-signed ( negative? -- bits )
  if, [lit] 65535 else, [lit] 32767 then,
  [lit] 13835058055282163712 swap cc-f80-allocate ;
: cc-f80-nan [lit] 0 cc-f80-nan-signed ;
: cc-f80-inf ( negative? -- bits )
  if, [lit] 65535 else, [lit] 32767 then, 2^63 swap cc-f80-allocate ;
: cc-f80-zero ( negative? -- bits )
  if, [lit] 32768 else, [lit] 0 then, [lit] 0 swap cc-f80-allocate ;
: cc-f80-a-inf cc-f64-a-e @ [lit] 16321 = ;
: cc-f80-b-inf cc-f64-b-e @ [lit] 16321 = ;
: cc-f80-special-arith ( operator -- bits handled? )
  dup [char] / = if,
    drop cc-f80-a-inf cc-f80-b-inf and
    cc-f64-a-m @ cc-f64-b-m @ or 0= or if,
      cc-f64-sign-of-product cc-f80-nan-signed true exit, then,
    cc-f80-a-inf cc-f64-b-m @ 0= or if,
      cc-f64-sign-of-product cc-f80-inf true exit,
    then,
    cc-f80-b-inf if, cc-f64-sign-of-product cc-f80-zero true exit, then,
    [lit] 0 [lit] 0 exit,
  then,
  dup [char] * = if,
    drop cc-f80-a-inf cc-f64-b-m @ 0= and
    cc-f80-b-inf cc-f64-a-m @ 0= and or if,
      cc-f64-sign-of-product cc-f80-nan-signed true exit, then,
    cc-f80-a-inf cc-f80-b-inf or if,
      cc-f64-sign-of-product cc-f80-inf true exit,
    then, [lit] 0 [lit] 0 exit,
  then, drop
  cc-f80-a-inf cc-f80-b-inf and
  cc-f64-a-negative @ cc-f64-b-negative @ <> and if,
    cc-f80-nan true exit,
  then,
  cc-f80-a-inf if, cc-f64-a-negative @ cc-f80-inf true exit, then,
  cc-f80-b-inf if, cc-f64-b-negative @ cc-f80-inf true exit, then,
  [lit] 0 [lit] 0 ;
: cc-f64-arith ( left right operator format -- bits )
  cc-f64-use >r cc-f64-operands r>
  cc-f64-format @ [lit] 16 = if,
    cc-f80-a-inf cc-f64-a-m @ 2^63 <> and if,
      drop cc-f64-a-negative @ cc-f80-nan-signed exit,
    then,
    cc-f80-b-inf cc-f64-b-m @ 2^63 <> and if,
      drop cc-f64-b-negative @ cc-f80-nan-signed exit,
    then,
  then,
  dup [char] - = if, cc-f64-b-negative @ 0= cc-f64-b-negative ! then,
  cc-f64-format @ [lit] 16 = if,
    dup cc-f80-special-arith if, nip exit, then, drop
  then,
  dup [char] * = if, drop cc-f64-product exit, then,
  dup [char] / = if, drop cc-f64-ratio exit, then,
  drop cc-f64-sum ;
\ Truncate toward zero. fits? is false when the magnitude needs more
\ than 64 bits; the caller applies the destination type's range.
: cc-f64-truncate ( bits format -- magnitude negative? fits? )
  cc-f64-use dup cc-f64-negative? >r cc-f64-unpack
  dup 0< if,
    [lit] 0 swap - dup [lit] 64 < if,
      cc-f64-power /
    else, 2drop [lit] 0 then,
    r> true exit,
  then,
  dup [lit] 63 > if, 2drop [lit] 0 r> [lit] 0 exit, then,
  cc-f64-power 2dup * dup >r swap / = r> swap r> swap ;

' cc-f64-decimal is cc-fp-decimal-fwd
' cc-f64-integer is cc-fp-integer-fwd
' cc-f64-resize is cc-fp-resize-fwd
' cc-f64-arith is cc-fp-arith-fwd
' cc-f64-truncate is cc-fp-truncate-fwd
