\ seed/050-cc-lex.fth — C tokenizer (one-token lookahead) for the C-subset compiler.
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

create kw-table
\ "int"
[lit] 3 c, [lit] 105 c, [lit] 110 c, [lit] 116 c,
\ "char"
[lit] 4 c, [lit]  99 c, [lit] 104 c, [lit]  97 c, [lit] 114 c,
\ "void"
[lit] 4 c, [lit] 118 c, [lit] 111 c, [lit] 105 c, [lit] 100 c,
\ "short"
[lit] 5 c, [lit] 115 c, [lit] 104 c, [lit] 111 c, [lit] 114 c, [lit] 116 c,
\ "long"
[lit] 4 c, [lit] 108 c, [lit] 111 c, [lit] 110 c, [lit] 103 c,
\ "unsigned"
[lit] 8 c, [lit] 117 c, [lit] 110 c, [lit] 115 c, [lit] 105 c, [lit] 103 c, [lit] 110 c, [lit] 101 c, [lit] 100 c,
\ "signed"
[lit] 6 c, [lit] 115 c, [lit] 105 c, [lit] 103 c, [lit] 110 c, [lit] 101 c, [lit] 100 c,
\ "const"
[lit] 5 c, [lit]  99 c, [lit] 111 c, [lit] 110 c, [lit] 115 c, [lit] 116 c,
\ "volatile"
[lit] 8 c, [lit] 118 c, [lit] 111 c, [lit] 108 c, [lit]  97 c, [lit] 116 c, [lit] 105 c, [lit] 108 c, [lit] 101 c,
\ "static"
[lit] 6 c, [lit] 115 c, [lit] 116 c, [lit]  97 c, [lit] 116 c, [lit] 105 c, [lit]  99 c,
\ "extern"
[lit] 6 c, [lit] 101 c, [lit] 120 c, [lit] 116 c, [lit] 101 c, [lit] 114 c, [lit] 110 c,
\ "auto"
[lit] 4 c, [lit]  97 c, [lit] 117 c, [lit] 116 c, [lit] 111 c,
\ "register"
[lit] 8 c, [lit] 114 c, [lit] 101 c, [lit] 103 c, [lit] 105 c, [lit] 115 c, [lit] 116 c, [lit] 101 c, [lit] 114 c,
\ "restrict"
[lit] 8 c, [lit] 114 c, [lit] 101 c, [lit] 115 c, [lit] 116 c, [lit] 114 c, [lit] 105 c, [lit]  99 c, [lit] 116 c,
\ "struct"
[lit] 6 c, [lit] 115 c, [lit] 116 c, [lit] 114 c, [lit] 117 c, [lit]  99 c, [lit] 116 c,
\ "enum"
[lit] 4 c, [lit] 101 c, [lit] 110 c, [lit] 117 c, [lit] 109 c,
\ "typedef"
[lit] 7 c, [lit] 116 c, [lit] 121 c, [lit] 112 c, [lit] 101 c, [lit] 100 c, [lit] 101 c, [lit] 102 c,
\ "sizeof"
[lit] 6 c, [lit] 115 c, [lit] 105 c, [lit] 122 c, [lit] 101 c, [lit] 111 c, [lit] 102 c,
\ "if"
[lit] 2 c, [lit] 105 c, [lit] 102 c,
\ "else"
[lit] 4 c, [lit] 101 c, [lit] 108 c, [lit] 115 c, [lit] 101 c,
\ "while"
[lit] 5 c, [lit] 119 c, [lit] 104 c, [lit] 105 c, [lit] 108 c, [lit] 101 c,
\ "for"
[lit] 3 c, [lit] 102 c, [lit] 111 c, [lit] 114 c,
\ "do"
[lit] 2 c, [lit] 100 c, [lit] 111 c,
\ "return"
[lit] 6 c, [lit] 114 c, [lit] 101 c, [lit] 116 c, [lit] 117 c, [lit] 114 c, [lit] 110 c,
\ "break"
[lit] 5 c, [lit]  98 c, [lit] 114 c, [lit] 101 c, [lit]  97 c, [lit] 107 c,
\ "continue"
[lit] 8 c, [lit]  99 c, [lit] 111 c, [lit] 110 c, [lit] 116 c, [lit] 105 c, [lit] 110 c, [lit] 117 c, [lit] 101 c,
\ "goto"
[lit] 4 c, [lit] 103 c, [lit] 111 c, [lit] 116 c, [lit] 111 c,
\ "switch"
[lit] 6 c, [lit] 115 c, [lit] 119 c, [lit] 105 c, [lit] 116 c, [lit]  99 c, [lit] 104 c,
\ "case"
[lit] 4 c, [lit]  99 c, [lit]  97 c, [lit] 115 c, [lit] 101 c,
\ "default"
[lit] 7 c, [lit] 100 c, [lit] 101 c, [lit] 102 c, [lit]  97 c, [lit] 117 c, [lit] 108 c, [lit] 116 c,
\ Terminator
[lit] 0 c,

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

\ ident-start? ( c -- f )  letter or '_' (ASCII 95).
: ident-start?
  dup alpha?  swap [lit] 95 = or ;

\ ident-cont? ( c -- f )  ident-start? or digit.
: ident-cont?
  dup ident-start?  swap digit? or ;

\ cc-peek-char-2 ( -- c1 c2 )  Returns the byte at pos and the byte at pos+1
\ without advancing.  Returns 0 for c2 at EOF.  c1 is also 0 at EOF.
: cc-peek-char-2
  cc-peek-char                                  ( c1 )
  cc-src-pos @ [lit] 1 +                        ( c1 next-pos )
  dup cc-src-len @ < if,
    cc-src-buf swap + c@                        ( c1 c2 )
  else,
    drop [lit] 0                                ( c1 0 )
  then, ;

\ ===========================================================================
\ cc-check-keyword
\ ===========================================================================
\ Walks kw-table once.  We can't bail early (no `exit`), so we accumulate the
\ match into a variable and stop comparing once we already have a hit.

\ cc-kw-found-id holds -1 while still searching, or the matched id.
variable cc-kw-found-id

\ cc-check-keyword ( -- )  After cc-lex-ident-or-kw has set tok-str-addr/len,
\ this walks kw-table; on match sets tok-kind=tk-kw + tok-kw-id, otherwise
\ tok-kind=tk-ident.  Loop invariant on the data stack: ( ptr id ).
: cc-check-keyword
  [lit] 0 0= cc-kw-found-id !                   \ -1 = "still searching"
  kw-table                                      \ ptr
  [lit] 0                                       \ id
  begin,
    over c@ [lit] 0 >                           \ entry length non-zero?
  while,
    cc-kw-found-id @ [lit] 0 0= = if,           \ still searching?
      over c@ tok-str-len @ = if,               \ same length?
        \ Stack here: ( ptr id ).  bytes-eq wants ( a1 a2 u ) where
        \ a1 = tok-str-addr, a2 = ptr+1 (skipping length byte), u = tok-str-len.
        over [lit] 1 +  tok-str-addr @  swap  tok-str-len @  bytes-eq if,
          dup cc-kw-found-id !                  \ store the matched id
        then,
      then,
    then,
    \ Advance: ( ptr id ) -> ( ptr+len+1 id+1 )
    swap dup c@ [lit] 1 + over + nip swap [lit] 1 +
  repeat,
  drop drop                                     \ discard ptr and id
  cc-kw-found-id @ [lit] 0 0= = if,             \ -1 ?
    tk-ident tok-kind !
  else,
    cc-kw-found-id @ tok-kw-id !
    tk-kw tok-kind !
  then, ;

\ ===========================================================================
\ Whitespace and comment skipping
\ ===========================================================================

\ cc-skip-line-comment ( -- )  Caller has already consumed the //.  Skip
\ to (but do not consume) the next newline; the outer ws-skip will eat it.
: cc-skip-line-comment
  begin,
    cc-eof? 0=
    cc-peek-char [lit] 10 <> and
  while,
    cc-next-char drop
  repeat, ;

\ cc-skip-block-comment ( -- )  Caller has already consumed the /*.  Skip
\ to and including the closing */.  Maintains a "still scanning" flag on the
\ data stack to avoid the missing `exit` primitive.
: cc-skip-block-comment
  [lit] 0 0=                                    \ scanning flag = -1 (true)
  begin,
    dup cc-eof? 0= and                          \ keep going AND not eof
  while,
    drop                                        \ discard old flag
    cc-next-char                                ( c )
    [lit] 42 = if,                              \ saw '*'
      cc-peek-char [lit] 47 = if,               \ followed by '/'
        cc-next-char drop                       \ consume '/'
        [lit] 0                                 \ stop
      else,
        [lit] 0 0=                              \ keep going
      then,
    else,
      [lit] 0 0=                                \ keep going
    then,
  repeat,
  drop ;                                        \ discard final flag

\ cc-skip-ws-and-comments ( -- )  Skip whitespace, // line-comments, and
\ /* block comments.  Stops at the first non-whitespace, non-comment byte.
\ Also uses a data-stack scanning flag.
: cc-skip-ws-and-comments
  [lit] 0 0=                                    \ keep-going flag = -1
  begin,
    dup cc-eof? 0= and
  while,
    drop                                        \ discard old flag
    cc-peek-char dup space? if,
      drop cc-next-char drop
      [lit] 0 0=                                \ keep going
    else,
      [lit] 47 = if,                            \ '/' ?
        cc-peek-char-2 nip [lit] 47 = if,       \ // ?
          cc-next-char drop  cc-next-char drop
          cc-skip-line-comment
          [lit] 0 0=                            \ keep going
        else,
          cc-peek-char-2 nip [lit] 42 = if,     \ /* ?
            cc-next-char drop  cc-next-char drop
            cc-skip-block-comment
            [lit] 0 0=                          \ keep going
          else,
            [lit] 0                             \ stop: bare '/'
          then,
        then,
      else,
        [lit] 0                                 \ stop: not ws or comment
      then,
    then,
  repeat,
  drop ;

\ ===========================================================================
\ Number / identifier / string / char lexers
\ ===========================================================================

\ Hex digit helpers (Task D: 0xFF hex literals).
\ cc-hex-digit? ( c -- f )  -1 if c is 0-9, a-f, A-F.
: cc-hex-digit?
  dup digit? if,
    drop [lit] 0 0=                               \ -1 = true
  else,
    dup alpha-lower? if,
      [lit] 97 - [lit] 6 / 0=                     \ 'a'..'f' -> 0..5 -> /6=0
    else,
      dup alpha-upper? if,
        [lit] 65 - [lit] 6 / 0=                   \ 'A'..'F'
      else,
        drop [lit] 0
      then,
    then,
  then, ;

\ cc-hex-digit-val ( c -- v )  Convert hex digit char to 0..15.
: cc-hex-digit-val
  dup digit? if,
    [lit] 48 -
  else,
    dup alpha-lower? if,
      [lit] 87 -                                  \ 'a'=97 -> 10
    else,
      [lit] 55 -                                  \ 'A'=65 -> 10
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
    cc-peek-char [lit] 48 - +
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
  over [lit] 48 = if,                             \ c1 == '0' ?
    dup [lit] 120 = swap [lit] 88 = or if,        \ c2 == 'x' or 'X' ?
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
    [lit] 1 +
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
    cc-peek-char [lit] 34 <> and
  while,
    cc-peek-char [lit] 92 = if,                 \ backslash: keep both bytes
      cc-next-char drop
      [lit] 1 +
      cc-eof? 0= if,
        cc-next-char drop
        [lit] 1 +
      then,
    else,
      cc-next-char drop
      [lit] 1 +
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
  cc-peek-char [lit] 92 = if,                   \ escape
    cc-next-char drop                           \ consume backslash
    cc-next-char                                ( c )
    dup [lit] 110 = if, drop [lit] 10  else,    \ \n
    dup [lit] 116 = if, drop [lit]  9  else,    \ \t
    dup [lit]  92 = if, drop [lit] 92  else,    \ \\
    dup [lit]  39 = if, drop [lit] 39  else,    \ \'
    dup [lit]  34 = if, drop [lit] 34  else,    \ \"
    dup [lit]  48 = if, drop [lit]  0  else,    \ \0
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
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-eq-eq tok-num !
  else,
    [lit] 61 tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-bang                                 \ '!'  '!='
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-bang-eq tok-num !
  else,
    [lit] 33 tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-lt                                   \ '<' '<=' '<<' '<<='
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-le tok-num !
  else,
    cc-peek-char [lit] 60 = if,
      cc-next-char drop
      cc-peek-char [lit] 61 = if,
        cc-next-char drop  pt-shl-eq tok-num !
      else,
        pt-shl tok-num !
      then,
    else,
      [lit] 60 tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-gt                                   \ '>' '>=' '>>' '>>='
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-ge tok-num !
  else,
    cc-peek-char [lit] 62 = if,
      cc-next-char drop
      cc-peek-char [lit] 61 = if,
        cc-next-char drop  pt-shr-eq tok-num !
      else,
        pt-shr tok-num !
      then,
    else,
      [lit] 62 tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-amp                                  \ '&' '&&' '&='
  cc-peek-char [lit] 38 = if,
    cc-next-char drop  pt-and-and tok-num !
  else,
    cc-peek-char [lit] 61 = if,
      cc-next-char drop  pt-amp-eq tok-num !
    else,
      [lit] 38 tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-pipe                                 \ '|' '||' '|='
  cc-peek-char [lit] 124 = if,
    cc-next-char drop  pt-or-or tok-num !
  else,
    cc-peek-char [lit] 61 = if,
      cc-next-char drop  pt-pipe-eq tok-num !
    else,
      [lit] 124 tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-plus                                 \ '+' '++' '+='
  cc-peek-char [lit] 43 = if,
    cc-next-char drop  pt-plus-plus tok-num !
  else,
    cc-peek-char [lit] 61 = if,
      cc-next-char drop  pt-plus-eq tok-num !
    else,
      [lit] 43 tok-num !
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-minus                                \ '-' '--' '-=' '->'
  cc-peek-char [lit] 45 = if,
    cc-next-char drop  pt-minus-minus tok-num !
  else,
    cc-peek-char [lit] 61 = if,
      cc-next-char drop  pt-minus-eq tok-num !
    else,
      cc-peek-char [lit] 62 = if,
        cc-next-char drop  pt-arrow tok-num !
      else,
        [lit] 45 tok-num !
      then,
    then,
  then,
  tk-punct tok-kind ! ;

: cc-punct-star                                 \ '*' '*='
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-star-eq tok-num !
  else,
    [lit] 42 tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-slash                                \ '/' '/=' (// and /* handled earlier)
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-slash-eq tok-num !
  else,
    [lit] 47 tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-percent                              \ '%' '%='
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-percent-eq tok-num !
  else,
    [lit] 37 tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-caret                                \ '^' '^='
  cc-peek-char [lit] 61 = if,
    cc-next-char drop  pt-caret-eq tok-num !
  else,
    [lit] 94 tok-num !
  then,
  tk-punct tok-kind ! ;

: cc-punct-dot                                  \ '.' '...'
  cc-peek-char [lit] 46 = if,
    cc-peek-char-2 nip [lit] 46 = if,
      cc-next-char drop  cc-next-char drop
      pt-ellipsis tok-num !
    else,
      [lit] 46 tok-num !
    then,
  else,
    [lit] 46 tok-num !
  then,
  tk-punct tok-kind ! ;

\ cc-lex-punct ( -- )  Consume the next char and dispatch to a per-char
\ handler.  Single-char punctuation (; { } ( ) [ ] , ? : ~) falls through
\ to the default arm, which stores the byte itself as the punct code.
: cc-lex-punct
  cc-next-char                                  ( first-char )
  dup [lit]  61 = if, drop cc-punct-eq      else,
  dup [lit]  33 = if, drop cc-punct-bang    else,
  dup [lit]  60 = if, drop cc-punct-lt      else,
  dup [lit]  62 = if, drop cc-punct-gt      else,
  dup [lit]  38 = if, drop cc-punct-amp     else,
  dup [lit] 124 = if, drop cc-punct-pipe    else,
  dup [lit]  43 = if, drop cc-punct-plus    else,
  dup [lit]  45 = if, drop cc-punct-minus   else,
  dup [lit]  42 = if, drop cc-punct-star    else,
  dup [lit]  47 = if, drop cc-punct-slash   else,
  dup [lit]  37 = if, drop cc-punct-percent else,
  dup [lit]  94 = if, drop cc-punct-caret   else,
  dup [lit]  46 = if, drop cc-punct-dot     else,
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
    dup [lit] 34 =   if, drop cc-lex-string          else,
    dup [lit] 39 =   if, drop cc-lex-char            else,
    dup ident-start? if, drop cc-lex-ident-or-kw     else,
      drop cc-lex-punct
    then, then, then, then,
  then, ;
