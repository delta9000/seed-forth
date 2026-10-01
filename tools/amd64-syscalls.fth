\ Runner-only compiler extension, loaded between 116 and 120 by the launcher.
\ Existing compiler sources/symbol slots and all other routes are untouched.
\ The runner declares syscall3 explicitly; resolve only that declared symbol.
create cc-runner-syscall-name s, syscall3

\ -- syscall3(number, a, b, c): raw Linux result; fourth argument is zero.
\ Used by the seed-built recipe runner. It is emitted only when referenced.
\ C: rdi=number rsi=a rdx=b rcx=c; Linux: rax=number rdi=a rsi=b rdx=c.
: cc-emit-syscall3-shim
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 247 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 214 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 202 cc-emit-byte
  [lit] 69 cc-emit-byte [lit] 49 cc-emit-byte [lit] 210 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte
  [lit] 195 cc-emit-byte ;

: cc-runner-finish-syscall
  cc-runner-syscall-name [lit] 8 cc-sym-find
  dup 0< if, drop [lit] 206 cc-die then,
  dup cc-sym-kind-of sk-func <> if, [lit] 206 cc-die then,
  dup cc-sym-call-fixups @ over cc-sym-addr-fixups @ or if,
    cc-here-vaddr over cc-sym-val cell[] !
    dup cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
    dup cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-imm64-to-vaddr
    [lit] 0 over cc-sym-call-fixups !
    [lit] 0 over cc-sym-addr-fixups !
    cc-emit-syscall3-shim
  then, drop ;

\ 120-cc-main.fth binds this runner-specific driver after loading this file.
: cc-parse-program
  cc-emit-entry-stub
  cc-emit-shims
  cc-register-late-shims
  cc-emit-external-protos
  cc-emit-libc-typedefs
  cc-parse-function-list
  cc-emit-late-shims
  cc-runner-finish-syscall
  cc-check-fns-defined
  cc-patch-call-main ;
