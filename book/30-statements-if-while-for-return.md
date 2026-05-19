# Chapter 30 — Statements: `if`, `while`, `for`, `switch`, `break`, `continue`, `goto`

> **Status:** ✅ complete.  Contributes lines 588–1438 of
> `110-cc-decl.fth` — the statement parsers including the
> control-flow combinators, break/continue fixup-list machinery,
> switch dispatch, label/goto support, and the `cc-parse-stmt`
> top-level dispatcher.

## Goal

By the end of this chapter the reader can:

- read `cc-parse-if` and recognise the same fixup-on-the-stack
  pattern from Ch 11's `if,`/`else,`/`then,`, now emitting x86-64
  `jz`/`jmp` instead of Forth `0branch`/`branch`;
- read `cc-parse-while`, `cc-parse-for`, and `cc-parse-do-while`
  and explain the break/continue fixup-list machinery;
- read `cc-parse-switch` and trace its three-pass layout (body,
  dispatch table, end);
- read the label-table machinery and `cc-parse-goto-stmt`'s
  forward / backward branching;
- read the `cc-parse-stmt` dispatcher and explain its lookahead
  for `IDENT ':'` label definitions versus expression statements.

## Source coverage

`110-cc-decl.fth` lines 588–1438.  Ch 29 covered 1–587;
Ch 31 covers 1439–2750.

## Concepts introduced

- **Statement trampoline `cc-parse-stmt-vec`.**  Mutually
  recursive with `cc-parse-if` and `cc-parse-compound`; the
  trampoline indirects through a vec so the late binding
  resolves.
- **Absolute backward jumps via `cc-emit-jmp-vaddr` /
  `cc-emit-jnz-vaddr` / `cc-emit-je-vaddr`.**  These compute
  rel32 = `target_vaddr - (cc-base-vaddr + cc-out-pos + 4)` and
  emit the bytes.  Defined here because they reference
  `cc-base-vaddr` from `080-cc-elf.fth`.
- **Break / continue fixup lists.**  Each loop has its own
  linked list of pending forward-jump fixups; entering a loop
  saves the outer head on the return stack and resets to 0;
  leaving walks the list patching each fixup to the appropriate
  target.
- **`for`-step rewind.**  The C `for` statement evaluates its
  step expression *after* the body, but textually it appears
  before.  This compiler records the source range of the step,
  scans past `)`, parses the body, then rewinds the lexer to
  re-parse the step in place after the body's bytes.
- **Switch via reverse-order dispatch table.**  Body codegen is
  emitted in source order; the dispatch table (`cmp rbx, K ; je
  body-vaddr` per case) is emitted *after* the body in reverse
  order from a linked list of cases.
- **Function-local labels with forward fixups.**  64-entry
  parallel-array label table per function; undefined labels
  accumulate a fixup list that gets patched on definition.

## Concepts carried in

- All declaration parsing from Ch 29.
- Codegen primitives — `cc-emit-test-rdi`,
  `cc-emit-jz-rel32-placeholder`, `cc-emit-jmp-rel32-
  placeholder`, `cc-patch-rel32-to-here`, `cc-emit-push-rbx`,
  `cc-emit-mov-rbx-rdi`, `cc-emit-cmp-rbx-imm32` (Chs 25–26).
- Forth's `if,`/`then,`/`else,`/`begin,`/`while,`/`repeat,`
  (Ch 11) — the *outer* control flow of the parser itself.

## Concepts deferred

- Function definitions, the function-list driver, and parameter
  parsing — Ch 31.
- Enum and typedef definitions — Ch 31.
- File-scope globals and the top-level driver — Ch 31.

---

Statements are control flow.  The parser sees keywords like
`if`, `while`, `for`, `switch`, `break`, `continue`, `return`,
`goto`, plus expression statements and compound `{}` blocks.
Each dispatches to a specialised parser, which evaluates any
embedded expressions via Ch 28's `cc-parse-expr` and emits
control-flow instructions via Chs 25–26's encoders.

The recurring pattern is the *forward-fixup*: emit a conditional
jump with a placeholder displacement, return when you know the
target, and patch the placeholder.  We met it in Ch 11 (Forth
combinators) and Ch 27 (logical operators).  This chapter is
where it gets used at scale.

**How this chapter is organized.**  The chapter has two big
sections.  Section §1 is the source listing — the full 800-line
slab of `110-cc-decl.fth` that defines `cc-parse-stmt` and all
its specialised sub-parsers.  Reading §1 once gives you the
shape; you don't have to absorb it all.  Section §2 *walks the
listing* statement by statement: `cc-parse-if`, `cc-parse-while`,
`cc-parse-for`, `cc-parse-do-while`, `cc-parse-switch`,
`cc-parse-break`/`continue`, `cc-parse-goto` and labels, then
the dispatcher `cc-parse-stmt` and the compound-statement parser.
If you want only one statement (say, how `for` is compiled), find
its subsection in §2 and read forward; the listing in §1 is the
canonical source the subsection is paraphrasing.

> The dispatch through `cc-parse-stmt-vec` is a trampoline
> pattern: the dispatcher fills in its function pointers from a
> table Ch 31 sets up.  Ch 31 (functions and scope) is where the
> trampoline gets populated and where you'll see the matching
> `cc-parse-stmt` call site.  This chapter explains the
> statements themselves; Ch 31 explains how they get invoked
> from a function body.

## 1. The source listing

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Statement dispatch
\ ===========================================================================
\ cc-parse-stmt is mutually recursive with cc-parse-if and cc-parse-compound,
\ so we route through cc-parse-stmt-vec.  The vec is set after all three
\ words are defined.

variable cc-parse-stmt-vec

: cc-parse-stmt-tramp  cc-parse-stmt-vec @ execute ;

\ cc-parse-compound ( -- )  '{' (stmt | decl)* '}'
\ Caller has already consumed '{'.  Pushes/pops a scope so locals declared
\ inside the block are discarded at end-of-block.
: cc-parse-compound
  cc-scope-push
  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [lit] 125 = and 0=
  while,
    cc-putback-token
    cc-parse-stmt-tramp
  repeat,
  \ '}' was consumed by the loop test.
  cc-scope-pop ;

\ cc-parse-if ( -- )  'if' already consumed.
\   if (expr) stmt
\   if (expr) stmt else stmt
\
\ Codegen:
\     <eval cond>
\     test rdi, rdi
\     jz   <else-or-end>            (rel32 fixup #1)
\     <then-body>
\     [if else:]
\     jmp  <end>                    (rel32 fixup #2)
\   else-or-end:
\     <else-body>
\   end:
: cc-parse-if
  [lit]  40 cc-expect-punct-c                     \ '('
  cc-parse-expr-balanced
  [lit]  41 cc-expect-punct-c                     \ ')'

  cc-emit-test-rdi
  cc-emit-jz-rel32-placeholder                    ( fixup-jz )

  cc-parse-stmt-tramp                             \ then-body

  \ Optional else.
  cc-next-token-keep
  tok-kind @ tk-kw = tok-kw-id @ kw-else = and if,
    \ jmp end ; patch jz to here ; else-body ; patch jmp to here.
    cc-emit-jmp-rel32-placeholder                 ( fixup-jz fixup-jmp )
    swap cc-patch-rel32-to-here                   ( fixup-jmp )
    cc-parse-stmt-tramp                           \ else-body
    cc-patch-rel32-to-here                        ( -- )
  else,
    cc-putback-token
    cc-patch-rel32-to-here                        ( -- )
  then, ;

\ ===========================================================================
\ Loop helpers
\ ===========================================================================
\ cc-emit-jmp-vaddr lives here (rather than in 090-cc-emit.fth) because it
\ references cc-base-vaddr, which is defined in 080-cc-elf.fth — loaded AFTER
\ 090-cc-emit.fth but BEFORE 110-cc-decl.fth.

\ cc-emit-jmp-vaddr ( target-vaddr -- )  Emit `E9 <rel32>` to absolute target.
\ After emitting the E9 opcode, cc-out-pos points at the rel32 slot's first
\ byte; the address of the next instruction is cc-base-vaddr + cc-out-pos + 4.
: cc-emit-jmp-vaddr                               ( target-vaddr -- )
  [lit] 233 cc-emit-byte                          \ E9 opcode
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        \ rel32
  cc-emit-4le ;

\ cc-emit-jnz-vaddr ( target-vaddr -- )  Emit `0F 85 <rel32>` to absolute target.
\ After emitting `0F 85`, cc-out-pos points at the rel32 slot's first byte.
: cc-emit-jnz-vaddr                               ( target-vaddr -- )
  [lit]  15 cc-emit-byte                          \ 0F prefix
  [lit] 133 cc-emit-byte                          \ 85 opcode
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        \ rel32
  cc-emit-4le ;

\ cc-emit-je-vaddr ( target-vaddr -- )  Emit `0F 84 <rel32>` to absolute
\ target.  Mirror of cc-emit-jnz-vaddr; used by switch dispatch.
: cc-emit-je-vaddr                                ( target-vaddr -- )
  [lit]  15 cc-emit-byte                          \ 0F prefix
  [lit] 132 cc-emit-byte                          \ 84 opcode
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        \ rel32
  cc-emit-4le ;

\ ===========================================================================
\ Break / continue fixup-list infrastructure
\ ===========================================================================
\ Each loop maintains TWO linked lists of pending forward-jump fixups: one for
\ break-statements (target = end-of-loop), one for continue-statements (target =
\ continue-point — for-loop step, do-while cond test, while-loop top).
\
\ A node is two cells (16 bytes): { fixup-offset (8), next-pointer (8) }.  The
\ list head is just the variable cc-break-stack-head / cc-continue-stack-head.
\ "0" is the empty-list sentinel.
\
\ When entering a loop, save the outer head on the rstack and reset to 0.  When
\ leaving, walk the list patching each fixup's rel32 to a known target vaddr,
\ then restore the outer head.

variable cc-break-stack-head
variable cc-continue-stack-head
\ Temp slot for cc-walk-and-patch-to-vaddr (avoids deeper stack juggling).
variable cc-fixup-target-tmp
variable cc-for-top-vaddr
variable cc-for-end-fixup
variable cc-for-step-start
variable cc-for-step-end

\ cc-add-fixup-to-list is now defined in 090-cc-emit.fth so 100-cc-expr.fth can
\ reference it from cc-parse-primary's forward-function-rvalue path.

: cc-add-break-fixup                              ( off -- )
  cc-break-stack-head cc-add-fixup-to-list ;

: cc-add-continue-fixup                           ( off -- )
  cc-continue-stack-head cc-add-fixup-to-list ;

\ cc-walk-and-patch-to-vaddr ( head-ptr target-vaddr -- )
\ Walk the linked list head-ptr, patching each fixup's rel32 to point at
\ target-vaddr.
: cc-walk-and-patch-to-vaddr                      ( head target -- )
  cc-fixup-target-tmp !                           ( head )
  begin,
    dup [lit] 0 <>
  while,
    \ Stack: ( node-ptr ).  Read the fixup-offset (node[0]).
    dup @                                         ( node off )
    \ rel32 = target - (cc-base-vaddr + off + 4)
    cc-fixup-target-tmp @                         ( node off target )
    over cc-base-vaddr + [lit] 4 + -              ( node off rel32 )
    \ Patch 4 bytes at off with rel32.
    over cc-out-patch-4le                         ( node off )
    drop                                          ( node )
    \ Advance to next node: head := node[8].
    [lit] 8 + @                                   ( next-node )
  repeat,
  drop ;

\ cc-walk-and-patch-imm64-to-vaddr ( head target-vaddr -- )
\ Walk the linked list head, patching each fixup's 8-byte imm64 to the
\ absolute target vaddr.  Used for forward `movabs rdi, imm64` sites that
\ load a function's address as an rvalue before the function is defined.
: cc-walk-and-patch-imm64-to-vaddr                ( head target -- )
  cc-fixup-target-tmp !                           ( head )
  begin,
    dup [lit] 0 <>
  while,
    dup @                                         ( node off )
    cc-fixup-target-tmp @                         ( node off target )
    swap cc-out-patch-8le                         ( node )
    [lit] 8 + @                                   ( next-node )
  repeat,
  drop ;

\ cc-walk-and-patch-fixups ( head-ptr -- )  Patch each fixup to current cc-out-pos.
: cc-walk-and-patch-fixups                        ( head -- )
  cc-base-vaddr cc-out-pos @ +
  cc-walk-and-patch-to-vaddr ;

\ cc-parse-while ( -- )  'while' already consumed.
\
\ Codegen:
\   <top:>           ; record vaddr; continue-target
\   <eval cond>      ; rdi = cond
\   test rdi, rdi
\   jz   <end>       ; rel32 placeholder
\   <body>           ; break/continue inside emit forward-fixed jmps
\   jmp  <top>       ; absolute via cc-emit-jmp-vaddr
\   <end:>           ; patch jz to here; break-target
\
\ The outer break/continue list heads are saved/restored on the rstack.
\ During the body, both heads are 0 (= empty list); break/continue stmts
\ inside add forward-jmp fixup nodes that we patch at end-of-loop.
: cc-parse-while
  \ Save outer break/continue list heads on rstack.
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !

  [lit]  40 cc-expect-punct-c                     \ '('
  cc-base-vaddr cc-out-pos @ +                    ( top-vaddr )
  cc-parse-expr
  [lit]  41 cc-expect-punct-c                     \ ')'
  cc-emit-test-rdi
  cc-emit-jz-rel32-placeholder                    ( top fixup-end )

  \ Park top-vaddr on rstack so it survives the body parse.
  swap >r                                         ( fixup-end ; R: ... top )

  cc-parse-stmt-tramp                             \ body

  \ Continue target = top-vaddr.  Walk continue list (no-op if empty).
  cc-continue-stack-head @ r@ cc-walk-and-patch-to-vaddr

  \ Emit jmp top, then patch jz fixup.
  r> cc-emit-jmp-vaddr                            ( fixup-end )
  cc-patch-rel32-to-here

  \ Break target = here.  Walk break list (no-op if empty).
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

\ cc-parse-for ( -- )  'for' already consumed.
\
\ Grammar: 'for' '(' init? ';' cond? ';' step? ')' stmt
\
\ The step expression appears textually BEFORE the body but must execute
\ AFTER it.  We handle this by recording the source range of the step,
\ scanning past the close-paren, parsing the body, then rewinding the lexer
\ to re-parse the step in place after the body.
\
\ Codegen:
\   <init expr (if any)>
\   <top:>
\   <cond expr (if any, else mov rdi, 1)>
\   test rdi, rdi
\   jz   <end>
\   <body>
\   <step expr (if any)>
\   jmp  <top>
\   <end:>
: cc-parse-for
  [lit]  40 cc-expect-punct-c                     \ '('

  \ --- Init (optional) ---
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
    \ ';' — empty init; token is consumed.
  else,
    cc-putback-token
    cc-parse-expr
    [lit] 59 cc-expect-punct-c
  then,

  \ Save outer break/continue heads on rstack (after init, since init runs
  \ outside the loop and shouldn't see this loop's break/continue).
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !

  \ Top of loop.
  cc-base-vaddr cc-out-pos @ +                    ( top-vaddr )

  \ --- Cond (optional) ---
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
    \ ';' — empty cond; emit `mov rdi, 1` for unconditional truth.
    [lit] 1 cc-emit-mov-rdi-imm32
  else,
    cc-putback-token
    cc-parse-expr
    [lit] 59 cc-expect-punct-c
  then,

  cc-emit-test-rdi
  cc-emit-jz-rel32-placeholder                    ( top fixup-end )
  cc-for-end-fixup !
  cc-for-top-vaddr !

  \ --- Step source-range capture ---
  \ Before scanning forward we must clear any pending putback so the lexer's
  \ next read after we rewind re-tokenises from the new cc-src-pos.
  \ (No putback is in flight here — cc-expect-punct-c above consumed it — but
  \ the assertion is cheap.)
  [lit] 0 cc-tok-pending !
  cc-src-pos @ cc-for-step-start !
  \ Scan to the matching ')'.  Track depth starting at 1 (we're already
  \ inside the outer for-paren).
  [lit] 1                                         ( depth )
  begin,
    dup [lit] 0 >  cc-eof? 0= and
  while,
    cc-peek-char [lit] 40 = if,
      [lit] 1 +
    else,
      cc-peek-char [lit] 41 = if,
        [lit] 1 -
      then,
    then,
    cc-next-char drop
  repeat,
  drop                                            ( -- )
  \ cc-src-pos is now just past ')'.  step-end = position of ')'.
  cc-src-pos @ [lit] 1 - cc-for-step-end !

  \ --- Body ---
  cc-parse-stmt-tramp

  \ Continue target = HERE (just before step).  Walk continue list.
  cc-continue-stack-head @ cc-walk-and-patch-fixups

  \ --- Re-parse step at recorded range ---
  \ Save current lexer state, set pos := step-start, len := step-end (so the
  \ tokenizer naturally hits EOF at the close-paren).  After parsing, restore.
  cc-src-pos @ >r
  cc-src-len @ >r
  cc-for-step-end @ cc-src-len !
  cc-for-step-start @ cc-src-pos !
  \ Clear any pending putback before re-tokenising at the new position.
  [lit] 0 cc-tok-pending !
  \ Parse step iff there is one (pos < len).
  cc-src-pos @ cc-src-len @ < if,
    cc-parse-expr
  then,
  \ Restore lexer state.
  [lit] 0 cc-tok-pending !
  r> cc-src-len !
  r> cc-src-pos !

  \ Emit jmp top.
  cc-for-top-vaddr @ cc-emit-jmp-vaddr

  \ Patch jz fixup to current position.
  cc-for-end-fixup @ cc-patch-rel32-to-here

  \ Break target = here.  Walk break list (no-op if empty).
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

\ ===========================================================================
\ do-while loop
\ ===========================================================================
\ Codegen:
\   <top:>           ; record vaddr (back-target for jnz)
\   <body>           ; break/continue inside emit forward-fixup jmps
\   <continue-here:> ; walk continue list, patch each to here
\   <eval cond>      ; rdi = cond
\   test rdi, rdi
\   jnz <top>        ; absolute backward branch
\   <break-here:>    ; walk break list, patch each to here
\
\ "do" has already been consumed.  Grammar:  do stmt while ( expr ) ;
: cc-parse-do-while
  \ Save outer break/continue heads.
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !

  \ Record top-vaddr for the backward jnz.
  cc-base-vaddr cc-out-pos @ + >r                 ( ; R: ... top )

  cc-parse-stmt-tramp                             \ body

  \ Continue target = HERE (just before cond test).
  cc-continue-stack-head @ cc-walk-and-patch-fixups

  \ Parse 'while ( expr ) ;'
  kw-while cc-expect-kw-id
  [lit]  40 cc-expect-punct-c                     \ '('
  cc-parse-expr
  [lit]  41 cc-expect-punct-c                     \ ')'
  [lit]  59 cc-expect-punct-c                     \ ';'

  cc-emit-test-rdi
  r> cc-emit-jnz-vaddr                            \ jnz top

  \ Break target = here.
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

\ ===========================================================================
\ switch / case / default
\ ===========================================================================
\ Codegen layout (single-pass with a deferred dispatch table):
\
\     <eval e>                  ; rdi = scrutinee
\     push rbx                  ; preserve outer rbx
\     mov  rbx, rdi             ; rbx = scrutinee for the rest of the switch
\     jmp  <dispatch>           ; rel32, patched after body parse
\   case-K1-body:               ; vaddr recorded in case-list
\     <stmts>
\     [break: jmp <end-A>]      ; (registered as a break fixup)
\     ... (falls through to next case-body if no break)
\   default-body:               ; (or absent)
\     <stmts>
\     jmp <end-A>               ; fall-through past last case (always emitted)
\   dispatch:
\     cmp rbx, K1; je case-K1-body
\     cmp rbx, K2; je case-K2-body
\     ...
\     [jmp default-body | jmp <end-A>]
\   end-A:                      ; break fixups + fall-through + no-default land here
\     pop rbx                   ; restore outer rbx
\   end:
\
\ The break list and the cc-switch-default-vaddr / cc-switch-cases-head state
\ are saved/restored on the rstack across recursion (nested switches and
\ switch-inside-loop and loop-inside-switch all work).

variable cc-switch-cases-head     \ linked list of { K (8), vaddr (8), next (8) }
variable cc-switch-default-vaddr  \ 0 if no default seen

\ cc-add-switch-case ( K body-vaddr -- )  Allocate a 24-byte node and prepend
\ it to cc-switch-cases-head.  The list is built in reverse source order;
\ this is fine because the dispatch table semantics are order-independent
\ (duplicate K is illegal C anyway).
: cc-add-switch-case                              ( K vaddr -- )
  [lit] 24 cc-alloc                               ( K vaddr node )
  >r                                              ( K vaddr ; R: node )
  r@ [lit] 8 + !                                  \ node[8] = vaddr
  r@ !                                            \ node[0] = K
  cc-switch-cases-head @ r@ [lit] 16 + !          \ node[16] = old head
  r> cc-switch-cases-head ! ;                     \ head := node

\ cc-emit-switch-dispatch ( -- )  Walk cc-switch-cases-head, emitting
\ `cmp rbx, K; je <body-vaddr>` for each entry.  Order is reverse of source,
\ which is semantically irrelevant for switch/case.
: cc-emit-switch-dispatch                         ( -- )
  cc-switch-cases-head @                          ( node )
  begin,
    dup [lit] 0 <>
  while,
    dup @                                         ( node K )
    cc-emit-cmp-rbx-imm32                         \ cmp rbx, K
    dup [lit] 8 + @                               ( node body-vaddr )
    cc-emit-je-vaddr                              \ je <body-vaddr>
    [lit] 16 + @                                  \ next
  repeat,
  drop ;

\ cc-parse-switch ( -- )  'switch' already consumed by cc-parse-stmt.
\ Grammar:  switch ( expr ) { (case INT : | default : | stmt)* }
\ The body is a single compound statement; we parse it inline rather than
\ via cc-parse-compound so that case/default can be intercepted.
: cc-parse-switch
  \ Save outer state on rstack.
  cc-switch-cases-head    @ >r
  cc-switch-default-vaddr @ >r
  cc-break-stack-head     @ >r
  [lit] 0 cc-switch-cases-head    !
  [lit] 0 cc-switch-default-vaddr !
  [lit] 0 cc-break-stack-head     !

  \ '(' expr ')'
  [lit]  40 cc-expect-punct-c                     \ '('
  cc-parse-expr                                   \ rdi = scrutinee
  [lit]  41 cc-expect-punct-c                     \ ')'

  \ Save outer rbx, then move scrutinee into rbx.
  cc-emit-push-rbx
  cc-emit-mov-rbx-rdi

  \ Forward jmp to the dispatch table (emitted after the body).
  cc-emit-jmp-rel32-placeholder                   ( jmp-to-dispatch )
  >r

  \ '{' (case|default|stmt)* '}'
  [lit] 123 cc-expect-punct-c                     \ '{'

  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [lit] 125 = and 0=
  while,
    \ Three sub-cases: 'case' INT ':', 'default' ':', or generic stmt.
    tok-kind @ tk-kw = tok-kw-id @ kw-case = and if,
      \ 'case' has been consumed; read constant (int literal only
      \ doesn't handle constant-expressions for case labels).
      cc-next-token-keep
      tok-kind @ tk-num <> if,
        [lit] 90 die
      then,
      tok-num @                                   ( K )
      [lit]  58 cc-expect-punct-c                 \ ':'
      cc-base-vaddr cc-out-pos @ +                ( K body-vaddr )
      cc-add-switch-case
    else,
      tok-kind @ tk-kw = tok-kw-id @ kw-default = and if,
        \ 'default' has been consumed.
        [lit]  58 cc-expect-punct-c               \ ':'
        cc-base-vaddr cc-out-pos @ +
        cc-switch-default-vaddr !
      else,
        \ Generic statement — put back, parse via the trampoline.
        cc-putback-token
        cc-parse-stmt-tramp
      then,
    then,
  repeat,
  \ '}' was consumed by the loop test.

  \ Fall-through past the last case-body must skip the dispatch table and
  \ land at end-A.  Emit a jmp placeholder and register it in the break list
  \ so it gets patched together with the rest.
  cc-emit-jmp-rel32-placeholder
  cc-add-break-fixup

  \ Patch the initial jmp-to-dispatch to land here (start of dispatch table).
  r> cc-patch-rel32-to-here                       ( -- )

  \ Emit the dispatch chain.
  cc-emit-switch-dispatch

  \ After the dispatch chain: if there's a default, jump to it; otherwise
  \ register a final jmp to end-A (no case matched, no default).
  cc-switch-default-vaddr @ [lit] 0 <> if,
    cc-switch-default-vaddr @ cc-emit-jmp-vaddr
  else,
    cc-emit-jmp-rel32-placeholder
    cc-add-break-fixup
  then,

  \ end-A: walk break list, patching each fixup to here.
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer rbx.
  cc-emit-pop-rbx

  \ Restore outer state.
  r> cc-break-stack-head     !
  r> cc-switch-default-vaddr !
  r> cc-switch-cases-head    ! ;

\ ===========================================================================
\ break / continue statements
\ ===========================================================================
\ Each emits a forward-jmp placeholder and prepends its rel32-fixup-offset to
\ the innermost loop's break or continue list.  The enclosing loop walks the
\ list at end-of-loop, patching each fixup's rel32 to the appropriate target.
\
\ cc-parse-break-stmt ( -- )  "break" already consumed by cc-parse-stmt.
\ NB: detecting "break outside any loop" requires a depth counter.  This
\ compiler assumes break/continue appear in valid loop or switch contexts.
: cc-parse-break-stmt
  [lit]  59 cc-expect-punct-c                     \ ';'
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-break-fixup ;

\ cc-parse-continue-stmt ( -- )  "continue" already consumed.
: cc-parse-continue-stmt
  [lit]  59 cc-expect-punct-c                     \ ';'
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-continue-fixup ;

\ ===========================================================================
\ Label table (per-function) + goto / label definition
\ ===========================================================================
\ Labels are function-local.  We use parallel arrays similar to cc-sym, sized
\ small (64 labels max per function).  cc-label-count is reset to 0 on
\ function entry.
\
\ Each label tracks:
\   cc-label-name-addr [id] : pointer into cc-src-buf where name begins
\   cc-label-name-len  [id] : length
\   cc-label-vaddr     [id] : 0 if undefined, else absolute vaddr of the label
\   cc-label-fixup     [id] : head-pointer of forward-jmp fixup list (0 = none)

[lit] 64 constant cc-label-cap
create cc-label-name-addr  cc-label-cap [lit] 8 * allot
create cc-label-name-len   cc-label-cap [lit] 8 * allot
create cc-label-vaddr      cc-label-cap [lit] 8 * allot
create cc-label-fixup      cc-label-cap [lit] 8 * allot
variable cc-label-count

\ cc-label-slot ( id arr -- addr )  Compute the address of slot id in arr.
: cc-label-slot  swap [lit] 8 * + ;

\ cc-label-vaddr-of ( id -- vaddr )
: cc-label-vaddr-of   cc-label-vaddr   cc-label-slot @ ;
: cc-label-fixup-of   cc-label-fixup   cc-label-slot @ ;
: cc-label-set-vaddr  cc-label-vaddr   cc-label-slot ! ;     \ ( v id -- )
: cc-label-set-fixup  cc-label-fixup   cc-label-slot ! ;     \ ( v id -- )

\ cc-label-find-result holds -1 (= [lit] 0 0=) while still searching, or the id.
variable cc-label-find-result
variable cc-label-find-needle-addr
variable cc-label-find-needle-len

\ cc-label-find ( name-addr name-len -- id-or-neg1 )
: cc-label-find
  cc-label-find-needle-len  !
  cc-label-find-needle-addr !
  [lit] 0 0= cc-label-find-result !               \ -1 = "not found"
  cc-label-count @ [lit] 1 -                      ( i = count-1 )
  begin,
    dup [lit] 0 >=
  while,
    cc-label-find-result @ [lit] 0 0= = if,       \ still searching?
      dup cc-label-name-len cc-label-slot @
      cc-label-find-needle-len @ = if,
        dup cc-label-name-addr cc-label-slot @    ( i entry-addr )
        cc-label-find-needle-addr @ swap
        cc-label-find-needle-len @
        bytes-eq if,
          dup cc-label-find-result !
        then,
      then,
    then,
    [lit] 1 -
  repeat,
  drop
  cc-label-find-result @ ;

\ cc-label-create ( name-addr name-len -- id )  Append a new label entry.
\ Initial vaddr=0 (undefined), fixup=0 (no forward refs yet).
: cc-label-create                                 ( a u -- id )
  cc-label-count @ cc-label-cap >= if,
    [lit] 82 die
  then,
  cc-label-count @                                ( a u id )
  >r                                              \ R: id
  r@ cc-label-name-len  cc-label-slot !           \ store len
  r@ cc-label-name-addr cc-label-slot !           \ store addr
  [lit] 0 r@ cc-label-set-vaddr                   \ vaddr := 0
  [lit] 0 r@ cc-label-set-fixup                   \ fixup-list := 0
  [lit] 1 cc-label-count +!
  r> ;

\ cc-label-find-or-create ( name-addr name-len -- id )
\ Look up by name; if not found, append a new entry.
: cc-label-find-or-create                         ( a u -- id )
  2dup cc-label-find                              ( a u id )
  dup [lit] 0 >= if,
    \ Found.  Discard name args, keep id.
    >r 2drop r>
  else,
    drop                                          ( a u )
    cc-label-create
  then, ;

\ cc-define-label ( name-addr name-len -- )
\ Bind the label to the current cc-out-pos and resolve any forward refs.
\ Errors out (status 81) on duplicate definition.
: cc-define-label                                 ( a u -- )
  cc-label-find-or-create                         ( id )
  \ Reject duplicates.
  dup cc-label-vaddr-of [lit] 0 <> if,
    [lit] 81 die
  then,
  \ Set vaddr.
  dup >r                                          ( id ; R: id )
  cc-base-vaddr cc-out-pos @ + r@ cc-label-set-vaddr
  \ Walk forward-fixup list, patch each to current pos.
  r> cc-label-fixup-of cc-walk-and-patch-fixups ;

\ cc-parse-goto-stmt ( -- )  "goto" already consumed.  Grammar:  goto IDENT ;
\
\ If the target label is already defined, emit an absolute backward jmp.
\ Otherwise emit a forward-jmp placeholder and prepend its rel32-fixup-offset
\ to the label's fixup list (resolved when the label is defined).
: cc-parse-goto-stmt
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 80 die
  then,
  tok-str-addr @ tok-str-len @ cc-label-find-or-create   ( id )

  dup cc-label-vaddr-of                           ( id vaddr )
  dup [lit] 0 <> if,
    \ Backward jump to known target.
    cc-emit-jmp-vaddr                             ( id )
    drop                                          ( -- )
  else,
    drop                                          ( id )
    \ Forward ref: emit placeholder, prepend offset to label's fixup list.
    cc-emit-jmp-rel32-placeholder                 ( id fixup-offset )
    over cc-label-fixup-of                        ( id off old-head )
    \ Allocate node: { off, old-head }.
    [lit] 16 cc-alloc                             ( id off old-head node )
    >r                                            ( id off old-head ; R: node )
    swap                                          ( id old-head off ; R: node )
    r@ !                                          ( id old-head ; R: node )
    r@ [lit] 8 + !                                ( id ; R: node )
    \ Set label's fixup-list head to the new node.
    r> swap cc-label-set-fixup                    ( -- )
  then,
  [lit]  59 cc-expect-punct-c ;                   \ ';'

\ ===========================================================================
\ One-token lookahead used to detect "IDENT :" label definitions.
\ ===========================================================================
\ The current putback layer (cc-tok-pending) only buffers one token.  To peek
\ TWO tokens ahead we save the lexer + token state, read one fresh token, and
\ either commit (if it confirms a label) or restore everything (if not).
variable cc-lookahead-save-pos
variable cc-lookahead-save-line
variable cc-lookahead-save-pending
variable cc-lookahead-save-tok-kind
variable cc-lookahead-save-tok-num
variable cc-lookahead-save-tok-addr
variable cc-lookahead-save-tok-len
variable cc-lookahead-save-tok-kw

: cc-lookahead-save
  cc-src-pos     @ cc-lookahead-save-pos      !
  cc-src-line    @ cc-lookahead-save-line     !
  cc-tok-pending @ cc-lookahead-save-pending  !
  tok-kind       @ cc-lookahead-save-tok-kind !
  tok-num        @ cc-lookahead-save-tok-num  !
  tok-str-addr   @ cc-lookahead-save-tok-addr !
  tok-str-len    @ cc-lookahead-save-tok-len  !
  tok-kw-id      @ cc-lookahead-save-tok-kw   ! ;

: cc-lookahead-restore
  cc-lookahead-save-pos      @ cc-src-pos     !
  cc-lookahead-save-line     @ cc-src-line    !
  cc-lookahead-save-pending  @ cc-tok-pending !
  cc-lookahead-save-tok-kind @ tok-kind       !
  cc-lookahead-save-tok-num  @ tok-num        !
  cc-lookahead-save-tok-addr @ tok-str-addr   !
  cc-lookahead-save-tok-len  @ tok-str-len    !
  cc-lookahead-save-tok-kw   @ tok-kw-id      ! ;

\ cc-peek-after-is-colon? ( -- f )
\ Caller has already consumed one token (e.g. IDENT) into tok-* via
\ cc-next-token-keep.  This peeks the FOLLOWING token without consuming.
\ Returns -1 iff that token is the punctuation ':'.
\
\ If the answer is true, the caller should also consume the colon (it has
\ been read into tok-* and cc-tok-pending=0 — i.e. it's "current").
\ If false, this word restores everything so the IDENT remains pending.
: cc-peek-after-is-colon?
  cc-lookahead-save
  cc-next-token
  tok-kind @ tk-punct = tok-num @ [lit] 58 = and
  dup 0= if,
    \ Not a colon — rewind.
    cc-lookahead-restore
  then, ;

\ cc-parse-stmt ( -- )  Dispatch on the leading token.
\ Silently skip any leading storage-class / type-qualifier keywords
\ (static, extern, const, volatile, ...).
: cc-parse-stmt
  cc-skip-storage-quals
  cc-next-token-keep
  cc-tok-is-basic-type-kw? if,
    cc-parse-decl
  else,
    tok-kind @ tk-kw = tok-kw-id @ kw-struct = and if,
      \ `struct TAG ... ;` at stmt scope is always a local declaration
      \ (struct *definition* — `struct TAG { ... };` — is only allowed at top
      \ level).  The 'struct' keyword is the current token and is
      \ already consumed; cc-parse-struct-local-decl reads from here.
      cc-parse-struct-local-decl
    else,
    tok-kind @ tk-kw = tok-kw-id @ kw-return = and if,
      cc-parse-return
    else,
      tok-kind @ tk-kw = tok-kw-id @ kw-if = and if,
        cc-parse-if
      else,
        tok-kind @ tk-kw = tok-kw-id @ kw-while = and if,
          cc-parse-while
        else,
          tok-kind @ tk-kw = tok-kw-id @ kw-for = and if,
            cc-parse-for
          else,
            tok-kind @ tk-kw = tok-kw-id @ kw-do = and if,
              cc-parse-do-while
            else,
            tok-kind @ tk-kw = tok-kw-id @ kw-switch = and if,
              cc-parse-switch
            else,
              tok-kind @ tk-kw = tok-kw-id @ kw-break = and if,
                cc-parse-break-stmt
              else,
                tok-kind @ tk-kw = tok-kw-id @ kw-continue = and if,
                  cc-parse-continue-stmt
                else,
                  tok-kind @ tk-kw = tok-kw-id @ kw-goto = and if,
                    cc-parse-goto-stmt
                  else,
                    tok-kind @ tk-punct = tok-num @ [lit] 123 = and if,
                      cc-parse-compound
                    else,
                      \ Possibly an IDENT followed by ':' — a label definition.
                      \ An IDENT that resolves to a typedef name introduces
                      \ a declaration instead.  Check the symbol table first.
                      tok-kind @ tk-ident = if,
                        \ typedef-led declaration?
                        tok-str-addr @ tok-str-len @ cc-sym-find        ( id-or-neg1 )
                        dup [lit] 0 >= if,
                          dup cc-sym-kind-of sk-typedef = if,
                            \ Resolved typedef: consume IDENT (it IS consumed —
                            \ tok-* still holds it), then parse decl with the
                            \ typedef's encoded base+ptr-depth.
                            cc-sym-val-of                                ( ty )
                            dup ty-base swap ty-ptr                      ( base ptr-depth )
                            cc-parse-decl-with-base
                          else,
                            \ Not a typedef; fall back to label / expr-stmt path.
                            drop
                            tok-str-addr @ tok-str-len @                ( a u )
                            cc-peek-after-is-colon? if,
                              cc-define-label
                            else,
                              2drop
                              cc-putback-token
                              cc-parse-expr-balanced
                              [lit]  59 cc-expect-punct-c
                            then,
                          then,
                        else,
                          \ Symbol not found yet — still might be a forward label.
                          drop
                          tok-str-addr @ tok-str-len @                  ( a u )
                          cc-peek-after-is-colon? if,
                            cc-define-label
                          else,
                            2drop
                            cc-putback-token
                            cc-parse-expr-balanced
                            [lit]  59 cc-expect-punct-c
                          then,
                        then,
                      else,
                        \ Expression statement leading with non-IDENT.
                        cc-putback-token
                        cc-parse-expr-balanced
                        [lit]  59 cc-expect-punct-c
                      then,
                    then,
                  then,
                then,
              then,
            then,
            then,
          then,
        then,
      then,
    then,
    then,
  then, ;

\ Wire the trampoline now that cc-parse-stmt is defined.
' cc-parse-stmt cc-parse-stmt-vec !

```

## 2. Walking the listing

### `if` and `else`

`cc-parse-if` is the cleanest statement parser.  Read it once and
you've seen the pattern that recurs in `while`, `for`, `do-while`,
and `switch`: emit a placeholder branch, parse the body, patch the
placeholder.

The codegen shape is:

```
test rdi, rdi
jz   else-or-end       ; fixup #1
<then-body>
; (if else)
jmp  end               ; fixup #2
else-or-end:           ; patch fixup #1
<else-body>
end:                   ; patch fixup #2 (only when else)
```

`cc-emit-jz-rel32-placeholder` returns the file offset of its
rel32 cell.  We carry it on the data stack across the recursive
`cc-parse-stmt-tramp` call that emits the then-body (the
trampoline preserves data-stack contents).  After the body,
peek for `else`; if present, emit a second placeholder for the
"jump over else" path, patch the first, recurse into the
else-body, patch the second.  If absent, just patch the first.

### Loop helpers and absolute backward branches

`cc-emit-jmp-vaddr`, `cc-emit-jnz-vaddr`, `cc-emit-je-vaddr`
emit conditional and unconditional jumps to *absolute* virtual
addresses.  The rel32 displacement is computed at emit time
from the target vaddr and `cc-base-vaddr + cc-out-pos + 4`.

These live in `110-cc-decl.fth` rather than `090-cc-emit.fth`
because they reference `cc-base-vaddr`, which is defined in
`080-cc-elf.fth`.  Load order: `090` then `080` then `110`.  The
encoders that need `cc-base-vaddr` have to be defined after
`080`'s load, which means they land here.

### Break/continue fixup lists

`while`, `for`, `do-while`, and `switch` each maintain two
linked-list heads — `cc-break-stack-head` and
`cc-continue-stack-head`.  When the parser enters a loop, it
saves the outer heads on the return stack and resets to 0; the
body's `break` and `continue` statements `cc-add-fixup-to-list`
to whichever applies.  When the loop ends,
`cc-walk-and-patch-fixups` walks the list and patches each
fixup's rel32 to the appropriate target vaddr.

This is the same fixup-on-the-stack pattern as Ch 11's `if,`,
generalised to a list because there can be multiple `break`s in
one loop.

### `for` with step rewind

`for` is the most intricate of the loops.  The step expression
appears textually *before* the body in source code, but must
*execute* after the body.  The compiler handles this by:

1. Parsing the init expression normally.
2. Recording `cc-for-step-start = cc-src-pos` at the start of
   the step.
3. Scanning forward at the byte level (not the token level —
   that's why `cc-peek-char` / `cc-next-char` are called
   instead of `cc-next-token-keep`) until the matching `)`.
4. Recording `cc-for-step-end` just before that `)`.
5. Parsing the body normally.
6. *Rewinding* `cc-src-pos` to `cc-for-step-start` and clamping
   `cc-src-len` to `cc-for-step-end` so the lexer naturally
   stops at the `)`.
7. Parsing the step in that windowed source range.
8. Restoring `cc-src-pos` and `cc-src-len`.

The rewind trick is the only place in the compiler where the
lexer state is moved backwards.  It's a careful piece of
state management.

### `switch` with deferred dispatch

`switch` doesn't fit the simple forward-fixup pattern because
the dispatch table can't be emitted until *all* the cases have
been collected.  The compiler's solution:

1. Save the scrutinee in `rbx` (a callee-saved register — so
   nested calls in the body don't trash it).  `cc-emit-push-rbx`
   preserves the outer `rbx`.
2. Emit a forward `jmp` to the dispatch table.  The dispatch
   table doesn't exist yet — we'll patch this later.
3. Parse the body inline, intercepting `case K :` (record
   `(K, body-vaddr)` in `cc-switch-cases-head`) and `default :`
   (record `cc-switch-default-vaddr`) as we go.
4. After the body, emit a final `jmp end-A` (registered in the
   break list).
5. Patch the initial `jmp` to point here.  Emit the dispatch
   chain (`cmp rbx, K ; je body-vaddr` for each case).
6. After the dispatch chain, if there's a default, jump to it;
   otherwise emit a final `jmp end-A`.
7. End-A: walk the break list, patching every fixup to here.
   `pop rbx` restores the outer scrutinee.

The dispatch table walks the case list in *reverse source order*
because the list is built via prepend.  That's fine because
`case` semantics are order-independent (two cases with the same
K is an error anyway).

### Break and continue

`cc-parse-break-stmt` and `cc-parse-continue-stmt` are tiny:
expect `;`, emit a placeholder `jmp`, add the offset to the
break or continue list.

There's no "break depth" tracking — the compiler assumes valid
nesting.  A `break` outside any loop would add a fixup to the
nearest non-loop frame's list and crash when no one walks it.
M2-Planet's source doesn't trigger this.

### Labels and `goto`

C labels are function-local.  The label table is parallel
arrays (same shape as Ch 24's symbol table) capped at 64 per
function.  `cc-label-count` is reset on function entry.

`cc-parse-goto-stmt` consumes `goto IDENT ;` and dispatches:

- If the target label is already defined (`vaddr != 0`), emit
  an absolute backward `jmp` via `cc-emit-jmp-vaddr`.
- If not, emit a forward-`jmp` placeholder and prepend the
  patch offset to the label's `cc-label-fixup-of` list.

`cc-define-label` is the matching definer: it sets the label's
vaddr to the current `cc-out-pos`, then walks the fixup list
patching each placeholder to here.  Duplicate definitions are
caught (status 81).

### The dispatcher

`cc-parse-stmt` is the giant `if, ... else,` chain that
dispatches on the leading token.  Read top-down:

1. Skip storage qualifiers.
2. If basic type keyword (int/char/void/...) → `cc-parse-decl`.
3. If `struct` → `cc-parse-struct-local-decl`.
4. If `return`/`if`/`while`/`for`/`do`/`switch`/`break`/
   `continue`/`goto` → dispatch to the corresponding parser.
5. If `{` → `cc-parse-compound`.
6. If `IDENT` — three subcases:
   - It resolves to a `sk-typedef` → typedef-led declaration via
     `cc-parse-decl-with-base`.
   - Followed by `:` → label definition via `cc-define-label`.
   - Otherwise → expression statement.
7. Anything else → expression statement.

The 2-token-lookahead for `IDENT :` reuses
`cc-peek-after-is-colon?` (defined just above the dispatcher).
Its save-and-restore discipline is the same pattern we saw in
Ch 29's `cc-peek-fnptr?` with different state slots so they
don't collide.

The final `' cc-parse-stmt cc-parse-stmt-vec !` is the
trampoline-wiring move from Part III's pattern book: once the
real word exists, point the vec at it so earlier code that
called `cc-parse-stmt-tramp` now resolves to the right
function.

## Try it

```sh
./build.sh
./test.sh
tests/cc/stage-a-check.sh
```

`tests/cc/G2.c` exercises nested `if`/`else`; `G5.c` exercises
`while` and `for` in the same body; `G6a.c` exercises `do-while`
with `break` and `continue`; `G6b.c` exercises `goto` and labels;
`G13.c` exercises `switch` with `case` fall-through and `default`.
The big M2-Planet monolith exercises all of them at once.

## Exercises

1. The `for`-step rewind is a unique trick.  Could `for` be
   compiled by recording the step's token range instead of
   byte range?  What would change?

2. Switch dispatch is linear in the number of cases.  At what
   case count does a binary-search or jump-table approach
   start to pay?  How would the codegen change?

3. `break outside any loop` is undefined here.  Add a depth
   counter and emit a compile-time error when it underflows.
   How many bytes does the check cost?

4. Labels are function-local.  M2-Planet's monolith has 891
   global references but how many gotos?  Grep the source and
   estimate.

5. The if/while/for/do-while/switch parsers all save and
   restore break/continue heads via `>r >r ... r> r>`.  Could
   you factor this into a single helper?  What would the
   helper's interface look like?

## Takeaways

- Every loop uses the same shape: save outer fixup heads, parse
  the body, walk the break list at the end, walk the continue
  list at the appropriate point.  The variation is purely in
  *when* each walk fires.
- The `for`-step rewind is the only place the lexer's source
  position moves backwards.  Everything else flows
  monotonically forward.
- The `cc-parse-stmt` dispatcher is the deepest nested `if`
  chain in the codebase — fourteen branches.  The Forth seed
  has no `case`, so this is what 14-way dispatch costs.

Next: Chapter 31 — Functions: Parameters, Locals, Scope.
