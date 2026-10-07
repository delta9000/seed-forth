\ 123-cc-object-program.fth — shared scalar C parser to ELF64 ET_REL.
\ Stable object records outlive parser scopes: static locals never inherit
\ an unrelated object when cc-sym IDs are reused. All relocations name these
\ records until081 assigns its own stable symbol IDs at serialization.
variable cc-sysv-object-mode
[lit] 0 cc-sysv-object-mode !
[lit] 4096 constant cc-om-default-cap
create cc-om-default-records cc-om-default-cap [lit] 128 * allot
variable cc-om-limit
variable cc-om-buffer
cc-om-default-cap cc-om-limit !
cc-om-default-records cc-om-buffer !
: cc-om-cap ( -- entries ) cc-om-limit @ ;
: cc-om-records ( -- address ) cc-om-buffer @ ;
\ Complete original insn-output.c needs 10,559 stable records; round to 10,752.
\ Keep the default table and opt in explicitly to a fixed mapped table.
[lit] 10752 constant cc-om-direct-cap
variable cc-om-direct-base
: cc-om-default-workspace ( -- )
  cc-om-default-records cc-om-buffer ! cc-om-default-cap cc-om-limit ! ;
: cc-om-direct-workspace ( -- )
  cc-om-direct-base @ 0= if,
    cc-om-direct-cap [lit] 128 * [lit] 245 cc-workspace-map
    cc-om-direct-base !
  then,
  cc-om-direct-base @ cc-om-buffer ! cc-om-direct-cap cc-om-limit ! ;
variable cc-om-count
\ Reject invalid IDs before subtraction or multiplication in either workspace.
: cc-om-record ( id -- address )
  dup [lit] 1 < if, [lit] 245 cc-die then,
  dup cc-om-cap [lit] 245 cc-check-cap
  1- [lit] 128 * cc-om-records + ;
: om-name cc-om-record ;
: om-nlen cc-om-record [lit] 8 + ;
: om-bind cc-om-record [lit] 16 + ;
: om-kind cc-om-record [lit] 24 + ;
: om-section cc-om-record [lit] 32 + ;
: om-offset cc-om-record [lit] 40 + ;
: om-size cc-om-record [lit] 48 + ;
: om-align cc-om-record [lit] 56 + ;
: om-type cc-om-record [lit] 64 + ;
: om-desc cc-om-record [lit] 72 + ;
: om-array cc-om-record [lit] 80 + ;
: om-inner cc-om-record [lit] 88 + ;
: om-flags cc-om-record [lit] 96 + ;
: om-output cc-om-record [lit] 104 + ;
: om-symbol cc-om-record [lit] 112 + ;
\ Lookup by name goes through a hash table (cc-name-hash, 030):
\ cc-om-bucket holds the newest record whose name hashes there (0 for
\ none), and cc-om-hnext the next older record in the same bucket.
create cc-om-bucket  cc-name-buckets [lit] 8 * allot
create cc-om-hnext   cc-om-direct-cap 1+ [lit] 8 * allot
: cc-om-hash-reset ( -- )
  [lit] 0 begin, dup cc-name-buckets < while,
    [lit] 0 over cc-om-bucket cell[] !  1+
  repeat, drop ;
: cc-om-link ( id -- )
  dup om-name @ over om-nlen @ cc-name-hash cc-om-bucket cell[]   ( id b )
  2dup @ swap cc-om-hnext cell[] !
  ! ;
\ Flags:1 extern-only,2 tentative,4 initialized,8 block static,
\ 16 referenced,32 anonymous. A later definition replaces extern-only.
: cc-om-flag ( flag record -- ) om-flags dup @ rot or swap ! ;
: cc-om-new ( name length binding kind -- record )
  cc-om-count @ 1+ cc-om-cap [lit] 245 cc-check-cap
  [lit] 1 cc-om-count +! cc-om-count @ >r
  r@ cc-om-record [lit] 128 cc-nzero
  r@ om-kind ! r@ om-bind ! r@ om-nlen ! r@ om-name !
  r@ cc-om-link
  [lit] 1 r@ om-align ! r> ;
variable cc-om-find-name
variable cc-om-find-length
\ The oldest record of that name that is neither a block static nor
\ anonymous: the walk along the name's bucket runs newest first, so the
\ last match it meets is the one.
: cc-om-find ( name length -- record|0 )
  cc-om-find-length ! cc-om-find-name !
  [lit] 0                                                ( found )
  cc-om-find-name @ cc-om-find-length @ cc-name-hash cc-om-bucket cell[] @
  begin, dup while,                                      ( found id )
    dup om-flags @ [lit] 40 and 0= if,
      dup om-nlen @ cc-om-find-length @ = if,
        dup om-name @ cc-om-find-name @ cc-om-find-length @ bytes-eq if,
          nip dup
        then,
      then,
    then, cc-om-hnext cell[] @
  repeat, drop ;
: cc-om-from-symbol ( symbol -- record )
  dup cc-sym-kind-of sk-global = if, cc-sym-val-of exit, then,
  dup cc-sym-name-addr cell[] @ swap cc-sym-name-len cell[] @ cc-om-find
  dup 0= if, [lit] 238 cc-die then, ;

\ The unused final record cell retains an implicit declaration's stable
\ identity even after its block-scoped parser symbol has disappeared.
: om-implicit cc-om-record [lit] 120 + ;
: cc-sysv-object-implicit ( id -- )
  cc-sysv-object-mode @ 0= if, drop exit, then,
  dup cc-sym-name-addr cell[] @ over cc-sym-name-len cell[] @ cc-om-find
  dup 0= if,
    drop dup cc-sym-name-addr cell[] @ over cc-sym-name-len cell[] @
    cc-obj-global cc-obj-func cc-om-new
  then,
  dup om-kind @ cc-obj-func <> if, [lit] 237 cc-die then,
  swap cc-sysv-implicit-symbol swap om-implicit ! ;
' cc-sysv-object-implicit is cc-sysv-implicit-declared-fwd

variable cc-om-relocations
: cc-om-reloc ( section offset kind record addend -- )
  [lit] 48 cc-alloc >r
  r@ [lit] 40 + ! dup [lit] 16 swap cc-om-flag
  r@ [lit] 32 + ! r@ [lit] 24 + ! r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-om-relocations @ r@ ! r> cc-om-relocations ! ;
: cc-om-reference ( record -- )
  >r cc-obj-text cc-out-pos @ [lit] 2 + cc-obj-r64 r> [lit] 0 cc-om-reloc
  [lit] 0 cc-emit-movabs-rdi-imm64 ;
: cc-sysv-object-function-desc
  cc-sysv-object-mode @ cc-expr-unevaluated @ 0= and if,
    dup cc-om-from-symbol >r
    cc-obj-text cc-out-pos @ [lit] 2 + cc-obj-r64 r> [lit] 0 cc-om-reloc
  then, cc-sysv-function-desc ;
' cc-sysv-object-function-desc is cc-native-function-desc-fwd

create cc-om-string-name s, .Lstring
: cc-om-string-piece ( address length -- )
  begin, dup while,
    over c@ backslash = over [lit] 1 > and if,
      over 1+ cc-decode-escape swap cc-obj-byte 1+
      >r swap r@ + swap r> -
    else,
      over c@ cc-obj-byte swap 1+ swap 1-
    then,
  repeat, 2drop ;
: cc-om-string ( -- record )
  cc-obj-current @ >r cc-obj-rodata cc-obj-use
  cc-om-string-name [lit] 8 cc-obj-local cc-obj-object cc-om-new
  [lit] 32 over om-flags ! cc-obj-rodata over om-section !
  cc-obj-here over om-offset !
  begin, tok-kind @ tk-str = while,
    tok-str-addr @ tok-str-len @ cc-om-string-piece cc-next-token-keep
  repeat,
  [lit] 0 cc-obj-byte
  cc-obj-here over om-offset @ - over om-size !
  r> cc-obj-use ;
: cc-sysv-object-string
  cc-sysv-object-mode @ cc-expr-unevaluated @ 0= and if,
    cc-om-string dup om-size @ cc-last-expr-array-len !
    cc-putback-token cc-om-reference
  else, cc-parse-native-string-literal then, ;
' cc-sysv-object-string is cc-native-string-fwd

: cc-sysv-object-function
  cc-sysv-object-mode @ 0= nc-top @ 0= or if, cc-sysv-function exit, then,
  nc-name @ nc-nlen @ cc-om-find
  dup 0= if,
    drop nc-name @ nc-nlen @ cc-obj-global cc-obj-func cc-om-new
  else,
    dup om-kind @ cc-obj-func <> if, [lit] 237 cc-die then,
  then,
  nc-static @ if, cc-obj-local over om-bind ! then,
  >r cc-out-pos @ >r cc-sysv-function
  nc-id @ r> r> rot over om-symbol !
  >r cc-out-pos @ over - dup if,
    r@ om-size ! r@ om-offset ! cc-obj-text r@ om-section !
  else, 2drop then, r> drop ;
' cc-sysv-object-function is cc-native-function-fwd

: cc-om-compatible-object ( record -- )
  dup om-kind @ cc-obj-object <> if, [lit] 237 cc-die then,
  dup om-type @ over om-desc @ nc-ty @ nc-desc @
  cc-sysv-same-types 0= if, [lit] 237 cc-die then,
  dup om-array @ 0= nc-array @ 0= <> if, [lit] 237 cc-die then,
  dup om-array @ [lit] 0 > nc-array @ [lit] 0 > and if,
    dup om-array @ nc-array @ <> if, [lit] 237 cc-die then,
  then,
  dup om-inner @ nc-inner @ <> if, [lit] 237 cc-die then, drop ;
: cc-om-size-from-declaration ( record -- )
  nc-ty @ over om-type ! nc-desc @ over om-desc !
  nc-array @ [lit] 0 < over om-array @ [lit] 0 > and if,
    dup om-array @ nc-array !
  then,
  nc-array @ over om-array ! nc-inner @ over om-inner !
  cc-sysv-object-size over om-size !
  nc-ty @ nc-desc @ cc-nalignment swap om-align ! ;
: cc-om-install-object ( record -- )
  dup nc-slot !
  nc-top @ if, nc-name @ nc-nlen @ cc-sym-find else, true then,
  dup 0< if,
    drop sk-global over cc-ninstall-symbol
  else,
    dup cc-sym-kind-of sk-global <> if, [lit] 237 cc-die then,
    nc-qualified @ over cc-sym-qualified cell[] !
    nc-ty @ over cc-sym-type cell[] !
    nc-desc @ over cc-sym-set-struct-desc
    nc-array @ over cc-sym-set-array-len nc-inner @ over cc-sym-set-array-inner
    over over cc-sym-val cell[] !
  then,
  dup nc-id ! cc-sysv-object-size swap cc-sym-set-object-size drop ;
: cc-om-initializer
  true cc-ni-static ! cc-next-token-keep
  nc-ty @ nc-desc @ nc-array @ nc-inner @ [lit] 0 [lit] 0 cc-ni-value ;
: cc-sysv-object-declaration
  cc-sysv-object-mode @ 0= if, cc-nobject exit, then,
  nc-top @ 0= nc-extern @ 0= and nc-array @ [lit] 0 < and
  [char] = cc-tok-punct? 0= and if, [lit] 238 cc-die then,
  nc-top @ nc-static @ or nc-extern @ or 0= if, cc-nobject exit, then,
  [char] = cc-tok-punct? if, cc-native-init-prepare-fwd then,
  nc-top @ 0= nc-static @ and if, [lit] 0
  else, nc-name @ nc-nlen @ cc-om-find then,
  dup if, dup cc-om-compatible-object else,
    drop nc-name @ nc-nlen @ cc-obj-global cc-obj-object cc-om-new
    nc-top @ 0= nc-static @ and if, [lit] 8 over cc-om-flag then,
  then,
  nc-static @ if, cc-obj-local over om-bind ! then,
  dup cc-om-size-from-declaration dup cc-om-install-object
  [char] = cc-tok-punct? if,
    dup om-flags @ [lit] 4 and if, [lit] 237 cc-die then,
    cc-obj-current @ >r cc-obj-data cc-obj-use
    dup om-align @ cc-obj-align dup om-size @ cc-obj-reserve over om-offset !
    cc-obj-data over om-section ! [lit] 4 over cc-om-flag
    r> cc-obj-use drop cc-om-initializer
  else,
    nc-extern @ if, [lit] 1 else, [lit] 2 then, swap cc-om-flag
  then, ;
' cc-sysv-object-declaration is cc-nobject-fwd

\ Reuse118's recursive aggregate/array traversal; only static leaves differ.
\ A floating leaf is converted at compile time (125); others keep their bits.
: cc-om-value-default ( value source destination -- value ) 2drop ;
defer cc-om-value-fwd
' cc-om-value-default is cc-om-value-fwd
: cc-om-scalar-initializer
  cc-sysv-object-mode @ cc-ni-static @ and 0= if, cc-ni-scalar exit, then,
  cc-ni-aggregate? if, [lit] 219 cc-die then,
  ni-type @ cc-sysv-check-scalar
  cc-putback-token cc-parse-static-const-fwd
  dup 0= [lit] 4 cc-npick 0= and cc-last-expr-null !
  >r 2dup ni-type @ ni-desc @ cc-value-shape-fwd r>
  dup if,
    ni-type @ ty-size [lit] 8 <> if, [lit] 238 cc-die then,
    ni-type @ dup ty-ptr 0= swap ty-base ty-double = and if, [lit] 232 cc-die then,
    >r 2drop
    cc-obj-data nc-slot @ om-offset @ ni-offset @ + cc-obj-r64 r> [lit] 4 cc-npick cc-om-reloc
    drop
  else,
    drop drop ni-type @ cc-om-value-fwd
    cc-obj-data nc-slot @ om-offset @ ni-offset @ +
    ni-type @ ty-size cc-obj-patch
  then,
  cc-next-token-keep ;
' cc-om-scalar-initializer is cc-ni-scalar-fwd
: cc-om-string-initializer
  cc-sysv-object-mode @ 0= if, cc-ni-string exit, then,
  cc-om-string
  dup om-size @ 1- ni-array @ > if, [lit] 223 cc-die then,
  dup om-size @ ni-array @ cc-nmax drop
  dup om-size @ ni-array @ > if, ni-array @ else, dup om-size @ then,
  cc-ni-static @ if,
    [lit] 0 begin, 2dup > while,
      [lit] 2 cc-npick om-offset @ over + cc-obj-rodata cc-obj-base + c@
      cc-obj-data nc-slot @ om-offset @ ni-offset @ + [lit] 3 cc-npick +
      [lit] 1 cc-obj-patch 1+
    repeat, 2drop drop
  else,
    swap cc-om-reference cc-ni-mov-rsi-rdi
    ni-offset @ cc-ni-address cc-ni-copy-bytes
  then, ;
' cc-om-string-initializer is cc-ni-string-fwd

\ Symbolic constant leaves feed125's typed expression grammar. Record IDs
\ are never addresses; arithmetic only changes an explicit RELA addend.
: cc-om-const-ident
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, cc-const-unsupported then,
  dup cc-sym-kind-of sk-func = if,
    dup cc-sysv-symbol-signature >r cc-om-from-symbol >r
    [lit] 0 ty-func [lit] 1 ty-make r> r> swap exit,
  then,
  dup cc-sym-kind-of sk-global <> if, cc-const-unsupported then,
  dup cc-sym-array-len-of 0= if, cc-const-unsupported then,
  dup cc-om-from-symbol >r
  dup cc-sym-array-inner-of if,
    dup cc-sym-type-of over cc-expr-symbol-desc
    [lit] 2 cc-npick cc-sym-array-inner-of [lit] 0
    [lit] 4 cc-npick cc-sym-qualified cell[] @ cc-sysv-qualified-node
    nip ty-array [lit] 1 ty-make swap
  else,
    dup cc-sym-type-of 1+ swap
    dup cc-sym-qualified cell[] @ >r cc-expr-symbol-desc
    over ty-base ty-array = if, r@ cc-sysv-qualify-node then, r> drop
  then, [lit] 0 rot rot r> ;
: cc-om-const-string
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  cc-cx-skip @ if,
    begin, cc-next-token-keep tok-kind @ tk-str <> until,
    [lit] 0
  else, cc-om-string then,
  >r cc-putback-token [lit] 0 ty-char [lit] 1 ty-make [lit] 0 r> ;
\ An address operand carries an lvalue category separately from its type.
\ Parentheses preserve it; casts produce values. Arrow and subscripting may
\ consume a constant pointer value, but must never load a pointer object.
variable cc-const-qualified
variable cc-om-address-frame
: oa-value cc-om-address-frame @ ;
: oa-type cc-om-address-frame @ [lit] 8 + ;
: oa-desc cc-om-address-frame @ [lit] 16 + ;
: oa-record cc-om-address-frame @ [lit] 24 + ;
: oa-array cc-om-address-frame @ [lit] 32 + ;
: oa-inner cc-om-address-frame @ [lit] 40 + ;
: oa-lvalue cc-om-address-frame @ [lit] 48 + ;
: oa-qualified cc-om-address-frame @ [lit] 56 + ;
defer cc-om-address-cast-fwd
defer cc-om-address-unary-fwd
defer cc-om-address-index-fwd
' cc-const-unsupported is cc-om-address-cast-fwd
' cc-const-unsupported is cc-om-address-unary-fwd
' cc-const-unsupported is cc-om-address-index-fwd
: cc-om-address-value ( value type descriptor symbol -- )
  oa-record ! oa-desc ! oa-type ! oa-value !
  [lit] 0 oa-array ! [lit] 0 oa-inner ! [lit] 0 oa-lvalue !
  cc-const-qualified @ oa-qualified ! ;
: cc-om-address-ident
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, cc-const-unsupported then,
  dup cc-sym-qualified cell[] @ oa-qualified !
  dup cc-sym-kind-of sk-func = if,
    dup cc-sysv-symbol-signature oa-desc ! cc-om-from-symbol oa-record !
    ty-func [lit] 0 ty-make oa-type !
  else,
    dup cc-sym-kind-of sk-global <> if, cc-const-unsupported then,
    dup cc-om-from-symbol oa-record ! dup cc-sym-type-of oa-type !
    dup cc-expr-symbol-desc oa-desc !
    dup cc-sym-array-len-of oa-array ! cc-sym-array-inner-of oa-inner !
  then,
  true oa-lvalue ! ;
: cc-om-address-array
  oa-array @ 0= oa-type @ ty-base ty-array = and
  oa-type @ ty-ptr 0= and if,
    oa-desc @ dup cc-ad-type oa-type !
    dup cc-ad-count oa-array ! dup cc-ad-inner oa-inner !
    cc-ad-desc oa-desc !
  then, ;
: cc-om-address-deref
  oa-lvalue @ oa-type @ ty-ptr 0= or if, cc-const-unsupported then,
  oa-type @ 1- oa-type ! true oa-lvalue !
  oa-type @ ty-base ty-array = oa-type @ ty-ptr 0= and if,
    oa-desc @ dup cc-ad-type oa-type !
    dup cc-ad-count oa-array ! dup cc-ad-inner oa-inner !
    cc-ad-desc oa-desc ! exit,
  then,
  oa-type @ ty-ptr 0= oa-type @ ty-base ty-void = and if,
    cc-const-unsupported
  then, ;
: cc-om-address-member
  oa-lvalue @ 0= oa-array @ or oa-type @ ty-ptr or if,
    cc-const-unsupported
  then,
  oa-type @ ty-base ty-struct <> oa-desc @ 0= or if,
    cc-const-unsupported
  then,
  cc-expect-ident
  tok-str-addr @ tok-str-len @ oa-desc @ cc-find-field oa-value +!
  cc-ff-result-record @ cc-field-qualified oa-qualified @ or oa-qualified !
  cc-ff-result-record @ cc-field-use-fwd
  cc-ff-result-type @ oa-type ! cc-ff-result-desc @ oa-desc !
  cc-ff-result-array @ oa-array !
  cc-ff-result-record @ cc-sf-array-inner oa-inner ! ;
: cc-om-address-index
  oa-array @ if,
    cc-om-address-index-fwd
    dup 0< over oa-array @ > or if, cc-const-unsupported then,
    oa-type @ oa-desc @ cc-nsize
    oa-inner @ if, oa-inner @ * then, * oa-value +!
    oa-inner @ oa-array ! [lit] 0 oa-inner ! cc-om-address-array
  else,
    oa-type @ oa-desc @ cc-expr-pointee-size >r
    cc-om-address-deref
    oa-type @ ty-ptr 0= oa-type @ ty-base ty-func = and if,
      cc-const-unsupported
    then,
    cc-om-address-index-fwd r> * oa-value +!
  then,
  [char] ] cc-expect-punct-c ;
: cc-om-address-operand
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    cc-om-address-ident
  else,
    lparen cc-tok-punct? if,
      cc-next-token-keep
      cc-type-start? if,
        cc-parse-type-name
        cc-type-name-array @ if, cc-const-unsupported then,
        cc-type-name-qualified @ >r
        cc-cast-desc @ >r >r [char] ) cc-expect-punct-c
        r> r> cc-om-address-cast-fwd cc-om-address-value
        r> oa-qualified ! exit,
      then,
      cc-putback-token cc-om-address-operand [char] ) cc-expect-punct-c
    else,
      [char] * cc-tok-punct? if,
        cc-om-address-unary-fwd cc-om-address-value cc-om-address-deref exit,
      then,
      cc-const-unsupported
    then,
  then,
  begin,
    cc-next-token-keep
    [char] [ cc-tok-punct? if,
      cc-om-address-index
    else,
      [char] . cc-tok-punct? if,
        cc-om-address-member
      else,
        pt-arrow cc-tok-punct? if,
          cc-om-address-deref cc-om-address-member
        else, cc-putback-token exit, then,
      then,
    then,
  again, ;
: cc-om-const-address
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  cc-om-address-frame @ >r
  [lit] 64 cc-alloc dup cc-om-address-frame ! [lit] 64 cc-nzero
  cc-om-address-operand
  oa-lvalue @ 0= if, cc-const-unsupported then,
  oa-value @
  oa-array @ if,
    oa-type @ oa-desc @ oa-array @ oa-inner @ oa-qualified @
    cc-sysv-qualified-node
    ty-array [lit] 1 ty-make swap
  else, oa-type @ 1+ oa-desc @ then,
  oa-record @
  r> cc-om-address-frame ! ;
' cc-om-const-ident is cc-const-ident-fwd
' cc-om-const-address is cc-const-address-fwd
' cc-om-const-string is cc-const-string-fwd

: cc-om-finalize-storage ( record -- )
  dup om-kind @ cc-obj-object = over om-section @ 0= and if,
    dup om-flags @ [lit] 2 and if,
      cc-obj-bss cc-obj-use dup om-align @ cc-obj-align
      dup om-size @ cc-obj-reserve over om-offset ! cc-obj-bss over om-section !
    then,
  then, drop ;
: cc-om-export ( record -- )
  dup >r om-name @ r@ om-nlen @ r@ om-bind @ r@ om-kind @ cc-obj-default
  r@ om-section @ r@ om-offset @
  r@ om-section @ if, r@ om-size @ else, [lit] 0 then,
  cc-obj-symbol r> om-output ! ;
: cc-om-export-needed? ( record -- flag )
  dup om-section @ swap om-flags @ [lit] 16 and or ;
: cc-om-function-calls ( record -- )
  dup om-kind @ cc-obj-func <> if, drop exit, then,
  dup om-implicit @ dup if, [lit] 32 + @
  else, drop dup om-symbol @ cc-sym-call-fixups @ then,
  begin, dup while,
    cc-obj-text over @ cc-obj-plt32 [lit] 4 cc-npick [lit] 0 [lit] 4 - cc-om-reloc
    [lit] 8 + @
  repeat, 2drop ;
: cc-sysv-object-enable
  cc-sysv-enable true cc-sysv-object-mode !
  [lit] 0 cc-om-count ! [lit] 0 cc-om-relocations ! cc-om-hash-reset ;
: cc-sysv-object-program
  cc-obj-init cc-sysv-translation-unit
  cc-ni-head @ if, [lit] 238 cc-die then,
  cc-obj-text cc-obj-use cc-out-buf cc-out-pos @ cc-obj-bytes
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup cc-om-finalize-storage dup cc-om-function-calls 1+
  repeat, drop
  [lit] 0 begin, dup cc-gfixup-count @ < while,
    cc-obj-text over cc-gfixup-out-pos cell[] @ cc-obj-r64
    [lit] 3 cc-npick cc-gfixup-slot cell[] @ [lit] 0 cc-om-reloc 1+
  repeat, drop
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup cc-om-export-needed? if, dup cc-om-export then, 1+
  repeat, drop
  cc-om-relocations @ begin, dup while,
    dup [lit] 8 + @ over [lit] 16 + @ [lit] 2 cc-npick [lit] 24 + @
    [lit] 3 cc-npick [lit] 32 + @ om-output @ [lit] 4 cc-npick [lit] 40 + @
    cc-obj-reloc @
  repeat, drop ;
