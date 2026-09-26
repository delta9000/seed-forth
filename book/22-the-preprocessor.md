# Chapter 22 — The Preprocessor

```text
Missing capability: C source still arrives as include-laden, macro-bearing text.
New pattern: rewrite source through cc-prep-out-buf while recording integer macros newest-first.
Artifact after this chapter: a flattened C stream plus an integer macro table.
Proof link: Stage-A sees the same project headers and integer constants as the reference path.
```

`tri.c` opens with `#define ROWS 4`, a line no C parser accepts, and
then uses `ROWS` four times.  Before the parser sees the program,
something has to delete that line and make each `ROWS` mean 4.  The
preprocessor does only the first half.  The 616-line file
`040-cc-prep.fth` is the smallest preprocessor that suffices for
M2-Planet.  It supports two active transformations: `#include "…"` for project
headers, spliced in recursively, and `#define NAME N` for integer
constants, recorded in a macro table.  Every other directive line is
elided.

The bootstrap monolith leans on even less than that.  The script that
assembles it deletes every column-0 `#include "…"` line from the `.c`
files, and the `TRUE`/`FALSE` defines with them, so only the headers'
own `#include "cc_globals.h"` and `#include "cc.h"` reach this pass,
both resolved through the `tests/cc/` fallback.  No integer `#define`
survives: the one left, `#define CC_H`, has no value and is dropped.
The integer path is exercised by the gate fixtures instead (see Try
it).  Angle-bracket includes, include guards and similar scaffolding
still appear, but this compiler does not need their semantics.

Macro *substitution* is not the preprocessor's job at all.  The pass
only records `ROWS → 4`; Ch 23's lexer calls `cc-macro-find-int`
after reading each identifier.

## 1. The output buffer and the two-megabyte detour

The file's header comment states the whole contract, including the
lex-time substitution rule and the include search order.

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

```

The preprocessor reads from `cc-src-buf` and writes the rewritten text
into a buffer of its own.

```forth file=040-cc-prep.fth
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

```

`cc-prep-out-buf` is 2 MiB and separate from `cc-out-buf` (Ch 21),
which holds ELF bytes.  When the pass finishes, `cc-prep-copy-back`
(§7) copies the result back into `cc-src-buf`, overwriting it.  Writing
to a second buffer is the simplest way to keep the writer from
trampling bytes the reader has not yet visited, since an `#include`
makes the output longer than the input.

`cc-prep-emit-byte` is a clone of `cc-emit-byte` from Ch 21 with the
preprocessor's own cursor.  For two call sites, duplicating is cheaper
than generalising.

## 2. Macro storage: parallel arrays plus a name pool

The macro table is three `256 × 8`-byte arrays (`name-addr`,
`name-len`, `value`) and a counter, the same parallel-array layout Ch
24 uses for the symbol table.

```forth file=040-cc-prep.fth
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

variable cc-macro-find-needle-addr
variable cc-macro-find-needle-len

```

The **name pool** is a separate 16 KiB buffer.  It exists because
`cc-prep-copy-back` overwrites `cc-src-buf` once the pass finishes.
Any `cc-macro-name-addr` that pointed into `cc-src-buf` would then
point at rewritten bytes: garbage at best, a different macro's name at
worst.  `cc-macro-add` therefore passes every name through
`cc-macro-name-pool-copy`, which deep-copies it and dies with status 72
if the pool is full.  After that the stored address never moves.

Lookup walks the table from the newest entry down:

```forth file=040-cc-prep.fth
\ cc-macro-find-int ( name-addr name-len -- value found? )
\ Iterates newest→oldest so a later #define wins: the first hit returns.
: cc-macro-find-int
  cc-macro-find-needle-len  !
  cc-macro-find-needle-addr !
  cc-macro-count @ 1-                              ( i )
  begin,
    dup [lit] 0 >=
  while,
    dup cc-macro-name-len cc-macro-slot @
    cc-macro-find-needle-len @ = if,
      dup cc-macro-name-addr cc-macro-slot @       ( i entry-a )
      cc-macro-find-needle-addr @ swap             ( i needle entry )
      cc-macro-find-needle-len @
      bytes-eq if,
        cc-macro-value cc-macro-slot @ true exit,  ( value -1 )
      then,
    then,
    1-
  repeat,
  drop [lit] 0 [lit] 0 ;                           \ not found: 0 0

```

The comparator is `bytes-eq` (Ch 12).  Walking newest-first means a later `#define` of the same name
shadows the earlier one, as in C.  The first hit returns at once with
`exit,` (Ch 11), leaving the value and a true flag.  This is the small-table,
newest-wins lookup of Ch 17's dictionary at macro scale.

## 3. The walker: peek, advance, classify

The preprocessor walks one *region* at a time: a buffer base address,
a length and a current position, held in `cc-prep-src-addr`,
`cc-prep-src-len` and `cc-prep-src-pos`.

```forth file=040-cc-prep.fth
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

\ Ident classifiers (use 010-lib.fth alpha?/digit?).
: cc-prep-is-ident-start?  dup alpha?  swap [char] _ = or ;
: cc-prep-is-ident-cont?   dup cc-prep-is-ident-start?  swap digit? or ;

```

Every read goes through `cc-prep-peek` and `cc-prep-advance`, the same
shape as Ch 21's `cc-peek-char` / `cc-next-char` but pointed at
whichever buffer is current.  The same code walks `cc-src-buf` for the
top-level pass and a 64 KiB include slot when `#include` recurses.

`cc-prep-skip-blanks` skips spaces and tabs but not newlines, because
the newline is structural.  `cc-prep-skip-to-eol` walks to the next
newline or the end of the region, leaving the newline unconsumed.
Together they make a lexer-free directive parser: skip blanks, read an
identifier, skip blanks, and so on.

`cc-prep-skip-to-eol` has one wrinkle.  It is used only to *elide the
tail of a directive line*: the bytes after a handled `#include` or
`#define`, or a whole unknown directive.  A directive's tokens may be
followed by a `/* … */` comment that runs past the newline.  If
skip-to-eol stopped blindly at the first newline, it would swallow the
comment's opener (on the elided line) and leave the closer on the next
line, where the lexer would meet stray `*` `/` tokens.  So it watches
for `/*`, using the two-byte lookahead `cc-prep-peek2`, and hands off
to `cc-prep-skip-block-comment-tail`, which consumes through the
matching `*/` across newlines.  Comments are otherwise the lexer's
department (Ch 23); the preprocessor must understand them here only
because it elides text before the lexer can see it.

`cc-prep-is-ident-start?` and `cc-prep-is-ident-cont?` fold C's
identifier rules (letter or underscore, then letters or digits) onto
Ch 6's `alpha?` and `digit?`.  Underscore is byte 95, ORed in.

## 4. `#include` and the four-slot include pool

An included file needs somewhere to live while it is walked.  The
pool has four 64 KiB slots, one per nesting depth.

```forth file=040-cc-prep.fth
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

```

A header is looked up under two names, so the file needs a small
path builder.

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Path building.  Concat prefix + name + NUL into cc-prep-path-buf.
\ ===========================================================================

[lit] 1024 constant cc-prep-path-cap
create cc-prep-path-buf  cc-prep-path-cap allot
variable cc-prep-path-out

create cc-prep-tests-prefix  s, tests/cc/

[lit] 9 constant cc-prep-tests-prefix-len

\ cc-prep-append ( src-addr src-len -- )  Append bytes to cc-prep-path-buf.
: cc-prep-append
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

```

`cc-prep-build-path` concatenates a prefix, the name and a NUL into
`cc-prep-path-buf`.  The only prefixes ever used are the empty one and
`tests/cc/`, and the loader tries them in that order:

```forth file=040-cc-prep.fth
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
  dup 0< if,
    drop
    cc-prep-tests-prefix cc-prep-tests-prefix-len
    cc-prep-load-name-a @ cc-prep-load-name-u @
    cc-prep-build-path
    cc-prep-path-buf cc-prep-try-open
    dup 0< if,
      drop
      [lit] 70 die
    then,
  then,
  \ fd is on TOS.  Load into the slot for the current depth.
  >r                                               ( ; R: fd )
  cc-prep-inc-depth @ cc-prep-inc-slot-addr        ( buf-a )
  dup r@ swap cc-prep-read-all                     ( buf-a total )
  r> close drop ;

```

`cc-prep-load-file` tries the literal path first (which catches
absolute paths and anything relative to the current directory), then
`tests/cc/<path>`, where the test inputs live.  If neither opens it
dies with status 70; if the depth already fills all four slots it dies
with 71.  The hard-coded `tests/cc/` prefix is the only coupling
between production code and test layout in the compiler, a deliberate
shortcut: the bootstrap chain runs the compiler from the repo root and
only asks for headers that live there.  `cc-prep-read-all` is Ch 21's
chunked-read loop again, aimed at the slot for the current
`cc-prep-inc-depth`.

The directive handlers need to read a name and a number from the
current region.

```forth file=040-cc-prep.fth
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
    cc-prep-peek [char] 0 - +
    cc-prep-dec-acc !
    true cc-prep-dec-seen !
    cc-prep-advance
  repeat,
  cc-prep-dec-acc @ cc-prep-dec-seen @ ;

```

`cc-prep-read-ident` records where the identifier starts and how long
it is; `cc-prep-read-decimal` accumulates digits and reports whether it
saw any.

Now the recursion.  `#include "…"` has to run the region walker,
`cc-prep-process-region` (§6), on the loaded header.  But the walker
calls `cc-prep-handle-include`, which is defined first, and Forth's `:`
cannot refer to a word that doesn't exist yet.

```forth file=040-cc-prep.fth
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

```

The fix is `cc-prep-process-vec`: declare the variable here, define a
trampoline that executes through it, and store
`' cc-prep-process-region` into it once the walker exists (§6).  The
save arrays are length 4, matching the pool, so four nested includes
is the hard ceiling.  M2-Planet uses at most two.  With the vector
and the save arrays in place, the handler can recurse:

```forth file=040-cc-prep.fth
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

```

For a quoted path, the handler measures the name up to the closing
`"`, loads the file, and stashes the current region triple in
`cc-prep-save-{addr,len,pos}` at the *outer* depth.  It then bumps
the depth, points the region globals at the loaded buffer, walks it
through the trampoline, decrements the depth and reads the triple
back.

Angle-bracket includes (`#include <stdio.h>`) take the other branch.
There are no system headers in the bootstrap environment, so the
handler skips to the closing `>` and emits nothing.  The few names
M2-Planet needs from those headers (`NULL`, `EOF`, `stdin` and so on)
come from the built-in macros in §7.

## 5. `#define` and the integer-only macro grammar

The grammar this preprocessor supports is, in full:

```
#define NAME DECIMAL_LITERAL
#define NAME ANOTHER_MACRO_NAME
```

`cc-prep-handle-define` parses both forms:

```forth file=040-cc-prep.fth
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

```

The first form parses the value with `cc-prep-read-decimal` and
registers the integer.  The second reads an identifier, runs it
through `cc-macro-find-int`, and registers the resolved value.
Anything else (string literals, expressions, function-like macros,
multi-line continuations) falls through the conditionals and is
dropped; the directive is elided either way.  The macros that matter
to code generation in the bootstrap input are integer constants, so
this is enough.

## 6. Directive dispatch at line start

A directive is a line whose first non-blank byte is `#`.  The
dispatcher compares the directive name against two byte arrays.

```forth file=040-cc-prep.fth
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
  cc-prep-peek cc-prep-is-ident-start? if,
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

```

`cc-prep-handle-directive` reads the name, matches it with `bytes-eq`
against `cc-prep-name-include` or `cc-prep-name-define`, and calls the
handler, returning with `exit,` once the handler is done.  An
unknown directive matches neither and falls through to
`cc-prep-skip-to-eol`, so the `#` already consumed is never
emitted.

Two words remain: the test for whether a line is a directive, and the
walker that asks it.

```forth file=040-cc-prep.fth
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
\ Main walker.  Emits bytes to cc-prep-out-buf, dispatching directives at
\ line start.  Recursion happens via cc-prep-handle-include.
\ ===========================================================================

variable cc-prep-at-line-start

: cc-prep-process-region
  true cc-prep-at-line-start !                     \ -1 = at start
  begin,
    cc-prep-eor? 0=
  while,
    cc-prep-at-line-start @  cc-prep-line-is-directive?  and if,
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

```

The walker `cc-prep-process-region` tracks whether it is at the start
of a line (`cc-prep-at-line-start`, initially `-1`).  At line start,
if the first non-blank byte is `#`, it dispatches the directive.
Otherwise it emits the current byte, advances, and sets the flag
according to whether that byte was a newline.  The last line of the
listing patches the trampoline vector from §4.

`cc-prep-line-is-directive?` saves `cc-prep-src-pos`, skips blanks,
checks for `#` and restores the position.  Because it restores, the
handler starts at the line's leading whitespace, not at the `#`, so
`cc-prep-handle-directive` skips blanks again before consuming `#`.
C allows whitespace before the `#`, and `   #define X 42` must register
`X`.  Without that first `cc-prep-skip-blanks` the handler would
consume a space, find `#` where it expected an identifier, match
nothing, and silently elide the line.  For a column-0 directive the
extra skip does nothing.

## 7. Copy-back and the built-in macros

When the walk ends, the rewritten text goes back where the lexer will
look for it.

```forth file=040-cc-prep.fth
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

```

`cc-prep-copy-back` clamps the length to `cc-src-cap`, stores it in
`cc-src-len`, and copies byte by byte.

Before the walk starts, the macro table is seeded with the few names
the elided system headers would have supplied:

```forth file=040-cc-prep.fth
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

```

`cc-prep-builtins` pre-loads seven names: `NULL = 0`, `EOF = -1`
(encoded as `true`, since `-1` would fail `parse_decimal_code`;
Ch 20 explains why), `EXIT_SUCCESS = 0`, `EXIT_FAILURE = 1`, and the
standard-fd shims `stdin = 0`, `stdout = 1`, `stderr = 2`.  These are
the only `stdio.h` / `stdlib.h` artefacts this bootstrap path needs
from the elided angle-bracket headers.  Installing them as macros
sidesteps host header files while project headers still supply their
own declarations.

## 8. The pass driver

`cc-preprocess` is the only word the rest of the compiler calls.

```forth file=040-cc-prep.fth
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

It resets every cursor and counter, primes the built-in macros, points
the region globals at `cc-src-buf`, runs `cc-prep-process-region`, and
copies the result back.  Resetting `cc-src-pos` to 0 and `cc-src-line`
to 1 means the lexer sees a fresh source: as far as it is concerned,
the preprocessor never happened.

The macro table outlives the pass.  When the lexer reads `NULL` it
calls `cc-macro-find-int` and produces a numeric token with value 0;
the same goes for `EOF`, `EXIT_FAILURE`, and any `#define` recorded
here.  That is what the file header means by "macro substitution
happens at LEX time."

## Try it

**Small check:** run the preprocessor on the four lines of `tri.c`
that mention `ROWS` and print the rewritten buffer.  Seed-forth has no file-`include` or
`-e` flag, so we concatenate the four Forth files it needs onto
stdin, strip Forth comments, and then append the C source.  The
driver defines a one-shot word `dump-prep` that calls
`cc-load-stdin` (which slurps whatever remains on stdin), runs
`cc-preprocess`, walks the rewritten buffer byte by byte, then
prints the macro count as a digit:

```sh
./build.sh
{
  cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 040-cc-prep.fth
  cat <<'FORTH'
    : dump-prep
      cc-load-stdin cc-preprocess
      [lit] 0
      begin, dup cc-src-len @ < while,
        dup cc-src-buf + c@ emit
        [lit] 1 +
      repeat, drop
      cc-macro-count @ [lit] 48 + emit
      bye ;
    dump-prep
FORTH
  cat <<'C'
#define ROWS 4
    int w[ROWS];
    t.rows = ROWS;
    if (t.stars == ROWS * ROWS) return t.stars;
C
} | ./seed-forth
```

After the REPL executes the final `dump-prep` token, `cc-load-stdin`
reads the rest of stdin (the C source) into `cc-src-buf`,
`cc-preprocess` runs, and the loop prints this (the first line is
empty):

```text

    int w[ROWS];
    t.rows = ROWS;
    if (t.stars == ROWS * ROWS) return t.stars;
8
```

The directive is gone but its newline stayed, so every later line
keeps its number.  All four `ROWS` are still there.  The preprocessor
only recorded `ROWS → 4` as the eighth macro, after the seven
built-ins of §7, which is the `8` on the last line.  Substitution
happens at lex time (Ch 23), when `cc-next-token` consults
`cc-macro-find-int` and emits a numeric token in place of the
identifier.  Registering at prep time and substituting at lex time
makes object-like macros almost free.

**Layer check:** there is no root-level `test-040-cc-prep.fth`.
The preprocessor's fixtures are gates: `tests/cc/G14a.c` (integer
`#define`), `G14b.c` (`#include "…"` through the `tests/cc/`
fallback) and `G5.c` (an elided `#include <stdio.h>` plus the
built-in macros).  Two more cover paths M2-Planet's source never
walks, so Stage-A parity alone could not catch a regression there.
`tests/cc/G-indented-define.c` holds an indented `#define`, which
registers only because the directive handler skips blanks before the
`#` (§6).  `tests/cc/H-comment-directive.c` ends a macro definition
with a block comment spanning a newline, which `cc-prep-skip-to-eol`
must consume whole (§3).  `tests/cc/run-gates.sh` runs both
alongside the other 30 gates.

**Bootstrap relevance:** Stage-A exercises the include path (the
two quote-includes left in the monolith's headers) and the
built-in macros such as `NULL` and `stdout`.  No integer `#define`
reaches the preprocessor there, so the gates above are the only
check on that path.

```sh
./build.sh
tests/cc/stage-a-check.sh
```

## Exercises

1. **★★ Trace.** M2-Planet uses a small set of preprocessor features.  Skim
   `tests/cc/M*.c` and `tests/cc/G*.c`, then list every directive
   you find.  Compare against §5's grammar — anything not covered?

2. **★★★ Verify.** The macro table is 256 entries × 8 bytes per column, plus a 16
   KiB name pool.  Could you shrink either without breaking the
   bootstrap?  Instrument `cc-macro-count` and
   `cc-macro-name-pool-pos` at the end of `cc-preprocess` to find
   out.

3. **★★★ Extend.** Function-style macros (`#define FOO(x) ((x)+1)`) are not
   supported.  Construct a test case that depends on this missing
   feature and observe how the compiler handles it.  Where would
   the smallest possible patch go?

4. **★★ Modify.** There is no `#include` cycle check.  Read §4: what stops
   a file that includes itself, at what depth, and with which exit
   status?  Sketch the smallest patch that would report a cycle as
   a cycle instead.

5. **★★ Extend.** `#undef NAME` and `#ifdef NAME` are absent.  Estimate the
   complexity cost of adding each.  Which would touch more code?

## After this chapter

The compiler can flatten C source: project includes splice in
recursively, integer macros are recorded for the lexer, and the lexer
sees one continuous stream with its position reset to zero.  Every
M2-Planet header reaches the parser as the same text the GCC reference
path sees.  For `tri.c` that stream is 470 bytes, still characters,
still spelling `ROWS` four times.  Ch 23 turns it into tokens, and
that is where `ROWS` finally becomes 4.

## Takeaways

- The preprocessor is a separate pass that rewrites `cc-src-buf` through a 2 MiB scratch buffer and rewinds it, so the lexer sees expanded text from position 0.
- Macro names are deep-copied into a dedicated pool because `cc-prep-copy-back` is about to overwrite the source they were read from.
- `#include "…"` recurses through a 4-slot × 64 KiB pool with per-depth save/restore, while `#include <…>` is elided in favour of built-in macros for `NULL`, `EOF` and the standard fds.

Next: Chapter 23 — The Lexer.
