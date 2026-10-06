\ 131-cc-aggregate-abi.fth -- shared INTEGER/binary32/binary64/X87/MEMORY SysV ABI.
\ Record expressions carry addresses. The ABI transports object bytes, never
\ that address: up to two INTEGER eightbytes, otherwise a private stack copy.
\ Long double (121) is X87: a sixteen-aligned stack copy, returned in st(0).
\ Records cross prototyped, unprototyped and variadic calls alike, and
\ va_arg retrieves them. Floating members and vector classes are not implemented.
create cc-ag-error-prefix s, aggregate-abi: bl c,
: cc-ag-die cc-ag-error-prefix [lit] 15 cc-err-write [lit] 232 cc-die ;
: cc-ag-type? ( type -- flag )
  dup ty-ptr 0= swap ty-base ty-struct = and cc-target-sysv @ and ;

\ Validate each nested member, including members of unions and arrays.
\ A descriptor with an unaligned member is MEMORY; the current parser emits
\ natural layouts, but the classifier does not rely on this coincidence.
\ The walk notes whether it met a long double leaf and any other leaf.
variable cc-ag-x87
variable cc-ag-other
defer cc-ag-walk-fwd
: cc-ag-walk ( type descriptor offset -- unaligned? )
  >r
  \ A ranked field must validate its real element, including floating leaves.
  over ty-base ty-array = [lit] 2 cc-npick ty-ptr 0= and if,
    nip dup cc-ad-type swap cc-ad-desc r> cc-ag-walk-fwd exit,
  then,
  2dup cc-ld? if,
    2drop true cc-ag-x87 ! r> [lit] 16 cc-mod 0= 0= exit,
  then,
  over cc-ag-type? 0= if,
    true cc-ag-other !
    drop dup ty-ptr 0= if,
      dup ty-base dup ty-float = over ty-double = or
      swap ty-ldouble = or if, cc-ag-die then,
    then,
    dup cc-sysv-check-scalar-default ty-align r> swap cc-mod 0= 0= exit,
  then,
  nip dup 0= if, cc-ag-die then,
  dup cc-sd-total-size 0= if, cc-ag-die then,
  dup cc-sd-align dup [lit] 16 > if, cc-ag-die then,
  r@ swap cc-mod 0= 0= swap
  [lit] 0 begin, over cc-sd-field-count over > while,
    2dup cc-sd-field-rec
    dup cc-sf-array-len [lit] 0 < if, cc-ag-die then,
    dup cc-sf-type over cc-sf-desc
    [lit] 2 cc-npick cc-sf-offset r@ + cc-ag-walk-fwd
    >r drop rot r> or rot rot 1+
  repeat, 2drop r> drop ;
' cc-ag-walk is cc-ag-walk-fwd
\ Class is zero for MEMORY, one/two INTEGER eightbytes, three for scalar SSE
\ and four for X87: sixteen bytes holding only long double leaves, which an
\ argument passes like MEMORY and a result returns in st(0). Any other leaf
\ sharing an eightbyte with X87 makes the whole object MEMORY.
: cc-ag-class ( type descriptor -- class )
  over cc-fp-type? if, 2drop [lit] 3 exit, then,
  over cc-ag-type? 0= if, cc-sysv-abi-type-default [lit] 1 exit, then,
  [lit] 0 cc-ag-x87 ! [lit] 0 cc-ag-other !
  2dup [lit] 0 cc-ag-walk >r nip cc-sd-total-size
  dup cc-sysv-object-size-limit > if, cc-ag-die then,
  cc-ag-x87 @ if,
    [lit] 16 = cc-ag-other @ 0= and r> 0= and if, [lit] 4 else, [lit] 0 then,
    exit,
  then,
  dup [lit] 16 > r> or if, drop [lit] 0 else, [lit] 7 + [lit] 8 / then, ;
: cc-ag-abi-type ( type descriptor -- ) cc-ag-class drop ;
' cc-ag-abi-type is cc-sysv-abi-type-fwd
: cc-ag-return-check ( type descriptor -- )
  over cc-ag-type? if, cc-ag-abi-type else, cc-sysv-return-check-default then, ;
' cc-ag-return-check is cc-sysv-return-check-fwd

\ Materializing a record does not fetch its first word. Assignment and
\ initialization consume the address and perform the existing byte copy.
: cc-ag-field-load ( type field -- )
  over cc-ag-type? if, 2drop else, cc-bf-load then, ;
' cc-ag-field-load is cc-field-load-fwd
: cc-ag-assignment
  cc-target-sysv @ if,
    cc-last-expr-type @ cc-assign-type @ <>
    cc-last-struct-desc @ cc-assign-desc @ <> or if, cc-ag-die then,
  then, ;
' cc-ag-assignment is cc-aggregate-assignment-fwd

\ A plan owns explicit argument locations. Nothing relies on the argument
\ index also being a register index. Each record is type, descriptor, byte
\ size, class, first GP register (-1 for stack), stack offset and frame slot.
variable cc-ag-plan
: ag-signature cc-ag-plan @ ;
: ag-count cc-ag-plan @ [lit] 8 + ;
: ag-gp cc-ag-plan @ [lit] 16 + ;
: ag-stack cc-ag-plan @ [lit] 24 + ;
: ag-result cc-ag-plan @ [lit] 32 + ;
: ag-return-class cc-ag-plan @ [lit] 40 + ;
: ag-return-size cc-ag-plan @ [lit] 48 + ;
: ag-indirect cc-ag-plan @ [lit] 56 + ;
: ag-live cc-ag-plan @ [lit] 64 + ;
: ag-target cc-ag-plan @ [lit] 72 + ;
: ag-fp cc-ag-plan @ [lit] 80 + ;
: ag-arg ( index -- record ) [lit] 64 * [lit] 96 + cc-ag-plan @ + ;
: ag-type @ ;
: ag-desc [lit] 8 + @ ;
: ag-size [lit] 16 + @ ;
: ag-class [lit] 24 + @ ;
: ag-register [lit] 32 + @ ;
: ag-offset [lit] 40 + @ ;
: ag-slot [lit] 48 + @ ;
: cc-ag-frame ( bytes -- slot )
  [lit] 7 + [lit] 8 / dup cc-fn-local-count @ + 1-
  swap cc-expr-unevaluated @ if, drop else, cc-fn-add-slots then, ;
: cc-ag-new-plan ( signature -- )
  dup cc-sysv-sig-varargs [lit] 3 and if,
    cc-sysv-arg-cap
  else, dup cc-sysv-sig-count then,
  [lit] 64 * [lit] 96 + dup cc-alloc dup cc-ag-plan ! swap cc-nzero
  ag-signature ! true ag-result ! true ag-return-class !
  ag-signature @ cc-sysv-sig-return cc-ag-type? if,
    ag-signature @ cc-sysv-signature-result cc-ag-class ag-return-class !
    ag-signature @ cc-sysv-sig-desc cc-sd-total-size ag-return-size !
    ag-return-class @ 0= if, [lit] 1 ag-gp ! then,
  then, ;
\ Records and long double have one ABI in every prototype form: default
\ promotions leave them unchanged, so prototyped, variadic and unprototyped
\ calls, and every definition form, classify them alike.
: cc-ag-check-entry ( signature -- )
  \ K&R float parameters arrive as promoted doubles, but the local declared
  \ type is float. Reject until entry conversion has its own transport type.
  dup cc-sysv-sig-varargs [lit] 4 and if,
    [lit] 0 begin, over cc-sysv-sig-count over > while,
      2dup cc-sysv-sig-param @ cc-f32-type? if, cc-ag-die then, 1+
    repeat, drop
  then,
  drop ;
: cc-ag-locate ( type descriptor index -- )
  ag-arg >r
  2dup cc-ag-class r@ [lit] 24 + !
  2dup cc-nsize dup [lit] 0 <= if, cc-ag-die then, r@ [lit] 16 + !
  r@ [lit] 8 + ! r@ !
  r@ ag-class [lit] 3 = if,
    ag-fp @ [lit] 8 < if,
      ag-fp @ r@ [lit] 32 + ! [lit] 1 ag-fp +!
    else, true r@ [lit] 32 + ! then,
  else,
    r@ ag-class dup 0= over [lit] 4 = or over ag-gp @ + [lit] 6 > or if,
      drop true r@ [lit] 32 + !
    else, ag-gp @ r@ [lit] 32 + ! ag-gp +! then,
  then,
  \ Stack copies keep their own alignment, at least eight: X87 takes sixteen.
  r@ ag-register [lit] 0 < if,
    ag-stack @ r@ ag-type r@ ag-desc cc-nalignment [lit] 8 cc-nmax cc-nalign
    dup ag-stack ! r@ [lit] 40 + !
    r@ ag-size [lit] 8 cc-nalign ag-stack +!
  then,
  r@ ag-size cc-ag-frame r> [lit] 48 + ! ;

\ Register numbers are the psABI sequence RDI, RSI, RDX, RCX, R8, R9.
: cc-ag-store-gp ( slot register -- )
  dup [lit] 0 = if, drop cc-emit-store-local exit, then,
  dup [lit] 1 = if, drop cc-emit-store-local-from-rsi exit, then,
  dup [lit] 2 = if, drop cc-emit-store-local-from-rdx exit, then,
  dup [lit] 3 = if, drop cc-emit-store-local-from-rcx exit, then,
  dup [lit] 4 = if, drop cc-emit-store-local-from-r8 exit, then,
  drop cc-emit-store-local-from-r9 ;
: cc-ag-load-gp ( slot register -- )
  dup [lit] 4 < if, [lit] 72 else, [lit] 76 then, cc-emit-byte
  [lit] 139 cc-emit-byte
  dup [lit] 0 = if, drop [lit] 125 else,
  dup [lit] 1 = if, drop [lit] 117 else,
  dup [lit] 2 = if, drop [lit] 85 else,
  dup [lit] 3 = if, drop [lit] 77 else,
  [lit] 4 = if, [lit] 69 else, [lit] 77
  then, then, then, then, then, cc-emit-local-ea ;
\ Scalar SSE arguments use only the low eight bytes of XMM0..XMM7.
: cc-ag-xmm-local ( slot register opcode -- )
  [lit] 242 cc-emit-byte [lit] 15 cc-emit-byte cc-emit-byte
  [lit] 8 * [lit] 69 + cc-emit-local-ea ;
: cc-ag-store-xmm [lit] 17 cc-ag-xmm-local ;
: cc-ag-load-xmm [lit] 16 cc-ag-xmm-local ;
: cc-ag-copy-to-slot ( size slot -- )
  cc-ni-mov-rsi-rdi cc-emit-lea-rdi-local cc-ni-copy-bytes ;

\ Each argument is frozen in the fixed frame when its expression finishes.
\ Nested calls and alloca may move RSP without moving these object copies.
: cc-ag-parse-arguments
  cc-next-token-keep [char] ) cc-tok-punct? if,
    ag-signature @ cc-sysv-sig-count if, [lit] 235 cc-die then, exit,
  then, cc-putback-token
  begin,
    ag-count @ cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
    cc-parse-assign-fwd cc-emit-materialize
    ag-count @ ag-signature @ cc-sysv-sig-count <
    ag-signature @ cc-sysv-prototype? and if,
      ag-signature @ ag-count @ cc-sysv-parameter-type
    else,
      ag-signature @ cc-sysv-sig-varargs [lit] 3 and 0= if, [lit] 235 cc-die then,
      \ Default promotions leave records and long double unchanged.
      cc-last-expr-type @ cc-last-struct-desc @
      2dup cc-ld? [lit] 2 cc-npick cc-ag-type? or 0= if,
        drop dup cc-sysv-check-scalar cc-sysv-default-type cc-last-struct-desc @
      then,
    then,
    2dup >r >r cc-last-expr-type @ cc-last-struct-desc @ r> r> cc-value-shape-fwd
    ag-count @ cc-ag-locate
    ag-count @ ag-arg >r
    r@ ag-type cc-ag-type? if,
      cc-last-expr-type @ r@ ag-type <>
      cc-last-struct-desc @ r@ ag-desc <> or if, cc-ag-die then,
      r@ ag-size r@ ag-slot cc-ag-copy-to-slot
    else,
      cc-last-expr-type @ cc-sysv-check-scalar
      cc-last-expr-type @ r@ ag-type cc-emit-convert-value
      r@ ag-slot cc-emit-store-local
    then, r> drop
    [lit] 1 ag-count +!
    cc-next-token-keep [char] , cc-tok-punct? 0=
  until,
  [char] ) cc-tok-punct? 0= if, [lit] 121 cc-die then,
  ag-signature @ cc-sysv-prototype? if,
    ag-count @ ag-signature @ cc-sysv-sig-count < if, [lit] 235 cc-die then,
  then, ;
: cc-ag-prepare-call
  [lit] 24 cc-alloc dup ag-live ! [lit] 24 cc-nzero
  cc-sysv-stack-depth @ cc-switch-depth @ + dup ag-live @ [lit] 8 + !
  cc-expr-unevaluated @ if,
    drop [lit] 0 ag-live @ [lit] 8 + !
  else,
    cc-fn-local-count @ ag-live @ ! 1+ cc-fn-add-slots
  then,
  ag-live @ cc-sysv-save-live
  [lit] 72 cc-emit-byte [lit] 129 cc-emit-byte [lit] 236 cc-emit-byte
  ag-stack @ [lit] 15 + cc-emit-4le
  [lit] 72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 228 cc-emit-byte [lit] 240 cc-emit-byte
  \ Stack copies precede register loads because REP MOVSB uses GP arguments.
  [lit] 0 begin, dup ag-count @ < while,
    dup ag-arg dup ag-register [lit] 0 < if,
      dup ag-slot cc-emit-lea-rdi-local cc-ni-mov-rsi-rdi
      [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
      [lit] 188 cc-emit-byte [lit] 36 cc-emit-byte dup ag-offset cc-emit-4le
      dup ag-size cc-ni-copy-bytes
    then, drop 1+
  repeat, drop
  ag-return-class @ 0= if, ag-result @ cc-emit-lea-rdi-local then,
  [lit] 0 begin, dup ag-count @ < while,
    dup ag-arg dup ag-register [lit] 0 >= if,
      dup ag-class [lit] 3 = if,
        dup ag-slot over ag-register cc-ag-load-xmm
      else,
        [lit] 0 begin, over ag-class over > while,
          over ag-slot over - [lit] 2 cc-npick ag-register [lit] 2 cc-npick + cc-ag-load-gp
          1+
        repeat, drop
      then,
    then, drop 1+
  repeat, drop ;
: cc-ag-result
  ag-return-class @ [lit] 4 = if,
    [lit] 219 cc-emit-byte ag-result @ [lit] 125 cc-emit-local-ea \ fstp tbyte
    ag-live @ cc-sysv-restore-live ag-result @ cc-emit-lea-rdi-local exit,
  then,
  ag-return-class @ [lit] 0 >= if,
    ag-return-class @ if,
      [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
      ag-result @ [lit] 69 cc-emit-local-ea
      ag-return-class @ [lit] 2 = if,
        ag-result @ 1- cc-emit-store-local-from-rdx
      then,
    then,
    ag-live @ cc-sysv-restore-live
    ag-result @ cc-emit-lea-rdi-local
  else,
    ag-live @ cc-sysv-restore-live cc-emit-mov-rdi-rax
    ag-signature @ cc-sysv-sig-return cc-sysv-result-value-fwd
  then, ;
: cc-ag-emit-call
  cc-ag-parse-arguments cc-ag-prepare-call
  [lit] 184 cc-emit-byte ag-fp @ cc-emit-4le
  ag-indirect @ if,
    [lit] 76 cc-emit-byte [lit] 139 cc-emit-byte
    ag-target @ [lit] 85 cc-emit-local-ea \ mov r10,[rbp+slot]
    [lit] 65 cc-emit-byte [lit] 255 cc-emit-byte [lit] 210 cc-emit-byte
  else,
    ag-target @ dup cc-sym-val-of 0= if,
      cc-emit-call-rel32-placeholder
      cc-expr-unevaluated @ if, 2drop
      else, swap cc-sym-call-fixups cc-add-fixup-to-list then,
    else, cc-sym-val-of cc-emit-call-vaddr then,
  then, cc-ag-result ;
: cc-ag-call-begin ( signature -- )
  dup cc-ag-check-entry cc-ag-new-plan
  ag-return-class @ [lit] 0 >= if,
    ag-return-size @ cc-ag-frame ag-result !
  then, ;
: cc-ag-save-target
  true ag-indirect ! [lit] 8 cc-ag-frame dup ag-target ! cc-emit-store-local ;
: cc-ag-call ( id -- )
  cc-target-sysv @ 0= cc-expr-unevaluated @ or if, cc-sysv-call exit, then,
  dup cc-sysv-symbol-signature
  cc-check-static-init cc-ag-plan @ >r cc-ag-call-begin
  dup cc-sym-kind-of sk-func = if, ag-target ! else,
    dup cc-sym-kind-of sk-local = if, cc-sym-val-of cc-emit-load-local
    else, cc-sym-val-of cc-emit-global-ref cc-emit-load-via-rdi then,
    cc-ag-save-target
  then,
  cc-ag-emit-call r> cc-ag-plan ! ;
' cc-ag-call is cc-native-call-fwd
: cc-ag-indirect-call
  cc-target-sysv @ 0= cc-expr-unevaluated @ or if, cc-sysv-indirect-call exit, then,
  cc-last-expr-type @ cc-sysv-check-callable
  cc-last-struct-desc @ cc-sysv-check-signature
  cc-check-static-init cc-ag-plan @ >r cc-ag-call-begin
  cc-emit-materialize cc-ag-save-target cc-ag-emit-call
  ag-signature @ cc-sysv-signature-result cc-mark-typed-value
  ag-signature @ cc-field-qualified cc-last-expr-qualified !
  r> cc-ag-plan ! ;
' cc-ag-indirect-call is cc-native-indirect-fwd

variable cc-ag-function-plan
variable cc-ag-sret-slot
: cc-ag-parameters ( signature -- )
  [lit] 0 cc-ag-function-plan !
  dup cc-ag-check-entry cc-ag-plan @ >r cc-ag-new-plan
  cc-ag-plan @ cc-ag-function-plan !
  ag-return-class @ 0= if, [lit] 8 cc-ag-frame cc-ag-sret-slot ! then,
  ag-signature @ cc-sysv-sig-count cc-native-param-count !
  [lit] 0 begin, dup cc-native-param-count @ < while,
    ag-signature @ over cc-sysv-sig-param cc-field-qualified nc-qualified !
    ag-signature @ over cc-sysv-parameter-type [lit] 2 cc-npick cc-ag-locate
    ag-signature @ over cc-sysv-sig-name
    dup @ nc-name ! [lit] 8 + @ nc-nlen !
    nc-nlen @ 0= if, [lit] 233 cc-die then,
    dup ag-arg dup ag-type nc-ty ! dup ag-desc nc-desc !
    [lit] 0 nc-array ! [lit] 0 nc-inner !
    ag-slot sk-local swap cc-ninstall-symbol drop 1+
  repeat, drop r> cc-ag-plan ! ;
' cc-ag-parameters is cc-sysv-params-fwd
: cc-ag-store-parameters
  cc-ag-function-plan @ 0= if, cc-sysv-store-params-default exit, then,
  cc-ag-plan @ >r cc-ag-function-plan @ cc-ag-plan !
  ag-return-class @ 0= if, cc-ag-sret-slot @ cc-emit-store-local then,
  \ Spill all register parameters before a stack copy clobbers any register.
  [lit] 0 begin, dup cc-native-param-count @ < while,
    dup ag-arg dup ag-register [lit] 0 >= if,
      dup ag-class [lit] 3 = if,
        dup ag-slot over ag-register cc-ag-store-xmm
      else,
        [lit] 0 begin, over ag-class over > while,
          over ag-slot over - [lit] 2 cc-npick ag-register [lit] 2 cc-npick + cc-ag-store-gp
          1+
        repeat, drop
      then,
    then, drop 1+
  repeat, drop
  [lit] 0 begin, dup cc-native-param-count @ < while,
    dup ag-arg dup ag-register [lit] 0 < if,
      [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
      [lit] 181 cc-emit-byte dup ag-offset [lit] 16 + cc-emit-4le
      dup ag-slot cc-emit-lea-rdi-local dup ag-size cc-ni-copy-bytes
    then, drop 1+
  repeat, drop r> cc-ag-plan ! ;
' cc-ag-store-parameters is cc-sysv-store-params-fwd

\ Return expressions keep their descriptor until the full object is copied.
\ MEMORY returns use the caller's separate result object and return its
\ address in RAX. Small returns are staged to avoid reading beyond the source.
: cc-ag-convert ( source destination -- )
  over cc-ag-type? over ty-void [lit] 0 ty-make = and if, 2drop exit, then,
  2dup cc-ag-type? swap cc-ag-type? or if,
    2dup <> if, cc-ag-die then, 2drop
  else, cc-fp-convert then, ;
' cc-ag-convert is cc-emit-convert-value
\ Scalar initializer paths retain their source type before storing bytes.
: cc-ag-initialize ( source destination -- )
  over cc-ag-type? over cc-ag-type? or if, cc-ag-die then,
  cc-fp-initialize ;
' cc-ag-initialize is cc-value-init-fwd
: cc-ag-return
  cc-last-expr-type @ cc-last-struct-desc @
  cc-native-return-type @ cc-native-return-desc @ cc-value-shape-fwd
  cc-last-expr-type @ cc-ag-type?
  cc-native-return-type @ ty-void [lit] 0 ty-make = and if, cc-ag-die then,
  cc-native-return-type @ cc-ag-type? 0= if, cc-fp-return exit, then,
  cc-last-expr-type @ cc-native-return-type @ <>
  cc-last-struct-desc @ cc-native-return-desc @ <> or if, cc-ag-die then,
  cc-native-return-type @ cc-native-return-desc @ cc-ag-class
  dup [lit] 4 = if, drop [lit] 219 cc-emit-byte [lit] 47 cc-emit-byte exit, then, \ fld tbyte [rdi]
  dup 0= if,
    drop cc-ni-mov-rsi-rdi cc-ag-sret-slot @ cc-emit-load-local
    cc-emit-mov-rax-rdi
    cc-native-return-desc @ cc-sd-total-size cc-ni-copy-bytes
  else,
    >r cc-native-return-desc @ cc-sd-total-size dup cc-ag-frame >r
    r@ cc-ag-copy-to-slot
    [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte r@ [lit] 69 cc-emit-local-ea
    r> r> [lit] 2 = if,
      1- [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte [lit] 85 cc-emit-local-ea
    else, drop then,
  then, ;
' cc-ag-return is cc-value-return-fwd

\ An address representation is not permission to use a record as a scalar.
\ Explicit record casts remain outside this value contract. Long double
\ shares the representation; every computing use is error 249 instead.
: cc-ag-scalar-use ( type -- ) dup cc-ag-type? if, cc-ag-die then, drop ;
: cc-ld-scalar-use ( type descriptor -- )
  over swap cc-ld? if, cc-ld-die then, cc-ag-scalar-use ;
: cc-ag-last-use cc-last-expr-type @ cc-last-struct-desc @ cc-ld-scalar-use ;
: cc-ag-plus cc-ag-last-use ;
' cc-ag-plus is cc-value-plus-fwd
: cc-ag-common-type ( left right -- type )
  over cc-expr-left-desc @ cc-ld-scalar-use
  dup cc-expr-right-desc @ cc-ld-scalar-use cc-fp-common-type ;
' cc-ag-common-type is cc-expr-common-type
: cc-ag-test cc-ag-last-use cc-fp-test ;
: cc-ag-not cc-ag-last-use cc-fp-not ;
: cc-ag-negate cc-ag-last-use cc-fp-negate ;
: cc-ag-complement cc-ag-last-use cc-fp-complement ;
: cc-ag-integer-use
  dup cc-last-struct-desc @ cc-ld-scalar-use cc-fp-integer-use ;
' cc-ag-test is cc-value-test-fwd
' cc-ag-not is cc-value-not-fwd
' cc-ag-negate is cc-value-negate-fwd
' cc-ag-complement is cc-value-complement-fwd
' cc-ag-integer-use is cc-value-integer-use-fwd

\ The join sees the selected arm's address. Freeze its complete object into
\ a fresh fixed-frame slot before any later expression can change an arm.
\ Every syntactic conditional owns storage, including nested conditionals;
\ sizeof checks identity but allocates no frame and emits no copy.
: cc-ag-ternary ( left-type left-desc inner null qualified true-fixup -- handled? )
  [lit] 5 cc-npick cc-ag-type? cc-last-expr-type @ cc-ag-type? or 0= if,
    [lit] 0 exit,
  then,
  cc-patch-rel32-to-here
  drop 2drop
  2dup cc-last-expr-type @ cc-last-struct-desc @ cc-ld-mismatch
  over cc-last-expr-type @ <> over cc-last-struct-desc @ <> or if, cc-ag-die then,
  dup 0= if, cc-ag-die then,
  cc-expr-unevaluated @ 0= if,
    cc-check-static-init
    dup cc-sd-total-size dup [lit] 0 <= over cc-sysv-object-size-limit > or if, cc-ag-die then,
    dup cc-ag-frame dup >r cc-ag-copy-to-slot r> cc-emit-lea-rdi-local
  then,
  cc-mark-typed-value lv-temporary cc-last-lvalue-kind ! true ;
' cc-ag-ternary is cc-aggregate-ternary-fwd


\ C type constraints apply inside sizeof even when no ABI code is emitted.
\ Leave the old scalar grammar and the metadata-only fallback intact; check
\ only the aggregate identities introduced by this layer's value contract.
: cc-ag-argument-check ( signature index -- )
  over cc-sysv-sig-count over > [lit] 2 cc-npick cc-sysv-prototype? and if,
    cc-sysv-parameter-type
    2dup >r >r cc-last-expr-type @ cc-last-struct-desc @ r> r> cc-value-shape-fwd
    over cc-ag-type? cc-last-expr-type @ cc-ag-type? or if,
      cc-last-expr-type @ cc-last-struct-desc @
      cc-sysv-compatible-types 0= if, cc-ag-die then,
    else, 2drop then,
  else, 2drop then, ;
' cc-ag-argument-check is cc-sysv-argument-check-fwd

\ A cast must never relabel a smaller object's address as a larger record.
\ Runtime and constant cast parsers share this pure policy hook. Valid
\ descriptor-checked assignments and returns bypass explicit cast parsing.
: cc-ag-cast-types ( source destination -- )
  dup ty-void [lit] 0 ty-make = if, cc-sysv-cast-types exit, then,
  \ A long double cast to its own type moves nothing; any other needs x87.
  over cc-last-struct-desc @ cc-ld? over cc-cast-desc @ cc-ld?
  2dup and if, 2drop 2drop exit, then,
  or if, cc-ld-die then,
  over cc-ag-type? over cc-ag-type? or if, cc-ag-die then,
  cc-sysv-cast-types ;
' cc-ag-cast-types is cc-cast-types-fwd

\ va_start uses the same named-argument plan as callee entry. GP and SSE
\ exhaustion are independent; overflow begins after all named stack bytes.
: cc-ag-va-layout ( -- gp-offset fp-offset overflow-offset )
  cc-ag-plan @ >r cc-ag-function-plan @ cc-ag-plan !
  ag-gp @ [lit] 8 * ag-fp @ [lit] 16 * [lit] 48 +
  ag-stack @ [lit] 16 + r> cc-ag-plan ! ;
' cc-ag-va-layout is cc-va-layout-fwd
: cc-ag-va-last-slot ( -- slot )
  cc-ag-plan @ >r cc-ag-function-plan @ cc-ag-plan !
  ag-signature @ cc-sysv-sig-count 1- ag-arg ag-slot r> cc-ag-plan ! ;
' cc-ag-va-last-slot is cc-va-last-slot-fwd
\ va_arg of a record: an INTEGER record whose eightbytes all fit in the
\ remaining GP save slots is read there, where they are consecutive; any
\ other record comes from the overflow area, aligned as the caller stored
\ it. The value is the record's address, like every record value.
: cc-ag-va-record ( type descriptor -- )
  2dup cc-ag-class >r
  r@ [lit] 1 = r@ [lit] 2 = or if,
    [lit] 139 cc-emit-byte [lit] 7 cc-emit-byte         \ mov eax, [rdi]
    [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte
    [lit] 49 r@ [lit] 8 * - cc-emit-byte                \ cmp eax, 49-8n
    [lit] 15 cc-emit-byte [lit] 131 cc-emit-byte        \ jae overflow
    cc-out-pos @ [lit] 0 cc-emit-4le >r
    [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
    [lit] 79 cc-emit-byte [lit] 16 cc-emit-byte         \ mov rcx, [rdi+16]
    [lit] 72 cc-emit-byte [lit] 1 cc-emit-byte [lit] 193 cc-emit-byte
    [lit] 131 cc-emit-byte [lit] 7 cc-emit-byte
    r> r@ [lit] 8 * cc-emit-byte >r                     \ add dword [rdi], 8n
    [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 207 cc-emit-byte
    cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  else, [lit] 0 >r then,
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 71 cc-emit-byte [lit] 8 cc-emit-byte            \ mov rax, [rdi+8]
  2dup cc-nalignment [lit] 8 > if,
    [lit] 72 cc-emit-byte [lit] 131 cc-emit-byte
    [lit] 192 cc-emit-byte [lit] 15 cc-emit-byte        \ add rax, 15
    [lit] 72 cc-emit-byte [lit] 131 cc-emit-byte
    [lit] 224 cc-emit-byte [lit] 240 cc-emit-byte       \ and rax, -16
  then,
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte [lit] 136 cc-emit-byte
  2dup cc-nsize [lit] 8 cc-nalign cc-emit-4le           \ lea rcx, [rax+size]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 8 cc-emit-byte            \ mov [rdi+8], rcx
  cc-emit-mov-rdi-rax
  r> dup if, cc-patch-rel32-to-here else, drop then, r> drop
  cc-mark-typed-value ;
' cc-ag-va-record is cc-va-record-fwd

\ Long double crosses no type boundary: assignment, arguments, results and
\ initializers accept only long double, copied whole. A static initializer
\ would need its x87 bytes at compile time, so it is rejected too.
: cc-ld-value-shape ( source descriptor destination descriptor -- )
  [lit] 3 cc-npick [lit] 3 cc-npick [lit] 3 cc-npick [lit] 3 cc-npick
  cc-ld-mismatch cc-sysv-value-shape ;
' cc-ld-value-shape is cc-value-shape-fwd
: cc-ld-ni-scalar
  ni-type @ ni-desc @ cc-ld? 0= if, cc-om-scalar-initializer exit, then,
  cc-ni-static @ if, cc-ld-die then,
  ni-offset @ cc-ni-address cc-emit-push-rdi
  cc-putback-token cc-parse-assign
  cc-last-expr-type @ cc-last-struct-desc @ ni-type @ ni-desc @ cc-ld-mismatch
  cc-ni-mov-rsi-rdi cc-emit-pop-rdi [lit] 16 cc-ni-copy-bytes
  cc-next-token-keep ;
' cc-ld-ni-scalar is cc-ni-scalar-fwd
' cc-ld-mismatch is cc-return-shape-fwd
: cc-ld-compound ( type descriptor -- ) cc-ld? if, cc-ld-die then, ;
' cc-ld-compound is cc-aggregate-compound-fwd
