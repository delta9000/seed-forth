# Chapter 30 — Statements: `if`, `while`, `for`, `switch`, `break`, `continue`, `goto`

```text
Missing capability: expressions cannot yet become statement-level control flow.
New pattern: emit jumps with placeholders and patch them when block, loop, switch, or label targets are known.
Artifact after this chapter: codegen for blocks, branches, loops, switch, return, break, continue, goto.
Proof link: Stage-A control flow uses emit, remember, patch at statement scale.
```

An expression leaves a value in `rdi`.  A statement decides what
runs next, and usually the place it needs to jump to has not been
emitted yet.  `if` must skip a then-body it hasn't parsed; `while`
must leave a loop whose end is still ahead; `break` must reach the
end of whichever loop or switch encloses it.

The answer in every case is Ch 11's emit-remember-patch pattern,
now with x86-64 `jz` / `jmp` rel32 placeholders in `cc-out-buf`
instead of Forth `0branch` / `branch` cells.  This chapter covers
all of `112-cc-stmt.fth` (828 lines): the `cc-parse-stmt` dispatcher
and the parsers it calls.  Three extensions let the pattern cover
all of C's statements.  Per-loop `break` / `continue` fixup lists
are saved across nested loops on the return stack.  A `for` loop
records its step expression's source range and re-parses it after
the body.  A `switch` emits its body first and its dispatch table
afterwards, from a linked list of cases.

Function definitions and parameters (`114-cc-func.fth`) and enums,
typedefs, file-scope globals, and the top-level driver
(`116-cc-prog.fth`) are Ch 31's.

The sections follow the source.  §1 is the statement forward reference,
compound blocks, and `if`.  §§2–3 are the loop machinery (absolute
backward jumps and the fixup lists), §§4–6 the loops and `switch`,
§§7–8 `break`, `continue`, labels, and `goto`, and §9 the
dispatcher.

## 1. The forward reference, compound blocks, and `if`

Statement parsers call each other recursively (an `if` body is a
statement), but `cc-parse-stmt` can only be defined after all of
them, since it calls each one.  So they call a deferred word
(Ch 12), `cc-parse-stmt-fwd`, which §9 fills in once `cc-parse-stmt`
exists; Ch 31's function body calls `cc-parse-stmt` directly.
`cc-parse-compound` is the first caller: it pushes a scope, parses
statements until `}`, and pops the scope, so locals declared in a
block disappear at its end.  The file header comes first; it names
`110-cc-decl.fth` as the file this one builds on, for the local
declarations and `return` that a block can contain.

```forth file=112-cc-stmt.fth
\ 112-cc-stmt.fth — statement parser for the C-subset compiler.
\
\ Parses compound blocks, if, while, for, do/while, switch, break, continue,
\ labels and goto, and expression statements.  Each emits jumps with rel32
\ placeholders and patches them once their targets are known.
\
\ Depends on 110-cc-decl.fth (local declarations, return) and everything it
\ depends on.

\ ===========================================================================
\ Statement dispatch
\ ===========================================================================
\ cc-parse-stmt is mutually recursive with every statement that has a body
\ (compound, if, while, for, do, switch), and those come first, so they call
\ it through this deferred word (010-lib.fth), filled in once it is defined.

defer cc-parse-stmt-fwd

\ cc-parse-compound ( -- )  '{' (stmt | decl)* '}'
\ Caller has already consumed '{'.  Pushes/pops a scope so locals declared
\ inside the block are discarded at end-of-block.
: cc-parse-compound
  cc-scope-push
  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [char] } = and 0=
  while,
    cc-putback-token
    cc-parse-stmt-fwd
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
  lparen cc-expect-punct-c
  cc-parse-expr
  [char] ) cc-expect-punct-c

  cc-value-test-fwd
  cc-emit-jz-rel32-placeholder                    ( fixup-jz )

  cc-parse-stmt-fwd                             \ then-body

  \ Optional else.
  cc-next-token-keep
  tok-kind @ tk-kw = tok-kw-id @ kw-else = and if,
    \ jmp end ; patch jz to here ; else-body ; patch jmp to here.
    cc-emit-jmp-rel32-placeholder                 ( fixup-jz fixup-jmp )
    swap cc-patch-rel32-to-here                   ( fixup-jmp )
    cc-parse-stmt-fwd                           \ else-body
    cc-patch-rel32-to-here                        ( -- )
  else,
    cc-putback-token
    cc-patch-rel32-to-here                        ( -- )
  then, ;

```

`cc-parse-if` is the simplest statement parser, and its shape
recurs in `while`, `for`, `do-while`, and `switch`: emit a
placeholder branch, parse the body, patch the placeholder.  The
emitted code is:

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
rel32 cell in `cc-out-buf`.  We carry it on the data stack across
the recursive `cc-parse-stmt-fwd` call that emits the then-body;
a statement's parse leaves the data stack as it found it.  After the body, peek
for `else`.  If it is there, emit a second placeholder for the
jump over the else-body, patch the first, parse the else-body, and
patch the second.  If not, patch the first and stop.

## 2. Loop helpers and absolute backward branches

```forth file=112-cc-stmt.fth
\ ===========================================================================
\ Loop helpers
\ ===========================================================================
\ cc-emit-jmp-vaddr lives here (rather than in 090-cc-emit.fth) alongside the
\ loop constructs that call it.  cc-here-vaddr (080) loads before 090, so the
\ split is organizational, not a load-order dependency.

\ cc-emit-jmp-vaddr ( target-vaddr -- )  Emit `E9 <rel32>` to absolute target.
\ After emitting the E9 opcode, cc-out-pos points at the rel32 slot's first
\ byte; the address of the next instruction is cc-here-vaddr + 4.
: cc-emit-jmp-vaddr                               ( target-vaddr -- )
  [lit] 233 cc-emit-byte                          \ E9 opcode
  cc-here-vaddr [lit] 4 + -                       \ rel32
  cc-emit-4le ;

\ cc-emit-jnz-vaddr ( target-vaddr -- )  Emit `0F 85 <rel32>` to absolute target.
\ After emitting `0F 85`, cc-out-pos points at the rel32 slot's first byte.
: cc-emit-jnz-vaddr                               ( target-vaddr -- )
  [lit]  15 cc-emit-byte                          \ 0F prefix
  [lit] 133 cc-emit-byte                          \ 85 opcode
  cc-here-vaddr [lit] 4 + -                       \ rel32
  cc-emit-4le ;

\ cc-emit-je-vaddr ( target-vaddr -- )  Emit `0F 84 <rel32>` to absolute
\ target.  Mirror of cc-emit-jnz-vaddr; used by switch dispatch.
: cc-emit-je-vaddr                                ( target-vaddr -- )
  [lit]  15 cc-emit-byte                          \ 0F prefix
  [lit] 132 cc-emit-byte                          \ 84 opcode
  cc-here-vaddr [lit] 4 + -                       \ rel32
  cc-emit-4le ;

```

`cc-emit-jmp-vaddr`, `cc-emit-jnz-vaddr`, `cc-emit-je-vaddr`
emit conditional and unconditional jumps to *absolute* virtual
addresses.  The rel32 displacement is computed at emit time
from the target vaddr and `cc-here-vaddr + 4` (Ch 25), the address
of the next instruction.

These live in `112-cc-stmt.fth` rather than `090-cc-emit.fth`
because they belong with the loop and control-flow constructs
that call them, not with the primitive instruction encoders.
They read `cc-here-vaddr` (`080-cc-elf.fth`), which loads before
`090`, so the placement is a layering choice, not a load-order
requirement.

## 3. Break/continue fixup lists

`if` has exactly one pending jump per branch, so the data stack
holds it.  A loop can contain any number of `break`s, so each one
is a node in a linked list instead:

```forth file=112-cc-stmt.fth
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
  cc-here-vaddr
  cc-walk-and-patch-to-vaddr ;

```

Two list heads,
`cc-break-stack-head` and `cc-continue-stack-head`, belong to the
innermost loop.  On entry the parser saves the outer heads on the
return stack and zeroes them.  Each `break` or `continue` in the
body calls `cc-add-fixup-to-list` on the matching head.  When the
loop ends, `cc-walk-and-patch-fixups` (or
`cc-walk-and-patch-to-vaddr`, for a known target) patches every
node's rel32.

Each loop also snapshots `cc-switch-depth` into
`cc-loop-switch-depth` (Ch 29 §7), so a `continue` buried inside
a `switch` knows how many scrutinee pushes stand between it and
the loop it continues.

## 4. `while` and `for` (with step rewind)

`cc-parse-while` is the plainest loop.  It records the top vaddr,
parses the condition, emits a `jz` placeholder, parses the body,
jumps back to the top, and patches the `jz`.  The outer fixup heads
go onto the return stack on entry and come back on exit, so nested
loops never see each other's fixups.

```forth file=112-cc-stmt.fth
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
  \ Save outer break/continue list heads + loop switch-depth on rstack.
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  cc-loop-switch-depth   @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  cc-switch-depth @ cc-loop-switch-depth !

  lparen cc-expect-punct-c
  cc-here-vaddr                                   ( top-vaddr )
  cc-parse-expr
  [char] ) cc-expect-punct-c
  cc-value-test-fwd
  cc-emit-jz-rel32-placeholder                    ( top fixup-end )

  \ Park top-vaddr on rstack so it survives the body parse.
  swap >r                                         ( fixup-end ; R: ... top )

  cc-parse-stmt-fwd                             \ body

  \ Continue target = top-vaddr.  Walk continue list (no-op if empty).
  cc-continue-stack-head @ r@ cc-walk-and-patch-to-vaddr

  \ Emit jmp top, then patch jz fixup.
  r> cc-emit-jmp-vaddr                            ( fixup-end )
  cc-patch-rel32-to-here

  \ Break target = here.  Walk break list (no-op if empty).
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

```

`cc-parse-for` has the same skeleton with one complication.  The
step expression appears in the source *before* the body but must
run *after* it.  The parser handles this in eight moves:

1. Parse the init expression normally.
2. Record `cc-for-step-start = cc-src-pos` at the start of the
   step.
3. Scan forward to the matching `)` at the byte level, with
   `cc-peek-char` / `cc-next-char` rather than the tokenizer.
4. Record `cc-for-step-end` just before that `)`.
5. Parse the body.
6. Rewind `cc-src-pos` to `cc-for-step-start` and clamp
   `cc-src-len` to `cc-for-step-end`, so the lexer stops at the
   `)` as if it were end of file.
7. Parse the step inside that window.
8. Restore `cc-src-pos` and `cc-src-len`.

```forth file=112-cc-stmt.fth
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
  cc-for-top-vaddr @ >r cc-for-end-fixup @ >r
  cc-for-step-start @ >r cc-for-step-end @ >r
  cc-scope-push
  lparen cc-expect-punct-c

  \ --- Init (optional); declaration scope ends with this loop. ---
  cc-next-token-keep
  [char] ; cc-tok-punct? 0= if,
    cc-target-lp64 @ if, cc-native-type-start-fwd else, [lit] 0 then, if,
      cc-native-decl-fwd
    else,
      cc-putback-token cc-parse-expr [char] ; cc-expect-punct-c
    then,
  then,

  \ Save outer break/continue heads + loop switch-depth on rstack (after
  \ init, since init runs outside the loop and shouldn't see this loop's
  \ break/continue).
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  cc-loop-switch-depth   @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  cc-switch-depth @ cc-loop-switch-depth !

  \ Top of loop.
  cc-here-vaddr                                   ( top-vaddr )

  \ --- Cond (optional) ---
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ; = and if,
    \ ';' — empty cond; emit `mov rdi, 1` for unconditional truth.
    [lit] 1 cc-emit-mov-rdi-imm32
  else,
    cc-putback-token
    cc-parse-expr
    [char] ; cc-expect-punct-c
  then,

  cc-value-test-fwd
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
    cc-next-token-keep
    lparen cc-tok-punct? if, 1+ then,
    [char] ) cc-tok-punct? if, 1- then,
  repeat,
  drop                                            ( -- )
  \ cc-src-pos is now just past ')'.  step-end = position of ')'.
  cc-src-pos @ 1- cc-for-step-end !

  \ --- Body ---
  cc-parse-stmt-fwd

  \ Continue target = HERE (just before step).  Walk continue list.
  cc-continue-stack-head @ cc-walk-and-patch-fixups

  \ --- Re-parse step at recorded range ---
  \ Save current lexer state, set pos := step-start, len := step-end (so the
  \ tokenizer naturally hits EOF at the close-paren).  After parsing, restore.
  cc-lex-state-size cc-alloc dup cc-lex-mark >r
  cc-src-len @ >r
  cc-for-step-end @ cc-src-len !
  cc-for-step-start @ cc-src-pos !
  \ Clear any pending putback before re-tokenising at the new position.
  [lit] 0 cc-tok-pending !
  \ Whitespace/comments alone do not make an omitted step an expression.
  cc-skip-ws-and-comments
  cc-src-pos @ cc-src-len @ < if,
    cc-parse-expr
  then,
  \ Restore lexer state.
  r> cc-src-len !
  r> cc-lex-reset

  \ Emit jmp top.
  cc-for-top-vaddr @ cc-emit-jmp-vaddr

  \ Patch jz fixup to current position.
  cc-for-end-fixup @ cc-patch-rel32-to-here

  \ Break target = here.  Walk break list (no-op if empty).
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    !
  cc-scope-pop
  r> cc-for-step-end ! r> cc-for-step-start !
  r> cc-for-end-fixup ! r> cc-for-top-vaddr ! ;

```

This is the only place the compiler moves the lexer backwards to
re-parse source it has already passed.  The lookahead peeks
(`cc-peek-fnptr?` in Ch 29, `cc-peek-after-is-colon?` in §9, and
the top-level peek in Ch 31) also move it back, with
`cc-lex-mark` / `cc-lex-reset` (Ch 23 §7), but they undo a read; the
step rewind replays code.

**tri.c at this stage.**  `main` in tri.c has one `for` and one `if`,
and between them three jumps.  With tri.c compiled to `/tmp/cc-out`
(Ch 21), list them:

```sh
objdump -D -b binary -m i386:x86-64 -M intel \
    --start-address=0x312 --stop-address=0x4b2 /tmp/cc-out | grep -E 'j[a-z]+ '
```

```
 34d:   0f 84 fe 00 00 00       je     0x451
 44c:   e9 d0 fe ff ff          jmp    0x321
 490:   0f 84 1c 00 00 00       je     0x4b2
```

Each `je` was emitted by `cc-emit-jz-rel32-placeholder` as `0f 84
00 00 00 00` and filled in by `cc-patch-rel32-to-here` once its target
existed.  The loop's `je` at 0x34d got 0xfe, measured from 0x353,
the loop's exit at 0x451.  The `if` on line 20 has no `else`, so
it has one fixup, and 0x1c is the 28-byte `return t.stars;` it
skips.  The `jmp` at 0x44c goes back to 0x321, the top of the
condition, through `cc-emit-jmp-vaddr`.  Just before it, at
0x431–0x44b, is `r = r + 1`: the step comes after the body
(0x353–0x430) even though the source puts it before, which is the
rewind above at work.

## 5. `do`/`while`

```forth file=112-cc-stmt.fth
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
  \ Save outer break/continue heads + loop switch-depth.
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  cc-loop-switch-depth   @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  cc-switch-depth @ cc-loop-switch-depth !

  \ Record top-vaddr for the backward jnz.
  cc-here-vaddr >r                                ( ; R: ... top )

  cc-parse-stmt-fwd                             \ body

  \ Continue target = HERE (just before cond test).
  cc-continue-stack-head @ cc-walk-and-patch-fixups

  \ Parse 'while ( expr ) ;'
  kw-while cc-expect-kw-id
  lparen cc-expect-punct-c
  cc-parse-expr
  [char] ) cc-expect-punct-c
  [char] ; cc-expect-punct-c

  cc-value-test-fwd
  r> cc-emit-jnz-vaddr                            \ jnz top

  \ Break target = here.
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

```

`cc-parse-do-while` is the inverted shape: emit the top label,
parse the body, parse `while ( EXPR )`, then a conditional jump
*backward* to the top if the test is non-zero, ending with a
forward fall-through.  No forward placeholder is needed for the
top, since the body always executes once.  `break` and
`continue` work the same way as in `while`: their fixup-list
heads are saved on entry, restored on exit.

## 6. `switch` with deferred dispatch

`switch` doesn't fit the single-placeholder shape, because the
dispatch table can't be emitted until every `case` has been seen.
The compiler emits the body first and the table after it.  The
layout comment and the case list come first:

```forth file=112-cc-stmt.fth
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

```

Each `case` prepends a 24-byte node `{ K, body-vaddr, next }`, so
`cc-emit-switch-dispatch` emits its `cmp rbx, K ; je body` pairs in
reverse source order.  The order doesn't matter: C forbids two
cases with the same `K`.

`cc-parse-switch` then runs in seven steps:

1. Evaluate the scrutinee and move it into `rbx`, a callee-saved
   register, so calls in the body don't clobber it.
   `cc-emit-push-rbx` preserves the outer `rbx` first.
2. Emit a forward `jmp` to the dispatch table, which doesn't exist
   yet.
3. Parse the body inline, intercepting `case K :` (record
   `(K, body-vaddr)`) and `default :` (record
   `cc-switch-default-vaddr`).  `K` is a constant expression, read by
   Ch 28's `cc-parse-const`: `case 5:`, and also `case 'x':`,
   `case -1:`, `case T_PLUS:` with an enum constant, or
   `case BASE + 1:` with a macro.  A label not followed by `:` is code
   170.  pnut's lexer and code generator switch on enum constants and
   characters throughout (`tests/cc/P6-case-labels.c`).
4. After the body, emit a `jmp end-A` and register it in the break
   list.
5. Patch the initial `jmp` to here and emit the dispatch chain.
6. Jump to the default if there is one; otherwise emit another
   `jmp end-A`.
7. At end-A, walk the break list and emit `pop rbx`.

```forth file=112-cc-stmt.fth
\ cc-parse-switch ( -- )  'switch' already consumed by cc-parse-stmt.
\ Grammar:  switch ( expr ) { (case CONSTANT : | default : | stmt)* }
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
  lparen cc-expect-punct-c
  cc-parse-expr                                   \ rdi = scrutinee
  cc-last-expr-type @ cc-value-integer-use-fwd
  [char] ) cc-expect-punct-c

  \ Save outer rbx, then move scrutinee into rbx.  Mark the switch open so
  \ return/continue/goto inside the body emit a balancing pop (see
  \ cc-emit-switch-unwind).
  cc-emit-push-rbx
  cc-emit-mov-rbx-rdi
  [lit] 1 cc-switch-depth +!

  \ Forward jmp to the dispatch table (emitted after the body).
  cc-emit-jmp-rel32-placeholder                   ( jmp-to-dispatch )
  >r

  \ '{' (case|default|stmt)* '}'
  [char] { cc-expect-punct-c
  cc-target-lp64 @ if, cc-scope-push then,

  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [char] } = and 0=
  while,
    \ Three sub-cases: 'case' CONSTANT ':', 'default' ':', or generic stmt.
    tok-kind @ tk-kw = tok-kw-id @ kw-case = and if,
      \ 'case' has been consumed; the label is a constant expression
      \ (cc-parse-const): a number, a character, an enum constant, -1 ...
      cc-parse-const                              ( K )
      cc-next-token-keep
      [char] : cc-tok-punct? 0= if,
        [lit] 170 cc-die
      then,
      cc-here-vaddr                               ( K body-vaddr )
      cc-add-switch-case
    else,
      tok-kind @ tk-kw = tok-kw-id @ kw-default = and if,
        \ 'default' has been consumed.
        [char] : cc-expect-punct-c
        cc-here-vaddr
        cc-switch-default-vaddr !
      else,
        \ Generic statement — put back, parse it as one.
        cc-putback-token
        cc-parse-stmt-fwd
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

  \ Restore outer rbx; the switch is closed again.
  cc-emit-pop-rbx
  cc-switch-depth @ 1- cc-switch-depth !

  \ Restore outer state.
  r> cc-break-stack-head     !
  r> cc-switch-default-vaddr !
  r> cc-switch-cases-head    !
  cc-target-lp64 @ if, cc-scope-pop then, ;

```

Exits that bypass end-A (`return`, `continue`, `goto`) balance the
`push rbx` themselves through `cc-emit-switch-unwind` (Ch 29 §7),
using the `cc-switch-depth` counter that brackets the body parse.

## 7. Break and continue

```forth file=112-cc-stmt.fth
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
  [char] ; cc-expect-punct-c
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-break-fixup ;

\ cc-parse-continue-stmt ( -- )  "continue" already consumed.
\ Unwind the scrutinee pushes of any switches between here and the loop
\ being continued before jumping out of them.
: cc-parse-continue-stmt
  [char] ; cc-expect-punct-c
  cc-switch-depth @ cc-loop-switch-depth @ - cc-emit-switch-unwind
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-continue-fixup ;

```

`cc-parse-break-stmt` and `cc-parse-continue-stmt` are tiny:
expect `;`, emit a placeholder `jmp`, add the offset to the
break or continue list.  `continue` additionally calls
`cc-emit-switch-unwind` (Ch 29 §7) with the number of switches
it's jumping out of, balancing each one's scrutinee `push rbx`.
`break` never needs this: it targets the innermost loop or
switch end label, so it never crosses a scrutinee push.

Nothing tracks break depth; the compiler assumes valid nesting.  A
`break` outside any loop would add a fixup to a list that no loop
walks.  M2-Planet's source never does this.

## 8. Labels and `goto`

C labels are function-local.  The label table is four parallel
arrays, the same shape as Ch 24's symbol table, indexed with
`cell[]` and searched with `cc-name-find` (Ch 21) just as the symbol
table is.  It holds 64 labels per function (a 65th dies with code
171, through `cc-check-cap`) and is reset on function entry.  Each
entry's payload is a vaddr (0 while undefined) and a list of
pending `goto` fixups.

```forth file=112-cc-stmt.fth
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
create cc-label-switch-depth cc-label-cap [lit] 8 * allot
variable cc-label-count

\ Each table is indexed with cell[] (030).
: cc-label-vaddr-of   cc-label-vaddr cell[] @ ;              \ ( id -- vaddr )
: cc-label-set-vaddr  cc-label-vaddr cell[] ! ;              \ ( v id -- )
: cc-label-fixups     cc-label-fixup cell[] ;                \ ( id -- list-cell )

\ cc-label-find ( name-addr name-len -- id-or-neg1 )  Newest first, like
\ cc-sym-find; cc-name-find (030) does the walk.
: cc-label-find
  cc-label-name-addr cc-label-name-len cc-label-count @ cc-name-find ;

\ cc-label-create ( name-addr name-len -- id )  Append a new label entry.
\ Initial vaddr=0 (undefined), fixup=0 (no forward refs yet).
: cc-label-create                                 ( a u -- id )
  cc-label-count @ 1+ cc-label-cap [lit] 171 cc-check-cap
  cc-label-count @                                ( a u id )
  >r                                              \ R: id
  r@ cc-label-name-len  cell[] !                  \ store len
  r@ cc-label-name-addr cell[] !                  \ store addr
  [lit] 0 r@ cc-label-set-vaddr                   \ vaddr := 0
  [lit] 0 r@ cc-label-fixups !
  [lit] 0 r@ cc-label-switch-depth cell[] !                    \ fixup-list := 0
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
\ Dies with code 172 on a duplicate definition.
: cc-define-label                                 ( a u -- )
  cc-label-find-or-create                         ( id )
  \ Reject duplicates.
  dup cc-label-vaddr-of [lit] 0 <> if,
    [lit] 172 cc-die
  then,
  \ Set vaddr.
  >r                                              ( ; R: id )
  cc-here-vaddr r@ cc-label-set-vaddr
  cc-switch-depth @ r@ cc-label-switch-depth cell[] !
  \ Native forward gotos use end-of-function switch-stack trampolines.
  cc-target-lp64 @ if, r> drop else,
    r> cc-label-fixups @ cc-walk-and-patch-fixups
  then, ;

```

`cc-define-label` binds the label to the current output position,
then walks its fixup list and patches every forward `goto` to here.
A second definition of the same name dies with code 172.

`cc-parse-goto-stmt` is the other half.  If the label already has a
vaddr, it emits an absolute backward `jmp` via `cc-emit-jmp-vaddr`.
Otherwise it emits a placeholder and pushes its offset onto the
label's fixup list with `cc-add-fixup-to-list` (Ch 26), the same
word `break` and `continue` use:

```forth file=112-cc-stmt.fth
\ cc-parse-goto-stmt ( -- )  "goto" already consumed.  Grammar:  goto IDENT ;
\
\ If the target label is already defined, emit an absolute backward jmp.
\ Otherwise emit a forward-jmp placeholder and prepend its rel32-fixup-offset
\ to the label's fixup list (resolved when the label is defined).
\ Adjust saved switch registers to the destination's lexical depth.
: cc-native-goto-adjust ( source-depth target-depth -- )
  - dup 0< if,
    [lit] 0 swap -
    begin, dup while, cc-emit-push-rbx 1- repeat, drop
  else, cc-emit-switch-unwind then, ;
: cc-native-goto-fixup ( label-id patch-offset -- )
  [lit] 24 cc-alloc >r r@ !
  cc-switch-depth @ r@ [lit] 8 + !
  dup cc-label-fixups @ r@ [lit] 16 + !
  r> swap cc-label-fixups ! ;
: cc-native-finish-gotos
  [lit] 0
  begin, dup cc-label-count @ < while,
    dup cc-label-fixups @
    begin, dup while,
      over cc-label-vaddr-of 0= if, [lit] 174 cc-die then,
      dup @ cc-patch-rel32-to-here
      dup >r [lit] 8 + @ over cc-label-switch-depth cell[] @
      r> swap >r swap r>
      cc-native-goto-adjust
      over cc-label-vaddr-of cc-emit-jmp-vaddr
      [lit] 16 + @
    repeat, drop 1+
  repeat, drop ;

: cc-parse-goto-stmt
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 173 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-label-find-or-create   ( id )
  cc-target-lp64 @ if,
    dup cc-label-vaddr-of if,
      cc-switch-depth @ over cc-label-switch-depth cell[] @
      cc-native-goto-adjust
      cc-label-vaddr-of cc-emit-jmp-vaddr
    else,
      cc-emit-jmp-rel32-placeholder cc-native-goto-fixup
    then,
    [char] ; cc-expect-punct-c exit,
  then,

  \ Unwind any open switch scrutinees before jumping (assumes the label is
  \ not inside any switch — a goto to a label inside any switch is unsupported).
  cc-switch-depth @ cc-emit-switch-unwind

  dup cc-label-vaddr-of                           ( id vaddr )
  dup [lit] 0 <> if,
    \ Backward jump to known target.
    cc-emit-jmp-vaddr                             ( id )
    drop                                          ( -- )
  else,
    drop                                          ( id )
    \ Forward ref: emit placeholder, prepend offset to label's fixup list.
    cc-emit-jmp-rel32-placeholder                 ( id fixup-offset )
    swap cc-label-fixups cc-add-fixup-to-list     ( -- )
  then,
  [char] ; cc-expect-punct-c ;

```

Either way, `goto` first unwinds every open switch scrutinee, which
assumes the target label is not inside any `switch`.  A `goto` into
a switch is unsupported; it would need the scrutinee re-pushed, and
M2-Planet's source never does it.

## 9. The dispatcher

A statement that starts with an identifier might be a label
(`done:`) or an expression (`done = 1;`).  Telling them apart needs
the token *after* the identifier, and the putback buffer
(`cc-tok-pending`) holds only one.  So `cc-peek-after-is-colon?`
marks the lexer state in `cc-peek-mark`, reads one token, and resets
to the mark unless that token is `:`.  This is the same mark-and-reset
discipline as Ch 29's `cc-peek-fnptr?`, with the same buffer: neither
peek can start while the other is reading.

```forth file=112-cc-stmt.fth
\ ===========================================================================
\ One-token lookahead used to detect "IDENT :" label definitions.
\ ===========================================================================
\ The putback layer (cc-tok-pending) only buffers one token.  To peek TWO
\ tokens ahead we mark the lexer state in cc-peek-mark, read one fresh token,
\ and either commit (if it confirms a label) or reset to the mark (if not).

\ cc-peek-after-is-colon? ( -- f )
\ Caller has already consumed one token (e.g. IDENT) into tok-* via
\ cc-next-token-keep.  This peeks the FOLLOWING token without consuming.
\ Returns -1 iff that token is the punctuation ':'.
\
\ If the answer is true, the caller should also consume the colon (it has
\ been read into tok-* and cc-tok-pending=0 — i.e. it's "current").
\ If false, this word restores everything so the IDENT remains pending.
: cc-peek-after-is-colon?
  cc-peek-mark cc-lex-mark
  cc-next-token
  tok-kind @ tk-punct = tok-num @ [char] : = and
  dup 0= if,
    \ Not a colon — rewind.
    cc-peek-mark cc-lex-reset
  then, ;

```

The dispatcher itself is a list of cases, one line per kind of
statement.  Each line tests the current token with Ch 27's
`cc-tok-kw?` or `cc-tok-punct?` and, if it matches, runs that
statement's parser and returns with `exit,` (Ch 11):

1. Skip storage qualifiers, noting `static` (Ch 29 §2).
2. A lone `;` is the empty statement: nothing to do.  (pnut writes
   `while (cond);` and `;;`.)
3. A basic type keyword (int/char/void/...) → `cc-parse-decl`; `enum
   TAG` → the same engine with type `int`.
4. `struct` → `cc-parse-struct-local-decl`.
5. `return`/`if`/`while`/`for`/`do`/`switch`/`break`/`continue`/
   `goto` → the corresponding parser.
6. `{` → `cc-parse-compound`.
7. An `IDENT` → `cc-parse-ident-stmt`, which has three subcases:
   - it resolves to an `sk-typedef` → a typedef-led declaration
     via `cc-parse-decl-with-base`;
   - it is followed by `:` → a label, via `cc-define-label`;
   - otherwise → an expression statement.
8. Anything else → an expression statement, `cc-parse-expr-stmt`.

A table from keyword to handler would do the same job, but ten
keywords with one caller don't need a data structure: the flat list
shows every statement head in the order they are tried, and each
handler's name appears where it is called.  The last line fills in
`cc-parse-stmt-fwd`, so every earlier call to it (from §1 to §6) now
reaches the finished word.

```forth file=112-cc-stmt.fth
\ cc-parse-expr-stmt ( -- )  An expression statement `e ;`.  The token
\ that starts it has been read, so it goes back first.
: cc-parse-expr-stmt
  cc-putback-token
  cc-parse-expr
  [char] ; cc-expect-punct-c ;

\ cc-parse-ident-stmt ( -- )  A statement that starts with an identifier:
\ a declaration if the name is a typedef, a label definition if a ':'
\ follows, an expression statement otherwise.
: cc-parse-ident-stmt
  tok-str-addr @ tok-str-len @ cc-sym-find        ( id | -1 )
  dup 0< 0= if,
    dup cc-sym-kind-of sk-typedef = if,
      \ Resolved typedef: the IDENT is consumed (tok-* still holds it);
      \ parse the declaration with the typedef's encoded base+ptr-depth.
      cc-sym-val-of                               ( ty )
      dup ty-base swap ty-ptr                     ( base ptr-depth )
      cc-parse-decl-with-base exit,
    then,
  then,
  drop
  \ Not a typedef (or not found yet — it may be a forward label).
  tok-str-addr @ tok-str-len @                    ( a u )
  cc-peek-after-is-colon? if,
    cc-define-label
    cc-target-lp64 @ if, cc-parse-stmt-fwd then,
    exit,
  then,
  2drop
  cc-parse-expr-stmt ;

\ cc-parse-stmt ( -- )  Dispatch on the leading token: one line per kind of
\ statement, each returning with exit, once its parser has run.  Silently
\ skip any leading storage-class / type-qualifier keywords (static,
\ extern, const, volatile, ...).  A lone ';' is the empty statement, and
\ `enum TAG x;` declares an int.
: cc-parse-stmt
  cc-skip-storage-quals
  cc-next-token-keep
  cc-target-lp64 @ if,
    kw-case cc-tok-kw? if,
      cc-switch-depth @ 0= if, [lit] 170 cc-die then,
      cc-parse-const [char] : cc-expect-punct-c
      cc-here-vaddr cc-add-switch-case cc-parse-stmt-fwd exit,
    then,
    kw-default cc-tok-kw? if,
      cc-switch-depth @ 0= if, [lit] 170 cc-die then,
      [char] : cc-expect-punct-c
      cc-here-vaddr cc-switch-default-vaddr ! cc-parse-stmt-fwd exit,
    then,
    cc-native-type-start-fwd kw-typedef cc-tok-kw? or if,
      cc-native-decl-fwd exit,
    then,
  then,
  [char] ;    cc-tok-punct? if, exit, then,           \ the empty statement
  cc-tok-is-basic-type-kw? if, cc-parse-decl exit, then,
  kw-enum     cc-tok-kw? if,
    cc-skip-enum-tag  ty-int [lit] 0 cc-parse-decl-with-base exit,
  then,
  \ `struct TAG ... ;` at stmt scope is always a local declaration (a struct
  \ *definition* — `struct TAG { ... };` — is only allowed at top level).
  \ The 'struct' keyword is the current token and is already consumed;
  \ cc-parse-struct-local-decl reads from here.
  kw-struct   cc-tok-kw? if, cc-parse-struct-local-decl exit, then,
  kw-return   cc-tok-kw? if, cc-parse-return            exit, then,
  kw-if       cc-tok-kw? if, cc-parse-if                exit, then,
  kw-while    cc-tok-kw? if, cc-parse-while             exit, then,
  kw-for      cc-tok-kw? if, cc-parse-for               exit, then,
  kw-do       cc-tok-kw? if, cc-parse-do-while          exit, then,
  kw-switch   cc-tok-kw? if, cc-parse-switch            exit, then,
  kw-break    cc-tok-kw? if, cc-parse-break-stmt        exit, then,
  kw-continue cc-tok-kw? if, cc-parse-continue-stmt     exit, then,
  kw-goto     cc-tok-kw? if, cc-parse-goto-stmt         exit, then,
  [char] {    cc-tok-punct? if, cc-parse-compound       exit, then,
  tok-kind @ tk-ident = if, cc-parse-ident-stmt exit, then,
  cc-parse-expr-stmt ;

\ Fill in the forward reference now that cc-parse-stmt is defined.
' cc-parse-stmt is cc-parse-stmt-fwd
```

## Try it

**Small check:** choose one fixture below and trace the emitted
placeholder jumps and patches.

**Layer check:** run the root unit suite and the focused C fixtures.

```sh
./build.sh
./test.sh
```

**Bootstrap relevance:** Stage-A runs all statement forms in the
large M2-Planet monolith, including nested control flow and labels.
One statement path it never reaches has its own gate:
`tests/cc/B-switch-continue.c` runs a `continue` that escapes a
`switch` body.  Without the pop that `cc-emit-switch-unwind` emits,
each iteration would leak the scrutinee's `push rbx`.  M2-Planet's
source never exits a switch that way, so Stage-A cannot see this
path; the gate is the only check on the unwind.

```sh
tests/cc/stage-a-check.sh
```

The fixtures for the small check are:

`tests/cc/G2.c` exercises nested `if`/`else`; `G5.c` exercises
`while` and `for` in the same body; `G6a.c` exercises `do-while`
with `break` and `continue`; `G6b.c` exercises `goto` and labels;
`G13.c` exercises `switch` with `case` fall-through and `default`.
The big M2-Planet monolith exercises all of them at once.

## Exercises

1. **★★ Trace.** The `for`-step rewind is a unique trick.  Could `for` be
   compiled by recording the step's token range instead of
   byte range?  What would change?

2. **★★★ Trace.** Switch dispatch is linear in the number of cases.  At what
   case count does a binary-search or jump-table approach
   start to pay?  How would the codegen change?

3. **★★★ Extend.** `break outside any loop` is undefined here.  Add a depth
   counter and emit a compile-time error when it underflows.
   How many bytes does the check cost?

4. **★★ Verify.** Labels are function-local.  M2-Planet's monolith has 891
   global references but how many gotos?  Grep the source and
   estimate.

5. **★★★ Modify.** The if/while/for/do-while/switch parsers all save and
   restore break/continue heads via `>r >r ... r> r>`.  Could
   you factor this into a single helper?  What would the
   helper's interface look like?

## After this chapter

The compiler can lower statements: blocks, `if`/`else`, `while`,
`for`, `do`/`while`, `switch`/`case`/`default` with fall-through,
`return`, `break`, `continue`, and `goto`/labels, all with Ch 11's
emit-remember-patch pattern.

You can read `cc-parse-stmt`, explain how each control structure
threads its branch fixups through a per-construct list, and trace
how a `break` inside a nested `while` reaches its own loop's fixup
list and not the outer one.

Toward Stage-A: the jump rel32s patched here are bytes in
`cc-out-v1`, not in the `.M1` text Stage A compares.  A wrong
rel32 shows up only indirectly: `cc-out-v1` takes a wrong branch
while compiling M2-Planet, and only if the self-compile reaches
that branch.

One kind of jump is still missing.  tri.c's `line(t.rows - 1 - r,
w[r])` must hand two values to code elsewhere in the file and come
back, and `main` itself must be reached from somewhere.  Ch 31
compiles calls, parameters, and the entry stub.

## Takeaways

- Every statement that jumps forward emits a rel32 placeholder and patches it once the target is known, keeping one pending offset on the data stack or many in a linked list.
- Loops save the outer `break`/`continue` list heads on the return stack, so nested loops and switches each patch only their own fixups.
- The `for`-step rewind is the one place the parser re-parses source it has already passed, and `switch` is the one construct that emits its body before its dispatch code.

Next: Chapter 31 — Functions: Parameters, Calls, Globals, Entry Stub.
