# 4. Macro expansion and rescanning

[Previous: Preprocessing regions and includes](03-preprocessing-regions-and-includes.md) · [Practice help](../practice/04-solutions.md) · [Edition coverage](../../COVERAGE.md)

Consider this small preprocessing input:

```c
#define N 7
#define ID(x) x
ID(N)
```

Why does the last line become a spelling of `7`? “Replace the names” skips the important work. A definition must survive the file that supplied it. An argument must be expanded while its original spelling remains available. A replacement must be scanned without losing the caller's position. A self-reference must eventually stop.

Our goal is to explain those transitions, including the bytes between them. By the end, you should be able to reconstruct a stored macro body, follow a call's temporary storage, and distinguish three operations: argument prescan, replacement rescan, and the direct profile's final-token tail rescan.

## Bring the region and ownership contracts

[C03](03-preprocessing-regions-and-includes.md) distinguished input regions `(base,length,position)` from output sinks `(base,position,capacity,error)`. It also showed why retaining an address does not preserve bytes in a reusable include slot. Check yourself: does popping a sink append its temporary text to the parent? Does restoring an input region restore the output position? Both answers are no. Revisit C03's parked-sink example if either distinction is uncertain.

Cells remain eight bytes; positions and lengths count bytes; stack tops are at the right. `cell[]` computes `array + index*8`. In byte displays, `␠` means one ASCII space, `\n` means one LF byte, and `[1,0]` means two numeric bytes, not printed bracket characters. A zero inside a stored body is permitted because spans carry lengths. Where we say **normalized token spelling**, redundant separating whitespace is deliberately omitted; that is not a byte-for-byte output claim.

**Evidence boundary.** All implementation descriptions refer to inspected [040-cc-prep.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/040-cc-prep.fth) at commit `7d7e1996d1753118181d43e1a413960d3a1ec24b`. The examples are manually derived, unexecuted preprocessing fixtures, not necessarily complete C programs. Unless stated otherwise, storage is sufficient, names have only the definitions shown, and conditional suppression is inactive. No build, conformance comparison, or compiler execution is claimed.

The identifier helpers from [030](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth) recognize a letter or underscore at the start and allow digits afterward. Reading a name returns a borrowed span; comparing it checks length before bytes. No copied zero terminator is needed.

The main path uses legacy preprocessing: `cc-prep-direct=0`, `cc-pp-location-enabled=0`. Later depth sections explicitly enable `cc-prep-direct`. That switch selects operator encoding, selective argument prescan, token shadows, and tail rescanning. The target-owned `cc-pp-location-enabled` independently selects location and stricter parameter-list behavior. Workspace selection independently chooses storage addresses and capacities. None is shorthand for the other two.

If the ordinary call mechanism is already familiar, attempt C4-01 through C4-03, then continue at “Direct depth: two spellings of an argument.” Their solutions are available whenever a worked comparison would help.

## Store a recipe before using it

### Six arrays describe one definition

Macro number i selects one cell in each of six parallel arrays:

| Array accessor | Meaning of cell i |
|---|---|
| `cc-macro-name-addr` | Address of owned name bytes |
| `cc-macro-name-len` | Name length; zero hides this record |
| `cc-macro-body-addr` | Address of owned replacement recipe |
| `cc-macro-body-len` | Recipe length in bytes |
| `cc-macro-params` | −1 for an ordinary object macro; nonnegative formal count for a function macro |
| `cc-macro-busy` | True while this definition's replacement is being scanned |

A macro record is therefore logically six cells, but its cells are not adjacent. The arrays are separate; each accessor returns the selected array's base. For ordinary definitions, the names and bodies live elsewhere, in `cc-macro-pool`. Their table entries point into that persistent pool rather than the reusable input file.

`cc-macro-record` checks the proposed count, stores five supplied fields, initializes busy to zero, then increments `cc-macro-count`. It stores the supplied spans without copying; the caller must provide the required lifetime. Ordinary definitions supply pool-owned spans. `cc-macro-add`, used for ordinary predefined objects, copies both spans first and supplies tag −1. C05 opens the target's dynamic tags −2 and −3 for location macros; they are special object dispatch cases, not formal counts. Those dynamic entries use static name bytes and an empty `(0,0)` body, rather than ordinary pool-owned replacement text.

Pool writes reuse the sink mechanism. `cc-pp-to-pool` parks the current sink and selects the pool at `cc-macro-pool-pos`; `cc-pp-from-pool` commits its new position and resumes the old sink. `cc-pp-pool-copy` remembers the destination address, copies a span, and returns the new owned span. It does not retain the original span's lifetime.

### Adjacency decides the definition's kind

After recognizing `define`, `cc-prep-handle-define` skips spaces/tabs and reads the name. A missing name makes this handler return without defining anything. It copies a present name to the pool before parsing the rest.

On our main path, the very next byte determines the kind:

```c
#define ID(x) x
#define OTHER (x)
```

`ID` is function-like because `(` immediately follows its name. `OTHER` is object-like because a space intervenes; its body is `(x)`. This definition-time test is different from invocation-time lookahead, which can cross spaces and newlines before a call's `(`.

`cc-pp-read-params` puts borrowed name spans into two fixed formal-name arrays used for this definition. It records `x` at index zero for `ID`, then requires a closing parenthesis. `cc-pp-param?` later searches these arrays with `cc-name-find`. The names need survive only through body encoding, not future expansion. There are at most sixteen formal records; attempting a seventeenth fails with 48. `cc-pp-need-rparen` rejects a missing required closer with 47. This older parser is not a general strict C parameter grammar; do not infer all malformed-list rejections from the valid example. The location-enabled parser's distinct checks and logical-name storage belong to C05.

### Body bytes are instructions to substitution

`cc-pp-copy-body` walks the rest of the definition line. It replaces a formal's identifier with byte 1 followed by its zero-based index. Ordinary names remain names; they are not expanded now. Thus `ID(x) x` stores `[1,0]`, not the one-byte letter `x`.

This encoding makes later substitution independent of parameter spelling. `ADD(a,b) ((a)+(b))` stores the following exact recipe, with ASCII punctuation shown as characters:

```text
( ( [1,0] ) + ( [1,1] ) )
```

Spaces in this display separate components for reading; the supplied body `((a)+(b))` has none. Its recipe has eleven bytes: seven punctuation bytes and four marker bytes.

The body walker protects whole literals, so `"x"` is not a formal use. It groups digit-starting runs with `cc-pp-copy-number`, so letters inside `0x1F` are not looked up as names. Comments become one blank. A backslash followed by LF is removed, with one newline owed. Leading spaces/tabs are skipped before copying, and `cc-pp-trim` removes trailing spaces/tabs. Ordinary names such as `N` stay available for lookup at invocation time, even when their definitions appear later.

Let pool base be B, initial pool position P, and initial record count M. The two opening definitions produce:

| Record | Name span | Body span | Tag; busy |
|---|---|---|---|
| M | `(B+P,1)` contains `N` | `(B+P+1,1)` contains `7` | −1; 0 |
| M+1 | `(B+P+2,2)` contains `ID` | `(B+P+4,2)` contains bytes 1,0 | 1; 0 |

The pool advances by six bytes and the count by two. M need not be zero: the legacy pass first installs eleven shim definitions. Defining macros does not put their replacement bodies into the final source sink; only the retained directive newlines reach that sink here.

### Newest wins; undef does not uncover an older version

`cc-macro-find` delegates to [030's `cc-name-find`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth): search from count−1 downward, compare length first, then bytes. A later `#define N 8` appends a record. Lookup finds that record before the earlier `N`.

`#undef N` repeatedly performs the same search and sets each matching name length to zero. It forgets both versions. It neither uncovers the earlier value nor reduces count nor reclaims pool bytes. Definitions and hidden records occupy storage until the next pass resets count and pool position.

The default arrays physically provide 4,096 entries. Legacy policy nevertheless permits only 1,024 records and 65,536 pool bytes. Direct policy permits the selected array capacity, normally 4,096, and 262,144 pool bytes. The opt-in `cc-prep-direct-workspace` selects six 4,608-entry arrays in one mapping: each array occupies 36,864 bytes, at successive offsets 0, 36,864, 73,728, 110,592, 147,456, and 184,320. The text pool stays the same. Its matching default selector restores the original array bases. Neither selector migrates live records or resets their count, so select before initializing and loading a pass. Record exhaustion uses 34; pool exhaustion uses 35.

## Keep temporary text alive for exactly one call

The persistent pool solves the include-lifetime problem. Calls have a different lifetime: intermediate text must survive nested scans but can expire together when its call finishes.

`cc-pp-scratch` is a 2,097,152-byte arena. `cc-pp-scratch-top` is an address of the first free byte, not a byte count. `cc-pp-scratch-alloc` checks the proposed top relative to the arena base, advances top, and returns the old address. Exhaustion uses 43.

A temporary sink reserves 65,536 bytes, but retains only what it writes:

```forth
: cc-pp-temp-begin
  cc-pp-temp-cap cc-pp-scratch-alloc  [lit] 0  cc-pp-temp-cap  [lit] 37
  cc-pp-sink-push ;

: cc-pp-temp-end
  cc-pp-out @ cc-pp-out-pos @                      ( a u )
  2dup + cc-pp-scratch-top !
  cc-pp-sink-pop ;
```

Suppose top is S and a temporary writes five bytes. Begin reserves `[S,S+65536)`. End returns `(S,5)`, sets top to S+5, and resumes the parked sink. It releases unused room, not the five retained bytes. A later temporary starts after them. Only the enclosing call's final restoration of its saved top releases the entire call's records and text.

This separation matters during nesting. While a temporary is active, its full reserved interval stays below the next allocation. While its completed text is still needed, only its used prefix must stay below that next allocation. A saved address into either interval remains valid for the appropriate lifetime; restoring top too early would let the next operation overwrite it.

One active temporary's output overflow uses 37; total arena exhaustion uses 43. The parked-sink array has 34 four-cell records. Source comments justify that bound from at most 32 full temporary reservations fitting in 2 MiB, plus the source and pool sinks. Push/pop have no separate general stack-capacity check. This is a resource relationship for this call pattern, not a promise of exactly 32 macro calls: record blocks, retained text, and active reservations all compete for scratch.

## Scan a replacement without becoming a file

Replacement scanning changes the region while keeping the selected sink:

```forth
: cc-pp-expand-text
  cc-prep-src-addr @ >r  cc-prep-src-len @ >r  cc-prep-src-pos @ >r
  cc-prep-in-file @ >r  cc-prep-at-line-start @ >r
  cc-prep-src-len ! cc-prep-src-addr !  [lit] 0 cc-prep-src-pos !
  [lit] 0 cc-prep-in-file !
  bl cc-prep-emit-byte  cc-pp-scan-fwd  bl cc-prep-emit-byte
  r> cc-prep-at-line-start !  r> cc-prep-in-file !
  r> cc-prep-src-pos !  r> cc-prep-src-len !  r> cc-prep-src-addr ! ;
```

The five saved values are address, length, position, file flag, and line-start flag. The incoming length is above its address, so storing length first consumes the pair correctly. Scanning starts at zero with `in-file=0`; a `#` in replacement text cannot start a directive. Restore happens in reverse order. It leaves all bytes appended to the sink in place.

The two emitted spaces prevent accidental joining to neighboring source text. If an object `NEG` contains `-1`, the source `2-NEG` produces `2-␠-1␠`, not a spelling containing `--`. These spaces are deliberate byte-level machinery; the later lexer ignores them. `cc-pp-scan-fwd` is a deferred Forth entry to the scanner already taught in C03, permitting the scanner and expansion words to call each other. A Forth word implementing a scan is not a C token emitted by that scan.

For the ordinary object `N`, `cc-pp-expand-object-body` sets its busy cell, scans its stored `7`, then clears busy. A plain file-level `N` therefore contributes exactly `␠7␠`. The caller's region resumes immediately after its original `N`.

Now replace the definition with `#define SELF SELF`. Outer lookup starts expansion and sets SELF busy. Inner lookup finds the same record busy and copies its spelling instead of entering it again. The contribution is `␠SELF␠`; busy returns to zero. Busy describes the definition's current expansion interval, not whether the spelling has ever been seen. Direct mode additionally remembers suppression on individual copied tokens; we will need that distinction after substitution.

The public object/call wrappers also bracket an invocation-location context through `cc-pp-location-begin` and `cc-pp-location-end`; `cc-pp-ident` saves and updates the current location around identifier handling. For this chapter, their interface is to preserve the relevant invocation location across nested replacements. C05 opens the physical-file cursor, logical location, and dynamic macro machinery. They do not change the bytes in our N/ID trace.

## Recognize a call, then collect its arguments

A function-like name alone is not a call. `cc-pp-paren-ahead?` saves the current position, scans spaces, tabs, LF newlines, and LF/CRLF continuations, and tests for `(`. On success it consumes `(` and adds crossed newlines to the owed count. On failure it restores the original position and commits no newline debt. The caller then copies the name, and ordinary scanning handles the bytes after it.

Thus `ID \n(7)` can call ID, but this lookahead does not skip a comment between the name and parenthesis. Do not replace its precise byte test with “skip every possible whitespace-like construct.” Definition adjacency and invocation lookahead deliberately answer different questions.

After successful lookahead, `cc-pp-expand-call-body` saves output position and scratch top. It reserves sixteen argument records, each an address/length pair occupying sixteen bytes. The 256-byte block is allocated even for a one-argument call.

`cc-pp-collect-args` starts at parenthesis depth one. Another `(` increments depth; `)` decrements it. A comma ends an argument only at depth one. Literals and comments are walked whole in drop mode, so their internal commas and parentheses are not structural delimiters.

For `PAIR((1,2),"x,y")`, the first borrowed argument is `(1,2)` and the second is `"x,y"`, each five bytes. The inner comma belongs to nested parentheses; the literal's comma belongs to the literal. The comma between them alone splits records. After recording the second slice, collection consumes the outer `)` and returns two. Brackets and braces do not change this collector's depth, so do not silently extend the rule to them.

The raw slices still point into the input region. The collector has advanced past their text but has not overwritten it. This is safe because the enclosing input owner remains live throughout prescan and substitution. `cc-pp-duplicate-args` then copies the used records, sixteen bytes per actual argument. It duplicates the spans, not their payload, preserving raw records before prescan updates the first block to point at expanded text.

The local failure rules are worth reading exactly:

- Reaching end-of-region before the closing parenthesis fails with 44
- Recording a seventeenth actual fails with 46
- The arity guard fails with 45 only when actual count exceeds formal count **and** actual count exceeds one

Collection records one slice even for `F()`; that slice has length zero. Missing formal slots substitute empty text. Consequently the implementation is not enforcing a universal “actual count equals formal count” rule. These are implementation boundaries, not recommendations for writing portable macro calls.

## Work the whole `ID(N)` call

Return to `N=7` and `ID(x)=x`. We trace only the final call's contribution, excluding definition-line newlines and the final source newline. Let scratch top on entry be S. Its bytes are initially free; output position is O.

On the legacy path, `cc-pp-expand-args` visits records from last to first and replaces each raw span with a span of its fully scanned temporary text. Direct mode makes a selection first, but ID's ordinary use selects its argument and gives the same bytes here.

| Completed transition | Scratch top and live text | Reason |
|---|---|---|
| Collect `N` | S+256; record 0 points at raw one-byte `N` | Fixed sixteen-slot block; no payload copy |
| Duplicate used record | S+272; second record also points at raw `N` | Preserve original spelling |
| Begin argument temporary | S+272+65536 while active | Reserve output room above both record blocks |
| Prescan argument; end temporary | S+277; five bytes `␠␠7␠␠` at S+272 | Argument scan adds two spaces; nested N expansion adds two more |
| Substitute `[1,0]`; end its temporary | S+284; seven bytes `␠␠␠7␠␠␠` at S+277 | Ordinary substitution wraps the expanded argument in another pair |
| Rescan replacement into caller's sink | Top stays S+284; output advances O→O+9 | Replacement scan adds its own edge pair |
| Complete call | Top returns to S | Both record blocks and both temporary texts expire |

The final nine-byte contribution is `␠␠␠␠7␠␠␠␠`: four spaces, digit 7, four spaces. Each added pair has an owner. If you predicted only `␠7␠` for the prescanned argument, you counted the object expansion but omitted the scan of the argument region containing that object.

Busy timing is equally important. ID is **not** marked busy while its argument is prescanned. It becomes busy only after substitution has finished, while the seven-byte replacement is scanned. A nested ID in the argument can therefore expand during prescan. N has its own shorter busy interval inside that prescan.

Why do nested calls not destroy the outer substitution setup? The call keeps its macro index, records, counts, and saved lifetime values on data/return stacks while prescanning. It installs `cc-pp-sub-raw`, `cc-pp-sub-recs`, and `cc-pp-sub-n` only afterward. Substitution itself copies selected argument text rather than expanding it recursively. Further calls occur when the completed replacement is rescanned. These phases make the globals usable without pretending all scanner state is saved in every frame.

**Pause point:** keep the two live spans `(S+272,5)` and `(S+277,7)`, and the restored caller position after `)`. On returning, explain which scan adds the final two spaces and why restoring top to S before that scan would be premature.

### Repay source newlines once, outside the replacement

A macro-region newline becomes one space and increments `cc-pp-pending-nl`. A macro-region comment also becomes one space while its swallowed newlines are counted. A backslash-LF outside a literal in macro text disappears and owes its newline. The file-level identifier path flushes owed newlines after expansion, once the outer file region has been restored.

For the exact invocation bytes `ID(\nN)`, the raw argument is LF then N. Prescan produces `␠␠␠7␠␠`, length six, and owes one newline: one leading scan space, one space replacing LF, then N's `␠7␠`, then the closing scan space. Substitution and replacement scanning add two spaces each. The call therefore contributes five leading spaces, `7`, four trailing spaces, and then the owed LF. A following source newline is still separate.

Do not infer a universal original-file diagnostic mapping. [020's emitter/error contract](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/020-cc-arena.fth) tracks the flattened progress counter, and emitting internal marker byte 10 can spuriously increment it, an inherited limitation documented in the historical chapter. Location macros have their own C05 contract.

## Direct depth: two spellings of an argument

Enable `cc-prep-direct` for this section; the location gate may remain zero. Direct encoding adds `[2,k]` for stringification of formal k and byte 3 for `##`, outside literals. `cc-pp-copy-hash` recognizes a second adjacent `#`; otherwise it requires a formal name after optional blanks. A missing identifier fails with 42; an identifier that is not a known formal fails with 47. Neither is treated as ordinary replacement text at this operator boundary.

Consider:

```c
#define N 7
#define BOTH(x) #x, x
BOTH(N)
```

BOTH's exact recipe is bytes `2,0,44,32,1,0`: stringize parameter zero, comma, space, ordinary parameter zero. One argument needs both spellings:

- Raw record: `N`
- Expanded record: `␠␠7␠␠`

Stringification reads the raw record, giving the string token `"N"`. Ordinary substitution reads the expanded record. The result's **normalized token spelling** is `"N", 7`. Expanding the raw record in place without preserving another record would lose the ability to produce `"N"`.

### Prescan only when the recipe requires it

`cc-pp-arg-expanded?` inspects the stored recipe for an ordinary use of a parameter that is not next to a paste marker. It tracks paste adjacency across body whitespace, skips stringize markers, and uses `cc-pp-paste-ahead?` for the other side. If it finds one ordinary use, `cc-pp-expand-used-args` prescans the argument once, even if several occurrences need its expanded form. Uses confined to `#`, `##`, or no occurrence require no prescan.

Those unprescanned slices still contain physical newlines. `cc-pp-count-raw-lines` counts each LF into pending debt. Otherwise deleting an unused argument, or using it only as a string, would silently delete its source-line contribution. This is independent of whether its spelling contributes a final token.

### Stringification is a small byte-state machine

`cc-pp-stringify` emits opening and closing double quotes. Between them it tracks quote kind, escape state, pending space, and whether meaningful text has begun. Outside literals, spaces/tabs/LF/CR and comments become a pending separator. It emits one separator only before the next meaningful byte, removing leading and trailing whitespace. Inside a quoted literal it preserves the literal's content and escape relationships. Every copied double quote or backslash is itself escaped for the newly enclosing C string.

With `#define STR(x) #x`, the call `STR( a /*note*/ + "b" )` yields the single string token `"a + \"b\""`. The spaces around the argument disappear; the comment contributes separation; the quoted `b` remains quoted inside the new string. The stringizer's private address/length cursor and peek/step helpers walk the raw slice without borrowing the main scanner's region. Its comment helper skips through block-comment closure or up to a line-comment newline. It removes backslash-LF pairs before whitespace processing. Do not generalize this into complete CRLF or universal translation-phase splicing.

### Pasting chooses raw text, joins it, then rescans

```c
#define CAT(a,b) a ## b
CAT(N,ame)
```

The stored body is `[1,0]␠[3]␠[1,1]`. Neither formal has an ordinary use away from paste, so neither is prescanned. The first formal is recognized as immediately before paste and selects raw `N`. At byte 3, substitution removes trailing output whitespace, sets a joining flag, and trims following body whitespace. The second formal sees that flag and selects raw `ame`. Operand edges are trimmed with `space?`, which here recognizes space, tab, LF, and CR. The replacement text is exactly `Name` before rescan adds surrounding spaces.

With no macro named Name, the normalized final spelling is `Name`, not `7ame`. If an object `Name` is defined as `9`, the rescan can instead yield normalized `9`. Pasting is not an exception that returns final, unscanned output.

`cc-pp-sub-argument` centralizes raw-versus-expanded selection and supplies `(0,0)` for a missing formal slot. Direct ordinary substitution still adds its separator blanks; missing text and surrounding punctuation remain separate questions. The legacy substitute recognizes only ordinary markers. The direct substitute additionally dispatches stringize and paste and maintains its joining state. This is a bounded text engine, not a full token-paste validity checker or a complete placemarker implementation.

## Direct depth: suppression must travel with a token

A busy cell answers “is this definition expanding now?” It cannot alone answer “was this particular copied token already suppressed?” Consider:

```c
#define SELF SELF
#define ID(x) x
ID(SELF)
```

In direct mode, argument prescan expands SELF, then meets its inner SELF while the definition is busy. The engine copies that spelling and marks its first output byte as **unavailable for further expansion**. Clearing the definition's busy cell does not clear this token's mark.

| Stage | Exact text | Marked byte offset |
|---|---|---:|
| Completed argument prescan | `␠␠SELF␠␠` | 2 |
| Completed substitution | `␠␠␠SELF␠␠␠` | 3 |
| Replacement rescan output | `␠␠␠␠SELF␠␠␠␠` | 4 |

During the last scan SELF's busy cell is already zero, but `cc-pp-ident-work` checks the mark before macro lookup. It copies the token without another expansion. The spelling alone cannot tell you this state; the character S and its unavailable flag occupy different storage.

`cc-pp-flag-address` maps scratch addresses into a scratch shadow and selected-source addresses into a source shadow. Raw input, includes, and persistent bodies have no shadow. One lazily allocated mapping holds 2 MiB of scratch flags followed by 7 MiB of source flags, one per text byte. The active source interval uses the selected source capacity; spare shadow capacity does not enlarge it. Initialization rejects a source capacity larger than that fixed 7 MiB bound with 43, and mapping failure also uses 43. Legacy mode leaves the mapping inactive.

Selecting a sink derives its flag address; the four-cell sink record needs no fifth field. Fresh byte emission clears the destination flag so reused storage does not inherit an old token's state. `cc-pp-copy-marked-byte` captures the source flag before emitting, then reapplies it at the destination. This order also handles copying to the same address. `cc-pp-emit-bytes` uses that deferred copy binding, so ordinary argument substitution preserves marks. Only the identifier's first byte needs the suppression mark for lookup; a copied span still forwards every byte's metadata.

The direct tail rescan also checks unavailability. Pasting has a stricter boundary: `cc-pp-paste-bytes` checks every byte in a supplied raw operand and fails with 47 if any is marked. That includes a marked token away from the pasted edge or beside an empty operand. The historical chapter describes this rejection as deliberately narrower than complete token/placemarker rules. No metadata byte is inserted into the C spelling.

## Direct depth: meet the parenthesis in the outer region

Replacement scanning alone does not join two input regions. Use:

```c
#define ALIAS F
#define F(x) x
ALIAS(7)
```

While scanning ALIAS's stored body, the active region contains only `F`. Its function lookahead reaches that region's end and finds no `(`. It copies F. `cc-pp-expand-text` finishes and restores the original file region, whose next byte is `(`. Without another operation, that opportunity has passed.

On the legacy path, normalized output is therefore `F(7)`. F was emitted before the scanner resumed at the parenthesis; emitted output is not automatically fed back as input.

On the direct path, object expansion remembers its starting output position O and calls `cc-pp-rescan-tail` after restoring the outer region and clearing ALIAS's busy flag. At that point the newly emitted bytes are `␠F␠`. The tail operation:

1. Searches backward within `[O,current-output)` past trailing whitespace
2. Finds the final identifier-continuation run and verifies its first byte can start an identifier
3. Rejects a marked, unknown, busy, or object-like candidate
4. Uses ordinary call lookahead in the **restored outer input region**
5. On success, rewinds output position to the start of F and expands its call

For this case the rewind is O+1, retaining ALIAS's initial separator. F consumes the outer `(7)` and yields normalized `7`. The original call suffix is consumed once by F's collector. The tail operation does not merely scan the old body again; it combines a final emitted name with unread surrounding input.

Function expansion uses the same tail hook after its call scratch has been released. The text needed for tail lookup is already in the output sink. Location-rescan state is bracketed separately so C05's location interface can distinguish this cross-region call. `cc-pp-rescan-tail-fwd` is bound to the real tail word after its definition, just as the scanner uses a deferred entry.

This is a final-token strategy, not general rescanning of every emitted token against every future input. The [historical chapter's suppression discussion](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/22-the-preprocessor.md) records remaining boundaries involving deferred-empty tails, stringification of inserted argument padding, and preprocessing numbers with exponent signs. Arbitrary token joins in replacement bodies and complete variadic/hide-set behavior are outside the established contract. Our small derivations do not remove those limitations.

## Reassemble the identifier decision

The pieces now give an inspectable order for `cc-pp-ident-work`:

1. Read a complete borrowed identifier span
2. In a conditional-expression expansion, recognize special `defined` before expanding its operand; C05 opens that interface
3. If this token is unavailable, copy it
4. Find the newest macro record; if busy, copy and, in direct mode, mark the token
5. If no record exists, copy it
6. For a negative parameter tag, enter object dispatch; otherwise look ahead for a call and expand only on success
7. After expansion returns to a file region, flush owed newlines

C03's scanner protects literals, comments, and digit-starting runs before reaching this decision. Its macro-text branches replace newlines/comments with separators and retain the appropriate newline debt. The later [050 lexer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth) then receives expanded bytes and skips separating whitespace/comments; this chapter has not evaluated a C expression.

One additional reusable operation, `cc-pp-line-slice`, borrows the rest of a directive up to its terminating newline, advancing the caller there without consuming that terminator. It walks literals, comments, and recognized continuations in drop mode to find the boundary; their original bytes remain in the borrowed slice. C05 uses that span with these same temporary sinks and expansion regions for conditional expressions, computed includes, and line-control operands. Its expression evaluator is supplied by the later [100 module](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth), not by the macro engine.

## Practice: predict the intermediate representation

Use the stated profile and paper states. [Graduated hints, checked derivations, and changed cases](../practice/04-solutions.md) are separate.

1. **C4-01 — Encode before expanding.** On the legacy path, encode `#define ADD(a,b) ((a)+(b))`. Then define `N` as `7`, redefine it as `8`, and undefine it. Give the formal indices, exact ADD recipe length, lookup results after each N directive, and the effect on record count/pool ownership. Compare `#define ADD (a,b)` with the original.
2. **C4-02 — Find argument boundaries.** With `#define PAIR(a,b) a+b`, collect `PAIR((1,2),"x,y")`. Give each raw span, nesting transitions, actual count, and ending cursor. Does `PAIR([1,2],3)` collect two arguments? Explain the applicable failure guard without evaluating any C expression.
3. **C4-03 — Reconstruct one call's lifetime.** With N and ID from the opening, start at scratch top S. Derive every retained top, both temporary lengths, final exact call bytes, and ID's busy interval for `ID(N)`. Diagnose a design that restores top to S immediately after substitution.
4. **C4-04 — Preserve two spellings.** In direct mode, encode `BOTH(x) #x, x` and `CAT(a,b) a ## b`. With `N=7`, predict normalized results for `BOTH(N)` and `CAT(N,ame)`, stating which arguments are prescanned. Then add `#define Name 9` and repeat the paste prediction. What happens to LF bytes in a raw-only argument?
5. **C4-05 — Separate two reasons not to expand.** In direct mode, trace the mark positions for `ID(SELF)` with SELF defined as itself. Then compare legacy and direct `ALIAS(7)` with ALIAS defined as F and `F(x)` as x. Identify the active region that supplies each decisive parenthesis test. Why would clearing all marks when a busy cell is cleared change the first mechanism?

## What to carry into C05

A definition owns its recipe in the pool. A call borrows raw arguments, retains expanded text in scratch, substitutes the recipe, and scans the result with the definition busy. Each completed call releases its scratch lifetime together. Direct mode additionally chooses raw spellings for operators, carries token unavailability outside the byte stream, and can recognize a final function name against the restored outer region.

Those capabilities explain a concrete result; they do not claim a complete C preprocessor. [C05](05-conditionals-and-profile-extensions.md) uses them to choose active groups and expand directive operands, then opens the separate location/profile machinery.

### Source-scope ledger

All rows refer to the pinned 040 source unless another module is named. Evidence is inspected source; worked outputs are manual derivations, not fresh test results.

| Source mechanism | Explanatory home here | Remaining interface |
|---|---|---|
| Six arrays, pool copy/record/add/find, workspace array selectors, define/undef, formal lookup, copy-body/trim | Stored recipes, adjacency, ownership, newest lookup, precise bounds | C05: location-enabled formal parser and target predefines |
| Scratch allocation, temp begin/end, sink push/pop capacity relationship | Reserve, retain, release; exact ID trace | C03: basic sink-copy mechanics |
| Expand-text and deferred scan/dispatch/tail seams | Five saved fields, separators, non-file regions | C05: conditional/directive dispatch completion |
| Paren lookahead, collect/duplicate/expand arguments, legacy substitution | Borrowed spans, delimiters, exact arity guard, prescan order, call lifetime | No expression evaluation assumed |
| Direct hash encoding, trim/string helpers, stringify, ordinary-use detection, raw-line count, direct substitute | Two spellings, selective prescan, string-state example, paste trace | Full token/placemarker behavior explicitly outside scope |
| Busy-cell, object/call bodies and wrappers, identifier dispatch | Busy interval and phase sequencing | C05: dynamic object tags and location wrapper internals |
| Flag addressing/initialization/selection, marked copying, paste rejection | Per-token unavailability and fixed shadow mapping | C02: mapping primitive; C03: ordinary emitter |
| Tail state and tail rescan binding | ALIAS trace and final-token boundary | C05: location-rescan interpretation |
| Line-slice, identifier equality/requirements, number grouping, macro scanner/comment branches | Borrowed directive operand, protected constructs, owed newlines | C05: `defined`, line-control/splice gates; later lexer/expression chapters |

The historical chapter supplies context and documented limits. It does not substitute for current definitions or establish learner success. A useful next check is whether you can explain an intermediate state in a changed exercise without copying the trace.
