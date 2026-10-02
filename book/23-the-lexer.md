# Chapter 23 — The Lexer

```text
Missing capability: the parser cannot ask for C-shaped units of source.
New pattern: one token at a time lives in tok-* cells with compact kind and punctuation IDs.
Artifact after this chapter: the cc-next-token interface over idents, numbers, strings, chars, kws, and punct.
Proof link: every later Stage-A parser consumes this token stream instead of raw source bytes.
```

After Ch 22, `tri.c` is 466 bytes of characters, but a parser does
not want characters.  At line 12 it should not have to see `i`, `n`,
`t`, a space, `w`, `[`, a space, `4`.  It wants to ask "what's
next?" and hear "the keyword `int`", "the identifier `w`", "`[`",
"the number 4".  The 683-line file `050-cc-lex.fth` answers that
question through a single word, `cc-next-token`.

Every later pass (types, symbols, expressions, declarations,
statements) sees the source only through five cells this file fills:
`tok-kind`, `tok-num`, `tok-str-addr`, `tok-str-len` and `tok-kw-id`,
part of the lexer-state block Ch 21 set up.  There is no token list and no streaming consumer.  The
parser calls `cc-next-token`, reads `tok-kind`, drives its grammar
with that one token, then asks for the next.  The lexer is hand-rolled
(no regex, no flex), and it never sees a macro: Ch 22 has already
replaced every macro name with its body, so `ROWS` arrives as the
text `4`.

## 1. Token kinds and punctuation IDs

The file opens by naming everything a token can be:

```forth file=050-cc-lex.fth
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

```

Seven token kinds (`eof`, `ident`, `num`, `str`, `chr`, `punct`,
`kw`) and twenty-two multi-character punctuation IDs; the thirty C
keywords follow in §2.  Everything else in the file builds on these
constants.

Single-character punctuation (`;`, `{`, `(`, `[`, `,`, `?`, `:`, `~`)
reuses the ASCII byte itself as `tok-num`.  Multi-character
punctuation needs its own namespace, so the `pt-*` codes occupy
`[256, 277]`, outside the byte range.  A single `>= 256` test could
tell the two apart, though the parser never needs one: it compares
against exact values.

The five `tok-*` cells of the lexer-state block (Ch 21) are the
lexer's single-token state; each name works like a variable.
`tok-kind` says what was read.  `tok-num` carries numeric values
(including the punctuation code for `tk-punct`), `tok-str-addr/len`
point into `cc-src-buf` for identifiers and string literals, and
`tok-kw-id` carries the keyword ID when `tok-kind = tk-kw`.  Strings
aren't copied.  They are slices of the source buffer, which lives for
the whole compilation.

## 2. The keyword table

The thirty keywords are laid down by name, then numbered:

```forth file=050-cc-lex.fth
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

```

Each entry in `kw-table` is a length byte followed by that many name
bytes, and a `0` length byte ends the table.  `kw,` builds one
entry from the next token with Ch 12's `token` and `bytes,`:
`kw, int` lays down `3 'i' 'n' 't'`.  The length sits inline, so no
parallel `[length, pointer]` table is needed.  The `kw-*` constants follow the entry order: `kw-int = 0`
because `"int"` is first, `kw-char = 1` because `"char"` is second,
and so on.

Three small helpers come next.

```forth file=050-cc-lex.fth
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

```

The identifier classifiers `ident-start?` and `ident-cont?` are the
shared ones from Ch 21, the same the preprocessor uses.
`cc-peek-char-2` is the two-byte
lookahead.  The lexer needs it only for `0x`, `//`, `/*` and the `...`
ellipsis; operators like `==`, `<=` and `<<=` consume their first byte
and test the next with plain `cc-peek-char`.

With the table and the classifiers in place, keyword recognition is
one walk over `kw-table`:

```forth file=050-cc-lex.fth
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

```

`cc-check-keyword` walks the table once with `( ptr id )` on the data
stack: a pointer into the table and the current candidate ID.  An
entry is compared only when its length byte equals the token's
length.  On a match the word stores the ID in `tok-kw-id`, sets
`tok-kind` to `tk-kw` and returns at once with `exit,` (Ch 11); the
loop holds nothing on the return stack, so the early return is
safe.  Falling off the end of the table means the token is an
identifier.

The advance step at the bottom is where the inline lengths pay off:

```
swap dup c@ 1+ + swap 1+
```

That is `( ptr id -- ptr+len+1 id+1 )`: read the length byte at
`ptr`, add 1 for the length byte itself, add to `ptr`, increment
`id`.  One `c@`, and no second table to index.

## 3. Whitespace and comments

Before each token, the lexer skips whatever the parser should never
see:

```forth file=050-cc-lex.fth
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

```

Three helpers cooperate:

- `cc-skip-line-comment` runs after the caller has consumed the
  `//`.  It eats bytes until newline or EOF, leaving the newline
  for the outer loop to eat as ordinary whitespace.
- `cc-skip-block-comment` runs after the caller has consumed
  `/*`.  It eats bytes until it sees `*/`, consuming the closer.
- `cc-skip-ws-and-comments` is the outer loop: if the next byte is
  whitespace, eat it; if it's `/`, peek the byte after to decide
  between a comment and a bare `/`; otherwise stop.

The last two stop from inside their loops with `exit,` (Ch 11): the
block-comment skipper as soon as it has eaten `*/`, the outer loop
at the first byte that starts neither whitespace nor a comment.
The `while,` test only has to watch for EOF.

`cc-skip-line-comment` leaves the newline, but `cc-skip-block-comment`
consumes the `*/`.  The newline is ordinary whitespace, so leaving it
for the outer loop costs nothing, and line counting doesn't care who
eats it, since `cc-next-char` bumps `cc-src-line` on every newline it
returns.  Nothing outside the comment would recognise `*/`, so the
comment skipper has to swallow it itself.

## 4. Number, identifier, string, char

Numbers come first, in decimal or hex:

```forth file=050-cc-lex.fth
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

```

`cc-lex-number` does one `cc-peek-char-2` to decide between hex
(`0x…` / `0X…`), octal (a `0` followed by another digit, so `010` is
8, as in C) and decimal.  Each path accumulates digits with
`*base + digit` on the data stack, then stores into `tok-num` and sets
`tok-kind = tk-num`.  The accumulator is the full 64-bit cell and
wraps, which is how the built-in `EOF` of Ch 22, spelled
`0xFFFFFFFFFFFFFFFF`, has the all-ones bit pattern.  A suffix
(`10UL`, `0xffL`) is consumed with the number, and its full original
spelling is retained in `tok-str-addr` / `tok-str-len`.  The legacy
target still treats every integer as 64 bits.  LP64 uses Ch 24's
`cc-integer-literal-type` to select `int`, `unsigned int`, `long`, or
`unsigned long` from the suffix, base, and unsigned value range.
These existing slice cells are already saved by lexer marks, so
lookahead restores number metadata without changing the state layout.

Identifiers are read as a slice and checked against the keywords:

```forth file=050-cc-lex.fth
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

```

`cc-lex-ident-or-kw` reads the identifier as a `(start, len)` slice
of `cc-src-buf` into `tok-str-addr` / `tok-str-len`, then calls
`cc-check-keyword`, which settles whether it is a `tk-kw` or a
`tk-ident`.  Nothing else can happen to a name here; what it means is
the parser's question (Ch 24's symbol table).

String and character literals close the section:

```forth file=050-cc-lex.fth
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

```

`cc-lex-string` records the quoted body as a `(start, len)` slice of
`cc-src-buf`, keeping backslash escapes as literal byte pairs.
Escape decoding happens in codegen (Ch 26's `cc-emit-string-bytes`),
which walks the slice as it copies the literal's bytes into the code
stream.  The lexer stays simple.

`cc-lex-char` does decode escapes immediately, because its result is a
single byte value in `tok-num`.  Both kinds of literal decode with the
same word, `cc-decode-escape`, which is handed the address after the
backslash and answers the byte and how many bytes the escape used:
`\n`, `\t`, `\r`, `\a`, `\b`, `\f` and `\v` are the usual control
characters; one to three octal digits (`\0`, `\033`) or `\x` and hex
digits (`\x1b`) give a byte by value; and any other escaped character
stands for itself, which covers `\\`, `\'` and `\"`.  pnut prints its
error messages in colour with `"\x1b[31m"`.  One table matters: when
character literals had their own copy it lacked `\r`, so `'\r'`
compiled to `'r'` (114) while `"\r"` gave 13;
`tests/cc/I-cr-escape.c` checks that both now agree, and
`tests/cc/O-octal-escapes.c` checks the numeric escapes and `010`.

## 5. Punctuation: a fan-out

C punctuation is the messy part of the lexer.  Some tokens are one
byte (`;`, `,`, `?`).  Some have two-byte forms with the same prefix
(`=` / `==`).  Some have three-byte forms (`<<=`).  Some prefixes
overlap badly (`-`, `--`, `-=`, `->`).

The file answers with one `cc-punct-X` handler per ambiguous first
character.  Each handler is entered after its first byte has been
consumed; it peeks ahead and picks the longest match.

```forth file=050-cc-lex.fth
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

```

`cc-punct-lt` shows the deepest case: `<`, `<=`, `<<` and `<<=` from
a single prefix, with two nested peeks.  `cc-punct-gt` mirrors it.
The remaining nine handlers follow the same shape:

```forth file=050-cc-lex.fth
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

```

`cc-punct-minus` has four outcomes (`-`, `--`, `-=`, `->`), and `cc-punct-dot` is the one
punctuation handler that needs `cc-peek-char-2`, because `..` alone
is not a token: it must see two more dots before committing to `...`.

A dispatcher picks the handler from the first byte:

```forth file=050-cc-lex.fth
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

```

It is a long `if, … else,` chain.  Anything without its own handler (`;`, `{`, `}`, `(`,
`)`, `[`, `]`, `,`, `?`, `:`, `~`) falls through to the default arm,
which uses the byte itself as the punctuation code.  The seed has no
`case`, so this is what a 14-way dispatch looks like: thirteen `if,`s
closed by thirteen `then,`s, a count worth checking when you read one
of these chains.

## 6. The top-level driver

`cc-next-token` reads one token; §7 wraps it for the parser.

```forth file=050-cc-lex.fth
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

```

Skip whitespace and comments.  At EOF, report `tk-eof`.  Otherwise
classify on the first byte: digit → number; `"` (34) → string; `'`
(39) → char; ident-start → identifier or keyword; everything else →
punctuation.  The chosen word fills the `tok-*` cells and returns.

The four tests are disjoint (`ident-start?` excludes digits, so a
leading digit can only begin a number), so their order doesn't
matter.  What matters is that punctuation is the final `else`: any
byte none of the four claims falls through to `cc-lex-punct`.

## 7. The parser's interface: putback, mark and reset

A recursive-descent parser often knows it has gone one token too far
only after reading it: `x` followed by `(` is a call, followed by
anything else a variable.  The file ends with the words the parser
actually drives the lexer through:

```forth file=050-cc-lex.fth
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
```

`cc-next-token-keep` is what the parsers call instead of
`cc-next-token`.  After `cc-putback-token` sets `cc-tok-pending`, the
next `cc-next-token-keep` clears the flag and returns without reading,
so the same `tok-*` values are seen twice.  One token of putback is
enough for almost all of C.

The rest needs to look further: is `int (*fp)(int);` a function
pointer, is `x :` a label, does this top-level declaration reach `{`
before `;`?  For those the parser takes a *mark*: `cc-lex-mark` copies
the whole 64-byte lexer-state block (reader position, line, current
token and the putback flag) into a buffer, the parser reads as many
tokens as it likes, and `cc-lex-reset` copies the block back.  Because
Ch 21 put every moving part of the lexer in that one block, the copy
cannot miss a field.  `cc-lex-copy` copies a cell at a time, walking
the offset down from 56 to 0.  Chs 27–31 use one mark buffer,
`cc-peek-mark`, the last thing in the file, for every such look-ahead.

## Try it

**Small check:** drive the lexer by hand on line 12 of `tri.c`,
`int w[ROWS];`, with the `#define` it depends on.
Seed-forth has no `-e` flag or `include` word, so we concatenate the
five files onto stdin as they are (the seed's reader skips their
comments), then the C source.
A one-shot `dump-tokens` word slurps the C source via `cc-load-stdin`,
runs the lexer in a loop, and emits each token's kind as an ASCII
digit until end-of-input:

```sh
./build.sh
{
  cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth \
      040-cc-prep.fth 050-cc-lex.fth
  cat <<'FORTH'
    : dump-tokens
      cc-load-stdin cc-preprocess
      begin, cc-next-token  tok-kind @ tk-eof = 0=  while,
        tok-kind @ [lit] 48 + emit [lit] 32 emit
      repeat, bye ;
    dump-tokens
FORTH
  cat <<'C'
#define ROWS 4
    int w[ROWS];
C
} | ./seed-forth
```

The output is `6 1 5 2 5 5`: keyword, identifier, `[`, number, `]`,
`;`.  The `2` is `ROWS`, which the preprocessor had already replaced
with the text `4`, so the lexer read a `tk-num` 4.  The whole of `tri.c` lexes to 168 tokens,
and 4 of its 14 number tokens were spelled `ROWS` in the source.  The
three character literals arrive as `tk-chr` with their values already
decoded: `' '` is 32, `'*'` is 42, and `'\n'` is 10.

**Layer check:** the probe shows only kinds.  For every token's text
and numeric value, run the lexer unit test:

```sh
./build.sh
./test.sh                                       # runs test-050-cc-lex.fth
```

`test-050-cc-lex.fth` exercises every token kind, every multi-char
punctuation, the keyword table, the comment skipper, the three number
bases and the numeric escapes.  Read it to see what each entry point is
supposed to produce.

**Bootstrap relevance:** every Stage-A parser consumes source only
through `cc-next-token`, so `tests/cc/stage-a-check.sh` covers this
lexer on the full M2-Planet input.

## Exercises

1. **★★★ Modify.** Add a `tk-*` constant and a new keyword (e.g. `inline`) to the
   table.  How many lines of patch?  Where does the `kw-*` ID
   need to be inserted to keep ordering stable?

2. **★★ Verify.** The lexer treats tab (9), space (32), `\r` (13), and `\n`
   (10) all as whitespace via `space?`.  Does it handle CRLF
   line endings?  Construct a test case and observe.

3. **★★ Trace.** `cc-lex-string` doesn't decode escapes — codegen does.  Find
   the word in `090-cc-emit.fth` (Ch 26) that walks the slice and
   turns `\n` into byte 10.  Trace one byte.

4. **★★ Extend.** The keyword table is walked linearly.  At 30 entries and a
   short average length, that's fine.  Could a hash table be
   faster, and would it be worth the bytes-of-code?

5. **★★ Trace.** The lexer has no error path — every malformed token (e.g. an
   unterminated string at EOF) ends with the lexer just
   stopping.  Trace what happens downstream when the parser sees
   the resulting `tk-eof` mid-expression.  Is silent truncation
   safe for the bootstrap chain?

## After this chapter

The parser can ask for C-shaped units of source on demand: each
`cc-next-token` puts one identifier, keyword, number, string, char or
punctuation token into the `tok-*` cells, with macro substitution
already applied.  Every later parser layer reads `tok-*` rather than
raw bytes, so the lexer's exact behaviour is the input contract for
the rest of the Stage-A proof.  `tri.c` is now 168 tokens, but when
the parser reaches `t.rows` on line 14, nothing yet remembers that `t`
is a struct or where `rows` sits inside it.  Ch 24 builds that memory.

## Takeaways

- The lexer's interface is one entry point and five cells: call `cc-next-token` (or `cc-next-token-keep`, which honours a put-back token), read `tok-kind`, and dispatch.
- The lexer's whole state is one 64-byte block, so looking ahead is `cc-lex-mark`, read, `cc-lex-reset`.
- Multi-character punctuation lives at codes `>= 256` while single-character punctuation reuses its ASCII byte, so the easy cases need no separate enumeration.
- Macro substitution happens in the lexer, where a `tk-ident` that hits the macro table becomes a `tk-num` before the parser sees it.

Next: Chapter 24 — Types and Symbols.
