\ 123-cc-object-program.fth — scalar translation unit to ELF64 ET_REL.
\ This is the object adapter for121, not a second C parser. Its first
\ boundary supports functions, incoming pointers, and direct external calls.
\ Global storage and taking a function's address currently reject with238.
variable cc-sysv-object-mode
[lit] 0 cc-sysv-object-mode !
create cc-sysv-object-binding cc-sym-cap [lit] 8 * allot
create cc-sysv-object-size cc-sym-cap [lit] 8 * allot
create cc-sysv-object-id cc-sym-cap [lit] 8 * allot

: cc-sysv-object-function-desc
  cc-sysv-object-mode @ if, [lit] 238 cc-die then,
  cc-sysv-function-desc ;
' cc-sysv-object-function-desc is cc-native-function-desc-fwd
: cc-sysv-object-string
  cc-sysv-object-mode @ cc-expr-unevaluated @ 0= and if, [lit] 238 cc-die then,
  cc-parse-native-string-literal ;
' cc-sysv-object-string is cc-native-string-fwd
: cc-sysv-object-function
  cc-sysv-object-mode @ 0= if, cc-sysv-function exit, then,
  nc-static @ >r cc-out-pos @ >r
  cc-sysv-function
  cc-out-pos @ r> - dup if,
    nc-id @ cc-sysv-object-size cell[] !
  else, drop then,
  r> if, true nc-id @ cc-sysv-object-binding cell[] ! then, ;
' cc-sysv-object-function is cc-native-function-fwd

: cc-sysv-object-symbol ( id -- )
  dup >r cc-sym-name-addr cell[] @
  r@ cc-sym-name-len cell[] @
  r@ cc-sysv-object-binding cell[] @ if, cc-obj-local else, cc-obj-global then,
  cc-obj-func cc-obj-default
  r@ cc-sym-val-of dup if,
    cc-base-vaddr - cc-obj-text swap
    r@ cc-sysv-object-size cell[] @
  else,
    drop cc-obj-undef [lit] 0 [lit] 0
    r@ cc-sysv-object-binding cell[] @ if, [lit] 239 cc-die then,
  then,
  cc-obj-symbol r> cc-sysv-object-id cell[] ! ;
: cc-sysv-object-calls ( id -- )
  dup cc-sysv-object-id cell[] @ >r
  cc-sym-call-fixups @
  begin, dup while,
    cc-obj-text over @ cc-obj-plt32 r@ [lit] 0 [lit] 4 - cc-obj-reloc
    [lit] 8 + @
  repeat, drop r> drop ;
: cc-sysv-object-enable
  cc-sysv-enable true cc-sysv-object-mode !
  cc-sysv-object-binding cc-sym-cap [lit] 8 * cc-nzero
  cc-sysv-object-size cc-sym-cap [lit] 8 * cc-nzero
  cc-sysv-object-id cc-sym-cap [lit] 8 * cc-nzero ;
: cc-sysv-object-program
  cc-sysv-translation-unit
  cc-globals-pos @ cc-bss-pos @ or cc-gfixup-count @ or cc-ni-head @ or if,
    [lit] 238 cc-die
  then,
  cc-obj-init cc-out-buf cc-out-pos @ cc-obj-bytes
  [lit] 0 begin, dup cc-sym-count @ < while,
    dup cc-sym-kind-of sk-func = if,
      dup cc-sym-val-of over cc-sym-call-fixups @ or if,
        dup cc-sysv-object-symbol dup cc-sysv-object-calls
      then,
    then, 1+
  repeat, drop ;
