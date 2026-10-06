# 21. Assembler input and expansion

C20 ended with a file of M1 text. Comparing that text answered whether two compiler programs emitted the same representation. It did not turn the representation into executable bytes. We now open the next transformation, starting with something small enough to follow character by character:

```text
DEFINE jump EB
DEFINE nop 90
:top jump !end "A"
:end nop jump !top
```

What does each spelling promise? Is `jump` already an instruction byte? Can `!end` be replaced before we have reached `:end`? Does `"A"` mean the hexadecimal digit A, the character A, or both?

Hold the address question open. This first session will get all the way from these four lines to the assembler's exact **expanded text**. That is an intermediate representation: definitions have been substituted and direct strings translated, but symbolic references remain. The fragment is not an ELF file or a proposed runnable program. We need no instruction execution to follow it.

## Give each token one job

A **token** here is a slice of input text that the reader returns as one item. Spaces normally separate items; the quotes make `"A"` one item, including its two quote characters. The detailed comment and quote boundaries come later. For this example, the following small key is enough:

- Two hexadecimal characters specify one eventual byte: `EB` specifies byte 0xEB, and `90` specifies byte 0x90
- `DEFINE name body` saves a name and a replacement body. The declaration itself contributes no text to the expanded stream
- `:top` and `:end` name positions that will be discovered when the expanded text is assembled
- `!end` and `!top` each reserve one eventual byte for a relative reference. Expansion preserves these spellings
- A directly encountered double-quoted string becomes hex text for its body bytes, followed by hex text for a zero byte

The names `jump` and `nop` acquire their meanings from the two declarations we supplied. This assembler does not need a built-in table that knows those names as x86 mnemonics.

Before following the walk, predict which items disappear, which are copied, and which grow. Write a rough expanded line; leave the `!` references unresolved. If the distinction between text and bytes is rusty, check one small fact first: `4142` contains four text characters but describes two bytes.

Our results are paper derivations from [`130-asm.fth` at the book's pinned revision](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth). They are not reports of new runs. We use the Linux/AMD64 seed's 64-bit cells and byte-addressed memory. Nothing in this first walk depends on knowing the eventual target addresses.

## The first two lines save slices, not instructions

The assembler first holds the complete input in a **raw buffer**. A buffer is a reserved region of memory; its length says how many of its bytes currently belong to the input. A **slice** is an address and a length pointing into that region. The token reader returns slices rather than allocating a new string for each token.

The first returned token is `DEFINE`. The expander recognizes this exact uppercase spelling and asks the token reader for two more tokens: `jump`, then `EB`. It saves four values in one definition record:

```text
name address | name length | body address | body length
```

The address fields point into the raw buffer. The record does not contain a fresh copy of the letters. To make that concrete, let R mean the raw buffer's first address and number source bytes from zero. With LF line endings as displayed, the first `jump` begins at R+7, and its `EB` begins at R+12.

The next declaration adds the second record. After the first two lines, the table is:

| Record | Name address | Name length | Body address | Body length |
|---|---|---:|---|---:|
| 0 | R+7, pointing to `jump` | 4 | R+12, pointing to `EB` | 2 |
| 1 | R+22, pointing to `nop` | 3 | R+26, pointing to `90` | 2 |

The expanded buffer is still empty. Neither the word `DEFINE` nor any of these six declaration tokens was copied into it.

These are **M1 definition records**, not Forth dictionary words. The Forth implementation has a word named `asm-def-store` that writes a record. Reading `DEFINE jump EB` does not teach the Forth interpreter a callable word named `jump`. The assembler is now reading assembly input as data.

Source: [definition storage and lookup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L621-L660).

## Follow the third line without solving its address

The next raw token is `:top`. It is neither `DEFINE` nor a direct quote, and no stored definition has that name. The expander copies its four characters to the expanded buffer, then appends a separator space:

```text
:top 
```

The final space inside this block is part of the result. For ordinary tokens, expansion writes one space after the copied text even when the original separator was a newline.

Next comes `jump`. Only definitions already seen can match; a later declaration does not rewrite earlier output. Definition lookup finds record 0, so the expander copies the two body bytes `EB`, followed by a space. It copies **text characters**, not byte 0xEB. The next consumer will turn that pair of characters into one byte.

Next comes `!end`. No definition matches this complete token. The expander copies it with its leading exclamation mark intact. We now have thirteen text bytes:

```text
:top EB !end 
```

Keeping an unresolved token is useful. It lets this walk finish its own job without pretending to know where `end` will be. This is also why “expansion has finished” will not mean “all numbers and addresses have become output bytes.”

Now the raw token `"A"` takes a different branch. Its first character is a double quote. The expander looks between the opening and closing quotes and reads the one body byte, capital A. That byte has the ASCII value 65, or 0x41. It writes the two hexadecimal characters `4` and `1`, then a space. Finally it writes `00 ` for the required NUL terminator. **NUL** here means a byte whose value is zero; the expanded buffer holds the characters `0` and `0` describing it.

After the third line the expanded text is therefore:

```text
:top EB !end 41 00 
```

The three source characters in `"A"` have contributed six expanded text characters, `41 00 `, describing two eventual bytes. This is the representation change that an unexplained phrase such as “copy the string” would hide.

Source: [direct double-quote translation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L696-L715) and [the expansion dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L729-L762).

## Finish the same walk

The fourth line needs no new rule. `:end` is copied. `nop` finds record 1 and contributes `90`. `jump` finds record 0 again and contributes `EB`. `!top` is copied unchanged. Every one of those contributions receives its separator space.

The complete expanded text is:

```text
:top EB !end 41 00 :end 90 EB !top 
```

There is **one final space after `!top` and no newline in this expanded result**. To verify its exact 35-byte length without relying on a visible trailing space, count each contribution including its separator:

```text
:top␠  EB␠  !end␠  41␠  00␠  :end␠  90␠  EB␠  !top␠
   5 +  3 +     5 +   3 +   3 +     5 +   3 +   3 +     5 = 35
```

This last display uses `␠` as a visible-space annotation; neither that symbol nor the extra alignment spaces belong in the actual text. The result consists of nine space-terminated tokens. Two definitions have disappeared, two uses of `jump` have become `EB`, one use of `nop` has become `90`, and both references still await assembly.

Pause over the two meanings of A. Inside `"A"`, A is a source character with byte value 0x41. A **bare** token `A` would be a hexadecimal digit with numeric value ten. It contains only half of a byte's required two-digit spelling, so the later bare-hex check rejects it as an odd-length token. Neither spelling is shorthand for the other.

## Why neither owner may move yet

We have used two kinds of storage at once:

```text
raw input       owns the letters used by definition name/body slices
expanded input  owns the new text copied or encoded by this walk
```

The raw input remains unchanged while expansion reads it. A later `jump` lookup can therefore follow record 0's body pointer and still find `EB`. Writing expanded text into a separate buffer avoids overwriting a definition body before its last use.

Once expansion finishes, the driver switches its active reader to the expanded buffer. Later label records will borrow their **name slices from this expanded buffer**, because that is where the later walks encounter `:top` and `:end`. The label's eventual address value is a different thing from the address of its name's letters. C22 will open that table. Its local promise here is that the expanded text stays unchanged throughout those later walks.

A useful lifetime rule follows: a borrowed slice stays meaningful only while the bytes it names remain available and unchanged. Keeping the record's four cells is insufficient if its owner buffer has been overwritten. This small assembler keeps the buffers allocated for the whole operation rather than trying to reclaim them between stages.

## Change the quotes, then keep the question

Replace only `"A"` with the directly encountered single-quoted token `'41'`. Predict the new expanded text before reading on. Does the spelling still request a zero terminator?

A direct single quote has a different contract: remove the two delimiters, copy the body verbatim, and add one separator space. `'41'` therefore contributes `41 `, with no `00 `. Our changed text is:

```text
:top EB !end 41 :end 90 EB !top 
```

It is 32 text bytes, three fewer than before. The hex token `41` still describes A's byte, but there is no longer a following zero byte. That difference will matter when the assembler locates `end`. For a small independent check, change the original `"A"` to `"AB"` instead. For this check and the next chapter, use ASCII A = 0x41, B = 0x42, and C = 0x43. Derive the new expanded text and its length without calculating any branch value yet.

We have reached a usable intermediate result. The same forward-reference puzzle remains in both versions: **the first `!end` appears before `:end`. How can the assembler know which byte to write without guessing?** Keep the original 35-byte text for C22. The later sessions below explain the input and expansion machinery behind the walk; none needs the answer to that address question.

## Later session: put the input somewhere it can stay

Return to the first definition record. Its pointer to `EB` was safe because the raw buffer did not change. We can now inspect the storage contract that makes that promise practical.

### Start a separate assembler process

The assembler's Forth vocabulary depends on the seed and `010-lib.fth`; it does not import the C-compiler layers. The intended load order is a **fresh seed process**, then 010, then 130. At 130's start, `skip-vm-pages` assigns Forth's allocation pointer, HERE, to **0x414000**. This puts subsequent large allocations above the seed's fixed runtime pages, including the data stack, I/O scratch, token buffer, and system variables.

The assignment is not “advance beyond whatever was previously allocated.” The [010 definition](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L379-L391) stores one fixed address and requires HERE still to be below the data-stack region when called. Loading 130 after the whole compiler could rewind allocation into occupied storage. Treat the assembler as its own small program, not a harmless extra layer appended to C20's compiler stream.

Loading 130 defines `asm-main`; it does **not** invoke it. The caller supplies that invocation explicitly. The relevant stream boundary is:

```text
010 Forth definitions
130 Forth definitions
optional Forth assignment to asm-base
asm-main followed by a newline
remaining M1/hex2 input bytes
```

This is a stream diagram, not a shell command. The newline separates the Forth invocation token from the assembly data. When `asm-main` runs, `asm-load-stdin` reads the remaining standard input as raw assembly text. The default target base is **0x600000**; a caller can replace that value before invocation. The target base is an address assigned to eventual output bytes, not either buffer's Forth-process address. Supplying a base also does not create an ELF header. C22 will follow the later driver and the explicitly supplied header input.

Source: [standalone dependency and allocation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L1-L65), [base initialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L163-L174), and [caller/driver boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L767-L785).

### Read the cells and bytes in the implementation

For the source excerpts below, Forth stack top is at the right. A stack comment `( addr len -- )` means the word consumes an address and length and returns no values. `@` fetches a 64-bit cell; `!` stores one. `c@` fetches one byte; `c!` stores the low byte. `+!` adds to a stored cell. `>r` temporarily moves a value to the return stack, `r@` copies it without removing it, and `r>` retrieves it. None of these Forth operations is the assembly token `!end`; the two languages are being read at different times.

`create` gives a data area a Forth name; `allot` reserves additional bytes without initializing them. A `variable` supplies a cell. `[lit]` and `[char]` put literal values into the implementation; they are not syntax that the assembly-input number parser accepts. These are the local contracts needed from [010's storage vocabulary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L379-L402).

The two storage triples are:

| Bytes belong to | Buffer address | Allocated capacity | Used length |
|---|---|---|---|
| Raw input | `asm-src-buf` | `asm-src-cap` = 4,194,304 | `asm-src-len` |
| Expanded text | `asm-exp-buf` | `asm-exp-cap` = 4,194,304 | `asm-exp-len` |

Both capacities are four mebibytes, or 4 × 1,048,576 bytes. Lengths count **bytes**, not tokens, definitions, or eventual machine instructions. Neither buffer is a NUL-terminated string. The length controls when reading stops. In particular, the characters `00` in expanded text are not a terminator for that text buffer.

### One reader, two selected buffers

The token reader uses three mutable cells:

- `asm-cur-buf`: address of the selected buffer
- `asm-cur-len`: number of selected bytes that may be read
- `asm-cur-pos`: zero-based offset of the next unread byte

`asm-use-src` copies the raw address and current raw length into the first two cells, then sets position to zero. `asm-use-exp` does the same for the expanded buffer. These operations select existing bytes; they do not copy or erase a buffer. The length is copied into the cursor state, not kept as a pointer to the buffer's length cell. The driver therefore selects each buffer **after** the phase that fills it.

The three character words turn that state into a small interface:

| Word | Result and state change |
|---|---|
| `asm-eof?` | True when position is at least length; no state change |
| `asm-peek-char` | Current byte, or zero at EOF; no advance |
| `asm-next-char` | Same returned byte as peek, then position increases by one |

`asm-next-char` advances even when called at EOF. The scanners guard their reads with `asm-eof?`; they do not infer EOF from a returned zero byte. This matters because a zero byte can be present within a length-bounded input.

For example, after selecting raw text `90` of length two, the initial position is zero. Two guarded calls to `asm-next-char` return ASCII `9` then ASCII `0` and leave position two. `asm-eof?` is now true. A peek returns zero and leaves position two. An unguarded next would return zero and leave position three; it would not discover another input character.

Source: [buffer selection and cursor primitives](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L55-L113).

### Capacity means the proposed next length

`asm-check-cap` has stack effect `( n cap code -- )`. Here `n` is the proposed count **after** the operation. It temporarily parks `code`, compares `n > cap`, and exits the process with that code if the comparison is true. Equality is allowed. On success it discards the saved code and returns with all three inputs consumed. Counts here are small positive values within 010's signed-comparison domain.

The two clients apply that same comparison differently:

1. `asm-load-stdin` starts raw length at zero, reads into `asm-src-buf + length`, and requests `capacity − length` bytes from descriptor 0. For each positive read result it adds the returned count, then checks **new raw length + 1** against capacity, using code 239
2. `asm-exp-emit-byte` checks **old expanded length + 1** against capacity, using code 240, before storing one byte and increasing the length

The raw loader consequently rejects a read that makes the length exactly 4,194,304, even if the input would end there. It does not attempt another read to distinguish “exactly full and finished” from “full with more coming.” Its maximum accepted completed length is **4,194,303** bytes. The expanded buffer can instead be filled through its last allocated byte: appending at old length 4,194,303 succeeds and produces length **4,194,304**. Only the next append fails.

The loader's one unused slot is not documented here as a stored NUL sentinel; the code does not write such a sentinel. It is a capacity rule. Short positive reads are accumulated in a loop. Any nonpositive read result ends that loop, and the result is discarded. Thus this implementation does not separately report a negative read error as distinct from end of input. “The complete source was loaded” requires successful reads in addition to sufficient capacity.

Every ordinary expansion separator passes through `asm-exp-emit-byte`, too. If a two-character body fits but its separator does not, the expansion can fail at that final append. The code checks individual appends; it does not preflight an entire token and roll back partially appended text.

Source: [`asm-check-cap`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L47-L53), [input loading](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L85-L97), and [expanded-byte append](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L115-L119).

## Later session: find the actual token boundaries

The first story used well-separated tokens. The same reader must also decide what to do with adjacent comments and quotes. This is where intuition from C strings or a shell can supply the wrong rule.

### Skip only the separators this implementation recognizes

`asm-skip-ws` repeatedly consumes whitespace or a comment until it reaches the next token or EOF. Its imported `space?` recognizes exactly four byte values: space (32), tab (9), LF (10), and CR (13). Other characters sometimes called whitespace, such as form feed, are not in that set.

Outside a quoted token, either `#` or `;` begins a comment. `asm-skip-rest-of-line` consumes through the next **LF**, or stops at EOF. CR alone does not end a comment, even though CR is ordinary whitespace outside comments. The skipper first consumes the comment marker, then calls this rest-of-line helper.

`asm-read-bareword` stops **before** whitespace, `#`, or `;`. That makes a comment marker work immediately after a bare token: `90#note` returns `90` first; the next call skips `#note`. No separating space is required.

Source: [010's whitespace predicate](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L93-L95) and [the comment/bareword loops](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L309-L352).

### A quote gets its special role at token start

`asm-read-token` first skips separators. If EOF follows, it returns `(0 0)`. Otherwise it records `buffer + position` in `asm-tok-start`, clears `asm-tok-len`, and inspects the next byte.

An opening double or single quote selects `asm-read-quoted`. This helper remembers the delimiter in `asm-quote-char`, consumes it, and counts it in the token length. It continues counting and consuming bytes until it consumes the first matching delimiter. It includes that closing delimiter in the returned slice. Spaces, newlines, `#`, `;`, and the other kind of quote are body bytes during this scan.

There is no escape processing. For example, the three body bytes in the direct token `"A\n"` are A, backslash, and lowercase n. They are not A followed by a newline. A backslash before a matching quote also does not prevent that quote from ending the token.

If the first byte is not a quote, `asm-read-token` selects `asm-read-bareword`. A quote encountered later in a bareword is an ordinary byte, not a new quoting region. Conversely, after a quoted token closes, a following nonspace character can begin the next token. The text `"A"90` returns `"A"` and then `90`; the text `90"A"` is one bare token. These rules follow from which scanner was selected at the initial byte.

Take this short input, with a real LF after `stop`:

```text
90#stop
"A;B" '41 42'
```

The three returned token slices are `90` of length two, `"A;B"` of length five, and `'41 42'` of length seven. The first `#` is outside quotes and removes the rest of that line. The semicolon is inside quotes and becomes a body byte. The internal space in `'41 42'` is part of its one raw token. After expansion the text is:

```text
90 41 3B 42 00 41 42 
```

The result's last two hex tokens came from the contents of one single-quoted raw token. Token boundaries need not be preserved across the transformation.

Source: [quoted and bare scans and the dispatch between them](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L329-L368).

### Matching delimiters are a premise, not a diagnosed guarantee

At EOF, `asm-read-quoted` returns without a special missing-quote error. The string handlers later use positions one through `length − 2`, on the assumption that the final byte was a closing delimiter. They do not independently check that assumption.

For example, the three-byte unterminated input `"AB`, with no following newline, is counted as a three-byte token. The double-string handler treats index two as if it were the closing delimiter, so its loop encodes A and omits B, then adds `00 `. This is a source-derived counterexample to “bad quoting must be rejected,” not a syntax to rely on. Our successful-input contract requires matching quotes.

Single-quote insertion adds another boundary worth keeping visible. It copies body bytes verbatim, including any comment markers or newlines. Those bytes will be tokenized again by the later **assembly** reader. A copied `#` may therefore begin a comment there. It is unsafe to summarize the entire expanded representation as “text with all comments and line breaks removed.” Normal raw separators disappear; bytes deliberately inserted through a single-quoted body can remain.

If a boundary trace becomes difficult, stop after identifying the next token slice. Do not try to expand and assemble it simultaneously. Knowing which bytes belong to the slice is enough to resume the next operation accurately.

## Later session: make substitution precise

Return to `jump`. The first walk made its lookup look like a dictionary operation, but the implementation is a flat array with one search rule. That rule explains redefinition, use before definition, and why aliases do not recursively expand.

### Lay out one record completely

`asm-def-rec-size` is **32 bytes**, four eight-byte cells. `asm-def-cap` is **4,096 records**. `asm-defs` reserves their product, 131,072 data bytes, and `asm-def-count` tracks the number currently in use. A record index starts at zero. `asm-def-rec` computes its address as:

```text
asm-defs + index × 32
```

The record's fields are:

| Byte offset within record | Stored value | Owner of any referenced bytes |
|---:|---|---|
| 0 | Name address | Raw source |
| 8 | Name length | Count, not a pointer |
| 16 | Body address | Raw source |
| 24 | Body length | Count, not a pointer |

`asm-def-store` receives `( name-address name-length body-address body-length -- )`. First it checks `count + 1` against 4,096 with code 243. The 4,096th record is allowed; the 4,097th is not. It computes the next record address and parks that address on the return stack. The operand stack's top is now body length, so stores proceed at offsets 24, 16, 8, then 0, consuming one field each time. Only after those stores does it increase the count.

For our record 0, the value at offset 0 is R+7, not the letters `jump` and not an instruction address. The value at offset 16 is R+12. Seeing four cells written does not imply that any pointed-to letters were copied.

Source: [record constants, allocation, addressing, and storage](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L621-L638).

### Search backward through what exists now

`asm-def-find` saves the query address and length in `asm-deff-addr` and `asm-deff-len`. It starts from the current definition count, subtracts one before examining each entry, and therefore visits newest records first. For each candidate it compares lengths first, then uses 010's `bytes-eq` to compare exactly that many bytes. There is no case folding and no required NUL terminator.

A match returns `( body-address body-length true )`, with true represented as −1. Exhausting the table returns `( 0 0 0 )`. A body address is returned, not executed. `bytes-eq` is itself a bounded comparison: it advances both addresses while the count remains positive and returns false on the first different byte. The caller's separate length check prevents a longer name sharing a prefix from matching.

Consider:

```text
DEFINE op 90
op
DEFINE op CC
op
```

The first use has only one candidate and contributes `90 `. The second declaration appends a new record without deleting the old one. The second use checks the new record first and contributes `CC `. The complete expansion is `90 CC `. **Newest preceding definition wins** describes both parts of the rule: the search is backward, and the table contains only declarations already encountered in this single walk.

Now move the declaration after its use:

```text
jump
DEFINE jump EB
jump
```

The first token has no match and is copied as `jump `. The last contributes `EB `. The later declaration never revisits the earlier output, so the complete expansion is `jump EB `. The later assembler rejects the nonhex bare token `jump` with code 246.

A missing expansion is not always visibly rejected. In `FACE DEFINE FACE 90 FACE`, the first `FACE` is copied and the last becomes `90`; the expansion is `FACE 90 `. Because `FACE` is already a valid even-length hexadecimal spelling, it can become bytes FA CE. A misspelled or undefined macro-looking name can therefore survive as literal bytes if its spelling happens to fit the byte grammar.

Source: [reverse definition lookup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L640-L660), [010's exact-byte comparison](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L453-L469), and [later bare-hex validation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L543-L559).

### Dispatch once, then move on

`asm-define-kw` holds the six bytes `DEFINE`. `asm-is-define?` first requires length six, then compares all six bytes with `bytes-eq`. Lowercase `define` is not the keyword. Recognizing the keyword happens before ordinary definition lookup.

`asm-expand-pass` clears the expanded length and definition count, then repeats this decision for tokens returned from the **selected raw cursor**:

1. Length zero means EOF: discard the returned pair and finish
2. Exact `DEFINE`: consume the next two token slices, store them as name and body, and append nothing
3. First byte is a double quote: run `asm-exp-string-double`
4. First byte is a single quote: run `asm-exp-string-single`
5. Otherwise: look up the complete token as a definition name; copy either the returned body or the original token; append one space

The two tokens after `DEFINE` can be separated by comments and newlines. There is no line-oriented “rest of this line” body rule. The implementation also does not validate that these two returned slices form a nonempty name and body. For normal inputs, supply a complete definition before use, with one unquoted body token. An incomplete declaration is outside that contract, not a promised syntax diagnostic.

At ordinary lookup, the expander duplicates the original `(start length)` so it can fall back to it. After `asm-def-find`, the stack is:

```text
original-address original-length body-address body-length flag
```

The branch consumes `flag`. On a match, `asm-exp-bytes` consumes the body pair, and two drops discard the original pair. On no match, two drops discard the returned zero pair, and `asm-exp-bytes` consumes the original. Both paths then append exactly one ordinary separator. This is how one branch avoids losing the original token before it knows whether a replacement exists.

The copied bytes go directly into the output buffer. They are not fed back through steps 2–5. For example:

```text
DEFINE op 90
DEFINE alias op
alias
```

The stored body of `alias` is the raw text `op`. Using `alias` copies `op ` once; it does not discover and apply `op`'s definition. The later assembly-token handler sees a nonhex token and reports 246. Our expander is a one-pass substituter, not a recursively rescanning C preprocessor.

Quoted definition bodies expose the same boundary:

```text
DEFINE x '90'
x
```

The declaration stores a four-byte body slice including its quotes. Using `x` copies `'90' ` through `asm-exp-bytes`; it does not call `asm-exp-string-single`. The later assembly reader can still return that quoted slice as one token, but the assembly-token handler has no quote-expansion branch. It reaches bare-hex validation and rejects the quote character with 246. If `x` were never used, storing that quoted body would not itself trigger this failure.

This is a distinction between **token reading** and **token meaning**. The later reader reuses the quote-aware scanner, but does not thereby rerun the earlier expander. Direct quotes receive special meaning only when `asm-expand-pass` itself encounters them in raw input. Likewise, `DEFINE` or quote-starting names cannot override the higher-priority dispatch cases merely by appearing in the definition table.

Source: [keyword storage and recognition](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L662-L671), [expansion loop](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L729-L762), and [later token dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L581-L594).

## Later session: open the two copy operations

The definition cases copy bytes without changing them. A direct double quote must instead turn each byte into a readable hexadecimal spelling. Both operations use `asm-cp-addr`, `asm-cp-len`, and `asm-cp-i`: a saved source address, its length, and a current zero-based index. These are reusable scratch cells, not extra fields in every definition record.

### Copy a body as text

`asm-exp-bytes` saves its `(address length)` arguments, sets the index to zero, and loops while index is below length. Each iteration fetches the byte at address plus index, passes it to `asm-exp-emit-byte`, and increases the index. The helper itself adds **no separator**; its ordinary-token caller does that afterward.

This explains the `jump` result at the byte level. With source body `EB`, index zero copies ASCII E, index one copies ASCII B, and index two stops. The expander then appends ASCII space. Nothing in this loop knows that E and B are hexadecimal digits.

`asm-exp-string-single` uses the same scratch cells but starts at index one and stops before index `length − 1`. For a well-formed token those are exactly the body bytes, excluding both delimiters. This helper appends its own separator. `'41 42'` copies five body bytes and then one space. The three body bytes in `'xyz'` would be copied just as readily; their later validity is another consumer's question.

### Encode a body as hexadecimal text

`asm-exp-string-double` also starts at index one and stops before `length − 1`. For each body byte `b`, it computes two values:

- `b / 16`, the high hexadecimal digit, using unsigned integer division
- `b and 15`, the low hexadecimal digit

For A, `b` is decimal 65. Its quotient by 16 is four and its low four bits give one. `asm-hex-digit` maps values zero through nine to the characters `0` through `9`; for ten through fifteen it adds 55, producing `A` through `F`. Thus the two encoded characters are `4` and `1`. Encoding byte 0xAF would produce uppercase `AF`.

The handler appends a space after each encoded pair, then appends `00 ` once after the body loop. For a well-formed double-quoted token containing `n` body bytes, it contributes **3 × (n + 1)** expanded bytes: three per body byte and three for the terminator. That formula counts generated text, not final output bytes. The described data occupies `n + 1` eventual bytes.

For a single-quoted body of `n` bytes, the copied text length is instead **n + 1**, including its separator. Its eventual byte count depends on what that text means. A body containing `4142` has four text bytes but describes two output bytes; a body containing a label declaration may describe no output bytes at all.

Even empty bodies differ. Direct `""` contributes `00 `, length three; direct `''` contributes only a separator space, length one. The later token reader skips the latter space and finds no token there.

These loops operate on **bytes**, not Unicode code points. If a body contains a multibyte text encoding, each encoded byte is processed separately. There is no decoding or escape-language layer hidden inside `asm-hex-digit`.

Source: [copy scratch and unchanged-byte copying](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L673-L686), [hexadecimal character generation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L688-L694), and [both string handlers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L696-L727).

## Later session: decide what a number means before parsing it

The expansion of our original fragment contains hex tokens and symbolic references. Other M1 inputs contain spellings such as `%42`. The percent sign is a **sigil**, a leading character selecting a kind and width of field. It changes the interpretation of the following characters.

The expansion pass does not lower `%42` to hexadecimal bytes. With no matching definition it copies `%42 ` unchanged. This internal expanded buffer is therefore not stock M1's fully lowered hex2 output. `130-asm.fth` combines expansion with a later assembly-token handler; that later handler calls the numeric parser when it needs a value.

### Keep four appearances of 42 apart

Each row is an independent raw input fragment:

| Raw input | Exact expanded contribution | Meaning for the later consumer |
|---|---|---|
| `42` | `42 ` | One bare hexadecimal byte, value 0x42 |
| `%42` | `%42 ` | A four-byte numeric field whose value is decimal 42 |
| `"42"` | `34 32 00 ` | ASCII `4`, ASCII `2`, then a zero byte |
| `'42'` | `42 ` | The body becomes one bare hexadecimal byte |

A numerical value, its written notation, and its eventual storage width are three separate choices. Decimal 42 is 0x2A; bare hex `42` is decimal 66. The quoted decimal-looking digits are characters with values 0x34 and 0x32. This is the same distinction that separated A's ASCII value from the bare hex digit A in the first story.

### The classifier inspects one body character

The later token handler saves its current slice in `asm-token-start-tmp` and `asm-token-len-tmp`. These two cells let helpers inspect the same token without keeping another copy of its bytes. `asm-tok-numeric?` reads that staged slice; its stack effect is `( -- flag )`.

If the whole token is shorter than two bytes, the answer is false. Otherwise it fetches the first character **after the sigil**. A decimal digit or `-` means “numeric form”; anything else means “label form.” This is a classifier, not a validation pass over the whole body.

For example:

| Staged token | Classification | Decisive fact |
|---|---|---|
| `%42` | Numeric | Body starts with `4` |
| `@-0X2A` | Numeric | Body starts with `-` |
| `&entry` | Label | Body starts with `e` |
| `%+42` | Label | `+` is not admitted as a numeric starter |
| `!` | Label branch | No body character exists |
| `%4oops` | Numeric branch | The later letters are not inspected by this test |

The last row is not a supported number. It demonstrates why “classified numeric” cannot mean “validated numeric.” Similarly, declaring a label whose spelling begins with a digit or `-` does not make it safely referenceable through these sigils: the reference would be sent to number parsing instead of label lookup. Use names beginning with another suitable nonseparator character for the examples here.

Source: [current-token staging and numeric classification](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L370-L388).

### Convert digits only under a valid-input contract

`asm-hex-char?` answers whether one byte is a hexadecimal digit: `0`–`9`, `a`–`f`, or `A`–`F`. The first range uses 010's `digit?`. The letter ranges subtract the first character, divide by six, and test whether the quotient is zero. On this seed, division is unsigned. For byte values below the range, subtraction wraps to a large cell value rather than producing a small quotient; for values above the range, the quotient is at least one. The three true/false answers are combined.

`hex-val` converts a **known valid** hexadecimal character to a value from zero through fifteen. Decimal digits subtract the ASCII value of `0`. Lowercase hex letters subtract 87, turning `a` into ten. Otherwise the valid-character premise leaves uppercase hex letters, which subtract 55. There is no independent invalid-character exit inside `hex-val`.

This direction is the inverse of the earlier `asm-hex-digit` for valid digit values. `asm-hex-digit` generates uppercase characters; `hex-val` accepts either case when its caller has met the premise.

The later bare-hex path does validate its token's characters before converting pairs. The number parser's hexadecimal branch calls `hex-val` **without** first calling `asm-hex-char?`. Do not transfer the bare-token validator's guarantees to that different call site.

Source: [digit recognition and conversion](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L212-L234) and [010's unsigned digit test](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L77-L81).

### Trace the whole number parser

`asm-parse-number` receives `( address length -- value )` for the body **after** a sigil. Its scratch state consists of six cells:

| Cell | Job during one call |
|---|---|
| `asm-dec-addr` | Body address |
| `asm-dec-len` | Body length |
| `asm-dec-val` | Accumulated magnitude |
| `asm-dec-neg` | Whether a leading minus was consumed |
| `asm-dec-hex` | Whether a hexadecimal prefix was consumed |
| `asm-dec-i` | Zero-based index of the next body character |

The `dec` part of these names is historical naming, not a restriction to decimal parsing. Every call saves its input pair and resets value, negative flag, hexadecimal flag, and index to zero.

The supported well-formed number syntax is: optional leading `-`, then either decimal digits or `0x`/`0X` followed by hexadecimal digits. At least one appropriate digit is part of our valid-input premise. There is no leading `+`, binary prefix, or octal interpretation of a leading zero.

Trace body `-0X2A`, five bytes long:

| Transition | Next index | Magnitude | Flags / reason |
|---|---:|---:|---|
| Initialize | 0 | 0 | Both flags false |
| Consume leading `-` | 1 | 0 | Negative flag true |
| Recognize `0X` at indices 1 and 2 | 3 | 0 | Hexadecimal flag true |
| Consume `2` | 4 | 2 | 0 × 16 + 2 |
| Consume `A` | 5 | 42 | 2 × 16 + 10 |
| Index equals length | 5 | 42 | Digit loop ends |
| Apply saved sign | 5 | Returned value −42 | Compute 0 − 42 |

The hexadecimal-prefix check runs after any minus sign and requires at least two remaining bytes before reading `0` and `x`/`X`. The decimal branch instead fetches each character, subtracts `0`, and updates `value × 10 + digit`. Thus decimal body `010` passes through magnitudes zero, one, ten and returns **ten**, not eight. Body `0x10` returns sixteen. The parser does not infer base from “starts with zero” alone.

Neither branch validates every character, requires a digit after a sign or prefix, or detects cell overflow. For example, a body consisting only of `0x` consumes the prefix, executes no digit iteration, and returns zero. That is a counterexample to a complete-number validator, not an additional supported notation. Keep arithmetic examples small enough that accumulation and the library's subtraction-based signed comparisons remain within their intended domain.

The parser returns a cell value. It does not write an output field, choose a width, look up a label, or subtract an instruction address. For numeric forms, the later handler uses this value as an immediate. Field-width policy and storage of its low bytes belong to C22.

Source: [all numeric-parser state and branches](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L236-L293) and [010's comparison domain](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L123-L136).

## The boundary we hand to the next chapter

We can now say precisely what expansion promises and what its next consumer expects. Assuming sufficient storage, successful input reads, matching quotes, and complete definitions, this walk consumes the raw tokens in order, stores definition slices, and writes the expanded text into a different buffer. Each ordinary token is either replaced once by a preceding definition or copied once; direct string tokens use their own translation path.

No recursive rescan follows a replacement. A sigil token normally remains symbolic or numeric text at this point, unless a complete-token definition happened to replace it. No label addresses have been calculated. No output ELF envelope has been manufactured.

The later assembly consumer assigns the following local meanings. A **field** is a fixed-width group of eventual output bytes, while a label declaration names a position and occupies no output bytes:

| Expanded token form | Eventual width | Meaning still to be completed |
|---|---:|---|
| `:name` | 0 | Record a label position |
| Even-length bare hexadecimal token | Half its character count | One byte per pair |
| `!body` | 1 | Numeric immediate, or end-relative label field |
| `@body` | 2 | Numeric immediate, or end-relative label field |
| `~body` | 3 | Numeric immediate, or end-relative label field |
| `%body` | 4 | Numeric immediate, or end-relative label field |
| `$body` | 2 | Numeric immediate, or absolute label field |
| `&body` | 4 | Numeric immediate, or absolute label field |

“End-relative” will mean relative to the address immediately after that field. Only the percent form additionally handles `%target>base`, a difference between two named labels. That extension is not automatically available on the other sigils. C22 will derive the addresses, ranges, byte order, and errors rather than requiring us to guess them here.

This is a bounded AMD64-oriented grammar. It does not promise padding directives, nibble accumulation across token separators, alignment markers, or architecture-specific ARM, AArch64, and RISC-V field adjustments. In particular, `A B` is not assembled as the byte AB: each bare token must contain a whole number of hex pairs. Quoted definition bodies and recursive aliases are also outside the expansion contract we have taught.

These limits do not amount to universal malformed-input rejection. Some malformed forms are diagnosed by later checks, some take unchecked parser paths, and an undefined even-length hex-looking name can be valid literal data. The source's compatibility and comparison comments motivate the implementation; C22 will identify the actual finite comparisons and what each establishes.

Source: [the declared scope](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L1-L38), [field interface](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L474-L490), and [bare-token whole-pair requirement](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/130-asm.fth#L543-L579).

## Practice: preserve the representation boundary

These ten tasks can be completed on paper from this chapter. No compiler, assembler, build, or generated program needs to run. [Graduated hints and worked solutions](../practice/21-solutions.md) are separate. For an independent check, write a prediction and its reason before opening them. If you are stuck, use one hint or compare one transition with the worked story; there is no need to hold the entire source listing in memory.

When an exact text result is requested, report its final separator explicitly and count text bytes separately from described output bytes. The visible marker `␠` may be used to annotate a space, but is never a real input character in these tasks.

### C21-01 — Complete the changed first walk

Keep the opening fragment's two definitions and label/reference tokens unchanged, but replace `"A"` with `"AB"`. Derive the complete expanded text, including its final separator, and calculate its text length. State which definition records change and how many eventual data bytes the direct string describes. Do not resolve either reference.

Then compare changing `"A"` to `'41'`. Identify the precise contribution that disappears; do not treat raw token length as output byte length.

### C21-02 — Trace separators before meanings

For this input, with LF after the first line, list every raw token slice and its length, then derive the expansion. Use ASCII C = 0x43, # = 0x23, and D = 0x44:

```text
90;discard
"C#D" '41 42'
```

Next consider `90#x`, followed by one CR byte, followed by `41`, with EOF immediately afterward and no LF anywhere. Which raw token is returned before the comment, and does the later `41` become a token? Finally, explain why `"A"90` and `90"A"` have different token boundaries.

### C21-03 — Choose the definition available at that moment

Trace this one input in order:

```text
FACE
DEFINE FACE 90
FACE
DEFINE FACE CC
FACE
```

Give the exact expanded text and explain the result of each lookup. Which uses can become literal bytes, and why would changing only the first `FACE` to `jump` reveal a different later failure? Explain why reading the final definition table alone cannot reconstruct the earlier lookup results.

### C21-04 — Diagnose two tempting repairs

For each independent input, predict the expanded text and identify the mistaken expectation:

```text
DEFINE op 90
DEFINE alias op
alias
```

```text
DEFINE x '90'
x
```

One reader proposes “look up aliases until no name remains.” Another proposes “send every copied quoted body through the string handler.” Explain why these are changes to this expander rather than descriptions of its current behavior. Does leaving `x` unused make its declaration fail by itself?

### C21-05 — Follow the borrowed addresses

A definition record begins at address D. It contains name-address R+7, name-length four, body-address R+12, and body-length two. R is the raw buffer address; E is the expanded buffer address.

State the byte offset and owner of each field. Explain what goes wrong if the raw bytes at R+12 are overwritten with `CC` before a later use of the record. After expansion finishes, a later assembly walk stores the name `top` from the expanded token `:top`; which buffer owns that name, and does the name's address equal the target address it labels?

Finally, explain why a shallow copy of the four record cells into another table would not repair an overwritten owner buffer.

### C21-06 — Find the exact capacity boundary

Let C = 4,194,304. Decide what happens in each independent situation and name the relevant expression or code:

1. A positive read makes raw length C−1, and the following read returns zero
2. A positive read makes raw length C
3. Expanded length is C−1 before one byte is appended
4. Expanded length is C before one byte is appended
5. The definition count is 4,095 before one complete record is stored
6. A read returns a negative result after some earlier positive reads

Then trace peek and next at cursor position equal to length. Which operation changes position, and why do normal scanners test EOF separately?

### C21-07 — Separate copy length from described bytes

For each independent direct token, derive its exact expanded contribution and length: `""`, `''`, `"A\n"`, and `'4142'`. In the third token, the input contains a literal backslash followed by n, not an actual newline; use backslash = 0x5C and lowercase n = 0x6E. State the eventual byte count where these contributions describe bare hex data.

Now suppose expanded length is capacity minus four just before direct `"A"` is handled. Which generated text characters fit, and which attempted append first fails? Use the per-byte append rule rather than assuming an atomic whole-token write.

### C21-08 — Classify, then convert

Classify `@-0X2A`, `%010`, `%+42`, `%4oops`, and `!` using only `asm-tok-numeric?`. For the two well-formed numeric bodies, trace index, base choice, and accumulated magnitude until the parser returns a value. State which examples do not satisfy the numeric parser's valid-input premise.

Explain why the parser can return zero for body `0x` even though the supported well-formed grammar requires a digit. Does bare-hex validation protect this call to `hex-val`?

### C21-09 — Repair an overconfident contract

A proposed manual says:

> Loading 130 after the compiler safely advances the allocator. It invokes itself, rejects all malformed source, and produces a ready-made ELF at the selected base. Its expanded buffer is fully lowered hex2, so every numeric sigil has already become bytes.

Rewrite this as an accurate short contract. Cover the load profile, fixed allocation assignment, caller invocation, input validation limits, retained numeric tokens, and the origin of any ELF header. Name one concrete counterexample to the claim about malformed-source rejection.

### C21-10 — Bring the boundaries together

Work independently from this input:

```text
DEFINE mark 90
:here mark "0" @010 '41 42' &here
```

Use ASCII digit `0` = 0x30. Derive the exact expanded text and its length. For every expanded token, state whether it describes a label position, bare hex bytes, a numeric field, or a label field; give its width using the local interface above. Calculate the eventual total byte count without resolving `&here`. Explain which two storage owners must remain unchanged at their respective uses.

Then change only `DEFINE mark 90` to `DEFINE mark '90'`. Identify the earliest representation whose expected contents change and the later contract that will fail. Does the target base repair that problem?

## Carry one unchanged text into C22

We began with four lines and finished with the exact 35-byte text `:top EB !end 41 00 :end 90 EB !top `, including its final space. You can now explain why the definition records point into raw input, why direct quotes and copied quoted bodies take different paths, and why numeric classification is weaker than validation. The buffers, cursor, record layout, and number parser make those distinctions inspectable in the implementation.

For a later return, close the worked expansion and reconstruct it from the original fragment. If only one contribution is uncertain, resume at that token rather than restarting every implementation session.

One question remains deliberately unanswered: **when `!end` arrives before `:end`, how can the assembler choose the correct byte without guessing?** C22 starts with this unchanged expanded text and answers that question.
