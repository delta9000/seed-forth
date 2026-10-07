# C18 practice help: functions and call-frame accounting

[Back to the chapter](../chapters/18-functions-and-call-frame-accounting.md)

These are checked manual derivations against the pinned source, not executed C/Forth results. Unless a question explicitly selects a later provider, use the legacy profile and default hooks. Builder metadata and target stack memory belong to different executions. Hexadecimal addresses are paper coordinates with adequate valid storage assumed.

The hints move from the relevant distinction to a partial transition. Use the full solution whenever it helps; changed-case answers are here so the chapter's retry prompts remain answer-free.

The chapter's opening story ends with a small [one-more-local check](#one-more-local). [C18-04](#c18-04--reconstruct-a-complete-call-frame) develops the full call trace. The remaining answers follow their stable exercise IDs.

## One more local

The reserved frame remains 256 bytes. Its size was fixed before the body revealed `scratch`. The two parameters already occupy slots 0 and 1, so `scratch` takes slot 2 at `Q−8*(2+1)=Q−24`, or `0x0FD8` for Q=`0x0FF0`. Its declaration has no initializer, and reserving the frame does not clear its contents. No initial zero is promised, and no additional PUSH is needed to reserve the slot.

Claiming `scratch`'s slot changes the compiler's slot count inside the frame already reserved; this uninitialized declaration emits no target instruction. A temporary PUSH instead changes the target RSP below that frame.

## Entry check

A compiler scope pop restores the visible symbol count; it neither emits a stack instruction nor changes target RSP. A local payload zero names slot 0, at `RBP−8`; an unresolved `sk-func` value zero means its callable address has not yet been supplied. An inner call's own balanced staging preserves an outer staged argument rather than removing it. Balance restores the inner staging's entry RSP, which need not be the function body's baseline.

If these were mixed together, keep two columns labeled “builder” and “target,” then annotate every zero or counter with the kind of record that gives it meaning.

## C18-01 — Publish, patch, and retain

**Hint 1.** The old promises belong to the prototype; the surviving definition is a newly appended symbol.

**Hint 2.** The call field needs `target−(base+field-offset+4)`. The address field needs the target itself. The scope marker is a count, not the new ID.

**Hint 3.** Starting at count 8, the new definition receives ID 8 and makes the count 9.

**Checked solution.** Save prior ID 2 before appending. Output offset 1200 is hexadecimal `0x4B0`, so the definition's target is `0x4004B0`. New ID 8 carries kind `sk-func`, legacy int/depth 0, and that address.

- Call field 901 receives `1200−(901+4)=295`, or `0x127`: bytes `27 01 00 00`
- The prior call-head cell is then set to zero
- Address field 930 receives `0x4004B0`: bytes `B0 04 40 00 00 00 00 00`
- The prior address-head cell is then set to zero

Both walkers receive fetched head values; the explicit clears write to the head cells. Neither frees arena nodes. Patching does not advance output. The prototype's old value is not rewritten by this consumer.

The function scope saves count 9. Parameters receive IDs 9 and 10 with slots 0 and 1, producing count 11. With no other lasting file-scope additions in this body, final pop restores 9, retaining IDs 0–8 and therefore the definition.

Looking up after append would select ID 8 and miss the prototype's pending lists. Pushing scope before append would save 8; final pop would hide the newly defined function. These are distinct ordering mistakes.

**Wrong path to diagnose.** Patching the call with absolute bytes confuses the two field representations. Clearing only the call head leaves the address promises reachable. Final count 8 loses the definition; final count 11 leaves parameters visible.

**Changed cases.** Without a prior match, the saved ID is −1; neither prior-head walk nor clear runs. The definition is still appended and included in the marker. If the newest matching row is a nonfunction, its ID is saved, but the kind guard skips both lists. The consumer does not search behind it for an older function and does not treat nonfunction auxiliary cells as call heads.

**Next step.** If only one number was wrong, recompute the relative field from its end. If lifetime was wrong, track only count, ID, and marker before adding patch bytes.

Source check: [`114`, publication and both clears](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/114-cc-func.fth#L232-L281).

## C18-02 — Follow the parameter tokens

**Hint 1.** A full mark restores the current token as well as the reader position. Putback and reset are different operations.

**Hint 2.** Only a first `void` followed immediately by `)` selects the special zero-parameter route.

**Hint 3.** For `(void *p)`, the peek's answer is false; resetting restores the consumed `void`, which is then put back for ordinary parsing.

**Checked solution.** Each independent parse begins by setting parameter count zero.

| Input | Decision sequence | State on successful return |
|---|---|---|
| `()` | Read `)` and finish | `)` current/consumed, count 0 |
| `(void)` | Read `void`; mark; read `)`; save true; reset to consumed `void`; read `)` again | `)` current/consumed, count 0 |
| `(void *p)` | Read `void`; mark; read `*`; save false; reset; put `void` back; ordinary loop | `)` current/consumed, count 1 |

In the third case the ordinary loop selects `ty-int` for non-char `void`, adds one star, and requires identifier `p`. It appends an `sk-local`, int-base depth one, slot 0, descriptor zero; local count becomes one. The encoded type is `2*65536+1=131073`. The scanner has not preserved a distinct void base for this parameter.

Unnamed `(int)` reaches the required-name step with current token `)`, so error 183 applies. In the separate ordinary-loop suffix `int x]`, the name is valid and its row/slot have been recorded; `]` is the noncomma token, replayed and rejected as the closing delimiter with error 184. Error handling terminates; no rollback of that row is promised.

**Wrong path to diagnose.** Ending with `)` pending would let the next expectation consume it instead of `{`. Treating the false peek as if `*` were still current skips the restored `void` state. Giving error 184 to unnamed `int` skips the earlier name requirement.

**Changed cases.** `(void **p)` follows the same false-peek route but adds two stars, producing int-base depth two, slot 0, descriptor zero. If the input is `(const void **p)`, the first token is `const`, so the special-void test is not taken at all. The ordinary loop skips `const`, then produces the same row. In contrast, `(const void)` is not recognized as the exact zero-parameter special case by this helper; the ordinary loop eventually requires a name and reaches 183 at `)`.

**Next step.** If the type was correct but the delimiter wrong, retry with only three token columns: current token, pending flag, next unread token.

Source check: [`114`, parameter loop and special case](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/114-cc-func.fth#L45-L147).

## C18-03 — Keep type and descriptor channels separate

**Hint 1.** The type word records base/depth. An associated descriptor is a separate fact.

**Hint 2.** A raw `struct` parameter uses strict tag lookup. A typedef parameter takes its encoded type from the symbol's payload and clears the pending descriptor.

**Hint 3.** After the first parameter, local count is one. Therefore `fn` is installed with payload 1, irrespective of its symbol ID.

**Checked solution.** Begin with both counts zero and a valid function scope:

| Name | Kind | Type | Payload/slot | Associated descriptor |
|---|---|---|---:|---|
| `p` | `sk-local` | struct, depth 1 (`196609`) | 0 | D |
| `fn` | `sk-local` | function, depth 1 | 1 | 0 |
| `s` | `sk-local` | char, depth 1 (`65537`) | 2 | 0 |

The leading qualifier is consumed. For `s`, `unsigned` initially selects int, but the later basic keyword `char` changes the base to char; one star then sets depth one. This legacy account does not preserve a distinct unsigned-char ABI parameter classification.

Both counts finish at three, and `)` is consumed. For `fn`, let its source name span be `a/u` and its inherited function-pointer word be F. At the append boundary the builder stack is `[a,u,sk-local,F,1]`, top at right. `cc-sym-add` consumes those five items and returns the new ID; the descriptor setter then receives zero and that ID.

The typedef preserves its payload's base and existing pointer depth. It does not cause this parameter producer to copy an associated struct descriptor, function signature, or qualifier record. An encoded function-pointer type is not a complete checked call signature.

**Wrong path to diagnose.** Giving `fn` slot zero restarts allocation per parameter. Associating D with `fn` leaks a prior parameter's descriptor across the explicit clear. Treating the descriptor as the runtime pointer argument crosses builder and target memory.

**Changed case.** If `FUNCTION` still resolves to the typedef, `FUNCTION *fn` adds one to inherited depth one, giving function base/depth two. If a newer ordinary local named `FUNCTION` instead wins lookup, the kind check terminates with 181 before constructing `fn`. A valid older typedef does not override newest-first lookup.

**Next step.** Keep type, descriptor, and payload in separate columns. Then change the first parameter to a scalar and verify that no descriptor survives into the second row by accident.

Source check: [`114`, type branches and append stack](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/114-cc-func.fth#L47-L109).

## C18-04 — Reconstruct a complete call frame

**Hint 1.** First finish argument staging; only then introduce CALL's return destination and the saved frame base.

**Hint 2.** Callee base Q is `S−16`. Its bottom is `Q−256`, and slot i is `Q−8*(i+1)`.

**Hint 3.** The first two pushes give RSP `0x1FF8` and `0x1FF0`, holding two and three respectively.

**Checked solution.** The complete pointer path is:

| Completed operation | RSP | RBP | Changed value/storage |
|---|---|---|---|
| Push first argument | `0x1FF8` | `0x2100` | `[0x1FF8]=2` |
| Push second argument | `0x1FF0` | `0x2100` | `[0x1FF0]=3` |
| POP RSI | `0x1FF8` | `0x2100` | RSI=3 |
| POP RDI | `0x2000` | `0x2100` | RDI=2 |
| CALL | `0x1FF8` | `0x2100` | `[0x1FF8]=K` |
| PUSH RBP | `0x1FF0` | `0x2100` | `[0x1FF0]=0x2100` |
| MOV RBP,RSP | `0x1FF0` | `0x1FF0` | Q established |
| SUB RSP,256 | `0x1EF0` | `0x1FF0` | Frame reserved |

The spills establish `pad` at `0x1FE8` and `n` at `0x1FE0`. Slot 31 is `0x1EF0`. Neither store changes either pointer. Prefix bytes total `11+2*4=19`.

After a normally completed body with its temporary/save obligations discharged, XOR sets RAX=0 while pointers remain unchanged. MOV RSP,RBP sets RSP=`0x1FF0`; POP RBP sets RBP=`0x2100`, RSP=`0x1FF8`; RET resumes K with RSP=`0x2000`. The implicit tail is eight bytes under default hooks. The caller's result move places zero in RDI without changing these pointers.

The callee's slot holding `n` contains a copied argument value. It is a different address from the separately owned caller scalar in the premise. Changing the copied integer does not write to the caller's storage. Passing an actual pointer and storing through it would be a materially different case.

**Wrong path to diagnose.** Putting K at Q confuses saved RBP with return control. Placing `pad` at `S−8` ignores CALL/PUSH RBP. Claiming all slots begin at zero adds initialization absent from SUB RSP.

**Changed case.** With S=`0x3000`, Q=`0x2FF0`; K is at `0x2FF8`, saved caller RBP at `0x2FF0`. The sixth incoming register R9 spills to slot 5, address `0x2FC0`. Slot 31 is `0x2EF0`. Six spills plus prologue occupy 35 bytes. The values in uninitialized slots remain unspecified by this prefix; the exercise does not provide the saved caller RBP's numerical value.

**Next step.** If the layout failed, draw only the three addresses S, S−8, and S−16 before adding any local slot.

Source check: [`114`, prefix and tail selection](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/114-cc-func.fth#L286-L310) and [`090`, prologue/epilogue](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L331-L359).

## C18-05 — Distinguish three limits

**Hint 1.** Separate the 32-slot allocator from the six-store routine and the six-argument caller check.

**Hint 2.** A 26-int array claims 26 slots. It does not claim one slot holding an array pointer.

**Hint 3.** Six parameters plus 26 slots reaches 32 exactly. Six plus 27 proposes 33.

**Checked solution.** A well-formed seven-parameter header can finish with parameter count seven and local count seven. Its fixed prefix reserves 256 bytes, but only slots 0–5 receive incoming register stores. Slot 6 at `RBP−56` gets no incoming value from the prefix. A matching seven-expression legacy call reaches error 122; no seven-argument support follows from header acceptance.

With six parameters plus a 26-int ordinary array, parameter count stays six and local count becomes 32. The array claims slots 6–31, records base slot 31, and starts at `RBP−256`; its remaining elements increase in address. The prefix still reserves 256 bytes. Only the parameter slots are initialized by the spills; an uninitialized array declaration adds no zeroing stores.

With six parameters plus a 27-int array, its computed base slot is 32, but attempting to add 27 to the existing six reaches error 162. The helper does not increment local count, which remains six; parameter count remains six. The symbol and array length were already recorded by the declaration path before that failure. There is no recovered, fully valid function to execute, and no whole-declaration rollback. Its 256-byte prologue and six spills were already emitted before the body declaration failed.

**Wrong path to diagnose.** Error 122 on the seven-parameter header assigns a caller check to a different parser. Reporting local count 33 after the failed capacity check ignores the check-before-increment order. Reporting count 32 for that failure silently performs a partial allocation that the helper does not do.

**Changed case.** Starting after 31 successful named parameters, the thirty-second is allocated at slot 31 and raises both counts to 32. The thirty-third appends a row carrying proposed slot 32, then fails the slot check with 162; both counters remain 32. Since the parameter list has not completed, this invocation of `cc-parse-function` has not yet emitted its prologue or spills. If instead a 32-parameter header ended successfully, its later prefix would still spill only six registers, and a matching legacy call would still be rejected.

**Next step.** Mark the exact failure point in the builder timeline. Then list only the mutations before it; do not infer a rollback or a partial success.

Source check: [`114`, parameter append/claim/count order and spills](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/114-cc-func.fth#L95-L170), [`110`, slot check](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L36-L46), and [array construction](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L462-L503).

## C18-06 — Reconstruct the exits

**Hint 1.** Computing the result, restoring switch saves, and discarding a frame solve three different obligations.

**Hint 2.** The explicit-return parser's source-token consumption order differs for valued and bare returns.

**Hint 3.** For valued return, RDI becomes seven before the default hook emits MOV RAX,RDI.

**Checked solution.** With `return` already consumed, the builder reads the first expression token, puts it back, compiles the expression, and obtains its materialized value. The generated sequence then moves RDI to RAX, emits two POP RBX operations for the two open switches, and emits MOV RSP,RBP; POP RBP; RET through the default epilogue. The builder finally consumes the required semicolon.

At execution, RAX remains seven through those restores and the return. Expression-owned pushes must have been removed before switch unwind begins; otherwise the first POP RBX would consume a temporary instead of the saved register cell. The two saved-RBX values restore the nested and then enclosing switch state in stack order.

For `return;`, the parser's initial read already consumes `;`. It emits XOR RAX,RAX, the full switch unwind, and the epilogue, with no second semicolon expectation. For normal fall-through, all structured statements have completed their own closing work; `114` emits zero plus epilogue without a separate switch-unwind loop at that point.

The builder continues parsing after explicit-return emission and later appends the implicit tail. Executing the explicit RET leaves the function immediately; it does not continue into those later bytes. A different control-flow path may still reach the tail.

**Wrong path to diagnose.** Saying MOV RSP,RBP makes the RBX pops unnecessary accounts for stack space but drops register restoration. Expecting a second semicolon on bare return consumes the next token. Saying “the implicit zero overwrites seven” ignores the executed RET.

**Changed case.** With one switch and `n=9`, load/materialize n, move RDI=9 to RAX, pop RBX once, then execute the epilogue. If that pop were omitted, MOV RSP,RBP would still recover the frame boundary for return control, but the saved RBX value would not be restored by the default epilogue. Balanced final pointers would not meet the same register-preservation obligation.

**Next step.** Trace RAX, RBX, and RSP separately. If only semicolon handling was wrong, leave out machine state and repeat the two token paths.

Source check: [`110`, switch unwind and return](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L740-L803).

## C18-07 — Test the actual call boundary

**Hint 1.** Count all still-live target saves, including those owned by an enclosing expression.

**Hint 2.** Each eight-byte push flips remainder 0↔8 modulo 16. Popping the inner call's argument does not pop an outer argument.

**Hint 3.** Immediately before CALL `leaf` in the first expression, the outer 10 is still at the stack top.

**Checked solution.** Starting at S with remainder zero, `combine(10,leaf(20))` gives:

```text
push outer 10:         8
push inner 20:         0
pop inner RDI:         8   <- immediately before CALL leaf
CALL pushes return:    0
leaf pushes RBP:       8
leaf subtracts 256:    8   <- leaf body baseline
leaf returns:          8   <- outer 10 remains
push leaf result:      0
pop RSI, then RDI:   8, 0  <- immediately before CALL combine
```

The inner call's entry alignment is wrong relative to the ordinary System V comparison, while the final outer call has the expected pre-CALL remainder. The derivation does not predict a mandatory fault.

For `combine(leaf(20),10)`, there is no outer staged argument yet when leaf is evaluated. Its own push gives remainder eight and its own pop restores zero before CALL. CALL entry is eight, PUSH RBP gives zero, and SUB 256 preserves zero. On return, the outer call stages leaf's result and then 10; its two pops again restore S.

Own-argument balance proves that the sequence removes the stack space it added. It does not prove the entry value of RSP was aligned. The missing premise is that each actual caller reaches CALL with remainder zero after accounting for all older expression/argument/switch saves. A fixed 256-byte allocation preserves a remainder; it cannot repair an incorrectly aligned incoming call.

**Wrong path to diagnose.** Counting only leaf's own argument hides the outer value. Treating every nested call as misaligned misses the second case. Treating a successful arithmetic return as proof of ABI alignment confuses outcome with a boundary condition.

**Changed cases.** In `combine(10,20,leaf(30))`, two outer arguments are already staged: RSP is S−16, remainder zero. Leaf's own push/pop returns there, so its pre-CALL remainder is zero. In the original two-argument expression with one older switch save below aligned baseline S, that save plus the outer 10 totals two live eight-byte saves. Leaf's pre-CALL remainder is then zero. After both outer arguments are popped, the switch save still remains, so the later CALL to combine has remainder eight. Fixing one boundary's parity by adding another live save does not fix every call in the expression.

**Next step.** Use a ledger of owners before using addresses: switch, outer argument, inner argument, return control, saved RBP. Remove a cell only when its owner finishes with it.

Source check: [`100`, staging and legacy call emission](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L586-L672); the chapter states the external alignment comparison and its limits.

## C18-08 — Restore names without reusing slots

**Hint 1.** Maintain separate columns for symbol count and local-slot count. Only one is restored by a lexical-scope pop.

**Hint 2.** The function symbol itself is appended before the function marker. A sibling declaration may reuse a symbol ID without reusing its predecessor's slot.

**Hint 3.** The function gets ID 3; its scope marker is 4.

**Checked solution.** Markers are shown oldest-to-newest, with top at right:

| Completed builder action | Symbol count | Markers | Local count | New symbol/payload |
|---|---:|---|---:|---|
| Append function | 4 | `[]` | Reset follows | Function ID 3 |
| Reset and push scope | 4 | `[4]` | 0 | None |
| Parameter 1 | 5 | `[4]` | 1 | ID 4 / slot 0 |
| Parameter 2 | 6 | `[4]` | 2 | ID 5 / slot 1 |
| Declare `outer` | 7 | `[4]` | 3 | ID 6 / slot 2 |
| Enter inner block | 7 | `[4,7]` | 3 | None |
| Declare `inner` | 8 | `[4,7]` | 4 | ID 7 / slot 3 |
| Leave inner block | 7 | `[4]` | 4 | ID 7 no longer live |
| Declare `after` | 8 | `[4]` | 5 | ID 7 / slot 4 |
| Leave function | 4 | `[]` | 5 | Function ID 3 survives |

This table assumes no surrounding compiler scope markers; with existing markers, append these markers above them and restore that original depth at the end.

The function parser resets local count, label count, break head, continue head, switch depth, and loop-switch depth; the parameter-list helper separately resets parameter count. Labels use their own function-wide records; symbols use a visible prefix and lexical markers; target frames hold runtime values and return control. These are different data structures and lifetimes. A builder scope pop neither returns the target function nor resets its slot allocator.

**Wrong path to diagnose.** Assigning `after` slot 3 confuses metadata-ID reuse with frame-slot reuse. Final symbol count 3 forgets the retained definition. Final local count zero imports the next function's reset into the current function's exit.

**Changed cases.** An empty inner block saves and restores count 7 without adding a slot; `after` receives ID 7, slot 3, and final local count is four. If the inner declaration is instead a local static scalar, it adds a block-scoped `sk-global` row at ID 7 and allocates separate global storage, but does not raise local count. The nested pop hides that row without reclaiming its storage. `after` again uses ID 7/slot 3, and local count finishes four.

**Next step.** Trace one ID and one slot through the pop and append. They may have equal numbers briefly without identifying the same kind of object.

Source check: [`114`, resets and scope lifecycle](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/114-cc-func.fth#L273-L310), [`070`, scope pop](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/070-cc-sym.fth#L160-L167), and C15's local-static contract.

## C18-09 — Choose a provider from evidence

**Hint 1.** A negative parameter slot and a frame-size placeholder do not describe the legacy six-spill path.

**Hint 2.** Apply the same displacement formula before deciding whether the address is above or below RBP.

**Hint 3.** For slot −3, `−8*(−3+1)=16`.

**Checked solution.** The evidence matches the private all-stack native provider in `117-cc-native-program.fth`. Its first parameter uses slot −3 and therefore address `RBP+16`. Five claimed local slots occupy 40 bytes; rounding upward to a multiple of 16 gives 48 bytes, encoded in the saved frame field as `30 00 00 00`.

`114` would emit the fixed immediate 256 (`00 01 00 00`) even if only five slots were eventually claimed. Its first parameter is slot 0 at `RBP−8`, initialized from RDI, not a negative slot naming incoming stack storage.

Before calling any trace a general System V implementation, evidence would be needed for actual argument/result classification and placement under the relevant signatures, and for stack alignment plus preserved-register obligations at every boundary. Other acceptable answers include supported variadic/aggregate shapes and the active provider/profile selection. The named `117` convention is private; its reuse of RBP-relative addressing does not change that fact. A correct answer does not require teaching the full later ABI algorithm here.

**Wrong path to diagnose.** Selecting System V merely because the target is x86-64 confuses instruction set with calling convention. Rounding 40 down to 32 reserves too little. Applying the legacy positive-slot intuition to −3 produces the wrong side of RBP.

**Changed cases.** Six total claimed slots require 48 bytes, already a multiple of 16. Under active `121`, the count begins at one for saved-callee storage. If “six” is the **total count**, the patch remains 48. If six newly claimed slots are added after that initial reserved slot, the total count is seven, requiring 56 bytes rounded to 64. State which count the evidence provides before calculating the patch.

**Next step.** Identify three independent facts in a new trace: active driver, parameter location, and local-frame size policy. One shared helper name cannot determine all three.

Source check: [`117`, native parameters and delayed frame patch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/117-cc-native-program.fth#L1-L77) and [`121`, saved-slot/count policy](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1315-L1334).

## After checking a solution

Following a solution with help and predicting a later changed case with the answers closed are different checks. Use the changed case when you want to test the second.
