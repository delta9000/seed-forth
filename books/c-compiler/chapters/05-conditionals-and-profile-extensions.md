# 5. Conditional preprocessing and profile extensions

[Previous: Macro expansion and rescanning](04-macro-expansion-and-rescanning.md) · [Practice help](../practice/05-solutions.md) · [Edition coverage](../../COVERAGE.md)

A header can define a name only once, choose one of several implementations, and report a filename different from the file that was opened. Those effects need different kinds of state. A macro table answers whether a name exists. A conditional stack decides which text survives. A location record says where a macro invocation belongs. Confusing the three produces plausible but wrong explanations.

Our goal is to **trace which groups are selected, which expressions are evaluated, and which profile permits each extension**. We will first complete the common conditional mechanism, then follow computed includes and the optional source-location path. You can finish the main-path example before taking the extension sections.

## Bring the table and the region contract

[C03](03-preprocessing-regions-and-includes.md) supplied the active input region, shared output sink, retained directive newline, and include restore frame. [C04](04-macro-expansion-and-rescanning.md) supplied newest-first macro lookup, copied definitions, temporary sinks, and replacement rescanning. Stacks below run bottom-to-top from left to right; addresses and lengths count bytes; cells are eight bytes. `\n` denotes one LF byte, `\r` one CR byte, `\\` one literal backslash in escaped byte descriptions, and `␠` one ASCII space. Trace rows show post-state.

Two entry questions: if `N` is defined as `0`, is it present in the macro table? Does restoring an input region undo bytes already appended to the output? The answers are yes and no. If either feels uncertain, revisit C04's lookup or C03's include trace before proceeding. No lexer implementation or expression-parser technique is a prerequisite here: we will give the evaluator a narrow, explicit interface.

**Evidence boundary.** This chapter follows inspected [040-cc-prep.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth), [100-cc-expr.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth), and the named target selectors at revision `bbcc1732152af2d884737272eed870d2410ffe8e`. Every result is a manual prediction, not an executed observation. Fixtures are preprocessor inputs, not necessarily complete C programs. Assume successful I/O, sufficient storage, a bound evaluator, and no other matching user definitions unless stated. Neither semantic correctness, learner validation, nor a current Linux bootstrap follows from these traces.

## Diagnostic locations in this edition

The direct driver can enable `cc-pp-line-map-on`. Arena records retain next,
output line, source line, filename length and filename bytes; includes save the
parent resume line, and `#line` adds a new mapping. This supports error 228's
source file/line without changing the default numeric diagnostics. The current
filename helper is shared with `__FILE__`. See [the map and lookup](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth#L1261-L1306)
and [include resume](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth#L1761-L1848).

## Presence is different from replacement value

Consider these definitions:

```c
#define N 0
#define EMPTY
#define ALIAS N
```

All three names exist. `EMPTY` has a zero-length body; it still has a live name. `#ifdef N` therefore selects its first group. `#ifndef N` does not. Neither directive expands N to zero first. The shared helper `cc-pp-defined-name?` requires an identifier, calls `cc-macro-find`, and asks whether the returned index is nonnegative.

`defined` supplies the same question inside a `#if` or `#elif` expression. While `cc-pp-in-if` is true, identifier dispatch recognizes the seven-byte spelling `defined` before ordinary macro lookup. `cc-pp-defined` accepts `defined N` or `defined(N)`, reads the operand as a name, queries the table, and emits the single byte `1` or `0`. Spaces and tabs are allowed at its explicit blank-skipping boundaries. A missing name uses error 42; a required closing parenthesis that is absent uses 47. Do not extend that small operand reader into a promise that arbitrary token forms are accepted there.

For the definitions above:

| Question | Result and reason |
|---|---|
| `defined(N)` | `1`: membership, irrespective of body `0` |
| `defined(EMPTY)` | `1`: an empty body is still a definition |
| `defined(ALIAS)` | `1`: query ALIAS itself, not the result of expanding it |
| Ordinary `N` in a condition | Expands to `0`, whose evaluator value is false |
| `defined(MISSING)` | `0` if there is no live matching record |

After `#undef N`, lookup no longer finds N. C04's all-matches invalidation also prevents an older N definition from reappearing. ALIAS remains defined, even though expanding it now leaves the identifier N. The later evaluator turns remaining ordinary identifiers into zero. That last rule belongs to the evaluator, not to `defined` or to the macro table.

This distinction makes an **include guard** possible: a header tests for a marker name, defines that marker, then supplies its contents. The marker need not represent a numerical truth value.

## A conditional stack records three states

One boolean cannot distinguish “no branch has been selected yet” from “a branch has already been selected.” Both discard the current text, but only the first may accept a later `#elif` or `#else`.

The actual codes are:

```forth
[lit] 0 constant cond-take
[lit] 1 constant cond-done
[lit] 2 constant cond-seek
```

- **take:** retain ordinary text in the current branch
- **seek:** discard ordinary text; a later branch may still be selected
- **done:** discard ordinary text and do not select another branch in this group

These are state codes, not Forth truth flags: `take` happens to be zero. `cc-pp-cond` has 64 cells; `cc-pp-cond-depth` counts live cells; `cc-pp-cond-top` addresses the last. `cc-pp-cond-push` checks proposed depth against 64 with error 38 before storing. At depth zero, `cc-pp-skipping?` is false. Otherwise it asks whether the innermost state differs from `take`.

Why is inspecting only the top sufficient? Opening a group while already skipping pushes `done`, regardless of its written condition. That new top cannot become `take`. When it closes, the still-inactive parent is exposed again. A child never overrides an inactive ancestor.

### All six directives in one transition table

`cc-pp-cond-directive` matches six stored directive spellings. It runs before dispatch checks whether ordinary directives are active.

| Directive | Starting situation | Action |
|---|---|---|
| `#if expression` | Enclosing text active | Evaluate; push `take` for nonzero, otherwise `seek` |
| `#ifdef name` | Enclosing text active | Query membership; push `take` if present, otherwise `seek` |
| `#ifndef name` | Enclosing text active | Query membership; invert it; push the corresponding state |
| Any of those three openers | Enclosing text skipped | Push `done`; do not evaluate or query its operand |
| `#elif expression` | Top `take` | Replace top with `done`; do not evaluate |
| `#elif expression` | Top `seek` | Evaluate; change to `take` only if nonzero |
| `#elif expression` | Top `done` | Leave `done`; do not evaluate |
| `#else` | Top `seek` | Replace with `take` |
| `#else` | Top `take` or `done` | Replace with `done` |
| `#endif` | Any existing top | Decrement depth, exposing the parent |

The last three directive names require an open group; `cc-pp-need-group` uses error 41 at depth zero. The table describes these transitions, not a complete validator of every malformed conditional-directive sequence. In particular, there is no additional “else already seen” state in this representation.

Here is a complete paper input; every displayed line ends in LF:

```c
#if 0
#error hidden
#if NEVER_EVALUATED
lost_a
#endif
#elif 1
kept
#else
lost_b
#endif
```

| Line handled | Conditional stack afterward | Consequence |
|---:|---|---|
| 1 | `[seek]` | Evaluate `0`; retain no branch yet |
| 2 | `[seek]` | Do not dispatch `#error` |
| 3 | `[seek, done]` | Do not send `NEVER_EVALUATED` to the evaluator |
| 4 | `[seek, done]` | Drop `lost_a` |
| 5 | `[seek]` | Close only the inner group |
| 6 | `[take]` | Evaluate `1`; select this branch |
| 7 | `[take]` | Copy `kept` |
| 8 | `[done]` | The selected branch has ended |
| 9 | `[done]` | Drop `lost_b` |
| 10 | `[]` | Close the outer group |

The exact predicted output is six LF bytes, `kept`, then four LF bytes: fourteen bytes total. Skipping removes the lost words, not their line endings. C03's newline branch runs before ordinary skipping, and its skipped-construct walker counts internal newlines in whole comments and literals. A `#` inside such a construct does not become a directive.

This is stronger than saying the nested condition “evaluates false.” It is **not evaluated at all**. Even so, the scanner still has to walk its source safely to find boundaries and matching directives. Inactive source is not an unrestricted bag of ignored bytes.

## Borrow an evaluator without learning its parser yet

The preprocessor needs a value for `#if`, not instructions for the eventual C program. It supplies expanded bytes to this deferred interface:

```forth
defer cc-pp-eval
```

Its contract is `( a u -- n )`: read one constant expression in the byte span, return its value, and leave the surrounding reader usable. Zero means false; nonzero means true. For this chapter we need only decimal `0`, `1`, `4`, ordinary identifiers as zero, and `&&` as “both operands are nonzero.” Parentheses can group an expression. Detailed token classification, precedence, conversions, and evaluation machinery belong to the later lexer and expression lessons.

`cc-pp-if-value` owns the preprocessing half:

```forth
: cc-pp-if-value
  cc-pp-scratch-top @ >r
  cc-pp-line-slice
  true cc-pp-in-if !
  cc-pp-temp-begin cc-pp-expand-text cc-pp-temp-end
  [lit] 0 cc-pp-in-if !
  cc-pp-eval 0= 0=
  r> cc-pp-scratch-top ! ;
```

Read this as a lifetime sequence. Save scratch top S. Borrow the rest of the directive line, leaving its terminating newline unread. Select a temporary output sink. Expand that span with the special `defined` behavior enabled. Finish the sink, obtaining `(address,length)` while restoring the previous sink. Clear the special mode, evaluate while the temporary text is still alive, normalize the value to a Forth flag, then reclaim the temporary storage by restoring S.

For `#if defined(N) && N` with `N=4`, the borrowed slice is `␠defined(N)␠&&␠N`. Its outer replacement scan adds one space at each edge; `defined(N)` emits `1`; ordinary object expansion contributes `␠4␠`. Thus the temporary bytes are exactly `␠␠1␠&&␠␠4␠␠`, eleven bytes. The evaluator sees the equivalent token expression `1 && 4` and returns one. The temporary's edge spaces do not appear in the final source: this sink exists to obtain a decision.

Restoring scratch before evaluation would violate that ownership contract. Restoring the main output position afterward would violate a different contract: sink pop has already restored the destination, and the final output has not consumed this expression text.

### What the supplied provider promises

In `100`, `cc-pp-eval-text` is bound to `cc-pp-eval`. It saves the lexer state using `cc-lex-mark` and separately saves `cc-src-len`. It temporarily gives the reader endpoints for this span relative to `cc-src-buf`, clears a pending token, sets preprocessing-constant mode, and calls the constant parser. The endpoints can be negative offsets when the main buffer is mapped; both use the same base. This is a borrowed region, not a copy into the main source buffer.

The provider requires end-of-input after the expression; leftover tokens use error 129. On successful return it clears preprocessing mode and restores source length and lexer state. That explains why the deferred call can be used now without pretending the later parser has already been taught. Failures exit through the compiler's error path; these are not exception-safe rollback promises.

### Optional depth: the evaluator has its own LP64 gate

The small-number traces below do not need the conversion machinery. Record this independent profile gate, then return when a condition depends on signedness:

```forth
: cc-cx-typed?  cc-cx-pp @ cc-target-lp64 @ and ;
```

Typed preprocessing is enabled by **preprocessing-constant mode AND LP64**, not by `cc-prep-direct`, and not by System V alone. Under that contract, values carry signed/unsigned 64-bit maximum-width state. Explicit unsigned literals, or literals above the signed maximum, select unsigned state. Ordinary mixed arithmetic/comparison combines operand signedness; shifts use the left operand's state. Consequently the manual predictions are false for `-1ULL < 0`, and true for `(0u - 1) > 0`. Do not transfer those examples to the older non-LP64 evaluator path without a separate derivation.

The provider's `&&`, `||`, and `?:` parse dead arms while suppressing their evaluation through `cc-cx-skip`. That is a different mechanism from skipping a nested `#if`, whose expression never reaches the provider. These interface facts do not establish complete standard-C expression support.

## Put the common mechanisms together

Use the legacy profile and two files. This preserves C01's `ROWS=4` name while isolating preprocessing from triangle execution. The root contains:

```c
#include "shape.h"
#include "shape.h"
#if defined(ROWS) && ROWS
ROWS
#else
99
#endif
```

The successfully opened `shape.h` contains:

```c
#ifndef SHAPE_H
#define SHAPE_H
#define ROWS 4
#endif
```

Every line ends in LF. Initially neither user name exists, conditional depth is zero, and the output is empty.

1. The first include opens the header. `#ifndef SHAPE_H` finds no record and pushes `take`. The two definitions append copied names/bodies to the persistent macro storage. SHAPE_H has an empty body; ROWS has body byte `4`. `#endif` returns the stack to empty. The header contributes four newlines and no other bytes.
2. Returning restores the root input region. Its still-unread include-line newline contributes a fifth newline. The copied macro definitions survive reuse of the include slot.
3. The second include is still opened and scanned. Now SHAPE_H exists, so `#ifndef` pushes `seek`. Both definitions are inactive and add no records. Closing returns to empty. This contributes four header newlines plus one root newline, bringing output length to ten.
4. The root `#if` expands `defined(ROWS)` to `1` and ordinary ROWS to `4`; the evaluator selects `take`. Its directive newline brings output length to eleven.
5. The ordinary ROWS line emits `␠4␠\n`, four bytes. `#else` changes `take` to `done`; the line `99` is skipped. Their newlines and the closing directive's newline still appear.

The final output is eleven LF bytes, `␠4␠`, then four LF bytes: **eighteen bytes, fifteen of them LF**. Output-progress line is sixteen before the final reader rewind. There are two added user records, not four. With the eleven legacy predefines, the table count is thirteen. The final conditional depth is zero.

The guard suppresses repeated *contents*, not repeated loading of the file. The record survives because it owns copied bytes, not because the first header remains in its include slot. This joins the three chapters' invariants: input regions return, macro definitions persist for the pass, and the output keeps accumulating.

**Pause point:** retain `(stack=[], macro count=13, output length=10)` just after the second include returns and its newline is copied. On resuming, predict the remaining eight output bytes without rereading the numbered explanation.

## Extension: computed include operands

This section requires `cc-prep-direct` to be true. The source-location flag is not required. C03 already supplied literal quote/angle operands and physical search paths; C04 supplied expansion.

```c
#define HEADER "a.h"
#include HEADER
```

When the first nonblank operand byte is already `"` or `<`, `cc-prep-handle-include` uses the literal path. Otherwise direct mode expands the rest of the directive into a temporary sink. Legacy mode goes directly to the literal parser and does not acquire computed-header behavior.

For this fixture, `cc-prep-skip-blanks` has already consumed the space after `include`, so the borrowed slice is `HEADER`. Its expansion is `␠␠"a.h"␠␠`, nine bytes: the outer scan and the object-replacement scan each add one space at each edge of the five quoted-header bytes. The handler then:

1. Saves the original file region and line-start flag, and installs the temporary span as an operand-reading region
2. Requires an opening quote or angle bracket, a nonempty name, and a matching closer
3. Requires that only surrounding spaces/tabs remain after that single computed operand
4. Uses the unchanged including-file identity for path search and the normal include descent
5. Restores the original directive region and scratch top after the include returns

Two lifetimes nest here. The temporary operand must remain alive during header parsing/loading. The loaded header gets its own include save/restore interval. Returning from the header does not itself finish the outer computed-operand interval.

A bare unknown macro, an empty expansion, or `"a.h" extra` fails with 30. An expanded angle operand containing a `space?` byte (space, tab, LF, or CR) also fails with 30: the corresponding whitespace-sensitive angle-token joining is not represented. The quoted-header grammar skips escaped bytes while finding the closer but does **not** C-string-decode the filename. Backslashes remain filename bytes. Do not import `#line`'s separate string decoder into include search. The exact-one-operand restriction described here belongs to the computed path; it is not a newly claimed check on every literal include.

## Extension: three different meanings of location

This section requires target-enabled `cc-pp-location-enabled`. “Direct” in a helper comment is not enough to select it. The profile table below states how it is enabled.

Keep three coordinates separate:

| Coordinate | State and purpose |
|---|---|
| Physical filename/line | Actual including-file path and LF count within that file |
| Logical filename/line | Presumed name and physical-line offset used by dynamic location macros |
| Flattened reader/output line | `cc-src-line`, used by the compiler's existing diagnostics |

`#line` changes the second. It does not rename a disk file, alter include search, or remap compiler diagnostics.

### Per-file state and invocation state

At each include depth, the location arrays keep base, end, physical cursor, physical line, logical offset, logical-name bytes, and name length. `cc-pp-location-enter` starts a file at physical line one, offset zero, cursor at base, and name length −1. That sentinel means “use the physical name.” An empty logical name instead has length zero.

`cc-pp-location-at` accepts an address in the current physical file. It counts LF bytes from the cached cursor to that address, then adds the logical offset. If argument prescan revisits an earlier raw slice, the physical cursor and line restart from the file base; the logical offset survives. Addresses outside the live file range do not change the current invocation location.

`cc-pp-ident` saves the old invocation line, updates it for the identifier's source address, performs expansion, then restores it. Replacement text stored elsewhere consequently inherits its invocation location. `cc-pp-location-begin`/`end` track nesting and remember whether the outer expansion was object-like. C04's tail rescan temporarily uses `cc-pp-location-rescan` with that object-root state, preserving the location context when an object alias discovers a function call in surrounding text. These wrappers supply location ownership, not a new macro expansion algorithm.

For example, with offset zero, define `HERE` as `__LINE__` on physical line one and invoke HERE on physical line eight. The copied replacement spelling lives in the macro pool, outside the current file range. It therefore uses the invocation line eight, yielding `␠8␠` through the ordinary object wrapper. It does not report the definition line or a line counted inside the pool.

### Dynamic macros are table entries

`cc-prep-location-builtins` enables the location flag and records `__LINE__` with parameter tag −2 and `__FILE__` with tag −3. Ordinary object macros use −1; function-like macros use nonnegative parameter counts. The object dispatcher recognizes the dynamic tags and formats their answers instead of scanning a fixed body.

Thus `defined(__LINE__)`, later shadowing, and `#undef __LINE__` use ordinary table lookup. There is no separate immortal name exception. Each preprocessing pass reinstalls the target's entries.

`cc-pp-location-number` repeatedly divides an unsigned number by ten, saves remainder digits in a 24-byte reverse-digit buffer, then emits them backward. `cc-pp-location-filename` selects the logical name, or the physical name when the sentinel remains, or `<stdin>` when the physical main name is empty. It surrounds the result with quotes. Quote/backslash bytes get a preceding backslash; printable bytes 32–126 are copied; other bytes become three-digit octal escapes. The answer is source text representing a string, not raw arbitrary filename bytes pasted into C.

### `#line` installs an offset after validating an operand

`cc-prep-handle-line` borrows and expands its operand in temporary storage, then parses a bounded grammar. `cc-pp-line-blanks` handles the accepted whitespace; `cc-pp-line-decimal` requires decimal **1 through 2,147,483,647**. Leading zeroes remain decimal. A sign, suffix, arithmetic expression, unknown name, or extra token is not accepted. There may be one ordinary byte-string filename, but no adjacent string concatenation or wide/Unicode form.

The filename helpers decode simple escapes (`\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v`, escaped quote/apostrophe/question-mark/backslash), up to three octal digits, and a nonempty hexadecimal escape. Decoded NUL, a value above 255, unsupported escapes, missing closure, or more than 1,023 decoded filename bytes uses error 49. Hex escapes consume consecutive hex digits; `"\x41a"` is not byte `A` followed by `a`, and exceeds this byte range.

For a small decoding/encoding trace, the filename operand `"a\042b\134c\011"` decodes to six bytes: a, quote, b, backslash, c, tab. A subsequent dynamic filename answer is `"a\"b\\c\011"`, thirteen source bytes including its surrounding quotes. Octal 042 became byte 34 and is re-emitted with a backslash-quote; octal 134 became byte 92 and is escaped; the tab is emitted as three-digit octal. The logical filename stores decoded bytes, not the original escape spelling.

After the complete expanded operand is valid, the original region is restored. Its terminating physical newline remains unread. If its physical line is P and the requested following line is N, the new offset is `N - (P + 1)`. An omitted filename retains the current logical name; `""` deliberately sets an empty one. The scanner still copies the ordinary directive newline.

Active GNU-style numeric markers such as `# 40 "virtual.c"` fail49 under this location gate. They are not an alternate accepted spelling of `#line`. In inactive groups neither line control nor active numeric-marker rejection runs. Without the gate, these forms are dropped as unrecognized directives.

### A virtual filename cannot redirect an include

Set the physical root name to `/project/src/main.c`; register `headers/` and `/sdk/include/` in that order. Enable direct semantics and target locations. The root's five physical lines are:

```c
#line 40 "virtual.c"
__LINE__
#define HEADER "detail.h"
#include HEADER
__FILE__ __LINE__
```

Suppose the first candidate `/project/src/detail.h` opens and contains exactly `__FILE__ __LINE__\n`. This is a paper premise, not a filesystem observation.

| Event | Physical state | Logical result or search consequence |
|---|---|---|
| Validate line 1 | Physical line 1; offset was 0 | Install offset `40-(1+1)=38`; name `virtual.c`, length 9 |
| Expand line 2 | Physical line 2 | `__LINE__` emits `40` |
| Define HEADER on line 3 | Physical line 3 | Definition persists; no filename change |
| Include on line 4 | Parent physical path unchanged | Quote candidates are `/project/src/detail.h`, then `headers/detail.h`, then `/sdk/include/detail.h`, stopping at first success |
| Enter header | Its own physical line 1; offset 0; no virtual name | Emit `"/project/src/detail.h" 1` |
| Return and expand root line 5 | Parent offset still 38 | Emit `"virtual.c" 43` |

Relative include directories are relative to the process working directory. An angle operand would omit the includer's-directory candidate; an absolute name would be attempted directly. None of these choices uses `virtual.c`.

The exact predicted flattened output is `\n40\n\n"/project/src/detail.h" 1\n\n"virtual.c" 43\n`. The header's newline precedes the parent's retained include-line newline. Logical line 43 and that flattened output's line count answer different questions.

## Extension: continuations have local, bounded rules

A **continuation** here is backslash followed by LF, or, where the handler supports it, backslash followed by CRLF. Avoid the tempting model “delete every continuation everywhere.” This text engine uses distinct strategies for comments, ordinary file text, directive prefixes, and formal parameter names.

### Comments and prefixes

Under `cc-pp-location-enabled`, `cc-pp-splice-skip` can look past a run of LF/CRLF continuations without keeping its cursor movement. `cc-pp-at-spliced?` uses that lookahead between two delimiter bytes. A slash, continuation, and star can therefore begin a block comment; a star, continuation, and slash can close it. Inside a `//` comment, deleting a continuation means the comment continues onto the next physical line.

`cc-pp-drop-splice` disposes of the removed newline according to the current put mode. For a copied comment it owes the newline instead of placing it inside the comment: inserting it there could end a `//` comment early or split a closer. The file-comment path flushes this debt after the complete comment.

For exact input bytes `/\\\n*x*\\\r\n/Q\n`, that is slash–backslash–LF–star–x–star–backslash–CR–LF–slash–Q–LF, the copied comment becomes `/*x*/`. Two newlines are owed and then emitted. The predicted output is `/*x*/\n\nQ\n`, nine bytes. Physical Q is on line three; the delimiter bytes are contiguous in output. This trace depends on the location gate, not just on direct macro operators.

At directive boundaries `cc-prep-directive-prefix` uses the same walkers. It temporarily selects line-control mode 2; the line-operand reader uses −1, and ordinary mode is zero. Lookahead uses `put-drop` and restores the source position; actual consumption uses `put-count`. The prefix recognizes space, tab, vertical tab, form feed, complete comments, and supported continuations before `#` or between `#` and the name. `cc-prep-directive-blanks` accepts a CR as part of CRLF there; a bare CR fails49. The dispatcher rejects a continuation immediately after the directive name with 49 rather than joining a split name. An unterminated block comment uses 49 when the walker has a nonzero line-control mode. This is not a universal unterminated-comment check on all file content.

`cc-prep-skip-to-eol` also walks line comments under the location gate, so a `/*` inside the trailing `//` text remains inert. Prefix and skipped-region walking still matter when no ordinary tokens survive.

### Ordinary file text preserves safe boundaries

The location-enabled file scanner removes the backslash and optional CR, but **emits the physical LF** at accepted ordinary-source boundaries. It leaves `at-line-start` false, so the byte after that continuation does not begin a newly recognized directive.

`cc-pp-file-splice-safe?` accepts the beginning of a region; a following space, tab, LF, vertical tab, form feed, or end-of-region after looking through further continuations; a preceding `space?` byte (space/tab/LF/CR); a complete preceding block-comment closer; or one of these complete punctuators:

```text
, ; ( ) [ ] { } ~
```

`cc-pp-splice-next` also treats a following CRLF ending as newline. These tests preserve token boundaries when substituting a newline for the continuation. They do not join split identifiers, numbers, or multi-byte punctuators.

For `int a;\\\nint b;\n`, the semicolon makes the boundary safe; predicted output is `int a;\nint b;\n`. For `fo\\\no`, neither side supplies a safe boundary, so the ordinary-file path uses 49. Likewise `+\\\n+` is not silently joined into `++`. This continuation branch occurs before the skipped-file branch; inactivity alone does not bypass its boundary check.

The ordinary literal walker `cc-pp-literal-splices` and C04's stringizer remove backslash-LF. Do not extend that statement to CRLF: the ordinary literal path still preserves that form. Non-file replacement scanning also has its existing LF-removal path. Within a `#line` operand, `cc-pp-line-splice-boundary` rejects unsupported nonliteral LF joins with non-whitespace on both sides; it does not turn the shared engine into arbitrary token joining. Comments, literals, and the stated whitespace boundaries retain their own handling.

### Parameter names need a different result

When `cc-pp-location-enabled` is true, definition reading selects `cc-pp-read-direct-params`, despite the word's broader-sounding name. `cc-prep-direct` alone does not select it. The grammar is an empty list or comma-separated **distinct identifiers**, at most sixteen. Missing names, duplicates, trailing commas, comments, and variadic forms use 47; the seventeenth formal uses 48. Separators are spaces/tabs and supported continuations, not form feed or vertical tab.

`cc-pp-param-splices` removes LF/CRLF continuations and owes one newline each. `cc-pp-param-ident` copies a logical identifier into a shared 65,536-byte temporary sink, bounded by 37. Thus the physical fragments `ar`, continuation, `g` become the one logical parameter `arg`, not two names separated by whitespace. Those temporary spellings survive until replacement-body encoding finishes, then the definition restores its saved scratch top.

A continuation between an intact macro name and `(` preserves function-like adjacency. A continuation splitting the macro's own name uses 47; that grammar is not the parameter-name join. Arbitrary joins inside replacement-body tokens remain outside this local repair. The encoded-parameter-index-10 diagnostic caveat from C04 also remains: a marker byte equal to LF can affect preprocessing's flattened line counter. Logical source locations do not establish universal diagnostic-line equality.

## Choose policy, target, and storage independently

The common machinery is easier to reuse when selection is explicit. Here are three named combinations; they are not automatic consequences of loading a file.

| Choice | Legacy/default | Direct TinyCC-style | SysV plus explicitly selected larger workspace |
|---|---|---|---|
| `cc-prep-direct` | 0 | True | True, selected by `cc-sysv-enable` |
| Locations during scan | Disabled | Disabled with default/non-SysV target hook | Enabled by `124`'s hook when `cc-target-sysv` is true |
| Computed includes, direct macro operators/rescans | No | Yes | Yes |
| Location macros, `#line`, newer prefix/comment/source/parameter rules | No | No | Yes |
| Include storage/depth | Four 256-KiB slots; at most 4 | Packed default 1-MiB pool; at most 32 | Selected packed 7-MiB pool; at most 32 |
| Macro-record bound | 1,024 | 4,096 in default workspace | 4,608 in selected direct workspace |
| Macro-text bound | 65,536 bytes | 262,144 bytes | 262,144 bytes |
| Input / expanded-source capacities | 1 / 2 MiB | 1 / 2 MiB unless separately selected | 3 / 7 MiB with `cc-io-direct-workspace` |

`cc-prep-direct-workspace` maps/selects six macro arrays and the include pool; `cc-prep-default-workspace` reselects their default storage. Neither migrates live bytes nor resets counts. The text pool is unchanged. `cc-io-direct-workspace` separately selects the raw/source/output storage. Merely calling `cc-sysv-enable` does not select either larger workspace. The default arrays physically have 4,096 slots even though legacy policy limits publication to 1,024.

Conditional depth remains 64 (error 38), active temporary text remains bounded by 65,536 (37), and total scratch remains 2 MiB (43). C03's strict input/include-read bound still needs one unused byte, while ordinary emission allows exact capacity. Expanded output uses its selected capacity and error 36. More workspace does not imply more grammar or a larger conditional stack.

### Predefined names express target policy

When direct preprocessing is false, `cc-prep-builtins` installs eleven ordinary records:

```text
NULL=0                 EOF=0xFFFFFFFFFFFFFFFF
EXIT_SUCCESS=0         EXIT_FAILURE=1
stdin=0                stdout=1               stderr=2
O_RDONLY=0             O_WRONLY=1
O_CREAT=64             O_TRUNC=512
```

Their small stored spelling/value helpers feed `cc-macro-add`, so copied text and records consume the normal limits. This is the legacy shim/header policy, not a complete system-header contract. Direct mode omits those eleven entries.

`cc-prep-target-fwd` initially names an empty default hook. Loading `124-cc-target.fth` binds it to `cc-target-predefines`, which acts only if `cc-target-sysv` is true. It installs the two dynamic entries plus `__STDC__=1`, `__STDC_HOSTED__=0`, `__SEED_FORTH__=1`, `__linux__=1`, `__x86_64__=1`, and `__LP64__=1`. It advertises neither a GCC identity nor a C99/C11 language-version macro. The explicit TinyCC driver sets LP64 and direct preprocessing; those flags alone do not activate this SysV hook.

### Finish the reset story

`cc-preprocess` begins a new pass, not a new global configuration. It resets macro count and pool position, include/conditional/sink depths, pending newlines, `in-if`, line-control mode, and scratch top. It initializes the selected output sink and shadow handling, installs legacy predefines if appropriate, clears the location-enable flag, initializes location line/rescan/depth, then invokes the target hook. Setting the location flag manually before the call is therefore insufficient; the hook owns reinstatement. The first expansion supplies object-root state rather than a top-level reset of that cell.

The pass clears packed include usage, copies the configured physical source name into depth zero, installs the raw input region, initializes that file's location state, and scans. Afterward a nonzero conditional depth fails39. On success, output position becomes `cc-src-len`; the lexer starts at position zero and line one. Active `#error` uses 40. These final checks do not prove that every source form has been validated.

Direct policy, explicit include directories, configured source name, target selection, and workspace selections survive this pass reset. The narrower `cc-prep-config-reset` clears direct mode, include count, and source-name length; it does not select default workspaces, unmap storage, or reset target flags. Keeping configuration separate from per-pass lifetime is what permits another input to use the same intended environment.

## Practice and a useful stopping point

[Hints, worked solutions, and changed cases](../practice/05-solutions.md) are available immediately. Start with C5-01 through C5-03 for the common path; take C5-04 through C5-06 after the extension sections. A correct state with a reason is the goal, not memorizing helper spellings.

### C5-01 — Complete a conditional stack

Trace this directive sequence from an empty stack: `#if 0`, `#if MISSING`, `#else`, `#endif`, `#elif 0`, `#elif 1`, `#else`, `#endif`. Show each post-state and identify exactly which operands reach the evaluator. Explain why the inner `#else` cannot activate its parent. What happens to a further `#endif`?

### C5-02 — Separate presence, text, and value

Start with `#define N 0`, `#define ALIAS N`, and `#define EMPTY`. Predict `defined(N)`, `defined(EMPTY)`, and the selected truth values of `#if N` and `#if ALIAS`. Then apply `#undef N` and repeat for `defined(N)`, `defined(ALIAS)`, and `#if ALIAS`. Explain which stage supplies each answer. Why must the `#if` temporary survive until the evaluator returns?

### C5-03 — Change the guarded header

In the integrated `shape.h` example, change only its definition to `#define ROWS 0`. Trace both header visits, the final root conditional, macro count, exact flattened bytes, length, and output-progress line before rewind. Then state the first failure if the root's final `#endif` is removed. Keep the header's closer.

### C5-04 — Preserve physical identity

Use the five-line location fixture, but register only `/sdk/include/`, assume `/project/src/detail.h` fails to open and `/sdk/include/detail.h` succeeds, and make the header contain `#line 7 "inner.c"\n__FILE__ __LINE__\n`. Predict the header's location answer and root line five's answer. Does the header's `#line` change the root offset or either file's physical search path? Contrast computed `"detail.h" extra` with `<detail.h>`.

### C5-05 — Diagnose a profile mix-up

A setup selects `cc-target-lp64=true`, `cc-prep-direct=true`, default workspaces, and no active SysV target. A report claims 4,608 macro records, `#line` support, dynamic `__LINE__`, computed includes, and typed `#if` evaluation. Correct each claim. Then enable SysV with `124` loaded but change no workspace: which conclusions change?

### C5-06 — Choose the continuation rule

With locations enabled, classify ordinary source `fo\\\no`, `x,\\\r\ny`, and the split-comment bytes used above. Separately classify the formal-name fragments `ar\\\r\ng`, an ordinary quoted literal containing backslash-CRLF, and a continuation splitting a directive name. Give the local effect or diagnostic, not the blanket answer “phase two deletes it.” Explain whether putting the first ordinary-source case inside an inactive group removes its boundary check.

If one task stalls, identify the missing state: table membership, group stack, temporary lifetime, profile flag, or physical/logical location. Revisit that small mechanism, then try the changed case with the solution closed. After intervening work, reconstruct the include-guard trace from its inputs. These are proposed opportunities to check retained reasoning, not evidence that reading the chapter establishes mastery.

You can now keep the preprocessor as a bounded client of the future lexer/evaluator. The next stage consumes the flattened bytes; it does not reconstruct macro invocations or recover a virtual filename from blank lines. Carry those boundaries into the lexer lesson.

## Source and evidence

- Common conditionals and evaluator caller: [`040`, `cc-pp-defined`, conditional storage, `cc-pp-if-value`, and `cc-pp-cond-directive`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth#L1637-L1736). Related source regions: 906–924 and 1398–1428. The directive table and outputs are hand-derived.
- Evaluator provider and independent typed gate: [`100`, constant-expression section and `cc-pp-eval-text`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2444-L2651). This is an inspected interface, not a lesson or proof of the entire parser.
- Computed headers and line operands: [`040`, `cc-prep-include-literal` through `cc-prep-handle-line`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth#L1761-L1950); location arrays at 718–765, formatters at 1236–1269, wrappers/dispatch at 1270–1397.
- Continuation families: [`040`, shared walkers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth#L383-L553), ordinary-source/prefix handling at 1429–1565, and stricter parameters at 1948–1999 with their selector at 2070–2096. Historical Chapter 22's existing marker/literal and token-join limitations remain boundaries, not requests for code repair.
- Selectors and reset: [`040`, predefines and `cc-preprocess`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth#L2206-L2300), workspaces at 605–667; [`030`, I/O workspace selectors](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/030-cc-io.fth#L239-L269); [`121`, `cc-sysv-enable`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1337-L1341); [`124`, target predefines](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/124-cc-target.fth); and the explicit [TinyCC driver](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/tcc-compile.fth).

The [historical preprocessor chapter](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/book/22-the-preprocessor.md) is comparison material. The pinned definitions govern the account here; its earlier test and bootstrap reports are not promoted to fresh observations.
