# C16 practice help: conditions and loops

[Back to the chapter](../chapters/16-conditions-and-loops.md)

These are checked manual derivations against revision `bbcc1732152af2d884737272eed870d2410ffe8e` and the chapter's explicit source/profile contracts. No compiler, Forth, C example, generated executable, or build was run. Numeric layouts are stipulated paper coordinates. The solutions establish predictions and source-reading criteria, not execution or learning-study results.

Use the first hint to locate the relevant distinction, the second to expose the decisive state, and the third for a partial step. You can open the complete solution immediately if that is more useful. After feedback, use a changed prompt from the chapter with this page covered; repeating a visible answer is supported practice rather than an independent check. Each solution gives a targeted next move without requiring a full reread.

## Entry check

1. Rereading a pending token clears the pending flag and returns the existing record. It does not advance the source cursor. Token fields remain available until another token read replaces them
2. Calling an emitter runs builder Forth that writes bytes. The future target instruction runs only when a generated program later reaches it
3. q is an output-file byte offset of the displacement field, not an arena pointer, opcode offset, or target virtual address. Its relative origin is q+4
4. No. A scope pop restores symbol count. The legacy local-slot allocator remains monotonic within the function; visibility restoration does not imply slot reuse

If only the first item was uncertain, practice a two-row current/pending ledger. If the coordinates were uncertain, label an address before subtracting anything. These are distinct repairs.

## C16-01 — Trace a recursive owner

**Hint 1.** The inner parser finishes before the outer parser can perform its optional-else read.

**Hint 2.** The saved offsets below a recursive call's own work must survive that call. An absent else requires putting the following token back.

**Hint 3.** Just after the inner JZ placeholder, B.D contains `[qO,qI]`. The first optional-else read belongs to that inner parser.

**Checked solution.** The outer if emits qO and recursively parses its body. That body starts with `if`, so the inner emits qI over the saved outer item. Its then-body consumes `pad=pad-1;` while preserving `[qO,qI]`. The inner reads `else`, emits its skip-over-else JMP, patches qI to the else-body, parses `n=n-1;`, and patches its second jump. Its final B.D is `[qO]`.

The outer then-body call is now complete. The outer optional-else read sees `return`, makes it pending, and patches qO to the end of the entire inner statement. B.D returns to its starting level. Current token fields describe `return`, pending=true; source position has already advanced past the keyword. The next dispatcher call rereads that record rather than advancing past it again.

The future paths are:

| Initial `(pad,n)` | Reached assignment | Values after that assignment, if any |
|---|---|---|
| `(0,2)` | Neither | `(0,2)` |
| `(2,0)` | `n=n-1` | `(2,−1)` |
| `(2,2)` | `pad=pad-1` | `(1,2)` |

With `if (pad) { if (n) pad=pad-1; } else n=n-1;`, the inner optional-else read sees `}` and puts it back. The compound consumes the brace and returns. The outer now reads and owns the `else`. For `(0,2)`, the outer else executes and makes n=1. For `(2,0)`, the compound is entered, the inner condition is false, and neither assignment runs. For `(2,2)`, pad becomes one. The builder pushes/pops a symbol scope for the braces; the braces alone emit no target-stack adjustment.

**Wrong path to diagnose.** Giving both assignments to the outer if ignores which recursive call is still active when `else` is read. Leaving `return` consumed loses the next statement. Treating the brace scope push as target PUSH confuses machines.

**Next step.** If ownership was wrong, cover the value table and trace only the five tokens `if`, `if`, `else`, `return`, and the relevant closing brace. If ownership was right but arithmetic was wrong, make a separate future-values table; no parser change is needed.

**Changed reattempt check.** In `if (pad) ; else if (n) pad=pad-1; return;`, the outer consumes its own `else` before invoking the inner parser. The inner has no else, so its optional-else read sees `return` and leaves it pending. The outer returns after its else-body completes; it does not perform a second optional-else read. Therefore the inner performs the read beyond the entire construct. “Every if peeks once more after its whole statement is complete” is not the algorithm.

Source check: [if parser](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L49-L70) and [compound parser](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L22-L33).

## C16-02 — Calculate both branch origins

**Hint 1.** First draw instruction boundaries. Perform signed displacement arithmetic only after locating each field's end.

**Hint 2.** A JZ/JNZ has two opcode bytes before its four-byte field; a JMP has one. The then-body starts after the six-byte JZ.

**Hint 3.** JZ field q=1002; the then-body starts at 1006 and ends at 1020. The separating JMP must be emitted before choosing the false-path target.

**Checked solution, Part A: if layout.** The with-else layout is:

- JZ occupies `[1000,1006)`, field 1002
- Then-body occupies `[1006,1020)`
- Separating JMP occupies `[1020,1025)`, field 1021
- Else-body occupies `[1025,1034)`

The field at 1002 targets 1025: `1025−1006=19`, bytes `13 00 00 00`. The field at 1021 targets 1034: `1034−1025=9`, bytes `09 00 00 00`.

Without else, neither the separating JMP nor else-body is emitted. The JZ targets 1020: `1020−1006=14`, bytes `0E 00 00 00`. It is not the with-else displacement minus only the else-body's length; that false-path target was the beginning of the else-body, not its end.

**Part B: known-target branches.** Target virtual address `0x40040A` corresponds to offset `0x40A=1034`. For the independent direct branches at 1100:

| Form | Field offset | Relative origin | Signed displacement | Complete bytes |
|---|---:|---:|---:|---|
| JMP | 1101 | 1105 | `1034−1105=−71` | `E9 B9 FF FF FF` |
| JNZ | 1102 | 1106 | `1034−1106=−72` | `0F 85 B8 FF FF FF` |

Both API calls receive a target virtual address, but both encodings contain a rel32. Their different instruction lengths produce different relative origins.

**Wrong path to diagnose.** Subtracting the opcode offset gives a target five or six bytes too far forward. Writing the target's low four bytes directly would encode a huge unintended displacement. Patching the if's JZ before its separating JMP makes the false path skip the else-body.

**Next step.** If only negative bytes were wrong, derive `2^32−71` and `2^32−72`, then separate them into low-to-high bytes. If target selection was wrong, draw the true and false edges before calculating.

**Changed reattempt check.** A zero-byte else-body leaves its start and end both at 1025. The JZ remains 19, `13 00 00 00`. The separating JMP now has displacement zero, `00 00 00 00`, reaching the immediately following position. Its five bytes are still present by the changed premise.

Source check: [if layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L49-L70), [direct branch emitters](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L79-L101), and C09's operand-offset patch contract.

## C16-03 — Separate three kinds of nesting

**Hint 1.** An active list head and an outer saved head are different ownership positions even though the same global cell is reused.

**Hint 2.** The inner loop saves B1/C1, resets active heads, patches its own lists, then restores B1/C1. Walking does not clear or free nodes.

**Hint 3.** After the later outer break, the break chain is B3→B1; B2 is not reachable from that head.

**Checked solution.** Active heads pass through `(B1,C1) → (0,0) → (B2,C2) → (B1,C1) → (B3,C1)`. B2 and C2 stand for the inner lists' heads and may represent more than one node if the body has multiple exits. The inner owner patches its break list to the inner exit and its continue list to the inner construct's continue point. The later B3 node records its field and stores B1 as next. The outer completion patches B3 then B1 to the outer exit, and C1's list to the outer continue point.

Node cells remain allocated. The walkers change instruction fields, not owner cells or arena allocation. Restoring a saved outer head makes the completed inner lists unreachable from those active global heads; it does not erase them or reuse their bytes.

For a continue, the unwind count is current switch depth minus the current loop's entry depth. `(3,1)` emits two POP RBX instructions before the jump; `(1,1)` emits none. The first preserves the still-enclosing switch's obligation, and the second preserves the only switch's obligation because it still encloses the loop. These operations are emitted target instructions; the builder's depth counters are not decremented by the continue adapter.

A newly entered valid loop has empty exit lists. An invalid-context statement may also see zero heads. The heads record pending fields, not context validity. The adapters contain no separate validity guard, so a zero head cannot settle legality.

**Wrong path to diagnose.** Joining B2 to B1 causes the outer owner to repatch a completed inner exit. Emitting three restores for `(3,1)` consumes the enclosing switch's saved state too. Reporting a guaranteed outside-loop diagnostic invents a check absent from these adapters.

**Next step.** If lists were mixed, label each node with its owner while keeping target addresses covered. If unwind was wrong, draw the loop between switch levels and count only levels crossed by the continue.

**Changed reattempt check.** `(3,2)` emits one restore. Both switch obligations already open when the loop was entered remain; only the innermost newly entered switch is crossed. A response that says merely “keep the outermost” is incomplete because two saved obligations remain here.

Source check: [list adapters and walkers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L104-L176), [while save/restore](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L192-L226), and [continue adapter](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L605-L620).

## C16-04 — Complete a loop layout

**Hint 1.** Name the two meanings first: continue reevaluates; break exits past the backward instruction.

**Hint 2.** The final five-byte JMP ends at 1005. The condition field is 922. Continue and break offsets were already supplied as fields, not opcodes.

**Hint 3.** The continue displacement is `900−(944+4)`. Do not add two to 944 again.

**Checked solution, Part A: while layout.** The four edges are:

| Edge | Field | Destination offset | Displacement | Four field bytes |
|---|---:|---:|---:|---|
| Condition JZ | 922 | 1005 | `1005−926=79` | `4F 00 00 00` |
| Continue JMP | 944 | 900 | `900−948=−48` | `D0 FF FF FF` |
| Break JMP | 965 | 1005 | `1005−969=36` | `24 00 00 00` |
| Final backward JMP | 1001 | 900 | `900−1005=−105` | `97 FF FF FF` |

Patching breaks before emitting the backward JMP would target 1000, where execution immediately returns to 900. The statement would repeat rather than leave. A continue sent only to the final TEST skips the condition's load/computation and uses whatever RDI value earlier body code left there. Correctness requires reevaluating from the first condition instruction.

**Part B: do comparison.** For `do`, the body top is saved before parsing the body, continues are patched to condition start after the body, and a JNZ at the end repeats to the body top. A false test falls through past JNZ. Breaks target that same post-JNZ position. No initial condition-JZ placeholder exists. The six-byte JNZ has a different length from the while's final five-byte JMP, so this description does not transplant the while's numerical offsets.

**Wrong path to diagnose.** A destination at the opcode's start can be correct; a relative origin at the opcode's start cannot. Keep those roles distinct. Sending every continue to “loop top” erases the semantic difference among the three layouts.

**Next step.** If the destinations were right but byte fields wrong, practice only q+4 arithmetic. If destinations were wrong, trace one body that changes RDI to a value unrelated to its loop condition.

**Changed reattempt check.** Moving the final JMP to 1007 moves its field to 1008 and the end to 1012. Condition JZ becomes 86 (`56 00 00 00`); continue stays −48 (`D0 FF FF FF`); break becomes 43 (`2B 00 00 00`); final JMP becomes −112 (`90 FF FF FF`). The continue edge is unchanged because both its own field and destination stayed fixed.

Source check: [while closure](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L201-L226) and [do layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L367-L400).

## C16-05 — Repair a replay account

**Hint 1.** Source position and the pending-token record are independent pieces of lexer state.

**Hint 2.** The proposed rewrite can fail before it reads any step bytes, and can fail again when it returns to the enclosing parser. Treat those as separate boundaries.

**Hint 3.** On entry, pending=true means the next `cc-next-token-keep` returns the saved `n`, whatever value was just assigned to source position.

**Checked solution.** Failure one is entrance contamination: resetting position to 40 while keeping pending=true lets the expression parser first receive the old token `n`. It does not retokenize `r` from byte 40 on that read. Failure two is return contamination: replay overwrites token fields and pending status. Restoring only cursor 91 and length 140 does not restore the following identifier `n` that the body already read and promised to the caller. Even if the first failure is fixed by clearing pending, the second remains.

The real mark has eight cells: source position, source line, token kind, token numeric/punctuation payload, token string/name address, token string/name length, token keyword ID, and pending flag. Eight cells of eight bytes make 64 bytes. `cc-src-len` is saved separately because it is outside the block. Fields unused by the current token kind are still copied; the mark is not a lossy serialization of only “interesting” fields.

The real order is:

1. Allocate 64 arena bytes M, copy the entire post-body state there, and save M on B.R
2. Save original source length 140 above M on B.R
3. Install length 45 and position 40; clear pending
4. Skip whitespace/comments within that window and parse an expression only if position remains below length
5. Restore length 140 from the top of B.R
6. Restore all eight cells from M, including position 91, the `n` record, and pending=true
7. Let the enclosing parser reread pending `n`; that read clears pending but leaves position 91

Replay leaves its generated step instructions in the output. Restoring lexer state rolls back the input view, not output position. The copied mark remains allocated; there is no local free in this algorithm.

Using `cc-peek-mark` is not an equivalent general replacement. A valid legacy step `++r`, with r a local, takes the [prefix-update path through `cc-name-alone?`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1402-L1432). That helper writes its own lexer snapshot into `cc-peek-mark`, overwriting an outer snapshot stored in the same buffer. A dedicated allocated block preserves the post-body state independently. This counterexample establishes the general ownership problem; it does not claim the particular `r=r+1` fixture itself performs that overwrite.

For a comments/whitespace-only step, the skipper reaches the window end. The comparison is false, so no expression parser is called. Continue still targets the step position, now occupied by the subsequently emitted backward JMP.

**Wrong path to diagnose.** Naming only “save all token fields” omits source line and position. Naming nine snapshot cells silently moves source length into a block where it is not stored. Restoring output position would discard or overwrite the very step code the replay was meant to append.

**Next step.** If you found only one failure, make two columns headed “first read inside replay” and “first read after return.” If the snapshot was correct but ordering was wrong, use B.R=`[…,M,140]` and pop its top explicitly.

**Changed reattempt check.** Restore the complete pending `}` record, cursor 121, and original length 180. The outer compound's next-token operation returns `}` without moving the cursor, clears pending, recognizes its closing brace, and pops its scope. A fresh token read instead of the pending-aware interface would skip that owed closing brace.

Source check: [for replay](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L313-L335), [snapshot layout](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/020-cc-arena.fth#L19-L28), and [mark/reset and shared peek buffer](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/050-cc-lex.fth#L655-L691).

## C16-06 — Protect an outer for

**Hint 1.** The scanner counts punctuation tokens, not bytes that happen to look like parentheses.

**Hint 2.** Start depth at one. The function call and inner arithmetic grouping each add one; the character token does neither.

**Hint 3.** After scanning `f(` depth is two. The character literal `')'` leaves it at two.

**Checked solution.** For the step `r = f(')', (r + 1))` plus the header's closing parenthesis, the relevant sequence is:

| Token or event | Depth after event |
|---|---:|
| Begin step scanning | 1 |
| Function-call `(` | 2 |
| Character token `')'` | 2 |
| Arithmetic grouping `(` | 3 |
| Grouping `)` | 2 |
| Function-call `)` | 1 |
| Header `)` | 0 |

Other tokens do not change depth. The cursor ends just after the header's final `)`, and step-end is cursor minus one. That final character is excluded from replay; both call-closing and grouping-closing parentheses are included. No function call instructions are emitted by this scan; call parsing happens later during replay.

The omitted condition emits integer one using `cc-emit-mov-rdi-imm32`, then calls `cc-mark-int-value` before the test. The metadata helper resets non-lvalue state and, in LP64, records int type. TEST and JZ are still emitted. Omitting both value and metadata would let prior runtime and builder states determine the condition accidentally.

The outer tuple `(Vouter,qOuter,40,59)` is preserved by saving the four old global values at the beginning of the inner `cc-parse-for` call. Its save order is top, end-fixup, step-start, step-end. The inner then creates its own symbol scope, consumes init, and separately saves/resets the loop heads and loop switch-depth. After the inner completes its body, replay, backward JMP, and exit patching, it restores depth and heads, pops its scope, then restores the four globals in reverse order: step-end=59, step-start=40, end-fixup=qOuter, top=Vouter.

The lexer mark serves a different lifetime: it preserves the post-body token/cursor state while one step is replayed. It contains no `cc-for-*` cells, and its separate source-length save contains no loop-head state. Neither can substitute for the outer tuple save. The source range need not describe the exact header used for the scanner subproblem; it is a stipulated nested-context example.

In legacy mode, the `int` token in `for (int k=0; …)` does not take the native declaration branch. The code puts it back and calls the expression parser; this for-init path has no legacy declaration alternative, so the chapter does not claim that declaration-form header is supported. Under the selected native-predicate-true premise, it invokes `cc-native-decl-fwd`, which consumes the declaration and its semicolon. The for-scope retains k through condition, body, and step, then hides it. Merely noticing that `int` is accepted by the general statement dispatcher would select the wrong caller.

**Wrong path to diagnose.** Decrementing for the character literal makes the scanner stop at the function-call close rather than the header close. Restoring only the top address protects the backward edge while leaving step-range and exit-field obligations corrupted.

**Next step.** If the scan was wrong, annotate token kinds above punctuation-looking characters. If the tuple was wrong, pair each global write with its outer saved value and reverse the order on return.

**Changed reattempt check.** Parentheses inside `/* ) ( */` are skipped as comment contents and do not change depth. The header's real `)` changes one to zero. The captured step includes whitespace/comment bytes; replay skips them to the window end and does not invoke `cc-parse-expr`.

Source check: [for saves/init/condition](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L247-L290), [token scanner](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L297-L311), and [reverse restoration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L337-L352).

## C16-07 — Select an interface without importing its implementation

**Hint 1.** The dispatcher has an LP64-only prelude before its ordinary branches. Recognized branches exit instead of falling through.

**Hint 2.** An identifier token is not sent directly to the expression adapter. Its name might have a different role.

**Hint 3.** For `pad=1;`, the ordinary identifier client rules out a typedef and label, then invokes the expression-statement adapter with the original starting token available.

**Checked solution.** In the default profile:

| Input | Dispatcher route | Token boundary |
|---|---|---|
| `;` | Empty-statement branch returns | Semicolon already consumed; no expression call |
| `return;` | `cc-parse-return` | `return` consumed; callee reads the semicolon itself |
| `{}` | `cc-parse-compound` | `{` consumed; compound reads and consumes `}` |
| `struct Node *p;` | `cc-parse-struct-local-decl` | `struct` consumed; callee reads the known tag/name syntax |
| `pad=1;` | `cc-parse-ident-stmt`, then expression fallback | Identifier current and consumed on client entry; expression adapter puts it back |

With LP64 selected and the native type predicate true, the declaration goes to `cc-native-decl-fwd` in the prelude and never reaches the later basic-type declaration branch. At switch depth zero, `case 2: pad=1;` reaches error 170 before registering the case or recursively parsing the assignment. At nonzero depth, the prelude calls `cc-switch-case` and then `cc-parse-stmt-fwd` for the following assignment. Deriving the case's record, generated destination and later matching mechanism belongs to C17. Likewise, the exact identifier lookahead/typedef-label discrimination mechanism is C17's, although its route contract is supplied here.

C15 supplies return and struct-local internals, and this chapter supplies empty/compound/expression-adapter internals. Naming a deferred interface is sufficient for selecting its caller; it does not establish that every provider implementation has been taught or that arbitrary syntax is accepted.

An expression statement may leave a value in RDI. Registers do not accumulate one cell per statement merely by retaining their last value. There is no adapter-level generated PUSH requiring a matching “discard” POP. Any temporary stack saves inside the expression must still balance under the expression parser's contract. A retained register value and a leaked target-stack cell are different claims.

**Wrong path to diagnose.** Routing every `int` token to the legacy parser ignores the prelude. Routing every identifier straight to the expression parser loses typedef declarations and labels. Assuming “unused result” implies a POP imports a different expression-machine convention.

**Next step.** Write only the selected caller chain for three tokens before opening any provider body. If the error concerned runtime storage, label each emitted PUSH/POP rather than inferring one from syntax.

**Changed reattempt check.** Legacy identifier routing still begins with `cc-parse-ident-stmt`, but a resolved `sk-typedef` now selects declaration handling. It obtains the typedef's encoded type from its symbol payload, extracts base and pointer depth, and calls `cc-parse-decl-with-base`. The starting identifier is consumed as the type name; it is not put back as a runtime variable expression.

Source check: [expression adapter and identifier client](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L828-L858) and [full dispatcher](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L865-L905).

## C16-08 — Change the triangle's behavior deliberately

**Hint 1.** Follow the branch destinations before computing totals. A for-continue reaches the step; a break reaches beyond the backward JMP.

**Hint 2.** At r=1, the inserted condition is evaluated before any `w[r]` assignment, line call, or star update.

**Hint 3.** In the continue variant, the body-work rows are zero, two, and three. The step still increments r after the skipped row.

**Checked solution.** With the early continue:

| r on body entry | Selected action | Assigned element | `t.stars` after that visit | r after step |
|---:|---|---|---:|---:|
| 0 | Ordinary body work | `w[0]=1` | 1 | 1 |
| 1 | Continue before work | None | 1 | 2 |
| 2 | Ordinary body work | `w[2]=5` | 6 | 3 |
| 3 | Ordinary body work | `w[3]=7` | 13 | 4 |

The next condition fails with r=4. Final `t.stars` is 13, so equality with sixteen is false and the following `return 1;` is selected. `w[1]` remains unassigned, but the line call and update that would read it are also skipped. Every reached read of another `w[r]` follows its assignment in that same row. This conclusion depends on the exact body given; it is not a claim that arbitrary skipped initialization is safe.

Replacing only continue with break gives body work only for r=0. At r=1 the break leaves immediately, before its step. Only `w[0]=1` is assigned, final r=1, and `t.stars=1`. The later equality again fails and selects return one. No later array read is reached in that loop. The difference in r is an observable consequence of bypassing the step, not a different condition parser.

**Independent layout rubric.** Use the supplied initialized, nonconflicting writable target counter; its declaration and output mechanism are outside this task. Place one counter increment at the entry of the step block, before the original `r=r+1` step. Continue fixups must target that increment. Ordinary body fallthrough reaches it too. The original step then executes, followed by the backward JMP to condition start. Break and false-condition edges target after the backward JMP, so they skip the counter and step. Keep all existing builder-state preservation and token replay duties unchanged; the counter is target state, not another use of a builder scratch cell.

A satisfactory answer retains the supplied initialization premise, distinguishes the counter's target storage from compiler bookkeeping, shows the four relevant edges, increments exactly once for each step entry, and preserves break behavior. Under the bounded examples, the early-continue variant increments four times; the break variant increments once. Placing the increment at body entry would count the breaking visit. Placing it after the continue target while some path jumps beyond it would miss continues. Placing it before condition evaluation would count the final failed test.

An alternative after the original step can be acceptable if the design explicitly counts normally completed steps and states its assumptions about exits/faults during that step. The entry placement matches the prompt's stated step-entry event; a completed-step alternative deliberately changes the counting criterion. No implementation change is requested or tested here.

**Next step.** If totals were wrong, retain the correct edge layout and make one row per body entry. If edges were wrong, temporarily ignore values and label “work,” “step,” and “exit.” Then attempt the changed placement with the result table covered.

### Small change: move the continue

**Changed reattempt check.** Moving the r=1 continue after the `t.stars` update changes none of the original triangle's totals. That statement is already the final body work, so jumping to the step skips no additional work. All four array elements become 1,3,5,7; final r=4, `t.stars=16`, and the valued return of sixteen is selected. The outcome differs from the early-continue case because the skipped interval is now empty, not because continue has changed its destination.

Source check: [canonical triangle](../chapters/01-compiler-entry-and-profile.md#read-enough-c-to-follow-the-example), [for continue target and replay](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L313-L338), and [for break completion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L340-L352).

## Return for a changed attempt

Choose a [changed prompt](../chapters/16-conditions-and-loops.md#changed-reattempts-with-answers-closed) with this page covered. If you need to reconstruct your starting state, use the chapter's [if-owner checkpoint](../chapters/16-conditions-and-loops.md#branch-owner-checkpoint) or [outer-for tuple](../chapters/16-conditions-and-loops.md#keep-the-outer-fors-state) before attempting the new case.
