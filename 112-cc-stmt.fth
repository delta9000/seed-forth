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

  cc-emit-test-rdi
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
  cc-emit-test-rdi
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
  lparen cc-expect-punct-c

  \ --- Init (optional) ---
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ; = and if,
    \ ';' — empty init; token is consumed.
  else,
    cc-putback-token
    cc-parse-expr
    [char] ; cc-expect-punct-c
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
    cc-peek-char lparen = if,
      1+
    else,
      cc-peek-char [char] ) = if,
        1-
      then,
    then,
    cc-next-char drop
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
  r> cc-loop-switch-depth   !
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

  cc-emit-test-rdi
  r> cc-emit-jnz-vaddr                            \ jnz top

  \ Break target = here.
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
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
  lparen cc-expect-punct-c
  cc-parse-expr                                   \ rdi = scrutinee
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

  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [char] } = and 0=
  while,
    \ Three sub-cases: 'case' INT ':', 'default' ':', or generic stmt.
    tok-kind @ tk-kw = tok-kw-id @ kw-case = and if,
      \ 'case' has been consumed; read constant (int literal only
      \ doesn't handle constant-expressions for case labels).
      cc-next-token-keep
      tok-kind @ tk-num <> if,
        [lit] 170 cc-die
      then,
      tok-num @                                   ( K )
      [char] : cc-expect-punct-c
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
  [lit] 0 r@ cc-label-fixups !                    \ fixup-list := 0
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
  dup >r                                          ( id ; R: id )
  cc-here-vaddr r@ cc-label-set-vaddr
  \ Walk forward-fixup list, patch each to current pos.
  r> cc-label-fixups @ cc-walk-and-patch-fixups ;

\ cc-parse-goto-stmt ( -- )  "goto" already consumed.  Grammar:  goto IDENT ;
\
\ If the target label is already defined, emit an absolute backward jmp.
\ Otherwise emit a forward-jmp placeholder and prepend its rel32-fixup-offset
\ to the label's fixup list (resolved when the label is defined).
: cc-parse-goto-stmt
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 173 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-label-find-or-create   ( id )

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
    cc-define-label exit,
  then,
  2drop
  cc-parse-expr-stmt ;

\ cc-parse-stmt ( -- )  Dispatch on the leading token: one line per kind of
\ statement, each returning with exit, once its parser has run.  Silently
\ skip any leading storage-class / type-qualifier keywords (static,
\ extern, const, volatile, ...).
: cc-parse-stmt
  cc-skip-storage-quals
  cc-next-token-keep
  cc-tok-is-basic-type-kw? if, cc-parse-decl exit, then,
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
