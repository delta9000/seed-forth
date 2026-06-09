# Chapter 31 — Functions: Parameters, Calls, Globals, Entry Stub

```text
Missing capability: the compiler cannot assemble functions, globals, calls, scopes, and program entry.
New pattern: parse file-scope forms while resolving forward calls, scoped locals, globals, and the entry stub.
Artifact after this chapter: a complete C-subset translation-unit compiler.
Proof link: Stage-A can compile whole M2-Planet inputs into a runnable /tmp/cc-out.
```

This chapter assembles the final translation-unit machinery: calls,
function bodies, globals, top-level parsing, and the entry stub.  It
is the final third of `110-cc-decl.fth` (lines 1439–2752) and the
busiest chapter in Part III.  Four anchors do the heavy lifting:
`cc-parse-call` dispatches direct, forward, and indirect calls;
`cc-parse-function` ties the prologue, body, epilogue, and scope
cleanup together; `cc-parse-program` loops over file-scope
declarations; and the 26-byte entry stub at `0x400078` sets up
`argc` / `argv`, calls `main`, and exits.

By the end you'll be able to read each call path, walk a function
from name through epilogue, explain why a `static int x = 3;` at
file scope contributes data but no code, and identify which named
word in `cc-parse-program` does each phase.  The Ch 32 bootstrap-
chain shell drivers (`stage-a-check.sh`, `bootstrap-chain.sh`) and
the byte-identical M1 parity claim against the GCC-built M2-Planet
are deferred to Ch 32.

---

```
        ,_,
   __(@___)___    "the longest chapter.  every piece
   ~~~~~~~~~~~~    of Part III converges here.  the payoff is the
                   next chapter; this one is the work."
```

**How this chapter is organized.**  The chapter walks the final
1,317 lines of `110-cc-decl.fth` in eight sections.  §1 introduces
the chapter's bookkeeping helpers.  Sections §§2–4 are the
*function machinery*: call codegen, parameter parsing with
register-spill, and function definitions with the prologue/epilogue
glue that wires Ch 26's calling convention into the body.  §§5–7
are the *top-level declarators*: enums and typedefs, top-level
forms that elide to nothing, and file-scope globals with deferred
vaddr fixups.  §8 is the *program glue*: the entry stub at
`0x400078` plus the top-level driver `cc-parse-program` that loops
over file-scope declarations until EOF.  Each section shows the
relevant code first, then walks it.

## 1. Setup

A handful of file-scope globals carry per-function state across
the parameter and body parses, and one short helper recognises the
name `main` so the entry stub can find it later.  Nothing here
does code generation yet; this is just the bookkeeping the rest of
the chapter reaches for.

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


`cc-parse-call` is the only entry point for the call-codegen path.
Ch 27's `cc-parse-primary` calls it via `cc-parse-call-vec` once it
has spotted `IDENT (`.

The flow:

1. Parse a comma-separated argument list, pushing each arg's
   value with `cc-emit-push-rdi` and counting them.  The arg
   count threads under the symbol id on the data stack.
2. After `)`, pop the args off the machine stack and into SYS-V
   registers in *reverse* push order (so the last-pushed value
   lands in the n-th register).  This is what
   `cc-emit-pops-for-args` does, walking `i = n-1 .. 0` and
   emitting the right pop per index.
3. Dispatch on symbol kind:
   - `sk-func` with non-zero val → emit `call <abs-vaddr>` via
     `cc-emit-call-vaddr`.
   - `sk-func` with val=0 (forward proto) → emit
     `cc-emit-call-rel32-placeholder` and thread the patch
     offset onto `cc-sym-extra`'s fixup list.
   - `sk-local` with `ty-base = ty-func` (function-pointer
     local) → `cc-emit-load-local-into-rax`, then
     `cc-emit-call-rax` for an indirect call.
4. After the call, `cc-emit-mov-rdi-rax` moves the return value
   into the caller's *evaluation register* — `rdi`, the register
   this compiler threads every expression result through (the
   System V return-value register `rax` is the callee's slot, and
   the caller copies out to `rdi` so the next expression step
   finds it where the rest of `100-cc-expr.fth` expects it).

The cap of 6 args (status 37 on overflow) is the SYS-V limit
before args spill onto the stack.  M2-Planet doesn't have any
9-arg functions, so this restriction never bites.

## 3. Parameter lists and the spill

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


`cc-parse-param-list` and its inner loop handle:
- `()` — empty list (consume `)` and done).
- `(void)` — special-cased via a 2-token peek (lookahead for
  `void` then `)`).
- `T name, T name, ...` — the normal case.

Each parameter becomes an `sk-local` symbol in slots
`0 .. cc-fn-param-count-1`.  These slots are *reserved* by the
prologue's `sub rsp, FRAMESIZE` — `cc-emit-prologue 256` gives
32 slots' worth of space, which is comfortably more than 6
params plus any body locals.

```
   ,___,
   [o,o]   "every function gets 256 bytes whether it needs them
   (")_)    or not.  more than 32 locals overflows silently into
            the caller's frame.  M2-Planet never does that.
            other code might."
```

`cc-emit-spill-params` then emits the actual stores:
`[rbp - 8] := rdi`, `[rbp - 16] := rsi`, etc.  Each ladder rung
is gated on `cc-fn-param-count` so we only emit the spills we
need.  The encoders themselves are the ones from Ch 25 §4
(`cc-emit-store-local`, `cc-emit-store-local-from-rsi`, ...).

After spill, the parameters look identical to ordinary locals.
The rest of the compiler doesn't know the difference.

## 4. Function definitions

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
  \ Reset per-function label table and break/continue stacks.
  [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
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


`cc-parse-function` is the chapter's centrepiece.  The eleven-step
layout in the source comment is the complete flow:

1. Consume return type, NAME, `(`.
2. Capture the function's start vaddr and `cc-sym-add` it
   *before* parsing params/body.  This is what lets the body
   recursively call this function (recursion!).
3. Walk any prior prototype's fixup lists — both the
   call-site rel32 list (`cc-sym-extra-of`) and the forward-
   rvalue imm64 list (`cc-sym-extra2-of`) — and patch every
   site to the now-known vaddr.  Zero the heads so a repeated
   definition doesn't double-patch.
4. If the name is "main", record `cc-main-vaddr` for the
   entry stub.
5. Reset `cc-fn-local-count`, `cc-label-count`, and the
   break/continue heads.  `cc-scope-push` so locals declared
   in this function don't leak.
6. Parse the parameter list.
7. Consume `{`.
8. Emit the prologue with a 256-byte frame.
9. Spill the SYS-V argument registers into the parameter slots.
10. Loop: parse statements until `}`.
11. Emit the implicit return — `xor rax, rax ; epilogue` — in case
    the body fell off the end without a `return`, then
    `cc-scope-pop` to discard the function-body scope.

Step 3 is the deferred-resolution payoff.  Every forward call
that emitted a placeholder `E8 00 00 00 00` (Ch 26 §1) now
gets its rel32 filled in.  Every forward `movabs rdi, imm64 = 0`
that took a function's address as an rvalue (Ch 28 §4) gets
its imm64 filled in.  All before the prologue's first byte is
emitted.

This is the same emit, remember, patch pattern from Ch 11, now at
function-symbol scale.  The remembered offsets live in symbol-table
extra fields until the definition supplies the vaddr.

## 5. Enums and typedefs

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


`cc-parse-enum-def` and `cc-parse-typedef` register names in the
symbol table:
- Enumerators become `sk-enum` with `val` = the integer value.
- Typedef names become `sk-typedef` with `val` = the encoded
  type word.

The enum parser handles the auto-incrementing value (`cc-enum-
next-val`, restarting after `= N`) and a trailing comma before
`}`.  The typedef parser handles both plain aliases
(`typedef int int_ptr;`) and function-pointer typedefs
(`typedef void (*FUNCTION)(void);`).  Function-pointer typedefs
parse the return type and parameter parens but don't validate
signatures.

## 6. Top-level elision

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


The big comment block above explains the elision
problem: real C source has many top-level forms — forward
prototypes, file-scope vars, struct-pointer return types,
extern declarations — that aren't function definitions.  Each
must parse without crashing.

The three peek-functions are how:
- `cc-top-peek-is-fn-def?` scans forward through balanced parens
  until `;` or `{` at depth 0.  `{` first → function def.
- `cc-top-peek-has-paren?` returns -1 if at least one `(` was
  seen before the terminator.  Used to distinguish prototypes
  from globals.
- `cc-top-skip-to-semi` consumes everything through the next
  top-level `;`.

All three save and restore lexer state, so they're pure
predicates.

`cc-register-fn-proto` registers a function name with vaddr=0
(forward) so call sites can resolve.  The idempotency comment
explains why: real-world headers re-declare the same prototype
across translation units; concatenated into our monolith we
have to skip the re-add or call sites will resolve to a stale
`val=0` entry whose fixups are never patched.

The symbol table's newest-first rule is doing real work here — the
same newest-wins lookup the dictionary used in Ch 17 and the symbol
table in Ch 24, now deciding prototype-versus-definition.  A
function definition appends a newer `sk-func` row so later calls
resolve to the body, while earlier forward-call fixups remain
attached to the prototype row until the definition patches them.

`cc-parse-function-list` is the master loop.  For every
top-level construct it:

1. Skips storage qualifiers.
2. On `kw-struct`: peek 2 tokens — if `{` follows the tag, parse
   the definition; otherwise dispatch via the peek-functions to
   function def, proto, or global decl.
3. On `kw-enum` → `cc-parse-enum-def`.
4. On `kw-typedef` → `cc-parse-typedef`.
5. On other type keywords (int/char/void/long/short/etc.) →
   peek for fn def / proto / global.
6. On `tk-ident` (typedef-name used as a type) → same peek
   triad.

## 7. File-scope globals

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
\ Storage is allocated in cc-globals-buf (8 bytes per scalar, N*8 per array).
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
      cc-gdecl-n @ [lit] 8 * cc-globals-alloc
      cc-gdecl-slot !
      cc-parse-global-int-literal
      cc-gdecl-slot @ cc-globals-store-8le
      [lit] 59 cc-expect-punct-c                    \ ';'
    else,
      tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
        \ Bare uninitialized scalar.  Allocate the slot.
        cc-gdecl-n @ [lit] 8 * cc-globals-alloc cc-gdecl-slot !
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


`cc-parse-global-decl` handles three forms:
- `T name;` — uninitialised scalar.  Allocate 8 bytes in
  `cc-globals-buf`, register the symbol.
- `T name = N;` — scalar with integer initialiser.  Same
  allocation plus `cc-globals-store-8le` of the value (negative
  literals supported via the leading-`-` test).
- `T name[N];` — array.  Allocate `N*8` bytes.  Element count
  goes into `cc-sym-extra` for the array-decay path in Ch 28.

The base type is recorded with a distinguished `ty-char` for
`char` so the array-index path in Ch 28 §3 emits byte-stride
loads/stores for `char*`.

`cc-globals-buf` is one more instance of the *one buffer per
responsibility* pattern from Ch 21: file-scope data accumulates in
its own staging area, separate from `cc-out-buf`, until layout is
known.  `cc-finalize-globals` (called by the bootstrap driver in
Ch 32) appends `cc-globals-buf` to `cc-out-buf`, computes
`cc-globals-base-vaddr = cc-base-vaddr + cc-out-pos`, then walks
the `cc-gfixup-*` arrays patching every recorded `movabs rdi,
imm64` placeholder to its actual global vaddr.

## 8. The entry stub and the top-level driver

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


`cc-emit-entry-stub` emits 26 bytes at vaddr `0x400078` (right
after the ELF header + program header):

```
mov rdi, [rsp]       ; 4 bytes — argc, kernel-supplied
lea rsi, [rsp+8]     ; 5 bytes — argv
call <main>          ; 5 bytes — rel32 placeholder
mov rdi, rax         ; 3 bytes — main's return → exit code
mov rax, 60          ; 7 bytes — exit syscall
syscall              ; 2 bytes
```

The `call <main>` placeholder is patched by `cc-patch-call-main`
once `cc-main-vaddr` is known (after the function-list parse).

This is the final emit, remember, patch recurrence inside the
compiler proper: the entry stub exists before `main`, but its call
site is completed only after the whole top-level parse.

`cc-emit-shims` walks the eleven libc shim emitters from Ch 26
and registers each in the symbol table with its emitted vaddr.
After this, user code calling `putchar(c)` resolves to a normal
`call <vaddr>` to the shim.

`cc-emit-libc-typedefs` registers `FILE`, `uint8_t`, etc., as
`sk-typedef` entries so headers using them parse cleanly.

`cc-parse-program` is the orchestrator.  Six steps:

1. `cc-emit-entry-stub` — 26 bytes at the entry vaddr.
2. `cc-emit-shims` — emit the 11 libc shims and register them.
3. `cc-emit-external-protos` — register one external proto
   (`memset`) for tests.
4. `cc-emit-libc-typedefs` — register `FILE`, `uint8_t`, etc.
5. `cc-parse-function-list` — walk every top-level
   declaration in the input, generating code as it goes.
6. `cc-patch-call-main` — patch the entry stub's `call`
   placeholder to point at `main`.

Ch 32 will show how a host script wires `cc-parse-program`,
`cc-finalize-globals`, `cc-finalize-elf`, and `cc-write-output`
together.

## Try it

**Small check:** inspect one focused fixture below and trace its
calls, globals, or parameter slots through the chapter.

**Layer check:** there is no standalone root-level test for
`110-cc-decl.fth`; the focused `tests/cc/G*.c` programs are this
chapter's layer checks.

**Bootstrap relevance:** function calls, scopes, globals, and the
entry stub converge in the Stage-A gate.

```sh
./build.sh
tests/cc/stage-a-check.sh                    # end-to-end gate
```

For the small check, pick one of these focused fixtures:

`tests/cc/G3.c` exercises function definitions with multiple
params (`square`, `sum`); `G12.c` exercises function pointers;
`G14d.c` exercises globals accessed from a function (`bump()`
reading and writing `g_counter`).  The big M2-Planet monolith
exercises every path at once: the `stage-a-check.sh` driver
compiles M2-Planet via seed-forth plus all the `cc-*.fth` files
and diffs the resulting .M1 output against the GCC-built
reference.


## Exercises

1. **★★ Trace.** The forward-fixup walk in `cc-parse-function` step 3 handles
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
parameters (spilled from SysV registers into locals), scoped
declarations, file-scope globals, forward-call resolution, and the
26-byte entry stub at `0x400078` that sets up `argc`/`argv`, calls
`main`, and exits.  The output file is now a runnable ELF.

You can read `cc-parse-function` from name through epilogue,
explain why every function reserves the same 256-byte frame, and
walk how `cc-parse-program` loops file-scope decls until EOF.

Toward Stage-A: `/tmp/cc-out` is now a complete executable that can
itself be invoked.  The next chapter wires the Stage-A driver
around it to compare its `.M1` output against the reference.

## Takeaways

- Function parsing is where everything converges: declarations
  from Ch 29, statements from Ch 30, expressions from Chs 27–28,
  codegen from Chs 25–26.  Every concept earned in those
  chapters gets used here.
- The forward-fixup pattern that started in Ch 11's `if,` is
  now applied to *function vaddrs*: at the moment a function
  is defined, every call to it that emitted a placeholder gets
  its rel32 patched in one walk.  Emit, remember, patch has scaled
  from one inline branch slot to whole-program symbol resolution.
- The top-level driver is small — six lines — because every
  piece it orchestrates is already complete.  This is what
  literate construction looks like at the apex.

Next: Chapter 32 — End to End: Main and the Bootstrap Chain.
