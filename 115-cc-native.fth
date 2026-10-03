\ 115-cc-native.fth — opt-in LP64 bootstrap declaration parser.
\ The legacy M2-compatible parser remains the default. Native mode uses
\ LP64 object layout and a private, all-stack call ABI within its image.
\ TinyCC built by this compiler emits its own standard target ABI.

: cc-npick ( x_n ... x_0 n -- x_n ... x_0 x_n )
  dup 0= if, drop dup exit, then,
  1- swap >r cc-npick r> swap ;
: cc-nminus-rot rot rot ;
: cc-nmax 2dup < if, swap then, drop ;
: cc-ncopy ( src dst n -- )
  begin, dup while,
    1- >r over r@ + c@ over r@ + c! r>
  repeat, drop 2drop ;

variable cc-nctx
[lit] 208 constant cc-nctx-bytes
: nc-ty     cc-nctx @ ;
: nc-desc   cc-nctx @ [lit] 8 + ;
: nc-name   cc-nctx @ [lit] 16 + ;
: nc-nlen   cc-nctx @ [lit] 24 + ;
: nc-array  cc-nctx @ [lit] 32 + ;
: nc-inner  cc-nctx @ [lit] 40 + ;
: nc-func   cc-nctx @ [lit] 48 + ;
: nc-params cc-nctx @ [lit] 56 + ;
: nc-td     cc-nctx @ [lit] 120 + ;
: nc-static cc-nctx @ [lit] 128 + ;
: nc-top    cc-nctx @ [lit] 136 + ;
: nc-base   cc-nctx @ [lit] 144 + ;
: nc-sdesc  cc-nctx @ [lit] 152 + ;
: nc-id     cc-nctx @ [lit] 160 + ;
: nc-slot   cc-nctx @ [lit] 168 + ;
: nc-extern cc-nctx @ [lit] 176 + ;
: nc-bound-mask cc-nctx @ [lit] 184 + ;
: nc-base-array cc-nctx @ [lit] 192 + ;
: nc-base-inner cc-nctx @ [lit] 200 + ;
: cc-nzero ( a n -- )
  begin, dup while, 1- 2dup + [lit] 0 swap c! repeat, 2drop ;
: cc-ncontext
  cc-nctx-bytes cc-alloc dup cc-nctx ! cc-nctx-bytes cc-nzero ;
: cc-nalign ( n alignment -- n' )
  dup [lit] 0 <= if, drop [lit] 1 then,
  dup >r 1- + r@ / r> * ;
: cc-nsize ( ty desc -- n )
  over ty-base ty-struct = [lit] 2 cc-npick ty-ptr 0= and if,
    dup 0= if, [lit] 210 cc-die then, nip cc-sd-total-size
  else, drop ty-size then, ;
: cc-nalignment ( ty desc -- n )
  over ty-base ty-struct = [lit] 2 cc-npick ty-ptr 0= and if,
    nip cc-sd-align
  else, drop ty-align then, ;

\ Tags live in their own namespace, so typedef struct T T is unambiguous.
variable cc-ntag-a
variable cc-ntag-u
: cc-nfind-tag ( a u -- id|-1 )
  cc-ntag-u ! cc-ntag-a !
  cc-sym-count @
  begin, dup while,
    1-
    dup cc-sym-kind-of sk-struct = if,
      dup cc-sym-name-len cell[] @ cc-ntag-u @ = if,
        dup cc-sym-name-addr cell[] @ cc-ntag-a @ cc-ntag-u @ bytes-eq if,
          exit,
        then,
      then,
    then,
  repeat, drop true ;

: cc-native-type-start
  cc-tok-is-basic-type-kw? cc-qualifier? or
  kw-struct cc-tok-kw? or kw-union cc-tok-kw? or kw-enum cc-tok-kw? or
  kw-float cc-tok-kw? or kw-double cc-tok-kw? or
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if, drop else, cc-sym-kind-of sk-typedef = or then,
  then, ;
' cc-native-type-start is cc-native-type-start-fwd

: cc-ntypedef-check-noop ;
defer cc-ntypedef-check-fwd
' cc-ntypedef-check-noop is cc-ntypedef-check-fwd

\ A target may provide C90's omitted int base without changing native mode.
: cc-native-implicit-base-noop [lit] 0 ;
defer cc-native-implicit-base-fwd
' cc-native-implicit-base-noop is cc-native-implicit-base-fwd

defer cc-nbase-fwd

defer cc-naggregate-fwd

\ A target can retain enum provenance without changing its scalar encoding.
: cc-nenum-desc-default [lit] 0 ;
defer cc-nenum-desc-fwd
' cc-nenum-desc-default is cc-nenum-desc-fwd

\ Read an enum type and optionally install its enumerators.
: cc-nenum
  cc-next-token-keep
  tok-kind @ tk-ident = if, cc-next-token-keep then,
  [char] { cc-tok-punct? if,
    [lit] 0
    begin,
      cc-next-token-keep
      [char] } cc-tok-punct? 0= while,
      tok-kind @ tk-ident <> if, [lit] 190 cc-die then,
      tok-str-addr @ tok-str-len @ rot
      cc-next-token-keep
      [char] = cc-tok-punct? if, drop cc-parse-const else, cc-putback-token then,
      dup >r sk-enum swap ty-int [lit] 0 ty-make swap cc-sym-add drop
      r> 1+
      cc-next-token-keep
      [char] , cc-tok-punct? 0= if,
        [char] } cc-tok-punct? 0= if, [lit] 192 cc-die then,
        cc-putback-token
      then,
    repeat,
    drop
  else, cc-putback-token then,
  ty-int [lit] 0 ty-make cc-nenum-desc-fwd ;

\ The current token is a base type. Return encoded type and descriptor.
: cc-nbase
  cc-nctx @ 0= if, cc-ncontext then,
  [lit] 0 nc-base-array ! [lit] 0 nc-base-inner !
  begin, cc-qualifier? while, cc-next-token-keep repeat,
  cc-native-implicit-base-fwd if, exit, then,
  kw-struct cc-tok-kw? kw-union cc-tok-kw? or if,
    cc-naggregate-fwd exit,
  then,
  kw-enum cc-tok-kw? if, cc-nenum exit, then,
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if, [lit] 194 cc-die then,
    dup cc-sym-kind-of sk-typedef <> if, [lit] 195 cc-die then,
    cc-ntypedef-check-fwd
    dup cc-sym-val-of swap cc-sym-struct-desc-of exit,
  then,
  \ Stack: base unsigned? long-seen?; preserve all across token reads.
  ty-int [lit] 0 [lit] 0
  begin,
    kw-char cc-tok-kw? if, rot drop ty-char cc-nminus-rot then,
    kw-short cc-tok-kw? if, rot drop ty-short cc-nminus-rot then,
    kw-long cc-tok-kw? if, drop true rot drop ty-long cc-nminus-rot then,
    kw-void cc-tok-kw? if, rot drop ty-void cc-nminus-rot then,
    kw-float cc-tok-kw? if, rot drop ty-float cc-nminus-rot then,
    kw-double cc-tok-kw? if,
      dup if, rot drop ty-ldouble cc-nminus-rot else, rot drop ty-double cc-nminus-rot then,
    then,
    kw-unsigned cc-tok-kw? if, swap drop true swap then,
    cc-next-token-keep
    cc-tok-is-basic-type-kw? kw-float cc-tok-kw? or kw-double cc-tok-kw? or
  while, repeat,
  cc-putback-token drop
  over ty-float = [lit] 2 cc-npick ty-double = or
  [lit] 2 cc-npick ty-ldouble = or cc-native-float-types-fwd 0= and if,
    [lit] 214 cc-die
  then,
  if,
    dup ty-char = if, drop ty-uchar else,
    dup ty-short = if, drop ty-ushort else,
    dup ty-long = if, drop ty-ulong else,
    drop ty-uint then, then, then,
  then,
  [lit] 0 ty-make [lit] 0 ;
' cc-nbase is cc-nbase-fwd

\ The optional ABI layer records function-pointer signatures at this seam.
: cc-nfnptr-default ( extra-stars -- )
  drop cc-skip-fnptr-params ty-func [lit] 1 ty-make nc-ty ! ;
defer cc-nfnptr-fwd
' cc-nfnptr-default is cc-nfnptr-fwd
: cc-ndeclarator-check-noop ;
defer cc-ndeclarator-check-fwd
' cc-ndeclarator-check-noop is cc-ndeclarator-check-fwd

\ A named declarator is the bootstrap default. Prototype parameters may
\ opt into an abstract function-pointer declarator with no identifier.
: cc-nfnptr-name-default
  cc-expect-ident
  tok-str-addr @ nc-name ! tok-str-len @ nc-nlen ! ;
defer cc-nfnptr-name-fwd
' cc-nfnptr-name-default is cc-nfnptr-name-fwd

\ Parse array suffixes with the current '[' already read. The count and
\ element type are independent, including arrays of function pointers.
: cc-narray-suffix
  [char] [ cc-tok-punct? if,
    cc-next-token-keep
    [char] ] cc-tok-punct? if, true nc-array ! else,
      [lit] 1 nc-bound-mask !
      cc-putback-token cc-parse-const nc-array ! [char] ] cc-expect-punct-c
    then,
    cc-next-token-keep
    [char] [ cc-tok-punct? if,
      [lit] 2 nc-bound-mask +!
      cc-parse-const nc-inner ! [char] ] cc-expect-punct-c
      cc-next-token-keep
    then,
  then, ;

: cc-nfunction-suffix
  \ An array may contain pointers to functions, never functions themselves.
  nc-array @ if, [lit] 238 cc-die then,
  true nc-func !
  nc-params cc-lex-mark
  cc-skip-fnptr-params
  cc-next-token-keep ;

\ A grouped declarator distinguishes (*f()) (function returning a pointer)
\ from (*f)() and (*f[N])() (a pointer or array of pointers to functions).
\ Stars inside the group belong to the object only when no outer function
\ suffix follows. General pointers to arrays still lack a representation.
: cc-ngrouped-declarator
  cc-count-stars >r
  cc-nfnptr-name-fwd
  cc-next-token-keep
  lparen cc-tok-punct? if,
    nc-nlen @ 0= if, [lit] 203 cc-die then,
    r> nc-ty +!
    cc-nfunction-suffix
    [char] ) cc-tok-punct? 0= if, [lit] 143 cc-die then,
    cc-next-token-keep
    lparen cc-tok-punct? [char] [ cc-tok-punct? or if, [lit] 238 cc-die then,
    exit,
  then,
  cc-narray-suffix
  [char] ) cc-tok-punct? 0= if, [lit] 143 cc-die then,
  cc-next-token-keep
  lparen cc-tok-punct? if,
    r@ 0= if,
      r> drop
      nc-array @ if, [lit] 238 cc-die then,
      cc-nfunction-suffix
    else,
      r> 1- cc-nfnptr-fwd
      cc-next-token-keep
      lparen cc-tok-punct? [char] [ cc-tok-punct? or if, [lit] 238 cc-die then,
    then,
  else,
    r@ nc-array @ or [char] [ cc-tok-punct? and if, [lit] 238 cc-die then,
    r> nc-ty +!
  then, ;

\ Declarator after nc-base/nc-sdesc. Function parameter tokens are saved
\ so a definition can return and install parameter names after classification.
: cc-ndeclarator
  cc-skip-qualifiers
  nc-base @ cc-count-stars + nc-ty !
  nc-sdesc @ nc-desc !
  [lit] 0 nc-name ! [lit] 0 nc-nlen !
  [lit] 0 nc-array ! [lit] 0 nc-inner ! [lit] 0 nc-func !
  [lit] 0 nc-bound-mask !
  cc-next-token-keep
  lparen cc-tok-punct? if,
    cc-ngrouped-declarator
  else,
    tok-kind @ tk-ident = if,
      tok-str-addr @ nc-name ! tok-str-len @ nc-nlen !
      cc-next-token-keep
    then,
  then,
  cc-narray-suffix
  lparen cc-tok-punct? if, cc-nfunction-suffix then,
  cc-ndeclarator-check-fwd ;

\ Add a field, including flattened anonymous aggregate members.
: cc-nadd-field ( desc -- )
  nc-inner @ if, [lit] 213 cc-die then,
  dup cc-sd-field-count over swap cc-sd-field-rec >r
  nc-name @ r@ cc-sf-set-name-addr
  nc-nlen @ r@ cc-sf-set-name-len
  nc-ty @ r@ cc-sf-set-type
  nc-desc @ r@ cc-sf-set-desc
  nc-array @ r@ cc-sf-set-array-len
  nc-ty @ nc-desc @ cc-nalignment
  over cc-sd-align over < if, dup [lit] 2 cc-npick cc-sd-set-align then,
  over cc-sd-total-size swap cc-nalign
  over cc-sd-union? if, drop [lit] 0 then,
  dup r> cc-sf-set-offset
  nc-ty @ nc-desc @ cc-nsize
  nc-array @ [lit] 0 > if, nc-array @ * then,
  nc-inner @ [lit] 0 > if, nc-inner @ * then,
  + over cc-sd-total-size cc-nmax over cc-sd-set-total-size
  dup cc-sd-field-count 1+ swap cc-sd-set-field-count ;

\ Anonymous aggregate promotion copies records and adds the enclosing offset.
: cc-npromote-fields ( child parent -- )
  dup cc-sd-field-count 1- over swap cc-sd-field-rec cc-sf-offset >r
  dup cc-sd-field-count 1- over cc-sd-set-field-count
  over cc-sd-field-count [lit] 0
  begin, 2dup > while,
    dup [lit] 4 cc-npick swap cc-sd-field-rec
    [lit] 3 cc-npick dup cc-sd-field-count swap over cc-sd-field-rec
    swap drop
    cc-sd-record-bytes cc-ncopy
    [lit] 2 cc-npick dup cc-sd-field-count cc-sd-field-rec
    dup cc-sf-offset r@ + swap cc-sf-set-offset
    [lit] 2 cc-npick dup cc-sd-field-count 1+ swap cc-sd-set-field-count
    1+
  repeat, 2drop 2drop r> drop ;

\ A target may add member syntax while retaining the shared declarator.
: cc-nmember-default ( desc -- )
  nc-func @ if, [lit] 238 cc-die then,
  dup cc-nadd-field
  nc-nlen @ 0= if, nc-desc @ swap cc-npromote-fields else, drop then, ;
defer cc-nmember-fwd
' cc-nmember-default is cc-nmember-fwd

: cc-naggregate
  kw-union cc-tok-kw? >r
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ 2dup cc-nfind-tag
    dup 0< if,
      drop cc-sd-alloc dup >r
      sk-struct swap [lit] 0 swap cc-sym-add drop r>
    else, nip nip cc-sym-val-of then,
    cc-next-token-keep
  else, cc-sd-alloc then,
  r> over cc-sd-set-union
  [char] { cc-tok-punct? if,
    [lit] 1 over cc-sd-set-align
    cc-nctx @ >r cc-ncontext
    begin,
      cc-next-token-keep
      [char] } cc-tok-punct? 0= while,
      cc-nbase-fwd nc-sdesc ! nc-base !
      begin,
        cc-ndeclarator
        dup cc-nmember-fwd
        [char] , cc-tok-punct?
      while, repeat,
      [char] ; cc-tok-punct? 0= if, [lit] 58 cc-die then,
    repeat,
    dup cc-sd-total-size over cc-sd-align cc-nalign over cc-sd-set-total-size
    r> cc-nctx !
  else, cc-putback-token then,
  ty-struct [lit] 0 ty-make swap ;
' cc-naggregate is cc-naggregate-fwd

\ Type queries preserve the enclosing declaration's array base shape.
: cc-native-type-shape-default + ;
defer cc-native-type-shape-fwd
' cc-native-type-shape-default is cc-native-type-shape-fwd
: cc-native-type-name
  cc-nctx @ 0= if, cc-ncontext then,
  nc-base-array @ >r nc-base-inner @ >r
  [lit] 0 cc-type-name-array ! [lit] 0 cc-type-name-inner !
  cc-nbase cc-cast-desc ! cc-skip-qualifiers cc-count-stars
  cc-native-type-shape-fwd
  r> nc-base-inner ! r> nc-base-array ! ;
' cc-native-type-name is cc-native-type-name-fwd

defer cc-native-function-fwd

: cc-nobject-size
  nc-ty @ nc-desc @ cc-nsize
  nc-array @ [lit] 0 > if, nc-array @ * then,
  nc-inner @ [lit] 0 > if, nc-inner @ * then, ;

: cc-ninstall-symbol ( kind slot -- id )
  >r >r nc-name @ nc-nlen @ r> nc-ty @ r> cc-sym-add
  nc-desc @ over cc-sym-set-struct-desc
  nc-array @ over cc-sym-set-array-len
  nc-inner @ over cc-sym-set-array-inner ;

: cc-ngstore ( value offset bytes -- )
  >r cc-globals-buf + r>
  begin, dup while,
    >r over [lit] 255 and over c!
    1+ swap [lit] 256 / swap r> 1-
  repeat, drop 2drop ;
: cc-nmove-tentative
  nc-slot @ cc-bss-flag >= if,
    cc-globals-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-globals-pos !
    cc-nobject-size cc-globals-alloc
    [lit] 0
    begin, dup cc-gfixup-count @ < while,
      dup cc-gfixup-slot cell[] @ nc-slot @ = if,
        over over cc-gfixup-slot cell[] !
      then, 1+
    repeat, drop
    dup nc-id @ cc-sym-val cell[] ! nc-slot !
  then, ;

: cc-native-init-noop ;
defer cc-native-init-prepare-fwd
defer cc-native-init-fwd
defer cc-native-init-entry-fwd
defer cc-native-init-finish-fwd
' cc-native-init-noop is cc-native-init-prepare-fwd
' cc-native-init-noop is cc-native-init-entry-fwd
' cc-native-init-noop is cc-native-init-finish-fwd
: cc-native-scalar-init
  nc-top @ nc-static @ or if,
    cc-nmove-tentative
    cc-parse-const nc-slot @ nc-ty @ ty-size cc-ngstore
  else,
    cc-parse-assign cc-emit-materialize
    nc-slot @ nc-ty @ cc-emit-store-local-typed
  then,
  cc-next-token-keep ;
' cc-native-scalar-init is cc-native-init-fwd

: cc-native-local-layout-default ( -- slots slot )
  cc-nobject-size [lit] 7 + [lit] 8 / dup cc-fn-local-count @ + 1- ;
defer cc-native-local-layout-fwd
' cc-native-local-layout-default is cc-native-local-layout-fwd

: cc-nobject
  [char] = cc-tok-punct? if, cc-native-init-prepare-fwd then,
  nc-name @ nc-nlen @ cc-sym-find nc-id !
  nc-top @ nc-static @ or if,
    nc-top @ 0= if, true nc-id ! then,
    nc-id @ 0< 0= if,
      nc-id @ cc-sym-kind-of sk-global = if,
        nc-id @ cc-sym-val-of nc-slot !
      else, true nc-id ! then,
    then,
    nc-id @ 0< if,
      [char] = cc-tok-punct? if,
        cc-globals-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-globals-pos !
        cc-nobject-size cc-globals-alloc
      else,
        cc-bss-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-bss-pos !
        cc-nobject-size cc-bss-alloc
      then,
      dup nc-slot ! sk-global swap cc-ninstall-symbol nc-id !
      cc-nobject-size nc-id @ cc-sym-set-object-size
    else,
      cc-nobject-size nc-id @ cc-sym-object-size-of > if,
        cc-bss-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-bss-pos !
        cc-nobject-size cc-bss-alloc
        [lit] 0
        begin, dup cc-gfixup-count @ < while,
          dup cc-gfixup-slot cell[] @ nc-slot @ = if,
            over over cc-gfixup-slot cell[] !
          then, 1+
        repeat, drop
        dup nc-id @ cc-sym-val cell[] ! nc-slot !
        cc-nobject-size nc-id @ cc-sym-set-object-size
      then,
      nc-ty @ nc-id @ cc-sym-type cell[] !
      nc-desc @ nc-id @ cc-sym-set-struct-desc
      nc-array @ nc-id @ cc-sym-set-array-len
      nc-inner @ nc-id @ cc-sym-set-array-inner
    then,
  else,
    cc-native-local-layout-fwd dup nc-slot !
    sk-local swap cc-ninstall-symbol nc-id !
    cc-fn-add-slots
  then,
  [char] = cc-tok-punct? if, cc-native-init-fwd then, ;

defer cc-nobject-fwd
' cc-nobject is cc-nobject-fwd

: cc-native-declaration ( top? -- )
  cc-nctx @ >r cc-ncontext nc-top !
  cc-decl-static @ nc-static ! cc-decl-extern @ nc-extern !
  kw-typedef cc-tok-kw? if,
    true nc-td ! cc-next-token-keep
  then,
  cc-nbase nc-sdesc ! nc-base !
  cc-next-token-keep
  [char] ; cc-tok-punct? if, r> cc-nctx ! exit, then,
  cc-putback-token
  begin,
    cc-ndeclarator
    nc-nlen @ 0= if, [lit] 203 cc-die then,
    nc-td @ if,
      nc-name @ nc-nlen @ sk-typedef [lit] 0 nc-ty @ cc-sym-add
      nc-desc @ over cc-sym-set-struct-desc
      nc-array @ over cc-sym-set-array-len
      nc-inner @ swap cc-sym-set-array-inner
    else,
      nc-func @ if,
        cc-native-function-fwd
        [char] } cc-tok-punct? if, r> cc-nctx ! exit, then,
      else, cc-nobject-fwd then,
    then,
    [char] , cc-tok-punct?
  while, repeat,
  [char] ; cc-tok-punct? 0= if, [lit] 205 cc-die then,
  r> cc-nctx ! ;
: cc-native-local-declaration [lit] 0 cc-native-declaration ;
' cc-native-local-declaration is cc-native-decl-fwd
