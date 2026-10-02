\ 117-cc-native-program.fth — program and private stack ABI for direct TinyCC.
\ All linked code is generated together. No system libc or host object is used.
variable cc-native-param-count
variable cc-native-frame-patch

: cc-native-params
  [lit] 0 cc-native-param-count !
  begin,
    cc-next-token-keep
    [char] ) cc-tok-punct? if, exit, then,
    pt-ellipsis cc-tok-punct? if, [char] ) cc-expect-punct-c exit, then,
    kw-void cc-tok-kw? if,
      cc-peek-mark cc-lex-mark cc-next-token-keep
      [char] ) cc-tok-punct? if, exit, then,
      cc-peek-mark cc-lex-reset
    then,
    cc-nbase nc-sdesc ! nc-base !
    cc-ndeclarator
    nc-array @ if, [lit] 1 nc-ty +! [lit] 0 nc-array ! then,
    nc-ty @ dup ty-base ty-struct = swap ty-ptr 0= and if, [lit] 212 cc-die then,
    nc-nlen @ if,
      sk-local [lit] 0 cc-native-param-count @ [lit] 3 + -
      cc-ninstall-symbol drop
    then,
    [lit] 1 cc-native-param-count +!
    [char] , cc-tok-punct? 0= if,
      [char] ) cc-tok-punct? 0= if, [lit] 184 cc-die then,
      exit,
    then,
  again, ;

: cc-native-function
  nc-ty @ dup ty-base ty-struct = swap ty-ptr 0= and if, [lit] 212 cc-die then,
  nc-name @ nc-nlen @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-func <> if, drop true then,
  then,
  dup 0< if,
    drop nc-name @ nc-nlen @ sk-func nc-ty @ [lit] 0 cc-sym-add
    nc-desc @ over cc-sym-set-struct-desc
  then,
  nc-id !
  nc-ty @ nc-id @ cc-sym-type cell[] !
  nc-desc @ nc-id @ cc-sym-set-struct-desc
  [char] { cc-tok-punct? 0= if, exit, then,
  nc-id @ cc-sym-val-of if, [lit] 211 cc-die then,
  cc-here-vaddr nc-id @ cc-sym-val cell[] !
  nc-id @ cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
  [lit] 0 nc-id @ cc-sym-call-fixups !
  nc-id @ cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-imm64-to-vaddr
  [lit] 0 nc-id @ cc-sym-addr-fixups !
  nc-name @ nc-nlen @ cc-is-main? if, cc-here-vaddr cc-main-vaddr ! then,
  nc-ty @ cc-native-return-type ! nc-desc @ cc-native-return-desc !
  nc-params cc-lex-reset
  cc-nctx @ >r cc-ncontext
  cc-scope-push
  [lit] 0 cc-fn-local-count !
  [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head ! [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth ! [lit] 0 cc-loop-switch-depth !
  cc-native-params
  [char] { cc-expect-punct-c
  [lit] 0 cc-emit-prologue
  cc-out-pos @ [lit] 4 - cc-native-frame-patch !
  begin,
    cc-next-token-keep [char] } cc-tok-punct? 0= while,
    cc-putback-token cc-parse-stmt
  repeat,
  cc-emit-xor-rax-rax cc-emit-epilogue
  cc-native-finish-gotos
  cc-fn-local-count @ [lit] 8 * [lit] 16 cc-nalign
  cc-native-frame-patch @ cc-out-patch-4le
  cc-scope-pop r> cc-nctx ! ;
' cc-native-function is cc-native-function-fwd

: cc-native-entry
  cc-native-init-entry-fwd
  \ Kernel stack has argc,argv. Push arguments right-to-left for main.
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte [lit] 60 cc-emit-byte [lit] 36 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte [lit] 116 cc-emit-byte [lit] 36 cc-emit-byte [lit] 8 cc-emit-byte
  [lit] 86 cc-emit-byte [lit] 87 cc-emit-byte
  cc-emit-call-rel32-placeholder cc-call-main-patch !
  cc-emit-mov-rdi-rax
  [lit] 184 cc-emit-byte [lit] 60 cc-emit-4le
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte ;

: cc-native-runtime-noop ;
defer cc-native-runtime-fwd
' cc-native-runtime-noop is cc-native-runtime-fwd

: cc-native-program
  cc-native-entry
  cc-native-runtime-fwd
  begin,
    cc-skip-storage-quals cc-next-token-keep
    tok-kind @ tk-eof = 0= while,
    true cc-native-declaration
  repeat,
  cc-native-init-finish-fwd
  cc-check-fns-defined cc-patch-call-main ;
