# C21 hints and solutions

These are paper solutions to [C21's expansion and input tasks](../chapters/21-assembler-input-and-expansion.md#practice-preserve-the-representation-boundary). No new execution is reported. The hints increase in specificity; use the first one that helps, or go directly to the solution. An answer-free changed case follows each solution so you can check a revised explanation without repeating the same input.

## C21-01 — Complete the changed first walk

**Hint 1.** Change only the direct string's contribution. Definition lookup and the copying of labels/references follow the original walk.

**Hint 2.** Every body byte in a double-quoted token adds two hex characters and a space; the terminator contributes another three characters.

**Hint 3.** ASCII B is 0x42. The new string contribution begins `41 42`.

**Solution.** The exact expansion is:

```text
:top EB !end 41 42 00 :end 90 EB !top 
```

There is one final space, no generated newline. Replacing `41 00 ` with `41 42 00 ` adds three text bytes, so the total is **38**. The string describes three eventual bytes: A, B, and NUL. Neither definition record changes: both declarations still occupy the same earlier raw locations, with the same names and bodies. The changed string occurs after them.

Direct `'41'` instead contributes `41 `, removing precisely `00 ` from the original expansion. That gives:

```text
:top EB !end 41 :end 90 EB !top 
```

Its length is **32** text bytes. This form describes A's byte without a following zero byte. Neither result resolves `!end` or `!top`.

**Wrong path to avoid.** Adding one character B to a quoted body does not add one expanded text byte. The body byte is represented by two generated hex digits plus a separator. Conversely, the quotes themselves are not output data bytes.

**Answer-free reattempt.** Replace the original `"A"` with the empty direct string `""`. Derive the complete text, its text length, and the number of string data bytes. Explain why empty text between double quotes is not the same as omitting the token.

## C21-02 — Trace separators before meanings

**Hint 1.** First decide whether each marker is outside a quote. Do not apply comment rules to the body of a quoted token.

**Hint 2.** The comment starts immediately after the bare token `90`. A matching quote, not whitespace, ends each quoted token.

**Hint 3.** Capital C is 0x43, `#` is 0x23, and capital D is 0x44. CR does not satisfy the comment helper's LF termination test.

**Solution.** The raw token slices are:

| Slice | Length | Reason it ends there |
|---|---:|---|
| `90` | 2 | Semicolon terminates the bareword |
| `"C#D"` | 5 | Matching double quote ends the quoted scan |
| `'41 42'` | 7 | Matching single quote ends the quoted scan |

The semicolon starts the discarded comment. The hash inside `"C#D"` is data. Expansion produces:

```text
90 43 23 44 00 41 42 
```

The final space is part of the **21-byte** text: seven two-digit tokens, each followed by one space.

For the separate `90#x` + CR + `41` input, the first returned token is `90`. The next token request reaches `#` and invokes comment skipping. It consumes x, CR, 4, and 1 before reaching EOF. There is no LF to end the comment earlier, so `41` never becomes a token. Ordinary CR whitespace recognition is not consulted inside that comment loop.

For `"A"90`, the quote was at token start. The quoted scanner stops immediately after the closing quote, leaving `90` for the next read. For `90"A"`, the bare scanner was chosen at `9`; quotes do not terminate it, so the whole five-character spelling is one bare token. Its later hex validation fails on a quote.

**Wrong path to avoid.** Applying “a quote is always special” during the bareword loop invents a scanner transition the source does not have. Applying “CR is whitespace” as “CR ends a comment” merges two different loops.

**Answer-free reattempt.** Use `90#x` followed by CR, then LF, then `41"B"`, with EOF afterward. List the returned slices and explain which later token cannot be bare hex. Then replace that final spelling with `"B"41` and repeat the boundary trace.

## C21-03 — Choose the definition available at that moment

**Hint 1.** Write the definition count beside every use, not only at the end of the input.

**Hint 2.** Before the first declaration, there is nothing to find. After a redefinition, the search starts at the newest record.

**Hint 3.** The characters F, A, C, and E are all valid hexadecimal digits, and four is an even length.

**Solution.** The expansion is `FACE 90 CC `, including its final space, for a total of **11 text bytes**.

1. The first `FACE` sees count zero and is copied unchanged
2. `DEFINE FACE 90` creates record 0; the next use finds it and copies `90`
3. `DEFINE FACE CC` appends record 1; the last use finds record 1 first and copies `CC`

The first token can become literal bytes FA CE even though no definition supplied it. The expanded `90` and `CC` also become one literal byte each. This input therefore describes four bytes through the bare-hex path.

If only the first use is changed to `jump`, the expansion becomes `jump 90 CC `. The first bare token contains nonhex characters, so the later validator reaches error 246. This is why a failed macro lookup is not itself the test for an error: the expander copies unmatched tokens, and the next consumer judges their spelling.

The final table contains both definitions but not the time at which each earlier token was processed. Applying the newest final record to every earlier use would invent a second expansion walk and incorrectly replace the first two results.

**Wrong path to avoid.** “The last definition wins” is incomplete. It wins only among records already stored at the time of that lookup.

**Answer-free reattempt.** Replace both definition names with `op`, but leave the first input token as `FACE` and change the two later uses to `op`. Predict the expansion and explain which result now depends on hexadecimal spelling rather than definition lookup. Then move the first declaration to immediately after the first use of `op`.

## C21-04 — Diagnose two tempting repairs

**Hint 1.** Find the body bytes stored in the record used by the final token.

**Hint 2.** `asm-exp-bytes` copies those bytes directly to the expanded buffer. It does not call definition lookup or choose a string handler.

**Hint 3.** The two exact body slices are `op` and `'90'`, with the quotes included in the latter.

**Solution.** The alias input expands to `op `, three text bytes. `alias` matches the record whose body is `op`; that copied spelling is not looked up a second time. Later, bare-hex validation rejects `op` with 246.

The quoted-body input expands to `'90' `, five text bytes. The definition stored its quoted body unchanged, and using `x` copies all four body bytes before adding a space. The later token reader recognizes the quoted slice as a token, but the later token **processor** has no direct-string expansion case. It treats the token through its bare-hex fallback and rejects a quote with 246.

“Repeatedly look up aliases” would add recursive or iterative rescanning with new termination and cycle questions. “Run copied quotes through the string handler” would add another semantic dispatch on generated text. Either could be a design for a different expander; neither describes this one.

Leaving `x` unused does not by itself fail. The declaration stores the body; no body validation or later quote processing is triggered merely by storage. The problem above arises when its copied body reaches the later consumer.

**Wrong path to avoid.** Quote-aware tokenization is not equivalent to quote-aware assembly meaning. Reusing a tokenizer does not rerun the expansion phase.

**Answer-free reattempt.** Compare `DEFINE x 90` followed by `x` with `DEFINE x 90` followed by the directly encountered token `'x'`. Derive both expanded texts and identify where the apparent similarity stops.

## C21-05 — Follow the borrowed addresses

**Hint 1.** Each cell occupies eight bytes, but a cell containing a pointer does not contain the pointed-to letters.

**Hint 2.** The record resides at D. Its two pointers still refer to R, however many times the record cells are copied.

**Hint 3.** Later label names are read after the active cursor switches to E.

**Solution.** The four cells are:

| Cell address | Value | Meaning |
|---|---|---|
| D+0 | R+7 | Pointer to four name bytes in raw input |
| D+8 | 4 | Name-byte count |
| D+16 | R+12 | Pointer to two body bytes in raw input |
| D+24 | 2 | Body-byte count |

All four cells themselves belong to the definition table. The bytes reached through the first and third fields belong to the raw buffer; the two length fields are counts and do not borrow another buffer.

If the two bytes at R+12 are overwritten with `CC`, a later lookup returns the same pointer and length as before but now copies `CC`, not `EB`. The record still looks structurally intact. Its borrowed content has changed.

The later label record's name points into the **expanded** buffer. If the token `:top` starts at E, the name slice begins at E+1 and has length three. That name-pointer value is an address in the assembler process. The target address assigned to `top` describes the position of eventual output bytes; these are distinct address roles and need not be numerically equal.

A shallow copy duplicates R+7 and R+12 as pointer values. It does not recreate the old raw letters, so it cannot repair an overwritten owner. Repair would require preserving or copying the actual bytes and updating which storage the record names.

**Wrong path to avoid.** Treating “the table owns the pointers” as “the table owns the strings” erases the lifetime requirement that makes zero-copy slices safe.

**Answer-free reattempt.** Suppose raw input remains intact, but someone normalizes the expanded buffer in place after the first later assembly walk has stored label-name pointers. Explain which records are threatened and which definition records are unaffected. Do not assume normalization preserves byte positions.

## C21-06 — Find the exact capacity boundary

**Hint 1.** `asm-check-cap` allows equality; check what each caller passes as its proposed count.

**Hint 2.** The raw loader tests one beyond the length it just obtained. The expanded writer tests the length it would obtain after one append.

**Hint 3.** A nonpositive read ends the loader loop, and `asm-next-char` increments position after peeking regardless of EOF.

**Solution.** With C = 4,194,304:

| Case | Result | Decisive check or branch |
|---|---|---|
| Raw read reaches C−1, then zero | Accepted loading boundary | `(C−1)+1 = C`, then nonpositive read ends loop |
| Raw read reaches C | Exits with 239 | `C+1 > C`; bytes have already been read |
| Append at expanded C−1 | Succeeds; new length C | `(C−1)+1 = C` before store |
| Append at expanded C | Exits with 240 before store | `C+1 > C` |
| Store at definition count 4,095 | Succeeds; new count 4,096 | `4,095+1 = 4,096` |
| Negative read after positive reads | Stops reading without a separate read-error report | The loop requires result greater than zero |

The last case leaves the previously accumulated raw length; it is not evidence that the intended full input was available. The loader discards the terminal read result, so its caller does not receive a special negative-read diagnosis from this routine.

At position equal to length, peek returns zero without moving. Next returns the same zero and then increments position to length plus one. Normal scanners check EOF before taking a next character, both to avoid that unnecessary advance and because an actual zero byte within the input is not EOF. Length and position determine EOF.

**Wrong path to avoid.** A four-mebibyte allocation does not imply every client accepts four mebibytes of completed content. Conversely, a reserved source slot does not imply a NUL byte was written there.

**Answer-free reattempt.** A positive read reaches C−2; another returns one; a third returns one. Trace the three updated lengths and identify exactly which read triggers the capacity failure. Separately, let expanded length be C−2 and append three bytes one at a time.

## C21-07 — Separate copy length from described bytes

**Hint 1.** A double string contributes one hex pair and separator per body byte, followed by a terminator pair and separator.

**Hint 2.** Single quotes copy their body as text. Backslash is an ordinary body byte here.

**Hint 3.** Backslash has byte value 0x5C and lowercase n has value 0x6E. The attempted output of `"A"` is the six-character sequence `4`, `1`, space, `0`, `0`, space.

**Solution.** The independent contributions are:

| Direct token | Expanded text, with final space | Text length | Described data-byte count |
|---|---|---:|---:|
| `""` | `00 ` | 3 | 1 |
| `''` | One space | 1 | 0 |
| `"A\n"` | `41 5C 6E 00 ` | 12 | 4 |
| `'4142'` | `4142 ` | 5 | 2 |

The empty single string inserts a separator that yields no later token. `'4142'` inserts one four-digit hex token, later read as two whole pairs. The backslash-n body contains two separate characters, not a newline escape.

With only four expanded-buffer slots free, direct `"A"` first writes `4`, `1`, space, and the first `0`. The buffer is now exactly full and contains the partial contribution `41 0`. Attempting the **second zero character** makes proposed length exceed capacity, so `asm-exp-emit-byte` exits with 240 before that write. The final separator is never reached. There is no whole-token rollback in this loop.

**Wrong path to avoid.** The byte 0x41 is represented by two text bytes. The termination byte 0x00 also takes two text bytes plus its separator. Counting only described data would predict the wrong capacity behavior.

**Answer-free reattempt.** Compare a direct single-quoted token whose body is `4142` with a direct double-quoted token whose body is `4142`. Derive their text lengths and described data lengths. Then give the minimum free expanded-buffer capacity required for each complete contribution.

## C21-08 — Classify, then convert

**Hint 1.** The classifier checks total token length and one byte after the sigil. It does not scan digits.

**Hint 2.** Consume a leading minus before checking for `0x` or `0X`. A leading zero without that prefix stays decimal.

**Hint 3.** For `-0X2A`, digit processing begins at body index three. For `010`, it begins at index zero.

**Solution.** The classifications are:

| Token | Branch | Reason |
|---|---|---|
| `@-0X2A` | Numeric | First body byte is `-` |
| `%010` | Numeric | First body byte is a digit |
| `%+42` | Label | `+` is not a numeric starter |
| `%4oops` | Numeric | Only the initial `4` is inspected |
| `!` | Label | Whole-token length is less than two |

The valid numeric bodies are `-0X2A` and `010`. The first consumes minus at index zero, then prefix at indices one and two. It processes `2` at index three to get magnitude two, and `A` at index four to get 2×16+10 = 42. Index five equals the length, and the saved sign changes the return value to **−42**.

For `010`, there is no sign and no hexadecimal prefix. At indices zero, one, and two, decimal accumulation gives 0, then 1, then 10. Index three ends the loop; the result is **ten**.

`+42` does not meet the taught numeric syntax and is not sent to that parser by this classifier. `4oops` is routed as numeric but does not meet its valid-digit premise. The empty body of `!` is not a well-formed number either. Classification alone provides no reason to accept those as numeric literals.

Body `0x` is long enough to consume a prefix, leaving the index equal to the length. No digit loop executes, and the initialized accumulator remains zero. This behavior exposes the absent “at least one digit” validation. It does not expand the supported well-formed contract.

Bare-hex validation does not protect the numeric parser. The hexadecimal branch's `hex-val` calls are on a separate path and receive no prior per-digit `asm-hex-char?` check there.

**Wrong path to avoid.** “Numeric branch” names a control-flow choice, not a certificate of syntactic validity. Treating `010` as octal also imports another language's convention.

**Answer-free reattempt.** Classify `%0X10`, `%-010`, and `%entry`. Trace the two numeric bodies, then explain what would change if a declared label were named `-010` and referenced with the same spelling after a sigil.

## C21-09 — Repair an overconfident contract

**Hint 1.** Separate defining the driver from invoking it, and separate selecting target addresses from supplying file-format bytes.

**Hint 2.** `skip-vm-pages` stores a fixed HERE value. Expansion copies numeric sigils for a later handler.

**Hint 3.** The unterminated three-byte token `"AB` and the prefix-only numeric body `0x` are counterexamples to complete validation.

**Solution.** An accurate replacement is:

> Use a fresh seed process with 010, then 130, before the caller explicitly invokes `asm-main`. The opening `skip-vm-pages` assigns HERE to 0x414000 under its fresh-load premise; it is not a high-water-mark allocator safe after arbitrary compiler loading. The driver reads the remaining input, expands definitions and direct strings, then assembles the expanded text. Numeric sigils can remain in that intermediate buffer. The implementation checks some later token and field errors, but relies on valid-input premises for quotes and numbers. It emits the bytes the input describes; an ELF header must be supplied as input. The default target base is 0x600000.

One concrete counterexample is the three-byte unterminated input `"AB` without newline. The scanner reaches EOF without a missing-delimiter error; the string handler treats the last byte as the supposed closing quote, encodes A, and adds `00 `. Another is body `0x`, which returns the initialized value zero after consuming its prefix without requiring a digit.

Either counterexample is enough to defeat “rejects all malformed source.” The point is not to recommend these inputs, but to avoid a guarantee absent from the source.

**Wrong path to avoid.** Fixing only the word “safely” leaves the false invocation, representation, and ELF claims untouched. The contract concerns several different boundaries.

**Answer-free reattempt.** Rewrite this separate claim: “Because the assembler reserved a raw buffer and its token reader returned EOF, a later file proves that every intended source byte was read.” Identify both a loading precondition and a later evidence requirement without inventing an observed run.

## C21-10 — Bring the boundaries together

**Hint 1.** The direct string contains ASCII digit zero, not a byte whose value is zero.

**Hint 2.** The single-quoted token creates two later hex tokens. `@010` remains spelled that way in expanded text but is classified numeric later.

**Hint 3.** Count widths in the order zero, one, one, one, two, one, one, four.

**Solution.** The exact expansion is:

```text
:here 90 30 00 @010 41 42 &here 
```

There is one final space and no newline. Text contributions, each including its separator, have lengths 6 + 3 + 3 + 3 + 5 + 3 + 3 + 6 = **32**.

| Token | Later role | Width in bytes |
|---|---|---:|
| `:here` | Label position | 0 |
| `90` | Bare hex | 1 |
| `30` | Bare hex for ASCII `0` | 1 |
| `00` | Bare hex for string terminator | 1 |
| `@010` | Numeric field with decimal value ten | 2 |
| `41` | Bare hex | 1 |
| `42` | Bare hex | 1 |
| `&here` | Absolute label field | 4 |

The described total is **11 bytes**. This is size accounting from the supplied local interface; no resolved address or emitted little-endian field is needed to obtain it.

During expansion, the definition record for `mark` borrows its name and body from unchanged raw input. During later label processing, the `here` name is borrowed from unchanged expanded input. The two owners have different roles at different stages.

Changing the declaration to `DEFINE mark '90'` changes the stored body slice first, from two bytes to four including quotes. When `mark` is used, the expanded text begins `:here '90' ...` instead of `:here 90 ...`. The later bare-hex fallback rejects the quote character. Changing the target base cannot fix a malformed expanded token or make copied bytes re-enter the direct-string handler.

**Wrong path to avoid.** Treating quoted `"0"` as an already-zero byte erases its ASCII byte 0x30. Treating `'41 42'` as one indivisible later field misses the change in token boundaries.

**Answer-free reattempt.** Keep the original unquoted definition but replace `"0" @010` with `'30' %0x10`. Derive the complete expanded text, its length, each token's role, and the new total described width. State which differences come from string semantics and which come from a changed field width.
