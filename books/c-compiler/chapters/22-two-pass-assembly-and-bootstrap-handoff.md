# 22. Two-pass assembly and bootstrap handoff

[C21](21-assembler-input-and-expansion.md) left us with this exact expanded text, including one space after the final token:

```text
:top EB !end 41 00 :end 90 EB !top 
```

The definitions and quotes are gone. The names are not. What bytes should replace `!end` and `!top`, and how can the first reference work before we have reached `:end`?

We will finish that seven-byte puzzle before putting the assembler into the bootstrap chain. This input is a fragment, not an ELF executable and not a program to run. Its useful result is a byte sequence we can account for completely.

You need C21's distinction between raw and expanded text and C19's distinction between a file offset and a target address. Here is a quick recovery check: two hex characters such as `41` describe one output byte; `:end` names a position but emits no byte. If either step is uncertain, keep those two rules beside the first table. No additional shell syntax or upstream compiler internals are needed for the first session.

All new traces in this chapter are source-derived predictions, not results of running the examples. The implementation is [`130-asm.fth` at the book's pinned revision](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth). Existing remote test evidence is identified separately below.

## First find positions, without filling the fields

The assembler's **target-address counter**, `asm-ip`, is the target address of the next byte it is counting or emitting. It does not mean that the assembler is executing those bytes. The default target base is `0x600000`, so output offset 4 corresponds to target address `0x600004`. The expanded text has its own character cursor; advancing past four characters of text need not advance the target IP by four bytes.

For this fragment, the only unfamiliar token is `!name`. The exclamation mark is a **sigil**, a leading character that selects a field format. Here it reserves one byte for a relative label value. The value will be the destination address minus the address immediately after that one-byte field.

Notice the opportunity: we already know the field's width, even though we do not yet know its value. The first pass can count widths and save label positions without resolving any reference.

Starting with IP=`0x600000` and an empty label table, it reads the same tokens C21 produced:

| Token | Offset before | First-pass action | Offset after |
|---|---:|---|---:|
| `:top` | 0 | Save `top` = `0x600000` | 0 |
| `EB` | 0 | Check two hex digits; count one byte | 1 |
| `!end` | 1 | Count the sigil's one-byte field | 2 |
| `41` | 2 | Check and count one byte | 3 |
| `00` | 3 | Check and count one byte | 4 |
| `:end` | 4 | Save `end` = `0x600004` | 4 |
| `90` | 4 | Check and count one byte | 5 |
| `EB` | 5 | Check and count one byte | 6 |
| `!top` | 6 | Count one byte | 7 |

At the end, IP is `0x600007`. The table contains two names and target addresses. The assembler has not emitted seven placeholder bytes and is not maintaining a list of fields to patch. It has measured the input. The second pass will emit bytes for the first time.

This is a different solution to forward references from C10's patch lists. A patch list saves output locations for later repair. Here the input stays available, so a second walk can resolve each reference against a completed table. The tradeoff is another walk and storage for the expanded input.

Source: [`asm-do-label-decl`, first-pass reference counting, and bare-hex counting](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L403-L579).

## Rewind the reading position, keep the discoveries

To start again, `asm-reset-pos` sets the expanded-input cursor to zero. The driver resets IP to `asm-base`, clears the output position with `asm-out-init`, and selects pass 2.

It deliberately does **not** call `asm-init` again. That word resets both IP and the label count. Calling it here would discard the very discoveries the second pass needs.

| State | End of pass 1 | Start of pass 2 |
|---|---|---|
| Expanded text | Complete, unchanged | Same bytes |
| Expanded cursor | At end | Zero |
| IP | `0x600007` | `0x600000` |
| Label table | `top` and `end` recorded | Both preserved |
| Output position | Not used for sizing | Zero |
| Pass selection | 1 | 2 |

The distinction matters even for backward references. Every pass-2 lookup sees the completed first-pass table, not only declarations already revisited on the second walk. Label declarations do nothing in pass 2, so the table is not populated twice.

Sources: [`asm-reset-pos`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L83) and [the actual reset sequence in `asm-main`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L767-L781).

## Fill the forward field from its end

In pass 2, `:top` emits nothing. `EB` emits one byte. The next token, `!end`, therefore starts at output offset 1, target address `0x600001`.

Before calculating, choose the subtraction point: the opcode at offset 0, the field at offset 1, or the position at offset 2 after the field?

The reference handler uses the last one:

```text
field start       = 0x600001
field width       = 1 byte
field end         = 0x600001 + 1 = 0x600002
destination end   = 0x600004
relative value    = 0x600004 − 0x600002 = 2
emitted field     = 02
```

This is the same next-instruction coordinate used for C19's CALL displacement. For the x86 short-jump encoding here, the byte following `EB` is the displacement and execution would add it after consuming the whole instruction. Subtracting the opcode address would give 4; subtracting the field's first address would give 3. Neither accounts for the point from which the machine applies the displacement.

The assembler does not decode `EB` to discover that rule. Its `!` label-reference path uses field-end arithmetic. The author or the compiler producing the assembly must choose a field form appropriate for the instruction.

The second walk now emits `41`, `00`, `90`, and the next `EB`. It reaches `!top` at offset 6:

```text
field start       = 0x600006
field end         = 0x600007
destination top   = 0x600000
relative value    = 0x600000 − 0x600007 = −7
low byte of −7    = 256 − 7 = 249 = F9
```

The one-byte label-displacement range is −128 through 127, so −7 fits. The emitter stores its low byte, `F9`. This is a representation of a negative displacement, not a request to emit 249 extra bytes.

The complete derived result is:

```text
offset:  0  1  2  3  4  5  6
byte:   EB 02 41 00 90 EB F9
```

Seven described bytes have become seven predicted output bytes. No ELF header has appeared. `130` emits what the input describes; it does not surround arbitrary input with an executable envelope.

Source: [`asm-do-ref` subtracts IP plus width before emission](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L496-L517).

## Why both walks agree at each token boundary

At the start of any token, pass 1's IP is base plus the sizes of all preceding tokens. In pass 2, after successfully processing that same prefix, the output position is that size, and IP is base plus output position.

This **token-boundary invariant** is more useful than the final size alone. Each kind of token preserves it:

- A label has width zero in both passes
- A sigil contributes its fixed width in both passes, regardless of the resolved value
- A valid bare-hex token contributes half its character count in pass 1 and exactly that many bytes in pass 2

The check for whole hex pairs is part of the reason this works. `E B` cannot be treated as a single byte assembled from two tokens: each token has odd length and fails validation. Within a token, `EB90` is two pairs and contributes two bytes. C21's inserted separators keep copied tokens from accidentally merging and changing these boundaries.

The two passes must also see the same expanded bytes. Replacing a token between passes with a wider one would move later positions without updating their saved labels. Successful sizing alone does not guarantee successful emission: pass 2 can still find an undefined label, reject a value's range, or fill the output buffer. The invariant describes successfully processed prefixes; it does not promise that every input reaches the end.

## Change the string, then move the base

Return to C21's raw input and change only the direct string `"A"` to `"AB"`. Its expansion now includes `41 42 00`: one additional byte before `:end`.

Pause and predict what must move. The `top` label stays at offset 0. The `end` label moves from 4 to 5. The forward field still ends at 2, so its value becomes `5−2=3`. The final field now ends at 8, so the backward value becomes `0−8=−8`:

```text
EB 03 41 42 00 90 EB F8
```

This is not a cosmetic text change. The length of the expanded string changes two reference calculations in opposite directions. The trailing NUL remains part of the string's output width.

Now keep the original one-character string and set the base to `0x700000`. Both saved label addresses increase by `0x100000`; both field-end addresses increase by the same amount. Subtraction cancels that common change, so the original seven bytes stay the same. An absolute-address field would change instead. We will use that distinction when filling the ELF entry field.

**Stop/resume point.** Keep three offsets: `top=0`, `end=4`, final end=7. On returning, reconstruct `4−2` and `0−7`, then explain why rewinding must preserve the labels. If your arithmetic works but the chosen subtraction point does not, redraw only the opcode, field, and position after the field. If this is secure, attempt C22-01 before opening its feedback.

## Choose a second session

The fragment's two unknown bytes are resolved. Choose a question to carry into the remaining source:

- **What else can a field mean?** Read the sigil and little-endian sessions, then try C22-02 through C22-04
- **What must survive between passes?** Read labels, the driver, and output failures, then try C22-05 through C22-08
- **How do bytes become the next tool?** Follow the supplied header and source-built handoff, then try C22-09 through C22-11

The first two routes open the rest of the bounded assembler implementation. The last route connects it to C20's producers without claiming to teach the upstream programs themselves.

## Reference: six sigils, three meanings

A sigil tells the handler a width and a rule for label references. A numeric body takes a different route: it is an immediate value, even when that sigil's label form is relative.

| Sigil | Width in bytes | Label-body meaning |
|---|---:|---|
| `!` | 1 | target minus this field's end |
| `@` | 2 | target minus this field's end |
| `~` | 3 | target minus this field's end |
| `%` | 4 | target minus this field's end; also supports `%target>base` |
| `$` | 2 | target address itself |
| `&` | 4 | target address itself |

For example, `%60` supplies decimal 60, not “the address 60 minus our position.” Wider fields use **little-endian** order: the byte holding the lowest eight bits comes first. Its four bytes are `3C 00 00 00`. Conversely, `%end` must look up the label and subtract the field end. C21's expanded stream can retain both tokens: expansion has not already lowered all numeric forms into bare hex, unlike the reference M1-to-hex2 route.

The shared handler, `asm-do-ref`, receives `( width relative? undefined-code -- )`. Its pass-1 branch discards the latter two arguments and adds width to IP. In pass 2 it uses C21's `asm-tok-numeric?`: a body beginning with a decimal digit or `-` selects numeric parsing. Otherwise `asm-ref-name` returns the slice after the sigil for label lookup. This is classification by first character, not a full validation of a number or a general expression grammar. C21 explains the parser's valid-input contract and malformed-number limits.

The numeric branch obtains the number, applies numeric bounds, and emits it. The label branch looks up the address, optionally subtracts `IP+width`, and applies label bounds. The dispatcher supplies a different undefined-name code for each sigil. Both successful branches emit the chosen width and advance IP by that same width.

### An explicit base names the subtraction point

`%target>base` means the difference of two label addresses. The word *base* in this syntax names a label, not necessarily the global variable `asm-base`.

For a nonnumeric `%` token in pass 2, `asm-do-pct-ref` asks `asm-find-gt` to locate the first `>` after the sigil. The scanner uses `asm-scan-i` to walk the token and stores in `asm-gt-pos` the length of the target name. A value of −1 means no separator, so the ordinary four-byte relative handler is used. When there is a separator, the handler looks up the left name, then the right name, subtracts right address from left address, and emits four bytes. Field IP is not part of this subtraction.

Follow all six widths in one small fragment. Like the first packet, this is not an ELF:

```text
:a !-1 @0x1234 ~a $258 &a %end>a :end
```

At base `0x600000`, `a` is at offset 0 and `end` is at offset 16:

| Token | Offset / width | Value used | Predicted bytes |
|---|---|---|---|
| `!-1` | 0 / 1 | Numeric −1 | `FF` |
| `@0x1234` | 1 / 2 | Numeric `0x1234` | `34 12` |
| `~a` | 3 / 3 | `0−(3+3)=−6` | `FA FF FF` |
| `$258` | 6 / 2 | Decimal 258 = `0x102` | `02 01` |
| `&a` | 8 / 4 | Absolute `0x600000` | `00 00 60 00` |
| `%end>a` | 12 / 4 | `16−0=16` | `10 00 00 00` |

Changing the last reference to `%end` would use `16−(12+4)=0`. Changing `$258` to `$a` would fail: the absolute address `0x600000` is too large for this two-byte label field. Both changed inputs still have the same first-pass size. Knowing where everything goes is different from knowing that every requested value is accepted.

Sources: [reference handlers and explicit-base scanner](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L376-L541) and [first-character dispatch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L584-L594).

### Accepted values are not quite the usual field ranges

The implementation deliberately has different bounds for labels and numbers. Keep both columns when predicting a result:

| Sigil | Accepted label-derived value | Accepted numeric value |
|---|---|---|
| `!` | −128 through 127 | −129 through 256 |
| `@` | −32768 through 32767 | −32769 through 32768 |
| `~` | −8388608 through 8388607 | −8388609 through 8388608 |
| `$` | 0 through 65535 | −32769 through 65536 |
| `%`, `&` | No width-4 fit check | No width-4 fit check |

These inclusive limits describe this source, not a proposed general rule for assemblers. For a checked width, `asm-half` builds `128 × 256^(width−1)`. `asm-label-bounds` puts the signed relative range or unsigned absolute range into `asm-fit-lo` and `asm-fit-hi`. `asm-number-bounds` puts the unusual numeric limits there instead. `asm-fit` compares the value with those variables only when width is less than four. `%target>base` also emits four bytes without a fit check.

A rejected label value exits through code 244; a rejected number uses 245. An accepted value is still reduced to its low output bytes. Thus `!256` is accepted but emits `00`, and `!-129` emits `7F`. `!257` is rejected. Four-byte fields can also discard high bits: for the valid number `%4294967296`, the low four bytes are zero. There is no width-four fit failure to rescue a mistaken oversized value.

For a one-byte forward reference, `EB !far` followed by N zero bytes and then `:far` has value N. For a backward reference, `:back` followed by N zero bytes and then `EB !back` has value `−(N+2)`. The two extra bytes are the opcode and its field. C22-04 asks you to derive each boundary rather than memorize two unrelated limits.

Source: [`asm-half`, both bounds constructors, and `asm-fit`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L417-L472).

## Reference: emit low bytes without changing their meaning

`asm-emit-le` receives a value and width. Each loop sends the current value to `asm-emit-byte`, whose byte store keeps its low eight bits. It then divides the value by 256 and reduces the remaining width by one. For `0x1234` at width two, the stores are `34`, then `12`. The emitter consumes both inputs when the width reaches zero.

The seed's division is unsigned. A negative value is held as a 64-bit two's-complement cell, so dividing that stored cell by 256 moves its remaining higher bytes down. For −6, the stored cell ends in `... FF FF FA`; the first three stores are consequently `FA FF FF`. The emitter neither prints a minus sign nor emits an ASCII hex string.

This separates three representations that appear on the same page: `@0x1234` is input text, `0x1234` is a cell value used during assembly, and `34 12` names the two resulting bytes. Displaying those bytes as hex is our notation, not an extra output transformation.

Sources: [`asm-emit-le`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L295-L303), [the byte append](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L124-L134), and [010's unsigned-division contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L112-L122).

## Reference: the label table borrows names and owns addresses

`asm-labels` reserves a flat array of `asm-cap=8,192` records. Each record occupies `asm-rec-size=24` bytes: three eight-byte cells.

| Cell offset in record | Stored value | Meaning |
|---:|---|---|
| 0 | Name address | Address of name bytes inside the expanded buffer |
| 8 | Name length | Number of bytes to compare |
| 16 | Target IP | Address being named in the assembled output |

The first and third cells are both addresses, but in different spaces. The first helps the running Forth assembler read text in its own memory. The third describes a position in the future output's target address space. Treating them as interchangeable would make name matching or relocation meaningless.

`asm-rec` calculates record i as `asm-labels + i×24`. `asm-count` counts occupied records. `asm-store-label` checks that count plus one fits the capacity, stores the borrowed slice and current `asm-ip`, then increments the count. `asm-do-label-decl` strips the leading colon and calls that store only in pass 1. Neither word copies the name's bytes into the record.

Borrowing is safe here because the expanded buffer remains unchanged through both passes. Resetting its cursor does not invalidate the slices. Reusing or overwriting its contents before pass 2 would invalidate the names even if the table itself remained untouched. C21's definition records borrow from raw input; these label records borrow from expanded input. The two tables need different buffers to remain alive.

`asm-find-label` saves the sought slice in `asm-find-addr` and `asm-find-len`, then searches from `asm-count−1` down to zero. It compares lengths first and uses 010's `bytes-eq` only when they match. It returns `( target-address true )` on success and `( 0 0 )` on failure. The flag matters: target address zero is a valid value when the base is zero, so zero alone cannot signify failure.

There is no duplicate-label rejection. The newest stored matching record wins. For example:

```text
:x 90 :x !x
```

Pass 1 stores `x=base` and then `x=base+1`. The `!x` field starts at offset 1 and ends at 2; newest `x` has offset 1. The predicted output is `90 FF`, since `1−2=−1`.

This is not a rule that chooses the nearest preceding declaration at each reference. A reference earlier in the text also sees the final table, including later duplicate declarations. C22-05 changes the position of the reference to expose that distinction.

Sources: [storage, append, and newest-first search](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L154-L210) and [010's exact byte comparison](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L453-L469).

## Reference: the pass loop gives every token one owner

`asm-pass-loop` asks C21's `asm-read-token` for an address and length. A zero length ends the loop; otherwise `asm-process-token` saves that slice in `asm-token-start-tmp` and `asm-token-len-tmp` and dispatches on its first character. Colon selects declaration, six sigils select references, and everything else selects bare hex. There is no instruction decoder hidden in this final fallback.

In pass 1, `asm-check-hex` walks the whole bare token using `asm-hex-i`. It checks every character before checking even length. Consequently a nonhex character selects 246 even if that token also has odd length; a token containing only valid hex but an odd number of digits selects 247. `asm-do-hex` then counts length divided by two.

In pass 2, the unchanged token needs no repeated validation. `asm-do-hex` resets `asm-hex-i`, combines each pair as `16×first-digit+second-digit`, appends one byte, and advances IP by one. The first pass's whole-pair check guarantees the second character exists for every pair. The reset of the index matters because validation and emission each walk many separate tokens.

This is the concrete source behind the earlier token-boundary invariant. It also bounds it: the assembler is relying on unchanged input and its own fixed-width dispatch, not proving arbitrary transformations preserve layout.

Source: [validation, pair emission, dispatch, loop, and `asm-init`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L543-L609).

## Reference: the caller starts three walks, not two expansions

In a fresh seed process, the assembler uses `010-lib.fth` and the seed primitives; it does not load the C-compiler layers. C21 explained the buffer allocation and fresh-load premise. Loading `130-asm.fth` defines its words and initializes `asm-base` to decimal 6,291,456, or `0x600000`. It does **not** execute `asm-main` at the end of the file. This differs from C19's `120-cc-main.fth`, whose load-time call begins consuming the following C source.

The assembler's caller explicitly supplies the `asm-main` token between the Forth definitions and the assembly source. The default base can be replaced before that token is invoked. Here is the input-stream shape, not a command to run:

```text
010 definitions → 130 definitions → optional base assignment → asm-main
                                                               |
                                following assembly text is read by the driver
```

`asm-base`, `asm-ip`, and `asm-pass` keep distinct jobs: configured target origin, current target position, and which assembly walk is active.

| Driver phase | Reads | Changes | Deliberately preserves |
|---|---|---|---|
| `asm-load-stdin` | Remaining standard input | Raw buffer and source length | Configured base |
| `asm-use-src`; `asm-expand-pass` | Raw text | Definition records and expanded text | Raw text needed by borrowed definitions |
| `asm-use-exp`; `asm-init`; pass 1 | Expanded text | IP and label records; label count starts at zero | Expanded text |
| Rewind and select pass 2 | No new source | Cursor=0, IP=base, output position=0 | Complete label table and expanded text |
| Pass 2 | Same expanded text | Output bytes and IP | Label table |
| `asm-write-output`; `bye` | Output buffer | Attempts file write, then ends assembler process | No further consumer inside this driver |

There is one expansion walk and then two assembly walks. The rewind changes a position, not the representation. `asm-init` is used once for table initialization; `asm-reset-pos` is used for the narrower rewind. The pass flag routes the same token kinds to sizing or emission behavior.

Source: [default base](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L163-L174), [initialization](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L607-L609), and [driver plus caller contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L764-L785).

## Reference: a complete buffer is followed by a write attempt

`asm-out-cap` is 1,048,579 bytes. `asm-out-buf` reserves that storage; `asm-out-pos` marks the next free byte. `asm-out-init` sets the position to zero. Before each append, `asm-emit-byte` uses C21's `asm-check-cap` to check the prospective occupancy, position plus one. Exactly 1,048,579 bytes are permitted; the next append fails with 241 before its store. Likewise exactly 8,192 label records are permitted; the next store fails with 242. Pass 1 does not precheck the eventual output-buffer capacity.

`asm-out-path` holds `/tmp/asm-out` followed by NUL: 12 pathname characters plus the terminator, 13 bytes total. 010's `s,` copies the next Forth token without adding a length or terminator; the explicit zero-byte store supplies the NUL.

`asm-write-output` requests open flags 577, the sum of write-only, create, and truncate, and requested mode 493 decimal, or octal 0755. A negative open result exits with 230. Otherwise it requests one write of the completed buffer and one close. It discards both return values.

That is a narrower contract than “a zero exit means the entire executable was saved.” A short or failed write is not retried; a failed close is not reported. The requested creation mode is also subject to the process's umask, and opening an existing file does not reset its permission bits. The driver does not validate an ELF envelope or make a readback comparison.

### Failures have a phase as well as a code

`asm-tok-err` attempts to write the current token and a newline to standard error, file descriptor 2, before calling `die`. `asm-nl-byte` provides that one newline byte. These diagnostic write results are discarded too. Capacity failures call `die` directly rather than taking this token-printing route.

| Code | Trigger in this implementation |
|---|---|
| 230 | Output open returns a negative result |
| 231 | Undefined `&label` |
| 232 / 233 | Undefined explicit base / target in `%target>base`; target is checked first |
| 234 / 235 / 236 / 237 / 238 | Undefined `%label` / `!label` / `@label` / `~label` / `$label` |
| 239 / 240 | Raw-input / expanded-buffer capacity failure, from C21 |
| 241 / 242 / 243 | Output-byte / label-record / definition-record capacity failure |
| 244 / 245 | Checked label / numeric value is outside its selected bounds |
| 246 / 247 | Bare token contains nonhex / contains only hex but has odd length |

There are no 248 or 249 failure sites in this pinned file. Nor is this table a promise to detect every malformed input: the numeric and quote parser limits from C21 still apply. Loading also stops on a nonpositive read result, without distinguishing ordinary end-of-file from a negative read error.

An undefined reference or range failure in pass 2 occurs before the output file is opened, even if some bytes have already been assembled in memory. An old `/tmp/asm-out` can therefore remain from a previous run. Checking that a file exists is insufficient unless the caller also rules out stale output. The fixture recipes remove it before invocation; the bootstrap wrapper removes its selected fixed path too.

Sources: [output buffer and writer](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L121-L152), [token diagnostic](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L411-L415), [path data](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/130-asm.fth#L764-L765), [010's byte-copy and `s,`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L441-L451), and [syscall wrappers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L47-L69).

## Reference: supply 120 header bytes, then assemble a 148-byte fixture

The seven-byte fragment established the assembler's work without borrowing credibility from an executable wrapper. Now supply the actual wrapper used by a small fixture.

The input order in [`m1-jump42-check.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/m1-jump42-check.sh#L40-L46) is:

```text
amd64_defs.M1 → ELF-amd64.hex2 → m1-jump42.M1
```

These are assembly inputs after the Forth prelude and explicit `asm-main` call. The definitions emit no target bytes. The header is not a feature switched on inside `130`; it is another input file whose hex and symbolic fields describe 120 bytes. The fixture then supplies `_start`, instructions, and `ELF_end`.

This small recipe uses the mescc-tools checkout's M2libc, pinned at `5a7c12a7be39cbce113c5459d77467b829a1ecc5`. Its [definitions](https://github.com/oriansj/M2libc/blob/5a7c12a7be39cbce113c5459d77467b829a1ecc5/amd64/amd64_defs.M1) provide `mov_rax,` → `48C7C0`, `mov_rdi,` → `48C7C7`, `jmp` → `E9`, and `syscall` → `0F05`. The comma belongs to each named token.

Here is an accounting of the [supplied header](https://github.com/oriansj/M2libc/blob/5a7c12a7be39cbce113c5459d77467b829a1ecc5/amd64/ELF-amd64.hex2#L30-L74). All offsets are output-byte offsets, starting at `:ELF_base`. A symbolic four-byte field followed by four explicit zero bytes fills an eight-byte ELF field.

| Offset | Width | Supplied content or field |
|---:|---:|---|
| 0 | 16 | `7F 45 4C 46 02 01 01 03`, then eight zero bytes: identification |
| 16 | 8 | `02 00 3E 00 01 00 00 00`: executable type, AMD64, version |
| 24 | 8 | `&_start`, then four zeros: entry address |
| 32 | 8 | `%ELF_program_headers>ELF_base`, then four zeros: program-header offset |
| 40 | 8 | All zeros: no section-header table |
| 48 | 4 | All zeros: flags |
| 52 | 6 | `40 00 38 00 01 00`: header size 64, program-header entry size 56, count 1 |
| 58 | 6 | All zeros: section-header size, count, and name-table index |
| 64 | 8 | `01 00 00 00 07 00 00 00`: loadable segment, read/write/execute flags |
| 72 | 8 | All zeros: segment file offset |
| 80 | 8 | `&ELF_base`, then four zeros: virtual address |
| 88 | 8 | `&ELF_base`, then four zeros: physical-address field |
| 96 | 8 | `%ELF_end>ELF_base`, then four zeros: file size |
| 104 | 8 | `%ELF_end>ELF_base`, then four zeros: memory size |
| 112 | 8 | `01 00 00 00 00 00 00 00`: alignment |

The first 64 bytes are the ELF header; the next 56 form one program-header entry. Their sum is 120. The label `ELF_program_headers` is therefore at offset 64, and `ELF_text` at offset 120. The source also declares `ELF_program_header__text` at 64; two different names may name the same position.

Now append the actual [fixture body](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/m1-jump42.M1#L5-L13). The table shows its text after definitions have been made available, together with the derived byte contribution:

| Fixture text | Offset before | Width | Predicted bytes |
|---|---:|---:|---|
| `:_start` | 120 | 0 | Entry label only |
| `mov_rax, %60` | 120 | 7 | `48 C7 C0 3C 00 00 00` |
| `mov_rdi, %42` | 127 | 7 | `48 C7 C7 2A 00 00 00` |
| `jmp %skip` | 134 | 5 | `E9 07 00 00 00` |
| `mov_rdi, %99` | 139 | 7 | `48 C7 C7 63 00 00 00` |
| `:skip syscall` | 146 | 2 | `0F 05` |
| `:ELF_end` | 148 | 0 | End label only |

The branch's four-byte field begins at 135 and ends at 139. `skip` is at 146, so its value is `146−139=7`. It uses the same rule as the seven-byte fragment; only the field width changed.

Pass 1 also gives the previously unresolved header fields their targets. At the default base:

- `_start = 0x600000+120 = 0x600078`, so entry's low four bytes are `78 00 60 00`
- `ELF_program_headers−ELF_base = 64`, so the program-header-offset field begins `40 00 00 00`
- `ELF_end−ELF_base = 148 = 0x94`, so both size fields begin `94 00 00 00`
- `&ELF_base` emits `00 00 60 00` in each address field

Each is followed by the header's explicit four zero bytes. We have accounted for all 148 output bytes, including the envelope. Moving the configured base changes the absolute-address fields but leaves the two size differences and branch displacement unchanged, provided the resulting addresses remain representable by the supplied layout.

Under the x86-64/Linux execution contract used in C19, the body sets the exit syscall number to 60, sets its argument to 42, jumps over the assignment of 99, and reaches `syscall`. The predicted exit status is 42. The recipe checks that behavior separately from exact ELF-byte equality. A size derivation, an equality check, and a process exit are three different kinds of evidence.

The adjacent fixtures illustrate the distinction. `exit42` contributes 16 body bytes for total 136. The short-jump `jump42` contributes 25 for total 145. This long-jump fixture contributes 28 for total 148. All three can exit 42 without being byte-identical to one another.

## Reference: the assembled program becomes the next assembler

[C20](20-complete-compiler-and-stage-a.md) ended with M2-Planet producing assembly text. Text cannot yet serve as an executable tool. We now know the missing transformation well enough to follow one source-built handoff.

The filenames here belong to [`bootstrap.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh), not to a new run of the small fixtures. Read this as the inspected recipe. No bootstrap was run for this chapter.

### First let the Forth assembler make a compiler executable

The bootstrap's `cc-out-v1` is the Forth-compiled M2-Planet program. Running it on the pinned M2-Planet source produces `self-v1-amd64.M1`. The helper `forth_asm` passes this text through `130`, with definitions, an ELF header, and the startup/runtime input `libc-full.M1`. The saved result is `cc-out-v2-fasm`, another executable M2-Planet.

The root checkout pins [M2-Planet at `0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb`](https://github.com/oriansj/M2-Planet/tree/0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb) and [mescc-tools at `9b1375115f9175d876c360dbbfd7e231dd9f2a2f`](https://github.com/oriansj/mescc-tools/tree/9b1375115f9175d876c360dbbfd7e231dd9f2a2f). Their nested M2libc pins supply different assembly-input profiles:

| Input profile | M2libc commit | Definition table | Startup input |
|---|---|---:|---|
| Small fixtures, mescc-tools subtree | `5a7c12a7be39cbce113c5459d77467b829a1ecc5` | 156 `DEFINE` entries | Fixture supplies its own `_start` |
| Bootstrap/self-compile, M2-Planet subtree | `eee5091e7a1af90b7b87389153647be9a24a8cdd` | 314 `DEFINE` entries | `libc-full.M1` precedes program M1 |

The two pinned header files have the same Git blob, `32ccc7c7d43ba28041a34d10bbb2f7836ac575a9`. The definition tables do not: the small table's blob is `3dddb1b71df189c3a1ad821c8ebff61dfb50fb04`; the large table's is `90d39789e3e1770f92838abab42895b2637cbfab`. Matching header bytes do not make the two complete input profiles interchangeable.

The larger [`libc-full.M1`](https://github.com/oriansj/M2libc/blob/eee5091e7a1af90b7b87389153647be9a24a8cdd/amd64/libc-full.M1#L17-L59) supplies `_start`, runtime setup calls, a call to the program, and an exit path. We use those supplied interfaces here; this chapter does not open the full upstream runtime implementation. The [larger definitions](https://github.com/oriansj/M2libc/blob/eee5091e7a1af90b7b87389153647be9a24a8cdd/amd64/amd64_defs.M1) and [header](https://github.com/oriansj/M2libc/blob/eee5091e7a1af90b7b87389153647be9a24a8cdd/amd64/ELF-amd64.hex2) are pinned separately from their small-fixture counterparts.

Source: [`forth_asm` input order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L131-L141) and [step 3](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L213-L219).

### Use that compiler to describe M1, then turn the description into M1

Follow the M1 tool first. The new compiler `cc-out-v2-fasm` receives these ordered C inputs from the pinned mescc-tools checkout:

```text
M2libc/bootstrappable.c → stringify.c → M1-macro.c
```

With `--architecture amd64 --expand-includes`, it produces `WORK/M1.M1`. `WORK` names the recipe's intermediate directory; it is not part of the tool's name. Despite the repeated `M1`, this file is text describing the M1 program, not an executable copy of it.

The Forth assembler now consumes that text with the larger companion inputs just described. The result is `OUT/M1`, an executable that can perform the M1 text transformation. `OUT` is the recipe's retained-output directory.

The companion `hex2` tool follows the same construction with its own ordered source list:

```text
M2libc/bootstrappable.c → hex2_linker.c → hex2_word.c → hex2.c
```

Its text artifact is `WORK/hex2.M1`; Forth assembly produces `OUT/hex2`. Together the two new executable tools can replace the text-to-byte role `130` has been serving.

```text
cc-out-v2-fasm + M1 C sources
                |
                v
          WORK/M1.M1 text
                |
       130 + companion inputs
                |
                v
           OUT/M1 executable
```

Text equivalent: M2-Planet compiles the M1 implementation into assembly text; the Forth assembler then turns that text into the executable M1 tool. A parallel construction makes hex2. There is no attempt to execute either `.M1` text file.

Sources: [compile helper and exact source vectors](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L166-L176) and [step 4's compilation and assembly calls](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L222-L228).

### Compare the old and new routes on the same text

The first handoff check does not change the M2-Planet text. It returns to `self-v1-amd64.M1`, the very file already assembled into `cc-out-v2-fasm`.

This time, `OUT/M1` reads the definitions, startup input, and program M1, producing reference-style hex2 text. `OUT/hex2` receives the supplied ELF header followed by that text, with AMD64, little-endian, and base `0x00600000` selected. The saved output is `cc-out-v2`.

The required comparison is:

```sh
cmp "$OUT/cc-out-v2" "$OUT/cc-out-v2-fasm"
```

C20 introduced `cmp`: it compares exact bytes, with no semantic normalization. Here both operands are ELFs assembled from the same M1 program and fixed companion inputs. Success establishes agreement between these two assembly routes for this input. It is neither a comparison with a GCC-compiled M2-Planet executable nor a comparison of two generations of M1 text.

If that required comparison succeeds, the source-built tools have replaced the assembly step and matched the Forth route's exact output for this input. That is the concrete handoff. The recipe uses no host C compiler, assembler, or linker in this construction, but still relies on its declared seed, pinned source inputs, shell, filesystem utilities, and operating system. The C-source-built M2-Planet programs are themselves compilers; “no host compiler in this route” must not become “no compiler was involved.” Equality does not prove that those sources or trusted components are benign.

Sources: [`m1_hex2` helper](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L143-L154), [step 5's exact comparison](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L231-L236), and [declared trust boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L6-L26).

### Later checks ask different questions

The same script continues beyond the first handoff. Keep each compared representation attached to its producer:

| Check | Exact compared artifacts | Question |
|---|---|---|
| Step 5 | `OUT/cc-out-v2` and `OUT/cc-out-v2-fasm` | Do two assembly routes agree on the same `self-v1` text? |
| Step 6 | `OUT/self-v2-amd64.M1` and `OUT/self-v3-amd64.M1` | Do v2 and v3 emit identical text from the specified self-source input? |
| Step 7, M1 | `WORK/M1-gen2` and `OUT/M1` | Does the later rebuild reproduce this tool ELF? |
| Step 7, hex2 | `WORK/hex2-gen2` and `OUT/hex2` | Does the later rebuild reproduce this other tool ELF? |

For step 6, v2 first emits `self-v2`, which the source-built tools assemble into v3. Then v3 emits `self-v3`. The mandatory equality is a textual fixed point; there is no `cmp` of compiler ELF v2 against compiler ELF v3 at this step. The separate v1-versus-v2 text comparison is informational, so a difference there does not fail the script.

For step 7, v3 recompiles each tool's C source, and the existing M1/hex2 tools assemble its new text. Each resulting ELF is compared with that tool's earlier ELF. M1 is not compared with hex2, and neither is compared with its host-GCC-built implementation.

Step 8 changes from byte equality to a behavior check. The final compiler emits a small greeting program, the tools assemble it, and the script runs it. The script requires exit status zero and compares captured stdout with `Hello from Forth-bootstrapped M2-Planet!`. Shell command substitution removes trailing newlines, so that comparison is not an exact comparison of all original stdout bytes. It remains a useful, distinct execution check.

The `run_forth` wrapper adds practical acceptance checks around fixed output paths: it removes stale output, runs the requested input in the chosen working directory, requires zero exit and a produced file, moves the file to its named destination, and requires executable permission. It uses a private `/tmp` when its namespace setup succeeds, otherwise the shared path. These checks do not turn the writer's ignored write result into a complete-write guarantee; the later comparisons serve a separate purpose.

Sources: [wrapper](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L97-L129), [steps 6–7](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L239-L262), and [step 8's behavior check](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L265-L274).

## Reference: choose the oracle that answers your question

An **oracle** here is the rule or reference result used to decide whether a particular check passes. It is not a guarantee that every behavior is correct.

The existing small recipes do not all exercise the same input path:

| Recipe | Forth assembler input after its prelude | Actual requested checks |
|---|---|---|
| `exit42-check.sh` | Header plus hex2 already produced by reference M1 | Reference ELF equals Forth output; result exits 42 |
| `jump42-check.sh` | Header plus the short-branch hex2 fixture | Reference ELF equals Forth output; result exits 42 |
| `m1-jump42-check.sh` | Definitions, header, original M1 fixture | Reference M1+hex2 route equals Forth output; result exits 42 |

The first test alone cannot demonstrate the Forth macro-expansion path: the reference M1 tool already performed that work before the Forth assembler received the input. The third includes numeric sigils and macro expansion, but is still only one selected input.

[`die-gates.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/die-gates.sh#L18-L90) has seventeen specific cases, one for each code 231 through 247. It removes old output, checks the expected exit code, and requires that no new `/tmp/asm-out` exist. It captures stderr without asserting its contents. It does not cover output-open failure 230 or every boundary value in the range table.

The larger tests also keep representations distinct:

- [`m2planet-check.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/m2planet-check.sh#L37-L98) compares two assembly routes on the same self-M1. Its final tiny-C check compares the M1 text emitted by two compiler executables; it does not assemble and run that tiny C program
- [`mescc-tools-check.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/mescc-tools-check.sh#L43-L88) compiles each tool once to M1, then compares the ELFs obtained by two assembly routes on that same text. The “reference” operand is the output of the reference assembler pipeline, not the host-compiled tool executable
- Its [tiny behavioral checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/mescc-tools-check.sh#L95-L121) compare M1-produced text and, separately, four bytes produced by hex2. The four bytes `7F 45 4C 46` are a magic-number fragment, not a complete ELF or a program that the check runs

The reference-builder helper defaults to GCC but permits a `CC` override. Calling a particular producer “GCC-built” therefore also needs the actual recipe context, not only a filename ending in `-ref`.

Sources for the small paths: [exit42](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/exit42-check.sh#L37-L78), [jump42](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/jump42-check.sh#L26-L57), [m1-jump42](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/asm/m1-jump42-check.sh#L24-L64), and [reference builder](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/build-gcc-refs.sh#L24-L43).

### What the recorded CI summary adds

The existing [Check run 37474668625](https://github.com/delta9000/seed-forth/actions/runs/37474668625), at head `764bdc4f4902d613145f361da6a7f33010dd37b4`, completed successfully on 2026-10-06. Its [check-all + verify job](https://github.com/delta9000/seed-forth/actions/runs/37474668625/job/112306844449) reports fixture assembly-route equality at 136, 145, and 148 bytes. It also reports M1 and hex2 assembly-route equality at 52,808 and 56,707 bytes respectively. The latter counts describe the compared outputs assembled from C-derived M1, not the GCC-compiled oracle executables.

Those are attributed observations from that run. The retained job summaries do not supply the compared binaries, their full hashes, or complete inner logs. They must not be enlarged into a claim that every new example here ran, that compiler ELFs across generations were equal, or that all input grammar is compatible. The source explanation in this chapter uses the separately stated teaching pin; the CI record has its own head identity. No new build, assembler invocation, generated program, or teaching example was executed for this chapter.

We have opened the complete bounded Forth assembler across C21 and C22: text expansion, sizing, name resolution, byte emission, and the caller/output contracts. We have followed the source-built M1/hex2 handoff far enough to name what its comparisons mean. Full upstream compiler, assembler, and runtime internals, and later TinyCC/GCC/Linux routes, remain outside this unit.

## Practice: explain the coordinate or artifact before calculating

These twelve paper tasks progress from completion to independent prediction, diagnosis, and changed-context checks. No execution is requested. The [graduated hints and solutions](../practice/22-solutions.md) are separate. You may use the source/range tables as references; the aim is to choose the right rule, not memorize every constant.

### C22-01 — Complete the original two-pass trace

For the original expanded fragment, complete this record without looking at the first trace:

```text
:top EB !end 41 00 :end 90 EB !top

top offset = __        end offset = __        final offset = __
forward field end = __  forward value = __
backward field end = __ backward value = __
```

Give the seven output bytes. Name two things the rewind resets and two things it preserves. Explain why calling `asm-init` for the rewind would break the reference lookups.

### C22-02 — Length and base change together

Start again from C21's two definitions, `jump` → `EB` and `nop` → `90`. Use base `0x700000` and this raw fragment:

```text
:top jump !end "ABC"
:end nop jump !top &end
```

For the character lookup, ASCII `C` is `0x43`; use C21's `A=0x41` and `B=0x42`. Write the expanded token sequence, both label addresses, total output size, and complete predicted bytes. Which emitted field depends on the new base? Which depend on the changed string length? Explain why the NUL is counted. This is still a non-ELF fragment.

### C22-03 — Separate number, relative label, and explicit difference

At base `0x1200`, assemble on paper:

```text
:a !-2 @0x1234 ~a $a &a %end>a :end
```

Annotate each field's offset and width, then derive its bytes. Explain why `$a` succeeds here even though it failed at the chapter's default base. Finally change only `%end>a` to `%end` and identify the changed bytes.

### C22-04 — Derive both short-reference boundaries

A forward fragment is `EB !far`, followed by N literal zero bytes and `:far`. A backward fragment is `:back`, followed by N literal zero bytes and `EB !back`. Derive the largest nonnegative N accepted in each case and the value at that boundary. Give the failure code after increasing each N by one.

Then predict `!256`, `!257`, and `!-129`. Explain why the numeric cases cannot be answered using only the label-range column.

### C22-05 — Move the duplicate after an earlier reference

At any base used in the worked examples, trace:

```text
!x :x 90 :x !x
```

List both stored records in insertion order, and give the three output bytes. Does the first reference see the first declaration, the last declaration, or no declaration? Explain the search and pass timing, not a presumed scope rule. Separately, why does `asm-find-label` need a success flag if a found label can have address zero?

### C22-06 — Locate the first rejecting phase

Treat these as three independent expanded inputs:

```text
A: 90 !missing
B: 90 Z
C: 90 F
```

The `A:`, `B:`, and `C:` labels here are annotations, not source. For each input, name the rejecting pass, the error code, whether any bytes have been newly emitted before failure, and whether this invocation has opened its output file. Explain which part of the token-boundary invariant remains useful even when an input fails.

### C22-07 — Preserve the storage contract

A proposed optimization overwrites the expanded buffer immediately after pass 1 because “the label table already has all the names.” Diagnose the proposal using the record's three cells. Give a correct lifetime rule without proposing a source change.

For a separate capacity check, suppose pass 1 successfully counts 1,048,577 output bytes and the input otherwise satisfies all checks. How many bytes can pass 2 append before the next append fails, what code is used, and is the failing byte stored? Compare with storing the 8,192nd and 8,193rd labels.

### C22-08 — Do the records establish a saved executable?

Record A says a previous `/tmp/asm-out` exists. A new invocation fails with undefined-label code 235 before its writer is reached. Does the remaining file establish success of the new invocation?

Record B says a fresh invocation built a complete 148-byte buffer, its open succeeded, its single write returned 100, and its close returned zero. Follow the inspected writer: does it detect the incomplete write? What extra observation would support a claim that the saved bytes equal the expected fixture? Do not change or run the program.

### C22-09 — Change the supplied-header fixture

Remove only the unreachable `mov_rdi, %99` line from `m1-jump42.M1`. Keep the supplied header, definitions, base, and all labels. Derive the new positions of `skip` and `ELF_end`, the `jmp` displacement bytes, the entry-address bytes, and the low four bytes of each size field. Under the chapter's target contract, does the expected exit value change? Separate that prediction from a recorded execution.

### C22-10 — Recover the source-built handoff

A notebook lists `WORK/M1.M1`, `OUT/M1`, `self-v1-amd64.M1`, `cc-out-v2-fasm`, and `cc-out-v2`, but loses their arrows. Reconstruct the producer of each and the exact comparison that first checks the source-built assembly route. Include the companion `hex2` tool where needed.

Then identify the distinct compared pairs in steps 6 and 7. You may look up source lists and options. Why would comparing `OUT/M1` with a GCC-compiled M1 executable ask a question the documented assembly-route check does not ask?

### C22-11 — Read the oracle literally

Assess these claims and rewrite any that overreach:

1. Passing `exit42-check` alone proves Forth macro expansion works
2. The final tiny-C check in `m2planet-check` runs a program that exits 42
3. The tiny hex2 check produces four bytes beginning with ELF magic, so it establishes a valid executable
4. The CI summary's 52,808-byte M1 result gives the size of the GCC-built M1 oracle
5. The greeting check's captured-string equality establishes byte-exact stdout including its trailing newline

For each correction, name what was actually supplied or compared. A bare “false” does not identify the missing evidence.

### C22-12 — Return without the original trace

After working on something else, try these without the worked byte tables. Give the decisive invariant before any calculation:

- At base zero, what does `:p 00 !p` emit, and why is address zero not a failed lookup?
- At that same point after `:p 00`, replace `!p` with `!0`. Is the value calculation the same?
- Two assembly texts differ only by a comment removed during expansion, and all other inputs and conditions are fixed. Can different source-text bytes lead to equal output bytes? Does output equality imply source-text equality?
- A reported step-6 pass is summarized as “v2 and v3 are byte-identical compilers.” What representation must the summary name instead?

If the coordinate questions go wrong, return to the field-end picture. If the final pair goes wrong, draw one invocation from each producer to its compared artifact. Use the feedback to repair that specific step, then try an answer-free reattempt from the solution page.

## What we can now carry forward

One expanded buffer was enough to support two different walks. The first measured every token and recorded addresses; the second reused those boundaries to emit values. Preserving the table and its borrowed names made forward references possible. Field-end subtraction, explicit label differences, numeric immediates, and low-byte storage each had a distinct role.

Adding the supplied header turned a bare fragment into a completely accounted-for ELF-shaped input. Following the resulting compiler into tool construction showed why assembly closes a real gap: generated text must become bytes before the next tool can run. The handoff's exact ELF comparison, later M1-text fixed point, rebuilt-tool comparisons, and behavior checks supply different evidence. Keep those identities attached to every later bootstrap claim.
