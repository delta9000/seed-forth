\ 132-cc-long-double.fth -- x87 scalar computations on address values.
\ Every result is popped into a private sixteen-byte frame object. No x87
\ value survives a call, expression boundary or branch. Record ABI is 131.
\ Type-only conversion sites are preceded by descriptor shape checks.
\ Actual records use whole-object copies and never scalar conversions.
' cc-f80-allocate is cc-f80-new
: cc-x87-type? ( type -- flag )
  ty-struct [lit] 0 ty-make = cc-target-sysv @ and ;
: cc-x87-last? cc-last-expr-type @ cc-last-struct-desc @ cc-ld? ;
: cc-x87-op ( opcode modrm -- ) swap cc-emit-byte cc-emit-byte ;
: cc-x87-load [lit] 219 [lit] 47 cc-x87-op ; \ fld tbyte [rdi]
: cc-x87-save
  [lit] 16 cc-ag-frame cc-emit-lea-rdi-local
  [lit] 219 [lit] 63 cc-x87-op ;              \ fstp tbyte [rdi]
: cc-x87-stage ( opcode modrm -- )
  [lit] 8 cc-ag-frame dup cc-emit-store-local cc-emit-lea-rdi-local cc-x87-op ;
: cc-x87-power ( exponent -- )
  \ Exact power of two in extended format, constructed in a frame object.
  [lit] 16383 + >r 2^63 cc-emit-movabs-rdi-imm64
  [lit] 16 cc-ag-frame dup >r cc-emit-store-local
  r@ 1- r> r> cc-emit-mov-rdi-int
  >r cc-emit-store-local r> cc-emit-lea-rdi-local cc-x87-load ;
: cc-x87-truncate
  \ Save caller's control word, select truncation, fistp, then restore it.
  [lit] 16 cc-ag-frame dup >r cc-emit-lea-rdi-local
  [lit] 217 [lit] 63 cc-x87-op                \ fnstcw [rdi]
  [lit] 15 [lit] 183 cc-x87-op [lit] 7 cc-emit-byte
  [lit] 128 [lit] 204 cc-x87-op [lit] 12 cc-emit-byte \ or ah,12
  [lit] 102 [lit] 137 cc-x87-op [lit] 71 cc-emit-byte [lit] 2 cc-emit-byte
  [lit] 217 [lit] 111 cc-x87-op [lit] 2 cc-emit-byte \ fldcw [rdi+2]
  [lit] 223 [lit] 127 cc-x87-op [lit] 8 cc-emit-byte \ fistp qword [rdi+8]
  [lit] 217 [lit] 47 cc-x87-op                \ fldcw [rdi]
  r> 1- cc-emit-load-local ;
: cc-x87-to-u64
  [lit] 63 cc-x87-power                     \ st0=2^63, st1=x
  [lit] 223 [lit] 233 cc-x87-op              \ fucomip st0,st1
  [lit] 135 cc-fp-jcc >r                    \ ja: x < 2^63
  [lit] 63 cc-x87-power
  [lit] 222 [lit] 233 cc-x87-op              \ fsubp st1,st0
  cc-x87-truncate ty-ulong [lit] 0 ty-make cc-fp-flip-sign
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  cc-x87-truncate r> cc-patch-rel32-to-here ;
: cc-x87-convert ( source destination -- )
  2dup cc-x87-type? swap cc-x87-type? or 0= if, cc-fp-convert exit, then,
  2dup = if, 2drop exit, then,
  dup cc-x87-type? if,
    over cc-fp-type? if,
      over cc-f32-type? if, [lit] 217 else, [lit] 221 then,
      [lit] 7 cc-x87-stage
    else,
      over cc-const-integer? 0= if, cc-ld-die then,
      over cc-emit-convert-rdi
      over ty-unsigned? [lit] 2 cc-npick ty-size [lit] 8 = and if,
        cc-emit-test-rdi [lit] 137 cc-fp-jcc >r
        [lit] 223 [lit] 47 cc-x87-stage
        [lit] 64 cc-x87-power [lit] 222 [lit] 193 cc-x87-op
        cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
        [lit] 223 [lit] 47 cc-x87-stage r> cc-patch-rel32-to-here
      else, [lit] 223 [lit] 47 cc-x87-stage then,
    then,
    2drop cc-x87-save
  else,
    dup ty-void [lit] 0 ty-make = if, 2drop exit, then,
    cc-x87-load
    dup cc-fp-type? if,
      [lit] 8 cc-ag-frame dup >r cc-emit-lea-rdi-local
      dup cc-f32-type? if, [lit] 217 else, [lit] 221 then,
      [lit] 31 cc-x87-op r> cc-emit-load-local
    else,
      dup cc-bool-type? if,
        [lit] 217 [lit] 238 cc-x87-op        \ fldz
        [lit] 223 [lit] 233 cc-x87-op
        [lit] 221 [lit] 216 cc-x87-op        \ fstp st0
        [lit] 15 [lit] 149 cc-x87-op [lit] 192 cc-emit-byte
        [lit] 15 [lit] 154 cc-x87-op [lit] 194 cc-emit-byte
        [lit] 8 [lit] 208 cc-x87-op
        [lit] 15 [lit] 182 cc-x87-op [lit] 248 cc-emit-byte
      else,
        dup cc-const-integer? 0= if, cc-ld-die then,
        dup ty-unsigned? over ty-size [lit] 8 = and if,
          cc-x87-to-u64 else, cc-x87-truncate then,
      then,
    then, nip cc-emit-convert-rdi
  then, ;
' cc-x87-convert is cc-emit-convert-value
\ Initializers store integers at their destination width without a separate
\ conversion. Preserve that byte sequence unless an x87 value participates.
\ The shared record type code is insufficient: bitfield leaves do not run
\ a descriptor shape check, so reject actual records here as before 132.
: cc-x87-initialize ( source destination -- )
  over cc-ag-type? if,
    over cc-last-struct-desc @ cc-ld? 0= if, cc-ag-die then,
  then,
  2dup cc-x87-type? swap cc-x87-type? or if,
    cc-x87-convert
  else, cc-ag-initialize then, ;
' cc-x87-initialize is cc-value-init-fwd
: cc-x87-right
  2dup cc-x87-type? swap cc-x87-type? or 0= if, cc-fp-convert-right exit, then,
  cc-emit-push-rdi
  [lit] 72 [lit] 137 cc-x87-op [lit] 207 cc-emit-byte
  cc-x87-convert cc-emit-mov-rcx-rdi cc-emit-pop-rdi ;
' cc-x87-right is cc-emit-convert-right
: cc-x87-arithmetic? ( type descriptor -- flag )
  2dup cc-ld? >r drop dup cc-const-integer? swap cc-fp-type? or r> or ;
: cc-x87-common ( left right -- type )
  over cc-expr-left-desc @ cc-ld? over cc-expr-right-desc @ cc-ld? or if,
    over cc-expr-left-desc @ cc-x87-arithmetic?
    over cc-expr-right-desc @ cc-x87-arithmetic? and 0= if, cc-ld-die then,
    2dup cc-x87-type? swap cc-x87-type? or if,
      2drop ty-struct [lit] 0 ty-make exit,
    then,
  then, cc-ag-common-type ;
' cc-x87-common is cc-expr-common-type
: cc-x87-binop-check
  cc-expr-left-type @ cc-expr-left-desc @ cc-ld?
  cc-expr-right-type @ cc-expr-right-desc @ cc-ld? or if,
    cc-expr-op-row @ bo-op + @
    dup [char] + = over [char] - = or over [char] * = or over [char] / = or
    over [char] < = or over [char] > = or over pt-le = or over pt-ge = or
    over pt-eq-eq = or swap pt-bang-eq = or 0= if, cc-ld-die then,
  then, cc-sysv-array-binop ;
' cc-x87-binop-check is cc-array-binop-fwd
: cc-x87-binop
  cc-expr-common @ cc-x87-type? 0= if, cc-fp-binop exit, then,
  [lit] 219 [lit] 41 cc-x87-op cc-x87-load \ right then left
  cc-expr-op-row @ bo-op + @
  dup [char] + = if, drop [lit] 193 else,
  dup [char] - = if, drop [lit] 225 else,
  dup [char] * = if, drop [lit] 201 else,
  dup [char] / = if, drop [lit] 241 else,
    \ Reuse IEEE unordered comparison handling after x87 sets EFLAGS.
    [lit] 223 [lit] 233 cc-x87-op [lit] 221 [lit] 216 cc-x87-op
    dup [char] < = over [char] > = or over pt-le = or over pt-ge = or
    over pt-eq-eq = or over pt-bang-eq = or 0= if, cc-ld-die then,
    cc-fp-comparison-flags exit,
  then, then, then, then,
  [lit] 222 swap cc-x87-op cc-x87-save ;
' cc-x87-binop is cc-native-binop-emit
: cc-x87-test
  cc-x87-last? if,
    cc-last-expr-type @ ty-bool [lit] 0 ty-make cc-x87-convert cc-emit-test-rdi
  else, cc-ag-test then, ;
: cc-x87-not
  cc-x87-last? if,
    cc-x87-test cc-emit-not-zero-flag
  else, cc-ag-not then, ;
: cc-x87-negate
  cc-x87-last? if, cc-x87-load [lit] 217 [lit] 224 cc-x87-op cc-x87-save
  else, cc-ag-negate then, ;
: cc-x87-plus cc-x87-last? 0= if, cc-ag-plus then, ;
' cc-x87-test is cc-value-test-fwd
' cc-x87-not is cc-value-not-fwd
' cc-x87-negate is cc-value-negate-fwd
' cc-x87-plus is cc-value-plus-fwd
: cc-x87-change-check cc-x87-last? 0= if, cc-fp-change-check then, ;
: cc-x87-change
  cc-change-type @ cc-change-desc @ cc-ld? if,
    cc-x87-load [lit] 217 [lit] 232 cc-x87-op \ fld1
    cc-change-delta @ [lit] 1 = if, [lit] 193 else, [lit] 233 then,
    [lit] 222 swap cc-x87-op cc-x87-save
  else, cc-fp-change-value then, ;
' cc-x87-change-check is cc-change-check-fwd
' cc-x87-change is cc-change-value-fwd
: cc-x87-field-load ( type field -- )
  over cc-last-struct-desc @ cc-ld? if,
    2drop [lit] 16 cc-ag-frame dup >r [lit] 16 swap cc-ag-copy-to-slot r> cc-emit-lea-rdi-local
  else, cc-ag-field-load then, ;
: cc-x87-field-store ( type field -- )
  over cc-x87-type? if,
    2drop cc-x87-load [lit] 219 [lit] 57 cc-x87-op \ fstp tbyte [rcx]
  else, cc-bf-store then, ;
' cc-x87-field-load is cc-field-load-fwd
' cc-x87-field-store is cc-field-store-fwd
: cc-x87-shape ( source descriptor destination descriptor -- )
  [lit] 3 cc-npick [lit] 3 cc-npick cc-ld? [lit] 2 cc-npick [lit] 2 cc-npick cc-ld? or if,
    2dup cc-x87-arithmetic? [lit] 4 cc-npick [lit] 4 cc-npick cc-x87-arithmetic? and 0= if,
      cc-ld-die
    then,
  else,
    [lit] 3 cc-npick cc-ag-type? [lit] 2 cc-npick cc-ag-type? <> if, cc-ag-die then,
  then, cc-sysv-value-shape ;
' cc-x87-shape is cc-value-shape-fwd
' cc-x87-shape is cc-return-shape-fwd
: cc-x87-cast ( source destination -- )
  dup ty-void [lit] 0 ty-make = if, cc-ag-cast-types exit, then,
  over cc-last-struct-desc @ cc-ld? over cc-cast-desc @ cc-ld? or if,
    over cc-last-struct-desc @ [lit] 2 cc-npick cc-cast-desc @ cc-x87-shape
    2drop exit,
  then, cc-ag-cast-types ;
' cc-x87-cast is cc-cast-types-fwd
: cc-x87-ternary ( left-type left-desc inner null qualified patch -- handled? )
  [lit] 5 cc-npick [lit] 5 cc-npick cc-ld? cc-x87-last? or if,
    [lit] 0 exit,
  then, cc-ag-ternary ;
' cc-x87-ternary is cc-aggregate-ternary-fwd
: cc-x87-scalar-check ( type -- )
  dup cc-x87-type? if, drop else, cc-fp-scalar-check then, ;
' cc-x87-scalar-check is cc-sysv-check-scalar
: cc-x87-ni-scalar
  ni-type @ ni-desc @ cc-ld? 0= if, cc-om-scalar-initializer exit, then,
  cc-ni-static @ if, cc-ld-die then,
  ni-offset @ cc-ni-address cc-emit-push-rdi
  cc-putback-token cc-parse-assign cc-emit-materialize
  cc-last-expr-type @ cc-last-struct-desc @ ni-type @ ni-desc @ cc-value-shape-fwd
  cc-last-expr-type @ ni-type @ cc-x87-convert
  cc-ni-mov-rsi-rdi cc-emit-pop-rdi [lit] 16 cc-ni-copy-bytes
  cc-next-token-keep ;
' cc-x87-ni-scalar is cc-ni-scalar-fwd
: cc-x87-literal
  cc-target-sysv @ tok-kind @ tk-float = and 0= if, [lit] 0 exit, then,
  cc-const-float-spelling
  dup ty-base ty-ldouble = if,
    drop dup @ cc-emit-movabs-rdi-imm64
    [lit] 16 cc-ag-frame dup >r cc-emit-store-local
    [lit] 8 + @ cc-emit-movabs-rdi-imm64 r@ 1- cc-emit-store-local
    r> cc-emit-lea-rdi-local
    ty-struct [lit] 0 ty-make cc-ld-descriptor cc-mark-typed-value
  else, swap cc-emit-movabs-rdi-imm64 [lit] 0 cc-mark-typed-value then,
  true ;
' cc-x87-literal is cc-value-literal-fwd
: cc-x87-initializer
  ni-type @ ni-desc @ cc-ld? 0= if, cc-om-scalar-initializer exit, then,
  cc-ni-static @ if,
    cc-putback-token cc-parse-static-const-fwd
    if, cc-const-unsupported then, drop
    ty-ldouble [lit] 0 ty-make cc-const-change
    cc-sysv-object-mode @ if,
      dup @ cc-obj-data nc-slot @ om-offset @ ni-offset @ + [lit] 8 cc-obj-patch
      [lit] 8 + @ cc-obj-data nc-slot @ om-offset @ ni-offset @ + [lit] 8 +
      [lit] 8 cc-obj-patch
    else,
      dup @ >r ni-offset @ cc-ni-address cc-emit-mov-rcx-rdi
      r> cc-emit-movabs-rdi-imm64 ty-ulong [lit] 0 ty-make cc-emit-store-typed-via-rcx
      [lit] 8 + @ >r ni-offset @ [lit] 8 + cc-ni-address cc-emit-mov-rcx-rdi
      r> cc-emit-movabs-rdi-imm64 ty-ulong [lit] 0 ty-make cc-emit-store-typed-via-rcx
    then, cc-next-token-keep exit,
  then, cc-x87-ni-scalar ;
' cc-x87-initializer is cc-ni-scalar-fwd
