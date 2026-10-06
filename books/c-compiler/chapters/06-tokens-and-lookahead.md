# 6. Tokens and reversible lookahead

[Previous: Conditional preprocessing and profile extensions](05-conditionals-and-profile-extensions.md) · [Practice help](../practice/06-solutions.md) · [Edition coverage](../../COVERAGE.md)

The preprocessor has replaced `ROWS` with text containing `4`. The parser still needs to distinguish that number from a name, a bracket, or the character value in `'4'`. It also needs to ask a question about what comes next without losing its place. Those needs meet in the lexer: one current-token record, a byte cursor, and two deliberately different ways to revisit input.

By the end, you should be able to derive token records from a short source span, identify which cells are meaningful, explain the treatment of spellings and escapes, and choose between putting back one token and restoring a complete lexer mark. The goal is to predict the state a parser receives, not to memorize numeric IDs.

## Bring the reader and lifetime contracts

[C02](02-buffers-arenas-and-failure.md) supplied the source span, next-byte cursor, and eight-byte cells. [C03–C05](03-preprocessing-regions-and-includes.md) supplied flattened, expanded source. The lexer does not look up macros. An identifier surviving preprocessing remains an identifier unless this lexer's keyword table recognizes its exact spelling.

Two checks before continuing:

1. Does peeking at a newline increment `cc-src-line`, or does consuming it do so?
2. If a saved span points at source bytes that are later overwritten, does saving its address preserve the old spelling?

Consuming increments the line; peeking does not. Saving an address does not preserve the bytes. If either distinction needs a refresher, return to C02's reader and ownership examples. Otherwise, use the worked tables and try the exercises directly.

Positions and lengths below count bytes; stacks run bottom-to-top from left to right; source base B names owned storage. Tables show post-state. In C code blocks, `\n` is two written bytes inside an escape spelling. In explicitly labeled escaped-byte descriptions, `\n` denotes one LF, `\r` one CR, and `\\` one backslash. `␠` denotes one ASCII space. No address in a paper trace is a proposed live address.

**Evidence and profile.** This chapter follows inspected [050-cc-lex.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth), with [020's state layout](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/020-cc-arena.fth#L12-L28) and [030's reader](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth#L86-L105), at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`. All traces are checked manual derivations, not executions. Unless a section changes the premise, use C01's default legacy direct-ELF profile, with `cc-target-sysv=0`, preserved source storage, bounded counts, and an initially clear pending flag. This account establishes neither complete C-standard conformance nor a newly verified build or bootstrap.

## A kind grants meaning to particular cells

The lexer does not construct a persistent token list. Each call replaces selected fields of one record. Its five token cells occupy part of this eight-cell block:

| Byte offset in `cc-lex-state` | Cell name | Role |
|---:|---|---|
| 0 | `cc-src-pos` | Offset of next unread byte |
| 8 | `cc-src-line` | One-based flattened-source line at the reader |
| 16 | `tok-kind` | Current token's classification |
| 24 | `tok-num` | Numeric payload, character value, or punctuation code |
| 32 | `tok-str-addr` | Borrowed spelling/body address |
| 40 | `tok-str-len` | Borrowed spelling/body length |
| 48 | `tok-kw-id` | Keyword ID |
| 56 | `cc-tok-pending` | Current token is available for one replay |

`cc-lex-state-size` is 64 bytes. Source base, source length, and source capacity live elsewhere. The line cell records reader progress; there is no separate token-start line in this layout.

The **kind** acts as a permission to interpret particular payloads:

| Kind name and value | Meaningful payload after this scanner produces it |
|---|---|
| `tk-eof = 0` | No token payload |
| `tk-ident = 1` | Address/length of the identifier |
| `tk-num = 2` | `tok-num` and address/length of the full integer spelling |
| `tk-str = 3` | Address/length of the quoted body, without delimiters and still escaped |
| `tk-chr = 4` | Decoded value in `tok-num` |
| `tk-punct = 5` | Punctuation code in `tok-num` |
| `tk-kw = 6` | Keyword ID and address/length of its spelling |
| `tk-float = 7` | Later hook's spelling span; its `tok-num=0` is a placeholder, not a decoded floating value |

There are eight declared kinds. The last has a profile-specific provider described below; the base scanner never assigns it.

A **stale cell** still contains its earlier bits but has no meaning for the current kind. Reading `w` after `int` leaves `tok-kw-id=0`; that does not make `w` the `int` keyword. Reading `[` after `w` leaves the `w` span in the record; that does not make the bracket's spelling `w`. The implementation avoids clearing unused fields. Its clients must check kind before using a payload.

Even initialization is local: `cc-src-init` rewinds position and line and clears source length, but does not initialize all token cells or the pending flag. Our paper fixtures explicitly establish their source length and clear pending. There is no meaningful “current token” before one is supplied or restored from a valid saved state.

## Route bytes into a token

The complete base dispatch is short enough to inspect:

```forth
: cc-lex-extra-default [lit] 0 ;
defer cc-lex-extra-fwd
' cc-lex-extra-default is cc-lex-extra-fwd

: cc-next-token
  cc-skip-ws-and-comments
  cc-lex-extra-fwd if, exit, then,
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

[Source: top-level dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L625-L643).

First remove separators. Next give the deferred **extra hook** a chance to handle a token; nonzero means the token is ready, so return. Otherwise test the length-based EOF condition and classify the first byte. The default hook returns zero and changes nothing.

The hook comes before EOF. A replacement must tolerate being called at the end. Returning false allows the base dispatch to continue from the resulting cursor; the interface does not universally promise that a false-returning hook left that cursor unchanged. The later extension-word skipper is an example.

At EOF the base code stores only kind zero. It neither clears the payloads nor advances position. A real zero byte inside the source is different: `cc-eof?` is false there, so the default punctuation arm can consume that byte and report punctuation code zero. Testing the byte alone would lose this distinction.

## Follow a fragment of `tri.c`

Take two fragments from C01, the array declaration and newline call, and arrange them next to one another without indentation. The following **isolated lexer fixture** is already preprocessed; it is not a claim about whole-file order or byte offsets:

```c
int w[ 4 ];
putchar('\n');
```

There is one LF between the lines and **no final LF**, making 26 bytes. The spaces around `4` are the separators introduced by the simple `ROWS` expansion. Key byte offsets are:

```text
0..2 int   3 space   4 w   5 [   6 space   7 4
8 space    9 ]      10 ;  11 LF
12..18 putchar      19 (  20 '   21 backslash   22 n   23 '   24 )   25 ;
```

Initialize position=0, line=1, length=26, pending=0. Repeated token reads predict:

| Token just produced | Position | Line | Kind | Valid payload |
|---|---:|---:|---|---|
| `int` | 3 | 1 | keyword | ID 0; span `(B,3)` |
| `w` | 5 | 1 | identifier | Span `(B+4,1)` |
| `[` | 6 | 1 | punctuation | 91 |
| `4` | 8 | 1 | number | 4; span `(B+7,1)` |
| `]` | 10 | 1 | punctuation | 93 |
| `;` | 11 | 1 | punctuation | 59 |
| `putchar` | 19 | 2 | identifier | Span `(B+12,7)` |
| `(` | 20 | 2 | punctuation | 40 |
| `'\n'` | 24 | 2 | character | 10 |
| `)` | 25 | 2 | punctuation | 41 |
| `;` | 26 | 2 | punctuation | 59 |
| End | 26 | 2 | EOF | None |

Why does `int` stop at position 3? Identifier continuation rejects the space and leaves it unread. The next token call consumes that separator, then `w`. Why does `putchar` end on line 2? Its call first consumes the real LF at offset 11. The character token's decoded value 10 does **not** increment line: its source bytes are backslash and `n`, not LF.

The table hides stale fields intentionally. Expand one row: after `(`, `tok-num=40`, the span still points at `putchar`, and `tok-kw-id` still holds 0 from `int`. After `'\n'`, number changes to 10; that same old name span remains. After EOF all those payload bits remain, including the final semicolon's number 59. None is a new EOF payload.

## Names use spans; keywords use a small table

`cc-lex-ident-or-kw` starts at `B+pos`, counts identifier-continuation bytes, and stores their borrowed span. Its caller has already established a valid starting byte. [030's classifiers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth) accept ASCII letters/underscore initially and additionally digits afterward. Thus `rows2` is one name, while initial `2` selects number scanning.

`kw,` is a dictionary-building helper, not a C-token reader. When loading the Forth file it reads the next Forth token, emits a one-byte length, then emits the name bytes. `kw-table` consists of those packed entries followed by a zero length. It has these 34 entries, with IDs fixed by order:

| IDs | Exact keyword spellings in that order |
|---|---|
| 0–5 | `int`, `char`, `void`, `short`, `long`, `unsigned` |
| 6–11 | `signed`, `const`, `volatile`, `static`, `extern`, `auto` |
| 12–17 | `register`, `restrict`, `struct`, `enum`, `typedef`, `sizeof` |
| 18–23 | `if`, `else`, `while`, `for`, `do`, `return` |
| 24–29 | `break`, `continue`, `goto`, `switch`, `case`, `default` |
| 30–33 | `union`, `float`, `double`, `inline` |

Each constant is named `kw-` plus its spelling. [Source: table, constants, and matcher](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L51-L174).

`cc-check-keyword` carries `(entry-address, id)` on the stack. It compares lengths first, then exact bytes only for equal lengths. Failure advances the entry address by `length+1` and ID by one. Success stores that ID and sets keyword kind; reaching the zero terminator sets identifier kind. For `int`, the first entry matches. For `integer`, even the first comparison fails on length; it is not recognized as keyword-plus-suffix. Matching is case-sensitive.

Recognizing `float` as a keyword says nothing about which floating operations the chosen parser supports. Likewise a name's source span does not tell us whether it names a variable, type, member, or function. Those are later consumers' questions.

## Skip separators without losing reader progress

`cc-peek-char-2` returns current and following bytes without advancing. The first uses ordinary peek; the second is fetched only if `pos+1 < length`, otherwise it is zero. This helper distinguishes comment openers, base prefixes, and punctuation continuations while retaining the unread cursor.

`cc-cspace?` extends the library's space/tab/LF/CR set with vertical tab 11 and form feed 12. Only actual LF consumption increments the line. CRLF therefore contributes one line increment, not two.

`cc-skip-ws-and-comments` repeatedly consumes those spaces, or recognizes `//` and `/*` after seeing slash. A slash followed by neither marker remains unread for punctuation. `cc-skip-line-comment`, entered after `//`, stops **before** LF; the outer whitespace loop consumes it. `cc-skip-block-comment`, entered after `/*`, consumes through the first adjacent `*/`, or to EOF. Neither skipper nests comments.

Use exact escaped bytes `x/*a\nb*/\r\n//q\ny`, length 15. After `x` the state is position=1, line=1. The next token call proceeds:

| Completed action | Position | Line | Next byte |
|---|---:|---:|---|
| Consume `/*` | 3 | 1 | `a` |
| Consume `a`, LF, `b`, `*/` | 8 | 2 | CR |
| Consume CR then LF | 10 | 3 | `/` |
| Consume `//q` through line-comment skipper | 13 | 3 | LF |
| Outer loop consumes LF | 14 | 4 | `y` |
| Read identifier `y` | 15 | 4 | End |

The comment delimiter bytes contribute cursor movement but no tokens. The LF inside the block comment is counted by its inner reader calls; the line-comment LF is counted by the outer whitespace loop. Different callers consume them through the same `cc-next-char` operation.

An unterminated block comment in 050 is consumed to EOF without a dedicated diagnostic, after which top-level scanning reports EOF. This scanner also does not splice backslash-newline inside line comments. C05's separately gated preprocessing rules may have changed the bytes beforehand; they are not implicit extra rules in these skippers. Lexical progress is narrower evidence than source validity.

## Numbers preserve both a value and a spelling

The accumulation rule is the same for three bases:

```text
next value = old value * base + next digit's value
```

`cc-hex-digit?` recognizes `0–9`, `a–f`, `A–F`; `cc-hex-digit-val` converts a known valid digit to 0–15. It is not an independent validator. `cc-octal-digit?` recognizes `0–7`. Its subtraction-and-unsigned-division formulation uses the same byte-classifier contract as C02; it is not a signed general-number test.

Here is the actual decimal loop:

```forth
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
```

[Source: classifiers and number scanning](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L233-L341).

The hex and octal loops, `cc-lex-number-hex` and `cc-lex-number-oct`, use 16 or 8 and their corresponding classifier. Their callers have already consumed `0x`/`0X` or the leading octal zero. `cc-lex-number` chooses hex for `0x`/`0X`, octal for zero followed by **any decimal digit**, and decimal otherwise. A standalone zero therefore uses the decimal loop.

Starting at each shown spelling, derive:

| Spelling | Selected path | Accumulator transitions | Final value; span length |
|---|---|---|---|
| `129` | Decimal | 0 → 1 → 12 → 129 | 129; 3 |
| `0x81U` | Hex after prefix | 0 → 8 → 129 | 129; 5 |
| `0201L` | Octal after leading zero | 0 → 2 → 16 → 129 | 129; 5 |

After accumulation, the wrapper consumes any run of `u`, `U`, `l`, or `L`. It does not validate suffix order or repetition. The saved start precedes the prefix; the final span ends after the suffix. Thus later type classification can distinguish spellings with the same bits. The base-specific helpers set kind/value; the outer wrapper supplies the complete spelling span.

`tok-num` is a 64-bit cell pattern in either target, not an already chosen C integer type. There is no explicit overflow diagnostic in these loops; multiplication/addition retain the cell-width result. A leading minus is a separate punctuation token. Type selection and unary negation are not hidden jobs of this scanner.

Boundary predictions should follow the loops rather than a language handbook:

- `09` becomes a zero-valued token spelled `0`, then a nine-valued token spelled `9`: octal selection occurs, but octal accumulation stops before 9
- `0xG` becomes zero spelled `0x`, then identifier `G`: the hex loop does not demand its first digit
- `12uuuLL` is one numeric spelling with value 12; the suffix loop accepts that sequence without classifying its validity
- In the default profile, `1.5` becomes number 1, punctuation dot, number 5; `1e3` becomes number 1 and identifier `e3`

These are lexer predictions, not promises that a later parser accepts the complete input.

### Explicit interface: the later floating-token hook

Loading [121](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L32-L52) binds `cc-lex-extra-fwd` to `cc-sysv-lex-extra`. It first skips whole `__extension__` names only when `cc-target-sysv` is true, including subsequent whitespace/comments, then calls `cc-sysv-lex-number-fwd`. Name-boundary checking prevents it from dropping the prefix of `__extension__x`. Loading does not itself enable the target.

[127](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/127-cc-binary64.fth#L25-L69) binds that numeric hook to `cc-f64-lex`. With SysV enabled it can scan a digit-starting or dot-plus-digit number-like run. A point, or the relevant exponent marker, makes it supply `tk-float` and the complete spelling span, with `tok-num=0`. With no floating marker it restores the starting cursor and returns false for the ordinary integer scanner. Under default `cc-target-sysv=0` it immediately returns false.

A separate consumer later sends a floating token's span through `cc-f64-parse-fwd`; [128 binds that decoder to `cc-f64-parse`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/128-cc-float-literal.fth#L256-L257). That is where its checked literal grammar/conversion belongs. Token recognition, decoding, type support, and arithmetic are separate interfaces. Their existence does not make 050 a complete floating-literal implementation or alter our default-profile `1.5` trace.

## Keep a string's spelling; decode a character's value

`cc-lex-string` consumes the opening double quote, saves the following address, and counts body bytes. On backslash it consumes that byte and, if available, one following byte together. An escaped double quote therefore does not close the string. It finally consumes a closing quote if one remains, and stores string kind and the body span.

For C spelling `"a\n\"b"`, the eight source bytes are double quote, `a`, backslash, `n`, backslash, double quote, `b`, double quote. The token span contains six bytes at B+1. No newline has yet been decoded; no new buffer or zero terminator has been added. Later string emission owns decoding and destination storage. Adjacent quoted strings are separate lexer calls; this routine does not concatenate them.

The loop is length-bounded but not a complete literal validator. At EOF without closure it still returns a string token for the body it reached. A final backslash contributes one body byte. A physical LF in the body is consumed and increments line; this word does not reject it. Do not replace these local facts with “all malformed literals are safely handled”: the character path has a different boundary.

### The shared decoder has an address-only contract

`cc-decode-escape ( a -- byte n )` takes the address **after** a backslash. `n` counts consumed spelling bytes after that backslash. It uses three scratch cells, `cc-esc-a`, `cc-esc-v`, and `cc-esc-n`, rather than independent records per active call.

| Following spelling | Returned value | Returned count | Rule |
|---|---:|---:|---|
| `n`, `t`, `r` | 10, 9, 13 | 1 each | Named controls |
| `a`, `b`, `f`, `v` | 7, 8, 12, 11 | 1 each | Named controls |
| `123` | 83 | 3 | Up to three octal digits |
| `400` | 0 | 3 | Octal 256 masked to its low byte |
| `x41Z` | 65 | 3 | Consume `x41`; leave nonhex Z |
| `x123Z` | 35 | 4 | Accumulate hexadecimal 291; mask with 255 |
| `q`, backslash, quote, apostrophe | That byte itself | 1 each | Fallback |

Lowercase `x` alone selects hexadecimal escape scanning. Uppercase `X` uses the fallback. With a readable nonhex byte immediately after `x`, zero digits gives value 0 and count 1; no error is raised here. Hex digit consumption has no fixed two-digit limit. Octal has a three-digit limit; `1234` consumes only `123` and leaves 4.

The numeric branches end with the same operation:

```forth
    drop  cc-esc-v @ [lit] 255 and  cc-esc-n @ exit,
```

[Source: decoder and character reader](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L387-L442).

This decoder receives no length and uses direct `c@` reads. It depends on readable backing bytes, including the byte examined to stop a numeric run. Even the octal loop fetches a byte before testing the three-digit count. It cannot, by itself, enforce a supplied source or string-span endpoint. Do not derive behavior for an escape at an inaccessible memory boundary from ordinary source peek's EOF protection.

### Character reading consumes the decoded count

`cc-lex-char` consumes apostrophe. Without backslash, it consumes one byte as the value. With backslash, it consumes that slash, calls the decoder at the resulting address, then advances the ordinary reader `n` times. It stores the value in `tok-num` and, if not at EOF, consumes one more byte as the presumed closing apostrophe.

For the fixture's `'\n'`, start at position 20, line 2:

| Step | Position | Line | Result or reason |
|---|---:|---:|---|
| Consume opening apostrophe | 21 | 2 | Next byte is backslash |
| Consume backslash | 22 | 2 | Decoder sees `n` at B+22 |
| Decode without moving source cursor | 22 | 2 | Return `(10,1)` |
| Advance once for decoded count | 23 | 2 | Consumes source `n`, not LF |
| Store value; consume closer | 24 | 2 | Character kind, number 10 |

Neither the string span cells nor keyword cell is refreshed. The source line remains two because producing byte value 10 is not consuming a source LF.

There is no actual closing-apostrophe check. For isolated `'ab'`, the reader returns value 97 for `a`, consumes `b` as the presumed closer, and leaves the final apostrophe unread at position 3. For a lone opening apostrophe at EOF, the unescaped `cc-next-char` can advance beyond length, as C02 already established. These boundaries explain why a lexical record cannot serve as proof that the original literal was well formed.

## Choose the longest supported punctuator

`cc-lex-punct` consumes the first byte, then dispatches to thirteen handlers. Each handler receives a cursor **after** its prefix; it only consumes successful continuations. All produce punctuation kind and a code in `tok-num`.

| Handler suffix in `cc-punct-…` | Multi-byte forms and exact codes |
|---|---|
| `eq`, `bang` | `==` 256 (`pt-eq-eq`); `!=` 257 (`pt-bang-eq`) |
| `lt` | `<=` 258 (`pt-le`); `<<` 265 (`pt-shl`); `<<=` 275 (`pt-shl-eq`) |
| `gt` | `>=` 259 (`pt-ge`); `>>` 266 (`pt-shr`); `>>=` 276 (`pt-shr-eq`) |
| `amp`, `pipe` | `&&` 260 (`pt-and-and`); `&=` 272 (`pt-amp-eq`); `\|\|` 261 (`pt-or-or`); `\|=` 273 (`pt-pipe-eq`) |
| `plus` | `++` 263 (`pt-plus-plus`); `+=` 267 (`pt-plus-eq`) |
| `minus` | `->` 262 (`pt-arrow`); `--` 264 (`pt-minus-minus`); `-=` 268 (`pt-minus-eq`) |
| `star`, `slash`, `percent`, `caret` | `*=` 269 (`pt-star-eq`); `/=` 270 (`pt-slash-eq`); `%=` 271 (`pt-percent-eq`); `^=` 274 (`pt-caret-eq`) |
| `dot` | `...` 277 (`pt-ellipsis`) |

Single-byte cases use their byte directly: `(` 40, `)` 41, `.` 46, `;` 59, `=` 61, `[` 91, `]` 93, for example. Codes 256–277 do not collide with any byte. [Source: codes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L25-L48) and [handlers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L451-L619).

Trace `<<=x`: the dispatcher consumes the first `<`, leaving position 1. `cc-punct-lt` sees another `<`, consumes it, then sees `=` and consumes it. Position becomes 3, kind punctuation, number 275; x remains unread. For `<<x`, its last test fails without consuming x, so the result is 265 at position 2.

Dot needs two-byte lookahead after the first dot. With `..x`, the remaining bytes are dot and x, so it reports one dot and leaves the second for the next call. With `...x`, both remaining dots match, producing 277 at position 3. With four dots, the result is ellipsis then dot.

“Longest” means longest among these supported forms, not arbitrary C punctuation rules. `+++` becomes `++` then `+`; `/=` survives the earlier comment check; `//` does not reach slash punctuation at all. The dispatch fallback also accepts an otherwise unclaimed byte as single-byte punctuation, rather than validating a whitelist. No source span is recorded for punctuation.

## Put back a token without putting back its bytes

A parser may read `[` to decide what follows `w`, then want its next operation to consume that bracket. The one-token mechanism is:

```forth
: cc-next-token-keep
  cc-tok-pending @ if,
    [lit] 0 cc-tok-pending !
  else,
    cc-next-token
  then, ;

: cc-putback-token
  true cc-tok-pending ! ;
```

[Source: pending-token interface](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L648-L664).

Return to the fixture immediately after `[`: position=6, line=1, kind=5, number=91, pending=0. Putback changes only pending to −1. Calling `cc-next-token-keep` clears it to zero and returns the same record at position 6. Calling keep again skips the space and reads 4, reaching position 8.

No byte cursor moved backward. Two putbacks in succession still set the same flag; they do not queue two tokens. Nor is there a saved copy of the current record. If a client overwrites the token or calls raw `cc-next-token` while pending, the old token is not protected. Raw next ignores the flag and does not clear it. A later keep can consequently replay the newly written record instead of the intended one. Use the wrapper consistently when relying on putback.

**Pause point:** save the bracket state with pending=−1. On returning, predict two keep calls before reopening the paragraph. If your first prediction advances the byte cursor, draw a separate column for token replay and byte reading.

## A mark restores eight cells, not the whole compiler

Further lookahead needs a snapshot. `cc-lex-mark ( buf -- )` saves the block; `cc-lex-reset ( buf -- )` restores it:

```forth
: cc-lex-copy
  cc-lex-state-size
  begin, dup while,
    [lit] 8 -
    >r  over r@ + @  over r@ + !  r>
  repeat,
  drop 2drop ;

: cc-lex-mark   cc-lex-state swap cc-lex-copy ;
: cc-lex-reset  cc-lex-state cc-lex-copy ;
```

[Source: copying and mark storage](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L666-L689).

Starting with source and destination addresses, the copy loop subtracts eight before each transfer. It therefore copies offsets 56, 48, 40, 32, 24, 16, 8, 0. Every cell is copied, including stale payloads and pending. Supply valid 64-byte storage with an independent lifetime; this is not a size-checked buffer API or a general overlap-safe byte mover.

Mark our fixture after its first semicolon. The whole block, in offset order, is:

```text
[position=11, line=1, kind=5, num=59,
 str-address=B+7, str-length=1, keyword-id=0, pending=0]
```

The span and keyword ID are stale but their actual values are known from earlier tokens. Save that block into M. Read ahead through `putchar`, `(`, and `'\n'`; the current state becomes:

```text
[position=24, line=2, kind=4, num=10,
 str-address=B+12, str-length=7, keyword-id=0, pending=0]
```

Reset M. Position is again 11, line 1, semicolon kind/number restored, old numeric-spelling span restored, pending zero. The next keep consumes the real LF again and returns `putchar` at position 19, line 2. Reset restores the previous **current** token; it does not automatically make that token pending. If the saved flag had been −1, the first keep after reset would instead replay the saved semicolon without advancing.

What makes this reversible is the limited work performed between mark and reset. The source bytes and their ownership remain stable, and token reads have not committed unrelated compiler effects. The block does **not** contain:

- Source base, length, capacity, or a copy of the source bytes
- Arena pointer, allocated records, emitted output, symbols, or string-pool contents
- Profile flags, deferred bindings, escape-decoder scratch, or later hook scratch
- Another caller's saved mark

The escape scratch is overwritten when needed; reset does not restore it. A future hook with persistent external effects would need its own reversal contract. Calling a parser that emits code or allocates records during speculative scanning is not undone by restoring these eight cells. C05's borrowed evaluator therefore saved source length separately in addition to its lexer mark.

The file reserves one 64-byte `cc-peek-mark` for lookahead patterns that do not overlap. A second mark into that same buffer replaces the first snapshot. Nested lookahead requires separate live storage or a deliberately saved outer snapshot; a pointer to the shared buffer is not an independent mark. Even separate marks preserve only addresses into source storage. Switching workspaces or overwriting the source between mark and reset breaks the source-lifetime premise.

## Practice: predict, diagnose, then change the case

Use paper states; no build, source edit, or execution is required. [Graduated hints and complete checked solutions](../practice/06-solutions.md) include meaningful changed cases. The ID tables may stay open: the reasoning target is state and ownership, not recall of numbers.

1. **C6-01 — Grant meaning by kind.** For the 26-byte `tri.c` fixture, give position, line, kind, and valid payload after `int`, `w`, `[`, `4`, `'\n'`, and EOF. At EOF give the actual retained number, span, and keyword ID. Explain why those bits are not EOF information and why the character value does not change line.
2. **C6-02 — Separate comment and line boundaries.** For the 15-byte comment fixture, trace the second token from the state after x. Identify who consumes each LF. Then replace the final y with an unterminated `/*z`: what token follows x, and what are final position and line? Contrast a standalone `/=`.
3. **C6-03 — Keep spelling and value together.** Starting afresh for each input `129`, `0x81U`, `0201L`, `09`, `0xG`, and `12uuuLL`, give the complete token sequence with numeric values and numeric spelling spans. Show the three accumulation routes to 129. Under the default profile, also classify `1.5` and explain which named interface would be needed to change that result.
4. **C6-04 — Distinguish decoding from scanning.** Compare C spellings `"a\n\"b"` and `'\x123'`: list source bytes, token payload, endpoint, and line effect from line 1. Explain the result of address-only decoding for `1234`, `xZ`, and `X41` with readable backing bytes. Diagnose what `'ab'` does and why a decoder without a length cannot establish safe EOF behavior.
5. **C6-05 — Trace longest supported prefixes.** Scan separate spans `<<=x`, `..x`, `....`, `+++`, `/=`, and `&&=`. Give token codes and cursor endpoints; include identifier x where present. Explain why dot lookahead must not consume a second dot before confirming a third.
6. **C6-06 — Diagnose a replay error.** After `[` in the main fixture, call putback twice, keep, then keep. Record every cursor/pending/token transition. Restart at the original bracket, put it back, call raw next, then keep. What is replayed, and why? Propose a client-side discipline using the existing interface, without changing compiler code.
7. **C6-07 — Bound rollback.** Mark the first semicolon into M, read through `'\n'`, then reset M. Give all eight restored cells and the next keep result. Repeat with a saved pending flag of −1. Explain separately the effects of overwriting the source bytes, changing source length, allocating a record, and taking a second mark into M before reset.

### Changed cases: keep the answers closed

After reviewing an exercise, use its matching prompt here without opening the solution. Each starts with fresh source storage, position zero, line one, and pending zero unless stated otherwise. The checked answers remain under **Changed case** in the matching [practice section](../practice/06-solutions.md).

1. **After C6-01:** Scan C spelling `"\n"`, then scan a separate three-byte span containing double quote, actual LF, double quote. Compare kind, valid payload, endpoint, and line. Which source bytes determine the difference?
2. **After C6-02:** Scan `x/*a/*b*/c*/y`. Give every token and its cursor endpoint. Which adjacent bytes close the comment, and does the inner-looking opener change that decision?
3. **After C6-03:** Scan `0XAfll+7`, showing the accumulation and full numeric spelling. Then scan `0b11`. Determine the second input's token boundaries from the available base-selection rules.
4. **After C6-04:** Scan C character spelling `'\400'`. Separately scan the unterminated three-byte string source double quote, a, backslash, then EOF. Give each token's valid payload, endpoint, and line, and distinguish what scanning establishes from what later decoding would require.
5. **After C6-05:** Scan `>>==` and `/==` as separate spans. Give each token code and endpoint. Explain why choosing a later-looking operator cannot change an earlier token's boundary.
6. **After C6-06:** Start after EOF has been read in the 26-byte main fixture, with pending zero. Put EOF back, then call keep twice. Track position, line, pending, and the operation responsible for each result. If the source owner validly changed the region between calls, which path would inspect that changed reader state?
7. **After C6-07:** Use independent, live 64-byte buffers M and N. Save the main fixture's first-semicolon state in M, read `putchar`, and save that state in N. Read through `'\n'`, reset N, and call keep. Then reset M and call keep. Predict both returned tokens and cursor/line states. What ownership assumption do both marks still share?

If an answer goes wrong, choose the smallest repair: replay the cursor rule, consult kind validity, count bytes, or distinguish owned storage from a saved address. Then close the matching solution and try its changed case. After intervening work, reconstruct the mark example from the two source lines. These are opportunities to assess reasoning, not evidence that reading alone establishes retention or transfer.

## What this chapter established

The lexer presents one classified record over borrowed source bytes. Kind determines which payload cells can be used. Numbers preserve spelling as well as cell bits; strings preserve escaped bodies; characters decode immediately. Separator and punctuation rules determine exactly how far the byte cursor moves. Putback replays the current record once; mark/reset restores eight cells under a stable-source, limited-side-effect contract.

The next dependency is meaning: associating names and types with compiler records. Carry the span-lifetime rule forward. A table that retains a source address relies on the same owner that made token lookahead safe.

### Source-scope and evidence ledger

This ledger covers all **39 colon definitions** in 050 without requiring every repeated punctuation wrapper on the main path. Non-colon constants, table bytes, deferred entries, scratch cells, and mark storage are included in their corresponding rows.

| Definitions/group | Count | Teaching home and boundary |
|---|---:|---|
| `kw,`, `cc-check-keyword`, `cc-lex-ident-or-kw` | 3 | Packed table, all 34 IDs, borrowed names, exact matching |
| `cc-peek-char-2` | 1 | Bounded two-byte peek; shared number/comment/dot uses |
| `cc-skip-line-comment`, `cc-skip-block-comment`, `cc-cspace?`, `cc-skip-ws-and-comments` | 4 | Six whitespace bytes, comment endpoints, line trace |
| `cc-hex-digit?`, `cc-octal-digit?`, `cc-hex-digit-val`, three base readers, `cc-lex-number` | 7 | Classifiers, accumulation, prefix/suffix and spelling ownership |
| `cc-lex-string`, `cc-decode-escape`, `cc-lex-char` | 3 | Borrowed versus decoded payload, decoder scratch, missing-boundary checks |
| Thirteen `cc-punct-…` handlers and `cc-lex-punct` | 14 | All 22 multi-byte codes, single-byte fallback, prefix traces |
| `cc-lex-extra-default`, `cc-next-token` | 2 | Dispatch and explicit 121→127 hook / 128 decoder interfaces |
| `cc-next-token-keep`, `cc-putback-token`, `cc-lex-copy`, `cc-lex-mark`, `cc-lex-reset` | 5 | Replay, eight-cell snapshot, shared mark and lifetime limits |

The [historical lexer chapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/23-the-lexer.md) is comparison material. Its older counts and whole-input execution claims are not substituted for the inspected eight-kind/34-keyword source or promoted to fresh observations. In particular, preprocessing performs macro expansion; tokenization consumes its result. No tests, compiler builds, or C/Forth examples were run for this chapter, and real-reader learnability remains untested.
