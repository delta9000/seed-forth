\ seed/040-cc-prep.fth — preprocessor for the C-subset compiler.
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
\   2. seed/tests/cc/<path>  — tracked local test fallback.
\
\ Depends on 010-lib.fth (open/read/close, digit?/alpha?, bytes-eq, control-flow)
\ and 030-cc-io.fth (cc-src-buf, cc-src-len).

\ ===========================================================================
\ Output buffer
\ ===========================================================================

[lit] 2097152 constant cc-prep-out-cap
create cc-prep-out-buf  cc-prep-out-cap allot
variable cc-prep-out-pos

\ cc-prep-emit-byte ( b -- )
: cc-prep-emit-byte
  cc-prep-out-buf cc-prep-out-pos @ + c!
  [lit] 1 cc-prep-out-pos +! ;

\ ===========================================================================
\ Macro table (parallel arrays).  Object-like macros, integer values only.
\ ===========================================================================

[lit] 256 constant cc-macro-cap
create cc-macro-name-addr  cc-macro-cap [lit] 8 * allot
create cc-macro-name-len   cc-macro-cap [lit] 8 * allot
create cc-macro-value      cc-macro-cap [lit] 8 * allot
variable cc-macro-count

\ Dedicated name pool.  When cc-macro-add is called, the source buffer it
\ points into is about to be overwritten by cc-prep-copy-back (which copies
\ the expanded source over cc-src-buf).  So the names are deep-copied here.
[lit] 16384 constant cc-macro-name-pool-cap
create cc-macro-name-pool  cc-macro-name-pool-cap allot
variable cc-macro-name-pool-pos

: cc-macro-slot  swap [lit] 8 * + ;                ( i base -- addr )

\ cc-macro-name-pool-copy ( src-addr src-len -- dest-addr )
\ Copy src-len bytes into the name pool, returning their dest address.
\ Exits status 72 if the pool overflows.
variable cc-mn-src-a
variable cc-mn-src-u
variable cc-mn-dst
: cc-macro-name-pool-copy
  cc-mn-src-u ! cc-mn-src-a !
  cc-macro-name-pool-pos @ cc-mn-src-u @ +
  cc-macro-name-pool-cap > if,
    [lit] 72 die
  then,
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
: cc-macro-add
  cc-macro-count @ >r                              ( a u v ; R: i )
  r@ cc-macro-value cc-macro-slot !                ( a u )
  \ Copy name into the pool; replace addr with pool addr.
  over over                                        ( a u a u )
  cc-macro-name-pool-copy                          ( a u pool-addr )
  \ Now we have ( a u pool-addr ).  We need to store pool-addr and u.
  r@ cc-macro-name-addr cc-macro-slot !            ( a u )
  r@ cc-macro-name-len  cc-macro-slot !            ( a )
  drop                                             ( -- )
  [lit] 1 cc-macro-count +!
  r> drop ;

variable cc-macro-find-flag
variable cc-macro-find-value
variable cc-macro-find-needle-addr
variable cc-macro-find-needle-len

\ cc-macro-find-int ( name-addr name-len -- value found? )
\ Iterates newest→oldest so a later #define wins.
: cc-macro-find-int
  cc-macro-find-needle-len  !
  cc-macro-find-needle-addr !
  [lit] 0 cc-macro-find-flag  !
  [lit] 0 cc-macro-find-value !
  cc-macro-count @ [lit] 1 -                       ( i )
  begin,
    dup [lit] 0 >=
  while,
    cc-macro-find-flag @ [lit] 0 = if,             \ still searching?
      dup cc-macro-name-len cc-macro-slot @
      cc-macro-find-needle-len @ = if,
        dup cc-macro-name-addr cc-macro-slot @     ( i entry-a )
        cc-macro-find-needle-addr @ swap           ( i needle entry )
        cc-macro-find-needle-len @
        bytes-eq if,
          dup cc-macro-value cc-macro-slot @ cc-macro-find-value !
          [lit] 0 0= cc-macro-find-flag !
        then,
      then,
    then,
    [lit] 1 -
  repeat,
  drop
  cc-macro-find-value @  cc-macro-find-flag @ ;

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

\ cc-prep-skip-blanks ( -- )  Skip spaces and tabs (NOT newlines).
: cc-prep-skip-blanks
  begin,
    cc-prep-eor? 0=
    cc-prep-peek dup [lit] 32 = swap [lit] 9 = or  and
  while,
    cc-prep-advance
  repeat, ;

\ cc-prep-skip-to-eol ( -- )  Stop at newline (which is left unconsumed) or EOR.
: cc-prep-skip-to-eol
  begin,
    cc-prep-eor? 0=
    cc-prep-peek [lit] 10 <> and
  while,
    cc-prep-advance
  repeat, ;

\ Ident classifiers (use 010-lib.fth alpha?/digit?).
: cc-prep-is-ident-start?  dup alpha?  swap [lit] 95 = or ;
: cc-prep-is-ident-cont?   dup cc-prep-is-ident-start?  swap digit? or ;

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

create cc-prep-tests-prefix
[lit] 115 c, [lit] 101 c, [lit] 101 c, [lit] 100 c,    \ seed
[lit]  47 c,                                            \ /
[lit] 116 c, [lit] 101 c, [lit] 115 c, [lit] 116 c, [lit] 115 c,  \ tests
[lit]  47 c,                                            \ /
[lit]  99 c, [lit]  99 c,                               \ cc
[lit]  47 c,                                            \ /

[lit] 14 constant cc-prep-tests-prefix-len

\ cc-prep-append ( src-addr src-len -- )  Append bytes to cc-prep-path-buf.
: cc-prep-append
  begin,
    dup [lit] 0 >
  while,
    over c@
    cc-prep-path-buf cc-prep-path-out @ + c!
    [lit] 1 cc-prep-path-out +!
    swap [lit] 1 + swap
    [lit] 1 -
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

variable cc-prep-read-fd
variable cc-prep-read-dst
variable cc-prep-read-total

\ cc-prep-read-all ( fd dst-addr -- total )
: cc-prep-read-all
  cc-prep-read-dst ! cc-prep-read-fd !
  [lit] 0 cc-prep-read-total !
  begin,
    cc-prep-read-fd @
    cc-prep-read-dst @ cc-prep-read-total @ +
    [lit] 4096
    read
    dup [lit] 0 >
  while,
    cc-prep-read-total +!
  repeat,
  drop
  cc-prep-read-total @ ;

variable cc-prep-load-name-a
variable cc-prep-load-name-u

\ cc-prep-load-file ( path-a path-u -- buf-a buf-u )
\ Opens the file (tries literal path, then seed/tests/cc/<path>), reads it
\ into the include-pool slot for the current depth.  Exits status 70 if
\ neither path opens or include depth exceeds the pool.
: cc-prep-load-file
  cc-prep-load-name-u ! cc-prep-load-name-a !

  cc-prep-inc-depth @ cc-prep-inc-slot-count >= if,
    [lit] 71 die
  then,

  \ Try literal path: prefix = "" (a=0,u=0).
  [lit] 0 [lit] 0
  cc-prep-load-name-a @ cc-prep-load-name-u @
  cc-prep-build-path
  cc-prep-path-buf cc-prep-try-open                ( fd )
  dup [lit] 0 < if,
    drop
    cc-prep-tests-prefix cc-prep-tests-prefix-len
    cc-prep-load-name-a @ cc-prep-load-name-u @
    cc-prep-build-path
    cc-prep-path-buf cc-prep-try-open
    dup [lit] 0 < if,
      drop
      [lit] 70 die
    then,
  then,
  \ fd is on TOS.  Load into the slot for the current depth.
  >r                                               ( ; R: fd )
  cc-prep-inc-depth @ cc-prep-inc-slot-addr        ( buf-a )
  dup r@ swap cc-prep-read-all                     ( buf-a total )
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
    cc-prep-peek cc-prep-is-ident-cont? and
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
    cc-prep-peek [lit] 48 - +
    cc-prep-dec-acc !
    [lit] 0 0= cc-prep-dec-seen !
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
: cc-prep-save-slot  cc-prep-inc-depth @ [lit] 8 * + ;

\ cc-prep-handle-include
\ Pre: pos points just past "include".  Skip blanks, read "..." or <...>,
\ then for "..." paths recurse on the loaded file.  For <...> emit nothing.
\ At exit pos is at end-of-line (or EOR); newline is NOT consumed.
variable cc-prep-inc-mode                          \ 1=quote, 2=angle, 0=other

: cc-prep-handle-include
  cc-prep-skip-blanks
  [lit] 0 cc-prep-inc-mode !
  cc-prep-peek [lit] 34 = if,
    [lit] 1 cc-prep-inc-mode !
  else,
    cc-prep-peek [lit] 60 = if,
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
      cc-prep-peek [lit] 34 <> and
      cc-prep-peek [lit] 10 <> and
    while,
      cc-prep-advance
    repeat,
    cc-prep-src-pos @ swap -                       ( path-a len )
    cc-prep-peek [lit] 34 = if, cc-prep-advance then,
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
        cc-prep-peek [lit] 62 <> and
        cc-prep-peek [lit] 10 <> and
      while,
        cc-prep-advance
      repeat,
      cc-prep-peek [lit] 62 = if, cc-prep-advance then,
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
  cc-prep-peek cc-prep-is-ident-start? if,
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
      cc-prep-peek cc-prep-is-ident-start? if,
        \ ident-valued: resolve through existing table.
        cc-prep-src-addr @ cc-prep-src-pos @ +     ( val-a )
        cc-prep-src-pos @                          ( val-a start )
        begin,
          cc-prep-eor? 0=
          cc-prep-peek cc-prep-is-ident-cont? and
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

create cc-prep-name-include
[lit] 105 c, [lit] 110 c, [lit]  99 c, [lit] 108 c,    \ incl
[lit] 117 c, [lit] 100 c, [lit] 101 c,                  \ ude

create cc-prep-name-define
[lit] 100 c, [lit] 101 c, [lit] 102 c, [lit] 105 c,    \ defi
[lit] 110 c, [lit] 101 c,                               \ ne

variable cc-prep-dir-matched

: cc-prep-handle-directive
  cc-prep-advance                                  \ consume '#'
  cc-prep-skip-blanks
  [lit] 0 cc-prep-dir-matched !
  cc-prep-peek cc-prep-is-ident-start? if,
    cc-prep-read-ident
    cc-prep-ident-len @ [lit] 7 = if,
      cc-prep-ident-addr @ cc-prep-name-include [lit] 7 bytes-eq if,
        cc-prep-handle-include
        [lit] 0 0= cc-prep-dir-matched !
      then,
    then,
    cc-prep-dir-matched @ [lit] 0 = if,
      cc-prep-ident-len @ [lit] 6 = if,
        cc-prep-ident-addr @ cc-prep-name-define [lit] 6 bytes-eq if,
          cc-prep-handle-define
          [lit] 0 0= cc-prep-dir-matched !
        then,
      then,
    then,
  then,
  cc-prep-dir-matched @ [lit] 0 = if,
    cc-prep-skip-to-eol
  then, ;

\ ===========================================================================
\ cc-prep-line-is-directive?  ( -- f )
\ Looks ahead from current pos: -1 iff the first non-blank byte on the
\ current line is '#'.  Does NOT advance pos.
\ ===========================================================================

variable cc-prep-isd-save-pos

: cc-prep-line-is-directive?
  cc-prep-src-pos @ cc-prep-isd-save-pos !
  cc-prep-skip-blanks
  cc-prep-peek [lit] 35 = >r                       \ '#' = 35
  cc-prep-isd-save-pos @ cc-prep-src-pos !
  r> ;

\ ===========================================================================
\ cc-prep-process-region  ( -- )
\ Main walker.  Emits bytes to cc-prep-out-buf, dispatching directives at
\ line start.  Recursion happens via cc-prep-handle-include.
\ ===========================================================================

variable cc-prep-at-line-start

: cc-prep-process-region
  [lit] 0 0= cc-prep-at-line-start !               \ -1 = at start
  begin,
    cc-prep-eor? 0=
  while,
    cc-prep-at-line-start @  cc-prep-line-is-directive?  and if,
      cc-prep-handle-directive
      [lit] 0 0= cc-prep-at-line-start !
    else,
      cc-prep-peek dup cc-prep-emit-byte
      [lit] 10 = if,
        [lit] 0 0= cc-prep-at-line-start !
      else,
        [lit] 0 cc-prep-at-line-start !
      then,
      cc-prep-advance
    then,
  repeat, ;

' cc-prep-process-region cc-prep-process-vec !

\ ===========================================================================
\ cc-preprocess  ( -- )
\ Top-level driver.  Walks cc-src-buf, writes to cc-prep-out-buf, then
\ copies back into cc-src-buf.  Resets cc-src-pos / cc-src-line so the
\ lexer rewinds.
\ ===========================================================================

\ cc-prep-copy-back ( -- )  Copy cc-prep-out-buf[0..pos] -> cc-src-buf[0..].
variable cc-prep-cb-n
variable cc-prep-cb-i
: cc-prep-copy-back
  cc-prep-out-pos @
  dup cc-src-cap > if, drop cc-src-cap then,       ( n )
  dup cc-src-len !
  cc-prep-cb-n !
  [lit] 0 cc-prep-cb-i !
  begin,
    cc-prep-cb-i @ cc-prep-cb-n @ <
  while,
    cc-prep-out-buf cc-prep-cb-i @ + c@            ( byte )
    cc-src-buf cc-prep-cb-i @ + c!
    [lit] 1 cc-prep-cb-i +!
  repeat, ;

\ ===========================================================================
\ Built-in macro constants — pre-populate the macro table with the small set
\ of stdio.h / stdlib.h identifiers used by M2-Planet sources.  Source code
\ that references e.g. NULL or EXIT_FAILURE picks them up via the standard
\ cc-macro-find-int path during lexing.
\ ===========================================================================

create cc-builtin-name-NULL
[lit]  78 c, [lit]  85 c, [lit]  76 c, [lit]  76 c,    \ NULL

create cc-builtin-name-EOF
[lit]  69 c, [lit]  79 c, [lit]  70 c,                 \ EOF

create cc-builtin-name-EXIT_SUCCESS
[lit]  69 c, [lit]  88 c, [lit]  73 c, [lit]  84 c,    \ EXIT
[lit]  95 c, [lit]  83 c, [lit]  85 c, [lit]  67 c,    \ _SUC
[lit]  67 c, [lit]  69 c, [lit]  83 c, [lit]  83 c,    \ CESS

create cc-builtin-name-EXIT_FAILURE
[lit]  69 c, [lit]  88 c, [lit]  73 c, [lit]  84 c,    \ EXIT
[lit]  95 c, [lit]  70 c, [lit]  65 c, [lit]  73 c,    \ _FAI
[lit]  76 c, [lit]  85 c, [lit]  82 c, [lit]  69 c,    \ LURE

create cc-builtin-name-stdin
[lit] 115 c, [lit] 116 c, [lit] 100 c, [lit] 105 c,    \ stdi
[lit] 110 c,                                            \ n

create cc-builtin-name-stdout
[lit] 115 c, [lit] 116 c, [lit] 100 c, [lit] 111 c,    \ stdo
[lit] 117 c, [lit] 116 c,                               \ ut

create cc-builtin-name-stderr
[lit] 115 c, [lit] 116 c, [lit] 100 c, [lit] 101 c,    \ stde
[lit] 114 c, [lit] 114 c,                               \ rr

: cc-prep-builtins
  cc-builtin-name-NULL          [lit]  4 [lit]  0 cc-macro-add
  cc-builtin-name-EOF           [lit]  3 [lit]  0 0= cc-macro-add
  cc-builtin-name-EXIT_SUCCESS  [lit] 12 [lit]  0 cc-macro-add
  cc-builtin-name-EXIT_FAILURE  [lit] 12 [lit]  1 cc-macro-add
  cc-builtin-name-stdin         [lit]  5 [lit]  0 cc-macro-add
  cc-builtin-name-stdout        [lit]  6 [lit]  1 cc-macro-add
  cc-builtin-name-stderr        [lit]  6 [lit]  2 cc-macro-add ;

: cc-preprocess
  [lit] 0 cc-prep-out-pos !
  [lit] 0 cc-macro-count !
  [lit] 0 cc-macro-name-pool-pos !
  [lit] 0 cc-prep-inc-depth !
  cc-prep-builtins
  cc-src-buf cc-prep-src-addr !
  cc-src-len @ cc-prep-src-len !
  [lit] 0 cc-prep-src-pos !
  cc-prep-process-region
  cc-prep-copy-back
  [lit] 0 cc-src-pos !
  [lit] 1 cc-src-line ! ;
