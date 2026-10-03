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
parameter count, prototype flags, parameter type/descriptor pairs, and
parameter names for definitions.
The same record drives incoming parameters and outgoing calls. Narrow
integers are converted to their declared width before a call and after a
return; the existing typed local loads read the low bytes saved on entry.
Struct pointers retain their tag identity. Function-pointer descriptors
hold a tagged signature, and repeated declarations compare that signature
recursively instead of quietly replacing the first declaration's type.

C90 distinguishes `f()` from `f(void)`: the first leaves the parameter
list unspecified and applies default integer promotions, while the second
is a prototype requiring zero arguments. Identifier-list definitions
retain their parameter names, then bind the following declarations by
name. Parameters without a declaration become `int`. Comparing such a
definition with a prototype compares its promoted parameter types; a
later unspecified declaration does not erase an already visible prototype.
Function bodies install the finalized signature directly, avoiding a
second parameter parser with different type rules.

The executable ABI admits integer and pointer values. Declarations may
record floating or aggregate parameter and return types without generating
code for them. Defining or calling a function across an unsupported value
boundary stops compilation. Scalar variadic *calls* set the vector argument
count to zero, while this layer defaults to rejecting variadic definitions
until the register-save-area and `va_list` hooks supplied by Chapter 42 are
installed. Parameter lists and call lists have a checked
bound; this is a diagnostic boundary, not permission to discard excess
arguments. Pointer-depth overflow is rejected too.

## 2. Keep expression temporaries alive

Expressions already save intermediate values on the machine stack. A
call nested inside another expression may therefore start with any number
of eight-byte temporaries below the frame. Counting pushes globally would
couple every expression operator, switch, and call to the alignment rule.
Instead, we finish evaluating this call's arguments, then construct a
fresh outgoing block below all those live values.

`r11` remembers the staged arguments. We reserve room for stack arguments
and alignment padding, then round `rsp` down to a multiple of sixteen.
Arguments zero through five go into `rdi`, `rsi`, `rdx`, `rcx`, `r8`, and
`r9`. Remaining arguments are copied in order to the bottom of the
outgoing block, so the seventh argument sits just above the return address
in the callee.

The caller's stack pointer and surviving expression values need a longer
lifetime than that outgoing block. A function such as `setjmp` can return
again after intervening calls have overwritten its former stack area.
Saving only `rsp` is insufficient: in `0 == setjmp(state)`, the zero was
also a live expression-stack value. Each call site therefore reserves
persistent slots in its fixed frame for the original `rsp` and the exact
surviving stack span. Compile-time push/pop accounting includes outer
argument staging; lexical switch depth accounts for saved `rbx` values.
This call's own arguments are excluded because they are discarded after
return. Every return restores the surviving span and `rsp`, discards the
staged arguments, and transfers the still-intact `rax` result to `rdi`.

Indirect targets remain staged alongside their arguments until the final
call sequence. We load the target into `r10`, leaving `al` available for
the System V vector-argument count. Caller-saved registers can all be
clobbered by the callee: recovery reads persistent frame slots. No function
name triggers this mechanism; it applies to every call, including nested
calls and callbacks. The price is a larger bounded frame in this
unoptimized compiler.

The accounting relies on the current fixed-frame contract. Variable-length
arrays and dynamic stack allocation are unsupported; implementing them
requires revisiting stack-span lifetime and restoration. The nonlocal
return oracle in `tests/gcc/sysv-setjmp-check.sh` checks both valid operand
orders, repeated returns, loops, callback recursion, switch re-entry, and
all callee-saved registers. It uses host libc only as an interoperability
oracle; a source-built `setjmp` runtime is a separate milestone.

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

Floating type spelling is distinct from floating computation. A header may
legitimately declare an unused `double` function, or a pointer to a floating
object. We keep its real type, size, and alignment: local storage also
aligns long doubles and containing aggregates to sixteen bytes. Scalar
local lvalues materialize only when their value is needed, so taking
`&local_double` does not first perform an unsupported floating load.
Typed load, store, and conversion hooks reject executable floating values;
static floating initializers and unsupported function definitions/calls
also fail before publication. `sizeof` may inspect their types without
creating a call or a value operation. Existing aggregate byte copies remain
supported; aggregate values still cannot cross this scalar call boundary.

`tests/gcc/sysv-declaration-types-check.sh` checks that distinction against a
host layout/address oracle and tests failure-output preservation. These
rules admit real headers without pretending to implement SSE arithmetic,
rewriting their declarations, or treating floating values as integer bits.

## Try it

The first gate uses only the seed interpreter to produce its executables:

```sh
./build.sh
tests/gcc/sysv-check.sh
tests/gcc/sysv-knr-check.sh
tests/gcc/sysv-setjmp-check.sh
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
```

## 4. Carry code and storage into a relocatable object

The object adapter uses the same parser and emitter. It leaves out the
kernel entry stub and private runtime, copies generated function code
into the object writer's text section, and exports each function's name,
binding, start, and size. Calls resolved within that text remain valid
because moving caller and callee together preserves their relative
distance. Calls to declarations without a definition become explicit
`R_X86_64_PLT32` relocations with an addend of minus four.

An object needs identities that last longer than a parser scope. The
symbol table reuses IDs when a block ends, but a static local must survive
for the entire program. The adapter therefore maintains separate stable
object records. Every global reference names a record; only final
serialization translates records to ELF symbol IDs. Two static locals
with the same spelling retain distinct records even when their parser
slots were reused. An `extern` declaration stays undefined until a real
definition appears, while a tentative definition receives zeroed BSS at
the end of the translation unit. Completing a tentative array updates its
record, so earlier references keep naming the final object.

Initialized objects reserve aligned data storage. The adapter reuses
Chapter 34's recursive initializer traversal and replaces only its scalar
and string leaves. Chapter 41's typed constant evaluator returns a value,
type, descriptor, and optional symbolic target. Absolute values write the
destination's low bytes. A symbolic pointer writes an `R_X86_64_64`
relocation with its explicit addend. This handles function pointers,
array elements, and aggregate fields without executing an initializer at
startup. Unsigned intermediate arithmetic follows the same width rules
as ordinary expressions, rather than using an untyped host-sized result.

String literals live in read-only object storage; character-array
initializers copy their decoded bytes into the array's own data or local
storage. Function addresses and global addresses materialized in code
also receive `R_X86_64_64` relocations. The current emitter uses absolute
addresses, so these objects target the bounded static executable path;
they do not claim position-independent code generation.

Object bounds are checked before multiplication, and explicit zero or
negative bounds are rejected separately from an unsized `[]`. Repeated
object declarations must agree on scalar versus array shape. Array
typedefs retain their shape through aliases, declarations, and `sizeof`.
A one-dimensional alias can be an element of an outer array; the existing
object representation holds at most two dimensions. A parameter declared
with a one-dimensional array alias decays to its element pointer, while a
local object keeps the array's full size. This is the ordinary type rule
used by Chapter 42's real `va_list[1]` representation, not a special size
attached to that typedef name. Type-name queries preserve the enclosing
declaration's shape, and casting to an array type is rejected.

The constant type representation does not yet encode a pointer to an
array. Address constants such as `&rows[i][j]` are supported, while a bare
`&array` or unindexed multidimensional-array decay is rejected. Multidimensional array parameters, block-scope function declarations, and
narrow integer relocations are also rejected.
Unsupported forms must stop before publication, rather than preserving an
absolute address that happened to work inside the old executable image.

Run the interoperability and storage gates with:

```sh
tests/gcc/sysv-interop-check.sh
tests/gcc/sysv-storage-check.sh
```

The first gate crosses the host ABI in both directions. The storage gate
checks globals, tentative arrays, strings, aggregate-field and array
element addends, external providers, and static-local identity. It first
uses a host harness, then repeats the storage checks with independently
Forth-compiled objects, a Forth-emitted startup object, and the Forth
linker. Host oracle bytes never enter the production proof.

```forth file=123-cc-object-program.fth
\ 123-cc-object-program.fth — shared scalar C parser to ELF64 ET_REL.
\ Stable object records outlive parser scopes: static locals never inherit
\ an unrelated object when cc-sym IDs are reused. All relocations name these
\ records until081 assigns its own stable symbol IDs at serialization.
variable cc-sysv-object-mode
[lit] 0 cc-sysv-object-mode !
[lit] 4096 constant cc-om-cap
create cc-om-records cc-om-cap [lit] 128 * allot
variable cc-om-count
: cc-om-record 1- [lit] 128 * cc-om-records + ;
: om-name cc-om-record ;
: om-nlen cc-om-record [lit] 8 + ;
: om-bind cc-om-record [lit] 16 + ;
: om-kind cc-om-record [lit] 24 + ;
: om-section cc-om-record [lit] 32 + ;
: om-offset cc-om-record [lit] 40 + ;
: om-size cc-om-record [lit] 48 + ;
: om-align cc-om-record [lit] 56 + ;
: om-type cc-om-record [lit] 64 + ;
: om-desc cc-om-record [lit] 72 + ;
: om-array cc-om-record [lit] 80 + ;
: om-inner cc-om-record [lit] 88 + ;
: om-flags cc-om-record [lit] 96 + ;
: om-output cc-om-record [lit] 104 + ;
: om-symbol cc-om-record [lit] 112 + ;
\ Flags:1 extern-only,2 tentative,4 initialized,8 block static,
\ 16 referenced,32 anonymous. A later definition replaces extern-only.
: cc-om-flag ( flag record -- ) om-flags dup @ rot or swap ! ;
: cc-om-new ( name length binding kind -- record )
  cc-om-count @ 1+ cc-om-cap [lit] 245 cc-check-cap
  [lit] 1 cc-om-count +! cc-om-count @ >r
  r@ cc-om-record [lit] 128 cc-nzero
  r@ om-kind ! r@ om-bind ! r@ om-nlen ! r@ om-name !
  [lit] 1 r@ om-align ! r> ;
variable cc-om-find-name
variable cc-om-find-length
: cc-om-find ( name length -- record|0 )
  cc-om-find-length ! cc-om-find-name !
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup om-flags @ [lit] 40 and 0= if,
      dup om-nlen @ cc-om-find-length @ = if,
        dup om-name @ cc-om-find-name @ cc-om-find-length @ bytes-eq if, exit, then,
      then,
    then, 1+
  repeat, drop [lit] 0 ;
: cc-om-from-symbol ( symbol -- record )
  dup cc-sym-kind-of sk-global = if, cc-sym-val-of exit, then,
  dup cc-sym-name-addr cell[] @ swap cc-sym-name-len cell[] @ cc-om-find
  dup 0= if, [lit] 238 cc-die then, ;

variable cc-om-relocations
: cc-om-reloc ( section offset kind record addend -- )
  [lit] 48 cc-alloc >r
  r@ [lit] 40 + ! dup [lit] 16 swap cc-om-flag
  r@ [lit] 32 + ! r@ [lit] 24 + ! r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-om-relocations @ r@ ! r> cc-om-relocations ! ;
: cc-om-reference ( record -- )
  >r cc-obj-text cc-out-pos @ [lit] 2 + cc-obj-r64 r> [lit] 0 cc-om-reloc
  [lit] 0 cc-emit-movabs-rdi-imm64 ;
: cc-sysv-object-function-desc
  cc-sysv-object-mode @ cc-expr-unevaluated @ 0= and if,
    dup cc-om-from-symbol >r
    cc-obj-text cc-out-pos @ [lit] 2 + cc-obj-r64 r> [lit] 0 cc-om-reloc
  then, cc-sysv-function-desc ;
' cc-sysv-object-function-desc is cc-native-function-desc-fwd

create cc-om-string-name s, .Lstring
: cc-om-string-piece ( address length -- )
  begin, dup while,
    over c@ backslash = over [lit] 1 > and if,
      over 1+ cc-decode-escape swap cc-obj-byte 1+
      >r swap r@ + swap r> -
    else,
      over c@ cc-obj-byte swap 1+ swap 1-
    then,
  repeat, 2drop ;
: cc-om-string ( -- record )
  cc-obj-current @ >r cc-obj-rodata cc-obj-use
  cc-om-string-name [lit] 8 cc-obj-local cc-obj-object cc-om-new
  [lit] 32 over om-flags ! cc-obj-rodata over om-section !
  cc-obj-here over om-offset !
  begin, tok-kind @ tk-str = while,
    tok-str-addr @ tok-str-len @ cc-om-string-piece cc-next-token-keep
  repeat,
  [lit] 0 cc-obj-byte
  cc-obj-here over om-offset @ - over om-size !
  r> cc-obj-use ;
: cc-sysv-object-string
  cc-sysv-object-mode @ cc-expr-unevaluated @ 0= and if,
    cc-om-string dup om-size @ cc-last-expr-array-len !
    cc-putback-token cc-om-reference
  else, cc-parse-native-string-literal then, ;
' cc-sysv-object-string is cc-native-string-fwd

: cc-sysv-object-function
  cc-sysv-object-mode @ 0= if, cc-sysv-function exit, then,
  nc-top @ 0= if, [lit] 238 cc-die then,
  nc-name @ nc-nlen @ cc-om-find
  dup 0= if,
    drop nc-name @ nc-nlen @ cc-obj-global cc-obj-func cc-om-new
  else,
    dup om-kind @ cc-obj-func <> if, [lit] 237 cc-die then,
  then,
  nc-static @ if, cc-obj-local over om-bind ! then,
  >r cc-out-pos @ >r cc-sysv-function
  nc-id @ r> r> rot over om-symbol !
  >r cc-out-pos @ over - dup if,
    r@ om-size ! r@ om-offset ! cc-obj-text r@ om-section !
  else, 2drop then, r> drop ;
' cc-sysv-object-function is cc-native-function-fwd

: cc-om-compatible-object ( record -- )
  dup om-kind @ cc-obj-object <> if, [lit] 237 cc-die then,
  dup om-type @ over om-desc @ nc-ty @ nc-desc @
  cc-sysv-compatible-types 0= if, [lit] 237 cc-die then,
  dup om-array @ 0= nc-array @ 0= <> if, [lit] 237 cc-die then,
  dup om-array @ [lit] 0 > nc-array @ [lit] 0 > and if,
    dup om-array @ nc-array @ <> if, [lit] 237 cc-die then,
  then,
  dup om-inner @ nc-inner @ <> if, [lit] 237 cc-die then, drop ;
: cc-om-size-from-declaration ( record -- )
  nc-ty @ over om-type ! nc-desc @ over om-desc !
  nc-array @ [lit] 0 < over om-array @ [lit] 0 > and if,
    dup om-array @ nc-array !
  then,
  nc-array @ over om-array ! nc-inner @ over om-inner !
  cc-sysv-object-size over om-size !
  nc-ty @ nc-desc @ cc-nalignment swap om-align ! ;
: cc-om-install-object ( record -- )
  dup nc-slot !
  nc-top @ if, nc-name @ nc-nlen @ cc-sym-find else, true then,
  dup 0< if,
    drop sk-global over cc-ninstall-symbol
  else,
    dup cc-sym-kind-of sk-global <> if, [lit] 237 cc-die then,
    nc-ty @ over cc-sym-type cell[] !
    nc-desc @ over cc-sym-set-struct-desc
    nc-array @ over cc-sym-set-array-len nc-inner @ over cc-sym-set-array-inner
    over over cc-sym-val cell[] !
  then,
  dup nc-id ! cc-sysv-object-size swap cc-sym-set-object-size drop ;
: cc-om-initializer
  true cc-ni-static ! cc-next-token-keep
  nc-ty @ nc-desc @ nc-array @ nc-inner @ [lit] 0 [lit] 0 cc-ni-value ;
: cc-sysv-object-declaration
  cc-sysv-object-mode @ 0= if, cc-nobject exit, then,
  nc-top @ 0= nc-extern @ 0= and nc-array @ [lit] 0 < and
  [char] = cc-tok-punct? 0= and if, [lit] 238 cc-die then,
  nc-top @ nc-static @ or nc-extern @ or 0= if, cc-nobject exit, then,
  [char] = cc-tok-punct? if, cc-native-init-prepare-fwd then,
  nc-top @ 0= nc-static @ and if, [lit] 0
  else, nc-name @ nc-nlen @ cc-om-find then,
  dup if, dup cc-om-compatible-object else,
    drop nc-name @ nc-nlen @ cc-obj-global cc-obj-object cc-om-new
    nc-top @ 0= nc-static @ and if, [lit] 8 over cc-om-flag then,
  then,
  nc-static @ if, cc-obj-local over om-bind ! then,
  dup cc-om-size-from-declaration dup cc-om-install-object
  [char] = cc-tok-punct? if,
    dup om-flags @ [lit] 4 and if, [lit] 237 cc-die then,
    cc-obj-current @ >r cc-obj-data cc-obj-use
    dup om-align @ cc-obj-align dup om-size @ cc-obj-reserve over om-offset !
    cc-obj-data over om-section ! [lit] 4 over cc-om-flag
    r> cc-obj-use drop cc-om-initializer
  else,
    nc-extern @ if, [lit] 1 else, [lit] 2 then, swap cc-om-flag
  then, ;
' cc-sysv-object-declaration is cc-nobject-fwd

\ Reuse118's recursive aggregate/array traversal; only static leaves differ.
: cc-om-scalar-initializer
  cc-sysv-object-mode @ cc-ni-static @ and 0= if, cc-ni-scalar exit, then,
  cc-ni-aggregate? if, [lit] 219 cc-die then,
  ni-type @ cc-sysv-check-scalar
  cc-putback-token cc-parse-static-const-fwd
  dup if,
    ni-type @ ty-size [lit] 8 <> if, [lit] 238 cc-die then,
    >r 2drop
    cc-obj-data nc-slot @ om-offset @ ni-offset @ + cc-obj-r64 r> [lit] 4 cc-npick cc-om-reloc
    drop
  else,
    drop 2drop cc-obj-data nc-slot @ om-offset @ ni-offset @ +
    ni-type @ ty-size cc-obj-patch
  then,
  cc-next-token-keep ;
' cc-om-scalar-initializer is cc-ni-scalar-fwd
: cc-om-string-initializer
  cc-sysv-object-mode @ 0= if, cc-ni-string exit, then,
  cc-om-string
  dup om-size @ 1- ni-array @ > if, [lit] 223 cc-die then,
  dup om-size @ ni-array @ cc-nmax drop
  dup om-size @ ni-array @ > if, ni-array @ else, dup om-size @ then,
  cc-ni-static @ if,
    [lit] 0 begin, 2dup > while,
      [lit] 2 cc-npick om-offset @ over + cc-obj-rodata cc-obj-base + c@
      cc-obj-data nc-slot @ om-offset @ ni-offset @ + [lit] 3 cc-npick +
      [lit] 1 cc-obj-patch 1+
    repeat, 2drop drop
  else,
    swap cc-om-reference cc-ni-mov-rsi-rdi
    ni-offset @ cc-ni-address cc-ni-copy-bytes
  then, ;
' cc-om-string-initializer is cc-ni-string-fwd

\ Symbolic constant leaves feed125's typed expression grammar. Record IDs
\ are never addresses; arithmetic only changes an explicit RELA addend.
: cc-om-const-ident
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, cc-const-unsupported then,
  dup cc-sym-kind-of sk-func = if,
    dup cc-sysv-symbol-signature >r cc-om-from-symbol >r
    [lit] 0 ty-func [lit] 1 ty-make r> r> swap exit,
  then,
  dup cc-sym-kind-of sk-global <> if, cc-const-unsupported then,
  dup cc-sym-array-len-of 0= over cc-sym-array-inner-of 0= 0= or if,
    cc-const-unsupported
  then,
  dup cc-om-from-symbol >r dup cc-sym-type-of 1+
  swap cc-expr-symbol-desc [lit] 0 rot rot r> ;
: cc-om-const-string
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  cc-cx-skip @ if,
    begin, cc-next-token-keep tok-kind @ tk-str <> until,
    [lit] 0
  else, cc-om-string then,
  >r cc-putback-token [lit] 0 ty-char [lit] 1 ty-make [lit] 0 r> ;
variable cc-om-address-frame
: oa-value cc-om-address-frame @ ;
: oa-type cc-om-address-frame @ [lit] 8 + ;
: oa-desc cc-om-address-frame @ [lit] 16 + ;
: oa-record cc-om-address-frame @ [lit] 24 + ;
: oa-array cc-om-address-frame @ [lit] 32 + ;
: oa-inner cc-om-address-frame @ [lit] 40 + ;
: cc-om-const-address
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  cc-om-address-frame @ >r
  [lit] 48 cc-alloc dup cc-om-address-frame ! [lit] 48 cc-nzero
  cc-next-token-keep tok-kind @ tk-ident <> if, cc-const-unsupported then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, cc-const-unsupported then,
  dup cc-sym-kind-of sk-func = if,
    dup cc-sysv-symbol-signature oa-desc ! cc-om-from-symbol oa-record !
    ty-func [lit] 0 ty-make oa-type !
  else,
    dup cc-sym-kind-of sk-global <> if, cc-const-unsupported then,
    dup cc-om-from-symbol oa-record ! dup cc-sym-type-of oa-type !
    dup cc-expr-symbol-desc oa-desc !
    dup cc-sym-array-len-of oa-array ! cc-sym-array-inner-of oa-inner !
  then,
  begin,
    cc-next-token-keep
    [char] [ cc-tok-punct? if,
      oa-array @ 0= if, cc-const-unsupported then,
      cc-parse-const
      dup 0< over oa-array @ > or if, cc-const-unsupported then,
      oa-type @ oa-desc @ cc-nsize
      oa-inner @ if, oa-inner @ * then, * oa-value +!
      [char] ] cc-expect-punct-c
      oa-inner @ oa-array ! [lit] 0 oa-inner !
    else,
      [char] . cc-tok-punct? if,
        oa-array @ oa-type @ ty-ptr or if, cc-const-unsupported then,
        oa-type @ ty-base ty-struct <> if, cc-const-unsupported then,
        cc-expect-ident
        tok-str-addr @ tok-str-len @ oa-desc @ cc-find-field oa-value +!
        cc-ff-result-type @ oa-type ! cc-ff-result-desc @ oa-desc !
        cc-ff-result-array @ oa-array !
      else,
        cc-putback-token
        oa-array @ if, cc-const-unsupported then,
        oa-value @ oa-type @ 1+ oa-desc @ oa-record @
        r> cc-om-address-frame ! exit,
      then,
    then,
  again, ;
' cc-om-const-ident is cc-const-ident-fwd
' cc-om-const-address is cc-const-address-fwd
' cc-om-const-string is cc-const-string-fwd

: cc-om-finalize-storage ( record -- )
  dup om-kind @ cc-obj-object = over om-section @ 0= and if,
    dup om-flags @ [lit] 2 and if,
      cc-obj-bss cc-obj-use dup om-align @ cc-obj-align
      dup om-size @ cc-obj-reserve over om-offset ! cc-obj-bss over om-section !
    then,
  then, drop ;
: cc-om-export ( record -- )
  dup >r om-name @ r@ om-nlen @ r@ om-bind @ r@ om-kind @ cc-obj-default
  r@ om-section @ r@ om-offset @
  r@ om-section @ if, r@ om-size @ else, [lit] 0 then,
  cc-obj-symbol r> om-output ! ;
: cc-om-export-needed? ( record -- flag )
  dup om-section @ swap om-flags @ [lit] 16 and or ;
: cc-om-function-calls ( record -- )
  dup om-kind @ cc-obj-func <> if, drop exit, then,
  dup om-symbol @ cc-sym-call-fixups @
  begin, dup while,
    cc-obj-text over @ cc-obj-plt32 [lit] 4 cc-npick [lit] 0 [lit] 4 - cc-om-reloc
    [lit] 8 + @
  repeat, 2drop ;
: cc-sysv-object-enable
  cc-sysv-enable true cc-sysv-object-mode !
  [lit] 0 cc-om-count ! [lit] 0 cc-om-relocations ! ;
: cc-sysv-object-program
  cc-obj-init cc-sysv-translation-unit
  cc-ni-head @ if, [lit] 238 cc-die then,
  cc-obj-text cc-obj-use cc-out-buf cc-out-pos @ cc-obj-bytes
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup cc-om-finalize-storage dup cc-om-function-calls 1+
  repeat, drop
  [lit] 0 begin, dup cc-gfixup-count @ < while,
    cc-obj-text over cc-gfixup-out-pos cell[] @ cc-obj-r64
    [lit] 3 cc-npick cc-gfixup-slot cell[] @ [lit] 0 cc-om-reloc 1+
  repeat, drop
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup cc-om-export-needed? if, dup cc-om-export then, 1+
  repeat, drop
  cc-om-relocations @ begin, dup while,
    dup [lit] 8 + @ over [lit] 16 + @ [lit] 2 cc-npick [lit] 24 + @
    [lit] 3 cc-npick [lit] 32 + @ om-output @ [lit] 4 cc-npick [lit] 40 + @
    cc-obj-reloc @
  repeat, drop ;
```

## 5. Compile an unchanged GCC source unit

GCC 4.0.4's `libiberty/ffs.c` is a useful first source boundary: it has no
headers, uses an identifier-list definition and a `register` parameter,
and returns the position of the first set bit. We compile the original
file from the pinned archive without changing its bytes. This is one
source unit from GCC, not evidence that the complete GCC compiler builds.

```sh
tests/gcc/sysv-gcc-ffs-check.sh
```

The gate requires the original source at its prepared path, or accepts
its path as an argument. It verifies the file's exact hash before parsing
it. Its first executable consists of the Forth-compiled GCC function, a
Forth-compiled comparison harness, the Forth-emitted startup object, and
the Forth linker. A second executable links the same Forth object into a
host-compiled harness as a separate interoperability oracle. Each runs
100,032 comparisons, including zero, signed inputs, and every single-bit
position. The upstream revision and archive hash remain in `gcc64/SOURCES`.

A second unchanged source unit exercises declarations and initialized data:

```sh
tests/gcc/sysv-gcc-hex-check.sh
```

This compiles GCC's original `libiberty/hex.c` together with its original
`libiberty.h`, `safe-ctype.h`, and `ansidecl.h`. Their exact hashes are checked,
and the runtime supplies its real standard headers. The resulting object
contains the complete 256-entry hexadecimal lookup table and `hex_init`.
A Forth-built/Forth-linked executable checks every entry and the original
header macros, including single evaluation of a side-effectful argument.
A separately host-built harness repeats the checks against the Forth
object. Unused floating declarations in the original header remain typed
metadata; they neither require fake ABI code nor become unresolved calls.

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
