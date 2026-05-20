# Chapter 27 — Expressions, Part 1: Precedence Climbing

This chapter opens `100-cc-expr.fth` (1447 lines total) and covers
its binary-operator cascade plus the scaffolding the rest of the
file needs.  The scaffolding is a one-token putback layer
(`cc-tok-pending`, `cc-next-token-keep`, `cc-putback-token`) so the
parser can peek past a fold boundary without re-lexing, plus
forward-reference vecs for the mutually recursive parsers.  The
cascade itself runs through ten precedence layers from
`cc-parse-mul` to `cc-parse-log-or`, every one a textbook
precedence-climbing loop emitting the same five-step codegen
template (eval left, push, eval right, `pop rdi`, apply op).

By the end you'll be able to read each precedence layer, follow the
op-byte threaded through the return stack so the data stack stays
free for recursive operand parsing, and predict the codegen for a
mixed expression like `a*b + c << d == e & f | g && h || i` by
walking the layers top-down.  Ch 28 picks up the right-associative
tail (`cc-parse-ternary`, `cc-parse-assign`, `cc-parse-expr`) and
the recursive-descent floor (`cc-parse-unary`, `cc-parse-primary`,
plus the lvalue-tracking globals that `cc-emit-materialize` reads).

---

The lexer hands us tokens; the codegen hands us instruction
encoders; this file is the bridge.  Given a token stream
representing a C expression, it emits x86-64 machine code that
leaves the expression's value in `rdi`.

The interesting question is *how the precedence works*.  C has
fifteen levels of operator precedence; a naive recursive-descent
parser would need fifteen mutually recursive functions.  This
file uses *precedence climbing*: each operator level is one
function that calls the next-tighter level, then loops on its
own operators.

Ch 27 covers the binary cascade — ten layers from `mul` through
`log-or` (mul, add, shift, rel, eq, bit-and, bit-xor, bit-or,
log-and, log-or).  Ch 28 covers everything above and below: the
top-level driver, the right-associative `=` and `?:`, the unary
operators, and `primary` itself (where actual identifiers,
literals, and calls live).

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

That single root-block defines the assembly order: header,
putback layer, forward references, all the parsers in source
order, top-level driver.  Each `<<name>>` expands to a chunk
defined either in this chapter or Ch 28.  The tangler resolves
the references and the result is byte-identical to the
checked-in `100-cc-expr.fth`.

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
\   mul    := primary (('*'|'/'|'%') primary)*
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

The grammar comment is the file's contract.  The expression
grammar shown is the *simplified* set: the actual file extends
it with shift, bitwise, logical, ternary, and the postfix
operators (`[]`, `.`, `->`, `()`, `++`, `--`).  The shape is
the same: every production parses an operand at the next-tighter
precedence, then loops on its own operator set.

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

The lexer (Ch 23) returns one token at a time; it has no
built-in lookahead beyond `cc-peek-char-2` (one *byte* of
character lookahead).  A precedence-climbing parser routinely
reads one operator too many — at the end of `a * b * c`, after
folding two `*` operations, the parser reads what *would* have
been a third operator and discovers it's a `+`.  It needs to
"un-read" that `+` so the next-looser layer (`add`) can see it.

`cc-tok-pending` is a one-token putback flag.  When set,
`cc-next-token-keep` *doesn't* advance the lexer — the existing
`tok-kind`/`tok-num`/`tok-str-*` state is preserved.  When
cleared, it calls `cc-next-token` as normal.

`cc-putback-token` is what every binary-op fold ends with:
"the token I just read isn't mine; the caller can have it back."
The next call to `cc-next-token-keep` sees the same token state.

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

The expression grammar is *mutually recursive*: `primary` parses
`'(' expr ')'` which recurses into the entire grammar.  Forth's
`:` can't forward-reference a word that doesn't yet exist, so we
declare three vec variables and three tiny trampolines that
fetch and execute the variable's contents.

`cc-parse-expr-vec` will be set to `cc-parse-expr` at the end of
the file (Ch 28's `expr-top` chunk).
`cc-parse-assign-vec` is set similarly.
`cc-parse-call-vec` is set in `110-cc-decl.fth` (Ch 31), where
the call-codegen lives — it needs `cc-base-vaddr` from
`080-cc-elf.fth`, which is loaded *after* `100-cc-expr.fth`.

This trampoline pattern recurs throughout Part III.  It's the
seed Forth's solution to load-order constraints: declare the
variable up front, define the trampoline, and patch the variable
once the real word exists.

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

This is the template every binary-op layer follows.  Read it
once carefully — every other binary parser is the same shape.

1. **Parse the left operand** at the next-tighter precedence
   (`cc-parse-unary` for `mul`).  After this, `rdi` holds the
   left value — though if it's a pending dereference, `rdi`
   holds an *address* that needs `cc-emit-materialize` to
   become a value.
2. **Loop while the next token is one of our operators.**
   `cc-next-token-keep` reads a token; `cc-mul-op?` tests it
   against `*`, `/`, `%`.  If it isn't, we fall out of the loop.
3. **Inside the loop:** materialize left (so it's an actual
   value), stash the op byte on the return stack, push `rdi` (the
   left operand), parse the right operand, materialize that,
   `mov rcx, rdi` (right → temp), `pop rdi` (left → result reg),
   pop the op byte, dispatch to the right encoder.
4. **After the loop ends** (we read a token that wasn't ours),
   `cc-putback-token` so the calling layer sees it.

The opcode bytes are the lexer's punct codes from Ch 23: `*` =
42 (ASCII), `/` = 47, `%` = 37.

The op byte travels through the return stack rather than the
data stack because the recursive `cc-parse-unary` call might
itself parse a parenthesised expression containing further
operators — and *those* operators want the data stack free for
their own intermediate values.  Using the return stack is the
release valve.

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

Identical shape to `cc-parse-mul` with three substitutions:
the inner call goes to `cc-parse-mul`, the operator test
matches `+` / `-`, and the dispatch goes to
`cc-emit-add-rdi-rcx` / `cc-emit-sub-rdi-rcx`.

The precedence chain pulls itself up: `add` calls `mul`, which
calls `unary`, which calls `primary`.  A bare number flows
through five layers (`expr` → `assign` → ... → `bit-or` → ... →
`add` → `mul` → `unary` → `primary`) before hitting an actual
literal.  Each layer is a one-token-lookahead with no
allocations and no recursion overhead beyond the call stack
itself.

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

C's precedence table puts shifts (`<<`, `>>`) *between*
additive and relational — `a + b << c` parses as `(a + b) << c`,
and `a << b < c` parses as `(a << b) < c`.  That layering is
implicit in the call chain: `cc-parse-shift` calls
`cc-parse-add` as its inner parser, and `cc-parse-rel` (next)
calls `cc-parse-shift`.

`>>` is arithmetic (sign-extending) right shift here, because
the only integer type is signed `int`.  An unsigned `>>` would
use `cc-emit-shr-rdi-cl` (logical right shift) — which doesn't
yet exist in `090-cc-emit.fth` because nobody calls it.

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

`cc-parse-rel` and `cc-parse-eq` use Ch 25 §6's `cmp-set`
emitters which produce a clean 0/1 result in `rdi`.  That 0/1
invariant matters for the logical operators below: `1 && 2`
needs to produce 1, not 2.

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

Three layers, three operators, identical shape.  Notice that
each is even shorter than the previous parsers because there's
only one operator per layer — no dispatch on the op code, no
return-stack stash.

The disambiguation comment is worth a moment.  C's `&`
overloads: at the start of an expression (where an operand is
expected) it's the *unary* address-of operator; between two
operands it's the *binary* bitwise-and.  This compiler resolves
the ambiguity *structurally*: `cc-parse-unary` (Ch 28) handles
`&` at operand position, while `cc-parse-bit-and` handles it at
operator position.  Each is called from a different point in the
grammar, so they can't collide.

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

`&&` and `||` break the binary-op template because they're
*short-circuit* — the right-hand side might not evaluate at all
if the left already decides the result.

The codegen mirrors a hand-written compiler's approach: emit
conditional jumps to a "false" join point if the operand
decides early, emit `mov rdi, 1` on the all-true path, an
unconditional jump to "end", a join point, `mov rdi, 0`, and
the "end" label.

Three rel32 fixups need to be tracked: the early-exit jump for
the LHS, the early-exit jump for the RHS, and the "end" jump
from the all-true path.  Each is pushed onto the return stack as
it's emitted; popped and patched as we reach its target.

The structure `r> r> ... r>` at the patching site reverses the
push order: top of return stack is `f-end`, second is `f-RHS`,
third is `f-LHS`.  Two pops give `(f-end, f-RHS)` on the data
stack; we patch `f-RHS` (current `cc-out-pos` is the join), pop
`f-LHS`, patch it too, emit `mov rdi, 0`, then finally patch
`f-end`.  The Forth idiom for stack juggling is dense but
straightforward once you decode the rotation.

`||` is the mirror image: jump-if-non-zero past the right
operand, emit `mov rdi, 0` on the all-false path, all-true path
falls into `mov rdi, 1`.

## 11. The cascade in motion

To see all of this fit together, trace what happens for
`a + b * c < 5`:

1. `cc-parse-rel` is the outer call (`<` is a relational op).
2. It calls `cc-parse-shift`, which calls `cc-parse-add`, which
   calls `cc-parse-mul`, which calls `cc-parse-unary`, which
   bottoms out in `cc-parse-primary`'s `tk-ident` branch and
   emits `mov rdi, [rbp - 8]` (load `a`).
3. `cc-parse-mul` reads the next token — `+`.  Not a mul-op;
   putback, return.
4. `cc-parse-add` reads `+`.  Match.  Materialize, stash `+`,
   push `rdi`, call `cc-parse-mul` again.
5. The inner `cc-parse-mul` calls `cc-parse-unary` → `b` →
   load.  Then reads `*`, matches, stashes, pushes, calls
   `cc-parse-unary` → `c` → load.  Materialize, `mov rcx, rdi`,
   `pop rdi`, dispatch `*` → `imul rdi, rcx`.  Reads next token
   — `<`.  Not a mul-op; putback, return.
6. Back in `cc-parse-add`: `mov rcx, rdi`, `pop rdi`, dispatch
   `+` → `add rdi, rcx`.  Reads `<`.  Not an add-op; putback,
   return.
7. `cc-parse-shift` reads `<`.  Not a shift-op; putback, return.
8. `cc-parse-rel` reads `<`.  Match.  Materialize, stash `<`,
   push, call `cc-parse-shift` again — which bottoms out at `5`.
9. `cc-parse-rel`: `mov rcx, rdi`, `pop rdi`, dispatch `<` →
   `cmp-lt`, which leaves a clean 0/1 in `rdi`.

The whole expression has cost six layers of dispatch and one
materialise per binary op.  The depth of the cascade *is* the
precedence table.

## Try it

```sh
./build.sh
./test.sh                              # exercises the expression parser
tests/cc/stage-a-check.sh              # end-to-end bootstrap gate
```

The unit tests under `tests/cc/` start at `G0.c` (return 42) and
walk up through `G14*.c`.  `G1.c` exercises basic arithmetic
precedence (`a + b * 2 - 1`); `G11.c` is the full sweep — shifts,
bitwise, `&&`/`||`, ternary, postfix `++`, and compound assignment
— in a single fixture.

## Exercises

1. **★★** Trace `cc-parse-add` parsing `a - b - c`.  Where does
   left-associativity come from?

2. **★★** The shift cascade `cc-parse-shift` handles `<<` and `>>` as
   binary operators.  Their compound-assign counterparts `<<=`
   and `>>=` already live in `cc-assign-op?` (Ch 28).  Why don't
   the compound forms live in this file alongside the binary
   forms?  (Hint: where does the parse tree branch into
   right-associative territory?)

3. **★★★** The short-circuit `&&` produces `1` on success.  Modify it
   to produce the *right operand's value* instead (the C
   standard leaves this implementation-defined — many compilers
   don't canonicalise to 0/1).  How many bytes does that save?

4. **★★** The three return-stack pushes in `cc-parse-log-and` are
   delicate — get the order wrong and the wrong fixup gets
   patched first.  Sketch a diagram showing each `>r`/`r>` and
   verify the comment's `R:` annotations match the code.

5. **★★★** Add an `>>>` unsigned-right-shift operator (it's not in C,
   but imagine it).  What would it touch in the lexer (Ch 23),
   the instruction encoders (Ch 25), and this file?

## Takeaways

- Every binary-op layer is one function with the same five-step
  template: parse-left, push, parse-right, mov rcx + pop, apply
  op.  The depth of the call chain *is* the precedence table.
- The op byte travels through the return stack so nested
  parenthesised expressions in operands can reuse the data
  stack freely.
- Short-circuit `&&`/`||` break the template because they need
  conditional branches and rel32 fixups; the fixups travel on
  the return stack too, in carefully tracked LIFO order.

Next: Chapter 28 — Expressions, Part 2: Primary, Unary,
Assignment, and the Top-Level Driver.
