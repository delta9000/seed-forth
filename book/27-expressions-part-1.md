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
(1435 lines total) solves this with a *precedence cascade*: plain
recursive descent with one word per precedence level.  Each word
asks the next-tighter level for its operands, then loops over its
own operators.  (This is not *precedence climbing*, which uses a
single function and a table of binding powers; see Appendix E.)

This chapter covers the scaffolding the whole file needs, forward
references for the mutually recursive parsers, and then the ten binary layers from
`cc-parse-mul` to `cc-parse-log-or`.  Eight of the ten follow one
five-step template: evaluate the left operand, push it, evaluate the
right, pop, apply the operator.  Which operators each of the eight
accepts, and what instruction each emits, is one table.  `&&` and
`||` short-circuit, so they emit jumps instead.  Ch 28 covers the levels above the cascade
(ternary, assignment, `cc-parse-expr`) and below it (unary, primary,
and the lvalue tracking that `cc-emit-materialize` reads).

---

## 1. The root block: how the file is assembled

```forth file=100-cc-expr.fth
<<expr-header>>
<<expr-fwd-refs>>
<<expr-tok-tests>>
<<expr-lvalue>>
<<expr-struct-field>>
<<expr-array-index>>
<<expr-call>>
<<expr-primary>>
<<expr-unary>>
<<expr-binops>>
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

The root block fixes the assembly order: header, forward references, the parsers in source order, and the top-level
driver.  Each `<<name>>` expands to a chunk defined in this chapter
or in Ch 28, and the result is byte-identical to the checked-in
`100-cc-expr.fth`.

## 2. File header and dependency comment

```forth chunk=expr-header
\ 100-cc-expr.fth — recursive-descent expression parser for the C subset.
\ Emits code that leaves the expression's value in rdi.  Uses 090-cc-emit.fth's
\ instruction encoders.
\
\ Expression grammar, loosest-binding first (one cc-parse-LEVEL word each):
\   expr    := assign                                 \ then materialize
\   assign  := ternary (ASSIGN-OP assign)?            \ = += -= *= /= %= <<= >>= &= |= ^=
\   ternary := log-or ('?' assign ':' assign)?
\   log-or  := log-and ('||' log-and)*
\   log-and := bit-or ('&&' bit-or)*
\   bit-or  := bit-xor ('|' bit-xor)*
\   bit-xor := bit-and ('^' bit-and)*
\   bit-and := eq ('&' eq)*
\   eq      := rel (('=='|'!=') rel)*
\   rel     := shift (('<'|'<='|'>'|'>=') shift)*
\   shift   := add (('<<'|'>>') add)*
\   add     := mul (('+'|'-') mul)*
\   mul     := unary (('*'|'/'|'%') unary)*
\   unary   := ('*'|'&'|'-'|'!'|'~'|'++'|'--') unary | 'sizeof' '(' ... ')'
\            | primary
\   primary := (NUMBER | CHAR | STRING | IDENT | IDENT '(' args ')'
\               | IDENT '[' expr ']' | '(' expr ')')
\              ('.' IDENT | '->' IDENT | '[' expr ']' | '++' | '--')*
\
\ Tokens come from the lexer's interface (050-cc-lex.fth): cc-next-token-keep
\ reads the next one, and cc-putback-token hands the current one back when a
\ parser has read one token too many.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 090-cc-emit.fth.

```

The grammar in the comment lists every level, loosest first, and
each level is one `cc-parse-LEVEL` word: this chapter's cascade from
`assign` down to `mul`, and Ch 28's `unary` and `primary` with its
postfix chain (`[]`, `.`, `->`, `++`, `--`).  Every binary
production has the same shape: parse an operand at the
next-tighter level, then loop over this level's operators.

## 3. One token of putback

A cascade always reads one operator too many.  After folding the two
`*`s in `a * b * c + d`, `cc-parse-mul` reads the `+`, finds it isn't
a multiplicative operator, and has to hand it back so the next-looser
layer (`add`) can see it.

The lexer's interface does that (Ch 23 §7).  The parsers read tokens
with `cc-next-token-keep`, and `cc-putback-token` sets
`cc-tok-pending`, so the next `cc-next-token-keep` clears the flag
*without* advancing the lexer: `tok-kind`, `tok-num`, and `tok-str-*`
still describe the same token.  Every binary layer ends with
`cc-putback-token`.

Most of the questions a parser asks about the token it has just read
are "is it this punctuation?" or "is it this keyword?".  Two words
answer them, so a dispatch can read as a list of cases:

```forth chunk=expr-tok-tests
\ ===========================================================================
\ Token tests.  Is the current token this punctuation, or this keyword?
\ ===========================================================================

\ cc-tok-punct? ( code -- f )  True if the current token is punctuation code
\ (a character such as [char] ( or a pt-* constant such as pt-arrow).
: cc-tok-punct?  tok-kind @ tk-punct =  swap tok-num @ =  and ;

\ cc-tok-kw? ( id -- f )  True if the current token is the keyword id (kw-*).
: cc-tok-kw?  tok-kind @ tk-kw =  swap tok-kw-id @ =  and ;

```

`cc-tok-punct?` takes a punct code, which is the character itself for
one-character operators (`[char] (` is 40) and a `pt-*` constant from
Ch 23 for the longer ones.  `cc-tok-kw?` takes a `kw-*` id.  Both
check the token's kind first: a number token's `tok-num` holds its
value, and the number 40 is not a `(`.

## 4. Forward references for mutual recursion

```forth chunk=expr-fwd-refs
\ ===========================================================================
\ Forward references.  The grammar is recursive: a primary's '(' expr ')'
\ and a call's arguments re-enter the whole grammar, and the ternary's arms
\ parse assignments.  cc-parse-expr and cc-parse-assign are defined near the
\ end of this file, so the words before them call these deferred words
\ (010-lib.fth), which the last lines of the file fill in.
\ ===========================================================================

defer cc-parse-expr-fwd                           \ runs cc-parse-expr
defer cc-parse-assign-fwd                         \ runs cc-parse-assign

```

The grammar is mutually recursive: `primary` parses `'(' expr ')'`,
which re-enters the whole grammar, and so does each argument of a
call.  A word can call itself, since `:` makes a word findable as
soon as its header is built, but it cannot call a word that comes
later in the file.  So the file declares two deferred words
(Ch 12): `cc-parse-expr-fwd` and `cc-parse-assign-fwd` run whatever
xt their cells hold.  The words before `cc-parse-expr` call them,
and the last two lines of the file (Ch 28's `expr-top` chunk) fill
the cells with `is`.

Part III uses this pattern wherever load order and call order
disagree: `defer NAME-fwd` before the callers, `' NAME is NAME-fwd`
once the real word exists.  Ch 22's `#include` recursion and Ch 30's
statement parser use it too.

## 5. The operator table

Eight of the binary levels, `mul` down to `bit-or`, do the same thing
with different operators.  Each parses an operand at the next-tighter
level, and while the next token is one of *its* operators, parses
another operand and combines the two with one instruction sequence.
What differs from level to level is only which operators it accepts
and which encoder each one calls.  That is data, so it lives in one
table:

```forth chunk=expr-binops
\ ===========================================================================
\ The binary-operator table
\ ===========================================================================
\ Eight levels of the grammar, mul down to bit-or, have one shape: parse an
\ operand at the next-tighter level, then, while the next token is one of
\ this level's operators, parse another operand and combine the two.  Only
\ the operators and the instructions that combine differ, so those live in
\ this table, one row of four cells per operator:
\
\   op        the operator's punct code (tok-num)
\   compound  the code of its compound assignment (`+` has `+=`); 0 if none
\   level     which level parses it (level-mul .. level-bit-or)
\   emitter   xt of the 090 word that emits rdi := rdi OP rcx
\
\ Each level's parser looks its operators up by op; cc-parse-assign looks
\ `+=` and the rest up by compound, so `a + b` and `a += b` share an
\ emitter.  A row whose op is 0 ends the table.

[lit] 1 constant level-mul                        \ * / %
[lit] 2 constant level-add                        \ + -
[lit] 3 constant level-shift                      \ << >>
[lit] 4 constant level-rel                        \ < > <= >=
[lit] 5 constant level-eq                         \ == !=
[lit] 6 constant level-bit-and                    \ &
[lit] 7 constant level-bit-xor                    \ ^
[lit] 8 constant level-bit-or                     \ |

[lit]  0 constant bo-op                           \ byte offsets within a row
[lit]  8 constant bo-compound
[lit] 16 constant bo-level
[lit] 24 constant bo-emitter
[lit] 32 constant bo-size

```

A row is four cells.  `op` is the punct code the lexer gives the
operator; `level` names the precedence level that owns it; `emitter`
is the execution token of the Ch 25–26 encoder that computes
`rdi := rdi OP rcx`.  `compound` is the operator's compound-assignment
twin, which Ch 28's assignment parser looks up in the same table, so
`a + b` and `a += b` reach the same `add rdi, rcx`.  The level
numbers only label rows; they don't rank anything.

`cc-binop,` lays down one row.  Its last field comes from the input,
the way `char` takes its argument: `'` reads the encoder's name and
`,` stores its xt.

```forth chunk=expr-binops
\ cc-binop, ( op compound level "emitter" -- )  Lay down one row; the
\ emitter's name follows in the input.
: cc-binop,  rot , swap , ,  ' , ;

create cc-binops
\ op          compound       level
char *      pt-star-eq     level-mul      cc-binop, cc-emit-imul-rdi-rcx
char /      pt-slash-eq    level-mul      cc-binop, cc-emit-idiv-quotient
char %      pt-percent-eq  level-mul      cc-binop, cc-emit-idiv-remainder
char +      pt-plus-eq     level-add      cc-binop, cc-emit-add-rdi-rcx
char -      pt-minus-eq    level-add      cc-binop, cc-emit-sub-rdi-rcx
pt-shl      pt-shl-eq      level-shift    cc-binop, cc-emit-shl-rdi-cl
pt-shr      pt-shr-eq      level-shift    cc-binop, cc-emit-sar-rdi-cl   \ signed
char <      [lit] 0        level-rel      cc-binop, cc-emit-cmp-lt
char >      [lit] 0        level-rel      cc-binop, cc-emit-cmp-gt
pt-le       [lit] 0        level-rel      cc-binop, cc-emit-cmp-le
pt-ge       [lit] 0        level-rel      cc-binop, cc-emit-cmp-ge
pt-eq-eq    [lit] 0        level-eq       cc-binop, cc-emit-cmp-eq
pt-bang-eq  [lit] 0        level-eq       cc-binop, cc-emit-cmp-ne
char &      pt-amp-eq      level-bit-and  cc-binop, cc-emit-and-rdi-rcx
char ^      pt-caret-eq    level-bit-xor  cc-binop, cc-emit-xor-rdi-rcx
char |      pt-pipe-eq     level-bit-or   cc-binop, cc-emit-or-rdi-rcx
[lit] 0 ,                                         \ end of table

```

The table reads like the grammar's operator lists turned sideways.
Division and remainder share one `idiv` sequence (Ch 25 §5) and
differ in which half of the result they keep; `>>` is an arithmetic
(sign-extending) shift, because the only integer type is signed
`int`, so an unsigned `cc-emit-shr-rdi-cl` doesn't exist.  The
comparisons use the `cmp-set` encoders (Ch 25 §6), which leave
exactly 0 or 1 in `rdi`; the logical operators below rely on that,
since `1 && 2` must produce 1, not 2.  A row whose `op` is 0 ends the
table.

Three words read it:

```forth chunk=expr-binops
\ cc-binop-row ( key field -- row | 0 )  The first row whose cell at byte
\ offset field holds key, or 0 when no row does.
: cc-binop-row
  >r cc-binops                                    ( key row ; R: field )
  begin,
    dup bo-op + @                                 \ stop at the end row
  while,
    2dup r@ + @ = if,                             ( key row )
      nip r> drop exit,                           \ found: answer the row
    then,
    bo-size +
  repeat,
  2drop r> drop [lit] 0 ;

\ cc-binop? ( level -- row | 0 )  Read the next token.  If it is one of
\ this level's operators, answer its row; otherwise 0, and the caller
\ puts the token back.
: cc-binop?
  cc-next-token-keep
  tok-kind @ tk-punct <> if,
    drop [lit] 0 exit,                            \ not an operator at all
  then,
  tok-num @ bo-op cc-binop-row                    ( level row | level 0 )
  dup 0= if,
    nip exit,                                     \ no row: answer 0
  then,
  swap over bo-level + @ = if,                    ( row )
    exit,                                         \ ours: answer the row
  then,
  drop [lit] 0 ;                                  \ another level's operator

\ cc-binop-apply ( row -- )  The left operand is pushed and the right one
\ is in rdi.  Materialize the right, move it to rcx, pop the left into rdi,
\ emit the row's operation, and mark the result a plain value.
: cc-binop-apply
  cc-emit-materialize                             \ right must be a value
  cc-emit-mov-rcx-rdi                             \ rcx = right
  cc-emit-pop-rdi                                 \ rdi = left
  bo-emitter + @ execute                          \ rdi = left OP right
  cc-mark-not-lvalue ;

```

`cc-binop-row` is the table's only search: walk the rows until the
end row, and return (with `exit,`, after `r> drop` clears the field
offset it parked) the first one whose cell at byte offset `field`
equals the key.  `cc-binop?` is the question a level asks after each
operand: read a token, and answer its row if it is punctuation, in
the table, and at this level.  Anything else answers 0, and the
level puts the token back.  `cc-binop-apply` is the second half of
the fold, which the next section walks through.

## 6. The level template: `cc-parse-mul`

```forth chunk=expr-mul
\ ===========================================================================
\ cc-parse-mul: unary (('*'|'/'|'%') unary)*
\ ===========================================================================

: cc-parse-mul
  cc-parse-unary
  begin,
    level-mul cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-unary                                \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

```

Every level from `mul` to `bit-or` is this word with two names
changed, so it is worth reading slowly.

1. **Parse the left operand** at the next-tighter level
   (`cc-parse-unary` for `mul`).  `rdi` now holds the left value,
   or, for a pending dereference, an *address* that
   `cc-emit-materialize` must load.
2. **Loop while the next token is one of our operators.**
   `level-mul cc-binop?` reads a token and answers its row for `*`,
   `/` or `%`, or 0.  `dup` keeps a copy of the answer for `while,`
   to test, so the loop body starts with the row on the stack.
3. **Inside the loop:** park the row on the return stack, materialize
   the left value, push `rdi`, and parse the right operand.  Then
   `cc-binop-apply` finishes: materialize the right value, `mov rcx,
   rdi` (right into the temp), `pop rdi` (left into the result
   register), run the row's encoder, and mark the result a plain
   value.
4. **After the loop** the last token read isn't ours, so `drop`
   discards `cc-binop?`'s 0 and `cc-putback-token` returns the token
   to the caller.

The operator codes are the lexer's punct codes from Ch 23, which
for single characters are ASCII: `*` = 42, `/` = 47, `%` = 37.

The row rides on the return stack because the recursive
`cc-parse-unary` call can parse a parenthesised expression with
operators of its own, and those need the data stack for their own
intermediate values.

## 7. `cc-parse-add`: just like `mul`, looser

```forth chunk=expr-add
\ ===========================================================================
\ cc-parse-add: mul (('+'|'-') mul)*
\ ===========================================================================

: cc-parse-add
  cc-parse-mul
  begin,
    level-add cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-mul                                  \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

```

The shape is identical to `cc-parse-mul` with two substitutions: the
operand parser is `cc-parse-mul`, and the level asked about is
`level-add`, whose rows are `+` and `-`.

Each layer calls the one below it, so a bare number passes through
fifteen parser words (`expr` → `assign` → `ternary` → `log-or` →
`log-and` → `bit-or` → `bit-xor` → `bit-and` → `eq` → `rel` →
`shift` → `add` → `mul` → `unary` → `primary`) before reaching the
literal.  Each layer needs one token of lookahead, allocates
nothing, and costs one call.

## 8. Shifts: between relational and additive

```forth chunk=expr-shift
\ ===========================================================================
\ cc-parse-shift: add (('<<'|'>>') add)*
\ ===========================================================================
\ C puts shift between relational and additive: `a + b << c` is
\ `(a + b) << c`.  Variable-count shifts take the count in rcx (CL).

: cc-parse-shift
  cc-parse-add
  begin,
    level-shift cc-binop? dup                     ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-add                                  \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

```

C puts shifts between additive and relational operators, so
`a + b << c` parses as `(a + b) << c` and `a << b < c` as
`(a << b) < c`.  The call chain encodes that: `cc-parse-shift` uses
`cc-parse-add` for its operands, and `cc-parse-rel` (next) uses
`cc-parse-shift`.  The shift count must be in `cl`, and
`cc-binop-apply` has already moved the right operand into `rcx`.

## 9. Relational and equality

```forth chunk=expr-rel
\ ===========================================================================
\ cc-parse-rel: shift (('<'|'<='|'>'|'>=') shift)*
\ ===========================================================================

: cc-parse-rel
  cc-parse-shift
  begin,
    level-rel cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-shift                                \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

```

`cc-parse-eq` is the same template one level looser, over `==` and
`!=`:

```forth chunk=expr-eq
\ ===========================================================================
\ cc-parse-eq: rel (('=='|'!=') rel)*
\ ===========================================================================

: cc-parse-eq
  cc-parse-rel
  begin,
    level-eq cc-binop? dup                        ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-rel                                  \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

```

## 10. The bitwise trio

```forth chunk=expr-bit
\ ===========================================================================
\ cc-parse-bit-and: eq ('&' eq)*
\ ===========================================================================
\ This '&' is the binary (infix) bitwise-and.  Unary '&' (address-of) is
\ cc-parse-unary's: operator position vs operand position tells them apart.

: cc-parse-bit-and
  cc-parse-eq
  begin,
    level-bit-and cc-binop? dup                   ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-eq                                   \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-bit-xor: bit-and ('^' bit-and)*
\ ===========================================================================

: cc-parse-bit-xor
  cc-parse-bit-and
  begin,
    level-bit-xor cc-binop? dup                   ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-bit-and                              \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-bit-or: bit-xor ('|' bit-xor)*
\ ===========================================================================

: cc-parse-bit-or
  cc-parse-bit-xor
  begin,
    level-bit-or cc-binop? dup                    ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-bit-xor                              \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

```

Three layers, one operator each, and the same template.  Before the
table existed these three were the only levels without a dispatch
on the operator; now no level has one.

C's `&` is overloaded.  Where an operand is expected it is unary
address-of; between two operands it is binary bitwise-and.  The
grammar separates the two by position: `cc-parse-unary` (Ch 28)
sees `&` only at operand position, and `cc-parse-bit-and` sees it
only at operator position, so they never compete for the same
token.

## 11. Short-circuit `&&` and `||`

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

## 12. The cascade in motion

Here is `a + b * c < 5` passing through the layers:

1. `cc-parse-rel` is the outer call (`<` is a relational op).
2. It calls `cc-parse-shift`, which calls `cc-parse-add`, which
   calls `cc-parse-mul`, which calls `cc-parse-unary`, which
   bottoms out in `cc-parse-primary`, whose `cc-parse-ident`
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

The operator table only says which level owns each operator; nothing
in this trace ranks one level above another.  The order in which the
layers call each other is the precedence table.

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

2. **★★ Trace.** The `<<` row of the operator table also names `<<=`,
   but no level parses `<<=`: `cc-binop?` compares `tok-num` with
   the `op` column only.  Who reads the `compound` column, and why
   does it have to be a different parser from `cc-parse-shift`?
   (Hint: where does the parse tree branch into right-associative
   territory?)

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
pop, op) driven by the operator table, and two through
short-circuit jumps.

You can read `cc-parse-mul`/`add`/`rel`/`eq`/`bit`/`log` and the
operator table, explain the precedence cascade, and predict what code an expression like
`a + b * c > d` will emit without running it.

What the cascade cannot do yet is write.  In `w[r] = 1 + r * 2`,
everything above computed the right side; the left side needs the
*address* of `w[r]`, and the parser does not know it wants an
address until it reaches the `=`.  Ch 28 solves that.

## Takeaways

- Each binary precedence level is one word that parses its operands
  at the next-tighter level, so the order of the calls is the
  precedence table.
- One table row per operator names its level, its compound form and
  its encoder, so the eight folding levels share one template and
  `+` and `+=` share one emitter.
- The operator's row travels on the return stack, which leaves the
  data stack free for a parenthesised expression parsed inside an
  operand.
- `&&` and `||` replace the fold template with conditional jumps
  whose three rel32 fixups wait on the return stack and are patched
  in reverse order.

Next: Chapter 28 — Expressions, Part 2: Primary, Unary, Assignment.
