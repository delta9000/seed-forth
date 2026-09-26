\ 050-cc-lex.fth — C tokenizer (one-token lookahead) for the C-subset compiler.
\ Reads bytes from cc-src-buf via cc-peek-char/cc-next-char/cc-eof? (030-cc-io.fth).
\ Stores the current token in 5 globals: tok-kind, tok-num, tok-str-addr,
\ tok-str-len, tok-kw-id.  Caller drives the lexer via cc-next-token.
\
\ Depends on 010-lib.fth (control-flow combinators, classifiers, bytes-eq, etc.),
\ 030-cc-io.fth (cc-src-buf, cc-peek-char, cc-next-char, cc-eof?), and
\ 040-cc-prep.fth (cc-macro-find-int for macro substitution).

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

variable tok-kind
variable tok-num
variable tok-str-addr
variable tok-str-len
variable tok-kw-id

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

\ ===========================================================================
\ Helpers: ident classifiers, 2-byte peek
\ ===========================================================================

\ ident-start? ( c -- f )  letter or '_'.
: ident-start?
  dup alpha?  swap [char] _ = or ;

\ ident-cont? ( c -- f )  ident-start? or digit.
: ident-cont?
  dup ident-start?  swap digit? or ;

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
: cc-skip-ws-and-comments
  begin,
    cc-eof? 0=
  while,
    cc-peek-char dup space? if,
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

\ cc-lex-number ( -- )  Decimal, or hex (0x/0X) if the first two chars match.
: cc-lex-number
  cc-peek-char-2                                  ( c1 c2 )
  over [char] 0 = if,                             \ c1 == '0' ?
    dup [char] x = swap [char] X = or if,         \ c2 == 'x' or 'X' ?
      drop                                        \ pop c1
      cc-next-char drop                           \ consume '0'
      cc-next-char drop                           \ consume 'x'/'X'
      cc-lex-number-hex
    else,
      drop                                        \ pop c1
      cc-lex-number-dec
    then,
  else,
    2drop
    cc-lex-number-dec
  then, ;

\ cc-lex-ident-or-kw ( -- )  Read [a-zA-Z_][a-zA-Z0-9_]* and check the
\ keyword table.  Sets tok-str-addr/len, then dispatches kind.
\
\ After the keyword check, if the ident did NOT match a keyword, consult the
\ preprocessor's macro table (cc-macro-find-int).  On match,
\ replace the token: tk-num with tok-num = the macro's integer value.
\ Object-like, integer-valued macros only.
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
  cc-check-keyword
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-macro-find-int  ( v found? )
    if,
      tok-num !
      tk-num tok-kind !
    else,
      drop
    then,
  then, ;

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

\ cc-lex-char ( -- )  Read 'c' or '\c'.  Stores the byte value in tok-num.
\ Recognised escapes: \n \t \\ \' \" \0.  Others pass through literally.
\ \xNN deferred.
: cc-lex-char
  cc-next-char drop                             \ consume opening '
  cc-peek-char backslash = if,                  \ escape
    cc-next-char drop                           \ consume backslash
    cc-next-char                                ( c )
    dup [char] n  = if, drop nl         else,   \ \n
    dup [char] t  = if, drop tab        else,   \ \t
    dup backslash = if, drop backslash  else,   \ \\
    dup [char] '  = if, drop [char] '   else,   \ \'
    dup [char] "  = if, drop [char] "   else,   \ \"
    dup [char] 0  = if, drop [lit] 0    else,   \ \0
    \ otherwise: pass the literal char through (stack already has it)
    then, then, then, then, then, then,
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
