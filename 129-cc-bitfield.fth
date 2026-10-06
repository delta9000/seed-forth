\ 129-cc-bitfield.fth -- AMD64 little-endian integer record bitfields.
\ Only the explicit SysV target changes descriptor or member semantics.
\ Named int/unsigned/long/unsigned long fields use their natural 4/8-byte
\ allocation units; a _Bool field is at most one bit in a one-byte unit. Stores preserve every bit outside the destination.
\ Volatile accesses use ordinary unit loads and RMW stores; no atomicity
\ or inter-thread synchronization is provided, and compound updates can
\ perform an operand load plus the preserving RMW load.
create cc-bf-error-prefix s, bitfield: bl c,
: cc-bf-die cc-bf-error-prefix [lit] 10 cc-err-write [lit] 248 cc-die ;
: cc-bf-record-bytes
  cc-target-sysv @ if, [lit] 72 else, cc-sd-record-bytes-default then, ;
' cc-bf-record-bytes is cc-sd-record-bytes

\ The final SysV field cell retains the second fixed array dimension.
\ Bitfield slots stay at48/56; anonymous promotion copies the entire record.
: cc-bf-array-inner ( rec -- n )
  cc-target-sysv @ if, [lit] 64 + @ else, cc-sf-array-inner-default then, ;
: cc-bf-set-array-inner ( n rec -- )
  cc-target-sysv @ if, [lit] 64 + ! else, cc-sf-set-array-inner-default then, ;
' cc-bf-array-inner is cc-sf-array-inner
' cc-bf-set-array-inner is cc-sf-set-array-inner

: cc-sd-bit-end [lit] 32 + ;
: cc-sf-bit-width [lit] 48 + @ ;
: cc-sf-bit-shift [lit] 56 + @ ;
: cc-bf? ( rec -- flag )
  cc-target-sysv @ over [lit] 0 <> and if, cc-sf-bit-width else, drop [lit] 0 then, ;
\ Enum representation is a separate capability. Preserve provenance through
\ typedefs so enum fields cannot silently acquire signed-int bit semantics.
create cc-bf-enum-origin [lit] 0 ,
: cc-bf-enum-desc
  cc-target-sysv @ if, cc-bf-enum-origin else, [lit] 0 then, ;
' cc-bf-enum-desc is cc-nenum-desc-fwd

: cc-bf-type? ( ty -- flag )
  dup ty-ptr if, drop [lit] 0 exit, then,
  ty-base dup ty-int = over ty-uint = or over ty-long = or over ty-ulong = or
  over ty-llong = or over ty-ullong = or swap ty-bool = or ;

variable cc-bf-desc
variable cc-bf-width
variable cc-bf-unit
variable cc-bf-position
variable cc-bf-record
: cc-bf-add ( desc -- )
  cc-bf-desc !
  nc-desc @ cc-bf-enum-origin = if, cc-bf-die then,
  nc-ty @ cc-bf-type? 0= nc-array @ [lit] 0 <> or
  nc-inner @ [lit] 0 <> or nc-func @ [lit] 0 <> or if, cc-bf-die then,
  cc-parse-const cc-bf-width !
  nc-ty @ ty-size [lit] 8 * cc-bf-unit !
  cc-bf-width @ [lit] 0 < cc-bf-width @ cc-bf-unit @ > or if, cc-bf-die then,
  cc-bf-width @ [lit] 32 > cc-bf-width @ [lit] 64 < and if, cc-bf-die then,
  nc-ty @ ty-base ty-bool = cc-bf-width @ [lit] 1 > and if, cc-bf-die then,
  cc-bf-width @ 0= nc-nlen @ [lit] 0 <> and if, cc-bf-die then,
  cc-bf-desc @ cc-sd-union? if, [lit] 0 else, cc-bf-desc @ cc-sd-bit-end @ then,
  cc-bf-position !
  cc-bf-width @ 0= if,
    cc-bf-position @ cc-bf-unit @ cc-nalign cc-bf-position !
  else,
    cc-bf-position @ cc-bf-unit @ cc-mod cc-bf-width @ + cc-bf-unit @ > if,
      cc-bf-position @ cc-bf-unit @ cc-nalign cc-bf-position !
    then,
    nc-nlen @ if,
      cc-bf-desc @ cc-sd-field-count cc-bf-desc @ swap cc-sd-field-rec cc-bf-record !
      nc-name @ cc-bf-record @ cc-sf-set-name-addr
      nc-nlen @ cc-bf-record @ cc-sf-set-name-len
      nc-ty @ cc-bf-record @ cc-sf-set-type
      cc-bf-position @ cc-bf-unit @ / cc-bf-unit @ * [lit] 8 /
      cc-bf-record @ cc-sf-set-offset
      cc-bf-width @ cc-bf-record @ [lit] 48 + !
      cc-bf-position @ cc-bf-unit @ cc-mod cc-bf-record @ [lit] 56 + !
      cc-bf-desc @ dup cc-sd-field-count 1+ swap cc-sd-set-field-count
      cc-bf-desc @ cc-sd-align nc-ty @ ty-align cc-nmax cc-bf-desc @ cc-sd-set-align
    then,
    cc-bf-width @ cc-bf-position +!
  then,
  cc-bf-position @ [lit] 7 + [lit] 8 /
  cc-bf-desc @ cc-sd-total-size cc-nmax cc-bf-desc @ cc-sd-set-total-size
  cc-bf-position @ cc-bf-desc @ cc-sd-bit-end !
  cc-next-token-keep ;
\ Products are checked by the declarator; sums and final tail padding
\ must also fit, including when a bitfield follows a maximal matrix.
: cc-bf-layout-check ( desc -- )
  dup cc-sd-total-size swap cc-sd-align cc-nalign
  cc-sysv-object-size-limit > if, [lit] 245 cc-die then, ;
: cc-bf-member ( desc -- )
  cc-target-sysv @ 0= if, cc-nmember-default exit, then,
  [char] : cc-tok-punct? if, dup >r cc-bf-add r> cc-bf-layout-check exit, then,
  \ An incomplete outer dimension cannot describe an inline matrix.
  nc-inner @ nc-array @ [lit] 0 <= and if, [lit] 238 cc-die then,
  dup >r cc-nmember-default
  r@ cc-bf-layout-check
  r@ cc-sd-total-size [lit] 8 * r> cc-sd-bit-end ! ;
' cc-bf-member is cc-nmember-fwd

: cc-bf-shift-rdi ( count opcode -- )
  over if,
    [lit] 72 cc-emit-byte [lit] 193 cc-emit-byte cc-emit-byte cc-emit-byte
  else, 2drop then, ;
: cc-bf-truncate ( rec -- )
  dup cc-sf-bit-width [lit] 64 swap - [lit] 231 cc-bf-shift-rdi
  dup cc-sf-bit-width [lit] 64 swap -
  swap cc-sf-type ty-unsigned? if, [lit] 239 else, [lit] 255 then, cc-bf-shift-rdi ;
: cc-bf-load ( ty rec -- )
  dup cc-bf? 0= if, cc-field-load-default exit, then,
  swap cc-emit-load-typed-via-rdi
  dup cc-sf-bit-shift [lit] 239 cc-bf-shift-rdi
  cc-bf-truncate ;
' cc-bf-load is cc-field-load-fwd

: cc-bf-mask ( width -- mask )
  dup [lit] 64 = if, drop true else, [lit] 1 swap cc-shl 1- then, ;
: cc-bf-shift-r8 ( count opcode -- )
  over if,
    [lit] 73 cc-emit-byte [lit] 193 cc-emit-byte cc-emit-byte cc-emit-byte
  else, 2drop then, ;
: cc-bf-store ( ty rec -- )
  dup cc-bf? 0= if, cc-field-store-default exit, then,
  nip dup cc-bf-truncate
  [lit] 73 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte \ mov r8,rdi
  dup cc-sf-bit-width [lit] 64 swap - [lit] 224 cc-bf-shift-r8
  dup cc-sf-bit-width [lit] 64 swap - [lit] 232 cc-bf-shift-r8
  dup cc-sf-bit-shift [lit] 224 cc-bf-shift-r8
  dup cc-sf-type ty-size [lit] 8 = if, [lit] 72 cc-emit-byte then,
  dup cc-sf-type ty-size [lit] 1 = if,
    [lit] 15 cc-emit-byte [lit] 182 cc-emit-byte [lit] 1 cc-emit-byte \ movzx eax,byte [rcx]
  else, [lit] 139 cc-emit-byte [lit] 1 cc-emit-byte then, \ mov eax/rax,[rcx]
  [lit] 73 cc-emit-byte [lit] 185 cc-emit-byte \ movabs r9,preserving mask
  dup cc-sf-bit-width cc-bf-mask over cc-sf-bit-shift cc-shl dup nand cc-emit-8le
  [lit] 76 cc-emit-byte [lit] 33 cc-emit-byte [lit] 200 cc-emit-byte \ and rax,r9
  [lit] 76 cc-emit-byte [lit] 9 cc-emit-byte [lit] 192 cc-emit-byte  \ or rax,r8
  cc-sf-type ty-size
  dup [lit] 8 = if, [lit] 72 cc-emit-byte then,
  [lit] 1 = if, [lit] 136 else, [lit] 137 then,
  cc-emit-byte [lit] 1 cc-emit-byte ; \ mov [rcx],al/eax/rax
' cc-bf-store is cc-field-store-fwd

: cc-bf-value-type ( ty rec -- promoted-ty )
  dup cc-bf? if,
    cc-sf-bit-width dup [lit] 32 < if,
      drop drop ty-int [lit] 0 ty-make
    else,
      [lit] 32 = if,
        ty-unsigned? if, ty-uint else, ty-int then, [lit] 0 ty-make
      then,
    then,
  else, drop then, ;
' cc-bf-value-type is cc-field-value-type-fwd
: cc-bf-use ( rec -- )
  cc-bf? if, cc-bf-die then, ;
' cc-bf-use is cc-field-use-fwd

\ Initializer records contain only named members; unnamed and zero-width
\ declarations affect layout but consume no initializer element.
variable cc-bf-init-record
variable cc-bf-init-offset
: cc-bf-static-initializer ( rec -- )
  cc-bf-init-record !
  cc-putback-token cc-parse-static-const-fwd
  if, cc-bf-die then, drop
  dup cc-const-float? cc-bf-init-record @ cc-sf-type cc-const-bool? or if,
    cc-bf-init-record @ cc-sf-type cc-const-change
  else, drop then,
  cc-bf-init-record @ cc-sf-bit-width cc-bf-mask and
  cc-bf-init-record @ cc-sf-bit-shift cc-shl
  nc-slot @ om-offset @ ni-offset @ + cc-bf-init-record @ cc-sf-offset + cc-bf-init-offset !
  cc-obj-data cc-obj-base cc-bf-init-offset @ + @
  cc-bf-init-record @ cc-sf-bit-width cc-bf-mask
  cc-bf-init-record @ cc-sf-bit-shift cc-shl dup nand and or
  cc-obj-data cc-bf-init-offset @ cc-bf-init-record @ cc-sf-type ty-size cc-obj-patch ;

: cc-bf-initializer ( rec -- handled? )
  dup cc-bf? 0= if, drop [lit] 0 exit, then,
  >r
  [char] { cc-tok-punct? dup >r if, cc-next-token-keep then,
  r> r> swap >r >r
  cc-sysv-object-mode @ cc-ni-static @ and if,
    r> cc-bf-static-initializer
  else,
    r@ cc-sf-offset ni-offset @ + cc-ni-address cc-emit-push-rdi
    cc-putback-token cc-parse-assign cc-emit-materialize
    cc-last-expr-type @ r@ cc-sf-type cc-value-init-fwd
    cc-emit-pop-rcx r@ cc-sf-type r> cc-field-store-fwd
  then,
  cc-next-token-keep
  r> if,
    [char] , cc-tok-punct? if, cc-next-token-keep then,
    [char] } cc-tok-punct? 0= if, [lit] 227 cc-die then,
    cc-next-token-keep
  then,
  true ;
' cc-bf-initializer is cc-ni-field-fwd
