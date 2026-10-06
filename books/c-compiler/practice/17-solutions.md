# C17 practice help: switches, labels, and nonlocal control

[Back to the chapter](../chapters/17-switches-labels-and-nonlocal-control.md)

These are checked manual derivations against revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`, using the chapter's explicit profiles and paper coordinates. No compiler, Forth, C example, generated program, build, or bootstrap was run. Correct answers here are source-reading and derivation results, not observed execution or evidence that a learner has mastered the material.

Use as much help as you want: the first hint identifies the distinction, the second exposes the decisive state, and the third supplies a partial step. The solution is available without a required waiting period. After feedback, close this page and use a changed reattempt from the chapter; copying a visible solution checks a different capability from an independent attempt.

## Entry check

Questions 1–2 support the first session (question 1 is for its byte-layout extension); question 4 belongs to ownership, and question 3 to the identifier session.

1. The displacement is `160−(101+4)=55`, bytes `37 00 00 00`. Field offset 101 is neither the JMP's opcode offset nor a target virtual address
2. No. Builder `>r` saves a Forth cell on the builder's return stack. A target PUSH emitter writes future machine-instruction bytes
3. No. Reset restores the saved pending flag, here zero. The expression-statement adapter later puts the restored identifier back
4. No. Symbol count controls visibility. The local-slot allocation count is separate and is not restored by scope pop

If only item 3 was wrong, reconstruct “current but consumed” versus “pending” without doing any branch arithmetic. If item 1 was wrong, label q and q+4 before subtracting. If item 2 or 4 was wrong, use distinct columns for builder metadata and generated machine/storage effects.

## C17-01 — Count the saves crossed

**Hint 1.** Break uses the nearest break owner; continue uses the nearest loop's owner.

**Hint 2.** Current switch depth is two, but L's saved depth is one. The destination may itself perform cleanup.

**Hint 3.** Continue emits `2−1=1` pop before its jump. It does not visit B's end-A.

**Checked solution (a).** Break adds its field to B's break list and emits no pre-jump pop. B's end-A targets the single POP RBX restoring B's entry save. A's save stays in place. Continue adds its field to L's continue list, with one pre-jump pop; its loop-specific destination is L's condition/top/step as appropriate to its form, inside A. It bypasses B's pop and needs no additional switch pop at that loop target.

Valued return places its result through the selected return-value path, emits two switch pops, then the function epilogue. There is no break or continue list for this return. The first pop restores B's saved RBX state and the second A's. Emitting the return does not change the builder's lexical depth: it is still parsing inside both switch bodies and must keep depth two for later source there.

**Wrong path to diagnose.** Adding a pre-jump pop for break and retaining end-A's pop restores twice. Using depth two as continue's pop count also removes A's still-needed save. Reducing parser depth after return mistakes a generated path for parser traversal.

**Next step.** If ownership was wrong, name each destination before counting anything. If the count was wrong, draw the source and destination depth numbers with only the crossed saves between them.

**Changed reattempt check (a).** Without B, current depth and L's snapshot are both one. Break now belongs to L and emits no switch pops; its loop-end destination is still inside A and adds no switch cleanup. Continue emits `1−1=0` pops and also remains inside A. Both retain A's save. Return emits one switch pop before the epilogue.

**Checked solution (b), after [native depth adjustment](../chapters/17-switches-labels-and-nonlocal-control.md#native-gotos-reconcile-source-and-destination-depth).** For an already-defined LP64 target at depth one, adjustment emits one pop, then its jump. The source/target difference is again one, though this jump uses label metadata rather than a loop snapshot. The target lies inside a switch, so it does not satisfy the legacy goto restriction. That legacy branch would emit all two pops without consulting destination depth.

**Changed reattempt: after part (b).** An LP64 goto to the stated depth-one label needs no adjustment. Legacy still unconditionally emits one pop and does not support that target contract.

Source check: [switch exit and break/continue](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L584-L620), [return/unwind](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L759-L803), and [goto adjustment](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L745-L802).

## C17-02 — Remove the default without losing the exit

**Hint 1 (a).** Follow the no-match path to the saved-RBX cleanup. Removing the default body does not remove the final no-match jump or the unconditional jump after the last body.

**Hint 2 (b).** The explicit break still ends at 1033. Emit the five-byte body-end JMP there before recording selector start.

**Hint 3 (b).** Selector start becomes 1038. The reverse case chain still occupies 26 bytes.

**Checked solution (a).** With n=9, both tests fail and the final JMP reaches the pop without executing any case body. With n=2, dispatch reaches the first body, falls through the second, then takes its explicit break to the pop. Removing default does not change this matching-case path. Omitting the body-end JMP would allow any reachable fall-through beyond the bodies to enter the selector again. Omitting the final no-match JMP would be a separate source change, even where falling directly into the pop could appear equivalent in this particular layout.

**Checked solution (b).** Removing a body moves all later output. Case bodies and their addresses remain V2 at offset 1009 and V5 at 1021. Explicit break remains at 1028–1032. With no default body, the body-end JMP occupies 1033–1037. The selector starts at 1038:

- CMP 5 occupies 1038–1044; JE occupies 1045–1050
- CMP 2 occupies 1051–1057; JE occupies 1058–1063
- No-match JMP occupies 1064–1068
- End-A/POP is 1069; the next instruction is 1070

| Branch | q | Target offset | Displacement | Four bytes |
|---|---:|---:|---:|---|
| Initial selector jump | 1005 | 1038 | 29 | `1D 00 00 00` |
| Explicit break | 1029 | 1069 | 36 | `24 00 00 00` |
| Body-end jump | 1034 | 1069 | 31 | `1F 00 00 00` |
| JE case 5 | 1047 | 1021 | −30 | `E2 FF FF FF` |
| JE case 2 | 1060 | 1009 | −55 | `C9 FF FF FF` |
| No-match jump | 1065 | 1069 | 0 | `00 00 00 00` |

The no-match displacement is zero because the next instruction is the pop. The source still emits this jump, records it, and patches it. “Zero displacement” and “no emitted instruction” are different facts.

**Wrong path to diagnose.** Keeping selector start 1048 forgets the removed ten bytes. Patching the initial branch before emitting the body-end JMP would send runtime to that exit jump and skip dispatch. Moving case addresses when only a later default was removed changes unaffected coordinates.

**Next step.** If layout was wrong, rebuild only the output intervals before recalculating fields. If layout was right, check whether each subtraction starts at q+4 rather than its opcode.

**Changed reattempt check (a).** Runtime takes the initial jump to a selector with no comparison pairs, then the no-match jump, then the pop; it does not normally execute the body-end jump.

**Changed reattempt: after part (b).** The empty-switch entry is PUSH at 1000, MOV at 1001–1003, initial JMP at 1004–1008. The empty body still gets its body-end JMP at 1009–1013. Dispatch starts at 1014 and has no comparison pairs. No-match JMP is 1014–1018, pop is 1019, and the next instruction is 1020. Patches are q=1005 to 1014: 5, bytes `05 00 00 00`; q=1010 to 1019: 5, `05 00 00 00`; q=1015 to 1019: 0, `00 00 00 00`.

Source check: [body-end, selector, and common exit ordering](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L563-L596).

## C17-03 — Convert before choosing an encoding

**Hint 1.** The constant is converted using the controlling type before comparison selection.

**Hint 2.** Four-byte control masks to 32 bits; signed control sign-extends that result. A short CMP sign-extends its encoded immediate regardless of the source's unsigned type.

**Hint 3.** In case (b), K becomes `0x00000000FFFFFFFF`, not the all-ones 64-bit cell.

**Checked solution.** JE occupies six bytes in every row. The short compare is seven bytes; the wide comparison sequence is ten-byte MOVABS plus three-byte register CMP, thirteen bytes.

| Case | Converted K | Selected compare | Compare plus JE |
|---|---:|---|---:|
| (a) signed 32-bit, −1 | −1 | Sign-extended imm32 | 13 bytes |
| (b) unsigned 32-bit, −1 | 4,294,967,295 | MOVABS plus register CMP | 19 bytes |
| (c) signed 32-bit, 4,294,967,301 | 5 | Sign-extended imm32 | 13 bytes |
| (d) signed 64-bit, 2,147,483,648 | 2,147,483,648 | MOVABS plus register CMP | 19 bytes |

For (a), masking gives 4,294,967,295, then the signed bit-31 test subtracts 4,294,967,296 to recover −1. For (c), masking leaves five and no sign correction is needed. In (d), the four-byte conversion branch does not run, but the value lies above signed-32 range.

In (b), short field `FF FF FF FF` would compare RBX with 64-bit −1, `0xFFFFFFFFFFFFFFFF`, rather than `0x00000000FFFFFFFF`. Equality of the low 32 bits is insufficient for this 64-bit CMP. Both source labels −1 and 4,294,967,295 convert to the same unsigned-32 K. Registration prepends both nodes without a duplicate-value check. The reverse-source selector encounters the later registered equal value first. These are duplicate converted labels, so our distinct-case semantic argument no longer applies; do not reinterpret the observed registration behavior as acceptance of a valid C case set.

**Wrong path to diagnose.** Choosing width from the source spelling before conversion gives the wrong answer for (c). Assuming unsigned means “use imm32” confuses the source type with x86 sign extension. Treating duplicate illegality as an implemented check invents a branch absent from registration.

**Next step.** If conversion was wrong, calculate mask and optional subtraction separately. If encoding was wrong, compare the full 64-bit values rather than only the four stored bytes.

**Changed reattempt check.** For signed 64-bit K=−2,147,483,649, no four-byte conversion applies. K is below signed-32 range and uses the wide thirteen-byte comparison sequence, nineteen bytes with JE. Its full immediate bit pattern is `0xFFFFFFFF7FFFFFFF`, stored `FF FF FF 7F FF FF FF FF`. Truncating to the short field would store `FF FF FF 7F`, which sign-extends to positive 2,147,483,647, a different value.

Source check: [label conversion and compare selection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L449-L486).

## C17-04 — Restore one owner without stealing another

**Hint 1.** Save the outer tuple before resetting current heads. Do not add a continue-head save that the switch does not perform.

**Hint 2.** Ordinary compound scope and the switch's inline braces are separate mechanisms.

**Hint 3.** Legacy switch exit leaves its directly declared local visible in the surrounding symbol prefix; the ordinary inner compound removes only its own local.

**Checked solution.** B.R saves C, D, B, T in order. Current case/default/break become zero; expression parsing establishes the inner controlling type. Switch depth rises from one to two; the initial jump field is saved above the tuple. Continue head K and loop snapshot zero are not replaced by this entry. At inner completion, its own branch list is patched to its pop, its saved initial field has already been used, and depth returns to one. T, B, D, C are restored in that order.

Legacy symbol count begins M. The directly declared local makes it M+1. The ordinary compound saves M+1, adds its local to reach M+2, then restores M+1. Legacy switch completion performs no additional scope pop, so final symbol count is M+1. Under LP64 the inner switch first saves M; after the same nested-compound sequence it pops that switch scope and restores M. With the supplied one-slot-per-declaration premise, local count ends L+2 in either profile. Neither scope pop reverses those allocation claims.

Inner case nodes and break-fixup nodes remain allocated in the arena after control variables are restored; the walkers and restores do not free them. Their current-owner heads are no longer the active outer heads. Any continue inside the inner switch would prepend to the enclosing loop's existing chain K, and those new nodes must remain reachable after the switch ends. “Leave the continue owner alone” does not mean freeze its head value: valid inner continues may extend that same owner's list.

**Wrong path to diagnose.** Giving both profiles final symbol count M imports the native scope branch into legacy. Restoring an old continue value after inner continues would discard their new pending jumps. Restoring local count L mistakes symbol visibility for storage allocation.

**Next step.** Keep three columns for current control owners, visible symbol count, and monotonic slot count. If only one column failed, replay that column without changing the others.

**Changed reattempt check.** Replacing the inner switch with a loop means the loop saves/replaces both break and continue heads and saves the prior loop snapshot. Its new loop snapshot is the still-open outer switch depth one. The outer case head C, default D, and type T remain current; no switch-depth increment or entry PUSH RBX is caused by entering the loop. On loop completion, it restores its prior loop snapshot and both heads. This selective ownership differs from a switch even if both constructs can collect breaks.

Source check: [switch save/restore and native scope gate](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L508-L596), [while ownership](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L192-L226), and [symbol scope](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/070-cc-sym.fth#L152-L167).

## C17-05 — Use the selected table, not an imagined larger one

**Hint 1.** Capacity checks the post-creation count. IDs start at zero.

**Hint 2.** Finding an existing spelling does not create a row or require one more table entry.

**Hint 3.** Row 1023 lies 8,184 bytes after its selected column's base, not 1,023 bytes after it.

**Checked solution.** Starting at count 63, `count+1=64` passes the default cap. The new row gets ID 63 and count becomes 64. Finding that same name returns 63 and leaves count 64. A different new spelling would require count 65; `cc-label-create` fails with 171 before storing the new row or incrementing count. No successful ID is returned for that request. A table exactly at capacity can still resolve existing names.

In the independent definition case, `cc-define-label` finds the row and tests its target cell. After one definition stores a nonzero generated V, a second definition dies with 172. This is a definition-state check, not a second-name-insertion check; `find-or-create` first resolves the same row.

For direct base A, row stride is eight bytes and `1023*8=8184`:

| Selected cell | Calculation | Builder address |
|---|---|---|
| Target V | `A+16384+8184` | A+24,568 |
| Fixup head | `A+24576+8184` | A+32,760 |
| Definition depth | `A+32768+8184` | A+40,952 |
| First byte after all arrays | `A+1024*40` | A+40,960 |

The depth cell spans through A+40,959 inclusive. These are builder addresses of metadata cells; the value stored in the target cell is a different address belonging to the generated image. Increasing only `cc-label-limit` would permit indexing past the 64-entry backing arrays. The direct selector replaces all five pointers together and provides the 40,960-byte allocation. It does not enlarge the arena containing separately allocated goto nodes.

**Wrong path to diagnose.** Returning ID 64 for the first request is a count/ID off-by-one error. Growing only the target-address column leaves other columns short. Treating A+24,568 as the label's target V confuses a cell address with its contents.

**Next step.** For capacity errors, keep “old count / new ID / proposed count” in three cells. For address errors, write column base plus eight times ID before calculating.

**Changed reattempt check.** Function entry sets count to zero. It need not clear old backing bytes because lookup now ranges over no rows. Creating the next row uses ID zero, overwrites its name address and length, explicitly zeros target/fixup/depth, then makes count one. Other rows' old bytes remain outside the active prefix. The old row-zero node list is no longer reached through the new zero head; this does not reclaim its arena storage. A retained name pointer in an inactive old row cannot make its spelling visible through count-bounded lookup.

Source check: [selected storage, accessors, and creation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L635-L737), and [legacy per-function reset](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L273-L280).

## C17-06 — Close a legacy forward reference

**Hint 1.** Each legacy node has two cells, and each new reference prepends to the row's head.

**Hint 2.** Required pops were already emitted at the source. Label definition only fills the branch fields.

**Hint 3.** The head after the second reference is the q=1701 node; its next pointer reaches the q=1601 node.

**Checked solution.** With symbolic builder addresses N1 and N2:

```text
done row: target=0, head=N2
N2: {1701,N1}
N1: {1601,0}
```

The first source emits two POP RBX instructions before its JMP. The second emits none. Defining `done` outside switches stores target `0x400000+1800` and depth zero, then walks the two-cell list:

| Field | Calculation | Displacement | Four bytes |
|---|---|---:|---|
| 1701 | `1800−(1701+4)` | 95 | `5F 00 00 00` |
| 1601 | `1800−(1601+4)` | 195 | `C3 00 00 00` |

The later direct JMP at 1900 has opcode `E9`, field q=1901, and next-instruction offset 1905. Its displacement is `1800−1905=−105`. Complete bytes are `E9 97 FF FF FF`. It uses the already stored V; no new forward node is needed.

Definition leaves the owner head N2 unchanged and does not free N1 or N2. The fields are patched, but the records remain allocated and the head is not cleared by this consumer. A future function reset/new-row creation prevents those old records from becoming a new label's pending work.

For a never-defined target in a separate legacy function, do not promise 174. The legacy function completion sequence does not call `cc-native-finish-gotos`, and the legacy goto path has left its placeholder awaiting a definition that never arrives. This is an unresolved implementation obligation for malformed/unsupported input, not evidence that an unrelated native check will run. No particular valid execution behavior is claimed for the unfinished output.

**Wrong path to diagnose.** Waiting until label definition to emit the source pops would put cleanup at the wrong runtime place and ignore distinct source depths. Clearing the head in the answer invents an operation this consumer lacks. Saying every unresolved name gets the unresolved-function diagnostic confuses separate namespaces and finishers.

**Next step.** If node order was wrong, draw head updates for only two references. If completion was wrong, name the exact word that receives the final address and list what it actually writes.

**Changed reattempt check, after the [native depth-adjustment section](../chapters/17-switches-labels-and-nonlocal-control.md#native-gotos-reconcile-source-and-destination-depth).** From depth one to a known target also at depth one, legacy emits one pop because it always uses the full source depth; it does not read destination depth. A later normal switch exit would expect the save that has already been removed, so the chapter excludes this legacy target. LP64 calculates `1−1=0`, emits no adjustment, and jumps directly. This comparison establishes the local depth behavior, not all possible same-depth switch-ancestry or source-language legality rules.

Source check: [definition, adjustment, and both goto branches](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L724-L802), and [legacy completion without the native finisher](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L293-L310).

## C17-07 — Finish native gotos from different depths

**Hint 1.** Patch each original site to the start of its own trampoline before emitting that trampoline's adjustment.

**Hint 2.** Each POP is one byte and each final JMP is five bytes. The second trampoline begins after all six bytes of the first.

**Hint 3.** The first block begins at 3400 with one pop and ends at 3406. The second begins at 3406 with two pops.

**Checked solution.** Process the head node `(3101,1)` first, target depth zero:

- Patch original q=3101 to trampoline offset 3400: `3400−3105=295`, bytes `27 01 00 00`
- Emit POP RBX (`5B`) at 3400
- Emit JMP at 3401–3405, with q=3402
- Its displacement to label offset 3300 is `3300−3406=−106`, field bytes `96 FF FF FF`

Then process `(3001,2)`:

- Patch original q=3001 to trampoline offset 3406: `3406−3005=401`, bytes `91 01 00 00`
- Emit POP RBX at 3406 and another at 3407
- Emit JMP at 3408–3412, with q=3409
- Its displacement is `3300−3413=−113`, field bytes `8F FF FF FF`

The first free output offset is 3413. The two final jumps have the same destination but different origins. Their original branches also point at different trampoline starts. No adjustment belongs in a builder label-table cell: the cells describe what instructions must be emitted.

The finisher's current lexical depth reflects function-end parsing, not either earlier source path. Using its zero would emit no pops and leave the generated saves outstanding at the destination. The native nodes retain those historical source depths precisely to avoid that mistake. The generic walker expects node+8 to be a next pointer, whereas the native node puts source depth there and next at +16. Feeding it these nodes would follow values one or two as if they were builder addresses. It would also lack the adjustment and trampoline operations entirely.

The ordinary function-end epilogue precedes these blocks. Normal fall-through returns; only a patched source goto enters its trampoline. A reached trampoline jumps back to the true label rather than falling through into the next trampoline.

**Wrong path to diagnose.** Patching both sites straight to 3300 loses cleanup. Patching both to 3400 gives one source the wrong adjustment count. Treating the node's source depth as the destination depth reverses which fact was known at creation.

**Next step.** If adjustment counts were wrong, cover all offsets and solve `(source,target)` pairs first. If branches were wrong, freeze the correct instruction layout and calculate each field from its own end.

**Changed reattempt check.** Set destination depth to three. The first node now needs two PUSH RBX instructions (`53`), at 3400 and 3401. Its JMP occupies 3402–3406, q=3403, displacement `3300−3407=−107`, bytes `95 FF FF FF`. The original q=3101 still targets 3400 with 295, bytes `27 01 00 00`.

The second block starts at 3407 and needs one PUSH at 3407. Its JMP remains at 3408–3412 with q=3409 and displacement −113, bytes `8F FF FF FF`. Original q=3001 now targets 3407: `3407−3005=402`, bytes `92 01 00 00`. First free offset remains 3413 because the two blocks still contain three one-byte adjustments and two five-byte jumps in total. The equal total size does not imply unchanged internal boundaries or equivalent saved values. These pushes do not execute the skipped switch controlling expressions.

Source check: [native node, adjuster, and finisher](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L745-L768), [117 completion order](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/117-cc-native-program.fth#L64-L74), and [121 completion order](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L1245-L1253).

## C17-08 — Preserve the right token and the right parser boundary

**Hint 1.** Ordinary symbol lookup occurs before colon lookahead. A consumed token can remain current without being pending.

**Hint 2.** False lookahead resets to the original mark; true lookahead commits its fresh read. Only the false branch later invokes the expression adapter's putback.

**Hint 3.** Immediately after the false colon peek for `pad=2;`, current is still `pad`, pending is zero, and the cursor is again after `pad`.

**Checked solution.** The dispatcher has consumed each leading identifier, so pending is initially zero.

For `int_ptr p;`, ordinary symbol lookup finds `sk-typedef`. Its payload supplies int base and inherited pointer depth one to `cc-parse-decl-with-base`. The colon detector is not called. That declaration parser owns `p` and the final semicolon; the declarator creates the depth-one local under the supplied type contract. Do not count its own function-pointer lookahead, if consulted within declaration parsing, as an invocation of the colon detector.

For `done /* gap */ : pad=1;`, lookup does not select the typedef branch. The adapter saves `(name-address,name-length)` on B.D, marks the lexer, and freshly tokenizes past the comment to `:`. The test succeeds; no reset or putback occurs. Current token is the consumed colon, pending zero, and the cursor is after the colon. The saved name pair is essential because current token fields no longer reliably describe `done`. Definition consumes the pair and binds the current output address. Under legacy, the adapter now returns. `pad` is the next unread token for the surrounding repeated body parser's next statement call.

For `pad=2;`, lookup finds an ordinary local, not a typedef. The adapter saves the name pair and marks the consumed-identifier state. Fresh lookahead reads `=`, fails the colon test, and restores the mark. Current is `pad`, pending zero, cursor after `pad`; all other lexer-state cells also match the mark. The adapter discards the saved name pair and calls `cc-parse-expr-stmt`. That adapter puts `pad` back, setting pending true. Expression parsing's first keep-read returns `pad` and clears pending without moving the cursor. A later fresh read gets `=`. The expression and its semicolon are then consumed through the normal expression-statement interface.

Under LP64 with the named native type-start provider, `int_ptr p;` is recognized earlier by the dispatcher's native-declaration branch and bypasses `cc-parse-ident-stmt`. The non-typedef `done` reaches the label branch, which defines it and recursively parses `pad=1;` before returning. If `done` instead resolves as a typedef, legacy identifier classification selects declaration before any colon test, and the native-first predicate does likewise in the LP64 dispatcher. A colon does not get first priority in those actual routes. This is the implementation's ordering, not a claim that all legal C namespace collisions are handled.

**Wrong path to diagnose.** Calling `cc-expect-punct-c` for a second colon consumes the first token of the labeled statement. Marking the failed peek's identifier pending before the expression adapter invents a state transition. Letting the colon overwrite the only saved name loses the label's identity. Assuming native typedefs always use the legacy declarator ignores the earlier dispatch branch.

**Next step.** If token state was wrong, draw one column each for current kind/name, pending flag, and source cursor. If parser ownership was wrong, mark where each called parser returns before continuing with source tokens.

**Changed reattempt check.** In `while (n) again: pad=1;`, the while calls its body parser once. Legacy's label adapter consumes through `again:` and returns immediately, so the while finishes its loop code without including the following assignment in that body call. The enclosing repeated body reader next receives `pad=1;`. This is why the chapter does not promise full labeled-substatement behavior for the legacy single-body contract.

Under LP64, label definition is followed by recursive `cc-parse-stmt-fwd`, which consumes `pad=1;` before returning through the label adapter to the while. That assignment is included in the while body's emitted region. These are source-derived parser boundaries, not executed outcomes. The label's non-typedef premise matters because otherwise the earlier declaration route would intervene.

Source check: [colon detector and identifier adapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L819-L858), [native-first dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L865-L879), and [actual native type-start predicate](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth#L83-L91).

## A later independent check

After another topic, choose one fresh statement sequence and write only three products: the next-token owner, the pending field's completion event, and the generated saved-register obligation at its destination. Use source and chapter navigation as references if useful, but leave the worked solutions closed. Then change one meaningful assumption: remove a default, move the destination's switch depth, or make the leading name resolve as a typedef.

If the original works but the changed case fails, compare the first differing transition rather than concluding that the whole mechanism is missing. If both work, explain the profile restriction without relying on a generic “C does this” rule.
