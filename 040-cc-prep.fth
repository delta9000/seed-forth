\ 040-cc-prep.fth — preprocessor for the C-subset compiler.
\
\ Responsibilities:
\   1. Process #include "FILE" / #include <FILE>.
\      - "FILE":  open it, recursively preprocess its content (nested
\                 includes / defines work), splice into output.
\      - <FILE>:  elide (the compiler has built-in shims for stdio.h).
\   2. Process #define NAME INT_OR_NAME.  Object-like macros only; the
\      value must be a decimal literal OR another previously-defined macro
\      name resolving to one.  The directive is elided.
\   3. All other characters are copied verbatim from input to output.
\   4. Macro substitution happens at LEX time via cc-macro-find-int (called
\      from cc-lex-ident-or-kw).  The lexer emits a tk-num token instead of
\      tk-ident when a macro matches.
\
\ Implementation: walk a region (addr,len,pos) byte-by-byte.  '#' at line
\ start triggers directive dispatch.  Recursion = save current region globals,
\ swap to the included region, process, restore.
\
\ Include buffers: a small fixed pool of 4 slots × 64 KiB.  cc-prep-inc-depth
\ tracks which slot we're using.  Sufficient for up to 4 levels of nested
\ #include.  M2-Planet's #include "M2libc/..." depth is at most 2.
\
\ Include search paths (first match wins):
\   1. Path verbatim (absolute, or relative to cwd).
\   2. tests/cc/<path>  — tracked local test fallback.
\
\ Input and output: the pass reads the raw source from cc-in-buf and writes
\ its result straight into cc-src-buf, the buffer the lexer reads (030).
\
\ Depends on 010-lib.fth (open/close, digit?, bytes-eq, control-flow),
\ 020-cc-arena.fth (cc-src-line, cc-die, cc-check-cap) and 030-cc-io.fth
\ (cc-in-buf, cc-src-buf, cc-src-init, cc-read-all, ident-start?/ident-cont?,
\ cell[], cc-name-find).

\ ===========================================================================
\ Output: the lexer's source buffer
\ ===========================================================================

\ cc-prep-emit-byte ( b -- )  Append b to cc-src-buf; die 36 if it is full.
\ Counts lines as it goes, so a failure during the pass reports the line of
\ the output it had reached.
: cc-prep-emit-byte
  cc-src-len @ 1+ cc-src-cap [lit] 36 cc-check-cap
  dup cc-src-buf cc-src-len @ + c!
  [lit] 1 cc-src-len +!
  nl = if, [lit] 1 cc-src-line +! then, ;

\ ===========================================================================
\ Macro table (parallel arrays).  Object-like macros, integer values only.
\ ===========================================================================

[lit] 256 constant cc-macro-cap
create cc-macro-name-addr  cc-macro-cap [lit] 8 * allot
create cc-macro-name-len   cc-macro-cap [lit] 8 * allot
create cc-macro-value      cc-macro-cap [lit] 8 * allot
variable cc-macro-count

\ Dedicated name pool.  A #define's name may sit in an include-pool slot
\ (below), which the next #include at the same depth overwrites while the
\ lexer still needs the macro.  So the names are deep-copied here.
[lit] 16384 constant cc-macro-name-pool-cap
create cc-macro-name-pool  cc-macro-name-pool-cap allot
variable cc-macro-name-pool-pos

\ cc-macro-name-pool-copy ( src-addr src-len -- dest-addr )
\ Copy src-len bytes into the name pool, returning their dest address.
\ Dies with code 35 if the pool overflows.
variable cc-mn-src-a
variable cc-mn-src-u
variable cc-mn-dst
: cc-macro-name-pool-copy
  cc-mn-src-u ! cc-mn-src-a !
  cc-macro-name-pool-pos @ cc-mn-src-u @ +
  cc-macro-name-pool-cap [lit] 35 cc-check-cap
  cc-macro-name-pool cc-macro-name-pool-pos @ +    ( dst )
  dup cc-mn-dst !
  begin,
    cc-mn-src-u @ [lit] 0 >
  while,
    cc-mn-src-a @ c@ cc-mn-dst @ c!
    [lit] 1 cc-mn-src-a +!
    [lit] 1 cc-mn-dst +!
    [lit] 1 cc-mn-src-u -!
  repeat,
  \ Advance pool pos by the original length.
  cc-mn-dst @ cc-macro-name-pool - cc-macro-name-pool-pos !
  ;

\ cc-macro-add ( name-addr name-len value -- )
\ Deep-copies the name into the name pool before recording the entry.
\ Dies with code 34 if the table already holds cc-macro-cap macros.
: cc-macro-add
  cc-macro-count @ 1+ cc-macro-cap [lit] 34 cc-check-cap
  cc-macro-count @ >r                              ( a u v ; R: i )
  r@ cc-macro-value cell[] !                       ( a u )
  \ Copy name into the pool; replace addr with pool addr.
  over over                                        ( a u a u )
  cc-macro-name-pool-copy                          ( a u pool-addr )
  \ Now we have ( a u pool-addr ).  We need to store pool-addr and u.
  r@ cc-macro-name-addr cell[] !                   ( a u )
  r@ cc-macro-name-len  cell[] !                   ( a )
  drop                                             ( -- )
  [lit] 1 cc-macro-count +!
  r> drop ;

\ cc-macro-find-int ( name-addr name-len -- value found? )
\ Newest first (cc-name-find), so a later #define wins.
: cc-macro-find-int
  cc-macro-name-addr cc-macro-name-len cc-macro-count @ cc-name-find  ( i )
  dup 0< if, drop [lit] 0 [lit] 0 exit, then,      \ not found: 0 0
  cc-macro-value cell[] @ true ;                   ( value -1 )

\ ===========================================================================
\ Walking-region state.  Globals so recursion just saves/restores.
\ ===========================================================================

variable cc-prep-src-addr
variable cc-prep-src-len
variable cc-prep-src-pos

\ cc-prep-eor? ( -- f )  End-of-region.
: cc-prep-eor?
  cc-prep-src-pos @ cc-prep-src-len @ >= ;

\ cc-prep-peek ( -- c )  Current byte; 0 at EOR.
: cc-prep-peek
  cc-prep-eor? if,
    [lit] 0
  else,
    cc-prep-src-addr @ cc-prep-src-pos @ + c@
  then, ;

\ cc-prep-advance ( -- )
: cc-prep-advance
  [lit] 1 cc-prep-src-pos +! ;

\ cc-prep-peek2 ( -- c )  The byte one past pos; 0 if that is at/after EOR.
\ Used to recognise the two-byte comment markers /* and */.
: cc-prep-peek2
  cc-prep-src-pos @ 1+ cc-prep-src-len @ >= if,
    [lit] 0
  else,
    cc-prep-src-addr @ cc-prep-src-pos @ + 1+ c@
  then, ;

\ cc-prep-skip-blanks ( -- )  Skip spaces and tabs (NOT newlines).
: cc-prep-skip-blanks
  begin,
    cc-prep-eor? 0=
    cc-prep-peek dup bl = swap tab = or  and
  while,
    cc-prep-advance
  repeat, ;

\ cc-prep-skip-block-comment-tail ( -- )  pos is just past an opening /*.
\ Consume bytes through the closing */ (crossing newlines), or to EOR.
: cc-prep-skip-block-comment-tail
  begin,
    cc-prep-eor? 0=
    cc-prep-peek [char] * = cc-prep-peek2 [char] / = and 0=  \ not yet "*/"
    and
  while,
    cc-prep-advance
  repeat,
  cc-prep-peek  [char] * = if, cc-prep-advance then,         \ consume '*'
  cc-prep-peek  [char] / = if, cc-prep-advance then, ;       \ consume '/'

\ cc-prep-skip-to-eol ( -- )  Stop at newline (which is left unconsumed) or EOR.
\ A directive's tokens may be followed by a /* block comment */ that runs past
\ the newline; consume such a comment whole so its closing */ doesn't leak into
\ the emitted stream as stray tokens.  Comments are otherwise the lexer's job —
\ this only matters here because directive tails are elided before lexing.
: cc-prep-skip-to-eol
  begin,
    cc-prep-eor? 0=
    cc-prep-peek nl <> and
  while,
    cc-prep-peek [char] / = cc-prep-peek2 [char] * = and if,
      cc-prep-advance cc-prep-advance                       \ skip '/*'
      cc-prep-skip-block-comment-tail
    else,
      cc-prep-advance
    then,
  repeat, ;

\ ===========================================================================
\ Include buffer pool (4 slots × 64 KiB).
\ ===========================================================================

[lit] 65536 constant cc-prep-inc-slot-cap
[lit] 4     constant cc-prep-inc-slot-count

create cc-prep-inc-pool  cc-prep-inc-slot-cap cc-prep-inc-slot-count * allot
variable cc-prep-inc-depth

\ cc-prep-inc-slot-addr ( depth -- addr )
: cc-prep-inc-slot-addr
  cc-prep-inc-slot-cap *  cc-prep-inc-pool + ;

\ ===========================================================================
\ Path building.  Concat prefix + name + NUL into cc-prep-path-buf.
\ ===========================================================================

[lit] 1024 constant cc-prep-path-cap
create cc-prep-path-buf  cc-prep-path-cap allot
variable cc-prep-path-out

create cc-prep-tests-prefix  s, tests/cc/

[lit] 9 constant cc-prep-tests-prefix-len

\ cc-prep-append ( src-addr src-len -- )  Append bytes to cc-prep-path-buf.
\ Dies with code 33 if they and the closing NUL would not fit.
: cc-prep-append
  cc-prep-path-out @ over + 1+ cc-prep-path-cap [lit] 33 cc-check-cap
  begin,
    dup [lit] 0 >
  while,
    over c@
    cc-prep-path-buf cc-prep-path-out @ + c!
    [lit] 1 cc-prep-path-out +!
    swap 1+ swap
    1-
  repeat,
  drop drop ;

\ cc-prep-build-path ( pa pu na nu -- )
\ Build NUL-terminated cc-prep-path-buf = prefix + name + 0.
: cc-prep-build-path
  >r >r                                            ( pa pu ; R: nu na )
  [lit] 0 cc-prep-path-out !
  cc-prep-append                                   \ append prefix
  r> r>                                            ( na nu )
  cc-prep-append                                   \ append name
  [lit] 0 cc-prep-path-buf cc-prep-path-out @ + c! ;  \ NUL

\ ===========================================================================
\ File loading.  Reads a file into the current include-pool slot.
\ ===========================================================================
\ Linux O_RDONLY = 0.
: cc-prep-try-open  [lit] 0 [lit] 0 open ;         ( path-addr -- fd )

variable cc-prep-load-name-a
variable cc-prep-load-name-u

\ cc-prep-load-file ( path-a path-u -- buf-a buf-u )
\ Opens the file (tries literal path, then tests/cc/<path>), reads it
\ into the include-pool slot for the current depth.  Dies with code 31 if
\ the include depth exceeds the pool, 30 if neither path opens, and 32 if
\ the file does not fit in its slot.
: cc-prep-load-file
  cc-prep-load-name-u ! cc-prep-load-name-a !

  cc-prep-inc-depth @ 1+ cc-prep-inc-slot-count [lit] 31 cc-check-cap

  \ Try literal path: prefix = "" (a=0,u=0).
  [lit] 0 [lit] 0
  cc-prep-load-name-a @ cc-prep-load-name-u @
  cc-prep-build-path
  cc-prep-path-buf cc-prep-try-open                ( fd )
  dup 0< if,
    drop
    cc-prep-tests-prefix cc-prep-tests-prefix-len
    cc-prep-load-name-a @ cc-prep-load-name-u @
    cc-prep-build-path
    cc-prep-path-buf cc-prep-try-open
    dup 0< if,
      drop
      [lit] 30 cc-die
    then,
  then,
  \ fd is on TOS.  Load into the slot for the current depth.
  >r                                               ( ; R: fd )
  cc-prep-inc-depth @ cc-prep-inc-slot-addr        ( buf-a )
  r@ over cc-prep-inc-slot-cap [lit] 32 cc-read-all  ( buf-a total )
  r> close drop ;

\ ===========================================================================
\ Ident / decimal readers (operate on cc-prep-src region).
\ ===========================================================================

variable cc-prep-ident-addr
variable cc-prep-ident-len

\ cc-prep-read-ident ( -- )  Reads an identifier at cc-prep-src-pos into
\ cc-prep-ident-{addr,len}.  Pre: peek is ident-start.  Advances pos past it.
: cc-prep-read-ident
  cc-prep-src-addr @ cc-prep-src-pos @ +  cc-prep-ident-addr !
  cc-prep-src-pos @                                ( start )
  begin,
    cc-prep-eor? 0=
    cc-prep-peek ident-cont? and
  while,
    cc-prep-advance
  repeat,
  cc-prep-src-pos @ swap -  cc-prep-ident-len ! ;

variable cc-prep-dec-acc
variable cc-prep-dec-seen

\ cc-prep-read-decimal ( -- n found? )
: cc-prep-read-decimal
  [lit] 0 cc-prep-dec-acc !
  [lit] 0 cc-prep-dec-seen !
  begin,
    cc-prep-eor? 0=
    cc-prep-peek digit? and
  while,
    cc-prep-dec-acc @ [lit] 10 *
    cc-prep-peek [char] 0 - +
    cc-prep-dec-acc !
    true cc-prep-dec-seen !
    cc-prep-advance
  repeat,
  cc-prep-dec-acc @ cc-prep-dec-seen @ ;

\ ===========================================================================
\ Directive dispatch.  Vector for recursion (#include -> process-region).
\ ===========================================================================

variable cc-prep-process-vec
: cc-prep-process-region-tramp  cc-prep-process-vec @ execute ;

\ State save / restore for recursive descent.
\ Arrays indexed by cc-prep-inc-depth (parallel to the include-pool slots),
\ so nested includes don't corrupt each other's restore state.
[lit] 4 constant cc-prep-save-count
create cc-prep-save-addr  cc-prep-save-count [lit] 8 * allot
create cc-prep-save-len   cc-prep-save-count [lit] 8 * allot
create cc-prep-save-pos   cc-prep-save-count [lit] 8 * allot

\ cc-prep-save-slot ( arr -- addr )  Compute the save-slot address for the
\ current include depth.  Arrays are indexed by cc-prep-inc-depth.
: cc-prep-save-slot  cc-prep-inc-depth @ swap cell[] ;

\ cc-prep-handle-include
\ Pre: pos points just past "include".  Skip blanks, read "..." or <...>,
\ then for "..." paths recurse on the loaded file.  For <...> emit nothing.
\ At exit pos is at end-of-line (or EOR); newline is NOT consumed.
variable cc-prep-inc-mode                          \ 1=quote, 2=angle, 0=other

: cc-prep-handle-include
  cc-prep-skip-blanks
  [lit] 0 cc-prep-inc-mode !
  cc-prep-peek [char] " = if,
    [lit] 1 cc-prep-inc-mode !
  else,
    cc-prep-peek [char] < = if,
      [lit] 2 cc-prep-inc-mode !
    then,
  then,

  cc-prep-inc-mode @ [lit] 1 = if,
    \ Quote include.
    cc-prep-advance                                \ consume "
    cc-prep-src-addr @ cc-prep-src-pos @ +         ( path-a )
    cc-prep-src-pos @                              ( path-a start )
    begin,
      cc-prep-eor? 0=
      cc-prep-peek [char] " <> and
      cc-prep-peek nl <> and
    while,
      cc-prep-advance
    repeat,
    cc-prep-src-pos @ swap -                       ( path-a len )
    cc-prep-peek [char] " = if, cc-prep-advance then,
    \ ( path-a len ) — load file, then recurse.
    cc-prep-load-file                              ( buf-a buf-u )
    \ Save current region state at depth slot BEFORE bumping.
    cc-prep-src-addr @ cc-prep-save-addr cc-prep-save-slot !
    cc-prep-src-len  @ cc-prep-save-len  cc-prep-save-slot !
    cc-prep-src-pos  @ cc-prep-save-pos  cc-prep-save-slot !
    \ Bump depth so a nested #include uses the next slot.
    [lit] 1 cc-prep-inc-depth +!
    \ Switch to the included region.
    cc-prep-src-len !                              ( buf-a )
    cc-prep-src-addr !
    [lit] 0 cc-prep-src-pos !
    cc-prep-process-region-tramp
    \ Restore outer region (depth has been decremented by now).
    [lit] 1 cc-prep-inc-depth -!
    cc-prep-save-addr cc-prep-save-slot @ cc-prep-src-addr !
    cc-prep-save-len  cc-prep-save-slot @ cc-prep-src-len  !
    cc-prep-save-pos  cc-prep-save-slot @ cc-prep-src-pos  !
  else,
    cc-prep-inc-mode @ [lit] 2 = if,
      \ Angle include — elide.
      cc-prep-advance
      begin,
        cc-prep-eor? 0=
        cc-prep-peek [char] > <> and
        cc-prep-peek nl <> and
      while,
        cc-prep-advance
      repeat,
      cc-prep-peek [char] > = if, cc-prep-advance then,
    then,
  then,
  cc-prep-skip-to-eol ;

\ cc-prep-handle-define
\ Pre: pos is just past "define".  Parses NAME VALUE.  VALUE may be a decimal
\ literal or an ident resolving to a defined macro.  Registers in cc-macro
\ and elides the directive.
variable cc-prep-def-state

: cc-prep-handle-define
  [lit] 0 cc-prep-def-state !
  cc-prep-skip-blanks
  cc-prep-peek ident-start? if,
    cc-prep-read-ident
    cc-prep-skip-blanks
    cc-prep-peek digit? if,
      cc-prep-read-decimal                         ( v found? )
      if,
        cc-prep-ident-addr @  cc-prep-ident-len @  rot
        cc-macro-add
      else,
        drop
      then,
    else,
      cc-prep-peek ident-start? if,
        \ ident-valued: resolve through existing table.
        cc-prep-src-addr @ cc-prep-src-pos @ +     ( val-a )
        cc-prep-src-pos @                          ( val-a start )
        begin,
          cc-prep-eor? 0=
          cc-prep-peek ident-cont? and
        while,
          cc-prep-advance
        repeat,
        cc-prep-src-pos @ swap -                   ( val-a len )
        cc-macro-find-int                          ( v found? )
        if,
          cc-prep-ident-addr @  cc-prep-ident-len @  rot
          cc-macro-add
        else,
          drop
        then,
      then,
    then,
  then,
  cc-prep-skip-to-eol ;

\ ===========================================================================
\ cc-prep-handle-directive  ( -- )
\ Pre: pos is at '#'.  Consume '#', read the directive name, dispatch.
\ Unknown directives are elided.  Always advances to end-of-line.
\ ===========================================================================

create cc-prep-name-include  s, include
create cc-prep-name-define   s, define

: cc-prep-handle-directive
  cc-prep-skip-blanks                              \ leading indent before '#'
  cc-prep-advance                                  \ consume '#'
  cc-prep-skip-blanks
  cc-prep-peek ident-start? if,
    cc-prep-read-ident
    cc-prep-ident-len @ [lit] 7 = if,
      cc-prep-ident-addr @ cc-prep-name-include [lit] 7 bytes-eq if,
        cc-prep-handle-include exit,
      then,
    then,
    cc-prep-ident-len @ [lit] 6 = if,
      cc-prep-ident-addr @ cc-prep-name-define [lit] 6 bytes-eq if,
        cc-prep-handle-define exit,
      then,
    then,
  then,
  cc-prep-skip-to-eol ;                            \ unknown directive: elide it

\ ===========================================================================
\ cc-prep-line-is-directive?  ( -- f )
\ Looks ahead from current pos: -1 iff the first non-blank byte on the
\ current line is '#'.  Does NOT advance pos.
\ ===========================================================================

variable cc-prep-isd-save-pos

: cc-prep-line-is-directive?
  cc-prep-src-pos @ cc-prep-isd-save-pos !
  cc-prep-skip-blanks
  cc-prep-peek [char] # = >r
  cc-prep-isd-save-pos @ cc-prep-src-pos !
  r> ;

\ ===========================================================================
\ cc-prep-process-region  ( -- )
\ Main walker.  Emits bytes to cc-src-buf, dispatching directives at
\ line start.  Recursion happens via cc-prep-handle-include.
\ ===========================================================================

variable cc-prep-at-line-start

\ cc-prep-at-directive? ( -- f )  -1 iff pos is at a line start and the line
\ is a directive.  Looks ahead only at a line start, so a long line of
\ blanks is scanned once, not once per byte.
: cc-prep-at-directive?
  cc-prep-at-line-start @ 0= if, [lit] 0 exit, then,
  cc-prep-line-is-directive? ;

: cc-prep-process-region
  true cc-prep-at-line-start !                     \ -1 = at start
  begin,
    cc-prep-eor? 0=
  while,
    cc-prep-at-directive? if,
      cc-prep-handle-directive
      true cc-prep-at-line-start !
    else,
      cc-prep-peek dup cc-prep-emit-byte
      nl = if,
        true cc-prep-at-line-start !
      else,
        [lit] 0 cc-prep-at-line-start !
      then,
      cc-prep-advance
    then,
  repeat, ;

' cc-prep-process-region cc-prep-process-vec !

\ ===========================================================================
\ Built-in macro constants — pre-populate the macro table with the small set
\ of stdio.h / stdlib.h identifiers used by M2-Planet sources.  Source code
\ that references e.g. NULL or EXIT_FAILURE picks them up via the standard
\ cc-macro-find-int path during lexing.
\ ===========================================================================

create cc-builtin-name-NULL          s, NULL
create cc-builtin-name-EOF           s, EOF
create cc-builtin-name-EXIT_SUCCESS  s, EXIT_SUCCESS
create cc-builtin-name-EXIT_FAILURE  s, EXIT_FAILURE
create cc-builtin-name-stdin         s, stdin
create cc-builtin-name-stdout        s, stdout
create cc-builtin-name-stderr        s, stderr

: cc-prep-builtins
  cc-builtin-name-NULL          [lit]  4 [lit]  0 cc-macro-add
  cc-builtin-name-EOF           [lit]  3 true      cc-macro-add   \ EOF = -1
  cc-builtin-name-EXIT_SUCCESS  [lit] 12 [lit]  0 cc-macro-add
  cc-builtin-name-EXIT_FAILURE  [lit] 12 [lit]  1 cc-macro-add
  cc-builtin-name-stdin         [lit]  5 [lit]  0 cc-macro-add
  cc-builtin-name-stdout        [lit]  6 [lit]  1 cc-macro-add
  cc-builtin-name-stderr        [lit]  6 [lit]  2 cc-macro-add ;

\ ===========================================================================
\ cc-preprocess  ( -- )
\ Top-level driver.  Walks cc-in-buf and writes the result into cc-src-buf,
\ then rewinds the reader (cc-src-pos 0, cc-src-line 1) for the lexer.
\ ===========================================================================

: cc-preprocess
  cc-src-init
  [lit] 0 cc-macro-count !
  [lit] 0 cc-macro-name-pool-pos !
  [lit] 0 cc-prep-inc-depth !
  cc-prep-builtins
  cc-in-buf cc-prep-src-addr !
  cc-in-len @ cc-prep-src-len !
  [lit] 0 cc-prep-src-pos !
  cc-prep-process-region
  [lit] 0 cc-src-pos !
  [lit] 1 cc-src-line ! ;
