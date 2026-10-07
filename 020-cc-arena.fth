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

\ ----- The compiler's arithmetic in machine code -----
\ 010-lib.fth builds - from nand and +, and the sign test 0< from the
\ unsigned / (a 64-bit divide per comparison).  The compiler runs them
\ hundreds of millions of times, so here they become x86 code with the
\ same answers: < is still (a - b)'s sign bit, wrapping as before.  Each
\ native word gets a fresh header (code:), and native! turns the first
\ definition into a jump to it, so every word compiled earlier, in
\ 010-lib.fth too, runs the new code.  TOS is in rdi and the data stack
\ grows down from rbp, as in the seed's + (Ch 15).
: code:  : [lit] 0 state ! ;             \ header only; c, lays the body
: native!  ( old new -- )                \ old's first bytes: JMP rel32 new
  over [lit] 5 + -  swap                 \ rel32 first: old may be - itself
  here >r  here-addr !  [lit] 233 c, ,4
  r> here-addr ! ;
variable code-start
: mov-rax-[rbp],  [lit] 72 c, [lit] 139 c, [lit] 69 c, [lit] 0 c, ;
: add-rbp-8,      [lit] 72 c, [lit] 131 c, [lit] 197 c, [lit] 8 c, ;
: sub-rax-rdi,    [lit] 72 c, [lit] 41 c, [lit] 248 c, ;
: mov-rdi-rax,    [lit] 72 c, [lit] 137 c, [lit] 199 c, ;
: sar63,  ( modrm -- )  [lit] 72 c, [lit] 193 c, c, [lit] 63 c, ;
' - code: -  here code-start !            \ ( a b -- a-b )
  mov-rax-[rbp], add-rbp-8, sub-rax-rdi, mov-rdi-rax, ret,
  code-start @ native!
' 0< code: 0<  here code-start !          \ ( n -- f )  sar rdi, 63
  [lit] 255 sar63, ret,
  code-start @ native!
' < code: <  here code-start !            \ ( a b -- f )  sign of a - b
  mov-rax-[rbp], add-rbp-8, sub-rax-rdi, [lit] 248 sar63, mov-rdi-rax, ret,
  code-start @ native!
' = code: =  here code-start !            \ ( a b -- f )  a - b = 0
  mov-rax-[rbp], add-rbp-8, sub-rax-rdi,
  [lit] 15 c, [lit] 148 c, [lit] 192 c,   \ sete al
  [lit] 72 c, [lit] 15 c, [lit] 182 c, [lit] 248 c,   \ movzx rdi, al
  [lit] 72 c, [lit] 247 c, [lit] 223 c,   \ neg rdi
  ret,
  code-start @ native!
' 1+ code: 1+  here code-start !          \ add rdi, 1
  [lit] 72 c, [lit] 131 c, [lit] 199 c, [lit] 1 c, ret,
  code-start @ native!
' 1- code: 1-  here code-start !          \ sub rdi, 1
  [lit] 72 c, [lit] 131 c, [lit] 239 c, [lit] 1 c, ret,
  code-start @ native!

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
