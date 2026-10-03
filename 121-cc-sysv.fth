\ 121-cc-sysv.fth — explicit scalar System V AMD64 target.
\ Loading this file changes no target. cc-sysv-enable opts in to LP64 and
\ INTEGER-class calls; floating and aggregate values fail closed.
variable cc-target-sysv
[lit] 0 cc-target-sysv !
[lit] 64 constant cc-sysv-arg-cap
[lit] 1398362966 constant cc-sysv-signature-tag
create cc-sysv-signatures cc-sym-cap [lit] 8 * allot

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
: cc-sysv-check-scalar ( ty -- )
  dup [lit] 256 / [lit] 255 and if, [lit] 231 cc-die then,
  dup ty-ptr if, drop exit, then,
  ty-base
  dup ty-struct = over ty-float = or over ty-double = or
  over ty-ldouble = or swap ty-func = or if, [lit] 232 cc-die then, ;
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
    dup cc-sym-array-len-of nc-base-array !
    dup cc-sym-array-inner-of nc-base-inner !
  then, ;
' cc-sysv-typedef-check is cc-ntypedef-check-fwd
\ Preserve array typedef shape through aliases and ordinary declarations.
\ The existing representation admits two dimensions, not pointers to arrays.
: cc-sysv-inherit-array
  nc-base-array @ if,
    nc-ty @ nc-base @ <> nc-func @ or if, [lit] 238 cc-die then,
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
  dup 0= 0= nc-base-array @ 0= 0= and if, [lit] 238 cc-die then,
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

: cc-sysv-check-declarator
  cc-target-sysv @ if,
    cc-sysv-inherit-array
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
    nc-inner @ if, [lit] 238 cc-die then,
    [lit] 1 nc-ty +! [lit] 0 nc-array !
  then, ;

defer cc-sysv-signature-fwd
: cc-sysv-fnptr
  cc-target-sysv @ 0= if, cc-nfnptr-default exit, then,
  if, [lit] 231 cc-die then,
  nc-ty @ nc-desc @ cc-sysv-signature-fwd nc-desc !
  ty-func [lit] 1 ty-make nc-ty ! ;
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
: cc-sysv-signature ( return-type return-desc -- signature )
  [lit] 2600 cc-alloc dup >r [lit] 2600 cc-nzero
  r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-sysv-signature-tag r@ !
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
    cc-nbase nc-sdesc ! nc-base ! cc-ndeclarator
    nc-func @ if, [lit] 233 cc-die then,
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
  ty-struct = if, r> r> = else, r> drop r> drop true then, ;
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

: cc-sysv-symbol-signature ( id -- signature )
  dup cc-sym-kind-of sk-func = if,
    cc-sysv-signatures cell[] @
  else,
    dup cc-sym-type-of ty-base ty-func <> if, [lit] 230 cc-die then,
    cc-sym-struct-desc-of
  then, cc-sysv-check-signature ;
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
: cc-sysv-parse-args ( signature -- count )
  [lit] 0 cc-next-token-keep
  [char] ) cc-tok-punct? 0= if,
    cc-putback-token
    begin,
      dup cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
      cc-parse-assign-fwd cc-emit-materialize
      cc-expr-unevaluated @ 0= if, cc-last-expr-type @ cc-sysv-check-scalar then,
      over cc-sysv-sig-count over > [lit] 2 cc-npick cc-sysv-prototype? and if,
        2dup cc-sysv-sig-param @ cc-emit-convert-rdi
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
  r> cc-sysv-sig-return cc-emit-convert-rdi ;
' cc-sysv-call is cc-native-call-fwd
: cc-sysv-indirect-call
  cc-target-sysv @ 0= if, cc-parse-indirect-call exit, then,
  cc-check-static-init
  cc-last-expr-type @ ty-base ty-func <> if, [lit] 230 cc-die then,
  cc-last-struct-desc @ cc-sysv-check-signature >r
  cc-emit-materialize cc-emit-push-rdi
  r@ cc-sysv-parse-args dup true cc-sysv-prepare-call >r
  dup cc-sysv-call-staged-target true r> cc-sysv-finish-call
  r@ cc-sysv-sig-return dup cc-emit-convert-rdi
  r> cc-sysv-sig-desc cc-mark-typed-value ;
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
: cc-sysv-old-parameters ( sig -- )
  cc-nctx @ >r cc-ncontext
  begin, [char] { cc-tok-punct? 0= while,
    kw-register cc-tok-kw? if, cc-next-token-keep then,
    cc-nbase nc-sdesc ! nc-base !
    begin,
      cc-ndeclarator
      nc-func @ if, [lit] 233 cc-die then,
      cc-sysv-adjust-array-parameter
      nc-ty @ cc-sysv-check-scalar
      nc-ty @ ty-size 0= if, [lit] 233 cc-die then,
      dup nc-name @ nc-nlen @ cc-sysv-find-parameter
      dup 0< if, [lit] 233 cc-die then,
      2dup cc-sysv-sig-name dup [lit] 16 + @ if, [lit] 233 cc-die then,
      true swap [lit] 16 + !
      over swap cc-sysv-sig-param
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
    2dup cc-sysv-parameter-type nc-desc ! nc-ty !
    nc-ty @ cc-sysv-check-scalar
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
  nc-ty @ cc-sysv-check-scalar
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
  cc-sysv-function-signature @ cc-sysv-params
  cc-sysv-function-signature @ cc-sysv-varargs-prepare-fwd
  [lit] 0 cc-emit-prologue
  cc-out-pos @ [lit] 4 - cc-sysv-frame-patch ! cc-sysv-save-callee
  cc-sysv-varargs-save-fwd
  [lit] 0 begin, dup cc-native-param-count @ < while,
    dup [lit] 6 < if, dup cc-sysv-store-gp else,
      [lit] 0 over [lit] 3 - - cc-emit-load-local
      dup 1+ cc-emit-store-local
    then, 1+
  repeat, drop
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
  cc-native-init-finish-fwd cc-check-fns-defined cc-patch-call-main ;
