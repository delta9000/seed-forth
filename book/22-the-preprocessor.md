# Chapter 22 — The Preprocessor

> **Status:** ✅ complete.  Tangles `040-cc-prep.fth` byte-identically.

## Goal

By the end of this chapter the reader can:

- enumerate the preprocessor directives this compiler supports —
  `#include "…"`, `#include <…>` (elided), and integer-valued
  `#define`;
- explain the macro storage layout (parallel arrays + a dedicated
  name pool) and the `bytes-eq`-based lookup;
- read the `#include` path search (literal, then `tests/cc/`) and
  trace how nested includes recurse through the four-slot include
  buffer pool;
- explain how macro expansion is *not* done by the preprocessor
  itself — it happens later, in the lexer, via `cc-macro-find-int`.

## Source coverage

`040-cc-prep.fth` (630 lines) — entire file.

## Concepts introduced

- **The preprocessor as a source rewriter.**  Reads `cc-src-buf`,
  emits the rewritten text into `cc-prep-out-buf`, copies back into
  `cc-src-buf`, and resets `cc-src-pos` so the lexer rewinds.
- **Macro table** — three parallel `cap × 8` arrays
  (`name-addr`, `name-len`, `value`) plus a dedicated 16 KiB name
  pool, all looked up via `bytes-eq` (Ch 12).
- **Built-in macro pre-population.**  `NULL`, `EOF`,
  `EXIT_SUCCESS`, `EXIT_FAILURE`, `stdin`, `stdout`, `stderr` are
  installed before any user `#define`s run, so M2-Planet sources
  that use them never need a real `stdio.h` / `stdlib.h`.
- **`#include` path resolution** — try the literal path, then
  prefix `tests/cc/`.  Recursion uses a depth counter into a
  4-slot × 64 KiB pool, with the trampoline `cc-prep-process-vec`
  to break the chicken-and-egg of recursive `:`-definitions.

## Concepts carried in

- `cc-peek-char`, `cc-next-char` are *not* used here — the
  preprocessor walks its own region via `cc-prep-peek`, `cc-prep-
  advance`.  Ch 21's I/O is for the lexer.
- `cc-prep-emit-byte` is the same pattern as `cc-emit-byte`.
- `bytes-eq` (Ch 12); `digit?`, `alpha?` (Ch 6); `open`, `read`,
  `close` (Ch 5).

## Concepts deferred

- Macro substitution at use sites — Ch 23 (lexer calls
  `cc-macro-find-int` after `cc-lex-ident-or-kw` reads a token).
- Why `tests/cc/` is the only fallback prefix — Ch 32 (the bootstrap
  driver scripts).

---

C source code is rarely self-contained.  Real translation units
pull in headers, define constants, and rely on a tiny preprocessor
to glue everything together before the compiler sees a single
token.  This file is that preprocessor.

It is also, deliberately, the *smallest* preprocessor that suffices
for the job.  M2-Planet's sources use exactly two preprocessing
features: `#include "…"` for its own headers (M2libc paths) and
`#define NAME N` for integer constants.  Anything else — angle-
bracket includes, function-like macros, conditional compilation,
token pasting — does not appear in the bootstrap input.  The
preprocessor's job is to handle *those two features faithfully* and
to silently elide everything else.

## 1. The output buffer and the two-megabyte detour

```forth file=040-cc-prep.fth
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
[lit] 116 c, [lit] 101 c, [lit] 115 c, [lit] 116 c, [lit] 115 c,  \ tests
[lit]  47 c,                                            \ /
[lit]  99 c, [lit]  99 c,                               \ cc
[lit]  47 c,                                            \ /

[lit] 9 constant cc-prep-tests-prefix-len

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
\ Opens the file (tries literal path, then tests/cc/<path>), reads it
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
```

That listing is the entire chapter's payload.  The rest of this
chapter is annotation.

The preprocessor declares its *own* 2 MiB output buffer — separate
from `cc-out-buf` (Ch 21), which is for ELF bytes.  Why two buffers?
The preprocessor reads from `cc-src-buf` and writes the rewritten
text into `cc-prep-out-buf`, then `cc-prep-copy-back` copies the
result back into `cc-src-buf`, overwriting it.  This dance is the
simplest way to avoid having the writer trample bytes the reader
has not yet visited.

`cc-prep-emit-byte` is a clone of `cc-emit-byte` from Ch 21,
parameterised over the preprocessor's own cursor.  Forth lets you
write a generalisation, but for two call sites it's cheaper to
duplicate.

## 2. Macro storage: parallel arrays plus a name pool

The macro table is three `256 × 8`-byte arrays (`name-addr`,
`name-len`, `value`) and a counter.  This is the same parallel-
array technique you'll see again in Ch 24 for the symbol table —
locality beats records-of-pointers when every walk is "iterate the
column."

The non-obvious piece is the **name pool**, a separate 16 KiB
buffer.  Why?  Because `cc-prep-copy-back` is going to overwrite
`cc-src-buf` once the preprocessing pass finishes.  Any
`cc-macro-name-addr` that pointed into `cc-src-buf` would suddenly
point at *rewritten* bytes — at best garbage, at worst, a different
macro's name.

`cc-macro-name-pool-copy` solves it by deep-copying the name into
the pool when the macro is registered.  After that, the pool is
immutable for the rest of compilation.  Lookups against
`cc-macro-find-int` use the pool addresses, which survive
`copy-back`.

Lookup itself is a straight linear scan, newest-first, with
`bytes-eq` (Ch 12) as the inner comparator.  Newest-first means a
later `#define` with the same name shadows the earlier one — the
standard C semantics.  We stop at the first hit by gating the body
on `cc-macro-find-flag`.

## 3. The walker: peek, advance, classify

The preprocessor walks one *region* at a time.  A region is a
triple — buffer base address, length, current position — held in
`cc-prep-src-addr`, `cc-prep-src-len`, `cc-prep-src-pos`.  Every
read goes through `cc-prep-peek` and `cc-prep-advance`.

This is the same shape as Ch 21's `cc-peek-char` / `cc-next-char`,
but pointed at *whatever buffer we currently care about*.  The
abstraction lets the same code walk `cc-src-buf` for the top-level
pass and the various 64 KiB include slots when `#include` recurses.

`cc-prep-skip-blanks` skips spaces and tabs but *not* newlines —
the newline is structural; we never want to lose it.
`cc-prep-skip-to-eol` walks until it sees newline or hits the end of
the region, leaving the newline unconsumed.  Together they
implement the lexer-free directive parser: "skip whitespace, read
ident, skip whitespace, …".

The `cc-prep-is-ident-start?` and `cc-prep-is-ident-cont?` helpers
fold the C identifier rules (letter or underscore, then letters or
digits) onto Ch 6's `alpha?` and `digit?`.  Underscore is byte 95;
we just OR it in.

## 4. `#include` and the four-slot include pool

`cc-prep-load-file` opens a header, reads it into one of four 64 KiB
slots from `cc-prep-inc-pool`, and returns its buffer address and
length.  The depth counter `cc-prep-inc-depth` picks the slot, so
nested includes don't collide.

Two paths are tried before giving up: the literal path (which
catches absolute paths and anything relative to the current
directory) and then `tests/cc/<path>` (which is where the test
inputs live).  The hard-coded `tests/cc/` prefix is the only
production-vs-test coupling in the compiler — a deliberate
shortcut, since the bootstrap chain runs the compiler from the
repo root and only ever asks for headers that live in `tests/cc/`.

Recursion uses a trampoline.  `cc-prep-process-region` is the
walker we'll meet in §6; `#include` needs to call it to process
the loaded header.  But the walker calls `cc-prep-handle-include`,
which is *defined before* the walker — a forward reference Forth's
`:` cannot satisfy.  The fix is the indirection through
`cc-prep-process-vec`: declare the variable up front, define the
trampoline that calls through it, then patch the variable to point
at `cc-prep-process-region` once the walker is defined.

The save/restore around the recursive call is straightforward.
Before bumping `cc-prep-inc-depth`, we stash the current region
triple in `cc-prep-save-{addr,len,pos}` indexed by the *outer*
depth; after the recursive walk we decrement the depth and read
back.  The arrays are length 4, matching the include-pool slot
count — four nested includes is the hard ceiling.  M2-Planet uses
at most two.

Angle-bracket includes (`#include <stdio.h>`) take a different
branch.  Rather than trying to find a system header that doesn't
exist in the bootstrap environment, the preprocessor *elides* the
directive — skips it entirely.  The shims for `NULL`, `EOF`,
`stdin`, etc. come from the built-in macros in §7, not from real
header files.

## 5. `#define` and the integer-only macro grammar

The grammar this preprocessor supports is, in full:

```
#define NAME DECIMAL_LITERAL
#define NAME ANOTHER_MACRO_NAME
```

The first form parses the value with `cc-prep-read-decimal` and
registers the integer.  The second form reads an identifier, runs
it through `cc-macro-find-int`, and registers the resolved value.
Anything else — string literals, expressions, function-like macros,
multi-line continuations — falls off the end of the conditionals
and is silently dropped (the directive is elided either way).

This is enough for M2-Planet because that codebase only `#define`s
integer constants.  Anything more would have to land here as code,
not as a documentation TODO.

## 6. Directive dispatch at line start

The walker `cc-prep-process-region` is the heart of the file.  Its
logic is:

1. Track whether we are at the start of a line (`cc-prep-at-line-
   start`, initialised to `-1` for "yes, line just began").
2. Loop until end-of-region.
3. If we're at line start AND the first non-blank byte is `#`,
   dispatch to `cc-prep-handle-directive` (and reset
   `cc-prep-at-line-start` for the next iteration).
4. Otherwise, emit the current byte and advance.  Update
   `cc-prep-at-line-start` based on whether the emitted byte was
   newline.

`cc-prep-line-is-directive?` peeks ahead without losing position
— it saves `cc-prep-src-pos`, skips blanks, checks for `#`,
restores `cc-prep-src-pos`.  The classic "save and restore"
pattern.  Forth's data-stack discipline makes it almost too easy.

`cc-prep-handle-directive` reads the directive name, compares it
against `cc-prep-name-include` and `cc-prep-name-define` (the
literal byte arrays just below it), and dispatches.  Unknown
directives are elided — the `cc-prep-dir-matched @ [lit] 0 = if,
cc-prep-skip-to-eol then,` path makes sure we don't fall back to
emitting the `#` we already consumed.

## 7. Built-in macros

`cc-prep-builtins` runs at the start of `cc-preprocess` and
pre-loads seven names into the macro table.  `NULL = 0`,
`EOF = -1` (encoded as `[lit] 0 0=`, since `-1` would fail
`parse_decimal_code`; Ch 20 explains why), `EXIT_SUCCESS = 0`,
`EXIT_FAILURE = 1`, and the three standard-fd shims `stdin = 0`,
`stdout = 1`, `stderr = 2`.

These are the only `stdio.h` / `stdlib.h` artefacts M2-Planet's
sources actually reference (the others — `printf`, `fopen`,
`malloc` — are not used).  By installing them as macros at preproc
time we sidestep the need for header files at all, while leaving
*the rest* of the M2libc include surface alone in case the
preprocessor encounters it.

## 8. The pass driver

`cc-preprocess` is the only function the outside world calls.  It
resets every cursor and counter, primes the built-in macros, points
the walking-region globals at `cc-src-buf`, runs
`cc-prep-process-region`, and then `cc-prep-copy-back` overwrites
the source buffer with the expanded text and clamps the length.

After the copy-back, `cc-src-pos` is reset to 0 and `cc-src-line`
to 1 so the lexer sees a fresh source.  As far as the lexer is
concerned, the preprocessor never happened — there's just text in
`cc-src-buf` and `cc-src-len` tells it how much.

The remaining wrinkle is that macros that *evaluate* (not just
parse) at substitution time are still in the table.  When the lexer
reads `NULL` it calls `cc-macro-find-int` and emits a numeric token
with value 0; same for `EOF`, `EXIT_FAILURE`, and any user-defined
`#define` that survived this pass.  That's why §3's docstring says
"macro substitution happens at LEX time."

## Try it

```sh
./build.sh
tests/cc/stage-a-check.sh         # exercises the preprocessor end to end
```

`tests/cc/G6a.c` and `G6b.c` are the small smoke-tests that touch
preprocessor features in isolation.  Read them to see exactly which
M2-Planet patterns the preprocessor must cope with.

You can also run the compiler directly on a small input to inspect
its behaviour:

```sh
./build.sh
cat <<'EOF' | ./seed-forth -e '
  s" 010-lib.fth" included
  s" 020-cc-arena.fth" included
  s" 030-cc-io.fth" included
  s" 040-cc-prep.fth" included
  cc-load-stdin cc-preprocess
  cr ." len=" cc-src-len @ . cr
  cc-src-len @ 0 do  cc-src-buf i + c@ emit  loop
  bye'
#define ANSWER 42
int x = ANSWER;
EOF
```

(The exact incantation depends on which test harness driver you
use; `tests/cc/stage-a-check.sh` is the path of least resistance.)

## Exercises

1. M2-Planet uses a small set of preprocessor features.  Skim
   `tests/cc/M*.c` and `tests/cc/G*.c`, then list every directive
   you find.  Compare against §5's grammar — anything not covered?

2. The macro table is 256 entries × 8 bytes per column, plus a 16
   KiB name pool.  Could you shrink either without breaking the
   bootstrap?  Instrument `cc-macro-count` and
   `cc-macro-name-pool-pos` at the end of `cc-preprocess` to find
   out.

3. Function-style macros (`#define FOO(x) ((x)+1)`) are not
   supported.  Construct a test case that depends on this missing
   feature and observe how the compiler handles it.  Where would
   the smallest possible patch go?

4. `#include` cycles would loop forever.  Read §4 and find the
   (deliberately missing) cycle check.  Sketch the smallest patch
   that would detect a cycle without parsing.

5. `#undef NAME` and `#ifdef NAME` are absent.  Estimate the
   complexity cost of adding each.  Which would touch more code?

## Takeaways

- The preprocessor is a separate pass that rewrites
  `cc-src-buf` in place via a 2 MiB scratch buffer.  After it
  runs, the lexer sees expanded text and a reset position.
- Macro storage is parallel arrays plus a dedicated name pool —
  the pool exists *because* `cc-src-buf` is about to be
  overwritten by `cc-prep-copy-back`.
- `#include "…"` recurses through a 4-slot × 64 KiB pool with
  per-depth save/restore; `#include <…>` is elided in favour of
  built-in macros for `NULL`, `EOF`, and the standard fds.

Next: Chapter 23 — The Lexer.
