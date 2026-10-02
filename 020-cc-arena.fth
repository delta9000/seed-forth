\ 020-cc-arena.fth — the compiler's ground floor: the lexer's state block,
\ how the compiler fails (cc-die, cc-check-cap), and a bump allocator for
\ variable-size data (struct descriptors, call/goto fixup lists, switch-case
\ lists — anything that doesn't fit a fixed slot in a parallel array).  Most
\ compiler state lives in fixed-size buffers (parallel arrays declared with
\ `create NAME N allot`); this arena handles the rest.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, s,, char, [lit],
\ if,/then,, begin,/until,, swap, dup, over, nip, drop, >r, r>, +, -, /, *,
\ >, !, @, c!, c,, write, die.

\ ----- The lexer's state: one block -----
\ Everything the source reader (030) and the lexer (050) change as they move
\ through the program lives in this one 8-cell block, so a parser that wants
\ to look ahead can copy the block away and later copy it back
\ (cc-lex-mark / cc-lex-reset, 050).  Each name below is the address of its
\ cell, used exactly like a variable.  The block comes first because cc-die
\ reports the current line from it.
[lit] 64 constant cc-lex-state-size
create cc-lex-state  cc-lex-state-size allot
cc-lex-state             constant cc-src-pos     \ reader: offset of the next byte
cc-lex-state [lit]  8 +  constant cc-src-line    \ reader: 1-based line number
cc-lex-state [lit] 16 +  constant tok-kind       \ lexer: tk-* of the current token
cc-lex-state [lit] 24 +  constant tok-num        \ lexer: number / char / punct code
cc-lex-state [lit] 32 +  constant tok-str-addr   \ lexer: identifier or string bytes
cc-lex-state [lit] 40 +  constant tok-str-len    \ lexer: ... and their length
cc-lex-state [lit] 48 +  constant tok-kw-id      \ lexer: kw-* when tok-kind = tk-kw
cc-lex-state [lit] 56 +  constant cc-tok-pending \ lexer: -1 = current token put back

\ ----- Failing: cc-die -----
\ cc-err-write ( a u -- )  Write u bytes at a to stderr (fd 2).
: cc-err-write  >r >r [lit] 2 r> r> write drop ;

\ cc-err-dec ( u -- )  Write u in decimal to stderr.  Digits come out lowest
\ first, so they fill cc-err-digits from its end backwards.
create cc-err-digits  [lit] 20 allot             \ 2^64 has 20 digits
: cc-err-dec
  cc-err-digits [lit] 20 +                       ( u p )
  begin,
    1-  over [lit] 10 / [lit] 10 * >r  over r> - ( u p digit )
    [char] 0 +  over c!                          ( u p )
    swap [lit] 10 / swap                         ( u/10 p )
    over 0=
  until,
  nip  cc-err-digits [lit] 20 + over -  cc-err-write ;

create cc-die-where  s, cc: bl c, s, line bl c,       \ "cc: line "  9 bytes
create cc-die-what   char : c, bl c, s, error bl c,   \ ": error "   8 bytes
create cc-die-end    nl c,                            \ "\n"         1 byte

\ cc-die ( code -- )  Every compiler failure ends here: write
\ "cc: line N: error CODE" to stderr and exit with status CODE.  N is the
\ reader's line in the preprocessed source, where #include'd files are
\ already spliced in (Appendix G).
: cc-die
  cc-die-where [lit] 9 cc-err-write
  cc-src-line @ cc-err-dec
  cc-die-what [lit] 8 cc-err-write
  dup cc-err-dec
  cc-die-end [lit] 1 cc-err-write
  die ;

\ cc-check-cap ( n cap code -- )  Die with code unless n <= cap.  n is how
\ full a buffer or table will be once the write about to happen is done.
: cc-check-cap
  >r > if, r> cc-die then,
  r> drop ;

\ ----- Storage -----
\ The buffer lives in the dictionary alongside the cc-arena-base header (it's
\ what `create` builds: a header + data area; allot extends the data area).
\ Sized to fit within 000-seed.hex0's mapped segment with room for the compiler
\ dictionary, struct descriptors, labels, and string overflow.
[lit] 32768 constant cc-arena-cap
create cc-arena-base  cc-arena-cap allot
variable cc-arena-ptr
\ Initialize the bump pointer to the base of the buffer.
cc-arena-base cc-arena-ptr !
variable cc-arena-start
variable cc-arena-limit
cc-arena-base cc-arena-start !
cc-arena-cap cc-arena-limit !
\ Opt-in workspace for larger translation units; the seed itself is unchanged.
: cc-arena-map ( bytes -- )
  dup cc-arena-limit !
  [lit] 0 swap [lit] 3 [lit] 34 true [lit] 0 [lit] 9 syscall6
  dup 0< if, [lit] 10 cc-die then,
  dup cc-arena-start ! cc-arena-ptr ! ;

\ ----- cc-alloc -----
\ cc-alloc ( n -- addr )  Bump n bytes (rounded up to an 8-byte boundary)
\ off the arena and return the start address of the allocation.  On exhaustion
\ the compiler dies with code 10.
\
\ Stack trace:
\   ( n )
\   align up to 8:  (n+7)/8*8
\   ( n' )
\   cc-arena-ptr @ swap over +     ( old-top new-top )
\   dup cc-arena-base -            ( old-top new-top used )
\   cc-arena-cap 10 cc-check-cap   ( old-top new-top )
\   cc-arena-ptr !                 ( old-top )
: cc-alloc                                       ( n -- addr )
  [lit] 7 + [lit] 8 / [lit] 8 *                  \ align up to 8 bytes
  cc-arena-ptr @ swap over +                     ( old-top new-top )
  dup cc-arena-start @ -  cc-arena-limit @ [lit] 10 cc-check-cap
  cc-arena-ptr ! ;                               ( -- old-top )
