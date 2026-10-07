# 3. Preprocessing regions and includes

[Previous: Buffers, arenas, and failure ownership](02-buffers-arenas-and-failure.md) · [Practice help](../practice/03-solutions.md) · [Edition coverage](../../COVERAGE.md)

An `#include "a.h"` directive requests text from `a.h` while the preprocessor is reading its parent file. When the included file finishes, the preprocessor must remember where to continue, preserve the bytes it has already produced, and eventually reuse the included file's storage. Those are three different jobs.

Our question is: **what changes when the input changes, and what must remain?** By the end, you should be able to trace nested quoted includes into one output stream, identify which saved addresses remain valid, and predict a path or capacity failure. This is the first part of the preprocessor: macros and conditional groups have named interfaces here and their own later chapters.

## Bring two small contracts

[C02](02-buffers-arenas-and-failure.md) supplies spans, cursors, lifetime, capacity checks, and file reads. Can you explain why saving `(address, length)` does not copy bytes? Can a buffer of capacity eight hold eight emitted bytes, while `cc-read-all` accepts only seven? If either answer is uncertain, revisit those two mechanisms before tracing includes. Otherwise, the state tables offer a quick route through this chapter.

Cells are eight bytes; addresses and positions count bytes; stacks have their top at the right. Arithmetic below stays within the small nonnegative range of the library comparisons. `nl` is byte 10, `bl` byte 32, and `tab` byte 9. We write `\n` for one newline byte, not a backslash followed by `n`. Symbolic bases such as R and I0 name distinct, valid storage, not suggested machine addresses.

**Evidence and profile.** The definitions are from inspected [040-cc-prep.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth), with [020](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/020-cc-arena.fth) and [030](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/030-cc-io.fth), at commit `bbcc1732152af2d884737272eed870d2410ffe8e`. All traces and predicted outputs are manually derived, unexecuted. They assume successful file opens/reads unless a failure is stated, sufficient output capacity, and no matching user macro definitions.

The main path is **legacy preprocessing**, with `cc-prep-direct=0` and `cc-pp-location-enabled=0`. Keep three choices distinct:

- `cc-prep-direct` selects include-search and macro policies, including the later stringification, pasting, shadow-byte, and tail-rescan paths
- `cc-pp-location-enabled` selects source-location and several directive/splice rules. `cc-preprocess` clears it; the target hook can enable it through `cc-prep-location-builtins`
- Workspace selectors choose addresses and limits. Setting a policy flag does not select the larger workspace

The [SysV setup](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth) and [target predefines](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/124-cc-target.fth) combine the first two, but one flag does not imply the other. C05, *Conditional preprocessing and profile extensions*, opens the second gate and its limits.

## One active region, one output sink

A **region** is the text currently being read. Its three cells are `cc-prep-src-addr`, `cc-prep-src-len`, and `cc-prep-src-pos`. For `(A, 3, 1)`, the next byte is at A+1 and two bytes remain. The length belongs to the input; it is not an output position.

The actual end and peek definitions are:

```forth
: cc-prep-eor?
  cc-prep-src-pos @ cc-prep-src-len @ >= ;

\ cc-prep-peek ( -- c )  Current byte; 0 at EOR.
: cc-prep-peek
  cc-prep-eor? if,
    [lit] 0
  else,
    cc-prep-src-addr @ cc-prep-src-pos @ + c@
  then, ;

\ cc-prep-advance ( -- )
: cc-prep-advance
  [lit] 1 cc-prep-src-pos +! ;
```

Peek leaves the cursor alone. Advance changes only the position, even at end-of-region. Thus for bytes `A\nB`, peeking at position 1 returns 10; advancing gives position 2; peeking returns 66. At position 3, peek returns zero without reading A+3. A stored zero byte and end-of-region can both produce zero, so completion uses the length predicate, not a zero terminator.

`cc-prep-peek2` applies the same bound to position+1. `cc-prep-at? ( c1 c2 -- f )` compares both peeks, allowing the walker to recognize `/*`, `*/`, or `//`. `cc-prep-skip-blanks` advances over spaces and tabs only, deliberately leaving newline for another operation.

Two additional flags describe how to interpret a region. `cc-prep-in-file` is true for source files and false for rescanned macro text. Only file regions can introduce directives. `cc-prep-at-line-start` says whether to attempt directive lookahead. Neither flag is a byte in the source.

A **sink** describes where output goes. Four adjacent cells contain buffer address, output position, capacity, and the error code for exhaustion. Their addresses are `cc-pp-out`, `cc-pp-out-pos`, `cc-pp-out-cap`, and `cc-pp-out-code`, at byte offsets 0, 8, 16, and 24 in `cc-pp-sink`.

```forth
: cc-prep-emit-byte
  cc-pp-out-pos @ 1+ cc-pp-out-cap @ cc-pp-out-code @ cc-check-cap
  cc-pp-out-flags @ if, [lit] 0 cc-pp-out-flags @ cc-pp-out-pos @ + c! then,
  dup cc-pp-out @ cc-pp-out-pos @ + c!
  [lit] 1 cc-pp-out-pos +!
  nl = if, [lit] 1 cc-src-line +! then, ;
```

The check precedes the store. With sink `(S, 2, 3, 36)`, emitting newline writes S+2, sets position to 3, and increments `cc-src-line`. A further byte fails with code 36 before its store. The shadow-byte branch is inactive in this chapter's legacy trace; C04 explains how direct-mode metadata accompanies text without becoming text.

`cc-pp-emit-bytes ( a u -- )` repeatedly copies the byte at a, increments a, and decrements u. Its deferred copy operation eventually selects the metadata-aware copy, which has the same byte-copy behavior here. Unlike changing an input region, selecting a different sink changes where future output is written.

### Parking a sink preserves a destination, not its bytes

`cc-pp-copy4` copies the four cells in the order offsets 24, 16, 8, 0. `cc-pp-sink-push ( addr pos cap code -- )` copies the old record to slot `sink-depth*32`, increments depth, and installs its four arguments. Pop decrements depth and copies that record back. Both reselect the associated shadow address; they do not save it as a fifth cell.

Suppose S already holds `Q;` and the sink is `(S,2,8,36)` at depth zero. This paper example selects a separate four-byte T:

| Operation completed | Active sink | Saved slot 0 | Bytes newly written |
|---|---|---|---|
| Push `(T,0,4,37)` | `(T,0,4,37)` | `(S,2,8,36)` | None |
| Emit `A`, then `B` | `(T,2,4,37)` | Unchanged | T contains `AB` |
| Pop | `(S,2,8,36)` | No longer active | None |
| Emit `!` | `(S,3,8,36)` | — | S now contains `Q;!` |

Pop does not append `AB` to S or erase T. A caller must copy temporary text explicitly and respect its lifetime. Nor does the sink record contain `cc-src-line`; emitting a newline changes that shared counter even when the destination is temporary. C04 supplies the surrounding macro bookkeeping and explains the 34-entry sink stack's dependence on bounded scratch use. These push/pop words are not independently checked general-purpose stacks.

## Walk bytes without mistaking their context

The main walker is short because it delegates complete constructs:

```forth
: cc-pp-scan
  true cc-prep-at-line-start !
  begin,
    cc-prep-eor? 0=
  while,
    cc-prep-in-file @ if, cc-prep-at-directive? else, [lit] 0 then,
    if,
      cc-prep-handle-directive-fwd
      cc-pp-flush-nl
      [lit] 0 cc-prep-at-line-start !
    else,
      cc-pp-scan-char
    then,
  repeat, ;
```

The deferred directive entry permits calling a definition supplied later in the file. This is the [deferred-word mechanism](../../seed-forth/chapters/10-storage-deferred-words-and-bytes.md), not a second preprocessor pass.

At a line start, `cc-prep-line-is-directive?` saves the position, skips spaces/tabs, tests for `#`, and restores the position. Consequently lookahead consumes no input. `cc-prep-at-directive?` avoids repeating that search after the first ordinary byte of the line. With the location gate enabled, the prefix lookahead recognizes more whitespace/comment/continuation forms; C05 owns that different path.

For `#include "a.h"\n`, the handler consumes `#`, then `cc-prep-read-ident` records the borrowed span starting at offset 1 and advances to offset 8. Its length is 8−1=7. `cc-prep-ident=` first compares lengths, then the seven bytes against the stored spelling `include`. It does not need a C symbol table. The handler selects the include operation and finally skips any remaining directive text up to, but not through, its terminating newline.

The dispatcher asks the conditional handler first, because even a dropped group must recognize its closing directives. For now, the **C05 interface** `cc-pp-skipping?` answers whether ordinary file content is suppressed; it is false throughout our fixtures. When true, `cc-pp-skip-char` counts newlines inside whole comments/literals and otherwise advances without output. The earlier newline branch still preserves ordinary line endings. In active content, `#error` exits with 40; unknown directives are discarded. Definition, conditional, and line-control handlers are opened in C04/C05.

For ordinary file text, `cc-pp-scan-char` handles newline first: consume it, emit it, set line-start true. For a non-newline it clears line-start, then chooses a whole quoted literal, comment, number-like run, identifier, or single remaining byte. A literal is text beginning with `'` or `"`; its walker remembers that quote and carries an escaped byte with its backslash, so an internal `#` or `/*` is not interpreted separately.

`cc-pp-copy-number` copies letters, digits, underscores, and dots after an initial digit, preserving runs such as `0x1F` without treating `x1F` as a macro name. This is byte grouping, not a numeric-value parser. The identifier operation, `cc-pp-ident`, is our **C04 interface**: for the unregistered names in these fixtures, consume the identifier and copy its spelling. C04, *Macro expansion and rescanning*, opens lookup and replacement. No lexer token, C type, or expression parser is needed for this trace.

The shared walkers use `cc-pp-put-mode` to decide what to do with consumed bytes:

| Mode | Effect of `cc-pp-put` | Typical reason |
|---|---|---|
| `put-emit` | Append the byte | Preserve a file's comment or literal |
| `put-count` | Count only newline as owed | Discard directive content without losing its line breaks |
| `put-drop` | Discard the byte entirely | Look through a slice without producing it |

`cc-pp-take` applies that choice to peek, then advances. A block-comment walker consumes through `*/` or end-of-region; a line-comment walker stops before its newline. On the legacy main path, ordinary file comments are copied for the later lexer to skip. They are not recursively scanned for directives. In rescanned macro text, the comment interface instead emits one blank and owes internal newlines. Unterminated block comments only take the explicit error-49 branch when `cc-pp-line-control` is nonzero; do not infer a universal preprocessor rejection from the walker name.

## Newlines can be owed before they are emitted

Deleting directive words must not delete all evidence of their occupied lines. `cc-pp-pending-nl` counts newline bytes consumed without immediate output. `cc-pp-flush-nl` emits and subtracts one until the count reaches zero.

Consider this legacy input, with each displayed line ending in newline:

```c
#unknown /*x
 y*/
R
```

This is a **preprocessor-only fixture**, not a complete C program. The unknown directive is dropped. `cc-prep-skip-to-eol` uses `put-count`; it crosses the whole block comment, including the first newline. At the end of `*/`, pending=1, output position=0, and the current byte is the second newline. The scanner flushes the owed newline, producing position=1 and line=2. Its next iteration consumes the still-present terminating newline, producing position=2 and line=3. Finally it copies `R\n`: predicted output `\n\nR\n`, length four, line counter four.

The two newline writes have different causes. Counting a swallowed newline is not the same as advancing to a newline and leaving it for the main walker.

The legacy directive-tail walker also crosses backslash-newline and owes that newline. The literal walker removes backslash-LF pairs and, except in drop mode, owes their newlines; it stops at an unescaped logical newline or end if no closing quote appears. These local rules do not establish complete C line-splicing behavior. C05 explains the additional gated continuation/comment machinery and its explicit rejected cases.

**Pause point:** save `(pending=1, output-pos=0, line=1, current byte=newline)` from the comment example. On returning, predict which operation produces each of the first two output bytes.

## Enter an include, then resume the parent

An included file is often called a **header**. This operation cares about its bytes, not its filename suffix or the declarations it might contain.

Use these exact files for a paper trace:

| File | Exact byte text | Length | Base while active |
|---|---|---:|---|
| Root | `#include "a.h"\nR\n` | 17 | R |
| `a.h` | `#include "b.h"\nA\n` | 17 | I0 |
| `b.h` | `B\n` | 2 | I1 |

These are **preprocessor-only fixtures**, not complete C programs. Uppercase `R`, `A`, and `B` have no macro definitions. Each first directive has `#` at offset 0, quote at 9, name at 10–12, closing quote at 13, and newline at 14. The final letter and newline occupy offsets 15 and 16.

`cc-prep-include-literal` records quote mode 1 or angle mode 2 and its matching delimiter. It takes a borrowed span of the name between delimiters, then advances past the closing delimiter. For quoted legacy includes, `cc-prep-load-file` opens and reads into the current depth's include slot, returning `(address,length)`. Then this exact section saves the parent and installs the child:

```forth
      cc-prep-src-addr @ cc-prep-save-addr cc-prep-save-slot !
      cc-prep-src-len  @ cc-prep-save-len  cc-prep-save-slot !
      cc-prep-src-pos  @ cc-prep-save-pos  cc-prep-save-slot !
      [lit] 1 cc-prep-inc-depth +!
      cc-prep-src-len ! cc-prep-src-addr ! [lit] 0 cc-prep-src-pos !
      cc-pp-location-enter
      cc-pp-scan
      [lit] 1 cc-prep-inc-depth -!
      cc-prep-save-addr cc-prep-save-slot @ cc-prep-src-addr !
      cc-prep-save-len  cc-prep-save-slot @ cc-prep-src-len  !
      cc-prep-save-pos  cc-prep-save-slot @ cc-prep-src-pos  !
      r> cc-prep-inc-top !
```

This is an excerpt inside the include operation, not a standalone definition. Immediately before loading, that operation parks the old packed-pool top with `>r`; the final `r>` restores it. `cc-prep-save-slot` computes `array + depth*8`. The returned length is on top of the returned address, so storing length first leaves the address available for the next store. `cc-pp-location-enter` initializes per-file location bookkeeping; it produces no output and C05 opens that separate interface.

The output sink is never pushed for a plain include. It keeps accumulating bytes while input regions change. Rows below show post-state; letter/newline copying is grouped only where shown. Pending newlines remain zero throughout.

| Step completed | Depth | Active `(base,len,pos)` | Saved parents | Output text | Output position; line |
|---|---:|---|---|---|---|
| Start root scan | 0 | `(R,17,0)` | None | Empty | 0; 1 |
| Parse root operand | 0 | `(R,17,14)` | None | Empty | 0; 1 |
| Load and enter `a.h` | 1 | `(I0,17,0)` | Slot 0=`(R,17,14)` | Empty | 0; 1 |
| Parse its operand | 1 | `(I0,17,14)` | Slot 0 unchanged | Empty | 0; 1 |
| Load and enter `b.h` | 2 | `(I1,2,0)` | Also slot 1=`(I0,17,14)` | Empty | 0; 1 |
| Copy `B\n`; child reaches end | 2 | `(I1,2,2)` | Both unchanged | `B\n` | 2; 2 |
| Restore `a.h`; finish directive | 1 | `(I0,17,14)` | Slot 0 still live | `B\n` | 2; 2 |
| Copy its newline, then `A\n` | 1 | `(I0,17,17)` | Slot 0 still live | `B\n\nA\n` | 5; 4 |
| Restore root; finish directive | 0 | `(R,17,14)` | None live | `B\n\nA\n` | 5; 4 |
| Copy its newline, then `R\n` | 0 | `(R,17,17)` | None live | `B\n\nA\n\nR\n` | 8; 6 |

The predicted eight output bytes are decimal `66 10 10 65 10 10 82 10`. Included text comes **before** its parent's retained directive newline. Restoring the parent's output position would erase the logical progress of the child; restoring its input position to zero would process the include again.

The include frame saves three cells, not the whole scanner. The caller's directive path sets line-start false after handling the directive; consuming the parent's retained newline sets it true again. That control flow explains why this plain include does not need to restore a saved line-start flag.

At top level, `cc-preprocess` initialized the sink to the selected source buffer with error 36, reset include/conditional/sink depths and pending count, established the raw region, and marked it as a file. After scanning, it assigns output position to `cc-src-len`, rewinds `cc-src-pos` to zero, and resets `cc-src-line` to one for the next stage. Thus this fixture's final source length is eight, but the next reader starts at line one, not six. During this trace, diagnostics refer to progress through the flattened stream; they do not identify an original filename and line.

## A saved address needs a living owner

Legacy include storage has four 262,144-byte slots. At depth d, `cc-prep-inc-slot-addr` computes `pool + d*262144`. The root lives separately in the input buffer. A child uses its parent's current depth as the slot index, then enters at depth d+1.

After `b.h` returns, I1 can be reused by another child of `a.h`. After `a.h` returns, I0 can be reused by another root include. Saved parent spans remain valid while their descendants run because descendants occupy different live slots. Old child spans are not permanent records.

This is why C04 will copy a macro's name and body into a separate macro pool before retaining them: saving an address into I0 would leave a definition pointing at a later header's bytes. Final source bytes already copied into the output sink are independent of those overwritten input slots. A saved cursor, an owned copy, and an allocation lifetime solve different problems.

The current source reserves **32 entries in each parent-save array**, using `cc-prep-direct-depth`, even though legacy loading permits only four live includes. At depth four a further include fails with code 31 before opening it. A larger save array does not expand the four-slot legacy pool.

## Build a path; know which search you asked for

Paths sent to `open` need a terminating zero. Source spans do not. `cc-prep-append` checks `path-out + incoming-length + 1 <= 1024` before copying, reserving the closing zero. The builder is:

```forth
: cc-prep-build-path
  >r >r                                            ( pa pu ; R: nu na )
  [lit] 0 cc-prep-path-out !
  cc-prep-append                                   \ append prefix
  r> r>                                            ( na nu )
  cc-prep-append                                   \ append name
  [lit] 0 cc-prep-path-buf cc-prep-path-out @ + c! ;  \ NUL
```

For prefix `tests/cc/` of length nine and name `a.h` of length three, prefix copying leaves position 9; name copying leaves 12; the zero is stored at offset 12 without increasing position. The resulting path needs thirteen bytes of storage. This helper concatenates bytes; it does not insert a slash or normalize a path.

Legacy quoted includes try the name as given, then `tests/cc/` plus the name if the first open returns a negative result. They do not automatically search the includer's directory. Legacy angle operands are consumed but not loaded; built-in shim macros provide selected historical names, not a real system-header installation. Direct-mode literal operands fail with 30 if empty or missing their closing delimiter; those explicit checks are absent on the legacy path.

Direct mode supplies a different, explicit search:

1. An absolute name beginning with `/` is tried as supplied
2. A relative quoted name first tries the including file's directory
3. Relative quoted or angle names then try configured include directories in order; angle names skip step 2

For current file `src/main.c`, directories `inc/`, then `vendor/`, and quoted `a.h`, the candidates are `src/a.h`, `inc/a.h`, `vendor/a.h`. If `inc/a.h` succeeds and includes quoted `b.h`, its first candidate is `inc/b.h`. `cc-prep-record-path` preserved the successful path at the child's depth; a later display-only `#line` filename does not replace that search path.

`cc-prep-directory` finds the prefix through the last slash, possibly empty. `cc-prep-copy-path` copies a bounded path and adds its zero. `cc-prep-source-name` stores the root's name. `cc-prep-add-include` records up to 32 directories, adding a trailing slash to a nonempty one when needed; paths remain relative to the process working directory. `cc-prep-current-path` selects the current depth's record. `cc-prep-config-reset` clears direct mode, directory count, and root-name length, not every preprocessor variable.

### Separate depth, live bytes, and accepted read size

Direct mode allows 32 live includes and packs them into the selected pool: load at `base+inc-top`, pass remaining capacity to `cc-read-all`, add returned length to top, and restore the old top when the include finishes. With top 20 and a five-byte child, the child occupies `[base+20,base+25)` and top becomes 25. A nested three-byte child advances top to 28; returning restores 25, then 20. Freed space can be reused without erasing its bytes.

Slots make depth arithmetic sufficient to locate storage, but reserve 256 KiB even for a tiny header. Packed storage replaces that fixed partition with actual lengths and a saved top; its per-file room depends on the live parents.

By default this packed pool is the same dictionary-backed **1 MiB** region as the four legacy slots. The opt-in `cc-prep-direct-workspace` instead selects a separately mapped **7 MiB** include pool and larger macro arrays. It maps each area only if its cached base is zero. `cc-prep-default-workspace` reselects defaults. Neither selector migrates live text or resets counts; use them before initialization and loading. Their macro-array layouts belong to C04. Pool size is a policy constant attributed to workload measurements in source comments, not a measurement repeated here.

Every include load checks depth first, then opens, reads, and attempts close. `cc-prep-try-open` supplies flags zero (read-only) and mode zero to the library's `open`; a nonnegative result is a usable file descriptor. Failure to open any candidate exits with 30; excessive depth with 31; an exhausted include slot/pool with 32; oversized paths/directories with 33. The selected final-source sink separately uses 36. There is no automatic growth or include-cycle detector here; repeated cyclic inclusion eventually meets a bound unless another preprocessing rule stops it.

`cc-read-all` requires payload smaller than its supplied remaining capacity, so a legacy slot accepts at most 262,143 bytes. Direct packing similarly keeps one byte of remaining room after each successful read; that is not a stored terminator. As C02 established, a negative read result stops the loop and returns the prefix already read, and close's result is ignored. Therefore our successful whole-file trace depends on the stated I/O assumptions, not merely on receiving a returned length.

## Practice: preserve the right thing

Use paper states. [Hints, worked solutions, and changed cases](../practice/03-solutions.md) are separate so you can attempt any question before revealing its answer.

1. **C3-01 — Distinguish input from output.** Region `(A,3,1)` contains `X\nY`; sink `(S,2,3,36)` contains `Q;`; line=1, flags=0. Peek, advance, emit the peeked byte, then attempt to emit `!`. Record the returned byte, both positions, sink bytes, line, and failure point. Does advance itself count a line?
2. **C3-02 — Restore a parent.** In the three-file trace, stop just after copying `B\n`. Write both live saved triples. Complete the remaining output and final preprocessor/next-reader line states. Explain what goes wrong if the child's output position is replaced by the parent's pre-include output position.
3. **C3-03 — Find a lifetime error.** A root includes `one.h`, then `two.h`. A hypothetical retained definition stores only a span into the first legacy include slot. Explain when that span can change meaning and what must be copied before then. Contrast a still-live parent's span during a nested include.
4. **C3-04 — Keep path and read bounds distinct.** Current file is `src/main.c`; configured directories are `inc/`, `vendor/`. Derive candidates for quoted and angle `a.h` in direct mode, and quoted `a.h` in legacy mode. For the legacy fallback, locate the zero terminator. Then predict a legacy include whose first read returns exactly 262,144 bytes.
5. **C3-05 — Recover swallowed newlines.** Trace `#unknown /*x\n y*/\nR\n` through the first ordinary `R`: pending count, input stopping point, output, and line. Would a `#` inside the comment start another directive? Explain which profile gate must be examined before generalizing the legacy line-prefix rule to a leading block comment.

## What this mechanism gives us

One active region tells the walker what to read. One sink tells it where to append. An include saves the parent's region, scans owned child bytes into the same sink, restores the parent, and releases the child's live storage for reuse. Retained newlines keep a flattened stream's accounting inspectable; they are not an original-file location map.

C04 will reuse these operations for macro text, but with a different lifetime problem: a replacement can need further scanning while temporary arguments and parent text remain live. Bring the distinction between a span and its owned bytes into that chapter.

### Source-scope and evidence ledger

This ledger accounts for the substantive C03 mechanisms rather than treating a quoted subset as the whole file. It uses the pinned `040` named sections and linked supporting source; derived states above remain unexecuted. The [historical chapter 22](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/book/22-the-preprocessor.md) supplies context, not a substitute for current definitions or a new validation run.

| Source group | Teaching here | Explicit later boundary |
|---|---|---|
| Sink: `cc-prep-emit-byte`, `cc-pp-emit-bytes`, copy default/deferred entries, `cc-pp-copy4`, sink push/pop | Four fields, checked append, shared line effect, copied-record trace | C04: scratch ownership, shadow-byte definitions/bindings, sink-depth resource argument |
| Region: `cc-prep-eor?`, peek, advance, peek2, skip-blanks, at? | Length-bounded reads and file/line-start flags | C04: replacement-region save/restore |
| Newlines/walkers: flush-nl, put/take, block-comment, line-comment, literal/literal-splices, skip-to-eol, skip-char; file branch of comment/scan-char | Modes, quote/comment protection, ordinary copying, skipped-construct interface, owed versus retained newline trace | C04: macro-text branches; C05: skipping? predicate, continuation/splice helpers, line-control and gated comment behavior |
| Names: read-ident, ident=, copy-number | Borrowed spelling, length-first equality, number-like run grouping | C04/C05: need-name/need-rparen and expansion/conditional uses |
| Include pool and workspace selectors/accessors | Four-slot lifetime, packed top, 32-save-slot distinction, default and opt-in capacities | C04: macro-array selection fields; C02: mapping primitive |
| Paths/configuration: append, build-path, copy-path, source-name, add-include, directory, current-path, record-path, config-reset | Path byte trace, configuration limits, ordered searches | C05: physical search path versus presumed display name |
| Loading: try-open, open-include, load-file | Open/read/close contract and failures 30–33 | C02: raw syscall/read limitations |
| Dispatch: line-is-directive?, at-directive?, scan, handle-directive and deferred bindings | Legacy lookahead, include dispatch, unknown-line disposal; active `#error` exits with 40 | C04: define/undef; C05: conditional dispatch, directive-blanks/prefix, line control |
| Include frame: save-slot, include-literal, handle-include | Literal operands, nested triple save/restore, output preserved, delimiter/profile limits | C05: computed operand expansion, expanded-only checks, temporary-region path |
| Top level: preprocess, builtins/target/location entry interfaces | Main initialization, main sink, final length/reader reset; legacy shim purpose | C04: macro reset/storage; C05: shim entries, conditional closure error 39, target/location implementation |

This chapter does not claim that every preprocessing input is valid C, that all C preprocessing is supported, or that a source inspection establishes successful execution. Real-reader learnability also remains untested; the exercises provide observable checks rather than a claim of mastery from reading.
