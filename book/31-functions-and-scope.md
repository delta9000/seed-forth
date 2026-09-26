# Chapter 31 — Functions: Parameters, Calls, Globals, Entry Stub

```text
Missing capability: the compiler cannot assemble functions, globals, calls, scopes, and program entry.
New pattern: parse file-scope forms while resolving forward calls, scoped locals, globals, and the entry stub.
Artifact after this chapter: a complete C-subset translation-unit compiler.
Proof link: Stage-A can compile whole M2-Planet inputs into a runnable /tmp/cc-out.
```

Every earlier Part III chapter compiles a piece of a C function: an
expression, a declaration, a statement.  Nothing yet reads a whole
file.  This chapter covers the rest of `110-cc-decl.fth`
(lines 1498–2827), which turns those pieces into a translation-unit
compiler.  It has four main words.  `cc-parse-call` compiles direct,
forward, and indirect calls.  `cc-parse-function` wraps a body in a
prologue, epilogue, and scope.  `cc-parse-function-list` loops over
file-scope declarations until end of file.  The 26-byte entry stub
at `0x400078` passes `argc` / `argv` to `main` and exits with its
return value.

It is the longest chapter in Part III, and mostly code.  §1 sets up
per-function state.  §§2–4 are the function machinery: calls,
parameters and their register spill, and function definitions.
§§5–7 handle everything else that can appear at file scope: enums,
typedefs, prototypes, and globals.  §8 is the entry stub and the
top-level driver `cc-parse-program`.  The shell scripts that run
the result, and the byte-identity comparison against GCC-built
M2-Planet, are Ch 32's.

## 1. Setup

A few globals carry per-function state across the parameter and
body parses, and `cc-is-main?` recognises the name `main` so the
entry stub can find it later.  Nothing here generates code.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Function parsing: multiple functions, params, SYS-V calling convention
\ ===========================================================================
\ The current-function bookkeeping uses two globals so the name token's bytes
\ aren't lost when subsequent tokens are read for the parameter list.
variable cc-fn-name-addr
variable cc-fn-name-len
variable cc-fn-param-count                        \ # params in current function
variable cc-fn-prior-sym-id                       \ prior sk-func id for fwd-fixup walk; -1 if none

\ Pre-baked literal "main" for cc-is-main? — laid out as 4 raw bytes (no length
\ prefix here, because cc-is-main? only consumes 4 bytes).
create cc-main-name-bytes
[lit] 109 c, [lit]  97 c, [lit] 105 c, [lit] 110 c,    \ "main"

\ cc-is-main? ( name-addr name-len -- f )  -1 if (addr, len) names "main".
: cc-is-main?                                     ( addr len -- f )
  dup [lit] 4 = if,
    drop                                          ( addr )
    cc-main-name-bytes swap [lit] 4 bytes-eq
  else,
    drop drop [lit] 0
  then, ;

\ cc-block-end? ( -- f )  After cc-next-token-keep, returns -1 if current
\ token is '}'.  Helper used by the function body loop.
: cc-block-end?
  tok-kind @ tk-punct =
  tok-num @ [lit] 125 = and ;

```

## 2. The call codegen

Ch 28's `cc-parse-primary` calls `cc-parse-call` through
`cc-parse-call-vec` once it has seen `IDENT (`.  Three helpers come
first.  `cc-emit-call-vaddr` emits `E8 <rel32>` to an absolute
target.  `cc-emit-pops-for-args` pops `n` pushed argument values into
the System V argument registers, walking `i = n-1 .. 0` so the
last-pushed value lands in the `n`-th register; for each index it
calls `cc-emit-pop-by-arg-index` to pick the register.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Function-call codegen (the body of cc-parse-call, wired to cc-parse-call-vec)
\ ===========================================================================

\ cc-emit-call-vaddr ( target-vaddr -- )  Emit `call <abs-target>` (5 bytes).
\ rel32 = target_vaddr - (callsite_after_E8 + 4) = target - (callsite_vaddr+5)
\ where callsite_vaddr = cc-base-vaddr + cc-out-pos@ at the moment of E8.
: cc-emit-call-vaddr
  [lit] 232 cc-emit-byte                          \ E8 opcode
  \ At this point cc-out-pos@ points at the rel32 slot's first byte.
  \ rel32 = target - (cc-base-vaddr + cc-out-pos@ + 4)
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        ( rel32 )
  cc-emit-4le ;

\ cc-emit-pop-by-arg-index ( arg-index -- )  Emit a pop into the SYS-V arg
\ register corresponding to arg-index (0=rdi, 1=rsi, 2=rdx, 3=rcx, 4=r8, 5=r9).
\ Caller is responsible for not asking past 5.
: cc-emit-pop-by-arg-index
  dup [lit] 0 = if, drop cc-emit-pop-rdi else,
  dup [lit] 1 = if, drop cc-emit-pop-rsi else,
  dup [lit] 2 = if, drop cc-emit-pop-rdx else,
  dup [lit] 3 = if, drop cc-emit-pop-rcx else,
  dup [lit] 4 = if, drop cc-emit-pop-r8  else,
                    drop cc-emit-pop-r9
  then, then, then, then, then, ;

\ cc-emit-pops-for-args ( n -- )  Pop n values off the stack into the first n
\ SYS-V arg registers, in REVERSE order (so the last-pushed value lands in the
\ n-th argument register).  After this, args 1..n live in rdi/rsi/rdx/rcx/r8/r9.
\
\ Walks i = n-1 down to 0, emitting pop-into-reg(i) at each step.  Loop drives
\ a counter on the data stack.
: cc-emit-pops-for-args                           ( n -- )
  [lit] 1 -                                       ( i = n-1 )
  begin,
    dup [lit] 0 >=
  while,
    dup cc-emit-pop-by-arg-index
    [lit] 1 -
  repeat,
  drop ;

```

`cc-parse-call` itself works in four steps:

1. Parse the comma-separated arguments, pushing each value with
   `cc-emit-push-rdi` and counting them.  The count sits under the
   symbol id on the data stack.
2. After `)`, reject more than six arguments (status 37), then pop
   the values into registers.
3. Dispatch on the callee's symbol:
   - `sk-func` with a non-zero `val` → `call <abs-vaddr>` via
     `cc-emit-call-vaddr`;
   - `sk-func` with `val = 0` (a prototype not yet defined) →
     `cc-emit-call-rel32-placeholder`, with the patch offset
     threaded onto the symbol's `cc-sym-extra` fixup list;
   - `sk-local` whose base type is `ty-func` (a function-pointer
     local) → `cc-emit-load-local-into-rax` then `cc-emit-call-rax`.
4. Copy the return value from `rax` into `rdi`, the register this
   compiler threads every expression result through.

Six is the System V register limit; beyond it arguments go on the
stack, which this compiler doesn't implement.  M2-Planet has no
function with more than six parameters.

```forth file=110-cc-decl.fth
\ cc-parse-call ( id -- )  Parse a comma-separated argument list — the leading
\ '(' has ALREADY been consumed by cc-parse-primary (it was the lookahead
\ token that triggered dispatch here).  Evaluate each arg left-to-right
\ (each result pushed onto the stack), then emit the SYS-V argument-register
\ loads, the call, and post-call rdi <- rax move so the caller sees the
\ return value in rdi.
\
\ Stack at entry: ( id ).  The id is the symbol-table id of the callee.
\ Stack at exit:  ( ).
: cc-parse-call
  \ Parse the argument list.  Stack underneath: ( id ).  We thread an
  \ argument count below the id.  Initial state: ( id 0 ).
  [lit] 0                                         ( id arg-count )

  \ Empty arg list?
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 41 = and if,
    \ ')' — empty arg list, leave count = 0.
  else,
    cc-putback-token
    \ Loop: parse one arg, push, increment count; continue while next is ','.
    [lit] 0 0=                                    \ keep-going flag = -1
    begin,
      dup
    while,
      drop                                        ( id arg-count )
      cc-parse-expr-balanced-2                    \ rdi := arg value
      cc-emit-push-rdi
      [lit] 1 +                                   \ count++
      cc-next-token-keep
      tok-kind @ tk-punct = tok-num @ [lit] 44 = and if,
        [lit] 0 0=                                \ continue
      else,
        cc-putback-token
        [lit] 0                                   \ stop
      then,
    repeat,
    drop                                          \ discard final flag
    \ The token AFTER the last arg should be ')'.  Consume it.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 41 = and 0= if,
      [lit] 36 die
    then,
  then,

  ( id arg-count )

  \ The SYS-V register path supports up to 6 args.  Reject excess.
  dup [lit] 6 > if,
    [lit] 37 die
  then,

  \ NOTE on alignment: argument values are pushed while parsing, then popped
  \ into registers before the call.  The pops restore rsp to its pre-argument
  \ value, which our prologue keeps 16-aligned.  Nested calls happen during
  \ expression parsing before these argument pushes are popped, so they have
  \ their own balanced call sequence.

  \ Pop arg-count values off the stack into the arg registers.
  dup cc-emit-pops-for-args                       ( id arg-count )
  drop                                            ( id )

  \ Dispatch on symbol kind.
  \   sk-func, val != 0 -> direct call: E8 <rel32> to absolute vaddr.
  \   sk-func, val == 0 -> forward call: emit placeholder, register fixup
  \                        on this prototype's cc-sym-extra slot.  When the
  \                        function is later defined, cc-parse-function walks
  \                        the list and patches each rel32.
  \   sk-local + ty-func -> indirect call: load fp slot into rax, call rax.
  \                        rdi/rsi/... already hold args; rax is free.
  dup cc-sym-kind-of sk-func = if,
    dup cc-sym-val-of [lit] 0 = if,
      \ Forward call.  Emit E8 + 4-byte placeholder; thread the slot offset
      \ onto the prototype's fixup list (cc-sym-extra at id).
      cc-emit-call-rel32-placeholder              ( id patch-off )
      swap cc-sym-extra sym-slot                  ( patch-off extra-cell-addr )
      cc-add-fixup-to-list
    else,
      cc-sym-val-of                               ( target-vaddr )
      cc-emit-call-vaddr
    then,
  else,
    dup cc-sym-kind-of sk-local =
    over cc-sym-type-of ty-base ty-func = and if,
      cc-sym-val-of                               ( slot )
      cc-emit-load-local-into-rax                 \ rax := fp value
      cc-emit-call-rax
    else,
      drop
      [lit] 38 die
    then,
  then,

  \ Move return value into rdi (so the caller's expression machinery picks it up).
  cc-emit-mov-rdi-rax ;

\ Wire the trampoline so cc-parse-primary (in 100-cc-expr.fth) can dispatch here.
' cc-parse-call cc-parse-call-vec !

```

## 3. Parameter lists and the spill

Each parameter becomes an `sk-local` symbol in slots
`0 .. cc-fn-param-count-1`.  `cc-parse-param-list-loop` reads
`T name` pairs separated by commas.  A keyword type gives a base
type with pointer depth 0 (keeping `char` distinct so `s[i]` on a
`char*` parameter uses byte loads); a typedef name contributes its
encoded base and pointer depth, so a function-pointer typedef stays
a function pointer.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Parameter-list parsing + spill
\ ===========================================================================

\ cc-parse-param-list-loop ( -- )  Parse one or more parameters separated by
\ ','.  T may be int / char / void / long / short / struct TAG / typedef-name,
\ with '*' modifiers.  Consumes the closing ')'.
: cc-parse-param-list-loop
  [lit] 0 0=                                      \ keep-going flag = -1
  begin,
    dup
  while,
    drop
    \ Base type.  Both branches leave ( base ptr-depth-so-far ); the kw path
    \ starts ptr-depth at 0; the typedef path inherits the typedef's encoded
    \ ptr-depth (so FUNCTION = void (*)() stays a function pointer in params).
    cc-next-token-keep
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-struct = if,
        cc-lookup-struct-tag cc-pending-struct-desc !
        ty-struct [lit] 0
      else,
        \ int/char/void/long/short/unsigned/signed — char is distinguished so
        \ `char* s` params get ty-char + ptr-depth, which the array-index path
        \ needs to emit byte stride / byte load for `s[i]`.  Others collapse
        \ to ty-int.
        [lit] 0 cc-pending-struct-desc !
        tok-kw-id @ kw-char = if,
          ty-char
        else,
          ty-int
        then,
        [lit] 0
      then,
    else,
      tok-kind @ tk-ident = if,
        \ Typedef-name (e.g. FILE, FUNCTION).  Look up and unpack its encoded
        \ base+ptr-depth so function-pointer typedefs survive into param type.
        tok-str-addr @ tok-str-len @ cc-sym-find   ( id )
        dup [lit] 0 < if,
          [lit] 38 die
        then,
        dup cc-sym-kind-of sk-typedef <> if,
          [lit] 38 die
        then,
        [lit] 0 cc-pending-struct-desc !
        cc-sym-val-of                              ( ty )
        dup ty-base swap ty-ptr                    ( base ptr-depth )
      else,
        [lit] 38 die
        ty-int [lit] 0                            \ unreachable
      then,
    then,
    ( base ptr-depth )
    cc-count-stars                                ( base ptr-depth extra )
    +                                              ( base total-ptr )
    ty-make                                       ( ty )
    \ Expect IDENT.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 38 die
    then,
    \ Add as a local: name in tok-str-addr/len, kind=sk-local, type=ty,
    \ val=current local count (= slot).  Stack on entry: ( ty ).
    tok-str-addr @ tok-str-len @                  ( ty a u )
    rot                                            ( a u ty )
    sk-local swap                                  ( a u sk-local ty )
    cc-fn-local-count @                            ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-pending-struct-desc @ swap cc-sym-set-extra
    [lit] 1 cc-fn-local-count +!
    [lit] 1 cc-fn-param-count +!
    \ Continue if next is ','.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 44 = and if,
      [lit] 0 0=                                  \ continue
    else,
      cc-putback-token
      [lit] 0                                     \ stop
    then,
  repeat,
  drop                                            \ discard flag
  \ Now consume the closing ')'.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 41 = and 0= if,
    [lit] 39 die
  then, ;

```

`cc-parse-param-list` handles the two special cases before calling
the loop: `()` and `(void)`.  Spotting `(void)` needs two tokens of
lookahead, so it uses `cc-top-lookahead-save` /
`cc-top-lookahead-restore`, which save the lexer position and the
current token.  §6's top-level peeks use the same pair.

```forth file=110-cc-decl.fth
\ Shared lexer/token lookahead save/restore.  Top-level peeking uses this,
\ and parameter parsing uses it for the `(void)` special case.
variable cc-top-save-pos
variable cc-top-save-line
variable cc-top-save-pending
variable cc-top-save-tok-kind
variable cc-top-save-tok-num
variable cc-top-save-tok-addr
variable cc-top-save-tok-len
variable cc-top-save-tok-kw

: cc-top-lookahead-save
  cc-src-pos     @ cc-top-save-pos      !
  cc-src-line    @ cc-top-save-line     !
  cc-tok-pending @ cc-top-save-pending  !
  tok-kind       @ cc-top-save-tok-kind !
  tok-num        @ cc-top-save-tok-num  !
  tok-str-addr   @ cc-top-save-tok-addr !
  tok-str-len    @ cc-top-save-tok-len  !
  tok-kw-id      @ cc-top-save-tok-kw   ! ;

: cc-top-lookahead-restore
  cc-top-save-pos      @ cc-src-pos     !
  cc-top-save-line     @ cc-src-line    !
  cc-top-save-pending  @ cc-tok-pending !
  cc-top-save-tok-kind @ tok-kind       !
  cc-top-save-tok-num  @ tok-num        !
  cc-top-save-tok-addr @ tok-str-addr   !
  cc-top-save-tok-len  @ tok-str-len    !
  cc-top-save-tok-kw   @ tok-kw-id      ! ;

\ cc-parse-param-list ( -- )  Parse a possibly-empty comma-separated list of
\ parameters.  Caller has NOT yet consumed any tokens.  When this returns the
\ closing ')' has been consumed.  Each parameter becomes an sk-local symbol.
: cc-parse-param-list
  [lit] 0 cc-fn-param-count !
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 41 = and if,
    \ ')' — empty list, done.
  else,
    \ Special case: `(void)` = no params.  Peek for kw-void followed by ')'.
    tok-kind @ tk-kw = tok-kw-id @ kw-void = and if,
      cc-top-lookahead-save
      cc-next-token                               \ advance past void; tok-* := next
      tok-kind @ tk-punct = tok-num @ [lit] 41 = and >r
      cc-top-lookahead-restore
      r> if,
        \ It IS '(void)'.  void is already consumed; now consume ')'.
        cc-next-token
      else,
        cc-putback-token
        cc-parse-param-list-loop
      then,
    else,
      cc-putback-token
      cc-parse-param-list-loop
    then,
  then, ;

```

`cc-emit-spill-params` stores the argument registers into their
slots: `[rbp - 8] := rdi`, `[rbp - 16] := rsi`, and so on, one rung
per parameter actually present.  The encoders are Ch 25 §4's
`cc-emit-store-local` family.  After the spill, parameters are
ordinary locals and the rest of the compiler can't tell them apart.

The slots live in the frame that `cc-emit-prologue 256` reserves:
32 eight-byte slots for parameters plus body locals, where an array
takes one slot per element.  Nothing checks the limit.  Exceed it
and the compile succeeds, but the frame silently overlaps the next
call's.  Fill an `int a[40]` in `main` with 7s, call an `f()` whose
first local is set to 99, and `a[5]` comes back as 99.  The
elements that don't fit hang below `main`'s `rsp`, exactly where
the call's return address, `f`'s saved `rbp`, and `f`'s locals
land.  M2-Planet never needs more than 32 slots; other C code might.

`cc-parse-fn-return-type` consumes the return type and discards it.
Every return value is one `rax`-sized word, so codegen doesn't need
it.

```forth file=110-cc-decl.fth
\ cc-emit-spill-params ( -- )  In the function prologue, spill the SYS-V
\ argument registers (rdi/rsi/rdx/rcx/r8/r9) into the local slots reserved
\ for them by cc-parse-param-list (slots 0..cc-fn-param-count-1).
: cc-emit-spill-params
  cc-fn-param-count @ [lit] 1 >= if,
    [lit] 0 cc-emit-store-local
  then,
  cc-fn-param-count @ [lit] 2 >= if,
    [lit] 1 cc-emit-store-local-from-rsi
  then,
  cc-fn-param-count @ [lit] 3 >= if,
    [lit] 2 cc-emit-store-local-from-rdx
  then,
  cc-fn-param-count @ [lit] 4 >= if,
    [lit] 3 cc-emit-store-local-from-rcx
  then,
  cc-fn-param-count @ [lit] 5 >= if,
    [lit] 4 cc-emit-store-local-from-r8
  then,
  cc-fn-param-count @ [lit] 6 >= if,
    [lit] 5 cc-emit-store-local-from-r9
  then, ;

\ ===========================================================================
\ cc-parse-fn-return-type ( -- )
\ Consume the function's return type, which may be:
\   - int / char / void
\   - struct TAG       (tag ident consumed)
\   - typedef-name     (any non-keyword ident — FILE, etc.)
\ Followed by zero or more '*' modifiers.  Codegen treats every return as a
\ single rax-sized value, so the type is not recorded — it's just consumed.
: cc-parse-fn-return-type
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-struct = if,
      cc-next-token-keep
      tok-kind @ tk-ident <> if,
        [lit] 42 die
      then,
    then,
  else,
    tok-kind @ tk-ident <> if,
      [lit] 43 die
    then,
  then,
  cc-count-stars drop ;

```

## 4. Function definitions

`cc-parse-function` compiles one `T NAME(params) { body }`.  The
source comment lists its eleven steps; three of them matter most.

The function is added to the symbol table *before* its parameters
and body are parsed, and before `cc-scope-push`.  Adding it first
lets the body call the function recursively; adding it outside the
function's scope keeps the entry alive after `cc-scope-pop`, so
later functions can call it.

Just before that, `cc-sym-find` fetches any earlier `sk-func` entry
for the same name, which is a prototype registered by §6's
`cc-register-fn-proto`.  Its two fixup lists are then patched to
the new vaddr: `cc-sym-extra` holds forward `call` sites (the
`E8 00 00 00 00` placeholders from Ch 26 §1), and `cc-sym-extra2`
holds forward `movabs rdi, imm64` sites that took the function's
address as a value (Ch 28 §4).  Both heads are then zeroed so a
repeated definition doesn't patch twice.  This is the
emit-remember-patch pattern from Ch 11, with the remembered offsets
parked in symbol-table fields until the definition supplies the
address.

Finally, if the name is `main`, its vaddr goes into
`cc-main-vaddr` for the entry stub.  The body loop ends with an
unconditional `xor rax, rax` and epilogue, which is dead code when
the body already ended in `return` and the default return value
when it didn't.

```forth file=110-cc-decl.fth
\ cc-parse-function — one user-defined `T NAME(params) { body }`.  T may be
\ int / char / void / struct TAG / typedef-name, optionally followed by '*'s.
\ ===========================================================================
\ Layout:
\   1. Consume return type, NAME, '('.
\   2. Capture the function's start vaddr (cc-base-vaddr + cc-out-pos@) and
\      register it in the symbol table BEFORE parsing params/body — this lets
\      the body call this function recursively, and is also needed before any
\      forward-call patch.
\   3. If the name is "main", record cc-main-vaddr for the entry stub.
\   4. Push a fresh scope.  Reset local counter.
\   5. Parse the parameter list — each param becomes a local in slots 0..N-1.
\   6. Consume `{`.
\   7. Emit prologue (256-byte frame, room for 32 locals incl. params).
\   8. Spill arg registers into their slots.
\   9. Loop: parse statements until `}`.
\  10. Emit implicit return (xor rax,rax + epilogue) — wasted bytes if the
\      function already ended with a `return`, but harmless.
\  11. Pop scope.
: cc-parse-function
  cc-parse-fn-return-type
  \ Function name.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 41 die
  then,
  tok-str-addr @ cc-fn-name-addr !
  tok-str-len  @ cc-fn-name-len  !

  [lit]  40 cc-expect-punct-c                     \ '('

  \ Capture any prior sk-func entry for this name BEFORE adding our own,
  \ so we can walk its forward-call fixup list and patch each call site.
  \ cc-sym-find returns the newest match; if a prototype was registered
  \ earlier (cc-register-fn-proto), that's what we get.  -1 means none.
  cc-fn-name-addr @ cc-fn-name-len @ cc-sym-find
  cc-fn-prior-sym-id !

  \ Register the function in the symbol table BEFORE pushing the per-function
  \ scope, so the entry survives cc-scope-pop at function-end and remains
  \ visible to subsequent function bodies.  Its vaddr is the address of the
  \ next byte we'll emit (the prologue's first byte, which we haven't emitted
  \ yet — but we will, immediately after the param list and the spill).
  cc-fn-name-addr @ cc-fn-name-len @
  sk-func
  ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +                    ( a u kind ty vaddr )
  cc-sym-add drop

  \ Patch any forward-call fixups registered against the prior prototype.
  \ The fixup list head lives in that entry's cc-sym-extra cell.  After
  \ patching we zero the head so a repeat definition doesn't double-patch.
  \ cc-sym-extra2 holds a parallel list for `movabs rdi, imm64` rvalue sites
  \ (function-pointer references that appear before the definition).
  cc-fn-prior-sym-id @ [lit] 0 >= if,
    cc-fn-prior-sym-id @ cc-sym-kind-of sk-func = if,
      cc-fn-prior-sym-id @ cc-sym-extra-of
      cc-base-vaddr cc-out-pos @ +
      cc-walk-and-patch-to-vaddr
      [lit] 0 cc-fn-prior-sym-id @ cc-sym-set-extra
      cc-fn-prior-sym-id @ cc-sym-extra2-of
      cc-base-vaddr cc-out-pos @ +
      cc-walk-and-patch-imm64-to-vaddr
      [lit] 0 cc-fn-prior-sym-id @ cc-sym-set-extra2
    then,
  then,

  \ If this is main, also record the vaddr for the entry-stub patch.
  cc-fn-name-addr @ cc-fn-name-len @ cc-is-main? if,
    cc-base-vaddr cc-out-pos @ + cc-main-vaddr !
  then,

  \ Reset locals; push scope (so params + body locals are popped together).
  [lit] 0 cc-fn-local-count !
  \ Reset per-function label table, break/continue stacks, switch depths.
  [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth        !
  [lit] 0 cc-loop-switch-depth   !
  cc-scope-push

  \ Parameter list (consumes through ')').
  cc-parse-param-list

  [lit] 123 cc-expect-punct-c                     \ '{'

  \ Prologue.
  [lit] 256 cc-emit-prologue

  \ Spill SYS-V argument registers into local slots 0..N-1.
  cc-emit-spill-params

  \ Body: stmt* until '}'.
  begin,
    cc-next-token-keep
    cc-block-end? 0=
  while,
    cc-putback-token
    cc-parse-stmt-tramp
  repeat,
  \ '}' was consumed by the loop test.

  \ Implicit return: if the body already ended with `return`, this is a few
  \ bytes of unreachable epilogue — harmless.  If it didn't, the function
  \ falls through to here and we need to terminate properly.
  cc-emit-xor-rax-rax                             \ rax := 0 (default return)
  cc-emit-epilogue

  cc-scope-pop ;

```

## 5. Enums and typedefs

Enums and typedefs generate no code; they only add names to the
symbol table.  Each enumerator becomes an `sk-enum` entry whose
`val` is its integer value.  `cc-enum-next-val` counts up from 0,
restarting after `= N`, and a trailing comma before `}` is allowed.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Enum and typedef definitions (file-scope only).
\ ===========================================================================
\ Enum:  `enum [TAG] { NAME (= INT)?, NAME, ... };`
\ Typedef: `typedef BASE '*'* NAME ;`   (BASE = int / char / void / struct TAG)
\
\ Both register their introduced names in the symbol table so later code can
\ reference them via the standard cc-sym-find path.

variable cc-enum-next-val

\ cc-parse-enum-def ( -- )  'enum' keyword has been consumed by the dispatcher.
\ Parses an optional tag, then `{ enumerator-list };`.
\ Each enumerator becomes an sk-enum entry whose val is the enumerator's
\ integer value (0-based by default, restart-from-N after `= N`).
: cc-parse-enum-def
  \ Optional tag — discard.
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    \ Tag IDENT — ignore.
  else,
    cc-putback-token
  then,

  [lit] 123 cc-expect-punct-c                     \ '{'

  [lit] 0 cc-enum-next-val !

  \ Enumerator loop.
  [lit] 0 0=                                       \ keep-going flag = -1
  begin,
    dup
  while,
    drop
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 100 die
    then,
    tok-str-addr @ tok-str-len @                  ( a u )

    \ Optional `= INT_LITERAL`.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 61 = and if,
      cc-next-token-keep
      tok-kind @ tk-num <> if,
        [lit] 102 die
      then,
      tok-num @ cc-enum-next-val !
    else,
      cc-putback-token
    then,

    \ Add to symbol table as sk-enum.  ( a u kind type val )
    sk-enum
    [lit] 0                                       \ type unused
    cc-enum-next-val @                            \ val
    cc-sym-add drop

    [lit] 1 cc-enum-next-val +!

    \ Separator: ',' continues, '}' terminates.  A trailing ',' before '}'
    \ is allowed: peek the next token; if it's '}', stop.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 44 = and if,
      \ Peek to allow trailing comma.
      cc-next-token-keep
      tok-kind @ tk-punct = tok-num @ [lit] 125 = and if,
        cc-putback-token                           \ leave '}' for the close
        [lit] 0                                    \ stop
      else,
        cc-putback-token                           \ not '}', let next iter read
        [lit] 0 0=                                 \ continue
      then,
    else,
      tok-kind @ tk-punct = tok-num @ [lit] 125 = and if,
        cc-putback-token                           \ leave '}' for the close
        [lit] 0                                    \ stop
      else,
        [lit] 101 die
      then,
    then,
  repeat,
  drop                                             \ discard final flag

  [lit] 125 cc-expect-punct-c                     \ '}'
  [lit]  59 cc-expect-punct-c ;                   \ ';'

```

A typedef name becomes an `sk-typedef` entry whose `val` is an
encoded type word.  `cc-parse-typedef` accepts plain aliases
(`typedef int int_ptr;`) and the function-pointer form
(`typedef void (*FUNCTION)(void);`) that M2-Planet's `gcc_req.h`
uses.  For the latter it skips the parameter list with a paren
counter and records the name as a pointer to function, without
checking the signature.

```forth file=110-cc-decl.fth
\ cc-parse-typedef ( -- )  'typedef' has been consumed by the dispatcher.
\ Grammar: typedef BASE '*'* NAME ';'
\ Supported bases: int / char / void / struct TAG / another typedef.
\ Registers NAME as sk-typedef with val = encoded type word.
\
\ Uses cc-td-ty to stage the type so the data stack stays shallow across
\ keyword / pointer / IDENT parsing — easier than r-stack juggling.
variable cc-td-ty
: cc-parse-typedef
  cc-next-token-keep
  \ Parse base type into cc-td-ty.
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-int = if,
      ty-int [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-char = if,
      ty-char [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-void = if,
      ty-void [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-struct = if,
      cc-lookup-struct-tag drop
      ty-struct [lit] 0 ty-make cc-td-ty !
    else,
      [lit] 110 die
    then, then, then, then,
  else,
    tok-kind @ tk-ident = if,
      tok-str-addr @ tok-str-len @ cc-sym-find
      dup [lit] 0 < if,
        [lit] 111 die
      then,
      dup cc-sym-kind-of sk-typedef <> if,
        [lit] 112 die
      then,
      cc-sym-val-of cc-td-ty !
    else,
      [lit] 113 die
    then,
  then,

  \ Add pointer stars onto whatever base we got.
  cc-count-stars                                   ( extra-stars )
  cc-td-ty @ +                                     ( final-ty )
  cc-td-ty !

  \ Distinguish:
  \   typedef BASE *... NAME ';'                  (simple alias)
  \   typedef BASE (*NAME) ( params ) ';'         (function-pointer typedef)
  \ M2-Planet's gcc_req.h uses the fn-ptr form for `typedef void (*FUNCTION)(void);`.
  \ The return type and parameter types are parsed-and-discarded; NAME is
  \ registered as a pointer-to-function (ty-func, depth 1), matching how
  \ encodes inline `int (*op)(int)` locals — sufficient for parse-through
  \ without enabling actual indirect call via a typedef'd name yet.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 40 = and if,
    \ '(' — function-pointer typedef.  Consume one or more '*'s, then IDENT,
    \ then ')'.  Then consume the parameter list parens (balanced).
    cc-count-stars drop                            \ at least one star expected
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 116 die
    then,
    tok-str-addr @ tok-str-len @                   ( a u )
    [lit] 41 cc-expect-punct-c                     \ ')'
    [lit] 40 cc-expect-punct-c                     \ '(' of param list
    \ Skip tokens paren-balanced until matching ')'.  Depth starts at 1.
    [lit] 1
    begin,
      dup [lit] 0 >
    while,
      cc-next-token-keep
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 1 + else,
        tok-num @ [lit] 41 = if, [lit] 1 - else,
        then, then,
      then,
    repeat,
    drop                                           ( a u )
    sk-typedef [lit] 0                             ( a u kind type )
    ty-func [lit] 1 ty-make                        ( a u kind type val )
    cc-sym-add drop
  else,
    \ Plain IDENT (the new typedef name) — putback first since we just peeked.
    tok-kind @ tk-ident <> if,
      [lit] 114 die
    then,
    tok-str-addr @ tok-str-len @                   ( a u )
    sk-typedef [lit] 0 cc-td-ty @                  ( a u kind type val )
    cc-sym-add drop
  then,

  [lit] 59 cc-expect-punct-c ;                    \ ';'

```

## 6. Top-level elision

Real C files contain far more top-level forms than function
definitions: prototypes with every kind of return type, `extern`
declarations, file-scope variables.  Each one has to parse, and
most generate nothing.  The trouble is that `int f(void);`,
`int f(void) { ... }`, and `int f;` all start the same way.

The comment block explains the strategy: scan ahead through
balanced parentheses to the first `;` or `{` at depth 0.
`cc-top-peek-is-fn-def?` returns true if `{` comes first.  Like the
other peeks, it restores the lexer state before returning, so it
consumes nothing.

```forth file=110-cc-decl.fth
\ ---------------------------------------------------------------------------
\ Top-level forward-decl / file-scope-var elision.
\ ---------------------------------------------------------------------------
\ Our compiler only knows how to emit code for `int NAME(params) { body }`
\ function definitions.  When parsing real-world C headers we encounter a
\ profusion of other top-level forms:
\
\   void f(args);             /* forward fn decl, non-int return type */
\   char* f(args);            /* forward fn decl, pointer return type */
\   struct T* f(args);        /* forward fn decl, struct-ptr return type */
\   int f(args);              /* forward fn decl, int return type (no body) */
\   extern int g;             /* file-scope variable */
\   struct T* g_list;         /* file-scope variable */
\
\ None of these need to GENERATE anything in our target (the body is missing
\ for forward decls; file-scope vars aren't yet supported).  But they DO need
\ to PARSE without exploding so the headers can flow through.
\
\ Strategy: at top level, when we see a type-introducing keyword (int / char /
\ void / struct / typedef-name) that isn't a struct/enum/typedef DEFINITION,
\ peek ahead through balanced parens for the next ';' vs '{':
\   - ';' first → forward decl or file-scope var → elide everything up to and
\     including that ';'.
\   - '{' first → function definition.  Rewind and dispatch to cc-parse-function
\     which expects 'int' return type (so 'void f() { ... }' will still fail).
\
\ The peek uses a save/restore of the lexer state (cc-src-pos / cc-src-line /
\ cc-tok-pending plus tok-* globals), separate from cc-fnptr-* slots so it
\ won't conflict with nested function-body parsing.

\ cc-top-peek-is-fn-def? ( -- f )
\ Scan tokens forward (paren-balanced) until we hit ';' or '{' at depth 0,
\ or EOF.  Return -1 iff '{' is hit first.  ALWAYS restores lexer state.
\ Loop convention: begin, COND while, repeat, runs while COND is non-zero.
\ So we push -1 (continue) for "keep scanning" and 0 (stop) to exit.
variable cc-top-peek-result
variable cc-top-peek-depth
variable cc-top-peek-go                            \ -1 keep scanning, 0 stop

: cc-top-peek-is-fn-def?
  cc-top-lookahead-save
  [lit] 0 cc-top-peek-depth !
  [lit] 0 cc-top-peek-result !                  \ default: not a fn def
  [lit] 0 0= cc-top-peek-go !                   \ -1 = keep scanning
  begin,
    cc-top-peek-go @
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if,
      [lit] 0 cc-top-peek-go !
    else,
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 1 cc-top-peek-depth +! then,
        tok-num @ [lit] 41 = if, [lit] 1 cc-top-peek-depth -! then,
        tok-num @ [lit] 59 = if,                  \ ';'
          cc-top-peek-depth @ [lit] 0 = if,
            [lit] 0 cc-top-peek-result !
            [lit] 0 cc-top-peek-go !
          then,
        then,
        tok-num @ [lit] 123 = if,                 \ '{'
          cc-top-peek-depth @ [lit] 0 = if,
            [lit] 0 0= cc-top-peek-result !
            [lit] 0 cc-top-peek-go !
          then,
        then,
      then,
    then,
  repeat,
  cc-top-lookahead-restore
  cc-top-peek-result @ ;

```

When the answer is "not a definition", `cc-top-peek-has-paren?`
tells a prototype (it saw a `(`) from a global variable (it didn't).
`cc-top-skip-to-semi` consumes tokens through the next depth-0 `;`.

```forth file=110-cc-decl.fth
\ cc-top-peek-has-paren? ( -- f )
\ Walks tokens forward (paren-balanced) until ';' or '{' or EOF.  Returns -1
\ iff at least one '(' was encountered before the terminator.  Always restores
\ lexer state.  Used to distinguish function prototypes from global decls when
\ cc-top-peek-is-fn-def? has already returned 0.
variable cc-top-paren-flag
variable cc-top-paren-go
: cc-top-peek-has-paren?
  cc-top-lookahead-save
  [lit] 0 cc-top-paren-flag !
  [lit] 0 0= cc-top-paren-go !
  begin,
    cc-top-paren-go @
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if,
      [lit] 0 cc-top-paren-go !
    else,
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 0 0= cc-top-paren-flag ! then,
        tok-num @ [lit] 59 = if, [lit] 0 cc-top-paren-go ! then,
        tok-num @ [lit] 123 = if, [lit] 0 cc-top-paren-go ! then,
      then,
    then,
  repeat,
  cc-top-lookahead-restore
  cc-top-paren-flag @ ;

\ cc-top-skip-to-semi ( -- )
\ Consume tokens through and including the next top-level ';'.  Paren-balanced
\ so commas / parens inside parameter lists don't fool us.  If we run into
\ EOF first, we exit cleanly so the outer loop also exits.
variable cc-top-skip-depth
variable cc-top-skip-go
: cc-top-skip-to-semi
  [lit] 0 cc-top-skip-depth !
  [lit] 0 0= cc-top-skip-go !
  begin,
    cc-top-skip-go @
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if,
      [lit] 0 cc-top-skip-go !
    else,
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 1 cc-top-skip-depth +! then,
        tok-num @ [lit] 41 = if, [lit] 1 cc-top-skip-depth -! then,
        tok-num @ [lit] 59 = if,
          cc-top-skip-depth @ [lit] 0 = if,
            [lit] 0 cc-top-skip-go !
          then,
        then,
      then,
    then,
  repeat, ;

```

`cc-register-fn-proto` adds a prototype as an `sk-func` with
`val = 0`, which is what makes forward calls in §2 possible.  The
symbol table's newest-first lookup (the same rule as the dictionary
in Ch 17 and the symbol table in Ch 24) settles which entry a call
finds.  A later definition appends a newer row, so later calls go
straight to the body, while earlier forward calls stay on the
prototype's fixup list until §4 patches them.

That rule also causes a trap, and the comment above the word
describes it.  M2-Planet declares some prototypes in two files,
with the definition between them in the concatenated monolith.  The
second prototype would add a newer `val = 0` row that shadows the
definition and whose fixups nothing patches.  So
`cc-register-fn-proto` skips the add when the name is already an
`sk-func`.

```forth file=110-cc-decl.fth
\ cc-register-fn-proto ( -- )  Parse `T '*'* NAME (...);` and register NAME
\ as sk-func with vaddr=0 so call sites resolve.  When the actual definition
\ is later parsed, cc-parse-function adds a newer sk-func entry; cc-sym-find
\ (newest-first) returns the definition for backward calls.  Forward calls
\ (call to fn before its def) are patched through the symbol's fixup list.
\ Caller has put-back the first token of the prototype.  Consumes through ';'.
\
\ Idempotency: real-world headers often re-declare the same prototype across
\ TUs (e.g. M2-Planet has `struct token_list* read_all_tokens(...)` in both
\ cc_macro.c and cc.c, with the definition in cc_reader.c sandwiched in
\ between).  Concatenated into our monolith the post-definition prototype
\ would register a new sk-func with val=0, and because cc-sym-find returns
\ the newest match, every later call site emits a forward-call placeholder
\ against a stale entry whose fixups are never patched.  Skip the re-add if
\ the name is already an sk-func.
: cc-register-fn-proto
  cc-parse-fn-return-type
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 44 die
  then,
  tok-str-addr @ tok-str-len @                    ( a u )
  2dup cc-sym-find                                ( a u id-or-neg1 )
  dup [lit] 0 >= if,
    cc-sym-kind-of sk-func = if,
      \ Already registered as a function — drop the leftover ( a u ).
      2drop
      cc-top-skip-to-semi
    else,
      sk-func ty-int [lit] 0 ty-make [lit] 0      ( a u kind ty val=0 )
      cc-sym-add drop
      cc-top-skip-to-semi
    then,
  else,
    drop                                          ( a u )
    sk-func ty-int [lit] 0 ty-make [lit] 0        ( a u kind ty val=0 )
    cc-sym-add drop
    cc-top-skip-to-semi
  then, ;

```

## 7. File-scope globals

`cc-parse-global-decl` accepts three forms, all stored in
`cc-globals-buf`:

- `T name;` allocates one slot;
- `T name = N;` allocates one slot and writes the (possibly
  negative) integer literal into it with `cc-globals-store-8le`, so
  the value is in the image before the program runs;
- `T name[N];` allocates `N*8` zeroed bytes.

A slot is normally 8 bytes.  `cc-gdecl-scalar-bytes` makes one
exception: a struct *value* gets its full descriptor size, rounded
up to a multiple of 8, so a store past its first field cannot
overwrite the next global.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ File-scope global variable declaration.
\ ===========================================================================
\ Parses ONE top-level declaration of the form
\
\    T '*'* name ';'
\    T '*'* name '=' int-literal ';'
\    T '*'* name '[' N ']' ';'
\
\ where T is one of int/char/void/long/short/etc.  The base type is consumed
\ by the caller (cc-parse-function-list) — when we get here the lookahead has
\ been put back so cc-next-token-keep yields the type keyword again.  We
\ re-consume it, accept star-modifiers, then expect IDENT, then optional
\ [N] OR optional `= NUM`, then ';'.
\
\ Storage is allocated in cc-globals-buf (8 bytes per scalar — a struct
\ VALUE gets its full descriptor size rounded up to 8 — N*8 per array).
\ Scalar initializer (must be an int literal — possibly negated) is written
\ into the buffer directly so the runtime image already contains the value.
\ Arrays start zero-initialized.  Function-pointer, aggregate, and struct
\ initializers are not implemented.
\
\ Errors abort with status 16x so they're distinguishable
\ from older codes).

variable cc-gdecl-base
variable cc-gdecl-name-a
variable cc-gdecl-name-u
variable cc-gdecl-n                                \ element count (>=1)
variable cc-gdecl-is-array
variable cc-gdecl-slot
variable cc-gdecl-desc
variable cc-gdecl-ptr-depth

\ cc-parse-global-int-literal ( -- v )
\ Read a single int literal as an initializer value.  Accepts an optional
\ leading '-' for negative literals.  Anything else aborts.
: cc-parse-global-int-literal                     ( -- v )
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 45 = and if,
    cc-next-token-keep
    tok-kind @ tk-num <> if,
      [lit] 163 die
    then,
    [lit] 0 tok-num @ -
  else,
    tok-kind @ tk-num <> if,
      [lit] 163 die
    then,
    tok-num @
  then, ;

\ cc-gdecl-scalar-bytes ( -- n )  Byte size of one non-array global slot.
\ A struct VALUE (ty-struct base, zero pointer depth, descriptor known)
\ needs its full descriptor size, rounded up to a multiple of 8 — a flat 8
\ would let stores past the first field clobber the next global.  Everything
\ else — ints, chars, pointers, struct pointers, opaque struct refs — is one
\ 8-byte slot.
: cc-gdecl-scalar-bytes                           ( -- n )
  cc-gdecl-base @ ty-struct =
  cc-gdecl-ptr-depth @ [lit] 0 = and
  cc-gdecl-desc @ [lit] 0 <> and if,
    cc-gdecl-desc @ cc-sd-total-size [lit] 7 + [lit] 8 / [lit] 8 *
  else,
    [lit] 8
  then, ;

```

The parser records the base type with `char` kept distinct from the
other keywords, so the array-index path in Ch 28 §3 uses byte
loads and stores for a `char*` global.  For a `struct TAG` base it
uses the soft lookup `cc-lookup-struct-tag-soft`, because
M2-Planet's `cc_globals.c` declares pointers to structs that are
never defined in scope.  The registered symbol's extra field holds
the element count for an array (so Ch 28 can tell array decay from
a scalar load) or the struct descriptor otherwise.

```forth file=110-cc-decl.fth
\ cc-parse-global-decl ( -- )  Caller has already done cc-skip-storage-quals;
\ the next token is the base-type keyword OR a typedef-name IDENT.  Consumes
\ through ';'.
: cc-parse-global-decl                            ( -- )
  [lit] 0 cc-gdecl-desc !
  ty-int cc-gdecl-base !
  \ Read base type.
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    \ Support struct TAG as base type.
    tok-kw-id @ kw-struct = if,
      ty-struct cc-gdecl-base !
      \ Soft lookup: descriptor pointer if the struct is defined, 0 otherwise.
      \ cc_globals.c declares `struct type* foo;` without a `struct type {...}`
      \ in scope — that's an opaque-pointer pattern we still need to parse.
      cc-lookup-struct-tag-soft cc-gdecl-desc !
    then,
    \ Distinguish `char` from other primitives so `char* foo;` records ty-char
    \ in the symbol table.  Without this, `char* hold_string;` looks identical
    \ to `int* foo;` and the array-index path uses qword stride/load on its
    \ bytes — corrupting tokenizer scratch buffers in M2-Planet's preprocessor.
    \ int/void/long/short/etc. all collapse to ty-int (storage is 8 bytes
    \ regardless; only the byte-stride dispatch cares).
    tok-kw-id @ kw-char = if,
      ty-char cc-gdecl-base !
    then,
  else,
    \ Typedef-name IDENT (FILE, uint8_t, ...).  We don't need to verify it
    \ actually resolves to a known typedef — the caller already determined
    \ this is a declaration via cc-top-peek-* lookahead.
    tok-kind @ tk-ident <> if,
      [lit] 160 die
    then,
  then,

  \ Star-modifiers (pointer depth).
  cc-count-stars cc-gdecl-ptr-depth !

  \ Name IDENT.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 161 die
  then,
  tok-str-addr @ cc-gdecl-name-a !
  tok-str-len  @ cc-gdecl-name-u !

  \ Peek next token: '[', '=', or ';'.
  cc-next-token-keep
  [lit] 0 cc-gdecl-is-array !
  [lit] 1 cc-gdecl-n !

  tok-kind @ tk-punct = tok-num @ [lit] 91 = and if,
    \ Array form: 'T name [ N ]'.
    cc-next-token-keep
    tok-kind @ tk-num <> if,
      [lit] 162 die
    then,
    tok-num @ cc-gdecl-n !
    [lit] 0 0= cc-gdecl-is-array !
    [lit] 93 cc-expect-punct-c                      \ ']'
    [lit] 59 cc-expect-punct-c                      \ ';'
  else,
    tok-kind @ tk-punct = tok-num @ [lit] 61 = and if,
      \ Scalar with initializer.  Allocate slot first so we can write the
      \ initializer bytes; then add the symbol.
      cc-gdecl-scalar-bytes cc-globals-alloc
      cc-gdecl-slot !
      cc-parse-global-int-literal
      cc-gdecl-slot @ cc-globals-store-8le
      [lit] 59 cc-expect-punct-c                    \ ';'
    else,
      tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
        \ Bare uninitialized scalar.  Allocate the slot.
        cc-gdecl-scalar-bytes cc-globals-alloc cc-gdecl-slot !
      else,
        [lit] 164 die
      then,
    then,
  then,

  \ For arrays, allocate the slot now (initializer was not consumed above).
  cc-gdecl-is-array @ if,
    cc-gdecl-n @ [lit] 8 * cc-globals-alloc cc-gdecl-slot !
  then,

  \ Register the symbol.  Stack target for cc-sym-add: ( a u kind type val ).
  cc-gdecl-name-a @ cc-gdecl-name-u @               ( a u )
  sk-global                                          ( a u kind )
  cc-gdecl-base @ cc-gdecl-ptr-depth @ ty-make      ( a u kind type )
  cc-gdecl-slot @                                    ( a u kind type val )
  cc-sym-add                                         ( id )

  \ Arrays: record element count in the extra field so the codegen path can
  \ tell array decay from scalar deref.
  cc-gdecl-is-array @ if,
    cc-gdecl-n @ swap cc-sym-set-extra
  else,
    \ Not an array — record the struct descriptor if any.
    cc-gdecl-desc @ swap cc-sym-set-extra
  then, ;

```

Global data can't go into `cc-out-buf` as it is parsed, because the
code after it isn't written yet and the data's address depends on
where the code ends.  It is one more case of Ch 21's one buffer per
responsibility.  Each reference to a global emits a `movabs rdi,
imm64` placeholder and records a fixup.  `cc-finalize-globals`,
called by the Ch 32 driver after all code is emitted, appends
`cc-globals-buf` to `cc-out-buf`, sets `cc-globals-base-vaddr`, and
patches every recorded placeholder with base plus slot.

```forth file=110-cc-decl.fth
\ cc-finalize-globals ( -- )  After the entire program has been parsed and
\ all functions emitted, append cc-globals-buf to cc-out-buf and patch every
\ recorded fixup to point at the now-known global vaddrs.
\
\ cc-globals-base-vaddr is set to cc-base-vaddr + (cc-out-pos at the moment
\ globals are appended).  Once that's known, each fixup's imm64 placeholder
\ is overwritten with (cc-globals-base-vaddr + slot).
: cc-finalize-globals
  cc-base-vaddr cc-out-pos @ + cc-globals-base-vaddr !
  \ Append cc-globals-pos bytes from cc-globals-buf to cc-out-buf.
  [lit] 0
  begin, dup cc-globals-pos @ < while,
    dup cc-globals-buf + c@ cc-emit-byte
    [lit] 1 +
  repeat, drop
  \ Patch each fixup.  i walks 0..cc-gfixup-count-1.
  [lit] 0
  begin, dup cc-gfixup-count @ < while,
    dup cc-gfixup-slot     sym-slot @              \ slot
    cc-globals-base-vaddr @ +                       \ vaddr = base + slot
    over cc-gfixup-out-pos sym-slot @              \ patch-offset
    cc-out-patch-8le
    [lit] 1 +
  repeat, drop ;

```

Every file-scope form now has a parser, and
`cc-parse-function-list` is the loop that picks one.  For each
declaration it skips storage qualifiers, then:

1. on `struct`, peeks two tokens: `struct TAG {` is a struct
   definition; anything else goes through the three-way peek below;
2. on `enum`, calls `cc-parse-enum-def`;
3. on `typedef`, calls `cc-parse-typedef`;
4. on any other type keyword, or on an identifier used as a
   typedef name, runs the three-way peek: a function definition
   goes to `cc-parse-function`, a prototype to
   `cc-register-fn-proto`, and anything else to
   `cc-parse-global-decl`.

```forth file=110-cc-decl.fth
\ cc-parse-function-list ( -- )  Loop over top-level declarations until EOF.
\ See the long comment above for the elision rules.
: cc-parse-function-list
  begin,
    cc-skip-storage-quals
    cc-next-token-keep
    tok-kind @ tk-eof = 0=
  while,
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-struct = if,
        \ Four forms to distinguish:
        \   `struct TAG { ... };`         → struct definition
        \   `struct TAG* foo(...) { ... }` → function definition (struct-ptr return)
        \   `struct TAG* foo(...);`        → fn proto → register with vaddr=0
        \   `struct TAG* g;`               → file-scope var → cc-parse-global-decl
        cc-top-lookahead-save
        cc-next-token                              \ consume tag IDENT (lookahead)
        cc-next-token                              \ peek next token
        tok-kind @ tk-punct = tok-num @ [lit] 123 = and >r
        cc-top-lookahead-restore
        r> if,
          cc-parse-struct-def
        else,
          cc-putback-token
          cc-top-peek-is-fn-def? if,
            cc-parse-function
          else,
            cc-top-peek-has-paren? if,
              cc-register-fn-proto
            else,
              cc-parse-global-decl
            then,
          then,
        then,
      else,
        tok-kw-id @ kw-enum = if,
          cc-parse-enum-def
        else,
          tok-kw-id @ kw-typedef = if,
            cc-parse-typedef
          else,
            \ int/char/void/long/short/etc. — could be fn def or fwd decl/var.
            cc-putback-token
            cc-top-peek-is-fn-def? if,
              cc-parse-function
            else,
              cc-top-peek-has-paren? if,
                \ Function prototype `T name(...);` — register as sk-func.
                cc-register-fn-proto
              else,
                \ File-scope global variable.
                cc-parse-global-decl
              then,
            then,
          then,
        then,
      then,
    else,
      \ Top-level starting with an ident — typedef-name used as a type
      \ (e.g. `FILE* p;`, `FILE* foo();`, `FILE* foo(){...}`).
      cc-putback-token
      cc-top-peek-is-fn-def? if,
        cc-parse-function
      else,
        cc-top-peek-has-paren? if,
          cc-register-fn-proto
        else,
          cc-parse-global-decl
        then,
      then,
    then,
  repeat, ;

```

## 8. The entry stub and the top-level driver

The kernel starts a process at `0x400078`, the first byte after
the ELF and program headers, with `argc` at `[rsp]` and the `argv`
array just above it.  `cc-emit-entry-stub` emits 26 bytes there:
load `argc` into `rdi` and `&argv[0]` into `rsi`, `call main`, move
the result into `rdi`, and `exit`.  The `call` is emitted before
`main` exists, so its rel32 is a placeholder whose offset goes into
`cc-call-main-patch`.  `cc-patch-call-main` fills it in after the
whole file is parsed, the last emit-remember-patch in the compiler.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Entry-stub emission and rel32 patching.
\ ===========================================================================

\ cc-emit-entry-stub ( -- )  Emit at vaddr cc-entry-vaddr (0x400078):
\     mov  rdi, [rsp]      48 8B 3C 24      ; argc (kernel puts it at [rsp])
\     lea  rsi, [rsp+8]    48 8D 74 24 08   ; argv = &argv[0]
\     call <main>          E8 <rel32>
\     mov  rdi, rax        48 89 C7         ; main's return -> exit code
\     mov  rax, 60         48 C7 C0 3C 00 00 00
\     syscall              0F 05
\ Records the file-offset of the rel32 in cc-call-main-patch.
\ Stack alignment: kernel hands us rsp 16-aligned and we don't touch it before
\ `call`, so main enters 8-mod-16 as SysV requires.
: cc-emit-entry-stub
  \ mov rdi, [rsp]   — argc
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit]  60 cc-emit-byte
  [lit]  36 cc-emit-byte

  \ lea rsi, [rsp+8] — argv
  [lit]  72 cc-emit-byte
  [lit] 141 cc-emit-byte
  [lit] 116 cc-emit-byte
  [lit]  36 cc-emit-byte
  [lit]   8 cc-emit-byte

  [lit] 232 cc-emit-byte                          \ E8
  cc-out-pos @ cc-call-main-patch !               \ remember rel32 file-offset
  [lit] 0 cc-emit-4le                             \ rel32 placeholder

  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 199 cc-emit-byte                          \ mov rdi, rax

  [lit]  72 cc-emit-byte
  [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte
  [lit]  60 cc-emit-4le                           \ mov rax, 60

  [lit]  15 cc-emit-byte
  [lit]   5 cc-emit-byte ;                        \ syscall

\ cc-patch-call-main ( -- )  Compute and store the call's rel32.
\ rel32 = main_vaddr - vaddr_of_next_instr
\       = main_vaddr - (cc-base-vaddr + cc-call-main-patch + 4)
: cc-patch-call-main
  cc-main-vaddr @
  cc-base-vaddr cc-call-main-patch @ + [lit] 4 + -
  cc-call-main-patch @
  cc-out-patch-4le ;

```

The libc shims from Ch 26 come straight after the stub.
`cc-emit-shims` emits each of the eleven and registers it as an
`sk-func` at its vaddr, so a user call to `putchar(c)` compiles to
an ordinary `call <vaddr>`.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Top-level driver
\ ===========================================================================

\ ===========================================================================
\ Built-in libc shim emission + symtab registration.
\ ===========================================================================
\ The shims (putchar, exit, getchar) live at the very start of the code
\ segment, immediately after the 26-byte entry stub.  Registering them in
\ the symbol table BEFORE parsing user functions means cc-parse-call's
\ name-lookup path finds them just like any user-defined function.

\ Pre-baked name strings (raw bytes, no length prefix; the length is supplied
\ explicitly to cc-sym-add).
create cc-name-putchar
[lit] 112 c, [lit] 117 c, [lit] 116 c, [lit]  99 c,
[lit] 104 c, [lit]  97 c, [lit] 114 c,            \ "putchar"

create cc-name-exit
[lit] 101 c, [lit] 120 c, [lit] 105 c, [lit] 116 c,    \ "exit"

create cc-name-getchar
[lit] 103 c, [lit] 101 c, [lit] 116 c, [lit]  99 c,
[lit] 104 c, [lit]  97 c, [lit] 114 c,            \ "getchar"

create cc-name-fputs
[lit] 102 c, [lit] 112 c, [lit] 117 c, [lit] 116 c, [lit] 115 c,
create cc-name-fopen
[lit] 102 c, [lit] 111 c, [lit] 112 c, [lit] 101 c, [lit] 110 c,
create cc-name-fclose
[lit] 102 c, [lit]  99 c, [lit] 108 c, [lit] 111 c, [lit] 115 c, [lit] 101 c,
create cc-name-fputc
[lit] 102 c, [lit] 112 c, [lit] 117 c, [lit] 116 c, [lit]  99 c,
create cc-name-fread
[lit] 102 c, [lit] 114 c, [lit] 101 c, [lit]  97 c, [lit] 100 c,
create cc-name-fwrite
[lit] 102 c, [lit] 119 c, [lit] 114 c, [lit] 105 c, [lit] 116 c, [lit] 101 c,
create cc-name-calloc
[lit]  99 c, [lit]  97 c, [lit] 108 c, [lit] 108 c, [lit] 111 c, [lit]  99 c,
create cc-name-memset
[lit] 109 c, [lit] 101 c, [lit] 109 c, [lit] 115 c, [lit] 101 c, [lit] 116 c,
create cc-name-free
[lit] 102 c, [lit] 114 c, [lit] 101 c, [lit] 101 c,

\ cc-emit-shims ( -- )  Emit each shim's body and register it in the symbol
\ table as sk-func with val = its absolute vaddr.
: cc-emit-shims
  \ putchar
  cc-name-putchar [lit] 7
  sk-func
  ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +                    ( a u kind ty vaddr )
  cc-sym-add drop
  cc-emit-putchar-shim

  \ exit
  cc-name-exit [lit] 4
  sk-func
  ty-void [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-exit-shim

  \ getchar
  cc-name-getchar [lit] 7
  sk-func
  ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-getchar-shim

  \ fputs
  cc-name-fputs [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fputs-shim

  \ fputc
  cc-name-fputc [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fputc-shim

  \ fopen
  cc-name-fopen [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fopen-shim

  \ fclose
  cc-name-fclose [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fclose-shim

  \ fwrite
  cc-name-fwrite [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fwrite-shim

  \ fread
  cc-name-fread [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fread-shim

  \ calloc
  cc-name-calloc [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-calloc-shim

  \ free (no-op bump allocator)
  cc-name-free [lit] 4
  sk-func ty-void [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-free-shim ;

```

`cc-emit-external-protos` registers `memset` as an undefined
prototype for the upstream tests that declare it, and
`cc-emit-libc-typedefs` registers `FILE`, `size_t`, and the fixed-
width integer names as `sk-typedef`s of `ty-int`.

`cc-parse-program` then runs the whole compile in six calls: entry
stub, shims, external prototype, typedefs, the top-level loop, and
the `call main` patch.  Ch 32 shows how `120-cc-main.fth` wraps it
with `cc-finalize-globals`, `cc-finalize-elf`, and
`cc-write-output`.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ M2 test-suite external prototype.  The M2 monolith itself does not call
\ memset, but the published parity script compares selected upstream tests
\ where memset is declared by an elided system header.
\ ===========================================================================

: cc-emit-external-protos
  cc-name-memset  [lit] 6  sk-func ty-int [lit] 0 ty-make  [lit] 0 cc-sym-add drop ;

\ Built-in typedefs for opaque libc/stdint names.  All map to ty-int so the
\ parser will accept `FILE* p;`, `uint8_t x;`, etc. — codegen still treats
\ them as 8-byte slots regardless of the C-visible width.
create cc-name-FILE
[lit]  70 c, [lit]  73 c, [lit]  76 c, [lit]  69 c,
create cc-name-int8_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  56 c, [lit]  95 c, [lit] 116 c,
create cc-name-int16_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  49 c, [lit]  54 c, [lit]  95 c, [lit] 116 c,
create cc-name-int32_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  51 c, [lit]  50 c, [lit]  95 c, [lit] 116 c,
create cc-name-int64_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  54 c, [lit]  52 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint8_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  56 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint16_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  49 c, [lit]  54 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint32_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  51 c, [lit]  50 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint64_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  54 c, [lit]  52 c, [lit]  95 c, [lit] 116 c,
create cc-name-size_t
[lit] 115 c, [lit] 105 c, [lit] 122 c, [lit] 101 c, [lit]  95 c, [lit] 116 c,
create cc-name-ssize_t
[lit] 115 c, [lit] 115 c, [lit] 105 c, [lit] 122 c, [lit] 101 c, [lit]  95 c, [lit] 116 c,

\ cc-emit-libc-typedefs ( -- )  Register the typedef names above so headers
\ that say `FILE* fp;` or `uint8_t b;` parse without rc 30.  All map to ty-int
\ encoded as the sk-typedef's val field (matching cc-parse-typedef's layout).
: cc-emit-libc-typedefs
  cc-name-FILE     [lit] 4  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int8_t   [lit] 6  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int16_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int32_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int64_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint8_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint16_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint32_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint64_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-size_t   [lit] 6  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-ssize_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop ;

\ cc-parse-program ( -- )  Emit entry stub, emit libc shims, register the
\ one external prototype and built-in typedefs, parse all functions, patch
\ entry stub.
: cc-parse-program
  cc-emit-entry-stub
  cc-emit-shims
  cc-emit-external-protos
  cc-emit-libc-typedefs
  cc-parse-function-list
  cc-patch-call-main ;
```

**tri.c at this stage.**  tri.c's `main` calls `line`, `line`
receives two arguments, and the kernel has to reach `main`.  With
tri.c compiled to `/tmp/cc-out` (Ch 21), disassemble the entry
stub, `line`'s prologue and spill, and the call site on line 17:

```sh
for r in 0x78:0x92 0x20a:0x21d 0x3d9:0x3e3; do
  objdump -D -b binary -m i386:x86-64 -M intel \
      --start-address=${r%:*} --stop-address=${r#*:} /tmp/cc-out | grep '^ '
done
```

```
  78:   48 8b 3c 24             mov    rdi,QWORD PTR [rsp]
  7c:   48 8d 74 24 08          lea    rsi,[rsp+0x8]
  81:   e8 5c 02 00 00          call   0x2e2
  86:   48 89 c7                mov    rdi,rax
  89:   48 c7 c0 3c 00 00 00    mov    rax,0x3c
  90:   0f 05                   syscall
 20a:   55                      push   rbp
 20b:   48 89 e5                mov    rbp,rsp
 20e:   48 81 ec 00 01 00 00    sub    rsp,0x100
 215:   48 89 7d f8             mov    QWORD PTR [rbp-0x8],rdi
 219:   48 89 75 f0             mov    QWORD PTR [rbp-0x10],rsi
 3d9:   5e                      pop    rsi
 3da:   5f                      pop    rdi
 3db:   e8 2a fe ff ff          call   0x20a
 3e0:   48 89 c7                mov    rdi,rax
```

The stub's `call` at 0x81 was a placeholder until
`cc-patch-call-main` wrote `5c 02 00 00`, which lands on `main` at
0x2e2.  At the call site, the two arguments were pushed left to
right, so they pop in reverse: `w[r]` into `rsi`, then
`t.rows - 1 - r` into `rdi`.  `line` was already defined, so the
`call` got its real rel32 at once, with no fixup.  `line`'s spill
at 0x215 and 0x219 copies `rdi` and `rsi` into slots 0 and 1, where
`pad` and `n` live from then on.  The stub closes the loop: `main`'s
`rax` becomes `rdi` for `exit` (syscall 60), which is how tri.c's
star count reaches the shell as its exit status.

## Try it

**Small check:** inspect one focused fixture below and trace its
calls, globals, or parameter slots through the chapter.

**Layer check:** there is no standalone root-level test for
`110-cc-decl.fth`; the focused `tests/cc/G*.c` programs are this
chapter's layer checks.

**Bootstrap relevance:** function calls, scopes, globals, and the
entry stub converge in the Stage-A gate.  One sizing path Stage-A
never reaches: `tests/cc/C-struct-global.c` declares a file-scope
`struct` *value* and writes its second field.  If
`cc-gdecl-scalar-bytes` gave it a flat 8 bytes, that write would
clobber the next global.  M2-Planet never declares a global struct
by value, so this fixture (run by `tests/cc/run-gates.sh`) is the
path's only automated coverage.  tri.c's `struct tri t;` takes the
same path:
`od -A x -t x1 -j 0x4c9 /tmp/cc-out` shows its 16 zero bytes, the
last 16 of the file.

```sh
./build.sh
tests/cc/stage-a-check.sh                    # end-to-end gate
```

For the small check, pick one of these focused fixtures:

`tests/cc/G3.c` exercises function definitions with multiple
params (`square`, `sum`); `G12.c` exercises function pointers;
`G14d.c` exercises globals accessed from a function (`bump()`
reading and writing `g_counter`).  The M2-Planet monolith in
`stage-a-check.sh` exercises every path at once.

## Exercises

1. **★★ Trace.** The forward-fixup walk in `cc-parse-function` handles
   both `cc-sym-extra` (rel32 calls) and `cc-sym-extra2`
   (imm64 movabs).  Trace how both lists get populated and
   which path each fixup type originates from.

2. **★★ Verify.** The 256-byte frame caps locals at 32.  Find the largest
   M2-Planet function (most locals) and confirm it fits.
   What changes if you bump the cap?

3. **★★★ Extend.** Parameter spill is hard-coded for 6 args.  Add a 7th param
   path that reads from `[rbp + 16]` (caller-allocated stack
   slot).  Where would the prologue change?

4. **★★ Modify.** The libc shim registration emits the bytes *and* the symbol
   in one pass.  Could you split this into "emit bytes" and
   "register symbol" phases?  What does the new ordering buy
   you?

5. **★★ Trace.** `cc-top-peek-is-fn-def?` walks all tokens to the next `{`
   or `;` at depth 0.  Could it stop after seeing a single
   `(` (since a function definition must have one)?  Construct
   a counterexample.

## After this chapter

The compiler can assemble whole translation units: functions with
parameters (spilled from System V registers into locals), scoped
declarations, file-scope globals, forward-call resolution, and the
26-byte entry stub at `0x400078` that sets up `argc`/`argv`, calls
`main`, and exits.  Once Ch 32's driver adds the globals and ELF
header, the output file is a runnable ELF.

You can read `cc-parse-function` from name through epilogue,
explain why every function reserves the same 256-byte frame, and
walk how `cc-parse-function-list` loops over file-scope
declarations until EOF.

Every line of tri.c now has a word that compiles it.  Two
questions are left: what runs those words in order, and whether
the same words, fed M2-Planet instead of tri.c, produce a compiler
that agrees with GCC's byte for byte.  Ch 32 answers both.

## Takeaways

- Every earlier Part III layer (codegen, expressions, declarations, statements) meets in `cc-parse-function`, which wraps a statement loop in a scope, a prologue, and an epilogue.
- A forward call emits a placeholder that waits on its prototype's symbol-table fixup list until the definition patches it, which is Ch 11's emit-remember-patch at whole-program scale.
- Most top-level forms generate no code, so the top-level loop peeks ahead to the first `;` or `{` to decide between a definition, a prototype, and a global.

Next: Chapter 32 — End to End: Main and the Bootstrap Chain.
