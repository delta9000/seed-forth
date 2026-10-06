# C05 practice: hints, worked solutions, and changed cases

[Return to Conditional preprocessing and profile extensions](../chapters/05-conditionals-and-profile-extensions.md)

These solutions are checked paper derivations against the pinned definitions cited in C05, not compiler executions. They use byte lengths, eight-byte cells, conditional stacks bottom-to-top from left to right, and successful I/O unless the question changes those premises. A preprocessor fixture need not be valid input for the later C parser. In escaped byte descriptions, `\n` is LF, `\r` is CR, and `\\` is one literal backslash.

Try the state transition and its reason before reading the solution. Hint 1 identifies the mechanism; hint 2 isolates its decisive boundary; hint 3 supplies a partial step. You can use the worked solution directly if that is more useful, then close it for the changed case. Correct work with hints and independent reconstruction are different evidence about your current capability.

## C5-01 — Complete a conditional stack

### Hints

1. A child's top state is determined partly by whether its parent is already skipping. Track the full stack, even though the predicate reads only its top.
2. `done` cannot turn into `take`. Only `seek` can select a later branch.
3. After the first two openers the stack is `[seek, done]`. The nested `MISSING` expression has not reached the evaluator.

### Worked solution

| Directive completed | Post-state | Was its operand evaluated? |
|---|---|---|
| `#if 0` | `[seek]` | Yes: zero |
| `#if MISSING` | `[seek, done]` | No: enclosing group inactive |
| Inner `#else` | `[seek, done]` | No expression operand |
| Inner `#endif` | `[seek]` | No expression operand |
| `#elif 0` | `[seek]` | Yes: zero, so keep seeking |
| `#elif 1` | `[take]` | Yes: one, so select this branch |
| Outer `#else` | `[done]` | No expression operand |
| Outer `#endif` | `[]` | No expression operand |

Only three expressions reach `cc-pp-eval`: the outer `0`, the first `#elif`'s `0`, and the second `#elif`'s `1`. The inner opener pushes `done` without reading its name through the evaluator. The inner `#else` transforms `done` into `done`, so it cannot activate anything. Its closing directive removes only that inner cell.

A further `#endif` finds depth zero. `cc-pp-need-group` exits with 41 before a decrement. This is an unmatched closer, whereas an opener left alive at the normal end of the whole pass uses 39. Neither is the depth-capacity failure 38.

A common wrong answer turns the inner `#else` into `take` because “else is the opposite of if.” That loses the difference between a false evaluated condition and an entire group suppressed by its parent. Use `seek` for the former, `done` for the latter.

### Changed case

Change only the first directive to `#if 1`; assume MISSING has no macro definition. The successive states become:

```text
[take]
[take, seek]
[take, take]
[take]
[done]
[done]
[done]
[]
```

Now the inner expression does reach the evaluator. Macro expansion leaves MISSING, and preprocessing-constant evaluation supplies zero, so its opener pushes `seek`. Its `#else` can select `take`. After closing the child, the first outer `#elif` changes the already-selected outer `take` to `done` without evaluating its operand. The next `#elif` also does not evaluate. Thus the evaluator receives only the first `1` and the inner MISSING expression.

If you predicted both outer `#elif` values were evaluated, revisit the distinction between looking for a directive boundary and requesting an expression value.

## C5-02 — Separate presence, text, and value

### Hints

1. Make three columns: live name, expanded bytes, evaluator value. Do not place an empty body in the “absent name” column.
2. ALIAS's stored replacement is the spelling N. A later table change changes what its rescan can do; it does not remove ALIAS's own record.
3. Before undefinition, ordinary N expands to `␠0␠`. Its padding is whitespace, and the evaluator value is zero.

### Worked solution

Before `#undef N`:

| Query | Result | Responsible mechanism |
|---|---|---|
| `defined(N)` | Byte `1` | `cc-pp-defined` queries a live macro record |
| `defined(EMPTY)` | Byte `1` | Same lookup; body length zero does not erase the name |
| `#if N` | False | Expansion produces zero; evaluator returns zero |
| `#if ALIAS` | False | ALIAS rescans N, which expands to zero; evaluator returns zero |

These are independent conditions considered from an active context, not four nested openers. If the corresponding directives were placed in a real fixture, each group would need its own closer.

After `#undef N`:

| Query | Result | Reason |
|---|---|---|
| `defined(N)` | Byte `0` | All live matching N entries have been invalidated |
| `defined(ALIAS)` | Byte `1` | ALIAS itself still has a live record |
| `#if ALIAS` | False | ALIAS expands to N; N now survives macro lookup; the evaluator maps that identifier to zero |

The last false result has a different cause from the earlier one. Before undefinition the evaluator receives a numeric zero. Afterward it receives an ordinary identifier and applies its preprocessing-mode identifier rule. `defined` does not recursively expand ALIAS to decide membership.

The `#if` caller owns temporary expanded bytes until the evaluator consumes them. `cc-pp-temp-end` returns their span while restoring the parent sink; it does not grant them indefinite lifetime. Restoring the saved scratch top before the callback would allow the borrowed span to be reused too early. The real sequence evaluates first, then restores scratch top. The provider separately saves/restores the lexer state and source length on successful return.

A wrong explanation that says “all false results came from lookup failure” cannot explain `defined(N)=1` alongside `#if N` being false. Use that pair as the small repair example.

### Changed case

Starting again from the original definitions, append `#define N 7`, then `#undef ALIAS`. N now resolves newest-first to seven; `defined(N)` is one and `#if N` is true. `defined(ALIAS)` is zero. An ordinary ALIAS that survives preprocessing would evaluate as zero in `#if`.

The new N record does not overwrite the old record's storage. Undefining ALIAS does not reclaim its record count or pool bytes, and it does not affect either N record. If N is subsequently undefined, all matching N entries are invalidated, so the older zero does not reappear.

## C5-03 — Change the guarded header

### Hints

1. The guard tests SHAPE_H, not the numerical value of ROWS. Both header visits therefore make the same guard decisions as before.
2. `defined(ROWS)` is still one, but ordinary ROWS now expands to zero. Track newline bytes even in the unselected branch.
3. After both includes and their root newlines, output has ten LF bytes and thirteen macro records. The `#if` newline makes eleven LF bytes.

### Worked solution

The first header visit pushes `take`, adds SHAPE_H and ROWS, and closes. The second pushes `seek`, skips the two definitions, and closes. Neither header visit emits ordinary source tokens. Together with the two retained root include-line newlines, they emit ten LF bytes.

The root condition expands to the token expression `1 && 0`, so the root pushes `seek`. The ROWS line is inactive. `#else` changes that root state to `take`, allowing the unexpanded numeric spelling `99` to be copied. The final `#endif` removes the state.

| Completed portion | Output position | LF count | Conditional stack |
|---|---:|---:|---|
| Both complete includes | 10 | 10 | `[]` |
| Root `#if` and its newline | 11 | 11 | `[seek]` |
| Skipped ROWS line and its newline | 12 | 12 | `[seek]` |
| `#else` and its newline | 13 | 13 | `[take]` |
| `99\n` | 16 | 14 | `[take]` |
| `#endif` and its newline | 17 | 15 | `[]` |

The exact output is thirteen LF bytes followed by `99\n\n`: seventeen bytes. Its fifteen LF bytes make output-progress line sixteen. There remain thirteen records: eleven legacy predefines and two user definitions. ROWS being zero does not reduce that count. On success, source length becomes seventeen and the next reader starts at position zero, line one.

Removing the root's final closer leaves `[take]` when scanning ends. At that point the partial sink contains thirteen LF bytes plus `99\n`, sixteen bytes in total, with fourteen LF bytes. `cc-preprocess` sees nonzero depth and fails39 before its normal source-length publication and reader rewind. It does not return a successful shortened translation. The header's own closer is balanced and does not close this later root group.

A common wrong count is fifteen bytes, obtained by counting only lines and forgetting the two literal `9` bytes. Another is seventeen LF bytes, confusing total output bytes with line endings. Keep those units separate.

### Changed case

Keep ROWS equal to zero, but change the root test to `#if defined(ROWS)`. The condition is now true. The ROWS line emits `␠0␠\n`, and `99` is skipped. The final output becomes eleven LF bytes, `␠0␠`, then four LF bytes: eighteen bytes, fifteen LF bytes, output-progress line sixteen. The count and final group state remain thirteen and empty.

This checks whether you can choose the right question: membership asks whether configuration supplied a name; numerical evaluation asks what its expanded value means.

## C5-04 — Preserve physical identity

### Hints

1. Include search reads the physical-path table. Dynamic filename output reads the per-file logical-name state when one has been installed.
2. Every entered header starts at physical line one and logical offset zero, independent of its parent's offset.
3. The header requests seven for the line following its line-control directive. Its new offset is `7-(1+1)=5`.

### Worked solution

The root's first line still installs offset 38 and logical filename `virtual.c`. Its line-two `__LINE__` is forty. The computed quote operand on physical line four is `detail.h` after parsing surrounding expansion spaces.

The direct quote search first attempts `/project/src/detail.h`; by the problem's premise that fails. It then tries `/sdk/include/detail.h`, which succeeds. The resulting child's physical path is `/sdk/include/detail.h`. These are explicit paper premises, not new claims that those paths exist.

The header enters at depth one with physical line one, offset zero, logical-name sentinel −1. Its first line, `#line 7 "inner.c"`, installs offset five and logical name `inner.c`. On physical line two, `__FILE__ __LINE__` emits `"inner.c" 7`. Returning to the parent selects depth zero's still-existing state: physical root path `/project/src/main.c`, offset 38, logical name `virtual.c`.

The root's fifth line therefore emits `"virtual.c" 43`. It does not emit seven or `inner.c`. Neither `#line` changed a physical path; each changed only its own depth's logical state.

For completeness, the changed fixture's exact flattened output is:

```text
\n40\n\n\n"inner.c" 7\n\n"virtual.c" 43\n
```

That is an escaped byte description, not seven literal lines of output. The extra blank line relative to C05's original fixture comes from the header's own `#line` directive. Both the header's final newline and the root's retained include-line newline remain.

A computed expansion yielding `"detail.h" extra` fails30 at the exact-one-operand check, before its header is loaded. A computed `<detail.h>` has one valid angle operand without internal whitespace, so search uses only the explicit `/sdk/include/` directory and succeeds under the same stated premise. It does not try the physical includer's directory. An expansion containing `<detail .h>` would instead fail30 because of whitespace inside the angle name.

The tempting wrong rule “relative includes use `__FILE__`” confuses reported identity with search identity. The two names happen to agree before line control, which can hide the mistake.

### Changed case

Append physical root line six `#line 100`, then line seven `__FILE__ __LINE__`, with each ending in LF. The requested number applies to physical line seven, so the new root offset is `100-(6+1)=93`. Omitting a filename preserves `virtual.c`; line seven emits `"virtual.c" 100`. The header's `inner.c` remains unrelated.

If instead the line-six directive is `#line 100 ""`, line seven emits `"" 100`. A zero-length logical filename is valid and differs from the −1 sentinel that requests the physical name. None of these changes redirects a later quoted include.

## C5-05 — Diagnose a profile mix-up

### Hints

1. Write four separate decisions: direct preprocessing policy, target-enabled locations, selected workspace, and evaluator typed mode.
2. `cc-prep-direct-workspace` selects 4,608 entries; `cc-prep-direct` by itself does not call that selector.
3. During `#if`, the provider sets `cc-cx-pp`. With LP64 already true, the AND gate is true even when SysV is false.

### Worked solution

For direct=true, LP64=true, no active SysV target, and default workspaces:

| Claim | Judgment | Reason |
|---|---|---|
| 4,608 macro records available | Incorrect; bound is 4,096 | Default selected arrays/limit; direct policy uses that selected bound |
| `#line` support | Incorrect for this setup | Location gate is cleared at pass start and no active target hook enables it |
| Dynamic `__LINE__` | Incorrect for this setup | No target location entries installed |
| Computed includes | Correct | Selected by direct preprocessing policy |
| Typed `#if` evaluation | Correct | During evaluation, `cc-cx-pp AND cc-target-lp64` is true |

Include storage is the default packed 1-MiB pool with maximum depth 32. Raw/source capacities remain 1/2 MiB. Macro text uses the direct 262,144-byte bound. The eleven legacy shim predefines are omitted because direct is true. Loading `124` while SysV remains false would not by itself add its target predefines.

Now call `cc-sysv-enable` with `124` loaded, without selecting other workspaces. The target enables SysV, LP64, and direct preprocessing. On the next preprocessing pass, the target hook enables locations and installs eight target records: two dynamic names plus six ordinary target predefines. `#line` and dynamic location macros now have their stated support. The stricter parameter reader and newer prefix/comment/source-continuation behavior also become available through that location gate.

The macro-record bound is still 4,096, include storage still 1 MiB, and raw/source capacities still 1/2 MiB. Computed includes and typed preprocessing were already active and remain so. Calling `cc-prep-direct-workspace` separately would select 4,608 macro entries and a 7-MiB include pool. Only the separate I/O selector supplies the larger 3/7-MiB raw/source buffers. Selectors do not migrate live definitions or reset counts, so these are setup choices, not a safe mid-pass growth recipe.

The report's core error was treating several flags and storage selectors as one “direct mode.” Equal settings in one driver do not make the selectors equivalent.

### Changed case

Choose direct=false, LP64=true, SysV=false, default workspaces, and the nonacting target hook. Legacy macro policy now imposes 1,024 records and 65,536 text bytes; the pass installs eleven legacy predefines. Includes use four legacy 256-KiB slots with maximum depth four. Computed includes and target location behavior are absent.

Typed `#if` evaluation nevertheless remains enabled while the provider is evaluating a condition, because its gate still has both preprocessing-constant mode and LP64. This is a flag-level paper comparison, not a recommended or executed full compiler configuration. It discriminates the evaluator's contract from the preprocessor's policy selector.

## C5-06 — Choose the continuation rule

### Hints

1. Identify which routine owns the bytes before deciding what “splice” means. A comment and an ordinary source token do not use the same disposal operation.
2. The file-text rule substitutes a newline only when it cannot change token boundaries. Comma is in its complete-punctuator list; a letter is not.
3. `ar` plus a continuation plus `g` is being read into the formal-name temporary sink. That path deletes the continuation and joins the spelling `arg`.

### Worked solution

All rows have locations enabled. Escaped byte text uses `\\` for one literal backslash.

| Case | Local behavior | Decisive reason |
|---|---|---|
| Ordinary `fo\\\no` | Fail49 at the continuation | Previous `o` and next `o` supply no accepted separator boundary |
| Ordinary `x,\\\r\ny` | Emit `x,\ny` | Comma is always a whole punctuator; remove backslash/CR and emit LF |
| `/\\\n*x*\\\r\n/Q\n` | Emit `/*x*/\n\nQ\n` | Comment delimiter matching looks through both continuations; their two LF bytes are owed until after the comment |
| Formal-name fragments `ar\\\r\ng` | Store logical name `arg`; owe one LF | Parameter-name phase joins logical spelling in temporary storage |
| Ordinary literal containing backslash-CRLF | Do not claim deletion by the ordinary literal splice helper | That helper recognizes backslash-LF, not CRLF; this is a recorded boundary, not general valid-literal support |
| Continuation splitting a directive name | Fail49 | The dispatcher rejects a continuation immediately after the identifier it read |

For the comment row, the copied comment has five bytes, `/*x*/`. Then two owed LF bytes, Q, and its terminating LF bring the total to nine. Inserting those owed bytes inside the delimiter would defeat the reason for removing the continuations.

For the parameter row, the temporary holds three logical bytes, and physical input still contains its original continuation. The owed newline is accounted for separately. The parameter can be matched in replacement-body encoding before that temporary is reclaimed. The count limit is sixteen formals (48), the shared temporary bound is 65,536 bytes (37), and malformed/duplicate-list errors use 47. None of those becomes error49 merely because location support selected the stricter reader.

Placing ordinary `fo\\\no` in an inactive group does not remove its check. The scanner handles the location-enabled file continuation before asking whether ordinary file text is skipped. It still fails49. By contrast, an inactive nested `#if` bypasses expression evaluation. “Skipped” therefore needs the name of the operation being bypassed.

A wrong answer that deletes every continuation reaches the right spelling for `arg` but silently joins `foo` and mishandles newline placement around comments. Use the three owners, ordinary file scanner, comment walker, formal-name reader, as separate trace columns.

### Changed cases

1. Replace the ordinary first case with `fo\\\n o`, adding a space after the LF. The lookahead now sees an accepted whitespace boundary, so the ordinary scanner emits `fo\n o`. It does not join the identifier pieces. The next byte after continuation is not marked as a new directive start.
2. Make the logical formal list `arg, ar\\\r\ng`. The second spelling becomes `arg` too; duplicate checking now fails47. This is not two distinct formals named by different physical slices.
3. Keep direct macro policy true but disable target locations for the pass. That alone does not select any of these newer comment/source/strict-parameter rules. Computed includes and C04's direct macro operators remain separately selected. The ordinary source continuation is no longer governed by the location-enabled safe-boundary branch; do not invent the same error49 from that now-inactive branch, or claim universal deletion by a different one.

## What your explanations should now separate

A complete answer identifies the state owner, follows the decisive transition, and keeps its profile premise. You need not recall the spelling of every helper to demonstrate that reasoning. If a result was right for the wrong reason, use the changed case that exposes it: zero-valued but present names, a nested inactive branch, an empty virtual filename, or LP64 without SysV.

All predictions above remain unexecuted. Source-matched reasoning and a checked arithmetic/byte count are useful evidence about this manuscript; they are not a semantic-correctness proof or a learner study. Use the [chapter's source ledger](../chapters/05-conditionals-and-profile-extensions.md#source-and-evidence) to inspect the relevant definitions without treating navigation memorization as part of the exercise.
