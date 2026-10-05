\ 126-cc-varargs.fth — INTEGER/binary64 System V AMD64 variadic callees.
\ va_list is the real 24-byte record array[1], declared by stdarg.h.
\ Six GP and eight XMM slots belong to each invocation below named parameters.
\ Binary64 retrieval consumes XMM or overflow slots; 131 supplies named ABI offsets.
create cc-va-error-prefix s, varargs: bl c,
: cc-va-die cc-va-error-prefix [lit] 9 cc-err-write cc-die ;

variable cc-va-signature
variable cc-va-register-slot

: cc-va-prepare ( signature -- )
  dup cc-va-signature !
  cc-sysv-sig-varargs [lit] 1 and if,
    cc-fn-local-count @ [lit] 1 and if, [lit] 1 cc-fn-add-slots then,
    cc-fn-local-count @ [lit] 21 + cc-va-register-slot !
    [lit] 22 cc-fn-add-slots
  then, ;
: cc-va-save-xmm ( index -- )
  [lit] 15 cc-emit-byte [lit] 17 cc-emit-byte
  dup [lit] 8 * [lit] 133 + cc-emit-byte \ movups [rbp+disp32], xmmN
  [lit] 16 * [lit] 48 +
  cc-va-register-slot @ 1+ [lit] 8 * - cc-emit-4le ;
: cc-va-save-registers
  cc-va-signature @ cc-sysv-sig-varargs [lit] 1 and if,
    cc-va-register-slot @ dup cc-emit-store-local
    1- dup cc-emit-store-local-from-rsi
    1- dup cc-emit-store-local-from-rdx
    1- dup cc-emit-store-local-from-rcx
    1- dup cc-emit-store-local-from-r8
    1- cc-emit-store-local-from-r9
    [lit] 0 begin, dup [lit] 8 < while,
      dup cc-va-save-xmm 1+
    repeat, drop
  then, ;

create cc-va-tag-name s, __seed_va_list_tag
: cc-va-field ( descriptor index offset type -- )
  >r >r cc-sd-field-rec
  dup cc-sf-offset r> <> if, [lit] 246 cc-va-die then,
  dup cc-sf-type r> <> if, [lit] 246 cc-va-die then,
  cc-sf-array-len if, [lit] 246 cc-va-die then, ;
: cc-va-descriptor ( -- descriptor )
  cc-va-tag-name [lit] 18 cc-nfind-tag
  dup 0< if, [lit] 246 cc-va-die then, cc-sym-val-of
  dup cc-sd-total-size [lit] 24 <> if, [lit] 246 cc-va-die then,
  dup cc-sd-align [lit] 8 <> if, [lit] 246 cc-va-die then,
  dup cc-sd-field-count [lit] 4 <> if, [lit] 246 cc-va-die then,
  dup cc-sd-union? if, [lit] 246 cc-va-die then,
  dup [lit] 0 [lit] 0 ty-uint [lit] 0 ty-make cc-va-field
  dup [lit] 1 [lit] 4 ty-uint [lit] 0 ty-make cc-va-field
  dup [lit] 2 [lit] 8 ty-void [lit] 1 ty-make cc-va-field
  dup [lit] 3 [lit] 16 ty-void [lit] 1 ty-make cc-va-field ;
: cc-va-expect ( punctuation -- )
  cc-next-token-keep cc-tok-punct? 0= if, [lit] 246 cc-va-die then, ;
: cc-va-operand
  cc-parse-assign-fwd
  cc-last-expr-type @ ty-struct [lit] 1 ty-make <> if,
    [lit] 246 cc-va-die
  then,
  cc-last-struct-desc @ cc-va-descriptor <> if, [lit] 246 cc-va-die then,
  cc-last-expr-array-inner @ if, [lit] 246 cc-va-die then,
  cc-emit-materialize ;
: cc-va-void-result
  [lit] 0 cc-emit-mov-rdi-int
  ty-void [lit] 0 ty-make [lit] 0 cc-mark-typed-value ;

\ rdi addresses the list. These helpers do not move that address.
: cc-va-store-u32 ( value displacement -- )
  [lit] 199 cc-emit-byte
  dup if, [lit] 71 cc-emit-byte cc-emit-byte
  else, drop [lit] 7 cc-emit-byte then,
  cc-emit-4le ;
: cc-va-store-frame-address ( frame-offset list-offset -- )
  >r [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
  [lit] 133 cc-emit-byte cc-emit-4le       \ lea rax, [rbp+disp32]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 71 cc-emit-byte r> cc-emit-byte ; \ mov [rdi+disp8], rax
: cc-va-last-named
  cc-va-signature @ dup 0= if, [lit] 246 cc-va-die then,
  dup cc-sysv-sig-varargs [lit] 1 and 0= if, [lit] 246 cc-va-die then,
  dup cc-sysv-sig-count 1- cc-sysv-sig-name
  cc-next-token-keep
  tok-kind @ tk-ident <> if, [lit] 246 cc-va-die then,
  dup [lit] 8 + @ tok-str-len @ <> if, [lit] 246 cc-va-die then,
  @ tok-str-addr @ tok-str-len @ bytes-eq 0= if, [lit] 246 cc-va-die then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, [lit] 246 cc-va-die then,
  dup cc-sym-kind-of sk-local <> if, [lit] 246 cc-va-die then,
  cc-sym-val-of cc-va-signature @ cc-sysv-sig-count <> if,
    [lit] 246 cc-va-die
  then, ;
: cc-va-layout-default ( -- gp-offset fp-offset overflow-offset )
  cc-va-signature @ cc-sysv-sig-count dup [lit] 6 > if,
    drop [lit] 6
  then, [lit] 8 * [lit] 48
  cc-va-signature @ cc-sysv-sig-count cc-sysv-stack-count [lit] 8 * [lit] 16 + ;
defer cc-va-layout-fwd
' cc-va-layout-default is cc-va-layout-fwd
: cc-va-start
  cc-va-operand [char] , cc-va-expect
  cc-va-last-named [char] ) cc-va-expect
  cc-va-layout-fwd >r swap [lit] 0 cc-va-store-u32
  [lit] 4 cc-va-store-u32 r> [lit] 8 cc-va-store-frame-address
  [lit] 0 cc-va-register-slot @ 1+ [lit] 8 * -
  [lit] 16 cc-va-store-frame-address
  cc-va-void-result ;

\ Choose the next eight-byte INTEGER slot, updating only that list's cursor.
\ The caller then loads the requested four- or eight-byte value from rdi.
: cc-va-next-address
  [lit] 139 cc-emit-byte [lit] 7 cc-emit-byte         \ mov eax, [rdi]
  [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte [lit] 48 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 131 cc-emit-byte        \ jae overflow
  cc-out-pos @ [lit] 0 cc-emit-4le >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 16 cc-emit-byte         \ mov rcx, [rdi+16]
  [lit] 72 cc-emit-byte [lit] 1 cc-emit-byte [lit] 193 cc-emit-byte
  [lit] 131 cc-emit-byte [lit] 7 cc-emit-byte [lit] 8 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 207 cc-emit-byte
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 71 cc-emit-byte [lit] 8 cc-emit-byte          \ mov rax, [rdi+8]
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 8 cc-emit-byte          \ lea rcx, [rax+8]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 8 cc-emit-byte          \ mov [rdi+8], rcx
  cc-emit-mov-rdi-rax r> cc-patch-rel32-to-here ;
\ Choose the next SSE slot for double, preserving gp_offset. Only the low
\ eight bytes of each sixteen-byte XMM save slot are the binary64 payload.
\ A stack double requires eight-byte alignment, already maintained by every
\ supported INTEGER/double overflow access and the incoming ABI stack area.
: cc-va-next-double-address
  [lit] 139 cc-emit-byte [lit] 71 cc-emit-byte [lit] 4 cc-emit-byte
  [lit] 61 cc-emit-byte [lit] 176 cc-emit-4le        \ cmp eax, 176
  [lit] 15 cc-emit-byte [lit] 131 cc-emit-byte        \ jae overflow
  cc-out-pos @ [lit] 0 cc-emit-4le >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 16 cc-emit-byte         \ mov rcx, [rdi+16]
  [lit] 72 cc-emit-byte [lit] 1 cc-emit-byte [lit] 193 cc-emit-byte
  [lit] 131 cc-emit-byte [lit] 71 cc-emit-byte
  [lit] 4 cc-emit-byte [lit] 16 cc-emit-byte         \ add dword [rdi+4],16
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 207 cc-emit-byte
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 71 cc-emit-byte [lit] 8 cc-emit-byte          \ mov rax, [rdi+8]
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 8 cc-emit-byte          \ lea rcx, [rax+8]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 8 cc-emit-byte          \ mov [rdi+8], rcx
  cc-emit-mov-rdi-rax r> cc-patch-rel32-to-here ;
: cc-va-check-result-type ( type -- )
  dup [lit] 256 / [lit] 255 and if, [lit] 247 cc-va-die then,
  dup ty-ptr if, drop exit, then,
  ty-base dup ty-int = over ty-uint = or
  over ty-long = or over ty-ulong = or over ty-llong = or over ty-ullong = or
  swap ty-double = or 0= if, [lit] 247 cc-va-die then, ;
: cc-va-arg
  cc-va-operand [char] , cc-va-expect
  cc-next-token-keep cc-native-type-name-fwd
  cc-type-name-array @ cc-type-name-inner @ or if, [lit] 247 cc-va-die then,
  dup cc-va-check-result-type cc-cast-desc @ >r >r
  [char] ) cc-va-expect
  r@ ty-double [lit] 0 ty-make = if,
    cc-va-next-double-address
  else, cc-va-next-address then,
  r@ cc-emit-load-typed-via-rdi
  r> r> cc-mark-typed-value ;
: cc-va-copy-word ( displacement -- )
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 71 cc-emit-byte dup cc-emit-byte             \ mov rax, [rdi+disp8]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 65 cc-emit-byte cc-emit-byte ;               \ mov [rcx+disp8], rax
: cc-va-copy
  cc-va-operand cc-emit-push-rdi [char] , cc-va-expect
  cc-va-operand [char] ) cc-va-expect cc-emit-pop-rcx
  [lit] 0 cc-va-copy-word [lit] 8 cc-va-copy-word [lit] 16 cc-va-copy-word
  cc-va-void-result ;
: cc-va-end
  cc-va-operand [char] ) cc-va-expect cc-va-void-result ;

create cc-va-start-name s, __builtin_va_start
create cc-va-arg-name s, __builtin_va_arg
create cc-va-copy-name s, __builtin_va_copy
create cc-va-end-name s, __builtin_va_end
: cc-va-name? ( name length -- flag )
  dup tok-str-len @ <> if, 2drop [lit] 0 exit, then,
  tok-str-addr @ swap bytes-eq ;
: cc-va-intrinsic ( -- handled? )
  cc-target-sysv @ 0= if, [lit] 0 exit, then,
  cc-va-start-name [lit] 18 cc-va-name? if, [lit] 1 else,
  cc-va-arg-name [lit] 16 cc-va-name? if, [lit] 2 else,
  cc-va-copy-name [lit] 17 cc-va-name? if, [lit] 3 else,
  cc-va-end-name [lit] 16 cc-va-name? if, [lit] 4 else,
    [lit] 0 exit,
  then, then, then, then,
  cc-check-static-init lparen cc-va-expect
  dup [lit] 1 = if, drop cc-va-start else,
  dup [lit] 2 = if, drop cc-va-arg else,
  [lit] 3 = if, cc-va-copy else, cc-va-end then, then, then,
  true ;
' cc-va-prepare is cc-sysv-varargs-prepare-fwd
' cc-va-save-registers is cc-sysv-varargs-save-fwd
' cc-va-intrinsic is cc-native-intrinsic-fwd
