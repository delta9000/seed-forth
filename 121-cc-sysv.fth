\ 121-cc-sysv.fth — explicit scalar System V AMD64 target.
\ Loading this file changes no target. cc-sysv-enable opts in to LP64 and
\ INTEGER-class calls; floating and aggregate values fail closed.
variable cc-target-sysv
[lit] 0 cc-target-sysv !
[lit] 64 constant cc-sysv-arg-cap
[lit] 1398362966 constant cc-sysv-signature-tag
create cc-sysv-signatures cc-sym-cap [lit] 8 * allot

\ An ordinary identifier never resolves to a struct/union tag. The reverse
\ scan still chooses the innermost ordinary declaration; member names live
\ in their aggregate descriptors and enumerators remain ordinary names.
: cc-sysv-find-ordinary ( a u -- id|-1 )
  cc-target-sysv @ 0= if, cc-sym-find-default exit, then,
  cc-nf-u ! cc-nf-a ! cc-sym-count @
  begin, dup while,
    1-
    dup cc-sym-kind-of sk-struct <> if,
      dup cc-sym-name-len cell[] @ cc-nf-u @ = if,
        dup cc-sym-name-addr cell[] @ cc-nf-a @ cc-nf-u @ bytes-eq if,
          exit,
        then,
      then,
    then,
  repeat, drop true ;
: cc-sysv-find-tag ( a u -- id|-1 )
  cc-target-sysv @ if, cc-nfind-tag else, cc-sym-find-default then, ;
' cc-sysv-find-ordinary is cc-sym-find
' cc-sysv-find-tag is cc-sym-find-tag

\ GNU C's __extension__ only silences pedantic diagnostics, which this
\ compiler never issues. The SysV lexer drops the reserved word between
\ tokens, so it may precede declarations, members and operands alike;
\ the preprocessed text keeps it. Number scanning (127) plugs in behind.
create cc-sysv-extension-name s, __extension__
: cc-sysv-extension? ( -- flag )
  cc-src-pos @ [lit] 13 + dup cc-src-len @ > if, drop [lit] 0 exit, then,
  dup cc-src-len @ < if,
    cc-src-buf + c@ ident-cont? if, [lit] 0 exit, then,
  else, drop then,
  cc-src-buf cc-src-pos @ + cc-sysv-extension-name [lit] 13 bytes-eq ;
: cc-sysv-skip-extensions
  begin,
    cc-target-sysv @ cc-eof? 0= and if, cc-sysv-extension? else, [lit] 0 then,
  while,
    cc-src-pos @ [lit] 13 + cc-src-pos ! cc-skip-ws-and-comments
  repeat, ;
defer cc-sysv-lex-number-fwd
' cc-lex-extra-default is cc-sysv-lex-number-fwd
: cc-sysv-lex-extra ( -- handled? )
  cc-sysv-skip-extensions cc-sysv-lex-number-fwd ;
' cc-sysv-lex-extra is cc-lex-extra-fwd

\ Signature: tag, return type, return descriptor, count, variadic flag,
\ then 64 (type, descriptor) pairs and 64 (name, length, declared) records.
\ Flags: 1 variadic, 2 unspecified prototype, 4 identifier-list definition.
\ Function-pointer descriptors are tagged; names are compile-time metadata.
: cc-sysv-sig-return [lit] 8 + @ ;
: cc-sysv-sig-desc [lit] 16 + @ ;
: cc-sysv-sig-count [lit] 24 + @ ;
: cc-sysv-sig-varargs [lit] 32 + @ ;
: cc-sysv-sig-param [lit] 16 * [lit] 40 + + ;
: cc-sysv-sig-name [lit] 24 * [lit] 1064 + + ;
: cc-sysv-prototype? cc-sysv-sig-varargs [lit] 2 and 0= ;
: cc-sysv-known-params?
  dup cc-sysv-prototype? swap cc-sysv-sig-varargs [lit] 4 and or ;
: cc-sysv-check-signature
  dup 0= if, [lit] 230 cc-die then,
  dup @ cc-sysv-signature-tag <> if, [lit] 230 cc-die then, ;
: cc-sysv-check-scalar-default ( ty -- )
  dup [lit] 256 / [lit] 255 and if, [lit] 231 cc-die then,
  dup ty-ptr if, drop exit, then,
  ty-base
  dup ty-struct = over ty-float = or over ty-double = or
  over ty-ldouble = or swap ty-func = or if, [lit] 232 cc-die then, ;
defer cc-sysv-check-scalar
' cc-sysv-check-scalar-default is cc-sysv-check-scalar

\ Bound object-size arithmetic before multiplying. Explicit bounds are
\ distinct from the unsized-array sentinel inherited from the native parser.
[lit] 1073741824 constant cc-sysv-object-size-limit
: cc-sysv-size-product ( size count -- size' )
  dup 0< if, [lit] 245 cc-die then,
  over 0= if, [lit] 238 cc-die then,
  over cc-sysv-object-size-limit swap / over < if, [lit] 245 cc-die then, * ;
: cc-sysv-object-size
  nc-ty @ nc-desc @ cc-nsize
  nc-array @ [lit] 0 > if, nc-array @ cc-sysv-size-product then,
  nc-inner @ [lit] 0 > if, nc-inner @ cc-sysv-size-product then, ;
: cc-sysv-typedef-check
  cc-target-sysv @ if,
    dup cc-sym-qualified cell[] @ nc-qualified @ or nc-qualified !
    dup cc-sym-array-len-of nc-base-array !
    dup cc-sym-array-inner-of nc-base-inner !
  then, ;
' cc-sysv-typedef-check is cc-ntypedef-check-fwd
\ Preserve array typedef shape through aliases and ordinary declarations.
\ Two bounded dimensions can also be retained behind pointer constructors.
[lit] 64 constant cc-sysv-array-rank-limit
: cc-sysv-array-rank ( type descriptor -- dimensions )
  over ty-base ty-array = [lit] 2 cc-npick ty-ptr 0= and if,
    nip dup cc-ad-type swap cc-ad-desc cc-sysv-array-rank 1+
  else, 2drop [lit] 0 then, ;
: cc-sysv-array-node ( type descriptor count inner -- descriptor )
  [lit] 56 cc-alloc >r [lit] 0 r@ [lit] 48 + !
  r@ [lit] 24 + ! r@ [lit] 16 + ! r@ [lit] 8 + ! r@ !
  \ Canonical nodes hold one dimension, including legacy matrix pointers.
  \ Equivalent row shapes must not depend on how the declarator was spelled.
  r@ cc-ad-inner if,
    r@ cc-ad-type r@ cc-ad-desc r@ cc-ad-inner [lit] 0
    cc-sysv-array-node r@ [lit] 8 + !
    ty-array [lit] 0 ty-make r@ ! [lit] 0 r@ [lit] 24 + !
  then,
  r@ cc-ad-type r@ cc-ad-desc cc-sysv-array-rank
  cc-sysv-array-rank-limit >= if, [lit] 238 cc-die then,
  r@ cc-ad-count [lit] 0 <= if, [lit] 238 cc-die then,
  r@ cc-ad-type ty-ptr 0= if,
    r@ cc-ad-type ty-base dup ty-void = swap ty-func = or if, [lit] 238 cc-die then,
  then,
  r@ cc-ad-type r@ cc-ad-desc cc-expr-type-size
  r@ cc-ad-count cc-sysv-size-product
  r@ cc-ad-inner if, r@ cc-ad-inner cc-sysv-size-product then,
  r@ [lit] 32 + !
  r@ cc-ad-type r@ cc-ad-desc cc-nalignment r@ [lit] 40 + ! r> ;
\ A new node may be born qualified. An existing one may be shared by a
\ typedef or declaration, so qualifying it builds a qualified copy.
: cc-sysv-qualified-node ( type descriptor count inner qualified -- descriptor )
  >r cc-sysv-array-node r> if, true over [lit] 48 + ! then, ;
: cc-sysv-qualify-node ( descriptor qualified -- descriptor )
  over cc-ad-qualified 0= and if,
    dup cc-ad-type over cc-ad-desc [lit] 2 cc-npick cc-ad-count
    [lit] 3 cc-npick cc-ad-inner true cc-sysv-qualified-node nip
  then, ;
\ Additional fixed suffixes form real element-array types. The old outer
\ metadata stays intact for one/two dimensions and for the native target.
\ Depth is bounded independently of the checked 1 GiB size product.
: cc-sysv-array-tail ( depth -- descriptor )
  dup cc-sysv-array-rank-limit > if, [lit] 238 cc-die then,
  cc-parse-const dup [lit] 0 <= if, [lit] 238 cc-die then, >r
  [char] ] cc-expect-punct-c cc-next-token-keep
  [char] [ cc-tok-punct? if,
    1+ cc-sysv-array-tail ty-array [lit] 0 ty-make swap
  else, drop nc-ty @ nc-desc @ then,
  r> [lit] 0 cc-sysv-array-node ;
: cc-sysv-array-extra
  cc-target-sysv @ [char] [ cc-tok-punct? and if,
    nc-base-array @ if, [lit] 238 cc-die then,
    nc-inner @ [lit] 0 <= if, [lit] 238 cc-die then,
    [lit] 3 cc-sysv-array-tail
    ty-array [lit] 0 ty-make swap nc-inner @ [lit] 0
    cc-sysv-array-node nc-desc ! ty-array [lit] 0 ty-make nc-ty !
    [lit] 0 nc-inner ! nc-bound-mask @ [lit] 1 and nc-bound-mask !
  then, ;
' cc-sysv-array-extra is cc-narray-extra-fwd
\ A qualified array decays like any other (C90 6.2.2.1): the qualifier moves
\ onto the pointed-to type. A matrix's row node records it, and the value
\ keeps the expression's qualified flag, so `const T t[2][3]` gives a
\ pointer to qualified rows. A ranked array already points at its element
\ node; a qualified one points at a qualified copy.
: cc-sysv-array-decay
  cc-target-sysv @ cc-last-expr-array-len @ 0= 0= and
  cc-last-expr-type @ ty-base ty-array = and if,
    cc-last-struct-desc @ cc-last-expr-qualified @ cc-sysv-qualify-node
    cc-last-struct-desc !
  then,
  cc-target-sysv @ cc-last-expr-array-inner @ 0= 0= and if,
    cc-last-expr-qualified @ >r
    cc-last-expr-type @ [lit] 1 - cc-last-struct-desc @
    cc-last-expr-array-inner @ [lit] 0 r@ cc-sysv-qualified-node
    ty-array [lit] 1 ty-make swap cc-mark-typed-value
    r> cc-last-expr-qualified !
  then, ;
' cc-sysv-array-decay is cc-array-decay-fwd
\ Declared array pointers take the base type's qualifiers: in
\ `const long (*p)[3]` the rows are qualified, in `long (*const p)[3]` only p.
: cc-sysv-grouped-array ( stars -- )
  cc-target-sysv @ 0= if, cc-npointer-array-default exit, then,
  nc-array @ nc-inner @ or nc-base-array @ or if, [lit] 238 cc-die then,
  >r cc-narray-suffix
  nc-bound-mask @ [lit] 2 and nc-inner @ [lit] 0 <= and if, [lit] 238 cc-die then,
  nc-ty @ nc-desc @ nc-array @ nc-inner @ nc-base-qualified @
  cc-sysv-qualified-node nc-desc !
  ty-array r> ty-make nc-ty !
  [lit] 0 nc-array ! [lit] 0 nc-inner ! [lit] 0 nc-bound-mask ! ;
' cc-sysv-grouped-array is cc-npointer-array-fwd
: cc-sysv-array-address ( type descriptor count inner -- type descriptor )
  cc-target-sysv @ 0= if, cc-array-address-default exit, then,
  >r >r swap [lit] 1 - swap r> r> cc-last-expr-qualified @
  cc-sysv-qualified-node ty-array [lit] 1 ty-make swap ;
' cc-sysv-array-address is cc-array-address-fwd
: cc-sysv-inherit-array
  nc-base-array @ if,
    nc-ty @ nc-base @ <> if,
      nc-base @ nc-sdesc @ nc-base-array @ nc-base-inner @
      nc-base-qualified @ cc-sysv-qualified-node nc-desc !
      ty-array nc-ty @ nc-base @ - ty-make nc-ty ! exit,
    then,
    nc-func @ if, [lit] 238 cc-die then,
    nc-array @ if,
      nc-inner @ nc-base-inner @ or nc-base-array @ [lit] 0 < or if,
        [lit] 238 cc-die
      then,
      nc-base-array @ nc-inner !
    else,
      nc-base-array @ nc-array ! nc-base-inner @ nc-inner !
    then,
  then, ;
: cc-sysv-type-shape ( base-type stars -- type )
  cc-target-sysv @ 0= if, + exit, then,
  dup 0= 0= nc-base-array @ 0= 0= and if,
    >r cc-cast-desc @ nc-base-array @ nc-base-inner @
    nc-base-qualified @ cc-sysv-qualified-node cc-cast-desc !
    ty-array r> ty-make exit,
  then,
  nc-base-array @ cc-type-name-array ! nc-base-inner @ cc-type-name-inner ! + ;
' cc-sysv-type-shape is cc-native-type-shape-fwd
: cc-sysv-sizeof-type ( type descriptor -- bytes )
  cc-expr-type-size
  cc-target-sysv @ if,
    cc-type-name-array @ if,
      cc-type-name-array @ [lit] 0 < if, [lit] 238 cc-die then,
      cc-type-name-array @ cc-sysv-size-product
      cc-type-name-inner @ if, cc-type-name-inner @ cc-sysv-size-product then,
    then,
  then, ;
' cc-sysv-sizeof-type is cc-sizeof-type-size-fwd
\ Array expressions carry a pointer-shaped type before decay. A whole
\ matrix is not a record, and another subscript needs a pointer operand.
: cc-sysv-index-base
  cc-target-sysv @ if,
    cc-last-expr-type @ ty-ptr 0= if, [lit] 238 cc-die then,
  then, ;
' cc-sysv-index-base is cc-index-base-fwd
: cc-sysv-member-base ( op -- op )
  cc-target-sysv @ if,
    cc-last-expr-type @ ty-base ty-struct <> if, [lit] 238 cc-die then,
    dup [char] . = if,
      cc-last-expr-array-len @ cc-last-expr-type @ ty-ptr or if, [lit] 238 cc-die then,
    else,
      cc-last-expr-type @ ty-ptr [lit] 1 <>
      cc-last-expr-array-inner @ or if, [lit] 238 cc-die then,
    then,
  then, ;
' cc-sysv-member-base is cc-member-base-fwd

\ Real layouts are retained even when floating/aggregate value operations
\ are unsupported. Taking an address must not read that value first.
: cc-sysv-float-types cc-target-sysv @ cc-bootstrap-floatbits @ or ;
' cc-sysv-float-types is cc-native-float-types-fwd
: cc-sysv-value-type-check ( type -- type )
  cc-target-sysv @ cc-expr-unevaluated @ 0= and if,
    dup cc-sysv-check-scalar
  then, ;
' cc-sysv-value-type-check is cc-emit-type-check-fwd
: cc-sysv-local-load ( slot type -- )
  cc-target-sysv @ if,
    drop cc-emit-lea-rdi-local
    true cc-last-ident-slot ! lv-deref cc-last-lvalue-kind !
  else, cc-emit-load-local-typed then, ;
' cc-sysv-local-load is cc-native-local-load-fwd
: cc-sysv-local-layout ( -- slots slot )
  cc-target-sysv @ 0= if, cc-native-local-layout-default exit, then,
  cc-sysv-object-size dup 0= if, [lit] 238 cc-die then,
  cc-fn-local-count @ [lit] 8 * +
  nc-ty @ nc-desc @ cc-nalignment [lit] 8 cc-nmax cc-nalign
  [lit] 8 / dup cc-fn-local-count @ - swap 1- ;
' cc-sysv-local-layout is cc-native-local-layout-fwd

\ C90 permits an omitted int at file scope. A typedef name still starts
\ an explicit type; other identifiers remain pending for the declarator.
: cc-sysv-implicit-base ( -- type descriptor true | false )
  cc-target-sysv @ nc-top @ and 0= if, [lit] 0 exit, then,
  tok-kind @ tk-ident <> if, [lit] 0 exit, then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-typedef = if, drop [lit] 0 exit, then,
  then, drop
  cc-putback-token ty-int [lit] 0 ty-make [lit] 0 true ;
' cc-sysv-implicit-base is cc-native-implicit-base-fwd

: cc-sysv-implicit-declarator-noop ;
defer cc-sysv-implicit-declarator-fwd
' cc-sysv-implicit-declarator-noop is cc-sysv-implicit-declarator-fwd

: cc-sysv-check-declarator
  cc-target-sysv @ if,
    nc-td @ nc-func @ and if, [lit] 238 cc-die then,
    cc-sysv-implicit-declarator-fwd
    cc-sysv-inherit-array
    nc-ty @ nc-desc @ cc-sysv-array-rank
    nc-array @ if, 1+ then, nc-inner @ if, 1+ then,
    cc-sysv-array-rank-limit > if, [lit] 238 cc-die then,
    nc-ty @ [lit] 256 / [lit] 255 and if, [lit] 231 cc-die then,
    nc-bound-mask @ [lit] 1 and if,
      nc-array @ [lit] 0 <= if, [lit] 238 cc-die then,
    then,
    nc-bound-mask @ [lit] 2 and if,
      nc-inner @ [lit] 0 <= if, [lit] 238 cc-die then,
    then,
    nc-array @ [lit] 0 > nc-inner @ [lit] 0 > or if,
      cc-sysv-object-size drop
    then,
  then, ;
' cc-sysv-check-declarator is cc-ndeclarator-check-fwd

: cc-sysv-adjust-array-parameter
  nc-array @ if,
    \ Ranked element nodes also construct a pointer-to-array at adjustment.
    nc-ty @ ty-base ty-array = nc-ty @ ty-ptr 0= and if,
      nc-desc @ nc-base-qualified @ cc-sysv-qualify-node nc-desc !
    then,
    nc-inner @ if,
      nc-ty @ nc-desc @ nc-inner @ [lit] 0 nc-base-qualified @
      cc-sysv-qualified-node nc-desc !
      ty-array [lit] 1 ty-make nc-ty !
      [lit] 0 nc-array ! [lit] 0 nc-inner ! exit,
    then,
    [lit] 1 nc-ty +! [lit] 0 nc-array !
  then, ;

\ Parameter signatures carry types independently of optional source names.
: cc-sysv-fnptr-name
  cc-target-sysv @ 0= if, cc-nfnptr-name-default exit, then,
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    tok-str-addr @ nc-name ! tok-str-len @ nc-nlen !
  else, cc-putback-token then, ;
' cc-sysv-fnptr-name is cc-nfnptr-name-fwd

defer cc-sysv-signature-fwd
: cc-sysv-fnptr
  cc-target-sysv @ 0= if, cc-nfnptr-default exit, then,
  1+ dup [lit] 255 > if, [lit] 231 cc-die then, >r
  nc-base-array @ if,
    nc-ty @ nc-base @ = if, [lit] 238 cc-die then,
    cc-sysv-inherit-array
    [lit] 0 nc-base-array ! [lit] 0 nc-base-inner !
  then,
  nc-ty @ nc-desc @ cc-sysv-signature-fwd nc-desc !
  ty-func r> ty-make nc-ty ! ;
' cc-sysv-fnptr is cc-nfnptr-fwd

: cc-sysv-find-parameter ( sig name length -- index|-1 )
  [lit] 0 begin, [lit] 3 cc-npick cc-sysv-sig-count over > while,
    [lit] 3 cc-npick over cc-sysv-sig-name
    dup [lit] 8 + @ [lit] 3 cc-npick = if,
      @ [lit] 3 cc-npick [lit] 3 cc-npick bytes-eq if,
        >r drop 2drop r> exit,
      then,
    else, drop then,
    1+
  repeat, drop drop 2drop true ;
: cc-sysv-identifier-list ( sig -- sig )
  dup cc-sysv-sig-count if, [lit] 233 cc-die then,
  [lit] 6 over [lit] 32 + !
  begin,
    tok-kind @ tk-ident <> if, [lit] 233 cc-die then,
    dup cc-sysv-sig-count cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
    dup tok-str-addr @ tok-str-len @ cc-sysv-find-parameter 0< 0= if,
      [lit] 233 cc-die
    then,
    dup dup cc-sysv-sig-count cc-sysv-sig-name
    tok-str-addr @ over ! tok-str-len @ swap [lit] 8 + !
    dup dup cc-sysv-sig-count cc-sysv-sig-param
    ty-int [lit] 0 ty-make swap !
    [lit] 1 over [lit] 24 + +!
    cc-next-token-keep [char] , cc-tok-punct? if,
      cc-next-token-keep
    else,
      [char] ) cc-tok-punct? 0= if, [lit] 233 cc-die then, exit,
    then,
  again, ;
\ C90 parameter declarations allow one register specifier, interleaved
\ with type keywords and qualifiers. Keep this policy in the parameter's
\ own declaration context: an aggregate member uses a different context.
\ Qualifiers retain the shared parser's existing representation; the base
\ type, signedness, pointer depth and descriptor still come from cc-nbase.
variable cc-sysv-parameter-context
variable cc-sysv-parameter-register
: cc-sysv-parameter-specifiers
  cc-target-sysv @ 0= if, exit, then,
  cc-nctx @ cc-sysv-parameter-context @ <> if, exit, then,
  begin,
    kw-static cc-tok-kw? kw-extern cc-tok-kw? or
    kw-auto cc-tok-kw? or kw-typedef cc-tok-kw? or
    kw-inline cc-tok-kw? or if, [lit] 233 cc-die then,
    kw-register cc-tok-kw? if,
      cc-sysv-parameter-register @ if, [lit] 233 cc-die then,
      true cc-sysv-parameter-register ! true
    else, cc-qualifier? dup if, cc-qual-note then, then,
  while, cc-next-token-keep repeat, ;
' cc-sysv-parameter-specifiers is cc-nbase-specifiers-fwd
\ C90 constrains the multiset of type keywords, whatever their order and
\ any qualifiers between them. Only long may repeat (long long); one sign;
\ void and float stand alone; double admits one long; char admits a sign;
\ short admits int and a sign. Every declaration context rejects with 233.
variable cc-sysv-spec-bad
: cc-sysv-spec-fail ( flag -- ) cc-sysv-spec-bad @ or cc-sysv-spec-bad ! ;
: cc-sysv-spec-total ( -- n )
  [lit] 0 [lit] 0
  begin, dup [lit] 9 < while, dup cc-nspec-count rot + swap 1+ repeat, drop ;
\ Fail when any keyword outside the named slots' total is present.
: cc-sysv-spec-only ( allowed -- ) cc-sysv-spec-total swap - [lit] 0 > cc-sysv-spec-fail ;
: cc-sysv-spec-check
  cc-target-sysv @ 0= if, exit, then,
  [lit] 0 cc-sysv-spec-bad !
  [lit] 0
  begin, dup [lit] 9 < while,
    dup cc-nspec-count over kw-long = if, [lit] 2 else, [lit] 1 then, >
    cc-sysv-spec-fail 1+
  repeat, drop
  kw-unsigned cc-nspec-count kw-signed cc-nspec-count + dup >r
  [lit] 1 > cc-sysv-spec-fail
  kw-void cc-nspec-count if, kw-void cc-nspec-count cc-sysv-spec-only then,
  [lit] 7 cc-nspec-count if, [lit] 7 cc-nspec-count cc-sysv-spec-only then,
  [lit] 8 cc-nspec-count if,
    kw-long cc-nspec-count [lit] 1 > cc-sysv-spec-fail
    [lit] 8 cc-nspec-count kw-long cc-nspec-count + cc-sysv-spec-only
  then,
  kw-char cc-nspec-count if, kw-char cc-nspec-count r@ + cc-sysv-spec-only then,
  kw-short cc-nspec-count if,
    kw-short cc-nspec-count kw-int cc-nspec-count + r@ + cc-sysv-spec-only
  then,
  r> drop
  cc-sysv-spec-bad @ if, [lit] 233 cc-die then, ;
' cc-sysv-spec-check is cc-nspec-check-fwd
: cc-sysv-parameter-base ( -- type descriptor )
  cc-sysv-parameter-context @ >r cc-sysv-parameter-register @ >r
  cc-nctx @ cc-sysv-parameter-context !
  [lit] 0 cc-sysv-parameter-register !
  cc-nbase
  \ Aggregate, enum and typedef bases return before trailing specifiers.
  cc-next-token-keep cc-sysv-parameter-specifiers cc-putback-token
  r> cc-sysv-parameter-register ! r> cc-sysv-parameter-context ! ;

\ C adjusts a function-declared parameter to a pointer to that function.
\ Reparse its saved suffix through the same recursive signature parser as
\ an explicit (*callback) declarator, then restore the enclosing delimiter.
: cc-sysv-adjust-function-parameter
  nc-func @ if,
    cc-lex-state-size cc-alloc dup cc-lex-mark >r
    nc-params cc-lex-reset
    nc-ty @ nc-desc @ cc-sysv-signature-fwd nc-desc !
    r> cc-lex-reset
    ty-func [lit] 1 ty-make nc-ty ! [lit] 0 nc-func !
  then, ;

: cc-sysv-signature ( return-type return-desc -- signature )
  [lit] 2600 cc-alloc dup >r [lit] 2600 cc-nzero
  r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-sysv-signature-tag r@ !
  nc-qualified @ r@ cc-field-set-qualified
  cc-nctx @ >r cc-ncontext
  begin,
    cc-next-token-keep
    [char] ) cc-tok-punct? if,
      r> cc-nctx ! r>
      dup cc-sysv-sig-count if, [lit] 233 cc-die then,
      [lit] 2 over [lit] 32 + ! exit,
    then,
    pt-ellipsis cc-tok-punct? if,
      r> cc-nctx ! r>
      dup cc-sysv-sig-count 0= if, [lit] 233 cc-die then,
      [lit] 1 over [lit] 32 + ! [char] ) cc-expect-punct-c exit,
    then,
    kw-void cc-tok-kw? if,
      cc-peek-mark cc-lex-mark cc-next-token-keep
      [char] ) cc-tok-punct? if,
        r> cc-nctx ! r> dup cc-sysv-sig-count if, [lit] 233 cc-die then, exit,
      then,
      cc-peek-mark cc-lex-reset
    then,
    tok-kind @ tk-ident = cc-native-type-start 0= and if,
      r> cc-nctx ! r> cc-sysv-identifier-list exit,
    then,
    cc-sysv-parameter-base nc-sdesc ! nc-base ! cc-ndeclarator
    cc-sysv-adjust-function-parameter
    cc-sysv-adjust-array-parameter
    nc-ty @ ty-size 0= if, [lit] 233 cc-die then,
    r> r> dup >r swap >r
    nc-nlen @ if,
      dup nc-name @ nc-nlen @ cc-sysv-find-parameter 0< 0= if,
        [lit] 233 cc-die
      then,
    then,
    dup cc-sysv-sig-count dup cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
    over swap cc-sysv-sig-param
    nc-qualified @ over cc-field-set-qualified
    nc-ty @ over ! nc-desc @ swap [lit] 8 + !
    dup dup cc-sysv-sig-count cc-sysv-sig-name
    nc-name @ over ! nc-nlen @ over [lit] 8 + !
    true swap [lit] 16 + !
    [lit] 1 swap [lit] 24 + +!
    [char] , cc-tok-punct? 0= if,
      [char] ) cc-tok-punct? 0= if, [lit] 184 cc-die then,
      r> cc-nctx ! r> exit,
    then,
  again, ;
' cc-sysv-signature is cc-sysv-signature-fwd

\ Abstract function-pointer type names reuse the declaration signature parser.
\ Each grouped star is retained in the type word beside its signature.
\ Depth one is a function pointer; greater depths point to pointer objects.
\ The operand address is unchanged; loads occur when those objects are read.
: cc-sysv-type-name-raw
  cc-native-type-name
  cc-type-name-qualified @ nc-qualified !
  cc-target-sysv @ 0= if, exit, then,
  cc-next-token-keep
  lparen cc-tok-punct? if,
    cc-type-name-array @ if, [lit] 238 cc-die then,
    [char] * cc-expect-punct-c
    cc-skip-qualifiers cc-count-stars 1+
    dup [lit] 255 > if, [lit] 231 cc-die then, >r
    [char] ) cc-expect-punct-c cc-next-token-keep
    [char] [ cc-tok-punct? if,
      cc-type-name-qualified @ cc-nctx @ >r cc-ncontext >r
      cc-narray-suffix
      nc-bound-mask @ [lit] 2 and nc-inner @ [lit] 0 <= and if, [lit] 238 cc-die then,
      cc-cast-desc @ nc-array @ nc-inner @ r> cc-sysv-qualified-node
      cc-cast-desc !
      r> cc-nctx ! ty-array r> ty-make cc-putback-token
    else,
      lparen cc-tok-punct? 0= if, [lit] 238 cc-die then,
      cc-cast-desc @ cc-sysv-signature cc-cast-desc !
      ty-func r> ty-make
    then,
  else, cc-putback-token then, ;
: cc-sysv-type-name
  cc-nctx @ 0= if, cc-ncontext then,
  nc-qualified @ >r nc-base-qualified @ >r nc-prefix-qualified @ >r
  [lit] 0 nc-prefix-qualified ! cc-sysv-type-name-raw
  nc-qualified @ cc-type-name-qualified !
  r> nc-prefix-qualified ! r> nc-base-qualified ! r> nc-qualified ! ;
' cc-sysv-type-name is cc-native-type-name-fwd

\ C permits function-pointer conversions and a round trip back to the
\ original signature. A call still uses its actual selected signature and
\ the normal ABI class checks. Only explicit casts cross to object pointers.
: cc-sysv-function-pointer? ( type -- flag )
  dup ty-base ty-func = swap ty-ptr [lit] 1 = and ;
: cc-sysv-integral? ( type -- flag )
  dup ty-ptr if, drop [lit] 0 exit, then,
  ty-base
  dup ty-char = over ty-uchar = or over ty-short = or
  over ty-ushort = or over ty-int = or over ty-uint = or
  over ty-long = or over ty-ulong = or
  over ty-llong = or swap ty-ullong = or ;
\ Explicit LP64 integer/function-pointer representation conversions use
\ all 64 bits. Only pointer-width integral destinations preserve a function
\ address. Explicit function/object pointer casts keep all 64 bits too, as
\ POSIX dlsym and GCC allow; any other function-pointer partner rejects.
\ The policy is pure so constant and runtime casts share it.
\ This permits signal sentinels and address round trips, not arbitrary calls.
: cc-sysv-cast-types ( source destination -- )
  cc-target-sysv @ 0= if, 2drop exit, then,
  dup ty-void [lit] 0 ty-make = if, 2drop exit, then,
  over cc-sysv-integral? over cc-sysv-function-pointer? and if,
    2drop exit,
  then,
  over cc-sysv-function-pointer? over cc-sysv-integral? and if,
    ty-size [lit] 8 <> if, [lit] 230 cc-die then, drop exit,
  then,
  over cc-sysv-function-pointer? over cc-sysv-function-pointer? = if,
    2drop exit,
  then,
  ty-ptr 0= swap ty-ptr 0= or if, [lit] 230 cc-die then, ;
' cc-sysv-cast-types is cc-cast-types-fwd
\ Normalize an integral operand before replacing its type with a pointer:
\ signed narrow values extend their sign and unsigned ones extend zero.
: cc-sysv-cast-value ( source destination -- )
  cc-target-sysv @ if,
    over cc-sysv-integral? over cc-sysv-function-pointer? and if,
      over cc-emit-convert-rdi
    then,
  then,
  cc-emit-convert-value ;
' cc-sysv-cast-value is cc-cast-value-fwd
\ Qualified void pointees do not form null pointer constants. The flattened
\ qualifier flag also conservatively excludes top-level-qualified void*.
\ Read the cast target's saved flag, never metadata left by a nested cast.
: cc-sysv-cast-null ( source destination null qualified -- null )
  swap >r >r
  dup cc-sysv-integral? swap ty-void [lit] 1 ty-make = r> 0= and or
  swap cc-sysv-integral? and r> and cc-target-sysv @ and ;
' cc-sysv-cast-null is cc-cast-null-fwd
: cc-sysv-ternary-split cc-target-sysv @ ;
' cc-sysv-ternary-split is cc-value-ternary-split-fwd


\ Type identity is checked at redeclarations. Struct pointers retain tag
\ identity; function-pointer signatures compare recursively by shape.
defer cc-sysv-compatible-signatures-fwd
: cc-sysv-compatible-types ( ty1 desc1 ty2 desc2 -- flag )
  >r swap >r
  2dup <> if, 2drop r> drop r> drop [lit] 0 exit, then,
  drop ty-base
  dup ty-func = if,
    drop r> r> cc-sysv-compatible-signatures-fwd exit,
  then,
  dup ty-array = if,
    drop r> r>
    2dup 0= swap 0= or if, [lit] 237 cc-die then,
    2dup cc-ad-count swap cc-ad-count <> if, 2drop [lit] 0 exit, then,
    2dup cc-ad-inner swap cc-ad-inner <> if, 2drop [lit] 0 exit, then,
    dup cc-ad-type swap cc-ad-desc >r >r
    dup cc-ad-type swap cc-ad-desc r> r> cc-sysv-compatible-types exit,
  then,
  ty-struct = if, r> r> = else, r> drop r> drop true then, ;
\ Implicit conversion may add a row qualifier but never discard one:
\ `long (*p)[3] = t` with `const long t[2][3]` needs an explicit cast.
: cc-sysv-row-qualifier-check ( source descriptor destination descriptor -- same )
  [lit] 3 cc-npick ty-base ty-array = [lit] 2 cc-npick ty-base ty-array = and
  [lit] 3 cc-npick 0= 0= and over 0= 0= and if,
    [lit] 2 cc-npick cc-ad-qualified over cc-ad-qualified 0= and
    if, [lit] 238 cc-die then,
  then, ;
: cc-sysv-value-shape ( source descriptor destination descriptor -- )
  cc-target-sysv @ 0= if, 2drop 2drop exit, then,
  [lit] 3 cc-npick ty-base ty-array = [lit] 2 cc-npick ty-base ty-array = or
  [lit] 4 cc-npick ty-base ty-func = [lit] 3 cc-npick ty-base ty-func = or or if,
    [lit] 3 cc-npick ty-ptr 0= [lit] 2 cc-npick ty-ptr 0= or if,
      cc-last-expr-null @ 0= if, [lit] 237 cc-die then,
      2drop 2drop exit,
    then,
    [lit] 3 cc-npick ty-void [lit] 1 ty-make =
    [lit] 2 cc-npick ty-void [lit] 1 ty-make = or if, 2drop 2drop exit, then,
    [lit] 3 cc-npick [lit] 3 cc-npick [lit] 3 cc-npick [lit] 3 cc-npick
    cc-sysv-compatible-types 0= if, [lit] 237 cc-die then,
    cc-sysv-row-qualifier-check 2drop 2drop
  else, 2drop 2drop then, ;
' cc-sysv-value-shape is cc-value-shape-fwd
: cc-sysv-array-operands?
  cc-target-sysv @ if,
    cc-expr-left-type @ ty-base ty-array = cc-expr-right-type @ ty-base ty-array = or
  else, [lit] 0 then, ;
: cc-sysv-array-pair-check
  cc-expr-left-type @ cc-expr-left-desc @ cc-expr-right-type @ cc-expr-right-desc @
  cc-sysv-compatible-types 0= if, [lit] 237 cc-die then, ;
: cc-sysv-array-binop
  cc-sysv-array-operands? 0= if, exit, then,
  cc-expr-left-type @ ty-ptr cc-expr-right-type @ ty-ptr and if,
    cc-expr-op-row @ bo-op + @ [char] - =
    cc-expr-op-row @ bo-level + @ dup level-rel = swap level-eq = or or
    0= if, [lit] 237 cc-die then,
    cc-sysv-array-pair-check exit,
  then,
  cc-expr-op-row @ bo-level + @ level-add = if,
    cc-expr-left-type @ ty-ptr if,
      cc-expr-right-type @ cc-sysv-integral? 0= if, [lit] 237 cc-die then,
    else,
      cc-expr-op-row @ bo-op + @ [char] + <>
      cc-expr-left-type @ cc-sysv-integral? 0= or if, [lit] 237 cc-die then,
    then, exit,
  then,
  cc-expr-op-row @ bo-level + @ level-eq = if,
    cc-expr-left-type @ ty-ptr if, cc-expr-right-null @ else, cc-expr-left-null @ then,
    if, exit, then,
  then,
  [lit] 237 cc-die ;
' cc-sysv-array-binop is cc-array-binop-fwd
: cc-sysv-array-compound
  cc-sysv-array-operands? if,
    cc-expr-left-type @ ty-ptr 0= cc-expr-right-type @ cc-sysv-integral? 0= or
    if, [lit] 237 cc-die then,
  then, ;
' cc-sysv-array-compound is cc-array-compound-fwd
: cc-sysv-array-ternary
  cc-target-sysv @ 0= if, exit, then,
  cc-expr-left-type @ ty-void [lit] 0 ty-make =
  cc-expr-right-type @ ty-void [lit] 0 ty-make = or if,
    cc-expr-left-type @ cc-expr-right-type @ <> if, [lit] 237 cc-die then,
    ty-void [lit] 0 ty-make cc-expr-common ! exit,
  then,
  cc-expr-left-type @ ty-ptr cc-expr-right-type @ ty-ptr or 0= if, exit, then,
  \ A null pointer constant adopts the other arm's pointer type. A void*
  \ variable, including one whose runtime value is zero, is not such a constant.
  cc-expr-left-null @ cc-expr-right-type @ ty-ptr and if,
    cc-expr-right-type @ cc-expr-common ! exit,
  then,
  cc-expr-right-null @ cc-expr-left-type @ ty-ptr and if,
    cc-expr-left-type @ cc-expr-common ! exit,
  then,
  cc-expr-left-type @ ty-ptr 0= cc-expr-right-type @ ty-ptr 0= or
  if, [lit] 237 cc-die then,
  cc-expr-left-type @ ty-void [lit] 1 ty-make =
  cc-expr-right-type @ ty-void [lit] 1 ty-make = or if,
    cc-expr-left-type @ cc-sysv-function-pointer?
    cc-expr-right-type @ cc-sysv-function-pointer? or if, [lit] 237 cc-die then,
    ty-void [lit] 1 ty-make cc-expr-common ! exit,
  then,
  cc-sysv-array-pair-check
  \ Either arm's row qualifier qualifies the result, which takes the left
  \ arm's node.
  cc-expr-left-type @ ty-base ty-array = if,
    cc-expr-left-desc @ cc-expr-right-desc @ cc-ad-qualified
    cc-sysv-qualify-node cc-expr-left-desc !
  then, ;
' cc-sysv-array-ternary is cc-array-ternary-fwd
: cc-sysv-signature-result dup cc-sysv-sig-return swap cc-sysv-sig-desc ;
: cc-sysv-parameter-type cc-sysv-sig-param dup @ swap [lit] 8 + @ ;
\ Default promotions matter to prototype compatibility even for types
\ whose executable calling convention is deliberately unsupported.
: cc-sysv-default-type ( type -- promoted-type )
  dup ty-ptr 0= over ty-base ty-float = and if,
    drop ty-double [lit] 0 ty-make
  else, cc-unary-type then, ;
: cc-sysv-comparison-param ( sig index -- type desc )
  over cc-sysv-prototype? >r cc-sysv-parameter-type
  r> 0= if, swap cc-sysv-default-type swap then, ;
: cc-sysv-default-compatible? ( sig -- flag )
  dup cc-sysv-sig-varargs [lit] 1 and if, drop [lit] 0 exit, then,
  [lit] 0 begin, over cc-sysv-sig-count over > while,
    2dup cc-sysv-sig-param @ dup cc-sysv-default-type <> if,
      2drop [lit] 0 exit,
    then, 1+
  repeat, 2drop true ;
: cc-sysv-compatible-signatures ( sig1 sig2 -- flag )
  2dup cc-sysv-check-signature drop cc-sysv-check-signature drop
  2dup >r cc-sysv-signature-result r> cc-sysv-signature-result
  cc-sysv-compatible-types 0= if, 2drop [lit] 0 exit, then,
  over cc-sysv-known-params? 0= if,
    nip dup cc-sysv-prototype? if, cc-sysv-default-compatible?
    else, drop true then, exit,
  then,
  dup cc-sysv-known-params? 0= if,
    drop dup cc-sysv-prototype? if, cc-sysv-default-compatible?
    else, drop true then, exit,
  then,
  2dup cc-sysv-sig-count swap cc-sysv-sig-count <> if, 2drop [lit] 0 exit, then,
  2dup cc-sysv-sig-varargs [lit] 1 and
  swap cc-sysv-sig-varargs [lit] 1 and <> if, 2drop [lit] 0 exit, then,
  [lit] 0 begin, over cc-sysv-sig-count over > while,
    [lit] 2 cc-npick over cc-sysv-comparison-param
    [lit] 3 cc-npick [lit] 3 cc-npick cc-sysv-comparison-param
    cc-sysv-compatible-types 0= if, drop 2drop [lit] 0 exit, then,
    1+
  repeat, drop 2drop true ;
' cc-sysv-compatible-signatures is cc-sysv-compatible-signatures-fwd

\ C90 implicit externs keep scoped visibility but persistent declaration
\ identity and fixups: a block's symbol IDs may be reused after it exits.
\ Record: next, name, length, unspecified-int signature, calls, addresses.
variable cc-sysv-implicit-head
variable cc-sysv-implicit-count
: cc-sysv-implicit-find ( name length -- record|0 )
  cc-nf-u ! cc-nf-a ! cc-sysv-implicit-head @
  begin, dup while,
    dup [lit] 16 + @ cc-nf-u @ = if,
      dup [lit] 8 + @ cc-nf-a @ cc-nf-u @ bytes-eq if, exit, then,
    then, @
  repeat, ;
: cc-sysv-implicit-symbol ( id -- record|0 )
  dup cc-sym-kind-of sk-func <> if, drop [lit] 0 exit, then,
  dup cc-sym-name-addr cell[] @ swap cc-sym-name-len cell[] @ cc-sysv-implicit-find ;
: cc-sysv-call-fixups ( id -- cell )
  cc-target-sysv @ if,
    dup cc-sysv-implicit-symbol dup if, nip [lit] 32 + exit, then, drop
  then, cc-sym-call-fixups-default ;
: cc-sysv-address-fixups ( id -- cell )
  cc-target-sysv @ if,
    dup cc-sysv-implicit-symbol dup if, nip [lit] 40 + exit, then, drop
  then, cc-sym-addr-fixups-default ;
' cc-sysv-call-fixups is cc-sym-call-fixups
' cc-sysv-address-fixups is cc-sym-addr-fixups
: cc-sysv-implicit-record ( name length -- record )
  2dup cc-sysv-implicit-find dup if, nip nip exit, then, drop
  cc-sysv-implicit-count @ 1+ cc-sym-cap [lit] 60 cc-check-cap
  [lit] 1 cc-sysv-implicit-count +!
  [lit] 48 cc-alloc dup >r [lit] 48 cc-nzero
  r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-sysv-implicit-head @ r@ ! r@ cc-sysv-implicit-head !
  [lit] 2600 cc-alloc dup [lit] 2600 cc-nzero
  cc-sysv-signature-tag over !
  ty-int [lit] 0 ty-make over [lit] 8 + !
  [lit] 2 over [lit] 32 + ! r@ [lit] 24 + ! r> ;
: cc-sysv-implicit-declared-noop drop ;
defer cc-sysv-implicit-declared-fwd
' cc-sysv-implicit-declared-noop is cc-sysv-implicit-declared-fwd
: cc-sysv-unknown-ident ( -- id|-1 )
  cc-target-sysv @ 0= if, true exit, then,
  cc-peek-mark cc-lex-mark cc-next-token-keep
  lparen cc-tok-punct? cc-peek-mark cc-lex-reset 0= if, true exit, then,
  tok-str-addr @ tok-str-len @ cc-sysv-implicit-record >r
  tok-str-addr @ tok-str-len @ sk-func ty-int [lit] 0 ty-make [lit] 0 cc-sym-add
  r> [lit] 24 + @ over cc-sysv-signatures cell[] !
  dup cc-sysv-implicit-declared-fwd ;
' cc-sysv-unknown-ident is cc-native-unknown-ident-fwd
: cc-sysv-check-implicit-signature ( signature -- )
  nc-name @ nc-nlen @ cc-sysv-implicit-find dup if,
    nc-static @ if, [lit] 237 cc-die then,
    [lit] 24 + @ cc-sysv-compatible-signatures 0= if, [lit] 237 cc-die then,
  else, 2drop then, ;
\ A file-scope object cannot replace an earlier implicit external function;
\ a typedef or a block-local object has no conflicting external linkage.
: cc-sysv-implicit-declarator
  nc-top @ nc-func @ 0= and nc-td @ 0= and if,
    nc-name @ nc-nlen @ cc-sysv-implicit-find if, [lit] 237 cc-die then,
  then, ;
' cc-sysv-implicit-declarator is cc-sysv-implicit-declarator-fwd
: cc-sysv-check-implicit-defined
  cc-sysv-implicit-head @ begin, dup while,
    dup [lit] 32 + @ over [lit] 40 + @ or if, [lit] 206 cc-die then, @
  repeat, drop ;

: cc-sysv-symbol-signature ( id -- signature )
  dup cc-sym-kind-of sk-func = if,
    cc-sysv-signatures cell[] @
  else,
    dup cc-sym-type-of cc-sysv-function-pointer? 0= if, [lit] 230 cc-die then,
    cc-sym-struct-desc-of
  then, cc-sysv-check-signature ;
: cc-sysv-call-qualified
  cc-target-sysv @ if, cc-sysv-symbol-signature cc-field-qualified
  else, drop [lit] 0 then, ;
' cc-sysv-call-qualified is cc-native-call-qualified-fwd

: cc-sysv-function-desc
  cc-target-sysv @ if, cc-sysv-symbol-signature
  else, cc-native-function-desc then, ;
' cc-sysv-function-desc is cc-native-function-desc-fwd
: cc-sysv-call-result
  cc-target-sysv @ if,
    cc-sysv-symbol-signature dup cc-sysv-sig-return swap cc-sysv-sig-desc
  else, cc-native-call-result then, ;
' cc-sysv-call-result is cc-native-call-result-fwd

\ Stage each argument in an eight-byte temporary, converting fixed arguments
\ to the prototype's actual width before the register/stack split.
: cc-sysv-argument-check-default ( signature index -- ) 2drop ;
defer cc-sysv-argument-check-fwd
' cc-sysv-argument-check-default is cc-sysv-argument-check-fwd
: cc-sysv-parse-args ( signature -- count )
  [lit] 0 cc-next-token-keep
  [char] ) cc-tok-punct? 0= if,
    cc-putback-token
    begin,
      dup cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
      cc-parse-assign-fwd cc-emit-materialize
      2dup cc-sysv-argument-check-fwd
      cc-expr-unevaluated @ 0= if, cc-last-expr-type @ cc-sysv-check-scalar-default then,
      over cc-sysv-sig-count over > [lit] 2 cc-npick cc-sysv-prototype? and if,
        2dup cc-sysv-sig-param @
        cc-expr-unevaluated @ 0= if, dup cc-sysv-check-scalar-default then,
        cc-last-expr-type @ swap cc-emit-convert-value
      else,
        over cc-sysv-sig-varargs [lit] 3 and 0= if, [lit] 235 cc-die then,
        cc-last-expr-type @ cc-unary-type cc-emit-convert-rdi
      then,
      cc-emit-push-rdi 1+
      cc-next-token-keep [char] , cc-tok-punct? 0=
    until,
    [char] ) cc-tok-punct? 0= if, [lit] 121 cc-die then,
  then,
  over cc-sysv-prototype? if,
    over cc-sysv-sig-count over > if, [lit] 235 cc-die then,
  then,
  nip dup cc-native-reverse-args ;

\ Count actual expression/argument pushes, separately from lexical switch
\ saves. A call snapshots the complete surviving span, including outer-call
\ arguments and switch RBX saves; its own argument vector is transient.
variable cc-sysv-stack-depth
: cc-sysv-track-push
  cc-target-sysv @ if, [lit] 1 cc-sysv-stack-depth +! then, ;
: cc-sysv-track-pop
  cc-target-sysv @ if,
    cc-sysv-stack-depth @ 0= if, [lit] 239 cc-die then,
    [lit] 1 cc-sysv-stack-depth -!
  then, ;
' cc-sysv-track-push is cc-emit-track-push-fwd
' cc-sysv-track-pop is cc-emit-track-pop-fwd

: cc-sysv-stack-count [lit] 6 - dup 0< if, drop [lit] 0 then, ;
: cc-sysv-load-staged ( index modrm -- )
  cc-emit-byte [lit] 8 * cc-emit-4le ;
: cc-sysv-load-gp ( index -- )
  dup [lit] 4 < if, [lit] 73 else, [lit] 77 then, cc-emit-byte
  [lit] 139 cc-emit-byte
  dup [lit] 0 = if, [lit] 187 else,
  dup [lit] 1 = if, [lit] 179 else,
  dup [lit] 2 = if, [lit] 147 else,
  dup [lit] 3 = if, [lit] 139 else,
  dup [lit] 4 = if, [lit] 131 else, [lit] 139
  then, then, then, then, then, cc-sysv-load-staged ;
: cc-sysv-store-outgoing ( offset -- )
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 132 cc-emit-byte [lit] 36 cc-emit-byte cc-emit-4le ;
\ Call record: RSP frame slot, surviving cell count, staged cell count.
: cc-sysv-save-live ( record -- )
  >r
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  r@ @ [lit] 101 cc-emit-local-ea                \ mov [rbp+slot],rsp
  [lit] 0 begin, dup r@ [lit] 8 + @ < while,
    [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
    [lit] 188 cc-emit-byte [lit] 36 cc-emit-byte
    dup r@ [lit] 16 + @ + [lit] 8 * cc-emit-4le
    dup r@ @ + 1+ cc-emit-store-local
    1+
  repeat, drop r> drop ;
: cc-sysv-restore-live ( record -- )
  >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  r@ @ [lit] 101 cc-emit-local-ea                \ mov rsp,[rbp+slot]
  [lit] 0 begin, dup r@ [lit] 8 + @ < while,
    dup r@ @ + 1+ cc-emit-load-local
    [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
    [lit] 188 cc-emit-byte [lit] 36 cc-emit-byte
    dup r@ [lit] 16 + @ + [lit] 8 * cc-emit-4le
    1+
  repeat, drop r> drop ;
: cc-sysv-prepare-call ( count indirect? -- record )
  >r dup r> if, 1+ then,
  [lit] 24 cc-alloc dup >r [lit] 16 + !
  cc-sysv-stack-depth @ r@ [lit] 16 + @ -
  dup 0< if, [lit] 239 cc-die then,
  cc-switch-depth @ + dup r@ [lit] 8 + !
  cc-expr-unevaluated @ if,
    drop [lit] 0 r@ ! [lit] 0 r@ [lit] 8 + !
  else,
    cc-fn-local-count @ r@ ! 1+ cc-fn-add-slots
  then,
  r@ cc-sysv-save-live
  \ Align a fresh outgoing block below every staged and surviving value.
  [lit] 73 cc-emit-byte [lit] 137 cc-emit-byte [lit] 227 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 129 cc-emit-byte [lit] 236 cc-emit-byte
  dup cc-sysv-stack-count [lit] 8 * [lit] 15 + cc-emit-4le
  [lit] 72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 228 cc-emit-byte [lit] 240 cc-emit-byte
  [lit] 6 begin, 2dup > while,
    [lit] 73 cc-emit-byte [lit] 139 cc-emit-byte
    dup [lit] 131 cc-sysv-load-staged
    dup [lit] 6 - [lit] 8 * cc-sysv-store-outgoing
    1+
  repeat, drop
  [lit] 0 begin, 2dup > over [lit] 6 < and while,
    dup cc-sysv-load-gp 1+
  repeat, 2drop r> ;
: cc-sysv-finish-call ( count indirect? record -- )
  >r 2drop r@ cc-sysv-restore-live
  r@ [lit] 16 + @ dup cc-sysv-stack-depth @ swap - cc-sysv-stack-depth !
  cc-native-drop-args r> drop
  cc-emit-mov-rdi-rax ;
: cc-sysv-zero-vector-count
  [lit] 49 cc-emit-byte [lit] 192 cc-emit-byte ;
: cc-sysv-call-staged-target ( count -- )
  \ r10 is independent of AL, which reports zero vector arguments.
  [lit] 77 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 147 cc-sysv-load-staged
  cc-sysv-zero-vector-count
  [lit] 65 cc-emit-byte [lit] 255 cc-emit-byte [lit] 210 cc-emit-byte ;
defer cc-sysv-result-value-fwd
' cc-emit-convert-rdi is cc-sysv-result-value-fwd

: cc-sysv-call ( id -- )
  cc-target-sysv @ 0= if, cc-parse-native-call exit, then,
  cc-check-static-init
  dup cc-sysv-symbol-signature >r
  dup cc-sym-kind-of sk-func <> if,
    dup cc-sym-kind-of sk-local = if,
      cc-sym-val-of cc-emit-load-local
    else, cc-sym-val-of cc-emit-global-ref cc-emit-load-via-rdi then,
    cc-emit-push-rdi
    r@ cc-sysv-parse-args dup true cc-sysv-prepare-call >r
    dup cc-sysv-call-staged-target true r> cc-sysv-finish-call
  else,
    r@ cc-sysv-parse-args dup [lit] 0 cc-sysv-prepare-call >r >r
    cc-sysv-zero-vector-count
    dup cc-sym-val-of 0= if,
      cc-emit-call-rel32-placeholder
      cc-expr-unevaluated @ if, 2drop
      else, swap cc-sym-call-fixups cc-add-fixup-to-list then,
    else, cc-sym-val-of cc-emit-call-vaddr then,
    r> [lit] 0 r> cc-sysv-finish-call
  then,
  r> cc-sysv-sig-return cc-sysv-result-value-fwd ;
' cc-sysv-call is cc-native-call-fwd
: cc-sysv-check-callable ( type -- )
  dup ty-base ty-func <> swap ty-ptr [lit] 1 > or if, [lit] 230 cc-die then, ;
: cc-sysv-indirect-call
  cc-target-sysv @ 0= if, cc-parse-indirect-call exit, then,
  cc-check-static-init
  cc-last-expr-type @ cc-sysv-check-callable
  cc-last-struct-desc @ cc-sysv-check-signature >r
  cc-emit-materialize cc-emit-push-rdi
  r@ cc-sysv-parse-args dup true cc-sysv-prepare-call >r
  dup cc-sysv-call-staged-target true r> cc-sysv-finish-call
  r@ cc-sysv-sig-return dup cc-sysv-result-value-fwd
  r> dup cc-field-qualified >r cc-sysv-sig-desc cc-mark-typed-value
  r> cc-last-expr-qualified ! ;
' cc-sysv-indirect-call is cc-native-indirect-fwd

\ RBX is the only callee-saved expression register. RBP is saved by090;
\ R12..R15 are never touched. Reserve local slot0 before any parameters.
: cc-sysv-restore-callee
  cc-target-sysv @ if,
    [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
    [lit] 93 cc-emit-byte [lit] 248 cc-emit-byte
  then, ;
' cc-sysv-restore-callee is cc-emit-restore-callee-fwd
: cc-sysv-save-callee
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 93 cc-emit-byte [lit] 248 cc-emit-byte ;
: cc-sysv-store-gp ( index -- )
  dup 1+ swap
  dup [lit] 0 = if, drop cc-emit-store-local exit, then,
  dup [lit] 1 = if, drop cc-emit-store-local-from-rsi exit, then,
  dup [lit] 2 = if, drop cc-emit-store-local-from-rdx exit, then,
  dup [lit] 3 = if, drop cc-emit-store-local-from-rcx exit, then,
  dup [lit] 4 = if, drop cc-emit-store-local-from-r8 exit, then,
  drop cc-emit-store-local-from-r9 ;
\ K&R declarations refine the identifier list by name, preserving order.
\ Undeclared parameters keep C90's implicit int. Only register storage is
\ permitted here; a declaration outside the identifier list is an error.
: cc-sysv-abi-type-default ( type descriptor -- ) drop cc-sysv-check-scalar-default ;
defer cc-sysv-abi-type-fwd
' cc-sysv-abi-type-default is cc-sysv-abi-type-fwd
: cc-sysv-old-parameters ( sig -- )
  cc-nctx @ >r cc-ncontext
  begin, [char] { cc-tok-punct? 0= while,
    cc-sysv-parameter-base nc-sdesc ! nc-base !
    begin,
      cc-ndeclarator
      cc-sysv-adjust-function-parameter
      cc-sysv-adjust-array-parameter
      nc-ty @ nc-desc @ cc-sysv-abi-type-fwd
      nc-ty @ ty-size 0= if, [lit] 233 cc-die then,
      dup nc-name @ nc-nlen @ cc-sysv-find-parameter
      dup 0< if, [lit] 233 cc-die then,
      2dup cc-sysv-sig-name dup [lit] 16 + @ if, [lit] 233 cc-die then,
      true swap [lit] 16 + !
      over swap cc-sysv-sig-param
      nc-qualified @ over cc-field-set-qualified
    nc-ty @ over ! nc-desc @ swap [lit] 8 + !
      [char] , cc-tok-punct?
    while, repeat,
    [char] ; cc-tok-punct? 0= if, [lit] 233 cc-die then,
    cc-next-token-keep
  repeat, drop r> cc-nctx ! ;
: cc-sysv-params ( sig -- )
  dup cc-sysv-sig-count cc-native-param-count !
  [lit] 0 begin, over cc-sysv-sig-count over > while,
    2dup cc-sysv-sig-name dup @ nc-name ! [lit] 8 + @ nc-nlen !
    nc-nlen @ 0= if, [lit] 233 cc-die then,
    2dup cc-sysv-sig-param cc-field-qualified nc-qualified !
    2dup cc-sysv-parameter-type nc-desc ! nc-ty !
    nc-ty @ cc-sysv-check-scalar-default
    [lit] 0 nc-array ! [lit] 0 nc-inner !
    sk-local over 1+ cc-ninstall-symbol drop
    [lit] 1 cc-fn-add-slots 1+
  repeat, 2drop ;

\ Later target layers may implement variadic definitions; the default
\ remains a checked rejection until their register-save machinery exists.
: cc-sysv-varargs-prepare-default ( signature -- )
  cc-sysv-sig-varargs [lit] 1 and if, [lit] 236 cc-die then, ;
: cc-sysv-varargs-save-default ;
defer cc-sysv-varargs-prepare-fwd
defer cc-sysv-varargs-save-fwd
' cc-sysv-varargs-prepare-default is cc-sysv-varargs-prepare-fwd
' cc-sysv-varargs-save-default is cc-sysv-varargs-save-fwd

defer cc-sysv-params-fwd
' cc-sysv-params is cc-sysv-params-fwd
: cc-sysv-store-params-default
  [lit] 0 begin, dup cc-native-param-count @ < while,
    dup [lit] 6 < if, dup cc-sysv-store-gp else,
      [lit] 0 over [lit] 3 - - cc-emit-load-local
      dup 1+ cc-emit-store-local
    then, 1+
  repeat, drop ;
defer cc-sysv-store-params-fwd
' cc-sysv-store-params-default is cc-sysv-store-params-fwd
: cc-sysv-return-check-default ( type descriptor -- ) drop cc-sysv-check-scalar ;
defer cc-sysv-return-check-fwd
' cc-sysv-return-check-default is cc-sysv-return-check-fwd

variable cc-sysv-frame-patch
variable cc-sysv-function-signature
: cc-sysv-function
  cc-target-sysv @ 0= if, cc-native-function exit, then,
  cc-lex-state-size cc-alloc dup cc-lex-mark >r
  nc-params cc-lex-reset
  nc-ty @ nc-desc @ cc-sysv-signature cc-sysv-function-signature !
  r> cc-lex-reset
  cc-sysv-function-signature @ cc-sysv-sig-varargs [lit] 4 and if,
    cc-sysv-function-signature @ cc-sysv-old-parameters
  then,
  cc-sysv-function-signature @ cc-sysv-check-implicit-signature
  nc-name @ nc-nlen @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-func <> if, [lit] 237 cc-die then,
    dup cc-sysv-symbol-signature cc-sysv-function-signature @
    cc-sysv-compatible-signatures 0= if, [lit] 237 cc-die then,
  then,
  dup 0< if,
    drop nc-name @ nc-nlen @ sk-func nc-ty @ [lit] 0 cc-sym-add
    nc-desc @ over cc-sym-set-struct-desc
    [lit] 0 over cc-sysv-signatures cell[] !
  then,
  nc-id !
  nc-id @ cc-sysv-signatures cell[] @ dup if,
    cc-sysv-prototype? cc-sysv-function-signature @ cc-sysv-prototype? 0= and
  else, drop [lit] 0 then, 0= if,
    cc-sysv-function-signature @ nc-id @ cc-sysv-signatures cell[] !
  then,
  nc-ty @ nc-id @ cc-sym-type cell[] !
  nc-desc @ nc-id @ cc-sym-set-struct-desc
  [char] { cc-tok-punct? 0= if, exit, then,
  nc-ty @ nc-desc @ cc-sysv-return-check-fwd
  nc-id @ cc-sym-val-of if, [lit] 211 cc-die then,
  cc-here-vaddr nc-id @ cc-sym-val cell[] !
  nc-id @ cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
  [lit] 0 nc-id @ cc-sym-call-fixups !
  nc-id @ cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-imm64-to-vaddr
  [lit] 0 nc-id @ cc-sym-addr-fixups !
  nc-name @ nc-nlen @ cc-is-main? if, cc-here-vaddr cc-main-vaddr ! then,
  nc-ty @ cc-native-return-type ! nc-desc @ cc-native-return-desc !
  cc-nctx @ >r cc-ncontext cc-scope-push
  [lit] 1 cc-fn-local-count ! [lit] 0 cc-label-count !
  [lit] 0 cc-sysv-stack-depth !
  [lit] 0 cc-break-stack-head ! [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth ! [lit] 0 cc-loop-switch-depth !
  cc-sysv-function-signature @ cc-sysv-params-fwd
  cc-sysv-function-signature @ cc-sysv-varargs-prepare-fwd
  [lit] 0 cc-emit-prologue
  cc-out-pos @ [lit] 4 - cc-sysv-frame-patch ! cc-sysv-save-callee
  cc-sysv-varargs-save-fwd
  cc-sysv-store-params-fwd
  begin,
    cc-next-token-keep [char] } cc-tok-punct? 0= while,
    cc-putback-token cc-parse-stmt
  repeat,
  cc-sysv-stack-depth @ if, [lit] 239 cc-die then,
  cc-emit-xor-rax-rax cc-emit-epilogue cc-native-finish-gotos
  cc-fn-local-count @ [lit] 8 * [lit] 16 cc-nalign
  cc-sysv-frame-patch @ cc-out-patch-4le
  cc-scope-pop r> cc-nctx ! ;
' cc-sysv-function is cc-native-function-fwd

: cc-sysv-enable
  [lit] 0 cc-qualified-fields !
  [lit] 0 cc-sysv-implicit-head ! [lit] 0 cc-sysv-implicit-count !
  true cc-target-sysv ! true cc-target-lp64 ! true cc-prep-direct !
  [lit] 0 cc-bootstrap-floatbits ! ;
: cc-sysv-translation-unit
  begin,
    cc-skip-storage-quals cc-next-token-keep tok-kind @ tk-eof = 0= while,
    true cc-native-declaration
  repeat, ;
: cc-sysv-entry
  cc-native-init-entry-fwd
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte [lit] 60 cc-emit-byte [lit] 36 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte [lit] 116 cc-emit-byte [lit] 36 cc-emit-byte [lit] 8 cc-emit-byte
  cc-sysv-zero-vector-count cc-emit-call-rel32-placeholder cc-call-main-patch !
  cc-emit-mov-rdi-rax [lit] 184 cc-emit-byte [lit] 60 cc-emit-4le
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte ;
: cc-sysv-program
  cc-sysv-entry cc-sysv-translation-unit
  cc-native-init-finish-fwd cc-sysv-check-implicit-defined
  cc-check-fns-defined cc-patch-call-main ;
