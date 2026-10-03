# Chapter 36: Scalar calls across the System V boundary

## Goal

Compile integer and pointer functions whose callers and callees agree with
AMD64 System V. Chapter 34 deliberately used a private stack convention.
That remains the native TinyCC route; this chapter adds an explicit target
selection, `cc-sysv-enable`, for separately compiled scalar code.

This is new reconstruction work. Its tests establish the behavior of the
source shown here; they do not recover or validate an earlier unpublished
GCC bootstrap implementation. Completing this calling convention does not
by itself mean that this compiler can build GCC.

## Concepts carried in

You need the LP64 type and declaration machinery from Chapter 34, the
expression stack and machine encoders from Chapters 25–28, and the function
scopes and forward fixups from Chapter 31. Chapter 35 supplies the
relocatable object writer used at the separate-compilation boundary.

## 1. One signature, two places to use it

A function signature records a tag, return type and descriptor, fixed
parameter count, variadic flag, and parameter type/descriptor pairs.
The same record drives incoming parameters and outgoing calls. Narrow
integers are converted to their declared width before a call and after a
return; the existing typed local loads read the low bytes saved on entry.
Struct pointers retain their tag identity. Function-pointer descriptors
hold a tagged signature, and repeated declarations compare that signature
recursively instead of quietly replacing the first declaration's type.

The present boundary admits integer and pointer values. Passing or
returning an aggregate, or using a floating parameter, stops compilation.
Scalar variadic *calls* set the vector argument count to zero, while
variadic definitions are rejected until the register-save-area and
`va_list` machinery exists. Parameter lists and call lists have a checked
bound; this is a diagnostic boundary, not permission to discard excess
arguments. Pointer-depth overflow is rejected too.

## 2. Keep expression temporaries alive

Expressions already save intermediate values on the machine stack. A
call nested inside another expression may therefore start with any number
of eight-byte temporaries below the frame. Counting pushes globally would
couple every expression operator, switch, and call to the alignment rule.
Instead, we finish evaluating this call's arguments, then construct a
fresh outgoing block below all those live values.

`r11` remembers the staged arguments. We reserve room for stack arguments,
a saved copy of that pointer, and alignment padding, then round `rsp` down
to a multiple of sixteen. Arguments zero through five go into `rdi`,
`rsi`, `rdx`, `rcx`, `r8`, and `r9`. Remaining arguments are copied in order
to the bottom of the outgoing block, so the seventh argument sits just
above the return address in the callee. The saved stack pointer follows
the outgoing arguments. After the call, it restores the original live
stack exactly; discarding this call's staged values then exposes the
surrounding expression's temporaries again.

Indirect targets remain staged alongside their arguments until the final
call sequence. We load the target into `r10`, leaving `al` available for
the System V vector-argument count. Caller-saved registers can all be
clobbered by the callee: recovery uses the saved memory slot, not a
register presumed to survive a call.

## 3. Save the registers the caller owns

The existing emitter saves and restores `rbp`. This mode reserves the
first local slot for `rbx`, the only other callee-saved register used by
the expression backend, and restores it on every epilogue. The backend
does not use `r12` through `r15`. Register arguments are copied into local
slots before parsing the body; later stack arguments are copied from the
caller's incoming stack area. All parameters can then use the same typed
local load and store machinery as ordinary variables.

The opt-in hooks have native defaults. Merely loading this module does
not select System V or change the private native argument convention.
The tests must keep checking that property as both routes develop.

## Try it

The first gate uses only the seed interpreter to produce its executables:

```sh
./build.sh
tests/gcc/sysv-check.sh
```

It checks direct and indirect calls, arguments on both sides of the
six-register boundary, nested argument evaluation, recursion, incoming
`argc`/`argv`, narrow integer results, and explicit rejection of unsupported
value classes and inconsistent prototypes. Host-compiler interoperability
is a separate boundary check added with the object adapter; a host-built
reference must never become a production bootstrap input.

## Canonical source

```forth file=121-cc-sysv.fth
\ 121-cc-sysv.fth — explicit scalar System V AMD64 target.
\ Loading this file changes no target. cc-sysv-enable opts in to LP64 and
\ INTEGER-class calls; floating and aggregate values fail closed.
variable cc-target-sysv
[lit] 0 cc-target-sysv !
[lit] 64 constant cc-sysv-arg-cap
[lit] 1398362966 constant cc-sysv-signature-tag
create cc-sysv-signatures cc-sym-cap [lit] 8 * allot

\ Signature: tag, return type, return descriptor, count, variadic flag,
\ then 64 (type, descriptor) pairs. Function-pointer descriptors are tagged.
: cc-sysv-sig-return [lit] 8 + @ ;
: cc-sysv-sig-desc [lit] 16 + @ ;
: cc-sysv-sig-count [lit] 24 + @ ;
: cc-sysv-sig-varargs [lit] 32 + @ ;
: cc-sysv-sig-param [lit] 16 * [lit] 40 + + ;
: cc-sysv-check-signature
  dup 0= if, [lit] 230 cc-die then,
  dup @ cc-sysv-signature-tag <> if, [lit] 230 cc-die then, ;
: cc-sysv-check-scalar ( ty -- )
  dup [lit] 256 / [lit] 255 and if, [lit] 231 cc-die then,
  dup ty-ptr if, drop exit, then,
  ty-base
  dup ty-struct = over ty-float = or over ty-double = or
  over ty-ldouble = or swap ty-func = or if, [lit] 232 cc-die then, ;
: cc-sysv-check-declarator
  cc-target-sysv @ if,
    nc-ty @ [lit] 256 / [lit] 255 and if, [lit] 231 cc-die then,
  then, ;
' cc-sysv-check-declarator is cc-ndeclarator-check-fwd

defer cc-sysv-signature-fwd
: cc-sysv-fnptr
  cc-target-sysv @ 0= if, cc-nfnptr-default exit, then,
  nc-ty @ nc-desc @ cc-sysv-signature-fwd nc-desc !
  ty-func [lit] 1 ty-make nc-ty ! ;
' cc-sysv-fnptr is cc-nfnptr-fwd

: cc-sysv-signature ( return-type return-desc -- signature )
  over cc-sysv-check-scalar
  [lit] 1064 cc-alloc dup >r [lit] 1064 cc-nzero
  r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-sysv-signature-tag r@ !
  cc-nctx @ >r cc-ncontext
  begin,
    cc-next-token-keep
    [char] ) cc-tok-punct? if, r> cc-nctx ! r> exit, then,
    pt-ellipsis cc-tok-punct? if,
      r> cc-nctx ! r>
      dup cc-sysv-sig-count 0= if, [lit] 233 cc-die then,
      true over [lit] 32 + ! [char] ) cc-expect-punct-c exit,
    then,
    kw-void cc-tok-kw? if,
      cc-peek-mark cc-lex-mark cc-next-token-keep
      [char] ) cc-tok-punct? if, r> cc-nctx ! r> exit, then,
      cc-peek-mark cc-lex-reset
    then,
    cc-nbase nc-sdesc ! nc-base ! cc-ndeclarator
    nc-array @ if, [lit] 1 nc-ty +! [lit] 0 nc-array ! then,
    nc-ty @ cc-sysv-check-scalar
    nc-ty @ ty-size 0= if, [lit] 233 cc-die then,
    r> r> dup >r swap >r
    dup cc-sysv-sig-count dup cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
    over swap cc-sysv-sig-param
    nc-ty @ over ! nc-desc @ swap [lit] 8 + !
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
: cc-sysv-compatible-signatures ( sig1 sig2 -- flag )
  2dup cc-sysv-sig-count swap cc-sysv-sig-count <> if, 2drop [lit] 0 exit, then,
  2dup cc-sysv-sig-varargs swap cc-sysv-sig-varargs <> if, 2drop [lit] 0 exit, then,
  2dup >r cc-sysv-signature-result r> cc-sysv-signature-result
  cc-sysv-compatible-types 0= if, 2drop [lit] 0 exit, then,
  [lit] 0 begin, over cc-sysv-sig-count over > while,
    [lit] 2 cc-npick over cc-sysv-parameter-type
    [lit] 3 cc-npick [lit] 3 cc-npick cc-sysv-parameter-type
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
      cc-last-expr-type @ cc-sysv-check-scalar
      over cc-sysv-sig-count over > if,
        2dup cc-sysv-sig-param @ cc-emit-convert-rdi
      else,
        over cc-sysv-sig-varargs 0= if, [lit] 235 cc-die then,
        cc-last-expr-type @ cc-unary-type cc-emit-convert-rdi
      then,
      cc-emit-push-rdi 1+
      cc-next-token-keep [char] , cc-tok-punct? 0=
    until,
    [char] ) cc-tok-punct? 0= if, [lit] 121 cc-die then,
  then,
  over cc-sysv-sig-count over > if, [lit] 235 cc-die then,
  nip dup cc-native-reverse-args ;

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
: cc-sysv-prepare-call ( count -- )
  \ r11 points to staged arg0. Align a fresh block below all live temporaries.
  [lit] 73 cc-emit-byte [lit] 137 cc-emit-byte [lit] 227 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 129 cc-emit-byte [lit] 236 cc-emit-byte
  dup cc-sysv-stack-count 1+ [lit] 8 * [lit] 15 + cc-emit-4le
  [lit] 72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 228 cc-emit-byte [lit] 240 cc-emit-byte
  \ The saved original RSP follows, and never overlaps, the stack arguments.
  [lit] 76 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 156 cc-emit-byte [lit] 36 cc-emit-byte
  dup cc-sysv-stack-count [lit] 8 * cc-emit-4le
  [lit] 6 begin, 2dup > while,
    [lit] 73 cc-emit-byte [lit] 139 cc-emit-byte
    dup [lit] 131 cc-sysv-load-staged
    dup [lit] 6 - [lit] 8 * cc-sysv-store-outgoing
    1+
  repeat, drop
  [lit] 0 begin, 2dup > over [lit] 6 < and while,
    dup cc-sysv-load-gp 1+
  repeat, 2drop ;
: cc-sysv-finish-call ( count indirect? -- )
  >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 164 cc-emit-byte [lit] 36 cc-emit-byte
  dup cc-sysv-stack-count [lit] 8 * cc-emit-4le
  r> if, 1+ then, cc-native-drop-args
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
    r@ cc-sysv-parse-args dup cc-sysv-prepare-call
    dup cc-sysv-call-staged-target true cc-sysv-finish-call
  else,
    r@ cc-sysv-parse-args dup cc-sysv-prepare-call >r
    cc-sysv-zero-vector-count
    dup cc-sym-val-of 0= if,
      cc-emit-call-rel32-placeholder
      cc-expr-unevaluated @ if, 2drop
      else, swap cc-sym-call-fixups cc-add-fixup-to-list then,
    else, cc-sym-val-of cc-emit-call-vaddr then,
    r> [lit] 0 cc-sysv-finish-call
  then,
  r> cc-sysv-sig-return cc-emit-convert-rdi ;
' cc-sysv-call is cc-native-call-fwd
: cc-sysv-indirect-call
  cc-target-sysv @ 0= if, cc-parse-indirect-call exit, then,
  cc-check-static-init
  cc-last-expr-type @ ty-base ty-func <> if, [lit] 230 cc-die then,
  cc-last-struct-desc @ cc-sysv-check-signature >r
  cc-emit-materialize cc-emit-push-rdi
  r@ cc-sysv-parse-args dup cc-sysv-prepare-call
  dup cc-sysv-call-staged-target true cc-sysv-finish-call
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
: cc-sysv-params
  [lit] 0 cc-native-param-count !
  begin,
    cc-next-token-keep
    [char] ) cc-tok-punct? if, exit, then,
    pt-ellipsis cc-tok-punct? if, [lit] 236 cc-die then,
    kw-void cc-tok-kw? if,
      cc-peek-mark cc-lex-mark cc-next-token-keep
      [char] ) cc-tok-punct? if, exit, then,
      cc-peek-mark cc-lex-reset
    then,
    cc-nbase nc-sdesc ! nc-base ! cc-ndeclarator
    nc-array @ if, [lit] 1 nc-ty +! [lit] 0 nc-array ! then,
    nc-ty @ cc-sysv-check-scalar
    nc-nlen @ if,
      sk-local cc-native-param-count @ 1+ cc-ninstall-symbol drop
    then,
    [lit] 1 cc-fn-add-slots [lit] 1 cc-native-param-count +!
    [char] , cc-tok-punct? 0= if,
      [char] ) cc-tok-punct? 0= if, [lit] 184 cc-die then, exit,
    then,
  again, ;

variable cc-sysv-frame-patch
variable cc-sysv-function-signature
: cc-sysv-function
  cc-target-sysv @ 0= if, cc-native-function exit, then,
  nc-ty @ cc-sysv-check-scalar
  cc-lex-state-size cc-alloc dup cc-lex-mark >r
  nc-params cc-lex-reset
  nc-ty @ nc-desc @ cc-sysv-signature cc-sysv-function-signature !
  r> cc-lex-reset
  nc-name @ nc-nlen @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-func <> if, [lit] 237 cc-die then,
    dup cc-sysv-symbol-signature cc-sysv-function-signature @
    cc-sysv-compatible-signatures 0= if, [lit] 237 cc-die then,
  then,
  dup 0< if,
    drop nc-name @ nc-nlen @ sk-func nc-ty @ [lit] 0 cc-sym-add
    nc-desc @ over cc-sym-set-struct-desc
  then,
  nc-id !
  cc-sysv-function-signature @ nc-id @ cc-sysv-signatures cell[] !
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
  cc-nctx @ >r cc-ncontext cc-scope-push
  [lit] 1 cc-fn-local-count ! [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head ! [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth ! [lit] 0 cc-loop-switch-depth !
  cc-sysv-params [char] { cc-expect-punct-c
  [lit] 0 cc-emit-prologue
  cc-out-pos @ [lit] 4 - cc-sysv-frame-patch ! cc-sysv-save-callee
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
```

## 4. Carry calls into a relocatable object

The object adapter uses the same parser and emitter. It leaves out the
kernel entry stub and private runtime, copies the generated function code
into the object writer's text section, and exports each function's name,
binding, start, and size. Calls resolved within that text remain valid
because moving caller and callee together preserves their relative
distance. Calls to declarations without a definition become explicit
`R_X86_64_PLT32` relocations with an addend of minus four.

This first adapter rejects global storage, string storage, and any attempt
to materialize a function address. The last rejection occurs at the shared
function-reference hook, so it covers already defined functions as well
as unresolved ones. Silently copying an absolute address from the
executable emitter into a relocatable object would produce plausible
bytes with the wrong meaning. Storage and address relocations will extend
this adapter when their complete semantics are implemented.

Run the separate interoperability oracle with:

```sh
tests/gcc/sysv-interop-check.sh
```

The Forth-generated object calls host functions and the host calls Forth
functions. The test covers signed and unsigned narrow values, stack
arguments, pointers, callbacks, nested calls, and scalar variadic calls.
Only the reference executable uses the host compiler and linker; its
bytes never enter the bootstrap chain.

```forth file=123-cc-object-program.fth
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
```

## Exercises

- **★** Draw the outgoing stack block for a call with eight integer arguments
- **★★** Add a boundary case where a nested call runs while a switch scrutinee is saved
- **★★★** Design the signature extension needed for System V aggregate classification

## Takeaways

- One tagged signature controls both sides of a scalar call
- A separate aligned outgoing block preserves arbitrary expression temporaries
- Explicit target selection keeps the existing private native ABI available

The object adapter connects these calls to the ELF symbols and relocations
introduced in Chapter 35.
