\ 118-cc-native-init.fth — bounded C initializers for the native bootstrap.
\ Scalar stores, brace lists, nested arrays/aggregates and character strings
\ are lowered by the Forth compiler. Static expressions use the expression
\ parser's constant-category guard; they run once before main. This avoids
\ a second relocation engine: ordinary global/function fixups serve both
\ executable expressions and initializers. No host compiler is involved.
\ Designators and more than two array dimensions are outside this profile.

variable cc-ni-frame
variable cc-ni-static
variable cc-ni-head
variable cc-ni-tail
variable cc-ni-entry-patch

: ni-type   cc-ni-frame @ ;
: ni-desc   cc-ni-frame @ [lit] 8 + ;
: ni-array  cc-ni-frame @ [lit] 16 + ;
: ni-inner  cc-ni-frame @ [lit] 24 + ;
: ni-offset cc-ni-frame @ [lit] 32 + ;
: ni-index  cc-ni-frame @ [lit] 40 + ;
: ni-brace  cc-ni-frame @ [lit] 48 + ;
: ni-nested cc-ni-frame @ [lit] 56 + ;

\ A target may represent a scalar as an opaque record (121: long double);
\ initializers treat it as one scalar leaf, never as a brace list.
: cc-ni-aggregate?
  ni-type @ ty-base ty-struct = ni-type @ ty-ptr 0= and
  ni-type @ ni-desc @ cc-opaque-scalar-fwd 0= and ;
: cc-ni-address ( offset -- )
  cc-ni-static @ if,
    nc-slot @ cc-emit-global-ref
  else, nc-slot @ cc-emit-lea-rdi-local then,
  dup if, cc-emit-add-rdi-imm32 else, drop then, ;
: cc-ni-count-rcx ( n -- )
  [lit] 185 cc-emit-byte cc-emit-4le ;
: cc-ni-mov-rsi-rdi
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 254 cc-emit-byte ;
: cc-ni-copy-bytes ( n -- )
  cc-ni-count-rcx [lit] 243 cc-emit-byte [lit] 164 cc-emit-byte ;
: cc-ni-zero-object
  [lit] 0 cc-ni-address
  cc-nobject-size cc-ni-count-rcx
  cc-emit-xor-rax-rax
  [lit] 243 cc-emit-byte [lit] 170 cc-emit-byte ;

\ The literal lexer retains escapes. Count exactly their decoded bytes.
: cc-ni-string-size ( a u -- n )
  [lit] 0 >r
  begin, dup [lit] 0 > while,
    over c@ backslash = over [lit] 1 > and if,
      over 1+ cc-decode-escape nip 1+
    else, [lit] 1 then,
    >r swap r@ + swap r> -
    r> 1+ >r
  repeat, 2drop r> ;

\ Before allocating an inferred array, count its outer brace elements.
\ Nested aggregates in inferred arrays require their own braces. Known-size
\ arrays additionally accept the ordinary brace-elided nested form.
variable cc-ni-scan-mark
variable cc-ni-scan-count
variable cc-ni-scan-depth
variable cc-ni-scan-have
variable cc-ni-scan-brace
: cc-ni-infer
  nc-array @ [lit] 0 < 0= if, exit, then,
  cc-lex-state-size cc-alloc dup cc-ni-scan-mark ! cc-lex-mark
  cc-next-token-keep
  [lit] 0 cc-ni-scan-brace !
  nc-inner @ 0= nc-ty @ ty-ptr 0= and
  nc-ty @ ty-size [lit] 1 = and [char] { cc-tok-punct? and if,
    cc-lex-state-size cc-alloc dup >r cc-lex-mark
    cc-next-token-keep
    tok-kind @ tk-str = if,
      true cc-ni-scan-brace ! r> drop
    else, r> cc-lex-reset then,
  then,
  tok-kind @ tk-str = if,
    nc-ty @ ty-ptr if, [lit] 220 cc-die then,
    nc-ty @ ty-size [lit] 1 <> if, [lit] 220 cc-die then,
    [lit] 0
    begin, tok-kind @ tk-str = while,
      tok-str-addr @ tok-str-len @ cc-ni-string-size +
      cc-next-token-keep
    repeat, 1+ nc-array !
    cc-ni-scan-brace @ if,
      [char] , cc-tok-punct? if, cc-next-token-keep then,
      [char] } cc-tok-punct? 0= if, [lit] 223 cc-die then,
    then,
  else,
    [char] { cc-tok-punct? 0= if, [lit] 220 cc-die then,
    [lit] 0 cc-ni-scan-count ! [lit] 0 cc-ni-scan-depth !
    [lit] 0 cc-ni-scan-have !
    begin,
      cc-next-token-keep
      tok-kind @ tk-eof = if, [lit] 221 cc-die then,
      [char] } cc-tok-punct? cc-ni-scan-depth @ 0= and if,
        cc-ni-scan-have @ if, [lit] 1 cc-ni-scan-count +! then,
        cc-ni-scan-count @ dup 0= if, [lit] 220 cc-die then, nc-array !
        cc-ni-scan-mark @ cc-lex-reset exit,
      then,
      [char] , cc-tok-punct? cc-ni-scan-depth @ 0= and if,
        cc-ni-scan-have @ 0= if, [lit] 221 cc-die then,
        [lit] 1 cc-ni-scan-count +! [lit] 0 cc-ni-scan-have !
      else,
        cc-ni-scan-have @ 0= if,
          nc-ty @ ty-base dup ty-struct = swap ty-array = or
          nc-ty @ ty-ptr 0= and nc-ty @ nc-desc @ cc-opaque-scalar-fwd 0= and if,
            [char] { cc-tok-punct? 0= if, [lit] 222 cc-die then,
          then,
          nc-inner @ if,
            [char] { cc-tok-punct? 0= if,
              tok-kind @ tk-str = nc-ty @ ty-ptr 0= and
              nc-ty @ ty-size [lit] 1 = and 0= if, [lit] 222 cc-die then,
            then,
          then,
        then,
        true cc-ni-scan-have !
        [char] { cc-tok-punct? lparen cc-tok-punct? or
        [char] [ cc-tok-punct? or if, [lit] 1 cc-ni-scan-depth +! then,
        [char] } cc-tok-punct? [char] ) cc-tok-punct? or
        [char] ] cc-tok-punct? or if, true cc-ni-scan-depth +! then,
        cc-ni-scan-depth @ [lit] 0 < if, [lit] 221 cc-die then,
      then,
    again,
  then,
  cc-ni-scan-mark @ cc-lex-reset ;
' cc-ni-infer is cc-native-init-prepare-fwd

defer cc-ni-value-fwd

\ Emit one complete (possibly concatenated) character string and copy its
\ decoded bytes. C permits a fixed char[N] string of exactly N non-NUL bytes.
: cc-ni-string
  cc-emit-jmp-rel32-placeholder >r
  cc-here-vaddr cc-out-pos @
  begin, tok-kind @ tk-str = while,
    tok-str-addr @ tok-str-len @ cc-emit-string-bytes
    true cc-out-pos +!
    cc-next-token-keep
  repeat,
  cc-out-pos @ swap -
  dup ni-array @ > if, [lit] 223 cc-die then,
  [lit] 0 cc-emit-byte
  1+ dup ni-array @ > if, drop ni-array @ then,
  r> cc-patch-rel32-to-here
  swap cc-emit-movabs-rdi-imm64 cc-ni-mov-rsi-rdi
  ni-offset @ cc-ni-address cc-ni-copy-bytes ;

: cc-value-static-init-default drop ;
defer cc-value-static-init-fwd
' cc-value-static-init-default is cc-value-static-init-fwd

: cc-ni-scalar
  cc-ni-aggregate? cc-ni-static @ and if, [lit] 219 cc-die then,
  cc-ni-static @ if, ni-type @ cc-value-static-init-fwd then,
  ni-offset @ cc-ni-address cc-emit-push-rdi
  cc-putback-token cc-parse-assign
  cc-ni-aggregate? if,
    cc-last-expr-type @ ty-base ty-struct <>
    cc-last-expr-type @ ty-ptr [lit] 0 <> or
    cc-last-struct-desc @ ni-desc @ <> or if, [lit] 224 cc-die then,
    cc-ni-mov-rsi-rdi
    cc-emit-pop-rdi
    ni-type @ ni-desc @ cc-nsize cc-ni-copy-bytes
  else,
    cc-emit-materialize
    cc-last-expr-type @ cc-last-struct-desc @ ni-type @ ni-desc @ cc-value-shape-fwd
    cc-last-expr-type @ ni-type @ cc-value-init-fwd
    cc-emit-pop-rcx ni-type @ cc-emit-store-typed-via-rcx
  then,
  cc-next-token-keep ;

defer cc-ni-scalar-fwd
defer cc-ni-string-fwd
' cc-ni-scalar is cc-ni-scalar-fwd
' cc-ni-string is cc-ni-string-fwd

: cc-ni-child-count
  ni-array @ if, ni-array @ exit, then,
  ni-desc @ cc-sd-union? if, [lit] 1 else, ni-desc @ cc-sd-field-count then, ;

: cc-ni-field-default ( rec -- handled? ) drop [lit] 0 ;
defer cc-ni-field-fwd
' cc-ni-field-default is cc-ni-field-fwd

: cc-ni-child
  ni-array @ if,
    ni-type @ ni-desc @ ni-inner @ [lit] 0
    ni-type @ ni-desc @ cc-nsize
    ni-inner @ if, ni-inner @ * then,
    ni-index @ * ni-offset @ + true cc-ni-value-fwd
  else,
    ni-desc @ ni-index @ cc-sd-field-rec
    dup cc-ni-field-fwd if, drop exit, then,
    dup cc-sf-type over cc-sf-desc
    [lit] 2 cc-npick cc-sf-array-len
    [lit] 3 cc-npick cc-sf-array-inner
    [lit] 4 cc-npick cc-sf-offset ni-offset @ +
    true cc-ni-value-fwd drop
  then, ;

: cc-ni-list
  [char] { cc-tok-punct? ni-brace !
  ni-brace @ if, cc-next-token-keep then,
  [lit] 0 ni-index !
  begin,
    [char] } cc-tok-punct? 0=
    ni-index @ cc-ni-child-count < and
  while,
    cc-ni-child [lit] 1 ni-index +!
    [char] , cc-tok-punct? if,
      ni-brace @ ni-index @ cc-ni-child-count < or if,
        cc-next-token-keep
      else, exit, then,
    else,
      ni-brace @ if,
        [char] } cc-tok-punct? 0= if, [lit] 225 cc-die then,
      else, exit, then,
    then,
  repeat,
  ni-brace @ if,
    [char] } cc-tok-punct? 0= if, [lit] 226 cc-die then,
    cc-next-token-keep
  then, ;

\ Character-array strings may optionally have a single pair of braces.
: cc-ni-char-array
  tok-kind @ tk-str = if, cc-ni-string-fwd exit, then,
  [char] { cc-tok-punct? if,
    cc-lex-state-size cc-alloc dup >r cc-lex-mark
    cc-next-token-keep
    tok-kind @ tk-str = if,
      r> drop cc-ni-string-fwd
      [char] , cc-tok-punct? if, cc-next-token-keep then,
      [char] } cc-tok-punct? 0= if, [lit] 223 cc-die then,
      cc-next-token-keep exit,
    then,
    r> cc-lex-reset
  then,
  [char] { cc-tok-punct? ni-nested @ or 0= if, [lit] 225 cc-die then,
  cc-ni-list ;

: cc-ni-value ( ty desc array inner offset nested? -- )
  cc-ni-frame @ >r
  [lit] 64 cc-alloc dup cc-ni-frame ! [lit] 64 cc-nzero
  ni-nested ! ni-offset ! ni-inner ! ni-array ! ni-desc ! ni-type !
  \ Re-enter the existing array traversal for a recursively typed element.
  ni-array @ 0= ni-type @ ty-base ty-array = and
  ni-type @ ty-ptr 0= and if,
    ni-desc @ dup cc-ad-type ni-type !
    dup cc-ad-count ni-array ! dup cc-ad-inner ni-inner !
    cc-ad-desc ni-desc !
  then,
  ni-array @ [lit] 0 > if,
    ni-inner @ 0= ni-type @ ty-ptr 0= and
    ni-type @ ty-size [lit] 1 = and if,
      cc-ni-char-array
    else,
      [char] { cc-tok-punct? ni-nested @ or 0= if, [lit] 225 cc-die then,
      cc-ni-list
    then,
  else,
    cc-ni-aggregate? if,
      [char] { cc-tok-punct? ni-nested @ or if,
        cc-ni-list
      else, cc-ni-scalar-fwd then,
    else,
      [char] { cc-tok-punct? if,
        cc-next-token-keep
        ni-type @ ni-desc @ [lit] 0 [lit] 0 ni-offset @ true cc-ni-value-fwd
        [char] , cc-tok-punct? if, cc-next-token-keep then,
        [char] } cc-tok-punct? 0= if, [lit] 227 cc-die then,
        cc-next-token-keep
      else, cc-ni-scalar-fwd then,
    then,
  then,
  r> cc-ni-frame ! ;
' cc-ni-value is cc-ni-value-fwd

: cc-ni-queue ( vaddr -- )
  [lit] 16 cc-alloc dup >r !
  [lit] 0 r@ [lit] 8 + !
  cc-ni-tail @ if, r@ cc-ni-tail @ [lit] 8 + ! else, r@ cc-ni-head ! then,
  r> cc-ni-tail ! ;

: cc-native-initializer
  nc-top @ nc-static @ or cc-ni-static !
  cc-ni-static @ if,
    cc-emit-jmp-rel32-placeholder >r
    cc-here-vaddr cc-ni-queue
    true cc-native-static-init !
  else,
    nc-array @ nc-ty @ ty-base ty-struct = nc-ty @ ty-ptr 0= and or if,
      cc-ni-zero-object
    then,
  then,
  cc-next-token-keep
  nc-ty @ nc-desc @ nc-array @ nc-inner @ [lit] 0 [lit] 0 cc-ni-value
  cc-ni-static @ if,
    [lit] 0 cc-native-static-init !
    [lit] 195 cc-emit-byte
    r> cc-patch-rel32-to-here
  then, ;
' cc-native-initializer is cc-native-init-fwd

: cc-ni-entry
  [lit] 0 cc-ni-head ! [lit] 0 cc-ni-tail !
  cc-emit-call-rel32-placeholder cc-ni-entry-patch ! ;
' cc-ni-entry is cc-native-init-entry-fwd

: cc-ni-finish
  cc-ni-entry-patch @ cc-patch-rel32-to-here
  cc-ni-head @
  begin, dup while,
    [lit] 232 cc-emit-byte
    dup @ cc-here-vaddr [lit] 4 + - cc-emit-4le
    [lit] 8 + @
  repeat, drop
  [lit] 195 cc-emit-byte ;
' cc-ni-finish is cc-native-init-finish-fwd
