\ 050-cc-lex.fth — C tokenizer (one-token lookahead) for the C-subset compiler.
\ Reads bytes from cc-src-buf via cc-peek-char/cc-next-char/cc-eof? (030-cc-io.fth).
\ Stores the current token in 5 cells of the lexer's state block
\ (020-cc-arena.fth): tok-kind, tok-num, tok-str-addr, tok-str-len, tok-kw-id.
\ The parser drives the lexer through the interface at the end of this file:
\ cc-next-token-keep / cc-putback-token, and cc-lex-mark / cc-lex-reset.
\
\ Depends on 010-lib.fth (control-flow combinators, classifiers, bytes-eq, etc.),
\ 020-cc-arena.fth (cc-lex-state and its cells), 030-cc-io.fth (cc-src-buf,
\ cc-peek-char, cc-next-char, cc-eof?, ident-start?, ident-cont?).

\ ===========================================================================
\ Token kinds and punctuation IDs
\ ===========================================================================

[lit] 0 constant tk-eof
[lit] 1 constant tk-ident
[lit] 2 constant tk-num
[lit] 3 constant tk-str
[lit] 4 constant tk-chr
[lit] 5 constant tk-punct
[lit] 6 constant tk-kw

\ Multi-char punctuation codes start at 256 to avoid clash with single-byte
\ ASCII codes used directly for one-char punct (e.g. '(' = 40).
[lit] 256 constant pt-eq-eq         \ ==
[lit] 257 constant pt-bang-eq       \ !=
[lit] 258 constant pt-le            \ <=
[lit] 259 constant pt-ge            \ >=
[lit] 260 constant pt-and-and       \ &&
[lit] 261 constant pt-or-or         \ ||
[lit] 262 constant pt-arrow         \ ->
[lit] 263 constant pt-plus-plus     \ ++
[lit] 264 constant pt-minus-minus   \ --
[lit] 265 constant pt-shl           \ <<
[lit] 266 constant pt-shr           \ >>
[lit] 267 constant pt-plus-eq       \ +=
[lit] 268 constant pt-minus-eq      \ -=
[lit] 269 constant pt-star-eq       \ *=
[lit] 270 constant pt-slash-eq      \ /=
[lit] 271 constant pt-percent-eq    \ %=
[lit] 272 constant pt-amp-eq        \ &=
[lit] 273 constant pt-pipe-eq       \ |=
[lit] 274 constant pt-caret-eq      \ ^=
[lit] 275 constant pt-shl-eq        \ <<=
[lit] 276 constant pt-shr-eq        \ >>=
[lit] 277 constant pt-ellipsis      \ ...

\ ===========================================================================
\ Keyword table + IDs
\ ===========================================================================
\ Flat byte array: each entry is [length-byte][name-bytes]; terminator is a
\ length-byte of 0.  Defined here (before cc-check-keyword) so the latter can
\ reference kw-table directly.

\ kw, ( "name" -- )  lay down one entry: the length byte, then the bytes.
: kw,  token dup c, bytes, ;

create kw-table
kw, int
kw, char
kw, void
kw, short
kw, long
kw, unsigned
kw, signed
kw, const
kw, volatile
kw, static
kw, extern
kw, auto
kw, register
kw, restrict
kw, struct
kw, enum
kw, typedef
kw, sizeof
kw, if
kw, else
kw, while
kw, for
kw, do
kw, return
kw, break
kw, continue
kw, goto
kw, switch
kw, case
kw, default
kw, union
kw, float
kw, double
kw, inline
[lit] 0 c,                                      \ terminator

\ Keyword IDs in declaration order.
[lit]  0 constant kw-int
[lit]  1 constant kw-char
[lit]  2 constant kw-void
[lit]  3 constant kw-short
[lit]  4 constant kw-long
[lit]  5 constant kw-unsigned
[lit]  6 constant kw-signed
[lit]  7 constant kw-const
[lit]  8 constant kw-volatile
[lit]  9 constant kw-static
[lit] 10 constant kw-extern
[lit] 11 constant kw-auto
[lit] 12 constant kw-register
[lit] 13 constant kw-restrict
[lit] 14 constant kw-struct
[lit] 15 constant kw-enum
[lit] 16 constant kw-typedef
[lit] 17 constant kw-sizeof
[lit] 18 constant kw-if
[lit] 19 constant kw-else
[lit] 20 constant kw-while
[lit] 21 constant kw-for
[lit] 22 constant kw-do
[lit] 23 constant kw-return
[lit] 24 constant kw-break
[lit] 25 constant kw-continue
[lit] 26 constant kw-goto
[lit] 27 constant kw-switch
[lit] 28 constant kw-case
[lit] 29 constant kw-default
[lit] 30 constant kw-union
[lit] 31 constant kw-float
[lit] 32 constant kw-double
[lit] 33 constant kw-inline

\ ===========================================================================
\ Helper: 2-byte peek
\ ===========================================================================

\ cc-peek-char-2 ( -- c1 c2 )  Returns the byte at pos and the byte at pos+1
\ without advancing.  Returns 0 for c2 at EOF.  c1 is also 0 at EOF.
: cc-peek-char-2
  cc-peek-char                                  ( c1 )
  cc-src-pos @ 1+                               ( c1 next-pos )
  dup cc-src-len @ < if,
    cc-src-buf swap + c@                        ( c1 c2 )
  else,
    drop [lit] 0                                ( c1 0 )
  then, ;

\ ===========================================================================
\ cc-check-keyword
\ ===========================================================================

\ cc-check-keyword ( -- )  After cc-lex-ident-or-kw has set tok-str-addr/len,
\ this walks kw-table; on a match it sets tok-kind=tk-kw + tok-kw-id and
\ returns at once, otherwise tok-kind=tk-ident.  Loop invariant on the data
\ stack: ( ptr id ).
: cc-check-keyword
  kw-table                                      \ ptr
  [lit] 0                                       \ id
  begin,
    over c@ [lit] 0 >                           \ entry length non-zero?
  while,
    over c@ tok-str-len @ = if,                 \ same length?
      \ Stack here: ( ptr id ).  bytes-eq wants ( a1 a2 u ) where
      \ a1 = tok-str-addr, a2 = ptr+1 (skipping length byte), u = tok-str-len.
      over 1+  tok-str-addr @  swap  tok-str-len @  bytes-eq if,
        tok-kw-id !  drop                       \ matched: record the id
        tk-kw tok-kind !  exit,
      then,
    then,
    \ Advance: ( ptr id ) -> ( ptr+len+1 id+1 )
    swap dup c@ 1+ + swap 1+
  repeat,
  2drop                                         \ discard ptr and id
  tk-ident tok-kind ! ;

\ ===========================================================================
\ Whitespace and comment skipping
\ ===========================================================================

\ cc-skip-line-comment ( -- )  Caller has already consumed the //.  Skip
\ to (but do not consume) the next newline; the outer ws-skip will eat it.
: cc-skip-line-comment
  begin,
    cc-eof? 0=
    cc-peek-char nl <> and
  while,
    cc-next-char drop
  repeat, ;

\ cc-skip-block-comment ( -- )  Caller has already consumed the /*.  Skip
\ to and including the closing */, or to EOF.
: cc-skip-block-comment
  begin,
    cc-eof? 0=
  while,
    cc-next-char [char] * = if,                 \ saw '*'
      cc-peek-char [char] / = if,               \ followed by '/'
        cc-next-char drop exit,                 \ consume '/': done
      then,
    then,
  repeat, ;

\ cc-skip-ws-and-comments ( -- )  Skip whitespace, // line-comments, and
\ /* block comments.  Returns at the first non-whitespace, non-comment byte.
: cc-cspace? dup space? over [lit] 11 = or swap [lit] 12 = or ;

: cc-skip-ws-and-comments
  begin,
    cc-eof? 0=
  while,
    cc-peek-char dup cc-cspace? if,
      drop cc-next-char drop
    else,
      [char] / <> if, exit, then,               \ stop: not ws or comment
      cc-peek-char-2 nip [char] / = if,         \ // ?
        cc-next-char drop  cc-next-char drop
        cc-skip-line-comment
      else,
        cc-peek-char-2 nip [char] * = if,       \ /* ?
          cc-next-char drop  cc-next-char drop
          cc-skip-block-comment
        else,
          exit,                                 \ stop: bare '/'
        then,
      then,
    then,
  repeat, ;

\ ===========================================================================
\ Number / identifier / string / char lexers
\ ===========================================================================

\ Hex digit helpers (Task D: 0xFF hex literals).
\ cc-hex-digit? ( c -- f )  -1 if c is 0-9, a-f, A-F.
: cc-hex-digit?
  dup digit? if,
    drop true
  else,
    dup alpha-lower? if,
      [char] a - [lit] 6 / 0=                     \ 'a'..'f' -> 0..5 -> /6=0
    else,
      dup alpha-upper? if,
        [char] A - [lit] 6 / 0=                   \ 'A'..'F'
      else,
        drop [lit] 0
      then,
    then,
  then, ;

\ cc-octal-digit? ( c -- f )  True for '0'..'7'.
: cc-octal-digit?  [char] 0 - [lit] 8 / 0= ;

\ cc-hex-digit-val ( c -- v )  Convert hex digit char to 0..15.
: cc-hex-digit-val
  dup digit? if,
    [char] 0 -
  else,
    dup alpha-lower? if,
      [char] a - [lit] 10 +                       \ 'a' -> 10
    else,
      [char] A - [lit] 10 +                       \ 'A' -> 10
    then,
  then, ;

\ cc-lex-number-dec ( -- )  Read decimal digits into tok-num.
: cc-lex-number-dec
  [lit] 0
  begin,
    cc-eof? 0=
    cc-peek-char digit? and
  while,
    [lit] 10 *
    cc-peek-char [char] 0 - +
    cc-next-char drop
  repeat,
  tok-num !
  tk-num tok-kind ! ;

\ cc-lex-number-hex ( -- )  '0x' already consumed; read hex digits into tok-num.
: cc-lex-number-hex
  [lit] 0
  begin,
    cc-eof? 0=
    cc-peek-char cc-hex-digit? and
  while,
    [lit] 16 *
    cc-peek-char cc-hex-digit-val +
    cc-next-char drop
  repeat,
  tok-num !
  tk-num tok-kind ! ;

\ cc-lex-number-oct ( -- )  A leading '0' already consumed; read octal
\ digits into tok-num (C's 010 is eight).
: cc-lex-number-oct
  [lit] 0
  begin,
    cc-eof? 0=
    cc-peek-char cc-octal-digit? and
  while,
    [lit] 8 *
    cc-peek-char [char] 0 - +
    cc-next-char drop
  repeat,
  tok-num !
  tk-num tok-kind ! ;

\ cc-lex-number ( -- )  Hex if it starts 0x or 0X, octal if it starts with
\ 0 and another digit, else decimal.  The full spelling, including a
\ u/U/l/L suffix, is retained in tok-str-addr/len for type classification.
\ tok-num still contains the unsigned 64-bit bit pattern, in both targets.
: cc-lex-number
  cc-src-buf cc-src-pos @ + >r                    \ numeric token start
  cc-peek-char-2                                  ( c1 c2 )
  over [char] 0 = if,                             \ c1 == '0' ?
    dup [char] x = over [char] X = or if,         \ c2 == 'x' or 'X' ?
      2drop
      cc-next-char drop                           \ consume '0'
      cc-next-char drop                           \ consume 'x'/'X'
      cc-lex-number-hex
    else,
      digit? if,                                  \ c2 a digit: octal
        drop
        cc-next-char drop                         \ consume '0'
        cc-lex-number-oct
      else,
        drop cc-lex-number-dec
      then,
    then,
  else,
    2drop
    cc-lex-number-dec
  then,
  begin,
    cc-peek-char dup [char] u = over [char] U = or
    over [char] l = or  swap [char] L = or
  while,
    cc-next-char drop
  repeat,
  cc-src-buf cc-src-pos @ + r@ - tok-str-len !
  r> tok-str-addr ! ;

\ cc-lex-ident-or-kw ( -- )  Read [a-zA-Z_][a-zA-Z0-9_]* and check the
\ keyword table.  Sets tok-str-addr/len, then dispatches kind.  Macros are
\ already expanded (040-cc-prep.fth), so an identifier is just a name.
: cc-lex-ident-or-kw
  cc-src-buf cc-src-pos @ +                     \ start address
  [lit] 0                                       ( start len )
  begin,
    cc-eof? 0=
    cc-peek-char ident-cont? and
  while,
    cc-next-char drop
    1+
  repeat,
  tok-str-len !  tok-str-addr !
  cc-check-keyword ;

\ cc-lex-string ( -- )  Read "..." preserving escape sequences as literal
\ bytes (a \" inside the body is two bytes long; the closing quote is the
\ unescaped ").  Stores the slice as offset+len into cc-src-buf for later
\ string-pool insertion or escape decoding.
: cc-lex-string
  cc-next-char drop                             \ consume opening "
  cc-src-buf cc-src-pos @ +                     \ start address
  [lit] 0                                       ( start len )
  begin,
    cc-eof? 0=
    cc-peek-char [char] " <> and
  while,
    cc-peek-char backslash = if,                \ backslash: keep both bytes
      cc-next-char drop
      1+
      cc-eof? 0= if,
        cc-next-char drop
        1+
      then,
    else,
      cc-next-char drop
      1+
    then,
  repeat,
  cc-eof? 0= if, cc-next-char drop then,        \ consume closing "
  tok-str-len !  tok-str-addr !
  tk-str tok-kind ! ;

\ cc-decode-escape ( a -- byte n )  a is the address of what follows a
\ backslash; answer the byte the escape stands for and how many bytes the
\ escape takes after the backslash.  \n \t \r \a \b \f \v are the usual
\ control characters; \ooo (one to three octal digits, so \0 too) and
\ \xhh... (hex digits) give a byte by value; any other \c (including \\
\ \' \") stands for c itself.  The one table for both character literals
\ (cc-lex-char) and string literals (cc-emit-string-bytes, 090).
variable cc-esc-a
variable cc-esc-v
variable cc-esc-n
: cc-decode-escape
  dup cc-esc-a !  c@
  dup [char] x = if,
    drop  [lit] 0 cc-esc-v !  [lit] 1 cc-esc-n !
    begin,
      cc-esc-a @ cc-esc-n @ + c@  dup cc-hex-digit?
    while,
      cc-hex-digit-val  cc-esc-v @ [lit] 16 * +  cc-esc-v !
      [lit] 1 cc-esc-n +!
    repeat,
    drop  cc-esc-v @ [lit] 255 and  cc-esc-n @ exit,
  then,
  dup cc-octal-digit? if,
    drop  [lit] 0 cc-esc-v !  [lit] 0 cc-esc-n !
    begin,
      cc-esc-a @ cc-esc-n @ + c@
      dup cc-octal-digit?  cc-esc-n @ [lit] 3 < and
    while,
      [char] 0 -  cc-esc-v @ [lit] 8 * +  cc-esc-v !
      [lit] 1 cc-esc-n +!
    repeat,
    drop  cc-esc-v @ [lit] 255 and  cc-esc-n @ exit,
  then,
  dup [char] n = if, drop nl       [lit] 1 exit, then,
  dup [char] t = if, drop tab      [lit] 1 exit, then,
  dup [char] r = if, drop [lit] 13 [lit] 1 exit, then,
  dup [char] a = if, drop [lit]  7 [lit] 1 exit, then,
  dup [char] b = if, drop [lit]  8 [lit] 1 exit, then,
  dup [char] f = if, drop [lit] 12 [lit] 1 exit, then,
  dup [char] v = if, drop [lit] 11 [lit] 1 exit, then,
  [lit] 1 ;

\ cc-lex-char ( -- )  Read 'c' or '\c'.  Stores the byte value in tok-num.
: cc-lex-char
  cc-next-char drop                             \ consume opening '
  cc-peek-char backslash = if,                  \ escape
    cc-next-char drop                           \ consume backslash
    cc-src-buf cc-src-pos @ + cc-decode-escape  ( byte n )
    begin, dup while, cc-next-char drop 1- repeat,
    drop
  else,
    cc-next-char                                \ literal char
  then,
  tok-num !
  cc-eof? 0= if, cc-next-char drop then,        \ consume closing '
  tk-chr tok-kind ! ;

\ ===========================================================================
\ Punctuation: per-first-char handlers + dispatch
\ ===========================================================================
\ Each handler is entered after the first char has already been read.  It
\ checks for any multi-char follow-on, then stores the punct code in tok-num
\ and sets tok-kind to tk-punct.

: cc-punct-eq                                   \ '='  '=='
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-eq-eq tok-num !
  else,
    [char] = tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-bang                                 \ '!'  '!='
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-bang-eq tok-num !
  else,
    [char] ! tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-lt                                   \ '<' '<=' '<<' '<<='
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-le tok-num !
  else,
    cc-peek-char [char] < = if,
      cc-next-char drop
      cc-peek-char [char] = = if,
        cc-next-char drop  pt-shl-eq tok-num !
      else,
        pt-shl tok-num !
      then,
    else,
      [char] < tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-gt                                   \ '>' '>=' '>>' '>>='
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-ge tok-num !
  else,
    cc-peek-char [char] > = if,
      cc-next-char drop
      cc-peek-char [char] = = if,
        cc-next-char drop  pt-shr-eq tok-num !
      else,
        pt-shr tok-num !
      then,
    else,
      [char] > tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-amp                                  \ '&' '&&' '&='
  cc-peek-char [char] & = if,
    cc-next-char drop  pt-and-and tok-num !
  else,
    cc-peek-char [char] = = if,
      cc-next-char drop  pt-amp-eq tok-num !
    else,
      [char] & tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-pipe                                 \ '|' '||' '|='
  cc-peek-char [char] | = if,
    cc-next-char drop  pt-or-or tok-num !
  else,
    cc-peek-char [char] = = if,
      cc-next-char drop  pt-pipe-eq tok-num !
    else,
      [char] | tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-plus                                 \ '+' '++' '+='
  cc-peek-char [char] + = if,
    cc-next-char drop  pt-plus-plus tok-num !
  else,
    cc-peek-char [char] = = if,
      cc-next-char drop  pt-plus-eq tok-num !
    else,
      [char] + tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-minus                                \ '-' '--' '-=' '->'
  cc-peek-char [char] - = if,
    cc-next-char drop  pt-minus-minus tok-num !
  else,
    cc-peek-char [char] = = if,
      cc-next-char drop  pt-minus-eq tok-num !
    else,
      cc-peek-char [char] > = if,
        cc-next-char drop  pt-arrow tok-num !
      else,
        [char] - tok-num !
      then,
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-star                                 \ '*' '*='
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-star-eq tok-num !
  else,
    [char] * tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-slash                                \ '/' '/=' (// and /* handled earlier)
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-slash-eq tok-num !
  else,
    [char] / tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-percent                              \ '%' '%='
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-percent-eq tok-num !
  else,
    [char] % tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-caret                                \ '^' '^='
  cc-peek-char [char] = = if,
    cc-next-char drop  pt-caret-eq tok-num !
  else,
    [char] ^ tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-dot                                  \ '.' '...'
  cc-peek-char [char] . = if,
    cc-peek-char-2 nip [char] . = if,
      cc-next-char drop  cc-next-char drop
      pt-ellipsis tok-num !
    else,
      [char] . tok-num !
    then,
  else,
    [char] . tok-num !
  then,
  tk-punct tok-kind ! ;

\ cc-lex-punct ( -- )  Consume the next char and dispatch to a per-char
\ handler.  Single-char punctuation (; { } ( ) [ ] , ? : ~) falls through
\ to the default arm, which stores the byte itself as the punct code.
: cc-lex-punct
  cc-next-char                                  ( first-char )
  dup [char] = = if, drop cc-punct-eq      else,
  dup [char] ! = if, drop cc-punct-bang    else,
  dup [char] < = if, drop cc-punct-lt      else,
  dup [char] > = if, drop cc-punct-gt      else,
  dup [char] & = if, drop cc-punct-amp     else,
  dup [char] | = if, drop cc-punct-pipe    else,
  dup [char] + = if, drop cc-punct-plus    else,
  dup [char] - = if, drop cc-punct-minus   else,
  dup [char] * = if, drop cc-punct-star    else,
  dup [char] / = if, drop cc-punct-slash   else,
  dup [char] % = if, drop cc-punct-percent else,
  dup [char] ^ = if, drop cc-punct-caret   else,
  dup [char] . = if, drop cc-punct-dot     else,
    \ Default: single-char punct.
    tok-num ! tk-punct tok-kind !
  then, then, then, then, then, then, then,
  then, then, then, then, then, then, ;

\ ===========================================================================
\ Top-level: cc-next-token
\ ===========================================================================

\ cc-next-token ( -- )  Skip ws/comments, dispatch on the first byte.
: cc-next-token
  cc-skip-ws-and-comments
  cc-eof? if,
    tk-eof tok-kind !
  else,
    cc-peek-char
    dup digit?       if, drop cc-lex-number          else,
    dup [char] " =   if, drop cc-lex-string          else,
    dup [char] ' =   if, drop cc-lex-char            else,
    dup ident-start? if, drop cc-lex-ident-or-kw     else,
      drop cc-lex-punct
    then, then, then, then,
  then, ;

\ ===========================================================================
\ The parser's interface: putback, mark and reset
\ ===========================================================================
\ The lexer reads one token at a time with no built-in peek.  A parser that
\ has read one token too many puts it back: cc-putback-token sets
\ cc-tok-pending, and the next cc-next-token-keep returns the same tok-*
\ state without advancing.

\ cc-next-token-keep ( -- )  Advance to the next token unless one is pending.
: cc-next-token-keep
  cc-tok-pending @ if,
    [lit] 0 cc-tok-pending !
  else,
    cc-next-token
  then, ;

\ cc-putback-token ( -- )  Mark the current tok-* as still-pending so the
\ next cc-next-token-keep returns it without advancing.
: cc-putback-token
  true cc-tok-pending ! ;

\ To look further ahead, a parser marks the whole lexer state (reader
\ cursor, line, current token, putback flag: the cc-lex-state block),
\ reads as many tokens as it likes, and resets to the mark.  A mark is any
\ cc-lex-state-size bytes of storage.

\ cc-lex-copy ( src dst -- )  Copy one lexer-state block, last cell first.
: cc-lex-copy
  cc-lex-state-size
  begin, dup while,
    [lit] 8 -                                   ( src dst off )
    >r  over r@ + @  over r@ + !  r>
  repeat,
  drop 2drop ;

\ cc-lex-mark ( buf -- )  Save the lexer state into buf.
: cc-lex-mark   cc-lex-state swap cc-lex-copy ;

\ cc-lex-reset ( buf -- )  Restore the lexer state saved by cc-lex-mark.
: cc-lex-reset  cc-lex-state cc-lex-copy ;

\ cc-peek-mark is the one mark every lookahead in the parser uses.  Between
\ marking and resetting, each of them only reads tokens, so no lookahead
\ can start while another is in progress and one buffer serves them all.
create cc-peek-mark  cc-lex-state-size allot
