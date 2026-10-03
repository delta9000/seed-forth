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
\   4. #error stops the compiler.  Any other directive is dropped.
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

\ cc-prep-emit-byte ( b -- )  Append b to the sink; die with the sink's
\ code if it is full.  Counts lines as it goes, so a failure during the
\ pass reports the line of the output it had reached.
: cc-prep-emit-byte
  cc-pp-out-pos @ 1+ cc-pp-out-cap @ cc-pp-out-code @ cc-check-cap
  dup cc-pp-out @ cc-pp-out-pos @ + c!
  [lit] 1 cc-pp-out-pos +!
  nl = if, [lit] 1 cc-src-line +! then, ;

\ cc-pp-emit-bytes ( a u -- )  Append u bytes from a.
: cc-pp-emit-bytes
  begin, dup while,
    over c@ cc-prep-emit-byte
    1- swap 1+ swap
  repeat,
  2drop ;

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
  cc-pp-out-code ! cc-pp-out-cap ! cc-pp-out-pos ! cc-pp-out ! ;

\ cc-pp-sink-pop ( -- )  Resume writing to the most recently parked sink.
: cc-pp-sink-pop
  [lit] 1 cc-pp-sink-depth -!
  cc-pp-sink-depth @ [lit] 32 * cc-pp-sinks +  cc-pp-sink  cc-pp-copy4 ;

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

variable cc-prep-direct                         \ explicit headers; no shim macros

[lit] 4096 constant cc-macro-cap
create cc-macro-name-addr  cc-macro-cap [lit] 8 * allot
create cc-macro-name-len   cc-macro-cap [lit] 8 * allot
create cc-macro-body-addr  cc-macro-cap [lit] 8 * allot
create cc-macro-body-len   cc-macro-cap [lit] 8 * allot
create cc-macro-params     cc-macro-cap [lit] 8 * allot
create cc-macro-busy       cc-macro-cap [lit] 8 * allot
variable cc-macro-count

[lit] 262144 constant cc-macro-pool-cap           \ 256 KiB
create cc-macro-pool  cc-macro-pool-cap allot
variable cc-macro-pool-pos

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

\ cc-pp-put ( c -- )  Dispose of one walked-over byte.
: cc-pp-put
  cc-pp-put-mode @ put-emit = if, cc-prep-emit-byte exit, then,
  cc-pp-put-mode @ put-count = if,
    nl = if, [lit] 1 cc-pp-pending-nl +! then, exit,
  then,
  drop ;

\ cc-pp-take ( -- )  Put the current byte and step past it.
: cc-pp-take  cc-prep-peek cc-pp-put cc-prep-advance ;

\ cc-pp-block-comment ( -- )  pos at "/*": walk through the closing "*/",
\ or to EOR.
: cc-pp-block-comment
  cc-pp-take cc-pp-take
  begin,
    cc-prep-eor? if, exit, then,
    [char] * [char] / cc-prep-at? 0=
  while,
    cc-pp-take
  repeat,
  cc-pp-take cc-pp-take ;

\ cc-pp-line-comment ( -- )  pos at "//": walk to the newline, which is
\ left for the caller.
: cc-pp-line-comment
  begin,
    cc-prep-eor? 0= cc-prep-peek nl <> and
  while,
    cc-pp-take
  repeat, ;

\ cc-pp-literal ( -- )  pos at a ' or ": walk through the closing quote.
\ A backslash takes the next byte with it; an unclosed literal stops at the
\ end of its line.
: cc-pp-literal
  cc-prep-peek cc-pp-take                          ( q )
  begin,
    cc-prep-eor? if, drop exit, then,
    cc-prep-peek nl = if, drop exit, then,
    cc-prep-peek backslash = if,
      cc-pp-take
      cc-prep-eor? 0= if, cc-pp-take then,
    else,
      cc-prep-peek over = if, drop cc-pp-take exit, then,
      cc-pp-take
    then,
  again, ;

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
          backslash nl cc-prep-at? if, cc-prep-advance then,
          cc-prep-advance
        then,
      then,
    then,
  repeat,
  cc-prep-src-pos @ swap - ;

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
: cc-pp-location-cell  cc-prep-inc-depth @ swap cell[] ;
: cc-pp-location-enter
  cc-prep-src-addr @ dup cc-pp-file-base cc-pp-location-cell !
  dup cc-pp-file-cursor cc-pp-location-cell !
  cc-prep-src-len @ + cc-pp-file-end cc-pp-location-cell !
  [lit] 1 cc-pp-file-line cc-pp-location-cell ! ;
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
  cc-pp-file-line cc-pp-location-cell @ cc-pp-location-line ! ;

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

\ cc-pp-paren-ahead? ( -- f )  After a function-like macro's name: true,
\ with pos past it, if the next thing (blanks and newlines skipped) is '('.
\ Otherwise pos is left where it was, and the name is not a call.
: cc-pp-paren-ahead?
  cc-prep-src-pos @ [lit] 0                        ( pos0 nls )
  begin,
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
  cc-pp-trim-slice cc-pp-string-u ! cc-pp-string-a !
  [lit] 0 cc-pp-string-quote ! [lit] 0 cc-pp-string-escape !
  [lit] 0 cc-pp-string-space ! true cc-pp-string-start !
  [char] " cc-prep-emit-byte
  begin, cc-pp-string-u @ while,
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
        cc-pp-trim-slice cc-pp-emit-bytes
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
  cc-prep-current-path cc-prep-inc-depth @ cc-prep-file-lens cell[] @
  dup 0= if, 2drop cc-pp-stdin-name [lit] 7 then,
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
  cc-prep-ident-addr @ cc-prep-ident-len @ cc-macro-find     ( i )
  dup 0< 0= if,
    dup cc-macro-busy-cell @ if, drop true then,
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
  cc-prep-in-file @ if,
    cc-pp-skipping? if, cc-pp-skip-char exit, then,
  then,
  cc-prep-peek dup [char] " = swap [char] ' = or if,
    put-emit cc-pp-put-mode !  cc-pp-literal exit,
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

\ cc-prep-line-is-directive? ( -- f )  -1 iff the first non-blank byte on
\ the current line is '#'.  Does NOT advance pos.
variable cc-prep-isd-save-pos

: cc-prep-line-is-directive?
  cc-prep-src-pos @ cc-prep-isd-save-pos !
  cc-prep-skip-blanks
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

\ ---------------------------------------------------------------------------
\ #define and #undef
\ ---------------------------------------------------------------------------

\ A function-like macro's parameter names, while its body is copied: slices
\ of the #define line, looked up with cc-name-find.
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
  cc-prep-peek lparen = if,
    cc-prep-advance cc-pp-read-params  cc-pp-param-count @
  else,
    [lit] 0 cc-pp-param-count !  true
  then,
  >r                                               ( na nu ; R: params )
  cc-prep-skip-blanks
  cc-macro-pool cc-macro-pool-pos @ +              ( na nu ba )
  cc-pp-to-pool  cc-pp-copy-body  cc-pp-trim  cc-pp-from-pool
  cc-macro-pool cc-macro-pool-pos @ + over -       ( na nu ba bu )
  r> cc-macro-record ;

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
  cc-prep-skip-blanks                              \ leading indent before '#'
  cc-prep-advance                                  \ consume '#'
  cc-prep-skip-blanks
  cc-pp-location-enabled @ cc-pp-skipping? 0= and if,
    cc-prep-peek digit? if, [lit] 49 cc-die then,
  then,
  cc-prep-peek ident-start? if,
    cc-prep-read-ident
    cc-pp-cond-directive if, cc-prep-skip-to-eol exit, then,
    cc-pp-skipping? 0= if,
      cc-pp-location-enabled @ if,
        cc-prep-name-line [lit] 4 cc-prep-ident= if, [lit] 49 cc-die then,
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

\ ===========================================================================
\ Built-in macros
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
  [lit] 0 cc-pp-in-if !
  cc-pp-scratch cc-pp-scratch-top !
  cc-src-buf cc-pp-out !  [lit] 0 cc-pp-out-pos !
  cc-src-cap cc-pp-out-cap !  [lit] 36 cc-pp-out-code !
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
