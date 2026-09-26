# Chapter 27 — Expressions, Part 1: The Precedence Cascade

```text
Missing capability: the token stream cannot become expression machine code.
New pattern: a precedence cascade repeats one binary-fold codegen template at each operator level.
Artifact after this chapter: arithmetic, comparison, bitwise, and logical binary expression codegen.
Proof link: Stage-A binary expressions lower through one auditable cascade.
```

Chs 25–26 supplied the encoders; the parser now has to call them in
the right order.  Given `a*b + c << d == e & f | g && h || i`, the
compiler has to emit code that applies each operator in C's precedence order, and it
has no expression tree to lean on: the lexer hands over one token at
a time and the emitters write bytes immediately.  `100-cc-expr.fth`
(1478 lines total) solves this with a *precedence cascade*: plain
recursive descent with one word per precedence level.  Each word
asks the next-tighter level for its operands, then loops over its
own operators.  (This is not *precedence climbing*, which uses a
single function and a table of binding powers; see Appendix E.)

This chapter covers the scaffolding the whole file needs, a
one-token putback layer and forward references for the mutually
recursive parsers, and then the ten binary layers from
`cc-parse-mul` to `cc-parse-log-or`.  Eight of the ten follow one
five-step template: evaluate the left operand, push it, evaluate the
right, pop, apply the operator.  `&&` and `||` short-circuit, so
they emit jumps instead.  Ch 28 covers the levels above the cascade
(ternary, assignment, `cc-parse-expr`) and below it (unary, primary,
and the lvalue tracking that `cc-emit-materialize` reads).

---

## 1. The root block: how the file is assembled

```forth file=100-cc-expr.fth
<<expr-header>>
<<expr-putback>>
<<expr-fwd-refs>>
<<expr-lvalue>>
<<expr-struct-field>>
<<expr-array-index>>
<<expr-primary>>
<<expr-unary>>
<<expr-mul>>
<<expr-add>>
<<expr-shift>>
<<expr-rel>>
<<expr-eq>>
<<expr-bit>>
<<expr-log>>
<<expr-ternary>>
<<expr-assign>>
<<expr-top>>
```

The root block fixes the assembly order: header, putback layer,
forward references, the parsers in source order, and the top-level
driver.  Each `<<name>>` expands to a chunk defined in this chapter
or in Ch 28, and the result is byte-identical to the checked-in
`100-cc-expr.fth`.

## 2. File header and dependency comment

```forth chunk=expr-header
\ 100-cc-expr.fth — recursive-descent expression parser for the C subset.
\ Emits code that leaves the expression's value in rdi.  Uses 090-cc-emit.fth's
\ instruction encoders.
\
\ Expression grammar:
\   expr   := assign
\   assign := eq ('=' assign)?            \ right-associative; LHS must be ident
\   eq     := rel (('=='|'!=') rel)*
\   rel    := add (('<'|'<='|'>'|'>=') add)*
\   add    := mul (('+'|'-') mul)*
\   mul    := unary (('*'|'/'|'%') unary)*
\   unary  := ('*'|'&'|'-'|'!'|'~'|'++'|'--') unary | primary
\   primary:= NUMBER | IDENT | '(' expr ')'
\
\ The lexer (050-cc-lex.fth) reads one token at a time with no built-in peek.
\ We add a one-token putback layer on top of cc-next-token via the
\ cc-tok-pending flag: when a parser has consumed one token too many it
\ calls cc-putback-token; the next cc-next-token-keep returns the same
\ tok-* state without advancing.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 090-cc-emit.fth.

```

The grammar in the comment is a simplified version.  The file also
handles shifts, bitwise and logical operators, the ternary, and the
postfix operators (`[]`, `.`, `->`, `()`, `++`, `--`).  Every
binary production has the same shape: parse an operand at the
next-tighter level, then loop over this level's operators.

## 3. The one-token putback layer

```forth chunk=expr-putback
\ ===========================================================================
\ One-token putback wrapper
\ ===========================================================================

variable cc-tok-pending                           \ -1 = a token is queued

\ cc-next-token-keep ( -- )  Advance to the next token unless one is pending.
: cc-next-token-keep
  cc-tok-pending @ if,
    [lit] 0 cc-tok-pending !
  else,
    cc-next-token
  then, ;

\ cc-putback-token ( -- )  Mark the current tok-* as still-pending so the
\ next cc-next-token-keep returns it without advancing.
: cc-putback-token
  [lit] 0 0= cc-tok-pending ! ;

```

The lexer (Ch 23) returns one token at a time.  Its only lookahead
is `cc-peek-char-2`, one *byte* of character lookahead.  A cascade
always reads one operator too many.  After folding the two `*`s in
`a * b * c + d`, `cc-parse-mul` reads the `+`, finds it isn't a
multiplicative operator, and has to hand it back so the next-looser
layer (`add`) can see it.

`cc-tok-pending` is that hand-back.  `cc-putback-token` sets it, and
the next `cc-next-token-keep` clears it *without* advancing the
lexer, so `tok-kind`, `tok-num`, and `tok-str-*` still describe the
same token.  When the flag is clear, `cc-next-token-keep` calls
`cc-next-token` as normal.  Every binary layer ends with
`cc-putback-token`.

## 4. Forward references for mutual recursion

```forth chunk=expr-fwd-refs
\ ===========================================================================
\ Forward reference for recursive expr (used by '(' expr ')' in primary).
\ ===========================================================================

variable cc-parse-expr-vec                        \ xt of top-level expr parser

: cc-parse-expr-tramp
  cc-parse-expr-vec @ execute ;

\ cc-parse-assign is defined AFTER cc-parse-ternary (mutual recursion:
\ ternary's arms parse via cc-parse-assign for right-associativity).  Route
\ ternary's recursive calls through this vec so the binding resolves at
\ ternary-execution time, not at compile time.
variable cc-parse-assign-vec                      \ xt of cc-parse-assign

: cc-parse-assign-tramp
  cc-parse-assign-vec @ execute ;

\ ===========================================================================
\ Forward reference for function-call codegen (defined in 110-cc-decl.fth so it
\ can use cc-base-vaddr from 080-cc-elf.fth).  cc-parse-primary calls into
\ cc-parse-call-tramp once it has spotted `IDENT (`; the callee consumes the
\ '(' (already peeked but not consumed), parses comma-separated arg
\ expressions, emits the SYS-V argument-passing prologue and the call.
\ ===========================================================================

variable cc-parse-call-vec                        \ xt of cc-parse-call

\ cc-parse-call-tramp ( id -- )  Stack: function symbol-id; consumes it.
: cc-parse-call-tramp
  cc-parse-call-vec @ execute ;

```

The grammar is mutually recursive: `primary` parses `'(' expr ')'`,
which re-enters the whole grammar.  Forth's `:` can't refer to a
word that doesn't exist yet, so the file declares three vec
variables, each with a trampoline that fetches the variable and
executes it.

`cc-parse-expr-vec` and `cc-parse-assign-vec` are filled at the end
of the file (Ch 28's `expr-top` chunk).  `cc-parse-call-vec` is
filled in `110-cc-decl.fth` (Ch 31), because call codegen needs
`cc-emit-call-vaddr` and the function-symbol machinery, which load
after this file.

Part III uses this pattern wherever load order and call order
disagree: declare the variable, define the trampoline, and store
the real word's execution token once it exists.

## 5. The binary-operator template: `cc-parse-mul`

```forth chunk=expr-mul
\ ===========================================================================
\ cc-parse-mul: unary (('*'|'/'|'%') unary)*
\ ===========================================================================

\ cc-mul-op? ( -- f )  After cc-next-token-keep, returns -1 if the current
\ token is one of *, /, %.
: cc-mul-op?
  tok-kind @ tk-punct = if,
    tok-num @ [lit] 42 =
    tok-num @ [lit] 47 = or
    tok-num @ [lit] 37 = or
  else,
    [lit] 0
  then, ;

\ The op byte is kept on the data stack across the recursive call to
\ cc-parse-primary so nested operator parsing (via parenthesised exprs)
\ can't clobber a shared global.  cc-parse-primary preserves the data
\ stack (0-in / 0-out), so the op survives across the call.

: cc-parse-mul
  cc-parse-unary                                  \ rdi = first operand (may be pending-deref)
  begin,
    cc-next-token-keep
    cc-mul-op?
  while,
    cc-emit-materialize                           \ left must be a value before push
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi                              \ save left
    cc-parse-unary                                \ rdi = right (may be pending-deref)
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi                           \ rcx = right
    cc-emit-pop-rdi                               \ rdi = left
    r>                                            ( op )
    dup [lit] 42 = if,
      drop cc-emit-imul-rdi-rcx
    else,
      [lit] 47 = if,
        cc-emit-idiv-quotient
      else,
        cc-emit-idiv-remainder
      then,
    then,
    cc-mark-not-lvalue                            \ result is not an lvalue
  repeat,
  cc-putback-token ;                              \ we read one too many

```

Every other binary layer is a copy of this word with different
operators, so it is worth reading slowly.

1. **Parse the left operand** at the next-tighter level
   (`cc-parse-unary` for `mul`).  `rdi` now holds the left value,
   or, for a pending dereference, an *address* that
   `cc-emit-materialize` must load.
2. **Loop while the next token is one of our operators.**
   `cc-next-token-keep` reads a token and `cc-mul-op?` tests it
   against `*`, `/`, and `%`.
3. **Inside the loop:** materialize the left value, move the
   operator's code to the return stack, push `rdi`, parse and
   materialize the right operand, `mov rcx, rdi` (right into the
   temp), `pop rdi` (left into the result register), fetch the
   operator code back, and dispatch to its encoder.
4. **After the loop** the last token read isn't ours, so
   `cc-putback-token` returns it to the caller.

The operator codes are the lexer's punct codes from Ch 23, which
for single characters are ASCII: `*` = 42, `/` = 47, `%` = 37.

The operator code rides on the return stack because the recursive
`cc-parse-unary` call can parse a parenthesised expression with
operators of its own, and those need the data stack for their own
intermediate values.

The source comment above `cc-parse-mul` is out of date on this
point.  It says the op byte stays on the *data* stack across a call
to `cc-parse-primary`.  The code moves it to the return stack with
`tok-num @ >r`, and the call is to `cc-parse-unary`.

## 6. `cc-parse-add`: just like `mul`, looser

```forth chunk=expr-add
\ ===========================================================================
\ cc-parse-add: mul (('+'|'-') mul)*
\ ===========================================================================

: cc-add-op?
  tok-kind @ tk-punct = if,
    tok-num @ [lit] 43 =
    tok-num @ [lit] 45 = or
  else,
    [lit] 0
  then, ;

: cc-parse-add
  cc-parse-mul
  begin,
    cc-next-token-keep
    cc-add-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-mul
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    [lit] 43 = if,
      cc-emit-add-rdi-rcx
    else,
      cc-emit-sub-rdi-rcx
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

```

The shape is identical to `cc-parse-mul` with three substitutions:
the operand parser is `cc-parse-mul`, the operator test matches `+`
and `-`, and the dispatch picks `cc-emit-add-rdi-rcx` or
`cc-emit-sub-rdi-rcx`.

Each layer calls the one below it, so a bare number passes through
fifteen parser words (`expr` → `assign` → `ternary` → `log-or` →
`log-and` → `bit-or` → `bit-xor` → `bit-and` → `eq` → `rel` →
`shift` → `add` → `mul` → `unary` → `primary`) before reaching the
literal.  Each layer needs one token of lookahead, allocates
nothing, and costs one call.

## 7. Shifts: between relational and additive

```forth chunk=expr-shift
\ ===========================================================================
\ cc-parse-shift: add (('<<' | '>>') add)*
\ ===========================================================================
\ C precedence: shift is BETWEEN relational and additive (binds tighter than
\ relational, looser than additive).  Variable-count shifts use rcx (CL).

: cc-shift-op?
  tok-kind @ tk-punct = if,
    tok-num @ pt-shl =
    tok-num @ pt-shr = or
  else,
    [lit] 0
  then, ;

: cc-parse-shift
  cc-parse-add
  begin,
    cc-next-token-keep
    cc-shift-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-add
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    \ rdi=left, rcx=right (low byte cl = count).
    pt-shl = if,
      cc-emit-shl-rdi-cl
    else,
      cc-emit-sar-rdi-cl                          \ '>>' is arithmetic (signed)
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

```

C puts shifts between additive and relational operators, so
`a + b << c` parses as `(a + b) << c` and `a << b < c` as
`(a << b) < c`.  The call chain encodes that: `cc-parse-shift` uses
`cc-parse-add` for its operands, and `cc-parse-rel` (next) uses
`cc-parse-shift`.

`>>` is an arithmetic (sign-extending) shift, because the only
integer type is signed `int`.  An unsigned `>>` would need a logical
`cc-emit-shr-rdi-cl`, which `090-cc-emit.fth` doesn't define because
nothing calls it.

## 8. Relational and equality

```forth chunk=expr-rel
\ ===========================================================================
\ cc-parse-rel: shift (('<' | '<=' | '>' | '>=') shift)*
\ ===========================================================================
\ Punct codes: '<'=60, '>'=62, pt-le=258, pt-ge=259.

: cc-rel-op?
  tok-kind @ tk-punct = if,
    tok-num @ [lit]  60 =
    tok-num @ [lit]  62 = or
    tok-num @ pt-le      = or
    tok-num @ pt-ge      = or
  else,
    [lit] 0
  then, ;

: cc-parse-rel
  cc-parse-shift
  begin,
    cc-next-token-keep
    cc-rel-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-shift
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    \ Now rdi=left, rcx=right.  Dispatch on op code.
    dup [lit] 60 = if,
      drop cc-emit-cmp-lt
    else,
      dup [lit] 62 = if,
        drop cc-emit-cmp-gt
      else,
        pt-le = if,
          cc-emit-cmp-le
        else,
          cc-emit-cmp-ge
        then,
      then,
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

```

`cc-parse-eq` is the same template one level looser, over `==` and
`!=`:

```forth chunk=expr-eq
\ ===========================================================================
\ cc-parse-eq: rel (('==' | '!=') rel)*
\ ===========================================================================

: cc-eq-op?
  tok-kind @ tk-punct = if,
    tok-num @ pt-eq-eq   =
    tok-num @ pt-bang-eq = or
  else,
    [lit] 0
  then, ;

: cc-parse-eq
  cc-parse-rel
  begin,
    cc-next-token-keep
    cc-eq-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-rel
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    pt-eq-eq = if,
      cc-emit-cmp-eq
    else,
      cc-emit-cmp-ne
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

```

`cc-parse-rel` and `cc-parse-eq` use the `cmp-set` emitters from
Ch 25 §6, which leave exactly 0 or 1 in `rdi`.  The logical
operators below rely on that: `1 && 2` must produce 1, not 2.

## 9. The bitwise trio

```forth chunk=expr-bit
\ ===========================================================================
\ Bitwise AND / XOR / OR — three layers, each above the next.
\ ===========================================================================
\ Precedence (high to low among these):
\   eq  >  bit-and (&)  >  bit-xor (^)  >  bit-or (|)
\ So cc-parse-bit-and folds over cc-parse-eq; cc-parse-bit-xor over bit-and;
\ cc-parse-bit-or over bit-xor.  Each handles a single punct char.
\
\ Note that '&' here is the BINARY (infix) bitwise-and.  The unary '&'
\ (address-of) is handled in cc-parse-unary at operand position — operator
\ position vs operand position disambiguates the two.

: cc-parse-bit-and
  cc-parse-eq
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 38 = and
  while,
    cc-emit-materialize
    cc-emit-push-rdi
    cc-parse-eq
    cc-emit-materialize
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    cc-emit-and-rdi-rcx
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

: cc-parse-bit-xor
  cc-parse-bit-and
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 94 = and
  while,
    cc-emit-materialize
    cc-emit-push-rdi
    cc-parse-bit-and
    cc-emit-materialize
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    cc-emit-xor-rdi-rcx
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

: cc-parse-bit-or
  cc-parse-bit-xor
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 124 = and
  while,
    cc-emit-materialize
    cc-emit-push-rdi
    cc-parse-bit-xor
    cc-emit-materialize
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    cc-emit-or-rdi-rcx
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

```

Three layers, three operators, one shape.  Each layer has a single
operator, so there is no dispatch on the operator code and nothing
to keep on the return stack.

C's `&` is overloaded.  Where an operand is expected it is unary
address-of; between two operands it is binary bitwise-and.  The
grammar separates the two by position: `cc-parse-unary` (Ch 28)
sees `&` only at operand position, and `cc-parse-bit-and` sees it
only at operator position, so they never compete for the same
token.

## 10. Short-circuit `&&` and `||`

```forth chunk=expr-log
\ ===========================================================================
\ Short-circuit logical && and || — produce 1 or 0 (not the operand).
\ ===========================================================================
\ For `a && b`:
\   eval a; if zero, skip b and produce 0; else eval b; if zero, produce 0;
\   else produce 1.
\
\ Codegen sketch (with three rel32 fixups stashed on rstack):
\   <eval a>
\   test rdi,rdi
\   jz   .false_LHS
\   <eval b>
\   test rdi,rdi
\   jz   .false_RHS
\   mov rdi, 1
\   jmp  .end
\ .false_LHS:
\ .false_RHS:
\   mov rdi, 0
\ .end:
\
\ We push the three fixups onto rstack so the data stack stays clear for the
\ nested parse calls and any pending operator codes.

: cc-parse-log-and
  cc-parse-bit-or
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ pt-and-and = and
  while,
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jz-rel32-placeholder >r               \ R: fixup-false-LHS
    cc-parse-bit-or
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jz-rel32-placeholder >r               \ R: f-LHS f-RHS
    [lit] 1 cc-emit-mov-rdi-imm32
    cc-emit-jmp-rel32-placeholder >r              \ R: f-LHS f-RHS f-end
    \ False-target lands here for both fixups.
    r> r>                                         ( f-end f-RHS ; R: f-LHS )
    cc-patch-rel32-to-here                        \ patch f-RHS
    r>                                            ( f-end f-LHS )
    cc-patch-rel32-to-here                        \ patch f-LHS
    [lit] 0 cc-emit-mov-rdi-imm32
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

: cc-parse-log-or
  cc-parse-log-and
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ pt-or-or = and
  while,
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jnz-rel32-placeholder >r              \ R: fixup-true-LHS
    cc-parse-log-and
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jnz-rel32-placeholder >r              \ R: t-LHS t-RHS
    [lit] 0 cc-emit-mov-rdi-imm32
    cc-emit-jmp-rel32-placeholder >r              \ R: t-LHS t-RHS f-end
    \ True-target lands here for both fixups.
    r> r>                                         ( f-end t-RHS ; R: t-LHS )
    cc-patch-rel32-to-here
    r>                                            ( f-end t-LHS )
    cc-patch-rel32-to-here
    [lit] 1 cc-emit-mov-rdi-imm32
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

```

`&&` and `||` can't use the template, because the right operand
must not run at all when the left one already decides the result.

The code follows the sketch in the comment.  Each operand is tested
and, if it decides the result early, jumps to a shared join point.
The path where neither does sets `rdi` to 1 and jumps to the end.
The join point sets `rdi` to 0, and the end label follows.

That takes three rel32 fixups: the early exit after the left
operand, the early exit after the right, and the jump to the end.
Each is pushed to the return stack as it is emitted, using the
emit-remember-patch pattern from Ch 11.

The patching code pops them in reverse.  The top of the return
stack is `f-end`, then `f-RHS`, then `f-LHS`.  Two `r>`s put
`( f-end f-RHS )` on the data stack.  The code patches `f-RHS` to
the current `cc-out-pos` (the join point), pops and patches
`f-LHS` to the same place, emits `mov rdi, 0`, and finally patches
`f-end`.

`||` is the mirror image: it jumps on non-zero, the path where
neither operand is true produces 0, and the join point produces 1.

## 11. The cascade in motion

Here is `a + b * c < 5` passing through the layers:

1. `cc-parse-rel` is the outer call (`<` is a relational op).
2. It calls `cc-parse-shift`, which calls `cc-parse-add`, which
   calls `cc-parse-mul`, which calls `cc-parse-unary`, which
   bottoms out in `cc-parse-primary`'s `tk-ident` branch and
   emits `mov rdi, [rbp - 8]` (load `a`).
3. `cc-parse-mul` reads the next token, `+`.  Not a mul-op;
   putback, return.
4. `cc-parse-add` reads `+`.  Match.  Materialize, stash `+`,
   push `rdi`, call `cc-parse-mul` again.
5. The inner `cc-parse-mul` calls `cc-parse-unary` → `b` →
   load.  Then it reads `*`, matches, stashes, pushes, and calls
   `cc-parse-unary` → `c` → load.  Materialize, `mov rcx, rdi`,
   `pop rdi`, dispatch `*` → `imul rdi, rcx`.  It reads the next
   token, `<`.  Not a mul-op; putback, return.
6. Back in `cc-parse-add`: `mov rcx, rdi`, `pop rdi`, dispatch
   `+` → `add rdi, rcx`.  Reads `<`.  Not an add-op; putback,
   return.
7. `cc-parse-shift` reads `<`.  Not a shift-op; putback, return.
8. `cc-parse-rel` reads `<`.  Match.  Materialize, stash `<`,
   push, and call `cc-parse-shift` again, which bottoms out at `5`.
9. `cc-parse-rel`: `mov rcx, rdi`, `pop rdi`, dispatch `<` →
   `cmp-lt`, which leaves a clean 0/1 in `rdi`.

Nothing in this trace consults a precedence table.  The order in
which the layers call each other is the table.

**tri.c at this stage.**  Line 16 of tri.c computes
`w[r] = 1 + r * 2`.  Compile tri.c with Ch 21's command, which
leaves the binary in `/tmp/cc-out`, and disassemble the right-hand
side:

```sh
objdump -D -b binary -m i386:x86-64 -M intel \
    --start-address=0x365 --stop-address=0x388 /tmp/cc-out | grep '^ '
```

```
 365:   48 c7 c7 01 00 00 00    mov    rdi,0x1
 36c:   57                      push   rdi
 36d:   48 8b 7d d8             mov    rdi,QWORD PTR [rbp-0x28]
 371:   57                      push   rdi
 372:   48 c7 c7 02 00 00 00    mov    rdi,0x2
 379:   48 89 f9                mov    rcx,rdi
 37c:   5f                      pop    rdi
 37d:   48 0f af f9             imul   rdi,rcx
 381:   48 89 f9                mov    rcx,rdi
 384:   5f                      pop    rdi
 385:   48 01 cf                add    rdi,rcx
```

The `1` is loaded first and parked on the machine stack at 0x36c.
Then `cc-parse-add` asks `cc-parse-mul` for its right operand, and
all of `r * 2` (`r` is `[rbp-0x28]`) is emitted inside that call,
ending in the `imul` at 0x37d.  Only then does the `add` run.  The
`*` binds tighter because its code was written inside the `+`'s
operand.

## Try it

**Small check:** read one focused expression fixture and trace it
through the precedence cascade.  The fixtures under `tests/cc/` start
at `G0.c` (return 42) and walk up through `G14*.c`.  `G1.c` exercises
basic arithmetic precedence (`a + b * 2 - 1`); `G11.c` covers shifts,
bitwise operators, `&&`/`||`, the ternary, postfix `++`, and compound
assignment in a single fixture.

**Layer check:** `./test.sh` exercises the expression parser through
the focused C fixtures.

```sh
./build.sh
./test.sh                              # exercises the expression parser
```

**Bootstrap relevance:** the end-to-end gate confirms that the same
expression paths emit byte-identical `.M1` for M2-Planet.

```sh
tests/cc/stage-a-check.sh
```

## Exercises

1. **★★ Trace.** Trace `cc-parse-add` parsing `a - b - c`.  Where does
   left-associativity come from?

2. **★★ Trace.** The shift cascade `cc-parse-shift` handles `<<` and `>>` as
   binary operators.  Their compound-assign counterparts `<<=`
   and `>>=` already live in `cc-assign-op?` (Ch 28).  Why don't
   the compound forms live in this file alongside the binary
   forms?  (Hint: where does the parse tree branch into
   right-associative territory?)

3. **★★★ Modify.** The short-circuit `&&` produces `1` on success.  Modify it
   to produce the *right operand's value* instead.  This is no
   longer C (the standard requires `&&` to yield exactly `0` or
   `1`), but it is what some other languages (Lua, JavaScript)
   do.  How many bytes does that save, and which M2-Planet idiom
   would break?

4. **★★ Trace.** The order of the three return-stack pushes in
   `cc-parse-log-and` matters: get it wrong and the wrong fixup is
   patched first.  Sketch a diagram showing each `>r`/`r>` and
   verify the comment's `R:` annotations match the code.

5. **★★★ Extend.** Add an `>>>` unsigned-right-shift operator (it's not in C,
   but imagine it).  What would it touch in the lexer (Ch 23),
   the instruction encoders (Ch 25), and this file?

## After this chapter

The compiler can lower binary expressions: arithmetic, comparison,
bitwise, and logical operators at every C precedence level, eight
of them through one five-step fold template (left, push, right,
pop, op) and two through short-circuit jumps.

You can read `cc-parse-mul`/`add`/`rel`/`eq`/`bit`/`log`, explain
the precedence cascade, and predict what code an expression like
`a + b * c > d` will emit without running it.

What the cascade cannot do yet is write.  In `w[r] = 1 + r * 2`,
everything above computed the right side; the left side needs the
*address* of `w[r]`, and the parser does not know it wants an
address until it reaches the `=`.  Ch 28 solves that.

## Takeaways

- Each binary precedence level is one word that parses its operands
  at the next-tighter level, so the order of the calls is the
  precedence table.
- The operator code travels on the return stack, which leaves the
  data stack free for a parenthesised expression parsed inside an
  operand.
- `&&` and `||` replace the fold template with conditional jumps
  whose three rel32 fixups wait on the return stack and are patched
  in reverse order.

Next: Chapter 28 — Expressions, Part 2: Primary, Unary, Assignment.
