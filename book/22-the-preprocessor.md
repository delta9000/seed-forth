# Chapter 22 — The Preprocessor

```text
Missing capability: C source still arrives as include-laden, macro-bearing, #if-guarded text.
New pattern: rewrite cc-in-buf into cc-src-buf, expanding macros and dropping false groups as it goes.
Artifact after this chapter: a flattened C stream with directives removed and supported macros expanded.
Proof link: pnut.c, exactly as shipped, comes out token for token what GCC's cpp makes of it.
```

`tri.c` opens with `#define ROWS 4`, a line no C parser accepts, and
then uses `ROWS` four times.  Before the parser sees the program,
something has to delete that line and make each `ROWS` mean 4.  That
is the preprocessor's job, and in this compiler it does all of it in
one pass over the text, before the lexer starts.  The preprocessor file
`040-cc-prep.fth` handles `#include "…"` (spliced in recursively),
object-like and function-like `#define`s with any body, `#undef`, and
conditional compilation with `#if`, `#ifdef`, `#ifndef`, `#elif`,
`#else` and `#endif`. What comes out is plain C with directives removed;
a self-referential macro can intentionally leave its own name behind.

M2-Planet's own source asks little of this: two headers included
through the `tests/cc/` fallback and one `#ifndef CC_H` include
guard.  The rest is there for pnut, the C compiler that
`tests/pnut/sf-pnut-check.sh` builds from its unmodified `pnut.c`.
pnut's source is configured almost entirely by `#if` and `#ifdef`
on names like `target_i386_linux`, and it writes helpers as
function-like macros: `#define TERNARY(cond, if_true, if_false) …`,
`#define get_child_(expected_parent_node, node, i) get_child(node, i)`.
On it, this pass produces the same tokens as GCC's preprocessor
(the check at the end of the chapter).

The design has three parts.  A *walker* reads a *region* (a buffer, a
length, a position) byte by byte and writes to a *sink*.  A macro
use pushes the replacement text as a new region and walks it, which
is how the result is scanned again for more macros.  Arguments and
replacements are built in temporary sinks carved out of a scratch
area.  And a stack of conditional states says whether the current
line is kept or dropped.

## 1. The contract, the sink and the scratch area

The file's header comment states the whole contract.

```forth file=040-cc-prep.fth
\ 040-cc-prep.fth — the C preprocessor.
\
\ One pass over the raw source, before the lexer sees anything:
\   1. Legacy #include "FILE" searches as given, then under tests/cc/;
\      angle includes are dropped in favour of built-in header shims.
\      Direct mode resolves quoted names relative to their includer, then
\      explicit include directories; angle names use those directories.
\   2. #define NAME BODY and #define NAME(PARAMS) BODY record a macro, and
\      #undef NAME forgets it.  Outside directives every identifier is
\      looked up: a macro's name is replaced by its body (for a function-
\      like macro, with the call's arguments put in for the parameters),
\      and the replacement is scanned again for more macros.
\   3. #if, #ifdef, #ifndef, #elif, #else and #endif keep or drop lines;
\      #if and #elif evaluate a constant expression in which
\      `defined NAME` asks whether NAME is a macro.
\   4. #error stops the compiler. SysV #line sets presumed source locations;
\      GNU numeric markers fail explicitly. Other directives are dropped.
\   5. Everything else is copied through unchanged.
\
\ Every source line keeps its line number, so cc-die's "line N" is the line
\ of the spliced-together program: a dropped line or directive leaves its
\ newline behind, and the newlines a directive or a macro call spanning
\ several lines swallows are written out right after it.
\
\ The pass reads a region (addr, len, pos) byte by byte and writes to a
\ sink.  The first region is the program in cc-in-buf; an #include pushes
\ the included file as a new region, and a macro expansion pushes the
\ replacement text.  The sink is cc-src-buf, the buffer the lexer reads
\ (030), except while an argument or a replacement is being built in a
\ temporary buffer.
\
\ Depends on 010-lib.fth (open/close, digit?, bytes-eq, control flow),
\ 020-cc-arena.fth (cc-src-line, cc-die, cc-check-cap) and 030-cc-io.fth
\ (cc-in-buf, cc-src-buf, cc-src-init, cc-read-all, ident-start?/ident-cont?,
\ cell[], cc-name-find).  #if's expression evaluator comes from
\ 100-cc-expr.fth, through the deferred word cc-pp-eval.

```

The last paragraph matters to everything after it: the line numbers
`cc-die` reports (Ch 21) are the flattened program's, and the pass
keeps them equal to the physical lines of the source with its
includes spliced in.  A dropped line still leaves its newline behind.

Output goes to a *sink*: a buffer, how much of it is written, its
size, and the error code to die with when it fills.  The four cells
sit in one block so that a sink can be parked and restored by copying
32 bytes, the same trick Ch 23 uses for the lexer's state.

```forth file=040-cc-prep.fth
\ ===========================================================================
\ The sink
\ ===========================================================================
\ Where output bytes go: one 4-cell block, so a sink can be parked and
\ restored by copying the block.

create cc-pp-sink  [lit] 32 allot
cc-pp-sink             constant cc-pp-out          \ buffer address
cc-pp-sink [lit]  8 +  constant cc-pp-out-pos      \ bytes written so far
cc-pp-sink [lit] 16 +  constant cc-pp-out-cap      \ buffer size
cc-pp-sink [lit] 24 +  constant cc-pp-out-code     \ die code when it fills

\ Direct mode keeps unavailable-token metadata outside the C byte stream.
\ The selected sink's shadow bytes are derived from its existing buffer.
variable cc-prep-direct                         \ explicit headers; no shim macros
variable cc-pp-out-flags
: cc-pp-select-flags-default ;
defer cc-pp-select-flags-fwd
' cc-pp-select-flags-default is cc-pp-select-flags-fwd

\ cc-prep-emit-byte ( b -- )  Append b to the sink; die with the sink's
\ code if it is full.  Counts lines as it goes, so a failure during the
\ pass reports the line of the output it had reached.
: cc-prep-emit-byte
  cc-pp-out-pos @ 1+ cc-pp-out-cap @ cc-pp-out-code @ cc-check-cap
  cc-pp-out-flags @ if, [lit] 0 cc-pp-out-flags @ cc-pp-out-pos @ + c! then,
  dup cc-pp-out @ cc-pp-out-pos @ + c!
  [lit] 1 cc-pp-out-pos +!
  nl = if, [lit] 1 cc-src-line +! then, ;

: cc-pp-copy-byte-default c@ cc-prep-emit-byte ;
defer cc-pp-copy-byte-fwd
' cc-pp-copy-byte-default is cc-pp-copy-byte-fwd

\ cc-pp-emit-bytes ( a u -- )  Append u bytes from a.
: cc-pp-emit-bytes
  begin, dup while,
    over cc-pp-copy-byte-fwd
    1- swap 1+ swap
  repeat,
  2drop ;

```

`cc-prep-emit-byte` is the only word that writes.  It checks the
capacity, stores, and counts newlines into `cc-src-line`, so a
failure during the pass reports the line the output had reached.  The
main sink is `cc-src-buf` (Ch 21) with code 36; the other two kinds
are below.

```forth file=040-cc-prep.fth
\ cc-pp-copy4 ( src dst -- )  Copy one 4-cell block (a sink).
: cc-pp-copy4
  [lit] 32
  begin, dup while,
    [lit] 8 -                                    ( src dst off )
    >r  over r@ + @  over r@ + !  r>
  repeat,
  drop 2drop ;

\ Parked sinks, innermost last.  Every sink parked here but the first
\ two (the source buffer and the macro pool, §2) belongs to a temp
\ buffer, and each temp buffer takes cc-pp-temp-cap bytes of the scratch
\ area below, so the scratch runs out (code 43) before this stack could:
\ it has room for as many temp buffers as the scratch holds, plus two.
[lit] 34 constant cc-pp-sinks-cap
create cc-pp-sinks  cc-pp-sinks-cap [lit] 32 * allot
variable cc-pp-sink-depth

\ cc-pp-sink-push ( addr pos cap code -- )  Park the current sink and make
\ a new one.
: cc-pp-sink-push
  cc-pp-sink  cc-pp-sink-depth @ [lit] 32 * cc-pp-sinks +  cc-pp-copy4
  [lit] 1 cc-pp-sink-depth +!
  cc-pp-out-code ! cc-pp-out-cap ! cc-pp-out-pos ! cc-pp-out !
  cc-pp-select-flags-fwd ;

\ cc-pp-sink-pop ( -- )  Resume writing to the most recently parked sink.
: cc-pp-sink-pop
  [lit] 1 cc-pp-sink-depth -!
  cc-pp-sink-depth @ [lit] 32 * cc-pp-sinks +  cc-pp-sink  cc-pp-copy4
  cc-pp-select-flags-fwd ;

```

`cc-pp-sink-push` parks the current sink on a stack and installs a
new one; `cc-pp-sink-pop` brings the parked one back.  The stack
needs no check of its own: every sink parked on it, but the first
two, belongs to a temporary buffer (below), and the scratch area
those come from runs out first.

A macro call needs text of its own: each argument, expanded, and then
the body with the arguments put in.  That text is built in *temporary
sinks* taken from a 2 MiB scratch area, used as a stack.

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Scratch space for temporary text
\ ===========================================================================
\ A macro call's arguments and its replacement are built here, in temporary
\ sinks allocated from the top of a stack.  A temp buffer being written
\ owns cc-pp-temp-cap bytes; once finished it keeps only its text.  Each
\ macro call gives back everything it took when it is done.

[lit] 2097152 constant cc-pp-scratch-cap          \ 2 MiB
create cc-pp-scratch  cc-pp-scratch-cap allot
variable cc-pp-scratch-top                        \ first free byte
[lit] 65536 constant cc-pp-temp-cap               \ one temp buffer's room

\ A copied identifier that encountered a disabled macro remains unavailable
\ during every later argument/replacement rescan. One shadow byte per text
\ byte retains that token property without changing spelling or line counts.
\ Only scratch and final-source sinks can contain expanded tokens; raw input,
\ includes and stored replacement bodies have no such flags.
variable cc-pp-flags-base
: cc-pp-flag-address ( address -- shadow-address-or-zero )
  cc-prep-direct @ 0= cc-pp-flags-base @ 0= or if, drop [lit] 0 exit, then,
  dup cc-pp-scratch >= over cc-pp-scratch cc-pp-scratch-cap + < and if,
    cc-pp-scratch - cc-pp-flags-base @ + exit,
  then,
  dup cc-src-buf >= over cc-src-buf cc-src-cap + < and if,
    cc-src-buf - cc-pp-flags-base @ cc-pp-scratch-cap + + exit,
  then, drop [lit] 0 ;
: cc-pp-unavailable? ( address -- flag )
  cc-pp-flag-address dup if, c@ then, ;
: cc-pp-select-flags
  cc-pp-out @ cc-pp-flag-address cc-pp-out-flags ! ;
' cc-pp-select-flags is cc-pp-select-flags-fwd
: cc-pp-copy-marked-byte ( address -- )
  dup cc-pp-unavailable? >r c@ cc-prep-emit-byte
  r> cc-pp-out-flags @ 0= 0= and if,
    true cc-pp-out-flags @ cc-pp-out-pos @ + 1- c!
  then, ;
' cc-pp-copy-marked-byte is cc-pp-copy-byte-fwd
: cc-pp-flags-init
  [lit] 0 cc-pp-out-flags !
  cc-prep-direct @ if,
    cc-src-cap cc-src-direct-cap > if, [lit] 43 cc-die then,
    cc-pp-flags-base @ 0= if,
      cc-pp-scratch-cap cc-src-direct-cap + [lit] 43 cc-workspace-map
      cc-pp-flags-base !
    then,
  then,
  cc-pp-select-flags ;
\ A paste containing an unavailable token needs token-level placemarker
\ rules beyond this text engine. Reject it instead of re-expanding a token
\ or leaking metadata into its spelling. Ordinary paste operands are intact.
: cc-pp-paste-bytes ( address count -- )
  2dup begin, dup while,
    over cc-pp-unavailable? if, [lit] 47 cc-die then,
    swap 1+ swap 1-
  repeat, 2drop cc-pp-emit-bytes ;

\ cc-pp-scratch-alloc ( n -- a )  Take n bytes; die 43 if they aren't
\ there (macro calls nested some 32 deep inside each other's arguments).
: cc-pp-scratch-alloc
  cc-pp-scratch-top @ swap over +                  ( a new-top )
  dup cc-pp-scratch - cc-pp-scratch-cap [lit] 43 cc-check-cap
  cc-pp-scratch-top ! ;

\ cc-pp-temp-begin ( -- )  Park the sink; write to a new temp buffer.  A
\ temp buffer that fills dies with 37.
: cc-pp-temp-begin
  cc-pp-temp-cap cc-pp-scratch-alloc  [lit] 0  cc-pp-temp-cap  [lit] 37
  cc-pp-sink-push ;

\ cc-pp-temp-end ( -- a u )  Finish the temp buffer: answer its text, give
\ back the room it did not use, and resume the parked sink.
: cc-pp-temp-end
  cc-pp-out @ cc-pp-out-pos @                      ( a u )
  2dup + cc-pp-scratch-top !
  cc-pp-sink-pop ;

```

`cc-pp-temp-begin` takes 64 KiB off the top of the stack and makes it
the sink; `cc-pp-temp-end` answers the text written there, gives
back the part of the 64 KiB it did not use, and resumes the parked
sink.  So a finished argument occupies only its own length, and the
next temporary starts right after it.  A macro call remembers
`cc-pp-scratch-top` before it starts and restores it when it is done
(§5), which frees everything it built.  An argument that overflows
its 64 KiB is code 37 (`tests/cc/die-37-macro-scratch-full.sh`); a
scratch area used up, which takes some 32 macro calls nested inside
each other's arguments, is 43 (`die-43-macro-scratch-deep.sh`).

## 2. The macro table

The default macro table is six parallel arrays of 4,096 cells and a counter,
the same layout Ch 24 uses for the symbol table, indexed with
`cell[]` (Ch 21). Legacy mode retains its original 1,024-definition limit.

```forth file=040-cc-prep.fth
\ ===========================================================================
\ The macro table
\ ===========================================================================
\ Parallel arrays indexed by macro number (cell[], 030).  A macro's name
\ and body are copied into cc-macro-pool: the source they came from may be
\ an include-pool slot that the next #include at that depth overwrites.
\   name-addr / name-len  the name; #undef sets the length to 0, so the
\                         entry can never match again
\   body-addr / body-len  the replacement text.  In a function-like macro's
\                         body ordinary parameter k is encoded as 1, k.
\                         Direct mode also uses 2, k for #k and 3 for ##.
\   params                -1 for an object-like macro; else how many
\                         parameters the function-like macro has
\   busy                  -1 while the macro's own replacement is being
\                         scanned: a macro met inside itself is not
\                         expanded again, so no expansion loops.


[lit] 4096 constant cc-macro-default-cap
variable cc-macro-limit
cc-macro-default-cap cc-macro-limit !
: cc-macro-cap ( -- entries ) cc-macro-limit @ ;
create cc-macro-default-name-addr cc-macro-default-cap [lit] 8 * allot
variable cc-macro-name-addr-buffer
cc-macro-default-name-addr cc-macro-name-addr-buffer !
: cc-macro-name-addr ( -- address ) cc-macro-name-addr-buffer @ ;
create cc-macro-default-name-len cc-macro-default-cap [lit] 8 * allot
variable cc-macro-name-len-buffer
cc-macro-default-name-len cc-macro-name-len-buffer !
: cc-macro-name-len ( -- address ) cc-macro-name-len-buffer @ ;
create cc-macro-default-body-addr cc-macro-default-cap [lit] 8 * allot
variable cc-macro-body-addr-buffer
cc-macro-default-body-addr cc-macro-body-addr-buffer !
: cc-macro-body-addr ( -- address ) cc-macro-body-addr-buffer @ ;
create cc-macro-default-body-len cc-macro-default-cap [lit] 8 * allot
variable cc-macro-body-len-buffer
cc-macro-default-body-len cc-macro-body-len-buffer !
: cc-macro-body-len ( -- address ) cc-macro-body-len-buffer @ ;
create cc-macro-default-params cc-macro-default-cap [lit] 8 * allot
variable cc-macro-params-buffer
cc-macro-default-params cc-macro-params-buffer !
: cc-macro-params ( -- address ) cc-macro-params-buffer @ ;
create cc-macro-default-busy cc-macro-default-cap [lit] 8 * allot
variable cc-macro-busy-buffer
cc-macro-default-busy cc-macro-busy-buffer !
: cc-macro-busy ( -- address ) cc-macro-busy-buffer @ ;
variable cc-macro-count

[lit] 262144 constant cc-macro-pool-cap           \ 256 KiB
create cc-macro-pool  cc-macro-pool-cap allot
variable cc-macro-pool-pos

\ Direct GCC maps six equally sized parallel arrays; the text pool is unchanged.
\ Fixed opt-in policy; changing one array never changes legacy macro limits.
[lit] 4608 constant cc-macro-direct-cap
variable cc-macro-direct-base
: cc-prep-default-workspace ( -- )
  cc-macro-default-cap cc-macro-limit !
  cc-macro-default-name-addr cc-macro-name-addr-buffer !
  cc-macro-default-name-len cc-macro-name-len-buffer !
  cc-macro-default-body-addr cc-macro-body-addr-buffer !
  cc-macro-default-body-len cc-macro-body-len-buffer !
  cc-macro-default-params cc-macro-params-buffer !
  cc-macro-default-busy cc-macro-busy-buffer !
;
: cc-prep-direct-workspace ( -- )
  cc-macro-direct-base @ 0= if,
    cc-macro-direct-cap [lit] 48 *
    [lit] 34 cc-workspace-map cc-macro-direct-base !
  then,
  cc-macro-direct-cap cc-macro-limit !
  cc-macro-direct-base @ cc-macro-direct-cap [lit] 0 * + cc-macro-name-addr-buffer !
  cc-macro-direct-base @ cc-macro-direct-cap [lit] 8 * + cc-macro-name-len-buffer !
  cc-macro-direct-base @ cc-macro-direct-cap [lit] 16 * + cc-macro-body-addr-buffer !
  cc-macro-direct-base @ cc-macro-direct-cap [lit] 24 * + cc-macro-body-len-buffer !
  cc-macro-direct-base @ cc-macro-direct-cap [lit] 32 * + cc-macro-params-buffer !
  cc-macro-direct-base @ cc-macro-direct-cap [lit] 40 * + cc-macro-busy-buffer !
;

\ cc-pp-to-pool ( -- )  Make the macro pool the sink (die 35 when full).
: cc-pp-to-pool
  cc-macro-pool cc-macro-pool-pos @
  cc-prep-direct @ if, cc-macro-pool-cap else, [lit] 65536 then, [lit] 35
  cc-pp-sink-push ;

\ cc-pp-from-pool ( -- )  Keep what was written to the pool; resume the
\ parked sink.
: cc-pp-from-pool
  cc-pp-out-pos @ cc-macro-pool-pos !
  cc-pp-sink-pop ;

\ cc-pp-pool-copy ( a u -- a' u )  Copy u bytes into the pool.
: cc-pp-pool-copy
  cc-macro-pool cc-macro-pool-pos @ + >r          ( a u ; R: a' )
  cc-pp-to-pool  dup >r cc-pp-emit-bytes  cc-pp-from-pool
  r> r> swap ;

```

A macro's name and body are *copied* into `cc-macro-pool`.  A
`#define` inside an included file is read out of that file's
include-pool slot (§4), and the next `#include` at the same depth
reads a new file into the same slot; a pointer into the slot would
then point at someone else's bytes.  The pool is filled by making it
the sink: `cc-pp-to-pool` parks the current sink and writes from the
pool's end, and `cc-pp-from-pool` keeps what was written.  A full pool
is code 35.

```forth file=040-cc-prep.fth
\ cc-macro-record ( name-a name-u body-a body-u params -- )  Add an entry
\ whose name and body already sit in the pool.  Dies with code 34 if the
\ table already holds cc-macro-cap macros.
: cc-macro-record
  cc-macro-count @ 1+
  cc-prep-direct @ if, cc-macro-cap else, [lit] 1024 then,
  [lit] 34 cc-check-cap
  cc-macro-count @ >r
  r@ cc-macro-params    cell[] !
  r@ cc-macro-body-len  cell[] !
  r@ cc-macro-body-addr cell[] !
  r@ cc-macro-name-len  cell[] !
  r@ cc-macro-name-addr cell[] !
  [lit] 0 r> cc-macro-busy cell[] !
  [lit] 1 cc-macro-count +! ;

\ cc-macro-add ( name-a name-u body-a body-u -- )  Add an object-like
\ macro, copying name and body into the pool (the built-in macros).
: cc-macro-add
  >r >r cc-pp-pool-copy r> r> cc-pp-pool-copy
  true cc-macro-record ;

\ cc-macro-find ( a u -- i | -1 )  The newest macro named a u, so a later
\ #define of the same name wins.
: cc-macro-find
  cc-macro-name-addr cc-macro-name-len cc-macro-count @ cc-name-find ;

```

`cc-macro-record` files an entry whose name and body are already in
the pool; a 1,025th macro is code 34.  `cc-macro-add`, which copies
both first, is for the built-in macros (§8).  Lookup is Ch 21's
`cc-name-find`, which walks newest-first, so a later `#define` of the
same name shadows the earlier one.  `#undef` sets the name's length
to 0: `cc-name-find` compares lengths first, and no name has length 0.

The body of a function-like macro is stored with its parameters
already found: `#define ADD(a, b) ((a) + (b))` stores the thirteen
bytes `((` 1 0 `) + (` 1 1 `))`, where 1 0 and 1 1 are two-byte
markers for parameters 0 and 1.  Byte 1 never occurs in C text, so
substitution (§5) needs no second look at identifiers.

## 3. Regions, owed newlines and the byte walkers

The preprocessor walks one region at a time: a base address, a length
and a position.  `cc-prep-in-file` says whether the region is a source
file, where a line may be a directive, or macro text being scanned
again, where it may not.

```forth file=040-cc-prep.fth
\ ===========================================================================
\ The region being read
\ ===========================================================================
\ cc-prep-in-file is true while the region is a source file, where a line
\ may be a directive; false while it is macro text being scanned again.

variable cc-prep-src-addr
variable cc-prep-src-len
variable cc-prep-src-pos
variable cc-prep-in-file
variable cc-prep-at-line-start                    \ true at the start of a line

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
\ Used to recognise two-byte markers such as /* and */.
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

\ cc-prep-at? ( c1 c2 -- f )  True if the next two bytes are c1 c2.
: cc-prep-at?
  cc-prep-peek2 = swap cc-prep-peek = and ;

```

Every read goes through `cc-prep-peek` and `cc-prep-advance`, the same
shape as Ch 21's `cc-peek-char` / `cc-next-char` but pointed at
whichever buffer is current: `cc-in-buf` for the program, a 256 KiB
include slot, or a replacement in the scratch area.  (Ch 21's reader
cannot be reused: it walks only `cc-src-buf`, and its cursor is the
lexer's.)  `cc-prep-peek2` looks one byte further, and `cc-prep-at?`
asks whether the next two bytes are a given pair, which is how `/*`,
`*/`, `//` and a backslash before a newline are recognised.

Some newlines are consumed without being written: the ones inside a
`/* … */` that trails a directive, a `#define` continued with a
backslash, a macro call whose arguments run over several lines.  Each
is *owed*:

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Newlines that are owed
\ ===========================================================================
\ A newline swallowed without being written (inside a directive's comment,
\ a continued line, a macro call's arguments) is counted here and written
\ out after the directive or the macro call, so later lines keep their
\ numbers.

variable cc-pp-pending-nl

: cc-pp-flush-nl
  begin, cc-pp-pending-nl @ while,
    nl cc-prep-emit-byte
    [lit] 1 cc-pp-pending-nl -!
  repeat, ;

```

`cc-pp-flush-nl` pays them back.  The walker calls it right after a
directive, a macro call made at file level (§5, §6), or a completed
literal containing a continued physical line.  The removed newline
belongs after the token, where it cannot change the string's contents.
The next line still starts where the source's next line starts.

Comments and literals need care in a text pass: a `'` inside a
comment is not a character literal, a `//` inside a string is not a
comment, and a `#` inside either is not a directive.  One walker per
construct steps over each whole.  What happens to the bytes stepped
over depends on the caller, so it is a mode: copy them (`put-emit`),
count their newlines as owed (`put-count`), or nothing (`put-drop`).

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Walking comments and literals
\ ===========================================================================
\ One walker per construct; what happens to each byte walked over is set by
\ cc-pp-put-mode: put-emit copies it to the sink, put-count only counts its
\ newlines as owed, put-drop does nothing.

[lit] 0 constant put-drop
[lit] 1 constant put-emit
[lit] 2 constant put-count
variable cc-pp-put-mode
variable cc-pp-line-control                     \ -1 operand, 2 prefix scan

\ cc-pp-put ( c -- )  Dispose of one walked-over byte.
: cc-pp-put
  cc-pp-put-mode @ put-emit = if, cc-prep-emit-byte exit, then,
  cc-pp-put-mode @ put-count = if,
    nl = if, [lit] 1 cc-pp-pending-nl +! then, exit,
  then,
  drop ;

\ cc-pp-take ( -- )  Put the current byte and step past it.
: cc-pp-take  cc-prep-peek cc-pp-put cc-prep-advance ;

\ Source #line operands fail closed on unsupported splices inside comments.
\ Detect CRLF as well as LF, even though the general engine only splices LF.
: cc-pp-line-continuation?
  backslash nl cc-prep-at? if, true exit, then,
  backslash [lit] 13 cc-prep-at? if,
    cc-prep-src-pos @ [lit] 2 + cc-prep-src-len @ < if,
      cc-prep-src-addr @ cc-prep-src-pos @ + [lit] 2 + c@ nl = exit,
    then,
  then, [lit] 0 ;

\ Consume a known LF or CRLF continuation, disposing of only its newline
\ through the caller's put mode. The physical source cursor still moves
\ past every byte, so location macros retain physical line accounting.
: cc-pp-take-continuation
  cc-prep-advance
  cc-prep-peek [lit] 13 = if, cc-prep-advance then,
  cc-pp-take ;

\ cc-pp-block-comment ( -- )  pos at "/*": walk through the closing "*/",
\ or to EOR.
: cc-pp-block-comment
  cc-pp-take cc-pp-take
  begin,
    cc-prep-eor? if,
      cc-pp-line-control @ if, [lit] 49 cc-die then, exit,
    then,
    [char] * [char] / cc-prep-at? 0=
  while,
    cc-pp-line-control @ cc-pp-line-continuation? and if,
      \ Prefix lookahead also crosses ordinary comments. A splice is
      \ inert there unless it follows '*', which could hide a closer.
      cc-pp-line-control @ [lit] 2 <> if, [lit] 49 cc-die then,
      cc-prep-src-addr @ cc-prep-src-pos @ + 1- c@ [char] * = if,
        [lit] 49 cc-die
      then,
    then,
    cc-pp-take
  repeat,
  cc-pp-take cc-pp-take ;

\ cc-pp-line-comment ( -- )  pos at "//": walk to the newline, which is
\ left for the caller.
: cc-pp-line-comment
  begin,
    cc-prep-eor? 0= cc-prep-peek nl <> and
  while,
    cc-pp-line-control @ cc-pp-line-continuation? and if, [lit] 49 cc-die then,
    cc-pp-take
  repeat, ;

\ cc-pp-literal-splices ( -- )  Remove physical continuations before
\ interpreting escapes, including between a backslash and its escaped byte.
: cc-pp-literal-splices
  begin, backslash nl cc-prep-at? while,
    cc-prep-advance cc-prep-advance
    cc-pp-put-mode @ put-drop <> if, [lit] 1 cc-pp-pending-nl +! then,
  repeat, ;

\ cc-pp-literal ( -- )  pos at a ' or ": walk through the closing quote.
\ A backslash takes the next logical byte with it; an unclosed literal
\ stops at the end of its logical line.
: cc-pp-literal
  cc-prep-peek cc-pp-take                          ( q )
  begin,
    cc-pp-literal-splices
    cc-prep-eor? if, drop exit, then,
    cc-prep-peek nl = if, drop exit, then,
    cc-prep-peek backslash = if,
      cc-pp-take cc-pp-literal-splices
      cc-prep-eor? 0= if, cc-pp-take then,
    else,
      cc-prep-peek over = if, drop cc-pp-take exit, then,
      cc-pp-take
    then,
  again, ;

```

`cc-pp-literal` handles `'…'` and `"…"` alike, removing physical continuations before keeping each backslash
with the next logical byte so `"\""` does not end early, and stopping at
the end of the line if the literal is never closed (C does not let a
literal cross a line).

```forth file=040-cc-prep.fth
\ cc-prep-skip-to-eol ( -- )  Step to the end of the line: pos stops on the
\ newline (or at EOR).  A /* comment */ or a backslash-newline on the way
\ is stepped over whole, and the newlines inside it are owed.
: cc-prep-skip-to-eol
  put-count cc-pp-put-mode !
  begin,
    cc-prep-eor? 0= cc-prep-peek nl <> and
  while,
    [char] / [char] * cc-prep-at? if,
      cc-pp-block-comment
    else,
      backslash nl cc-prep-at? if, cc-prep-advance then,
      cc-pp-take
    then,
  repeat, ;

\ The shared text engine does not join split identifier tokens or splice
\ line comments. In #line operands fail closed on those phase-two forms;
\ whitespace-separated and literal continuations retain their usual path.
: cc-pp-line-splice-boundary
  cc-pp-line-control @ 0= if, exit, then,
  cc-prep-src-pos @ 0= if, exit, then,
  cc-prep-src-addr @ cc-prep-src-pos @ + 1- c@ space? if, exit, then,
  cc-prep-src-pos @ [lit] 2 + cc-prep-src-len @ >= if, exit, then,
  cc-prep-src-addr @ cc-prep-src-pos @ + [lit] 2 + c@ space? 0= if,
    [lit] 49 cc-die
  then, ;

\ cc-pp-line-slice ( -- a u )  The rest of the directive line, from pos to
\ (not including) the newline that ends it; pos moves there.  Comments and
\ backslash-newlines stay in the slice (scanning it counts their newlines).
: cc-pp-line-slice
  cc-prep-src-addr @ cc-prep-src-pos @ +  cc-prep-src-pos @   ( a start )
  put-drop cc-pp-put-mode !
  begin,
    cc-prep-eor? 0= cc-prep-peek nl <> and
  while,
    cc-prep-peek dup [char] " = swap [char] ' = or if,
      cc-pp-literal
    else,
      [char] / [char] / cc-prep-at? if,
        cc-pp-line-comment
      else,
        [char] / [char] * cc-prep-at? if,
          cc-pp-block-comment
        else,
          backslash nl cc-prep-at? if,
            cc-pp-line-splice-boundary cc-prep-advance
          then,
          cc-prep-advance
        then,
      then,
    then,
  repeat,
  cc-prep-src-pos @ swap - ;

```

`cc-prep-skip-to-eol` finishes a directive line.  It leaves the
newline for the walker to write, and steps over a trailing
`/* … */` whole even when the comment runs onto the next lines, owing
their newlines; stopping at the first newline would leave a stray
`*/` for the lexer (`tests/cc/H-comment-directive.c`).
`cc-pp-line-slice` is its cousin for `#if` and `#elif`: it answers the
rest of the line as a slice, to be expanded and evaluated (§7).

Names and numbers come next.

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Identifiers and numbers
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

\ cc-prep-ident= ( a u -- f )  True if the identifier just read is a u.
: cc-prep-ident=
  dup cc-prep-ident-len @ = if,
    cc-prep-ident-addr @ swap bytes-eq
  else,
    2drop [lit] 0
  then, ;

\ cc-pp-need-name ( -- )  Read the name a directive requires (#ifdef NAME,
\ defined NAME) into cc-prep-ident-{addr,len}; die 42 if there is none.
: cc-pp-need-name
  cc-prep-skip-blanks
  cc-prep-peek ident-start? 0= if, [lit] 42 cc-die then,
  cc-prep-read-ident ;

\ cc-pp-need-rparen ( -- )  Step past the ')' that closes `defined(NAME`
\ or a #define's parameter list; die 47 if it isn't there.
: cc-pp-need-rparen
  cc-prep-skip-blanks
  cc-prep-peek [char] ) <> if, [lit] 47 cc-die then,
  cc-prep-advance ;

\ cc-pp-copy-number ( -- )  A number is copied whole, suffix and all, so
\ the letters in 0x1F or 10UL are never taken for an identifier.
: cc-pp-copy-number
  begin,
    cc-prep-peek ident-cont?  cc-prep-peek [char] . = or
  while,
    cc-prep-peek cc-prep-emit-byte cc-prep-advance
  repeat, ;

```

`cc-pp-copy-number` copies a number together with any letters in it,
so that in `0x1F`, `10UL` or `1e5` nothing is taken for an
identifier and looked up as a macro.

## 4. `#include` and its bounded file pool

An included file needs somewhere to live while it is walked.  The
pool has four 256 KiB slots, one per nesting depth (pnut's `exe.c`
is 145 KB).

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Include buffer pool (4 slots × 256 KiB).
\ ===========================================================================

[lit] 262144 constant cc-prep-inc-slot-cap
[lit] 4      constant cc-prep-inc-slot-count

create cc-prep-inc-pool  cc-prep-inc-slot-cap cc-prep-inc-slot-count * allot
variable cc-prep-inc-depth
variable cc-prep-inc-top                         \ direct-mode bytes in use
[lit] 32 constant cc-prep-direct-depth

\ cc-prep-inc-slot-addr ( depth -- addr )
: cc-prep-inc-slot-addr
  cc-prep-inc-slot-cap *  cc-prep-inc-pool + ;

```

A header is looked up under two names, so the file needs a small path
builder.

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

```

`cc-prep-build-path` concatenates a prefix, the name and a NUL into
`cc-prep-path-buf`; a path that would not fit its 1,024 bytes is code
33.  The only prefixes ever used are the empty one and `tests/cc/`,
and the loader tries them in that order:

```forth file=040-cc-prep.fth
\ Direct mode keeps include directories explicit and relative to the process
\ working directory.  Quote includes first search the including file's
\ directory; angle includes search only the configured directories.
[lit] 32 constant cc-prep-include-max
create cc-prep-include-dirs  cc-prep-include-max cc-prep-path-cap * allot
create cc-prep-include-lens  cc-prep-include-max [lit] 8 * allot
variable cc-prep-include-count
create cc-prep-source-path  cc-prep-path-cap allot
variable cc-prep-source-len
create cc-prep-file-paths  cc-prep-direct-depth 1+ cc-prep-path-cap * allot
create cc-prep-file-lens   cc-prep-direct-depth 1+ [lit] 8 * allot
variable cc-prep-inc-mode                         \ 1=quote, 2=angle

\ Source provenance is separate from flattened diagnostic line numbers.
\ Each live file caches a physical-line cursor. Macro replacement text keeps
\ its invocation location; raw argument slices can recover their own lines.
variable cc-pp-location-enabled
variable cc-pp-location-line
variable cc-pp-location-rescan
variable cc-pp-location-depth
variable cc-pp-location-object-root
: cc-pp-location-begin ( object-like? -- )
  cc-pp-location-depth @ 0= if, cc-pp-location-object-root ! else, drop then,
  [lit] 1 cc-pp-location-depth +! ;
: cc-pp-location-end [lit] 1 cc-pp-location-depth -! ;
create cc-pp-file-base    cc-prep-direct-depth 1+ [lit] 8 * allot
create cc-pp-file-end     cc-prep-direct-depth 1+ [lit] 8 * allot
create cc-pp-file-cursor  cc-prep-direct-depth 1+ [lit] 8 * allot
create cc-pp-file-line    cc-prep-direct-depth 1+ [lit] 8 * allot
\ Physical cursors never change for #line: an offset supplies the logical
\ line, including when argument prescan revisits an earlier source slice.
\ Virtual names never change cc-prep-file-paths, used for include search.
create cc-pp-file-offset  cc-prep-direct-depth 1+ [lit] 8 * allot
create cc-pp-file-names   cc-prep-direct-depth 1+ cc-prep-path-cap * allot
create cc-pp-file-name-len cc-prep-direct-depth 1+ [lit] 8 * allot
: cc-pp-logical-name
  cc-prep-inc-depth @ cc-prep-path-cap * cc-pp-file-names + ;
: cc-pp-location-cell  cc-prep-inc-depth @ swap cell[] ;
: cc-pp-location-enter
  cc-prep-src-addr @ dup cc-pp-file-base cc-pp-location-cell !
  dup cc-pp-file-cursor cc-pp-location-cell !
  cc-prep-src-len @ + cc-pp-file-end cc-pp-location-cell !
  [lit] 1 cc-pp-file-line cc-pp-location-cell !
  [lit] 0 cc-pp-file-offset cc-pp-location-cell !
  true cc-pp-file-name-len cc-pp-location-cell ! ;
: cc-pp-location-at ( address -- )
  cc-pp-location-enabled @ 0= cc-pp-location-rescan @ or if, drop exit, then,
  dup cc-pp-file-base cc-pp-location-cell @ < if, drop exit, then,
  dup cc-pp-file-end cc-pp-location-cell @ >= if, drop exit, then,
  dup cc-pp-file-cursor cc-pp-location-cell @ < if,
    cc-pp-file-base cc-pp-location-cell @ cc-pp-file-cursor cc-pp-location-cell !
    [lit] 1 cc-pp-file-line cc-pp-location-cell !
  then,
  cc-pp-file-cursor cc-pp-location-cell @
  begin, 2dup > while,
    dup c@ nl = if, [lit] 1 cc-pp-file-line cc-pp-location-cell +! then,
    1+
  repeat,
  nip cc-pp-file-cursor cc-pp-location-cell !
  cc-pp-file-line cc-pp-location-cell @
  cc-pp-file-offset cc-pp-location-cell @ + cc-pp-location-line ! ;

: cc-prep-config-reset
  [lit] 0 cc-prep-direct !  [lit] 0 cc-prep-include-count !
  [lit] 0 cc-prep-source-len ! ;

\ cc-prep-copy-path ( a u dst -- )  Copy a path including a new terminator.
: cc-prep-copy-path
  >r dup cc-prep-path-cap 1- [lit] 33 cc-check-cap
  begin, dup while,
    over c@ r@ c!  r> 1+ >r  swap 1+ swap 1-
  repeat,
  2drop [lit] 0 r> c! ;

: cc-prep-source-name
  dup cc-prep-source-len ! cc-prep-source-path cc-prep-copy-path ;

: cc-prep-add-include
  cc-prep-include-count @ 1+ cc-prep-include-max [lit] 33 cc-check-cap
  [lit] 0 cc-prep-path-out ! cc-prep-append
  cc-prep-path-out @ if,
    cc-prep-path-buf cc-prep-path-out @ + 1- c@ [char] / <> if,
      [char] / cc-prep-path-buf cc-prep-path-out @ + c!
      [lit] 1 cc-prep-path-out +!
    then,
  then,
  cc-prep-path-out @ dup cc-prep-include-count @ cc-prep-include-lens cell[] !
  cc-prep-path-buf swap
  cc-prep-include-count @ cc-prep-path-cap * cc-prep-include-dirs +
  cc-prep-copy-path
  [lit] 1 cc-prep-include-count +! ;

\ cc-prep-directory ( a u -- a dir-u )  Prefix through the final slash.
: cc-prep-directory
  begin, dup while,
    2dup + 1- c@ [char] / = if, exit, then,
    1-
  repeat, ;

: cc-prep-current-path
  cc-prep-inc-depth @ cc-prep-path-cap * cc-prep-file-paths + ;

: cc-prep-record-path
  cc-prep-path-out @ cc-prep-inc-depth @ 1+ cc-prep-file-lens cell[] !
  cc-prep-path-buf cc-prep-path-out @
  cc-prep-inc-depth @ 1+ cc-prep-path-cap * cc-prep-file-paths +
  cc-prep-copy-path ;

\ ===========================================================================
\ File loading.  Reads a file into the current include-pool slot.
\ ===========================================================================
\ Linux O_RDONLY = 0.
: cc-prep-try-open  [lit] 0 [lit] 0 open ;         ( path-addr -- fd )

variable cc-prep-load-name-a
variable cc-prep-load-name-u

\ cc-prep-load-file ( path-a path-u -- buf-a buf-u )
\ Legacy mode tries the literal name then tests/cc/<name>, using a slot
\ per depth.  Direct mode uses the includer and explicit directories,
\ packing live files into the pool.  Dies with 31 at the depth limit,
\ 30 if no path opens, and 32 when the include pool is full.
: cc-prep-open-include
  \ Absolute names are already complete in either include form.
  cc-prep-load-name-u @ if,
    cc-prep-load-name-a @ c@ [char] / = if,
      [lit] 0 [lit] 0 cc-prep-load-name-a @ cc-prep-load-name-u @
      cc-prep-build-path cc-prep-path-buf cc-prep-try-open exit,
    then,
  then,
  cc-prep-inc-mode @ [lit] 1 = if,
    cc-prep-current-path cc-prep-inc-depth @ cc-prep-file-lens cell[] @
    cc-prep-directory cc-prep-load-name-a @ cc-prep-load-name-u @
    cc-prep-build-path cc-prep-path-buf cc-prep-try-open
    dup 0< 0= if, exit, then, drop
  then,
  [lit] 0
  begin, dup cc-prep-include-count @ < while,
    dup cc-prep-path-cap * cc-prep-include-dirs +
    over cc-prep-include-lens cell[] @
    cc-prep-load-name-a @ cc-prep-load-name-u @ cc-prep-build-path
    cc-prep-path-buf cc-prep-try-open
    dup 0< 0= if, nip exit, then, drop 1+
  repeat,
  drop true ;

: cc-prep-load-file
  cc-prep-load-name-u ! cc-prep-load-name-a !
  cc-prep-inc-depth @ 1+
  cc-prep-direct @ if, cc-prep-direct-depth else, cc-prep-inc-slot-count then,
  [lit] 31 cc-check-cap
  cc-prep-direct @ if,
    cc-prep-open-include
  else,
    [lit] 0 [lit] 0 cc-prep-load-name-a @ cc-prep-load-name-u @
    cc-prep-build-path cc-prep-path-buf cc-prep-try-open
    dup 0< if,
      drop cc-prep-tests-prefix cc-prep-tests-prefix-len
      cc-prep-load-name-a @ cc-prep-load-name-u @
      cc-prep-build-path cc-prep-path-buf cc-prep-try-open
    then,
  then,
  dup 0< if, drop [lit] 30 cc-die then,
  >r
  cc-prep-direct @ if,
    cc-prep-record-path
    cc-prep-inc-pool cc-prep-inc-top @ +
    r@ over cc-prep-inc-slot-cap cc-prep-inc-slot-count *
    cc-prep-inc-top @ - [lit] 32 cc-read-all
    dup cc-prep-inc-top +!
  else,
    cc-prep-inc-depth @ cc-prep-inc-slot-addr
    r@ over cc-prep-inc-slot-cap [lit] 32 cc-read-all
  then,
  r> close drop ;

```

`cc-prep-load-file` tries the literal path first (which catches
absolute paths and anything relative to the current directory: pnut's
`#include "x86.c"` is found because the check runs the compiler in
`vendor/pnut`), then `tests/cc/<path>`, where the test inputs live.
If the depth already fills all four slots it dies with code 31; if
neither path opens, 30.  The hard-coded `tests/cc/` prefix is the only
coupling between production code and test layout in the compiler, a
deliberate shortcut.  The file is read with Ch 21's `cc-read-all`,
aimed at the slot for the current `cc-prep-inc-depth`; a file that
fills its slot is code 32.  The directive handler that uses all this
comes in §7.

## 5. Macro expansion

Expansion and walking call each other: the walker (§6) meets a
macro's name and expands it, and expanding means walking the
replacement.  The walker and the directive dispatcher are defined
later, so they are reached through deferred words (Ch 12).

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Scanning: the main walker and macro expansion
\ ===========================================================================
\ cc-pp-scan walks the current region to its end.  A macro use pushes the
\ replacement as a new region and scans it (cc-pp-expand-text), which
\ calls cc-pp-scan again: the two are mutually recursive, and the
\ directive dispatcher (defined further on) is reached from the walker as
\ well, so both go through deferred words (010-lib.fth).

defer cc-pp-scan-fwd
defer cc-prep-handle-directive-fwd
defer cc-pp-rescan-tail-fwd

\ cc-pp-expand-text ( a u -- )  Scan the text a u (macro text, never a
\ file) as a region of its own, then return to the region we were in.  A
\ blank on either side keeps the replacement from gluing onto its
\ neighbours (`-N` with N defined as -1 is `- -1`, not `--1`).
: cc-pp-expand-text
  cc-prep-src-addr @ >r  cc-prep-src-len @ >r  cc-prep-src-pos @ >r
  cc-prep-in-file @ >r  cc-prep-at-line-start @ >r
  cc-prep-src-len ! cc-prep-src-addr !  [lit] 0 cc-prep-src-pos !
  [lit] 0 cc-prep-in-file !
  bl cc-prep-emit-byte  cc-pp-scan-fwd  bl cc-prep-emit-byte
  r> cc-prep-at-line-start !  r> cc-prep-in-file !
```

`cc-pp-expand-text` is the whole of rescanning.  It parks the current
region's five cells on the return stack, makes the text a region of
its own (not a file, so no directives), walks it, and restores.  A
name met in that walk is looked up and expanded in turn; one met in
the region below, after the replacement ends, belongs to that
region's walk.  The blanks it writes on either side keep a
replacement from gluing onto its neighbours: C's preprocessor works
on tokens, this one on text, and without them `2-NEG` with `NEG`
defined as `-1` would become `2--1`, a decrement.

`#if` needs one special name.  While an `#if` line is being expanded,
`defined NAME` and `defined(NAME)` must be answered before `NAME`
itself is expanded:

```forth file=040-cc-prep.fth
  r> cc-prep-src-pos !  r> cc-prep-src-len !  r> cc-prep-src-addr ! ;

\ ---------------------------------------------------------------------------
\ `defined` in #if and #elif
\ ---------------------------------------------------------------------------
\ While an #if line is being expanded, cc-pp-in-if is true and
\ `defined NAME` / `defined(NAME)` becomes 1 or 0, before NAME itself could
\ be expanded.

variable cc-pp-in-if
create cc-pp-n-defined  s, defined

\ cc-pp-defined ( -- )  `defined` has just been read.
: cc-pp-defined
  cc-prep-skip-blanks
  cc-prep-peek lparen = dup if, cc-prep-advance then,
  cc-pp-need-name
  cc-prep-ident-addr @ cc-prep-ident-len @ cc-macro-find 0< 0=   ( paren? f )
  swap if, cc-pp-need-rparen then,
  if, [char] 1 else, [char] 0 then, cc-prep-emit-byte ;

\ ---------------------------------------------------------------------------
\ Function-like macro calls
\ ---------------------------------------------------------------------------

```

A function-like macro's name is a call only if a `(` follows,
possibly on a later line; otherwise it stays a plain name, as in C.

```forth file=040-cc-prep.fth
\ cc-pp-paren-ahead? ( -- f )  After a function-like macro's name: true,
\ with pos past it, if the next thing (blanks, newlines and LF or CRLF
\ continuations skipped) is '('.  Otherwise pos is left where it was, and
\ the name is not a call.
: cc-pp-paren-ahead?
  cc-prep-src-pos @ [lit] 0                        ( pos0 nls )
  begin,
    cc-pp-line-continuation? if,                   \ leave pos at its nl
      cc-prep-advance cc-prep-peek [lit] 13 = if, cc-prep-advance then,
    then,
    cc-prep-peek bl =  cc-prep-peek tab = or  cc-prep-peek nl = or
  while,
    cc-prep-peek nl = if, 1+ then,
    cc-prep-advance
  repeat,
  cc-prep-peek lparen = if,
    cc-pp-pending-nl +!  drop  cc-prep-advance  true
  else,
    drop  cc-prep-src-pos !  [lit] 0
  then, ;

```

The arguments are found before anything is expanded.  They are slices
of the current region, split at commas that are not inside inner
parentheses, with literals and comments stepped over so that a `,` or
`)` inside them does not count:

```forth file=040-cc-prep.fth
\ A call's arguments are recorded as (addr, len) pairs, 16 bytes each, in a
\ record block taken from the scratch space.
[lit] 16 constant cc-pp-args-max

variable cc-pp-ca-recs                            \ the record block
variable cc-pp-ca-n                               \ arguments so far
variable cc-pp-ca-depth                           \ ( ) nesting inside the call
variable cc-pp-ca-start                           \ where this argument began

\ cc-pp-ca-record ( -- )  The argument from cc-pp-ca-start to pos is done.
\ Dies with 46 past cc-pp-args-max arguments.
: cc-pp-ca-record
  cc-pp-ca-n @ 1+ cc-pp-args-max [lit] 46 cc-check-cap
  cc-pp-ca-recs @ cc-pp-ca-n @ [lit] 16 * +                 ( rec )
  cc-prep-src-addr @ cc-pp-ca-start @ + over !
  cc-prep-src-pos @ cc-pp-ca-start @ -  swap [lit] 8 + !
  [lit] 1 cc-pp-ca-n +! ;

\ cc-pp-collect-args ( recs -- n )  pos is just past the call's '('.  Split
\ the arguments at the commas outside inner parentheses, record each as a
\ slice of the region, and stop past the closing ')'.  A call that runs off
\ the end of its region dies with 44.
: cc-pp-collect-args
  cc-pp-ca-recs !  [lit] 0 cc-pp-ca-n !  [lit] 1 cc-pp-ca-depth !
  cc-prep-src-pos @ cc-pp-ca-start !
  put-drop cc-pp-put-mode !
  begin,
    cc-prep-eor? if, [lit] 44 cc-die then,
    cc-prep-peek
    dup [char] " =  over [char] ' = or if, drop cc-pp-literal else,
    [char] / [char] * cc-prep-at? if, drop cc-pp-block-comment else,
    [char] / [char] / cc-prep-at? if, drop cc-pp-line-comment else,
    dup lparen = if, drop [lit] 1 cc-pp-ca-depth +! cc-prep-advance else,
    dup [char] , =  cc-pp-ca-depth @ [lit] 1 = and if,
      drop cc-pp-ca-record cc-prep-advance
      cc-prep-src-pos @ cc-pp-ca-start !
    else,
    [char] ) = if,
      [lit] 1 cc-pp-ca-depth -!
      cc-pp-ca-depth @ 0= if,
        cc-pp-ca-record cc-prep-advance cc-pp-ca-n @ exit,
      then,
      cc-prep-advance
    else,
      cc-prep-advance
    then, then, then, then, then, then,
  again, ;

```

Each argument is then expanded on its own into a temporary sink, as C
requires: in `TWICE(ADD(1, 2))` the inner call is expanded before it
is put into `TWICE`'s body.  Then the body is written into another
temporary sink with each parameter marker replaced by its argument's
expanded text, between blanks for the same reason as above.

```forth file=040-cc-prep.fth
\ cc-pp-expand-args ( recs n -- )  Expand every argument fully, before it
\ is substituted (C's rule), and record the expanded text in its place.
: cc-pp-expand-args
  begin, dup while,
    1- 2dup [lit] 16 * +                           ( recs k rec )
    dup >r  dup @ swap [lit] 8 + @                 ( recs k a u ; R: rec )
    cc-pp-temp-begin cc-pp-expand-text cc-pp-temp-end
    r@ [lit] 8 + !  r> !
  repeat,
  2drop ;

\ Argument records retain both spellings: ordinary substitution uses the
\ fully expanded argument; # and ## use its unexpanded spelling.
: cc-pp-duplicate-args
  [lit] 16 * dup cc-pp-scratch-alloc >r
  r@ swap
  begin, dup while,
    [lit] 8 - >r over r@ + @ over r@ + ! r>
  repeat,
  drop 2drop r> ;

variable cc-pp-sub-raw
variable cc-pp-sub-recs
variable cc-pp-sub-n

\ cc-pp-substitute ( a u -- )  Write a function-like macro's body, each
\ parameter marker (1, k) replaced by argument k's expanded text between
\ blanks; a parameter with no argument is empty.
: cc-pp-substitute-legacy
  begin, dup while,
    over c@ [lit] 1 = if,
      over 1+ c@                                   ( a u k )
      dup cc-pp-sub-n @ < if,
        [lit] 16 * cc-pp-sub-recs @ +
        bl cc-prep-emit-byte
        dup @ swap [lit] 8 + @ cc-pp-emit-bytes
        bl cc-prep-emit-byte
      else,
        drop
      then,
      swap [lit] 2 + swap [lit] 2 -
    else,
      over c@ cc-prep-emit-byte
      swap 1+ swap 1-
    then,
  repeat,
  2drop ;

```

`busy` stops a macro from expanding inside its own replacement.
`#define SELF SELF` would otherwise loop forever; with the flag, the
inner `SELF` is copied as a name (`tests/cc/P2-fn-macros.c` defines
exactly that and uses `SELF` as a variable).

### Unavailable tokens across rescans

A busy flag belongs to a macro definition, but suppression must also follow
an individual token after that definition stops being busy. Consider
`#define gen_lowpart rtl_hooks.gen_lowpart`: an identity macro around a call
must retain `rtl_hooks.gen_lowpart(...)`, rather than expand the copied
member name into another `rtl_hooks.gen_lowpart`. Direct preprocessing marks
the first byte of an identifier encountered while its macro is disabled.
Argument and replacement copies retain that mark; ordinary identifier lookup
and the tail rescan both check it before trying another expansion.

The mark is stored outside the C spelling. One fixed mapping contains a
2 MiB scratch shadow followed by a 3 MiB source shadow. The active source
interval uses its selected capacity, so native direct mode with the default
2 MiB source does not expose the spare part of that shadow. Raw input,
include storage and saved replacement text have no shadow. The mapping is
allocated on the first direct preprocessing pass, reused without growth,
and inactive in legacy mode. A failed mapping or a source capacity larger
than the fixed shadow reports error 43.

Sink push and pop derive the shadow address from the selected text buffer.
Every fresh emitted byte clears its old shadow byte, preventing marks from
an earlier scratch lifetime or preprocessing pass from escaping into new
text. A forwarding copy captures the source mark before that clearing write,
which also handles copying a byte to its own address. The normal sink bound
is checked before either write. No control-byte marker enters the C stream.

This is deliberately a bounded repair. If either raw operand passed to
`##` contains an unavailable byte anywhere, `cc-pp-paste-bytes` reports
error 47. The check includes a marked identifier away from the pasted edge,
and an unavailable operand paired with an empty operand. These inputs were
accepted by the previous implementation in some cases; the new rejection
narrows support rather than implementing C's complete token and placemarker
rules. Ordinary unmarked pastes remain supported.

The suppression checks (`tests/gcc/macro-suppression-README.md`) compare
maximal-munch preprocessing tokens, preserving punctuator boundaries and
literal spelling. They also exercise shadow boundaries, mapping failures,
mode transitions and output preservation. Three inherited mismatches remain:
deferred-empty tail rescanning, stringification of inserted argument padding,
and pp-numbers containing an exponent sign. This change does not establish
general C-preprocessor conformance or a complete GCC build.

```forth file=040-cc-prep.fth
\ cc-pp-trim-slice ( a u -- a' u' )  Strip argument-edge whitespace.
: cc-pp-trim-slice
  begin, dup if, over c@ space? else, [lit] 0 then, while,
    swap 1+ swap 1-
  repeat,
  begin, dup if, 2dup + 1- c@ space? else, [lit] 0 then, while, 1- repeat, ;

variable cc-pp-string-quote
variable cc-pp-string-escape
variable cc-pp-string-space
variable cc-pp-string-start

: cc-pp-string-byte
  dup [char] " = over backslash = or if, backslash cc-prep-emit-byte then,
  cc-prep-emit-byte ;

variable cc-pp-string-a
variable cc-pp-string-u
: cc-pp-string-peek  cc-pp-string-a @ c@ ;
: cc-pp-string-step
  [lit] 1 cc-pp-string-a +! [lit] 1 cc-pp-string-u -! ;
: cc-pp-string-at?
  cc-pp-string-u @ [lit] 1 > if,
    cc-pp-string-a @ 1+ c@ = swap cc-pp-string-peek = and
  else, 2drop [lit] 0 then, ;

: cc-pp-string-comment
  [char] / [char] * cc-pp-string-at? if,
    cc-pp-string-step cc-pp-string-step
    begin, cc-pp-string-u @ while,
      [char] * [char] / cc-pp-string-at? if,
        cc-pp-string-step cc-pp-string-step exit,
      then,
      cc-pp-string-step
    repeat,
  else,
    begin, cc-pp-string-u @ if, cc-pp-string-peek nl <> else, [lit] 0 then,
    while, cc-pp-string-step repeat,
  then, ;

\ # collapses whitespace and comments, preserving literal contents and
\ escaping quotes/backslashes in the resulting C string token.
: cc-pp-stringify
  \ Whitespace is collapsed below, after physical splices are removed.
  cc-pp-string-u ! cc-pp-string-a !
  [lit] 0 cc-pp-string-quote ! [lit] 0 cc-pp-string-escape !
  [lit] 0 cc-pp-string-space ! true cc-pp-string-start !
  [char] " cc-prep-emit-byte
  begin, cc-pp-string-u @ while,
    backslash nl cc-pp-string-at? if,
      \ Raw-argument line accounting is done by argument prescan.
      cc-pp-string-step cc-pp-string-step
    else,
    cc-pp-string-peek
    cc-pp-string-quote @ if,
      dup cc-pp-string-byte
      cc-pp-string-escape @ if,
        drop [lit] 0 cc-pp-string-escape !
      else,
        dup backslash = if, true cc-pp-string-escape ! then,
        cc-pp-string-quote @ = if, [lit] 0 cc-pp-string-quote ! then,
      then,
      cc-pp-string-step
    else,
      dup space? if,
        drop true cc-pp-string-space ! cc-pp-string-step
      else,
        [char] / [char] * cc-pp-string-at?
        [char] / [char] / cc-pp-string-at? or if,
          drop true cc-pp-string-space ! cc-pp-string-comment
        else,
          cc-pp-string-space @ cc-pp-string-start @ 0= and if,
            bl cc-prep-emit-byte
          then,
          [lit] 0 cc-pp-string-space ! [lit] 0 cc-pp-string-start !
          dup [char] " = over [char] ' = or if, dup cc-pp-string-quote ! then,
          cc-pp-string-byte cc-pp-string-step
        then,
      then,
    then,
    then,
  repeat,
  [char] " cc-prep-emit-byte ;

variable cc-pp-sub-joining

\ The next nonblank body byte after this parameter is the paste marker.
: cc-pp-paste-ahead?
  swap [lit] 2 + swap [lit] 2 - cc-pp-trim-slice
  dup if, drop c@ [lit] 3 = else, 2drop [lit] 0 then, ;

variable cc-pp-arg-index
variable cc-pp-arg-paste
\ Only parameters used outside # and ## undergo argument prescan.
: cc-pp-arg-expanded?
  cc-pp-arg-index !
  dup cc-macro-body-addr cell[] @ swap cc-macro-body-len cell[] @
  [lit] 0 cc-pp-arg-paste !
  begin, dup while,
    over c@
    dup [lit] 1 = if,
      drop
      over 1+ c@ cc-pp-arg-index @ = if,
        2dup cc-pp-paste-ahead? cc-pp-arg-paste @ or 0= if,
          2drop true exit,
        then,
      then,
      [lit] 0 cc-pp-arg-paste ! swap [lit] 2 + swap [lit] 2 -
    else,
    dup [lit] 2 = if,
      drop [lit] 0 cc-pp-arg-paste ! swap [lit] 2 + swap [lit] 2 -
    else,
    dup [lit] 3 = if,
      drop true cc-pp-arg-paste ! swap 1+ swap 1-
    else,
      space? 0= if, [lit] 0 cc-pp-arg-paste ! then,
      swap 1+ swap 1-
    then, then, then,
  repeat, 2drop [lit] 0 ;

\ Arguments used only by #/## (or not used) still owe their source
\ newlines even though no argument prescan walks them.
: cc-pp-count-raw-lines
  begin, dup while,
    over c@ nl = if, [lit] 1 cc-pp-pending-nl +! then,
    swap 1+ swap 1-
  repeat, 2drop ;

\ ( recs n macro -- )  The macro number lives on the return stack while
\ expanding each argument, so nested calls cannot overwrite it.
: cc-pp-expand-used-args
  >r
  begin, dup while,
    1- r@ over cc-pp-arg-expanded? if,
      2dup [lit] 16 * +
      dup >r dup @ swap [lit] 8 + @
      cc-pp-temp-begin cc-pp-expand-text cc-pp-temp-end
      r@ [lit] 8 + ! r> !
    else,
      2dup [lit] 16 * + dup @ swap [lit] 8 + @ cc-pp-count-raw-lines
    then,
  repeat,
  2drop r> drop ;

: cc-pp-sub-argument
  \ ( k raw? -- a u )  Missing parameters have empty text.
  if, cc-pp-sub-raw @ else, cc-pp-sub-recs @ then,
  over cc-pp-sub-n @ < if,
    swap [lit] 16 * + dup @ swap [lit] 8 + @
  else, 2drop [lit] 0 [lit] 0 then, ;

: cc-pp-substitute-direct
  [lit] 0 cc-pp-sub-joining !
  begin, dup while,
    over c@
    dup [lit] 3 = if,
      drop
      begin, cc-pp-out-pos @ if,
        cc-pp-out @ cc-pp-out-pos @ + 1- c@ space?
      else, [lit] 0 then, while, [lit] 1 cc-pp-out-pos -! repeat,
      true cc-pp-sub-joining !
      swap 1+ swap 1- cc-pp-trim-slice
    else,
    dup [lit] 2 = if,
      drop over 1+ c@ true cc-pp-sub-argument cc-pp-stringify
      [lit] 0 cc-pp-sub-joining !
      swap [lit] 2 + swap [lit] 2 -
    else,
    [lit] 1 = if,
      2dup cc-pp-paste-ahead? cc-pp-sub-joining @ or >r
      over 1+ c@ r@ cc-pp-sub-argument
      r@ if,
        cc-pp-trim-slice cc-pp-paste-bytes
      else,
        bl cc-prep-emit-byte cc-pp-emit-bytes bl cc-prep-emit-byte
      then,
      r> drop [lit] 0 cc-pp-sub-joining !
      swap [lit] 2 + swap [lit] 2 -
    else,
      over c@ cc-prep-emit-byte
      [lit] 0 cc-pp-sub-joining ! swap 1+ swap 1-
    then, then, then,
  repeat, 2drop ;

: cc-pp-substitute
  cc-prep-direct @ if, cc-pp-substitute-direct else, cc-pp-substitute-legacy then, ;

\ The busy flag of macro i.
: cc-macro-busy-cell  cc-macro-busy cell[] ;       ( i -- cell )

create cc-pp-location-digits [lit] 24 allot
variable cc-pp-location-digit-count
: cc-pp-location-number ( unsigned -- )
  [lit] 0 cc-pp-location-digit-count !
  begin,
    dup [lit] 10 / swap over [lit] 10 * - [char] 0 +
    cc-pp-location-digits cc-pp-location-digit-count @ + c!
    [lit] 1 cc-pp-location-digit-count +!
    dup 0=
  until, drop
  begin, cc-pp-location-digit-count @ while,
    [lit] 1 cc-pp-location-digit-count -!
    cc-pp-location-digits cc-pp-location-digit-count @ + c@ cc-prep-emit-byte
  repeat, ;
: cc-pp-location-string-byte ( byte -- )
  dup [char] " = over backslash = or if,
    backslash cc-prep-emit-byte cc-prep-emit-byte exit,
  then,
  dup [lit] 32 >= over [lit] 127 < and if, cc-prep-emit-byte exit, then,
  backslash cc-prep-emit-byte
  dup [lit] 64 / [char] 0 + cc-prep-emit-byte
  dup [lit] 8 / [lit] 7 and [char] 0 + cc-prep-emit-byte
  [lit] 7 and [char] 0 + cc-prep-emit-byte ;
create cc-pp-stdin-name s, <stdin>
: cc-pp-location-filename
  [char] " cc-prep-emit-byte
  cc-pp-file-name-len cc-pp-location-cell @ dup 0< if,
    drop cc-prep-current-path cc-prep-inc-depth @ cc-prep-file-lens cell[] @
    dup 0= if, 2drop cc-pp-stdin-name [lit] 7 then,
  else, cc-pp-logical-name swap then,
  begin, dup while,
    over c@ cc-pp-location-string-byte swap 1+ swap 1-
  repeat, 2drop [char] " cc-prep-emit-byte ;

\ cc-pp-expand-object ( i -- )  Scan object-like macro i's body in place of
\ its name.
: cc-pp-expand-object-body
  dup cc-macro-params cell[] @ [lit] 0 [lit] 2 - = if,
    drop cc-pp-location-line @ cc-pp-location-number exit,
  then,
  dup cc-macro-params cell[] @ [lit] 0 [lit] 3 - = if,
    drop cc-pp-location-filename exit,
  then,
  cc-pp-out-pos @ >r
  true over cc-macro-busy-cell !
  dup cc-macro-body-addr cell[] @  over cc-macro-body-len cell[] @
  cc-pp-expand-text
  [lit] 0 swap cc-macro-busy-cell !
  r> cc-prep-direct @ if, cc-pp-rescan-tail-fwd else, drop then, ;
: cc-pp-expand-object
  true cc-pp-location-begin cc-pp-expand-object-body cc-pp-location-end ;

\ cc-pp-expand-call ( i -- )  The '(' of function-like macro i's call has
\ been read.  Collect and expand the arguments, substitute them into the
\ body, and scan the result in place of the call.  A call with more
\ arguments than the macro has parameters dies with 45 (a macro with no
\ parameters takes one empty argument).
: cc-pp-expand-call-body
  cc-pp-out-pos @ >r
  cc-pp-scratch-top @ >r                           ( i ; R: top )
  cc-pp-args-max [lit] 16 * cc-pp-scratch-alloc    ( i recs )
  dup cc-pp-collect-args >r                        ( i recs ; R: top n )
  over cc-macro-params cell[] @ r@ <  r@ [lit] 1 > and if,
    [lit] 45 cc-die
  then,
  r>                                               ( i recs n )
  2dup cc-pp-duplicate-args >r
  cc-prep-direct @ if,
    2dup >r >r
    >r over r> swap cc-pp-expand-used-args
    r> r>
  else,
    2dup cc-pp-expand-args
  then,                                           ( i recs n )
  r> cc-pp-sub-raw !
  cc-pp-temp-begin
  cc-pp-sub-n ! cc-pp-sub-recs !                   ( i )
  dup cc-macro-body-addr cell[] @  over cc-macro-body-len cell[] @
  cc-pp-substitute
  cc-pp-temp-end                                   ( i a u )
  rot true over cc-macro-busy-cell ! >r            ( a u ; R: top i )
  cc-pp-expand-text
  [lit] 0 r> cc-macro-busy-cell !
  r> cc-pp-scratch-top !
  r> cc-prep-direct @ if, cc-pp-rescan-tail-fwd else, drop then, ;
: cc-pp-expand-call
  [lit] 0 cc-pp-location-begin cc-pp-expand-call-body cc-pp-location-end ;

\ Rescan the final token together with the surrounding source.  This is
\ essential for both an alias (DEF_BWLX(mov)) and a computed name such as
\ ELFW(ST_INFO)(bind,type): the final function-like macro's '(' belongs
\ to the outer region, not to the replacement text just scanned.
variable cc-pp-tail-start
variable cc-pp-tail-end
variable cc-pp-tail-name
: cc-pp-rescan-tail
  cc-pp-tail-start !
  cc-pp-out-pos @ cc-pp-tail-end !
  begin, cc-pp-tail-end @ cc-pp-tail-start @ > if,
    cc-pp-out @ cc-pp-tail-end @ + 1- c@ space?
  else, [lit] 0 then, while, [lit] 1 cc-pp-tail-end -! repeat,
  cc-pp-tail-end @ cc-pp-tail-name !
  begin, cc-pp-tail-name @ cc-pp-tail-start @ > if,
    cc-pp-out @ cc-pp-tail-name @ + 1- c@ ident-cont?
  else, [lit] 0 then, while, [lit] 1 cc-pp-tail-name -! repeat,
  cc-pp-tail-name @ cc-pp-tail-end @ = if, exit, then,
  cc-pp-out @ cc-pp-tail-name @ + cc-pp-unavailable? if, exit, then,
  cc-pp-out @ cc-pp-tail-name @ + dup c@ ident-start? 0= if, drop exit, then,
  cc-pp-tail-end @ cc-pp-tail-name @ - cc-macro-find
  dup 0< if, drop exit, then,
  dup cc-macro-busy-cell @ if, drop exit, then,
  dup cc-macro-params cell[] @ 0< if, drop exit, then,
  cc-pp-paren-ahead? if,
    cc-pp-tail-name @ cc-pp-out-pos !
    cc-pp-location-rescan @ >r
    cc-pp-location-object-root @ cc-pp-location-rescan !
    cc-pp-expand-call
    r> cc-pp-location-rescan !
  else, drop then, ;
' cc-pp-rescan-tail is cc-pp-rescan-tail-fwd

\ cc-pp-ident ( -- )  pos is at an identifier.  Replace it if it names a
\ macro that is not busy (a function-like one only when '(' follows);
\ otherwise copy it.  Newlines a file-level call swallowed are owed; write
\ them now.
: cc-pp-ident-work
  cc-prep-read-ident
  cc-pp-in-if @ if,
    cc-pp-n-defined [lit] 7 cc-prep-ident= if, cc-pp-defined exit, then,
  then,
  cc-prep-ident-addr @ cc-pp-unavailable? if,
    cc-prep-ident-addr @ cc-prep-ident-len @ cc-pp-emit-bytes exit,
  then,
  cc-prep-ident-addr @ cc-prep-ident-len @ cc-macro-find     ( i )
  dup 0< 0= if,
    dup cc-macro-busy-cell @ if,
      drop cc-pp-out-pos @ >r
      cc-prep-ident-addr @ cc-prep-ident-len @ cc-pp-emit-bytes
      cc-pp-out-flags @ if, true cc-pp-out-flags @ r@ + c! then,
      r> drop exit,
    then,
  then,
  dup 0< if,
    drop cc-prep-ident-addr @ cc-prep-ident-len @ cc-pp-emit-bytes exit,
  then,
  dup cc-macro-params cell[] @ 0< if,
    cc-pp-expand-object
  else,
    cc-prep-ident-addr @ cc-prep-ident-len @ rot    ( a u i )
    cc-pp-paren-ahead? if,
      nip nip cc-pp-expand-call
    else,
      drop cc-pp-emit-bytes
    then,
  then,
```

`cc-pp-expand-call` puts the pieces together.  It keeps the scratch
top on the return stack, takes a record block for up to 16
arguments (a 17th is code 46), collects and checks them (a call that
runs off the end of its region is code 44, more arguments than
parameters 45), expands them, substitutes, and walks the result with
the macro busy.
Restoring the scratch top at the end frees the arguments and the
substituted body in one store.

`cc-pp-ident` is where the walker hands over a name.  After a call
made at file level it writes the newlines the call's arguments owed,
so the line after a call spread over three lines is still the line
after it.

## 6. Conditional groups and the walker

An `#if` opens a *conditional*; its groups are separated by `#elif`
and `#else` and closed by `#endif`.  The walker needs one fact per
open conditional: is the current group being kept?

```forth file=040-cc-prep.fth
  cc-prep-in-file @ if, cc-pp-flush-nl then, ;
: cc-pp-ident
  cc-pp-location-line @ >r
  cc-prep-src-addr @ cc-prep-src-pos @ + cc-pp-location-at
  cc-pp-ident-work
  r> cc-pp-location-line ! ;

\ ---------------------------------------------------------------------------
\ Conditional groups
\ ---------------------------------------------------------------------------
\ One cell per open #if, innermost last, saying what happens to the lines of
\ its current group:
\   cond-take  the group is compiled
\   cond-done  a group was already taken, or the whole #if sits inside a
\              dropped group: drop lines up to the #endif
\   cond-seek  no group taken yet: drop lines, but an #elif or #else may
\              take the next one

[lit] 0 constant cond-take
[lit] 1 constant cond-done
[lit] 2 constant cond-seek

[lit] 64 constant cc-pp-cond-cap
create cc-pp-cond  cc-pp-cond-cap [lit] 8 * allot
variable cc-pp-cond-depth

\ cc-pp-cond-top ( -- cell )  The innermost open #if's cell.
: cc-pp-cond-top  cc-pp-cond-depth @ 1- cc-pp-cond cell[] ;

\ cc-pp-skipping? ( -- f )  True while lines are being dropped.
: cc-pp-skipping?
  cc-pp-cond-depth @ if,
    cc-pp-cond-top @ cond-take <>
  else,
    [lit] 0
```

Three states are enough.  `cond-take` keeps lines.  `cond-seek`
drops them but lets a later `#elif` or `#else` take over.
`cond-done` drops everything to the `#endif`, either because a group
was already taken or because the whole conditional sits inside a
dropped group.  That last case is why a nested `#if` in a dropped
group is never evaluated (§7): its expression may name things that do
not exist in this configuration.

The walker itself deals with one byte at a time, and with whatever
construct starts there.

```forth file=040-cc-prep.fth
  then, ;

\ ---------------------------------------------------------------------------
\ The walker
\ ---------------------------------------------------------------------------

\ cc-pp-skip-char ( -- )  One byte of a dropped line.  A comment or literal
\ is stepped over whole (a '#' or quote inside it means nothing), and the
\ newlines inside it are owed.
: cc-pp-skip-char
  put-count cc-pp-put-mode !
  [char] / [char] * cc-prep-at? if, cc-pp-block-comment exit, then,
  [char] / [char] / cc-prep-at? if, cc-pp-line-comment  exit, then,
  cc-prep-peek dup [char] " = swap [char] ' = or if, cc-pp-literal exit, then,
  cc-prep-advance ;

\ cc-pp-comment ( -- )  pos at a comment.  A file's comments are copied (the
\ lexer skips them); in macro text a comment is one blank.
: cc-pp-comment
  cc-prep-in-file @ if,
    put-emit cc-pp-put-mode !
  else,
    put-count cc-pp-put-mode !
    bl cc-prep-emit-byte
  then,
  [char] / [char] * cc-prep-at? if,
    cc-pp-block-comment
  else,
    cc-pp-line-comment
  then, ;

\ cc-pp-splice-next ( -- c )  The byte after the run of LF or CRLF
\ continuations at pos: nl for a CRLF line end or at EOR.  pos is kept.
: cc-pp-splice-next
  cc-prep-src-pos @ >r
  begin, cc-pp-line-continuation? while,
    cc-prep-advance
    cc-prep-peek [lit] 13 = if, cc-prep-advance then,
    cc-prep-advance
  repeat,
  cc-prep-eor? if, nl else,
    [lit] 13 nl cc-prep-at? if, nl else, cc-prep-peek then,
  then,
  r> cc-prep-src-pos ! ;

\ cc-pp-whole-punct? ( c -- f )  c is a punctuator that is always a whole
\ token, never the first byte of a longer one: , ; ( ) [ ] { } ~
: cc-pp-whole-punct?
  dup [lit] 44 = over [lit] 59 = or over [lit] 40 = or
  over [lit] 41 = or over [lit] 91 = or over [lit] 93 = or
  over [lit] 123 = or over [lit] 125 = or swap [lit] 126 = or ;

\ In source text a continuation becomes its newline, which is only safe
\ where a separator cannot change the tokens: at the start of the input,
\ before whitespace or EOR, after whitespace, a whole-token punctuator or
\ a complete block comment. It cannot join an identifier, number or
\ delimiter.
: cc-pp-file-splice-safe?
  cc-prep-src-pos @ 0= if, true exit, then,
  cc-pp-splice-next dup bl = over tab = or over nl = or
  over [lit] 11 = or swap [lit] 12 = or if, true exit, then,
  cc-prep-src-addr @ cc-prep-src-pos @ + 1- dup c@ space? if,
    drop true exit,
  then,
  dup c@ cc-pp-whole-punct? if, drop true exit, then,
  cc-prep-src-pos @ [lit] 2 < if, drop [lit] 0 exit, then,
  dup c@ [char] / = swap 1- c@ [char] * = and ;

\ cc-pp-scan-char ( -- )  Deal with the byte at pos, and the construct it
\ starts.  A newline in macro text (an argument spread over lines) is a
\ blank, and the newline is owed.
: cc-pp-scan-char
  cc-prep-peek nl = if,
    cc-prep-advance
    cc-prep-in-file @ if,
      nl cc-prep-emit-byte  true cc-prep-at-line-start !
    else,
      bl cc-prep-emit-byte  [lit] 1 cc-pp-pending-nl +!
    then,
    exit,
  then,
  [lit] 0 cc-prep-at-line-start !
  cc-prep-in-file @ cc-pp-location-enabled @ and if,
    cc-pp-line-continuation? if,
      cc-pp-file-splice-safe? 0= if, [lit] 49 cc-die then,
      put-emit cc-pp-put-mode ! cc-pp-take-continuation exit,
    then,
  then,
  cc-prep-in-file @ if,
    cc-pp-skipping? if, cc-pp-skip-char exit, then,
  then,
  cc-prep-peek dup [char] " = swap [char] ' = or if,
    put-emit cc-pp-put-mode ! cc-pp-literal
    cc-prep-in-file @ if, cc-pp-flush-nl then, exit,
  then,
  [char] / [char] * cc-prep-at?  [char] / [char] / cc-prep-at? or if,
    cc-pp-comment exit,
  then,
  backslash nl cc-prep-at?  cc-prep-in-file @ 0= and if,
    cc-prep-advance cc-prep-advance  [lit] 1 cc-pp-pending-nl +! exit,
  then,
  cc-prep-peek digit?       if, cc-pp-copy-number exit, then,
  cc-prep-peek ident-start? if, cc-pp-ident       exit, then,
  cc-prep-peek cc-prep-emit-byte  cc-prep-advance ;

```

In a dropped group, `cc-pp-skip-char` still steps over comments and
literals whole: an apostrophe in a comment, or a `/*` that closes on a
later line, must not change where the next directive is found.  The
line's newline is still written, so dropped lines keep their numbers.

In a kept group, a literal is copied with backslash-newline pairs removed,
and a comment is copied too
(the lexer skips it, Ch 23), a number is copied whole, and a name goes
to `cc-pp-ident`.  In macro text, a comment or a newline becomes a
blank and the newline is owed: such text is an argument that spanned
lines, and its newlines are paid back after the call. Stringification
also removes these pairs before quoting the raw argument. This bounded
stage handles continued string and character tokens and stringified
arguments; it does not yet implement phase-two splicing of arbitrary
tokens, such as an identifier split across physical lines.

```forth file=040-cc-prep.fth
\ cc-prep-line-is-directive? ( -- f )  -1 iff the first non-blank byte on
\ the current line is '#'.  Does NOT advance pos.
variable cc-prep-isd-save-pos

\ SysV recognizes all C horizontal whitespace at directive boundaries.
\ Reuse the comment walker for lookahead and consumption. Prefix mode
\ permits inert block-comment splices; split delimiters and malformed
\ comments still fail49 before any directive can silently disappear.
: cc-prep-directive-blanks
  begin,
    cc-prep-peek [lit] 13 = if,
      cc-prep-peek2 nl <> if, [lit] 49 cc-die then, cc-prep-advance
    then,
    cc-prep-eor? 0= if,
      cc-prep-peek dup bl = over tab = or over [lit] 11 = or
      swap [lit] 12 = or
    else, [lit] 0 then,
  while, cc-prep-advance repeat, ;

: cc-prep-directive-prefix ( put-mode -- )
  cc-pp-put-mode @ >r cc-pp-put-mode !
  cc-pp-line-control @ >r [lit] 2 cc-pp-line-control !
  begin,
    cc-prep-directive-blanks
    begin, cc-pp-line-continuation? while,
      cc-pp-take-continuation cc-prep-directive-blanks
    repeat,
    \ A splice may split a comment opener before or after '#'. Do not
    \ let that unsupported prefix look like ordinary text or vanish.
    cc-prep-peek [char] / = if,
      cc-prep-advance cc-pp-line-continuation?
      [lit] 1 cc-prep-src-pos -! if, [lit] 49 cc-die then,
    then,
    [char] / [char] * cc-prep-at?
  while,
    cc-pp-block-comment
  repeat,
  [char] / [char] / cc-prep-at? if, cc-pp-line-comment then,
  r> cc-pp-line-control ! r> cc-pp-put-mode ! ;

: cc-prep-line-is-directive?
  cc-prep-src-pos @ cc-prep-isd-save-pos !
  cc-pp-location-enabled @ if,
    put-drop cc-prep-directive-prefix
  else, cc-prep-skip-blanks then,
  cc-prep-peek [char] # = >r
  cc-prep-isd-save-pos @ cc-prep-src-pos !
  r> ;

\ cc-prep-at-directive? ( -- f )  -1 iff pos is at a line start and the line
\ is a directive.  Looks ahead only at a line start, so a long line of
\ blanks is scanned once, not once per byte.
: cc-prep-at-directive?
  cc-prep-at-line-start @ 0= if, [lit] 0 exit, then,
  cc-prep-line-is-directive? ;

\ cc-pp-scan ( -- )  Walk the current region to its end.  In a file, a line
\ that starts with '#' is a directive; the newlines it owes are written
\ right after it.
: cc-pp-scan
  true cc-prep-at-line-start !
  begin,
    cc-prep-eor? 0=
  while,
    cc-prep-in-file @ if, cc-prep-at-directive? else, [lit] 0 then,
    if,
      cc-prep-handle-directive-fwd
      cc-pp-flush-nl
      [lit] 0 cc-prep-at-line-start !
    else,
      cc-pp-scan-char
    then,
  repeat, ;

' cc-pp-scan is cc-pp-scan-fwd

\ ===========================================================================
\ Directives
```

A directive is a line whose first non-blank byte is `#`, and only a
file can have one.  `cc-prep-at-directive?` asks only at the start of
a line: the look-ahead scans the line's leading blanks, and asking at
every byte would rescan them once per byte.
`cc-prep-line-is-directive?` restores the position, so the handler
starts at the line's leading whitespace, and skips it itself (C
allows `   #define X 42`; `tests/cc/G-indented-define.c` checks it).
After a directive, `cc-pp-scan` pays its owed newlines.  The last line
fills in the deferred word from §5.

## 7. The directives

### `#if` and friends

`#if` and `#elif` evaluate an integer constant expression.  The
parser has the same need for array sizes and case labels, so there is
one evaluator, `cc-parse-const` in Ch 28, reached through a deferred
word that `100-cc-expr.fth` fills in.

```forth file=040-cc-prep.fth
\ ===========================================================================

\ ---------------------------------------------------------------------------
\ #if, #ifdef, #ifndef, #elif, #else, #endif
\ ---------------------------------------------------------------------------

\ cc-pp-eval ( a u -- n )  The value of the constant expression a u, which
\ has no macros left in it.  100-cc-expr.fth fills it in: #if uses the
\ same evaluator as array sizes and case labels.
defer cc-pp-eval

\ cc-pp-if-value ( -- f )  Expand the rest of the #if / #elif line into a
\ temp buffer, with `defined` answered first, and evaluate it.
: cc-pp-if-value
  cc-pp-scratch-top @ >r
  cc-pp-line-slice
  true cc-pp-in-if !
  cc-pp-temp-begin cc-pp-expand-text cc-pp-temp-end
  [lit] 0 cc-pp-in-if !
  cc-pp-eval 0= 0=
  r> cc-pp-scratch-top ! ;

```

`cc-pp-if-value` takes the rest of the line as a slice, expands it into
a temporary sink with `cc-pp-in-if` set (so `defined` is answered
first, §5), and hands the text to `cc-pp-eval`.  Any name left after
expansion is 0, as C says.  With `ONE` and `TWO` defined as in
`tests/cc/P1-conditionals.c`, `#if TWO == 2 && defined(ONE)` reaches
the evaluator as `( 1 + 1 ) == 2 && 1`, give or take blanks.

```forth file=040-cc-prep.fth
\ cc-pp-cond-push ( state -- )  Open an #if.  Dies with 38 past
\ cc-pp-cond-cap nested ones.
: cc-pp-cond-push
  cc-pp-cond-depth @ 1+ cc-pp-cond-cap [lit] 38 cc-check-cap
  cc-pp-cond-depth @ cc-pp-cond cell[] !
  [lit] 1 cc-pp-cond-depth +! ;

\ cc-pp-cond-open ( f -- )  Open an #if whose first group is taken iff f.
: cc-pp-cond-open
  if, cond-take else, cond-seek then, cc-pp-cond-push ;

\ cc-pp-defined-name? ( -- f )  #ifdef / #ifndef: is the next name a macro?
: cc-pp-defined-name?
  cc-pp-need-name
  cc-prep-ident-addr @ cc-prep-ident-len @ cc-macro-find 0< 0= ;

\ cc-pp-need-group ( -- )  #elif / #else / #endif with no #if open: die 41.
: cc-pp-need-group
  cc-pp-cond-depth @ 0= if, [lit] 41 cc-die then, ;

create cc-pp-n-if      s, if
create cc-pp-n-ifdef   s, ifdef
create cc-pp-n-ifndef  s, ifndef
create cc-pp-n-elif    s, elif
create cc-pp-n-else    s, else
create cc-pp-n-endif   s, endif

\ cc-pp-cond-directive ( -- f )  If the directive just read is one of the
\ six conditionals, act on it and answer true.  Inside a dropped group an
\ #if is not evaluated: the whole #if is dropped.
: cc-pp-cond-directive
  cc-pp-n-if [lit] 2 cc-prep-ident= if,
    cc-pp-skipping? if,
      cond-done cc-pp-cond-push
    else,
      cc-pp-if-value cc-pp-cond-open
    then,
    true exit,
  then,
  cc-pp-n-ifdef [lit] 5 cc-prep-ident= if,
    cc-pp-skipping? if,
      cond-done cc-pp-cond-push
    else,
      cc-pp-defined-name? cc-pp-cond-open
    then,
    true exit,
  then,
  cc-pp-n-ifndef [lit] 6 cc-prep-ident= if,
    cc-pp-skipping? if,
      cond-done cc-pp-cond-push
    else,
      cc-pp-defined-name? 0= cc-pp-cond-open
    then,
    true exit,
  then,
  cc-pp-n-elif [lit] 4 cc-prep-ident= if,
    cc-pp-need-group
    cc-pp-cond-top @ cond-take = if, cond-done cc-pp-cond-top ! then,
    cc-pp-cond-top @ cond-seek = if,
      cc-pp-if-value if, cond-take cc-pp-cond-top ! then,
    then,
    true exit,
  then,
  cc-pp-n-else [lit] 4 cc-prep-ident= if,
    cc-pp-need-group
    cc-pp-cond-top @ cond-seek = if, cond-take else, cond-done then,
    cc-pp-cond-top !
    true exit,
  then,
  cc-pp-n-endif [lit] 5 cc-prep-ident= if,
    cc-pp-need-group
    [lit] 1 cc-pp-cond-depth -!
    true exit,
  then,
```

`cc-pp-cond-directive` implements the state table.  An `#elif` in a
group that was taken moves to `cond-done`; in a group still seeking,
it evaluates and takes over if true; in `cond-done` it does nothing.
`#else` takes over only from `cond-seek`.  Nesting past 64 is code
38, an `#elif`, `#else` or `#endif` with no `#if` open is 41, an
`#ifdef` or `defined` with no name after it is 42, and an `#if` still
open at the end of the program is 39 (§8).
`tests/cc/P1-conditionals.c` walks every transition, including a
dropped group that holds an unclosed quote.

### `#include`

```forth file=040-cc-prep.fth
  [lit] 0 ;

\ ---------------------------------------------------------------------------
\ #include
\ ---------------------------------------------------------------------------

\ State save / restore for recursive descent.
\ Arrays indexed by cc-prep-inc-depth (parallel to the include-pool slots),
\ so nested includes don't corrupt each other's restore state.
cc-prep-direct-depth constant cc-prep-save-count
create cc-prep-save-addr  cc-prep-save-count [lit] 8 * allot
create cc-prep-save-len   cc-prep-save-count [lit] 8 * allot
create cc-prep-save-pos   cc-prep-save-count [lit] 8 * allot

\ cc-prep-save-slot ( arr -- addr )  Compute the save-slot address for the
\ current include depth.  Arrays are indexed by cc-prep-inc-depth.
: cc-prep-save-slot  cc-prep-inc-depth @ swap cell[] ;

\ cc-prep-handle-include
\ Pre: pos points just past "include".  Skip blanks, read "..." or <...>,
\ then recurse on quoted names, and on angle names in direct mode.
\ At exit pos is at end-of-line (or EOR); newline is NOT consumed.
variable cc-prep-inc-end
variable cc-prep-inc-expanded

: cc-prep-include-literal
  cc-prep-skip-blanks
  [lit] 0 cc-prep-inc-mode !
  cc-prep-peek [char] " = if,
    [lit] 1 cc-prep-inc-mode ! [char] " cc-prep-inc-end !
  else,
    cc-prep-peek [char] < = if,
      [lit] 2 cc-prep-inc-mode ! [char] > cc-prep-inc-end !
    then,
  then,
  cc-prep-inc-mode @ if,
    cc-prep-advance
    cc-prep-src-addr @ cc-prep-src-pos @ + cc-prep-src-pos @
    begin,
      cc-prep-eor? 0= cc-prep-peek cc-prep-inc-end @ <> and
      cc-prep-peek nl <> and
    while,
      cc-prep-inc-expanded @ cc-prep-inc-mode @ [lit] 1 = and
      cc-prep-peek backslash = and if,
        cc-prep-advance
        cc-prep-eor? 0= cc-prep-peek nl <> and if, cc-prep-advance then,
      else, cc-prep-advance then,
    repeat,
    cc-prep-src-pos @ swap -
    cc-prep-direct @ if,
      dup 0= cc-prep-peek cc-prep-inc-end @ <> or if, [lit] 30 cc-die then,
    then,
    cc-prep-peek cc-prep-inc-end @ = if, cc-prep-advance then,
    cc-prep-inc-expanded @ if,
      \ Macro expansion must yield exactly one header operand.
      cc-prep-skip-blanks cc-prep-eor? 0= if, [lit] 30 cc-die then,
      cc-prep-inc-mode @ [lit] 2 = if,
        \ Whitespace-sensitive angle token joining is not yet represented.
        \ Reject it explicitly instead of silently selecting another file.
        2dup begin, dup while,
          over c@ space? if, [lit] 30 cc-die then,
          swap 1+ swap 1-
        repeat, 2drop
      then,
    then,
    [lit] 0 cc-prep-inc-expanded !
    cc-prep-inc-mode @ [lit] 1 = cc-prep-direct @ or if,
      cc-prep-inc-top @ >r
      cc-prep-load-file
      cc-prep-src-addr @ cc-prep-save-addr cc-prep-save-slot !
      cc-prep-src-len  @ cc-prep-save-len  cc-prep-save-slot !
      cc-prep-src-pos  @ cc-prep-save-pos  cc-prep-save-slot !
      [lit] 1 cc-prep-inc-depth +!
      cc-prep-src-len ! cc-prep-src-addr ! [lit] 0 cc-prep-src-pos !
      cc-pp-location-enter
      cc-pp-scan
      [lit] 1 cc-prep-inc-depth -!
      cc-prep-save-addr cc-prep-save-slot @ cc-prep-src-addr !
      cc-prep-save-len  cc-prep-save-slot @ cc-prep-src-len  !
      cc-prep-save-pos  cc-prep-save-slot @ cc-prep-src-pos  !
      r> cc-prep-inc-top !
    else, 2drop then,
```

For a quoted path, the handler measures the name up to the closing
`"`, loads the file, and stashes the current region triple in
`cc-prep-save-{addr,len,pos}` at the *outer* depth.  It then bumps the
depth, points the region globals at the loaded buffer, walks it, and
reads the triple back.  The save arrays are length 4, matching the
pool. Legacy mode retains four nested includes (pnut nests two
deep: `pnut.c` includes `x86.c`, which includes `exe.c` and then
`elf.c`).

In legacy mode, angle-bracket includes (`#include <stdio.h>`) are dropped: there are
no system headers in the bootstrap environment.  What a program needs
from them comes from the compiler itself: the built-in macros of §8,
the built-in typedefs such as `FILE` and `intptr_t` (Ch 31), and the
libc shims such as `putchar` and `malloc` (Chs 26 and 31).

### Computed include operands

```forth file=040-cc-prep.fth
  then, ;

\ A computed operand is rescanned with the same macro engine as C text.
\ Preserve the original file region while parsing its expanded header token;
\ recursive include search and location state still belong to that file.
: cc-prep-handle-include
  [lit] 0 cc-prep-inc-expanded !
  cc-prep-skip-blanks
  cc-prep-peek [char] " = cc-prep-peek [char] < = or
  cc-prep-direct @ 0= or if, cc-prep-include-literal exit, then,
  cc-pp-scratch-top @ >r
  cc-pp-line-slice
  cc-pp-temp-begin cc-pp-expand-text cc-pp-temp-end
  cc-prep-src-addr @ >r cc-prep-src-len @ >r cc-prep-src-pos @ >r
  cc-prep-at-line-start @ >r
  cc-prep-src-len ! cc-prep-src-addr ! [lit] 0 cc-prep-src-pos !
  cc-prep-skip-blanks
  cc-prep-peek [char] " = cc-prep-peek [char] < = or 0= if,
    [lit] 30 cc-die
  then,
  true cc-prep-inc-expanded ! cc-prep-include-literal
  r> cc-prep-at-line-start !
  r> cc-prep-src-pos ! r> cc-prep-src-len ! r> cc-prep-src-addr !
  r> cc-pp-scratch-top ! ;

```

### Parsing C line control

Generated parsers need to name a grammar file while continuing to read the
physical generated source. The earlier per-file state keeps those two names
separate. Here we expand the operand with the existing macro engine, then
validate only the resulting number and optional filename.

The number is a decimal digit sequence, even when it starts with zero.
Checking its range after each digit also bounds every intermediate value.

```forth file=040-cc-prep.fth
\ ---------------------------------------------------------------------------
\ #line: shared macro expansion followed by a bounded operand grammar
\ ---------------------------------------------------------------------------
\ Only the source-location-enabled target uses this directive. The parser
\ accepts decimal 1..2147483647 and an optional ordinary byte string.
\ Simple, octal and hex escapes are decoded; NUL, overflow, wide/Unicode
\ forms and names exceeding 1023 bytes fail49 rather than alter provenance.
variable cc-pp-line-number
variable cc-pp-line-name-size

: cc-pp-line-blanks
  begin, cc-prep-eor? 0= if,
    cc-prep-peek dup space? over [lit] 11 = or swap [lit] 12 = or
  else, [lit] 0 then, while, cc-prep-advance repeat, ;

: cc-pp-line-decimal
  cc-prep-peek digit? 0= if, [lit] 49 cc-die then,
  [lit] 0
  begin, cc-prep-peek digit? while,
    [lit] 10 * cc-prep-peek [char] 0 - +
    dup [lit] 2147483647 > if, [lit] 49 cc-die then,
    cc-prep-advance
  repeat,
  dup 0= if, [lit] 49 cc-die then, cc-pp-line-number ! ;

```

Filename escapes need byte values, so these helpers recognize hex and octal
digits without invoking the C expression parser.

```forth file=040-cc-prep.fth
: cc-pp-line-hex ( c -- n|-1 )
  dup digit? if, [char] 0 - exit, then,
  dup [char] a >= over [char] f <= and if, [char] a - [lit] 10 + exit, then,
  dup [char] A >= over [char] F <= and if, [char] A - [lit] 10 + exit, then,
  drop true ;

: cc-pp-line-octal? ( c -- f )
  dup [char] 0 >= swap [char] 7 <= and ;

```

The escape decoder accepts ordinary C byte escapes. It rejects unsupported
forms and values that would silently truncate the virtual filename.

```forth file=040-cc-prep.fth
: cc-pp-line-escape ( -- byte )
  cc-prep-eor? if, [lit] 49 cc-die then,
  cc-prep-peek cc-prep-advance
  dup [char] x = if,
    drop cc-prep-peek cc-pp-line-hex 0< if, [lit] 49 cc-die then,
    [lit] 0
    begin, cc-prep-peek cc-pp-line-hex dup 0< 0= while,
      swap [lit] 16 * + dup [lit] 255 > if, [lit] 49 cc-die then,
      cc-prep-advance
    repeat, drop exit,
  then,
  dup cc-pp-line-octal? if,
    [char] 0 - [lit] 1
    begin, dup [lit] 3 < cc-prep-peek cc-pp-line-octal? and while,
      swap [lit] 8 * cc-prep-peek [char] 0 - + swap 1+ cc-prep-advance
    repeat, drop exit,
  then,
  dup [char] a = if, drop [lit] 7 exit, then,
  dup [char] b = if, drop [lit] 8 exit, then,
  dup [char] f = if, drop [lit] 12 exit, then,
  dup [char] n = if, drop nl exit, then,
  dup [char] r = if, drop [lit] 13 exit, then,
  dup [char] t = if, drop tab exit, then,
  dup [char] v = if, drop [lit] 11 exit, then,
  dup backslash = over [char] " = or over [char] ' = or over [char] ? = or
  0= if, [lit] 49 cc-die then, ;

```

The filename walker decodes one string into the current include depth's
logical-name slot. Empty names remain distinguishable from an unspecified
physical input name.

```forth file=040-cc-prep.fth
: cc-pp-line-filename
  cc-prep-peek [char] " <> if, [lit] 49 cc-die then,
  cc-prep-advance [lit] 0 cc-pp-line-name-size !
  begin,
    cc-prep-eor? cc-prep-peek nl = or if, [lit] 49 cc-die then,
    cc-prep-peek [char] " <>
  while,
    cc-prep-peek cc-prep-advance
    dup backslash = if, drop cc-pp-line-escape then,
    dup 0= over [lit] 255 > or if, [lit] 49 cc-die then,
    cc-pp-line-name-size @ 1+ cc-prep-path-cap 1- [lit] 49 cc-check-cap
    cc-pp-logical-name cc-pp-line-name-size @ + c!
    [lit] 1 cc-pp-line-name-size +!
  repeat,
  cc-prep-advance ;

```

With the operand grammar defined, the handler can use the shared expansion
engine and restore the original file region. Only after complete validation
does it change the offset for the next physical source line.

```forth file=040-cc-prep.fth
: cc-prep-handle-line
  cc-pp-scratch-top @ >r
  true cc-pp-line-control ! cc-pp-line-slice
  cc-pp-temp-begin cc-pp-expand-text cc-pp-temp-end
  [lit] 0 cc-pp-line-control !
  cc-prep-src-addr @ >r cc-prep-src-len @ >r cc-prep-src-pos @ >r
  cc-prep-at-line-start @ >r
  cc-prep-src-len ! cc-prep-src-addr ! [lit] 0 cc-prep-src-pos !
  cc-pp-line-blanks cc-pp-line-decimal cc-pp-line-blanks
  true cc-pp-line-name-size !
  cc-prep-eor? 0= if, cc-pp-line-filename cc-pp-line-blanks then,
  cc-prep-eor? 0= if, [lit] 49 cc-die then,
  r> cc-prep-at-line-start !
  r> cc-prep-src-pos ! r> cc-prep-src-len ! r> cc-prep-src-addr !
  r> cc-pp-scratch-top !
  \ The terminating physical newline is still unread. Set the offset for
  \ the following line only after validating the entire expanded operand.
  cc-prep-src-addr @ cc-prep-src-pos @ + cc-pp-location-at
  cc-pp-line-number @ cc-pp-file-line cc-pp-location-cell @ 1+ -
  cc-pp-file-offset cc-pp-location-cell !
  cc-pp-line-name-size @ dup 0< if, drop else,
    cc-pp-file-name-len cc-pp-location-cell !
  then, ;

```

The include-search path still names the physical source. The logical state
changes only the source-location macros; compiler diagnostics remain based
on flattened source lines.

### `#define` and `#undef`

```forth file=040-cc-prep.fth
\ ---------------------------------------------------------------------------
\ #define and #undef
\ ---------------------------------------------------------------------------

\ A function-like macro's parameter names, while its body is copied:
\ legacy source slices or direct logical names in scratch, looked up
\ with cc-name-find. Direct scratch is released after copying the body.
[lit] 16 constant cc-pp-params-max
create cc-pp-param-addr  cc-pp-params-max [lit] 8 * allot
create cc-pp-param-len   cc-pp-params-max [lit] 8 * allot
variable cc-pp-param-count

\ cc-pp-read-params ( -- )  pos is just past the '(' of `#define NAME(`.
\ Read the parameter names through the ')'.  Anything but names, commas
\ and blanks before the ')' dies with 47, more than cc-pp-params-max
\ parameters with 48.
: cc-pp-read-params
  [lit] 0 cc-pp-param-count !
  begin,
    cc-prep-skip-blanks
    cc-prep-peek ident-start? if,
      cc-pp-param-count @ 1+ cc-pp-params-max [lit] 48 cc-check-cap
      cc-prep-read-ident
      cc-prep-ident-addr @ cc-pp-param-count @ cc-pp-param-addr cell[] !
      cc-prep-ident-len  @ cc-pp-param-count @ cc-pp-param-len  cell[] !
      [lit] 1 cc-pp-param-count +!
      cc-prep-skip-blanks
    then,
    cc-prep-peek [char] , =
  while,
    cc-prep-advance
  repeat,
  cc-pp-need-rparen ;

\ cc-pp-param? ( -- k | -1 )  Is the identifier just read parameter k?
: cc-pp-param?
  cc-prep-ident-addr @ cc-prep-ident-len @
  cc-pp-param-addr cc-pp-param-len cc-pp-param-count @ cc-name-find ;

\ Parameter-list phase two is local to the direct grammar: remove LF or
\ CRLF continuations, retaining their physical newlines as owed. Do not
\ turn a splice into whitespace: ab\<newline>cd is one parameter name.
: cc-pp-param-splices
  put-count cc-pp-put-mode !
  begin, cc-pp-line-continuation? while,
    cc-pp-take-continuation
  repeat, ;

: cc-pp-param-blanks
  begin,
    cc-prep-skip-blanks
    cc-pp-line-continuation?
  while, cc-pp-param-splices repeat, ;

\ Logical parameter names share one bounded temporary sink (code 37).
\ Its text survives through body encoding; the physical input is untouched.
: cc-pp-param-ident
  cc-pp-out @ cc-pp-out-pos @ + cc-prep-ident-addr !
  begin,
    cc-pp-param-splices
    cc-prep-peek ident-cont?
  while,
    cc-prep-peek cc-prep-emit-byte cc-prep-advance
  repeat,
  cc-pp-out @ cc-pp-out-pos @ + cc-prep-ident-addr @ - cc-prep-ident-len ! ;

\ Direct lists are empty or comma-separated distinct identifiers. Reject
\ missing names, trailing commas and duplicates with 47; retain the existing
\ 16-name limit (48). Comments and variadic forms remain unsupported (47).
: cc-pp-read-direct-params
  [lit] 0 cc-pp-param-count !
  cc-pp-temp-begin cc-pp-param-blanks
  cc-prep-peek [char] ) = if,
    cc-prep-advance cc-pp-temp-end 2drop exit,
  then,
  begin,
    cc-prep-peek ident-start? 0= if, [lit] 47 cc-die then,
    cc-pp-param-count @ 1+ cc-pp-params-max [lit] 48 cc-check-cap
    cc-pp-param-ident
    cc-pp-param? 0< 0= if, [lit] 47 cc-die then,
    cc-prep-ident-addr @ cc-pp-param-count @ cc-pp-param-addr cell[] !
    cc-prep-ident-len @ cc-pp-param-count @ cc-pp-param-len cell[] !
    [lit] 1 cc-pp-param-count +!
    cc-pp-param-blanks
    cc-prep-peek [char] ) = if,
      cc-prep-advance cc-pp-temp-end 2drop exit,
    then,
    cc-prep-peek [char] , <> if, [lit] 47 cc-die then,
    cc-prep-advance cc-pp-param-blanks
  again, ;

\ cc-pp-copy-hash ( -- )  Encode #parameter and ## outside literals.
: cc-pp-copy-hash
  cc-prep-advance
  cc-prep-peek [char] # = if,
    [lit] 3 cc-prep-emit-byte cc-prep-advance
  else,
    cc-prep-skip-blanks
    cc-pp-need-name cc-pp-param?
    dup 0< if, [lit] 47 cc-die then,
    [lit] 2 cc-prep-emit-byte cc-prep-emit-byte
  then, ;

\ cc-pp-copy-body ( -- )  Copy the rest of the #define line to the sink (the
\ macro pool): a comment becomes one blank, a backslash-newline joins the
\ lines (the newline is owed), and a parameter becomes the marker 1, k.
: cc-pp-copy-body
  begin,
    cc-prep-eor? 0= cc-prep-peek nl <> and
  while,
    backslash nl cc-prep-at? if,
      cc-prep-advance cc-prep-advance  [lit] 1 cc-pp-pending-nl +!
    else,
    [char] / [char] * cc-prep-at?  [char] / [char] / cc-prep-at? or if,
      put-count cc-pp-put-mode !
      [char] / [char] * cc-prep-at? if,
        cc-pp-block-comment
      else,
        cc-pp-line-comment
      then,
      bl cc-prep-emit-byte
    else,
    cc-prep-peek dup [char] " = swap [char] ' = or if,
      put-emit cc-pp-put-mode !  cc-pp-literal
    else,
    cc-prep-peek [char] # = cc-prep-direct @ and if,
      cc-pp-copy-hash
    else,
    cc-prep-peek digit? if,
      cc-pp-copy-number
    else,
    cc-prep-peek ident-start? if,
      cc-prep-read-ident
      cc-pp-param? dup 0< if,
        drop cc-prep-ident-addr @ cc-prep-ident-len @ cc-pp-emit-bytes
      else,
        [lit] 1 cc-prep-emit-byte  cc-prep-emit-byte
      then,
    else,
      cc-prep-peek cc-prep-emit-byte  cc-prep-advance
    then, then, then, then, then, then,
  repeat, ;

\ cc-pp-trim ( start -- start )  Drop the blanks that end the text written
\ to the sink since address start.
: cc-pp-trim
  begin,
    cc-pp-out @ cc-pp-out-pos @ +                  ( start end )
    2dup < if,
      1- c@ dup bl = swap tab = or
    else,
      drop [lit] 0
    then,
  while,
    [lit] 1 cc-pp-out-pos -!
  repeat, ;

\ cc-prep-handle-define ( -- )  pos is just past "define".  `NAME(` with no
\ blank before the '(' makes a function-like macro.  The name and the body
\ go to the pool.  A #define with no name is dropped.
: cc-prep-handle-define
  cc-prep-skip-blanks
  cc-prep-peek ident-start? 0= if, exit, then,
  cc-prep-read-ident
  cc-prep-ident-addr @ cc-prep-ident-len @ cc-pp-pool-copy   ( na nu )
  cc-pp-scratch-top @ >r
  cc-pp-location-enabled @ cc-pp-line-continuation? and if,
    cc-pp-param-splices
    \ A join before '(' preserves adjacency; split macro names are outside
    \ this grammar and must not silently define the unjoined prefix.
    cc-prep-peek ident-cont? if, [lit] 47 cc-die then,
  then,
  cc-prep-peek lparen = if,
    cc-prep-advance
    cc-pp-location-enabled @ if, cc-pp-read-direct-params else, cc-pp-read-params then,
    cc-pp-param-count @
  else,
    [lit] 0 cc-pp-param-count !  true
  then,
  >r                                               ( na nu ; R: saved-scratch params )
  cc-pp-location-enabled @ if, cc-pp-param-blanks else, cc-prep-skip-blanks then,
  cc-macro-pool cc-macro-pool-pos @ +              ( na nu ba )
  cc-pp-to-pool  cc-pp-copy-body  cc-pp-trim  cc-pp-from-pool
  cc-macro-pool cc-macro-pool-pos @ + over -       ( na nu ba bu )
  r> cc-macro-record
  r> cc-pp-scratch-top ! ;

\ cc-prep-handle-undef ( -- )  pos is just past "undef".  Forget every
\ definition of the name (a zero length never matches).
: cc-prep-handle-undef
  cc-prep-skip-blanks
  cc-prep-peek ident-start? 0= if, exit, then,
  cc-prep-read-ident
  begin,
    cc-prep-ident-addr @ cc-prep-ident-len @ cc-macro-find
    dup 0< 0=
  while,
    [lit] 0 swap cc-macro-name-len cell[] !
  repeat,
```

A `(` right after the name, with no blank between, makes the macro
function-like. The legacy/native reader keeps source slices. In the explicit
SysV target, `cc-pp-read-direct-params` instead joins physical continuations
before recognizing names and punctuation. For example, `ar` followed by a
backslash-newline and `g` names the single parameter `arg`; a join contributes
no space. A join between an intact macro name and `(` also preserves adjacency.

The SysV reader stores at most 16 distinct names in one 64 KiB temporary
buffer: code 48 bounds the count, code 37 bounds their combined logical bytes,
and code 47 rejects malformed or duplicate names. The temporary survives until
the body has been encoded, then its scratch space is returned. Neither source
bytes nor physical locations are rewritten. Each LF or CRLF continuation owes
one output newline, preserving physical `__LINE__` calls and adding no
continuation-related diagnostic drift. An inherited body-marker caveat remains:
parameter index 10 is encoded as LF and can increment preprocessing diagnostic
lines spuriously; this parser repair does not change that encoding.
Errors inside the definition retain the established flattened start-line
location because owed newlines have not yet been emitted.

This is a bounded parameter grammar, not a general phase-two pass. Spaces and
tabs separate names; comments, variadic lists, form feed and vertical tab remain
unsupported here. A join inside the macro's own name diagnoses 47. Token joins
inside replacement bodies remain a separate preexisting limitation. The
focused proof (`tests/gcc/macro-parameter-splices-check.py`) compares host CPP
and records these boundaries as well as unchanged legacy/native output.

`cc-pp-copy-body` then writes the rest of the line to
the pool: comments become one blank, a backslash-newline joins the
next line (its newline is owed), literals are copied whole, and a
name that is a parameter becomes its marker.  `cc-pp-trim` drops
trailing blanks, so `#define EMPTY` has an empty body and
`#define TWO (ONE + ONE)   ` has a clean one.

The body is not expanded here.  `#define TWICE(x) ADD(x, x)` stores
`ADD(` 1 0 `, ` 1 0 `)`, and `ADD` is looked up when `TWICE` is used,
so a macro may use one defined after it, as in C.

### The dispatcher

```forth file=040-cc-prep.fth
  drop ;

\ ---------------------------------------------------------------------------
\ cc-prep-handle-directive  ( -- )
\ ---------------------------------------------------------------------------
\ Pre: pos is at the line's '#'.  Read the directive's name and dispatch.
\ In a dropped group only the conditionals count.  #error dies with 40.
\ Anything else is dropped.  Always ends at the end of the line.

create cc-prep-name-include  s, include
create cc-prep-name-define   s, define
create cc-prep-name-undef    s, undef
create cc-prep-name-error    s, error
create cc-prep-name-line     s, line

: cc-prep-handle-directive
  cc-pp-location-enabled @ if,
    put-count cc-prep-directive-prefix
  else, cc-prep-skip-blanks then,                 \ leading indent before '#'
  cc-prep-advance                                 \ consume '#'
  cc-pp-location-enabled @ if,
    put-count cc-prep-directive-prefix
  else, cc-prep-skip-blanks then,
  cc-pp-location-enabled @ cc-pp-skipping? 0= and if,
    cc-prep-peek digit? if, [lit] 49 cc-die then,
  then,
  cc-prep-peek ident-start? if,
    cc-prep-read-ident
    cc-pp-location-enabled @ cc-pp-line-continuation? and if,
      [lit] 49 cc-die
    then,
    cc-pp-cond-directive if, cc-prep-skip-to-eol exit, then,
    cc-pp-skipping? 0= if,
      cc-pp-location-enabled @ if,
        cc-prep-name-line [lit] 4 cc-prep-ident= if,
          cc-prep-handle-line exit,
        then,
      then,
      cc-prep-name-include [lit] 7 cc-prep-ident= if,
        cc-prep-handle-include cc-prep-skip-to-eol exit,
      then,
      cc-prep-name-define [lit] 6 cc-prep-ident= if,
        cc-prep-handle-define cc-prep-skip-to-eol exit,
      then,
      cc-prep-name-undef [lit] 5 cc-prep-ident= if,
        cc-prep-handle-undef cc-prep-skip-to-eol exit,
      then,
      cc-prep-name-error [lit] 5 cc-prep-ident= if,
        [lit] 40 cc-die
      then,
    then,
  then,
  cc-prep-skip-to-eol ;

' cc-prep-handle-directive is cc-prep-handle-directive-fwd

```

`cc-prep-handle-directive` reads the directive's name and tries the
six conditionals first, because they must be acted on even in a
dropped group.  The others count only in a kept group: `#include`,
`#define`, `#undef`, and `#error`, which stops the compiler with code
40 (`tests/cc/die-40-error-directive.c` has one in an `#if 0` group
too, which must not fire). The SysV profile handles C `#line` and
rejects numeric markers with code 49; the other profiles drop them.
`#pragma` and other unrecognized directives are dropped.  Each handler returns with `exit,` at once: after an
`#include`, the name just read belongs to the included file.

## 8. The built-in macros and the pass driver

Before the walk starts, the macro table is seeded with the names the
dropped system headers would have supplied:

```forth file=040-cc-prep.fth
\ ===========================================================================
\ Built-in macros
```

Eleven macros: `NULL`, `EOF`, `EXIT_SUCCESS`, `EXIT_FAILURE`,
`stdin`, `stdout`, `stderr` (file descriptors 0 to 2, since this
compiler's `FILE*` is a descriptor; Appendix F), and `open(2)`'s
flags `O_RDONLY`, `O_WRONLY`, `O_CREAT`, `O_TRUNC` with their Linux
values.  `EOF`'s body is `0xFFFFFFFFFFFFFFFF`, one token that the
lexer's 64-bit accumulator reads as -1 (Ch 23), because Ch 20's number
parser cannot write a negative literal.  A program that defines one
of these names itself, as pnut does with `EOF`, shadows the built-in.

```forth file=040-cc-prep.fth
\ ===========================================================================
\ What the dropped system headers would have defined and the subset's
\ programs use: <stdio.h>'s NULL, EOF, stdin/stdout/stderr (file
\ descriptors, see Appendix F), <stdlib.h>'s EXIT_SUCCESS/EXIT_FAILURE and
\ <fcntl.h>'s open(2) flags.

create cc-pp-t0      s, 0
create cc-pp-t1      s, 1
create cc-pp-t2      s, 2
create cc-pp-t64     s, 64
create cc-pp-t512    s, 512
create cc-pp-teof    s, 0xFFFFFFFFFFFFFFFF

create cc-builtin-name-NULL          s, NULL
create cc-builtin-name-EOF           s, EOF
create cc-builtin-name-EXIT_SUCCESS  s, EXIT_SUCCESS
create cc-builtin-name-EXIT_FAILURE  s, EXIT_FAILURE
create cc-builtin-name-stdin         s, stdin
create cc-builtin-name-stdout        s, stdout
create cc-builtin-name-stderr        s, stderr
create cc-builtin-name-O_RDONLY      s, O_RDONLY
create cc-builtin-name-O_WRONLY      s, O_WRONLY
create cc-builtin-name-O_CREAT       s, O_CREAT
create cc-builtin-name-O_TRUNC       s, O_TRUNC

: cc-prep-builtins
  cc-builtin-name-NULL          [lit]  4  cc-pp-t0   [lit] 1  cc-macro-add
  cc-builtin-name-EOF           [lit]  3  cc-pp-teof [lit] 18 cc-macro-add
  cc-builtin-name-EXIT_SUCCESS  [lit] 12  cc-pp-t0   [lit] 1  cc-macro-add
  cc-builtin-name-EXIT_FAILURE  [lit] 12  cc-pp-t1   [lit] 1  cc-macro-add
  cc-builtin-name-stdin         [lit]  5  cc-pp-t0   [lit] 1  cc-macro-add
  cc-builtin-name-stdout        [lit]  6  cc-pp-t1   [lit] 1  cc-macro-add
  cc-builtin-name-stderr        [lit]  6  cc-pp-t2   [lit] 1  cc-macro-add
  cc-builtin-name-O_RDONLY      [lit]  8  cc-pp-t0   [lit] 1  cc-macro-add
  cc-builtin-name-O_WRONLY      [lit]  8  cc-pp-t1   [lit] 1  cc-macro-add
  cc-builtin-name-O_CREAT       [lit]  7  cc-pp-t64  [lit] 2  cc-macro-add
  cc-builtin-name-O_TRUNC       [lit]  7  cc-pp-t512 [lit] 3  cc-macro-add ;

\ ===========================================================================
\ cc-preprocess  ( -- )
\ ===========================================================================
\ Top-level driver.  Walks cc-in-buf and writes the result into cc-src-buf,
\ then rewinds the reader (cc-src-pos 0, cc-src-line 1) for the lexer.  An
\ #if still open at the end dies with 39.

\ Negative parameter tags below -1 identify dynamic object-like builtins.
\ They are real table entries: defined/#ifdef, replacement and undef work
\ through the same lookup as ordinary macros, without fixed line answers.
create cc-pp-name-line s, __LINE__
create cc-pp-name-file s, __FILE__
: cc-prep-location-builtins
  true cc-pp-location-enabled !
  cc-pp-name-line [lit] 8 [lit] 0 [lit] 0 [lit] 0 [lit] 2 - cc-macro-record
  cc-pp-name-file [lit] 8 [lit] 0 [lit] 0 [lit] 0 [lit] 3 - cc-macro-record ;

\ Optional target-owned predefined macros. The default preserves native output.
: cc-prep-target-default ;
defer cc-prep-target-fwd
' cc-prep-target-default is cc-prep-target-fwd

: cc-preprocess
  cc-src-init
  [lit] 0 cc-macro-count !
  [lit] 0 cc-macro-pool-pos !
  [lit] 0 cc-prep-inc-depth !
  [lit] 0 cc-pp-cond-depth !
  [lit] 0 cc-pp-sink-depth !
  [lit] 0 cc-pp-pending-nl !
  [lit] 0 cc-pp-in-if ! [lit] 0 cc-pp-line-control !
  cc-pp-scratch cc-pp-scratch-top !
  cc-src-buf cc-pp-out !  [lit] 0 cc-pp-out-pos !
  cc-src-cap cc-pp-out-cap !  [lit] 36 cc-pp-out-code !
  cc-pp-flags-init
  cc-prep-direct @ 0= if, cc-prep-builtins then,
  [lit] 0 cc-pp-location-enabled ! [lit] 1 cc-pp-location-line !
  [lit] 0 cc-pp-location-rescan ! [lit] 0 cc-pp-location-depth !
  cc-prep-target-fwd
  [lit] 0 cc-prep-inc-top !
  cc-prep-source-path cc-prep-source-len @ cc-prep-file-paths cc-prep-copy-path
  cc-prep-source-len @ cc-prep-file-lens !
  cc-in-buf cc-prep-src-addr !
  cc-in-len @ cc-prep-src-len !
  [lit] 0 cc-prep-src-pos !
  cc-pp-location-enter
  true cc-prep-in-file !
  cc-pp-scan
  cc-pp-cond-depth @ if, [lit] 39 cc-die then,
  cc-pp-out-pos @ cc-src-len !
  [lit] 0 cc-src-pos !
  [lit] 1 cc-src-line ! ;
```

`cc-preprocess` is the only word the rest of the compiler calls.  It
empties `cc-src-buf`, resets every counter, makes `cc-src-buf` the
sink, primes the built-in macros, points the region at `cc-in-buf`
and walks it.  An `#if` still open at the end is code 39.  Then the
sink's length becomes `cc-src-len`, and resetting `cc-src-pos` to 0
and `cc-src-line` to 1 means the lexer starts at the top: as far as it
is concerned, the source it reads is the program.

## Try it

**Small check:** run the preprocessor on a few lines in the style of
`tri.c` and print the rewritten buffer.  Seed-forth has no
file-`include` or `-e` flag, so we concatenate the four Forth files it
needs onto stdin and then append the C source.  The driver defines a
one-shot word `dump-prep` that calls `cc-load-stdin` (which slurps
whatever remains on stdin), runs `cc-preprocess`, and walks the
rewritten buffer byte by byte.  (`#if` is left out: its evaluator
lives in `100-cc-expr.fth`, which this driver does not load.
`#ifdef` needs none.)

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
      bye ;
    dump-prep
FORTH
  cat <<'C'
#define ROWS 4
#define SQUARE(x) ((x) * (x))
#ifdef ROWS
    int w[ROWS];
#else
    int w[1];
#endif
    if (t.stars == SQUARE(ROWS)) return t.stars;
C
} | ./seed-forth
```

After the REPL executes the final `dump-prep` token, `cc-load-stdin`
reads the rest of stdin (the C source) into `cc-in-buf`,
`cc-preprocess` runs, and the loop prints this (the first three lines
are empty, and so are the three between):

```text



    int w[ 4 ];



    if (t.stars ==  ((   4   ) * (   4   )) ) return t.stars;
```

Every directive is gone, and so is the dropped `#else` group, but each
left its newline behind, so `int w` is still on line 4 and the `if` on
line 8.  `ROWS` became ` 4 `, blanks and all.  In `SQUARE(ROWS)` the
argument was expanded first (` 4 `) and then substituted, between
blanks, for both uses of `x`.

**Layer check:** there is no root-level `test-040-cc-prep.fth`.  The
preprocessor's fixtures are gates in `tests/cc/`: `G14a.c` (integer
`#define`), `G14b.c` (`#include "…"` through the `tests/cc/`
fallback), `G5.c` (an elided `#include <stdio.h>` plus the built-in
macros), `G-indented-define.c` and `H-comment-directive.c` (§6, §3),
`P1-conditionals.c` (every conditional directive) and
`P2-fn-macros.c` (function-like macros, rescanning, a self-referring
macro, a call over three lines).  `tests/cc/run-gates.sh` runs them with
the rest, and its die gates `die-30-*` through `die-48-*` check that
each limit and each malformed directive fails with its code and line.

**Bootstrap relevance:** Stage A exercises the include path, the
`#ifndef CC_H` guard around `cc.h` (included a second time, through
`cc_emit.h`, and now dropped the second time) and built-in macros
such as `NULL` and `stdout`.  `tests/pnut/sf-pnut-check.sh` exercises
the rest: pnut's four source files hold some 850 conditional
directives.

```sh
./build.sh
tests/cc/stage-a-check.sh
tests/pnut/sf-pnut-check.sh
```

## Direct TinyCC preprocessing

The default mode preserves the original M2-Planet and pnut contract.
The opt-in direct mode instead reads the real portable headers and
supports the operators used by the pinned TinyCC source. Before calling
`cc-preprocess`, set `true cc-prep-direct !`, register each explicit
include directory with `cc-prep-add-include ( address length -- )`, and
set the main input's pathname with `cc-prep-source-name` when the input
is the file itself. `cc-prep-config-reset` clears that configuration;
ordinary preprocessing preserves it for the next input.

Quoted includes try the directory of the including file before the
registered directories, in order. Angle includes use the registered
directories. Missing angle headers now fail with code 30 rather than
silently disappearing. Included file paths are kept at each nesting
depth, so a header's own relative include does not depend on the shell's
working directory. Direct mode packs the live file contents into the
same 1 MiB include pool, with a depth limit of 32, and raises the macro
limits to 4,096 definitions and a 256 KiB text pool. The direct-GCC driver
selects a separately mapped 4,608-entry table; its text-pool bound is unchanged. Legacy limits and
diagnostic codes are retained.

A direct function-macro call keeps both raw and expanded arguments.
Stringizing reads the raw spelling, compresses whitespace and comments,
and escapes characters inside literal tokens. Pasting strips surrounding
whitespace, joins raw spellings, and rescans the resulting identifier.
Only parameters used outside `#` and `##` are prescanned. Finally, the
last function-macro token is rescanned with the following source, so
both `DEF_BWLX(mov)` and `ELFW(ST_INFO)(bind,type)` can find the opening
parenthesis outside their own replacement regions. This is the targeted
TinyCC profile, not a claim of a complete ISO C preprocessor: variadic
macros and general hide-set rescanning remain outside it.

### C line control for generated parser sources

Original `oyacc-6.6/reader.c` defines the format `#line %d "%s"\n`.
Generated parsers need that
provenance to compile their copied grammar actions. In the SysV profile,
`#line` now changes `__LINE__` and optionally `__FILE__` from the following
source line onward. The directive passes its operand through the existing
macro engine, so aliases, function macros, stringification, and dynamic
location macros retain the engine's established invocation semantics. It
then requires a decimal digit sequence from 1 through 2147483647 and at most
one ordinary string literal. No expression evaluation or string concatenation
is implied. Leading zeroes still mean decimal, as C line control requires.

Each live include has a physical cursor and an independent logical offset
and filename. Resetting a physical cursor for reverse argument prescan keeps
that offset. Entering a header initializes its own state; returning restores
the includer's state by depth. The physical include-search path never changes
when `#line` names a virtual file. Repeated `cc-preprocess` calls reset the
main input's state. Continuations and comments consumed by a directive count
as physical lines before the following line receives its requested number.

Filename strings decode standard simple, octal, and hexadecimal byte escapes,
then use the existing `__FILE__` string encoder. Empty names are valid. This
bounded implementation rejects NUL bytes, values exceeding 255, unsupported
Unicode/wide string forms, invalid escapes, and filenames beyond 1023 decoded
bytes with code 49. Unknown macros, suffixes, signs, expressions, missing
quotes, unterminated comments, extra tokens and out-of-range numbers also
fail; the driver preserves
an existing output on failure. GNU numeric line markers remain rejected49.
Skipped groups do not execute either form of line control. Whitespace-separated
continuations and continuations within filename literals are supported. A
nonliteral continuation with non-whitespace on both sides, or a continuation
inside either comment form (LF or CRLF), is explicitly rejected49 in a
`#line` operand: the
shared engine does not yet represent those phase-two forms reliably. Its
other existing macro-expansion limits remain unchanged.

Directive boundaries in the SysV profile recognize space, tab, form feed,
vertical tab and CRLF endings. A bare carriage return in the prefix is
rejected49, since this engine tracks LF source lines. Complete block comments
before `#` or between `#` and the directive name are consumed by the shared
comment walker, in active and skipped groups. Lookahead drops their bytes;
consumption counts their newlines so source locations and conditional nesting
stay balanced. A directive cannot vanish behind a comment prefix.

Prefix lookahead also crosses ordinary source comments. The unchanged GCC
`ansidecl.h` contains a backslash-newline in a commented-out macro example.
Such a splice is inert inside a block comment unless it follows `*`, where
phase two could assemble a closing delimiter. Prefix mode permits the inert
case and rejects the latter, split opening delimiters, line-comment
continuations and unterminated comments with49. The stricter `#line` operand
mode continues to reject all comment continuations. Both modes use the same
walker; this does not add another macro or comment parser.
Continuations between prefix whitespace and complete comments are consumed
with the same newline disposal operation in lookahead and dispatch. This also
handles a continuation immediately after a complete source comment, as emitted
by the unchanged Flex scanner skeleton. In ordinary file text a continuation
is replaced by its physical newline, which phase two would have deleted. That
is the same token sequence wherever the bytes on either side could not have
joined: at the start of the input; before whitespace or the end of input,
looking past any further continuations; or after whitespace, a complete block
comment, or a punctuator that is always a whole token (`, ; ( ) [ ] { } ~`).
The unchanged binutils 2.30 `bfd/cofflink.c` continues a call's argument
list as `addend,\` followed by indentation, which needs the last two rules.
The newline is emitted without turning the next byte into a new directive
line, and location macros still count the original source bytes. The lookahead
for a function-like macro's `(` skips continuations like other blanks, so
`F \` followed by `(1,2)` on the next line is still a call. Other nonliteral
source continuations — those that would join an identifier, number,
multi-byte punctuator or comment delimiter — and splices splitting a directive
name fail49; the shared engine does not yet join those phase-two tokens
(`tests/gcc/file-splice-check.py`).
Legacy/native and TinyCC directive dispatch retain their previous bytes.

The unchanged ordinary string-literal copier still preserves a backslash followed
by CRLF instead of performing line splicing. That boundary is recorded as a
known limitation; the accepted comment-boundary repair does not establish full
translation-phase-two handling for arbitrary source text.

This maps location macros only. Compiler diagnostics still use flattened
source line numbers; no diagnostic or debug-location remapping is claimed.
The legacy/native and direct TinyCC profiles keep their previous policy.

The semantic references are [C draft N1570, section 6.10.4](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf)
and [GCC line control](https://gcc.gnu.org/onlinedocs/cpp/Line-Control.html).
`tests/gcc/line-control-check.py` compares host CPP tokens, checks Forth-built
executable values and nested physical includes, and verifies fail-closed
rejections and repeated preprocessing.

### Computed include operands

Original GCC `genmodes.c` selects a target definition file through
`#include EXTRA_MODES_FILE`. Merely accepting that directive without reading
the named file produces a plausible, incomplete program. Direct mode now
expands a nonliteral include operand using the ordinary macro engine and
requires the result to contain exactly one header name. It then uses the same
search order and include recursion as a directly written header. Unknown,
empty, malformed, cyclic, or missing results fail with code 30 and preserve
the prior output artifact.

The expanded operand occupies a temporary scratch region. The caller's
original file region and position are restored afterward; relative searches
and `__FILE__`/`__LINE__` still refer to the actual including and included
files. Quoted computed names preserve backslashes literally, including an
escaped quote in the string token. Whitespace-free computed angle operands
are supported. Internal whitespace in a computed angle result is explicitly
rejected: the current text macro engine adds separator blanks and cannot yet
preserve GNU's full token-spacing rule. A function macro that stringifies its
header argument provides an unambiguous supported form.

The [GNU computed-include documentation](https://gcc.gnu.org/onlinedocs/cpp/Computed-Includes.html)
explains why token joining matters. `tests/gcc/computed-include-check.py`
compares supported forms with an independent host preprocessor, runs a
Forth-built program dependent on a selected header, and checks every token
of the pinned original `i386-modes.def` after a computed include. The input
hash and target-specific markers prevent the earlier silent omission from
being mistaken for successful generator reconstruction.

The seed-only checks run without writing the shared compiler output:

```sh
tests/tcc/prep-check.sh --legacy-pnut
tests/tcc/prep-check.sh --target build-out/tcc-sources
```

The optional target check requires the already staged, pinned and
patched kit. `tests/tcc/prep-stage-sources.py OUTPUT` prepares a fresh
source-only tree directly from the pinned tarball and portable libc,
checking input and output hashes for every exact patch. This Python
helper is an explicitly host-side source-preparation step; it does not
run pnut or produce executable code.

The target check preprocesses TinyCC and portable libc independently,
and then libc before TinyCC in one combined input. That order matters:
TinyCC's header redefines `malloc`, `free` and `realloc`, while portable
libc needs those identifiers unchanged to define its implementations.
An optional `--oracle` directory may contain separately generated host
preprocessor output for token comparison; it is never compilation input
on the seed path. The focused tests also pin the exact legacy output
for the existing conditional and function-macro fixtures.

## Exercises

1. **★ Trace.** In the Try-it output, why does `SQUARE(ROWS)` produce
   three blanks on each side of `4`?  Count where each one comes from
   (§5).

2. **★★ Verify.** Write a function-like macro call whose arguments run
   over three lines, followed by an undefined name on the line after.
   Which line does `cc-die` report?  Now remove the `cc-pp-flush-nl` in
   `cc-pp-ident` and try again.

3. **★★ Analyse.** This preprocessor keeps a macro busy while its own
   replacement is walked, but not while the text *after* the
   replacement is walked.  Find a C program where the two rules differ
   (hint: a function-like macro whose name ends a replacement, with its
   `(` in the source after the call).  What does this pass do, and what
   does C require?

4. **★★★ Trace.** Direct mode encodes `#parameter` as bytes `2, k`
   and `##` as byte `3`. Explain why `ElfW(Sym)` needs the raw argument,
   while an ordinary parameter needs its expanded spelling. Trace a
   macro that uses the same parameter both ways.

5. **★★ Modify.** There is no `#include` cycle check.  What stops a file
   that includes itself, at what depth, and with which error code?
   (`tests/cc/die-31-include-deep.c` is such a file.)  Sketch the
   smallest patch that would report a cycle as a cycle instead.

## After this chapter

The compiler can flatten C source: project includes splice in
recursively, macros are expanded, and dropped groups are gone.  The
lexer sees one continuous stream with its position reset to zero,
and every line is where the source had it.  For `tri.c` that stream
is 466 bytes of characters, with `ROWS` already `4` in all four
places.  Ch 23 turns it into tokens.

## Takeaways

- The preprocessor is a separate pass that reads the raw input in `cc-in-buf` and writes the flattened source into `cc-src-buf`, with supported macros expanded and dropped groups removed; intentionally unavailable macro names remain ordinary tokens.
- Expansion is walking: a macro's replacement becomes a region of its own and is walked by the same code, with the macro marked busy so it cannot expand inside itself; arguments are expanded first, in temporary sinks from a scratch stack.
- Line numbers survive: dropped lines leave their newlines, and newlines swallowed by a directive or a multi-line macro call are paid back right after it.
- Every limit is checked, each with its own code (30–48): include depth, path length, include size, macro count, macro pool, scratch, conditional nesting, output size, malformed directives and macro calls, and `#error`.

Next: Chapter 23 — The Lexer.

### Direct-GCC macro-table selection

The unchanged original `expr.c` needs 4,120 recorded macro definitions,
including records subsequently hidden or undefined. Its pool uses 238,367
bytes, below the existing 256 KiB direct limit. The opt-in table therefore has
4,608 entries, the next 512-entry quantum above the measured count. Each of
its six parallel arrays occupies 36,864 bytes, an integral number of pages.
One mapping contains all six disjoint slices. Every address and the capacity
come from the same selected workspace. No pool, include or scratch limit is
raised. The legacy profile still enforces 1,024 records and 64 KiB of pool text.
`cc-preprocess` resets the count and pool cursor; recording a macro clears its
busy cell before it can be used. A reused mapping keeps its fixed size.
