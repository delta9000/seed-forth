# C04 practice: hints, worked solutions, and changed cases

[Return to Macro expansion and rescanning](../chapters/04-macro-expansion-and-rescanning.md)

These solutions are manually checked derivations from the chapter's pinned source, not executed compiler results. Keep eight-byte cells, byte-length spans, sufficient storage, and the profile named in each question. The fixtures test the preprocessor; they need not be complete C programs. `␠` is one byte 32, and normalized token spelling deliberately omits surplus separating whitespace.

Choose the help that fits your attempt. The first hint points toward a representation; the next identifies a decisive transition; the last supplies a partial result. After checking the solution, try a changed case before reading its answer. If the notation itself is the obstacle, C03's region/sink examples provide a smaller restart point.

## C4-01 — Encode before expanding

### Hints

1. Definition-time parameter lookup uses formal positions, not argument values
2. Count each ordinary parameter marker as two bytes, including parameter zero's zero byte
3. The body begins with two ASCII opening parentheses followed by bytes 1,0

### Worked solution

For `#define ADD(a,b) ((a)+(b))`, the formal table has `a` at zero and `b` at one. The function record has parameter count two and busy zero. The recipe is:

```text
40 40 1 0 41 43 40 1 1 41 41
```

These are decimal byte values: `(` is 40, `)` is 41, and `+` is 43. There are eleven bytes. The repeated numeric 1 in the second marker has two roles: its first byte says ordinary substitution; its second says parameter index one. A zero byte does not terminate the recipe because the body span supplies length eleven.

Let the first N record be j. `#define N 7` appends it and lookup returns j, whose body is `7`. `#define N 8` appends j+1 and lookup returns that newer record. The earlier record still occupies its array slots and pool bytes.

`#undef N` finds j+1 and sets its name length to zero. It searches again, finds j, and zeroes that length too. A third search fails. Count is unchanged by undef, both bodies remain physically stored, and neither record can match the nonempty name N. Across these two definitions, two records and four pool bytes were added: one name byte and one body byte per definition. Undef reclaims none of them.

With `#define ADD (a,b)`, the space after ADD changes the definition kind. The tag is −1, the formal table is empty for body encoding, and the ordinary object body is the five ASCII bytes `(a,b)`. It does not encode a or b as parameters. This is an adjacency decision at definition time, not a judgment that text with parentheses is always a function macro.

A plausible wrong answer expands a named object while copying the body. The actual body encoder looks up formal names only; ordinary macro lookup belongs to later scanning.

### Changed case

Start a fresh relevant setup:

```c
#define LATER N
#define N 7
LATER
#define N 8
LATER
```

Predict the normalized spelling of each LATER use before reading on.

The first yields `7`; the second yields `8`. LATER persistently stores the one-byte name N. Each use scans that body and consults the table as it exists then. It does not freeze N's value at definition time. If an `#undef N` precedes another LATER use, that use yields normalized `N`, because lookup now fails and copies the name. The lifetime of stored bytes and the time of lookup are different properties.

## C4-02 — Find argument boundaries

### Hints

1. The collector starts at depth one after the call's opening parenthesis
2. Only parentheses change its depth. A literal walker consumes quoted content whole
3. In `PAIR((1,2),"x,y")`, the separator between the arguments is at byte offset 10, counting P as offset zero

### Worked solution

The complete invocation has seventeen bytes. PAIR occupies offsets 0–3; the outer `(` is at 4. Collection begins at position 5 with depth one.

| Event | Depth after event | Position after event | Record effect |
|---|---:|---:|---|
| Inner `(` at 5 | 2 | 6 | None |
| Comma at 7 | 2 | 8 | None: nested comma |
| Inner `)` at 9 | 1 | 10 | None |
| Comma at 10 | 1 | 11 | Record `(base+5,5)`, spelling `(1,2)` |
| Literal at 11–15 | 1 | 16 | Whole `"x,y"` consumed; internal comma ignored |
| Outer `)` at 16 | 0 | 17 | Record `(base+11,5)`, then finish |

The actual count is two. Both raw records borrow input bytes; neither allocates a string payload. The call's first 256-byte record allocation has room for sixteen pairs, regardless of this count.

For `PAIR([1,2],3)`, `[` and `]` do not affect parenthesis depth. The raw slices are `[1`, `2]`, and `3`: three actuals. The count guard computes three greater than two formals, and three greater than one, so it fails with 45. No C-expression parser is consulted to decide whether brackets ought to protect this comma.

Counting every comma without considering literals would split `"x,y"` incorrectly. Treating every paired punctuation kind like parentheses would incorrectly preserve `[1,2]`. The taught rule needs both its inclusion and its boundary.

### Changed cases

1. Replace the first raw argument with `1/*, )*/`. The comment walker consumes the internal comma and parenthesis as comment contents. The call still collects two arguments, with that whole comment inside the first borrowed slice.
2. Use `PAIR(1)`. It collects one actual. One is not greater than two, so no arity error occurs; the missing second formal substitutes empty text. Normalized result is `1+`, without any claim that this result is a valid complete C expression.
3. Define `ZERO()` as `9` and invoke `ZERO(7)`. The collector still returns one actual. Although one exceeds zero formals, the guard's second test, one greater than one, is false. That guard therefore permits the call. In legacy mode the unused actual is prescanned before the constant body yields normalized `9`. This is why “exact arity is checked” would overstate the implementation.

## C4-03 — Reconstruct one call's lifetime

### Hints

1. Reserve the entire sixteen-record block before thinking about text lengths
2. The duplicate block contains only the used records: one sixteen-byte pair here
3. Prescan has two nested scans, one for the argument N and another for N's replacement 7

### Worked solution

For the opening definitions, the one raw record points at N in the caller's region. Let the call's original scratch top be S.

| Retained state | Top | Contents needed by later phases |
|---|---|---|
| Collected records | S+256 | Record zero points at raw N |
| Raw-record duplicate | S+272 | Duplicate also points at raw N |
| Completed argument prescan | S+277 | Five bytes `␠␠7␠␠`; original record now points here |
| Completed substitution | S+284 | Seven bytes `␠␠␠7␠␠␠` |
| After final rescan, before release | S+284 | Final nine-byte contribution already copied into caller's sink |
| After release | S | None of this call's scratch remains owned |

The argument temporary is reserved at S+272, temporarily advancing top to S+272+65,536. End shrinks it to five bytes. Substitution's temporary is then reserved at S+277 and shrinks to seven bytes. Reserve size, retained length, and final sink length answer different questions.

The final call contribution is decimal bytes `32 32 32 32 55 32 32 32 32`, length nine. Digit 7 is byte 55. The final source newline, if present, follows this contribution separately; the two earlier definition-line newlines also lie outside it.

During prescan, N is busy only while its `7` body is scanned. ID is still not busy. During the replacement rescan, ID is busy; after that scan it is cleared. The direct ordinary-argument path yields the same bytes and retained tops for this fixture because parameter zero has an ordinary use and no suppression mark is involved.

Restoring top to S immediately after substitution would end the ownership of both retained argument text and the replacement before the replacement is read. This particular digit-only replacement might appear to work because its last scan needs no further scratch allocation. The design would still be wrong: a replacement containing a function call could allocate over unread bytes. The correct release point follows the completed replacement scan, when its contribution is already owned by the caller's sink.

### Changed cases

First use `ID(7)` rather than `ID(N)`. There is no nested object scan. The retained expanded argument is `␠7␠`, length three, so top becomes S+275. Substitution retains five bytes and top becomes S+280. Final call output is `␠␠␠7␠␠␠`, length seven. The 256-byte record block and sixteen-byte duplicate do not shrink merely because the argument text was easier to expand.

Next consider `ID(ID(7))`. Predict only the normalized result and busy timing. The inner call expands during the outer argument prescan, while outer ID has not yet set its busy cell. It yields normalized `7`, which survives outer substitution and rescan. An account that sets outer ID busy before argument prescan would suppress this nested call too early.

If exact spaces were wrong but the storage trace was right, recount scan boundaries rather than relearning arena allocation. If a retained address could be overwritten while still needed, return to the reserve/retain/release example before adding nested calls.

## C4-04 — Preserve two spellings

### Hints

1. Stringize and paste choose raw records; ordinary substitution chooses expanded records
2. Prescan is selected per argument by all its uses, not independently repeated for every occurrence
3. BOTH's recipe is decimal bytes `2 0 44 32 1 0`

### Worked solution

BOTH has one formal. Its recipe's first marker `[2,0]` asks for stringification; its last marker `[1,0]` is an ordinary use. Therefore parameter zero is prescanned once. Raw N stays available while its expanded record becomes `␠␠7␠␠`.

The stringizer receives raw N and emits the string token `"N"`. Ordinary substitution receives the expanded record. The result's normalized token spelling is `"N", 7`. Producing `"7", 7` would mean selecting the wrong record for the stringizer.

CAT's exact stored bytes are:

```text
1 0 32 3 32 1 1
```

Formal zero sits before paste; formal one sits after it. Neither has an ordinary use elsewhere. Both therefore remain unprescanned. Substitution trims operand-edge whitespace and joins raw N with raw ame, producing exact temporary text `Name`. It rescans this text afterward.

Without a matching Name definition, the normalized result is `Name`. After `#define Name 9`, it is `9`: the paste first forms Name, then rescan finds its object definition. It still does not form `7ame`; N's raw spelling is selected before the join.

Any LF bytes in a raw-only or unused actual are counted into `cc-pp-pending-nl` by `cc-pp-count-raw-lines`. Raw text can be omitted or changed by the operator without losing that owed source-newline count. Where BOTH does prescan, the normal macro-region scanner accounts for its newlines instead; do not add a second raw-only count for the same argument.

### Changed case: selection changes whether a nested call is attempted

Start with these definitions and invoke the last line:

```c
#define BAD(a) a
#define DROP(x) 9
DROP(BAD(1,2))
```

Predict whether BAD's arity guard is reached in each profile.

In direct mode, DROP's recipe contains no use of its formal. The argument is not prescanned; its raw newlines, if any, are counted. Substitution builds `9`, then replacement rescan produces normalized `9`. BAD is never looked up through an argument-expansion scan.

In legacy mode, every actual is prescanned even if unused. The nested BAD call collects two actuals for one formal. Both comparisons in the arity guard are true, so it fails with 45 before DROP's replacement is produced.

This comparison tests a change in work performed, not merely a change in final spacing. It does not mean every raw-only construct is valid C; it shows which source path actually examines this nested invocation.

## C4-05 — Separate two reasons not to expand

### Hints

1. Busy belongs to a table record; unavailable belongs to a particular emitted identifier
2. In ID(SELF), SELF's busy interval has ended before ID's replacement scan begins
3. In ALIAS(7), the region containing only F cannot see the parenthesis after ALIAS in the file

### Worked solution

For direct `ID(SELF)`, the inner SELF encountered during argument prescan is copied while SELF is busy. Its first byte is marked. The mark moves with the text:

| Completed phase | Exact text | Length | Mark offset |
|---|---|---:|---:|
| Argument prescan | `␠␠SELF␠␠` | 8 | 2 |
| Substitution | `␠␠␠SELF␠␠␠` | 10 | 3 |
| Replacement rescan | `␠␠␠␠SELF␠␠␠␠` | 12 | 4 |

SELF's busy cell is zero during the last phase. ID's busy cell is true. The early unavailable check, rather than SELF's busy value, prevents another SELF expansion. Clearing every mark when the busy cell is cleared would erase the history needed by that later scan. Fresh emission instead clears only the reused destination byte's old mark; a forwarding copy then restores the copied source mark as needed.

A plain file-level SELF is shorter: it contributes `␠SELF␠`, with a direct-mode mark at offset one. There is no enclosing argument prescan or substitution to add the other separator pairs.

For the separate ALIAS/F setup, scanning ALIAS's body installs a one-byte F region. F's first lookahead fails at that region's end. After restoration, the caller's region points at the `(` in `ALIAS(7)`.

- Legacy stops the replacement operation there. It later copies `(7)` from the caller, yielding normalized `F(7)`
- Direct tail scanning finds the final emitted F, checks its mark/busy/kind, and performs a second lookahead in the restored caller. That test succeeds, so it rewinds the sink to F and invokes the function macro. Normalized result: `7`

A failed lookahead restores its position. A successful tail lookahead consumes the opening parenthesis before collection. The decisive difference is where the input cursor points, not whether F's bytes were stored correctly.

### Changed cases

First keep ALIAS and F but use `ALIAS+7`. The tail candidate still names F, but the outer lookahead sees `+`, restores the position, and makes no call. Both profiles yield normalized `F+7`. The tail rule needs both an eligible final name and a following call opener.

Then restart SELF with a visible suffix:

```c
#define SELF SELF+1
#define ID(x) x
ID(SELF)
```

In direct mode, prescan produces normalized `SELF+1` with the copied SELF marked. Substitution forwards that mark. Replacement rescan leaves the marked name alone, so normalized output remains `SELF+1`.

On the legacy path there are no token shadows. Prescan still stops the immediate self-reference through the busy cell and yields normalized `SELF+1`. After that cell clears, ID's replacement scan encounters an unmarked SELF and expands it once more; its inner SELF is suppressed by busy, and the already-present `+1` remains after the newly expanded `SELF+1`. Normalized output is `SELF+1+1`.

This manually derived comparison makes the distinct roles observable. Busy stops re-entry during the current replacement scan. Direct token unavailability carries an earlier suppression decision through later scans. Neither statement alone describes the whole mechanism.

## Choose the next check from your attempt

- If the recipe was wrong, encode one two-formal body before tracing any invocation
- If the recipe was right but bytes differed, label every scan and substitution boundary that adds spaces
- If a name expanded at the wrong time, write the active input region, definition busy value, and token mark separately
- If all five explanations held up independently, C05's conditional operand and computed-include examples reuse these mechanisms in a different context

An immediate corrected answer shows what the worked comparison helped you do. A later fresh attempt with the solution closed provides a different check; neither reading fluency nor confidence alone establishes that result.
