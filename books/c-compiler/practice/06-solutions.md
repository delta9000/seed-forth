# C06 practice: hints, worked solutions, and changed cases

[Return to Tokens and reversible lookahead](../chapters/06-tokens-and-lookahead.md)

These are checked paper derivations against the pinned [050 lexer](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/050-cc-lex.fth), [020 state block](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/020-cc-arena.fth#L12-L28), and [030 reader](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/030-cc-io.fth#L86-L105), not executions. Use the default legacy profile, with `cc-target-sysv=0`, unless the question changes it. Positions count bytes from B, endpoints exclude the following byte, and post-state is shown throughout. Storage remains live unless a question deliberately breaks that premise.

Try a prediction and its reason before revealing a solution. Hints are optional: the first locates the mechanism, the second identifies the boundary, and the third supplies a partial transition. After checking, close the solution for the changed case. Accurate work with help is useful supported performance; it does not by itself establish independent recall or transfer.

## C6-01 — Grant meaning by kind

### Hints

1. Keep the five token cells separate from cursor and line. A new token does not clear all five.
2. Only consuming an actual LF in the source increments the line. A numeric payload equal to 10 does not do so.
3. After `int`, position=3 and the span is `(B,3)`. The next call consumes the space before reading `w`.

### Worked solution

The fixture has 26 bytes, one LF at offset 11, and no trailing LF.

| Token | Position | Line | Kind value | Valid payload |
|---|---:|---:|---:|---|
| `int` | 3 | 1 | 6 | Keyword 0; `(B,3)` |
| `w` | 5 | 1 | 1 | `(B+4,1)` |
| `[` | 6 | 1 | 5 | Number cell 91 |
| `4` | 8 | 1 | 2 | Number cell 4; `(B+7,1)` |
| `'\n'` | 24 | 2 | 4 | Number cell 10 |
| EOF | 26 | 2 | 0 | No payload |

The omitted intermediate calls still matter: `putchar` replaced the span with `(B+12,7)`, and the final semicolon replaced `tok-num` with 59. At EOF the actual retained fields are therefore number=59, address=B+12, length=7, keyword ID=0. Only kind was newly set to zero. Treating EOF's number cell as 0, or its span as empty, would invent stores absent from the definition.

The escape decoder sees source `n` and returns value 10 plus count 1. The reader advances over that `n`, then the closing apostrophe. Neither is LF. Line 2 came from consuming the physical LF between the two statements.

A correct solution identifies both kinds of fact: what the bits happen to be and what a consumer may interpret for this kind. A stale value is not necessarily unknown; here its history is known, but it is still invalid as current-token information.

### Changed case

Start a fresh span at line 1 containing C spelling `"\n"`. Its four source bytes are double quote, backslash, `n`, double quote. The result is `tk-str`, span `(B+1,2)`, position=4, line=1. No decoder runs during this string scan, so there is no valid number payload of 10.

Now replace the middle two bytes with one actual LF. The three-byte source is double quote, LF, double quote. This string reader returns `tk-str`, span `(B+1,1)`, position=3, line=2. It does not reject the physical LF. The changed source representation, rather than an intended eventual string value, determines cursor and line behavior. Later decoding or parsing may impose other requirements; those are separate claims.

## C6-02 — Separate comment and line boundaries

### Hints

1. Both comment helpers are entered after their two opener bytes have been consumed.
2. The line-comment helper leaves LF unread. The block-comment helper consumes its internal LF and both closer bytes.
3. After the block comment ends, position=8, line=2, and the next byte is CR.

### Worked solution

For escaped bytes `x/*a\nb*/\r\n//q\ny`, the indexes are:

```text
0 x   1 /   2 *   3 a   4 LF   5 b   6 *   7 /
8 CR  9 LF  10 /  11 /  12 q  13 LF  14 y
```

The first token x leaves position=1, line=1. The next token call consumes `/*` to position 3, then the block-comment helper consumes a, LF, b, and `*/`, ending at position 8, line 2. LF at index 4 is counted inside the block helper through `cc-next-char`.

The outer skipper consumes CR without changing line and LF at index 9 with a line increment, reaching position 10, line 3. It consumes `//`; the line-comment helper consumes q and stops at index 13. The outer skipper consumes that LF, reaching position 14, line 4. Identifier reading consumes y, so the second token is `tk-ident`, span `(B+14,1)`, position=15, line=4.

Replacing y with `/*z` gives 17 bytes. The shared prefix still reaches position 14, line 4. The outer skipper consumes the new opener, and its block helper consumes z to EOF at 17. With no further LF, line stays 4. Top-level scanning sets EOF kind. There is no intervening y token and no unterminated-comment diagnostic in this scanner. The x span survives as stale payload, because none of these comment reads refreshed it.

For an independent `/=` span, the initial skipper peeks the second byte and sees neither slash nor star. It leaves position zero. Punctuation then consumes `/` and `=`, producing code 270 at position 2, line 1. Recognizing all slash-prefixed text as comments would lose this token.

### Changed case

Use `x/*a/*b*/c*/y`, length 13, starting at line 1. After x, the skipper enters the block comment at positions 1–2. It does not track another nesting level at the inner-looking `/*`; the first `*/`, at positions 7–8, closes the comment. The next token is identifier c at offset 9, ending at 10. Then `*` is punctuation 42 ending at 11, `/` is punctuation 47 ending at 12, and y is an identifier ending at 13. Line remains 1 throughout.

If you skipped through the last slash before y, you supplied nesting behavior that this helper does not have. The repair is to track the first adjacent closer, not an imagined comment-depth stack.

## C6-03 — Keep spelling and value together

### Hints

1. Base selection and digit acceptance are separate tests. Zero followed by 9 selects octal, but 9 is not an octal digit.
2. The outer number wrapper remembers the start before consuming the prefix and finishes the span after consuming suffix letters.
3. For `0x81U`, accumulator states are 0, 8, 129; U changes the span length but not the value.

### Worked solution

Each row starts a separate span at B with position zero. All final EOF calls leave their listed endpoint unchanged.

| Input | Non-EOF tokens, values, spans, and endpoints |
|---|---|
| `129` | Number 129, `(B,3)`, endpoint 3 |
| `0x81U` | Number 129, `(B,5)`, endpoint 5 |
| `0201L` | Number 129, `(B,5)`, endpoint 5 |
| `09` | Number 0, `(B,1)`, endpoint 1; number 9, `(B+1,1)`, endpoint 2 |
| `0xG` | Number 0, `(B,2)`, endpoint 2; identifier G, `(B+2,1)`, endpoint 3 |
| `12uuuLL` | Number 12, `(B,7)`, endpoint 7 |

All number tokens have kind 2; G has kind 1. Each complete sequence ends with kind 0. The three routes to 129 are:

- Decimal: `0*10+1=1`, `1*10+2=12`, `12*10+9=129`
- Hex after consuming `0x`: `0*16+8=8`, `8*16+1=129`
- Octal after consuming the initial zero: `0*8+2=2`, `2*8+0=16`, `16*8+1=129`

For `09`, the octal reader starts with accumulator zero and cannot consume 9, so it returns zero after only the wrapper's leading zero was consumed. For `0xG`, the hex reader likewise consumes no digits. Neither loop requires at least one digit. For `12uuuLL`, the digit loop stops before the first u; the suffix loop then accepts all five letters without validating their order.

Default-profile `1.5` yields number 1 at endpoint 1, punctuation code 46 at endpoint 2, number 5 at endpoint 3, then EOF. Their respective numeric spans are `(B,1)` and `(B+2,1)`; dot does not supply a valid span.

To recognize a floating token, the top-level `cc-lex-extra-fwd` interface must have an active provider. The inspected chain is 121's `cc-sysv-lex-extra`, then 127's `cc-f64-lex` through `cc-sysv-lex-number-fwd`, gated by SysV selection. The 128 decoder is a subsequent consumer through a separate deferred entry. Merely defining `tk-float`, loading 128, or recognizing keyword `float` does not change the base dispatch.

### Changed case

Use `0XAfll+7`. The uppercase prefix selects hex; A and f contribute 10 and 15, giving `10*16+15=175`. Both l letters are consumed as suffix. The first token is number 175, span `(B,6)`, endpoint 6. Plus is punctuation 43 at endpoint 7; number 7 has span `(B+7,1)` and endpoint 8.

Now change only the prefix spelling to `0b11`. This scanner does not select a binary base. Decimal scanning consumes zero, giving value 0 and span `(B,1)`; identifier scanning then consumes `b11`, ending at 4. This is a changed recognition boundary, not an arithmetic problem with base two.

## C6-04 — Distinguish decoding from scanning

### Hints

1. A string records escaped source bytes. A character records a decoded byte-sized value.
2. Decoder count excludes backslash but includes the initial x in a hexadecimal escape.
3. For x123, the accumulated value is hexadecimal 123 = decimal 291; keeping its low byte produces 35.

### Worked solution

C spelling `"a\n\"b"` has these source bytes:

```text
0 double quote   1 a   2 backslash   3 n
4 backslash      5 double quote    6 b   7 double quote
```

The string reader consumes each backslash with the following byte, so the double quote at 5 is part of the body. The double quote at 7 closes it. Result: kind 3, span `(B+1,6)`, endpoint 8, line 1. The body is not decoded or copied. Number and keyword cells are stale.

C spelling `'\x123'` has apostrophe at 0, backslash at 1, x at 2, digits at 3–5, and apostrophe at 6. After consuming opener and backslash, the decoder is called at B+2. It reads x123 and examines the following apostrophe as a nonhex stopper. It returns `(35,4)`. The reader advances four times to position 6, then consumes the closer to position 7. Result: kind 4, number 35, endpoint 7, line 1. No valid spelling span is newly supplied.

For the separate address-only decoder calls, assume all stopping/lookahead bytes are readable:

| Bytes starting at decoder address | Value; count | What remains outside the consumed spelling |
|---|---|---|
| `1234` | 83; 3 | The fourth digit 4 |
| `xZ` | 0; 1 | Z; no hex digit was required |
| `X41` | 88; 1 | 41; uppercase X uses fallback |

The octal loop's count limit is three. That does not mean it never fetches the fourth byte: its condition fetches before combining the digit test with `count<3`. The returned count describes consumed spelling, not every memory location inspected.

For `'ab'`, consuming the opening apostrophe reaches 1, consuming a supplies value 97 and reaches 2, then the presumed-closer step consumes b and reaches 3. The final apostrophe remains unread. The result is a character token for 97, not a two-character constant and not a validated literal. We need not invent the downstream parser's diagnosis to identify this local behavior.

A decoder taking only an address cannot compare its reads against a source-span length. EOF-safe `cc-peek-char` elsewhere does not protect its direct `c@` calls. To derive a numeric-escape result, establish readable backing storage through the required stopping byte. Without that premise, the stated interface cannot justify a safe or deterministic endpoint result.

### Changed case

Decode a character with C spelling `'\400'`. Its octal value is `4*64=256`, and masking with 255 gives zero. Decoder count is 3; total source length and endpoint are 6: opener, backslash, three digits, closer. Line remains 1.

Compare an unterminated string made from double quote, a, backslash, then EOF. The string reader remains bounded: its body span is `(B+1,2)`, kind 3, endpoint 3, line 1. It has retained the trailing backslash byte without decoding it. This result does not establish that a later decoder can safely process that body or that the full compiler accepts the input. Bounded scanning and validated decoding are different properties.

## C6-05 — Trace longest supported prefixes

### Hints

1. The dispatcher already consumed the first byte when a punctuation handler starts.
2. Dot commits two additional bytes only after both have matched; there is no two-dot token.
3. In `&&=`, ampersand selects `&&` first and leaves equals for another call.

### Worked solution

All these spans begin at position zero, line 1. Each complete sequence is followed by EOF at its last endpoint.

| Input | Tokens in order; cursor after each |
|---|---|
| `<<=x` | Punctuation 275 (`<<=`), 3; identifier x, 4 |
| `..x` | Punctuation 46 (`.`), 1; punctuation 46, 2; identifier x, 3 |
| `....` | Punctuation 277 (`...`), 3; punctuation 46, 4 |
| `+++` | Punctuation 263 (`++`), 2; punctuation 43 (`+`), 3 |
| `/=` | Punctuation 270 (`/=`), 2 |
| `&&=` | Punctuation 260 (`&&`), 2; punctuation 61 (`=`), 3 |

For `<<=x`, less-than's handler first rules out immediate equals, matches the second less-than, then matches equals. For `..x`, after the first dot the two-byte peek returns dot and x. Because the third dot is absent, neither lookahead byte is consumed. The default one-dot result uses only the first byte already consumed by dispatch.

If the dot handler consumed the second dot before checking the third, it would need a rollback operation to produce the correct one-dot token for `..x`. This implementation avoids that extra state by peeking first. Similarly, longest matching does not invent a `&&=` token; it selects the supported two-byte form and leaves the remainder.

### Changed case

Scan `>>==`: greater-than's handler consumes `>>=`, code 276 at endpoint 3; the last equals becomes code 61 at endpoint 4. It does not choose `>>` followed by `==`, even though both of those forms exist. The choice follows the longest supported prefix at the current starting position.

Then scan `/==`: the comment skipper leaves it alone; slash's handler consumes `/=`, code 270 at endpoint 2; the last equals gives 61 at endpoint 3. Recognizing equality later cannot retroactively change the first token's boundary.

## C6-06 — Diagnose a replay error

### Hints

1. Putback writes a flag; it does not allocate a token record or move source position.
2. The wrapper clears pending without scanning. Raw `cc-next-token` never consults that flag.
3. From the bracket at position 6, a genuine scan skips the space and produces number 4 at position 8.

### Worked solution

Use the original bracket state: position=6, line=1, kind=5, number=91, pending=0.

| Operation completed | Position | Pending | Current token |
|---|---:|---:|---|
| First putback | 6 | −1 | `[` |
| Second putback | 6 | −1 | `[` |
| First keep | 6 | 0 | `[` replayed |
| Second keep | 8 | 0 | Number 4 freshly scanned |

The two writes of true have the same result as one. The first keep consumes the replay opportunity, not source bytes. The second keep runs the scanner and updates number and spelling span.

Restart at the original bracket state:

| Operation completed | Position | Pending | Current token |
|---|---:|---:|---|
| Putback | 6 | −1 | `[` |
| Raw next | 8 | −1 | Number 4 |
| Keep | 8 | 0 | Number 4 replayed |

The record containing `[` was overwritten. There is no hidden bracket copy to recover. Since raw next left pending true, keep then replayed the number that happened to occupy the shared record.

A suitable client discipline is: use `cc-next-token-keep` consistently while putback is possible, put back only the current token, and do not overwrite its fields before that replay is consumed. For deeper speculative reading, use a separate valid mark under the chapter's lifetime restrictions. Replacing raw next with keep in this sequence preserves the intended bracket replay; no compiler implementation change is required.

### Changed case

At the end of the full fixture, read EOF at position 26, line 2, pending zero. Put EOF back, then call keep twice. The first keep clears pending and replays EOF at 26. The second calls the scanner, which again finds length-based EOF and writes kind zero without moving position. Both produce EOF at 26, but one is a replay and the other a fresh end check.

Matching visible results do not make the paths identical. If the source region were validly changed by its owner between those calls, the second path would inspect the new reader state while the pending replay path would not. Such a region change needs its own state/lifetime setup; putback supplies none of it.

## C6-07 — Bound rollback

### Hints

1. A mark includes stale cell contents and pending; it does not include source length or bytes.
2. Reset restores the previous current token. Whether the next keep replays it depends on the saved flag.
3. Immediately after the first semicolon, the stored span still names numeric spelling 4 at `(B+7,1)`.

### Worked solution

M holds exactly these eight cells, in byte-offset order 0 through 56:

```text
[11, 1, 5, 59, B+7, 1, 0, 0]
```

They are position, line, kind, number, address, length, keyword ID, and pending. Reading through the character changes the active block to:

```text
[24, 2, 4, 10, B+12, 7, 0, 0]
```

Reset M restores the first block, including stale span and keyword ID. The next keep sees pending zero, so it scans after the restored semicolon. It consumes the LF at 11, reads `putchar` at offsets 12–18, and leaves:

```text
[19, 2, 1, 59, B+12, 7, 0, 0]
```

Number 59 is now stale: identifier scanning does not replace it. This full-state answer checks that restoring one known record and producing another does not imply clearing all unused fields.

If pending was −1 when M was made, M's last cell is instead −1. To perform the same later scan through the character, first consume that pending semicolon replay, then keep reading. After reset, the first keep again clears pending and returns the semicolon at position 11, line 1. Only the following keep reads `putchar`.

The four proposed changes fall outside this snapshot in different ways:

- **Overwrite source bytes:** reset restores addresses and cursor but cannot recover the old text. A saved span can now name changed spelling
- **Change source length:** reset does not restore `cc-src-len`; the next EOF decision uses the changed length, so a caller borrowing another region must preserve/restore it separately
- **Allocate a record:** reset does not restore arena pointer or undo allocation, contents, or downstream references
- **Take another mark into M:** M now holds the newer snapshot. Reset restores that newer state, not the first semicolon; retaining another pointer to M changes nothing

An explanation that “everything is restored” misses the ownership boundary. A mark is comprehensive for the specified eight-cell record, not for all memory reachable from it or all work performed since it was saved.

### Changed case

Use two independent, live 64-byte buffers M and N. Save the first-semicolon state in M, read `putchar`, and save that state in N. Read through the character, then reset N. With its pending flag zero, the next keep reads `(`, ending at position 20, line 2. Reset M instead, and the next keep reads `putchar`, ending at position 19, line 2.

Both snapshots remain available because their storage is distinct. They still share source ownership: overwriting B's text can invalidate the interpretation of either. Separate mark buffers solve overlapping snapshot lifetimes, not source copying or arbitrary transactional rollback.

## A return check

After another task or reading session, close these answers and explain three transitions: why decoded newline does not move the source line, why a putback does not rewind the byte cursor, and why resetting a mark does not undo an allocation. Then choose one changed case and reconstruct its intermediate states. If a discrepancy appears, return to that specific contract. These are proposed checks of retained reasoning; no reader study or execution outcome is claimed here.
