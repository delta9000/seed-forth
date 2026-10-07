# C15 practice help: declarations and recursive records

[Back to the chapter](../chapters/15-declarations-and-recursive-records.md)

These solutions are checked manual derivations against the pinned source and the chapter's stated legacy profile. No compiler, Forth, C example, or generated program was executed. Object addresses are symbolic offsets within valid assumed storage. The exercises assess source reading and prediction; completing them is not evidence of compiler conformance or an executed program.

Use the first hint to find the relevant distinction, the second to expose the state you need, and the third if one partial step would help. The full solution remains available without a required wait or repeated attempt. After checking, use the changed case with the answer covered; seeing a solution and reproducing it immediately is different from an independent prediction.

## C15-01 — Prefix facts and token ownership

**Hint 1.** Separate the prefix skipper from basic-type parsing and from star counting. They do not all own the same state.

**Hint 2.** The prefix skipper resets old state before reading anything. Qualification is a bit set; storage class is counted separately. Stars belong to individual declarators.

**Hint 3.** The prefix skipper puts `unsigned` back. `const` following the first star is handled later by `cc-skip-qualifiers`.

**Checked solution.** After the leading prefix, `cc-prefix-qualified=3`, `cc-decl-static=true`, `cc-decl-extern=false`, and `cc-decl-storage=1`. The prior arbitrary values do not survive the initial reset. `unsigned` is pending.

The basic-type sequence begins with `unsigned`, initially selecting legacy int; the later `char` changes the base to char. The first declarator has one star, so `first` has type char-pointer, depth one. The qualifier following that star is consumed; this legacy account does not infer persistent native qualifier enforcement from it. The second declarator begins again with initial depth zero and no star, so `second` is scalar char. Both pass through the static scalar-storage branch because the static flag applies to the declaration.

After the first local-declarator call, the comma is current and consumed. The outer word recognizes it and starts another declarator. After the second call, the semicolon is current and consumed. The outer word tests it without fetching another token. An expectation helper would advance too far here.

For the separate expectation question, `)` is punctuation, so it passes the kind test but fails the requested-character test: error 143. A consumed identifier would instead give error 142.

**Wrong path to diagnose.** Depth one for both names carries a declarator's star into its sibling. Qualification value two loses the `const` bit rather than ORing it with `volatile`. Calling the static flag “scope” confuses a storage choice with the symbol table's visible prefix.

**Changed case.** Replace the prefix with `extern restrict inline unsigned`. The collected values become qualification 4, static false, extern true, storage count one. `inline` is consumed without incrementing storage count. If the rest is unchanged, the basic sequence still reaches `char`. This question is about recorded facts, not a claim that every resulting keyword combination receives complete C validity checking.

**Next step.** If only the delimiter was wrong, trace current/pending status without calculating types. If types were wrong, keep the shared initial depth in one column and each declarator's added stars in another, then retry with an already-defined pointer typedef.

Source check: [prefix and star scanners](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L95-L183), [basic spellings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L531-L571), and [expectation helpers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L62-L89).

## C15-02 — Move the starting slot

**Hint 1.** A local payload is a slot index, not a byte displacement. For an array it selects the lowest-address end of the reserved range.

**Hint 2.** Use `base-slot=C+N−1` and `address(slot)=RBP−8*(slot+1)`. Update C after each reservation.

**Hint 3.** `w` claims slots 3 through 6. Its first element is in slot 6.

**Checked solution.** The relevant rows and counter transitions are:

| Name | Kind | Type | Payload | Array length | Count after declaration |
|---|---|---|---:|---:|---:|
| `w` | `sk-local` | Legacy int, depth 0 | 6 | 4 | 7 |
| `r` | `sk-local` | Legacy int, depth 0 | 7 | 0 | 8 |

The int type word is `2*65536=131072`. `w` records its element type; the separate length distinguishes its array shape. `r`'s length metadata remains zero from symbol initialization.

The addresses for `w[0]` through `w[3]` are `RBP−56`, `RBP−48`, `RBP−40`, and `RBP−32`. `r` is at `RBP−64`. Counting from zero again would overlap the three already-claimed parameter slots, contrary to the premise.

Leaving the block removes its appended symbol rows from lookup. It does not reduce the slot counter, so the sibling `other` claims slot 8 at `RBP−72`, making count 9. A symbol ID might be reused after scope restoration, but an ID indexes compiler metadata; it is not the frame payload stored in that row. Scope restoration alone says nothing about choosing the next slot. The monotonic allocator supplies that policy.

**Wrong path to diagnose.** Base slot 3 confuses the first allocated slot with the array's lowest address. Reporting `other` in slot 3 imports a reuse scheme absent from `cc-fn-add-slots` and `cc-scope-pop`.

**Changed case.** Begin at count 28 instead. `w`'s payload is 31, base `RBP−256`, and the new count is 32. The later scalar's attempt to claim one more slot reaches error 162. Do not claim a clean rollback of the whole declaration: `cc-parse-local-declarator` appends the symbol before it calls the capacity-checked slot helper. The helper's own counter increment does not happen on that failure.

**Next step.** If offsets were wrong, draw only the newly reserved slot interval and label its high and low addresses. If reuse was wrong, keep separate columns for symbol count and local-slot count across the scope pop.

Source check: [array payload and reservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L462-L503), [capacity helper](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L36-L46), and [scope pop](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/070-cc-sym.fth#L160-L167).

## C15-03 — Separate visibility from storage duration

**Hint 1.** Write “builder calculates now” or “emits calculation for later” next to each initializer path.

**Hint 2.** A static scalar selects global data allocation, but its symbol is still added at the current lexical scope.

**Hint 3.** The ordinary local claims slot 5. The static scalar does not call `cc-fn-add-slots`.

**Checked solution.** For ordinary `int count=3;`, the symbol is `sk-local`, int, payload slot 5, at `RBP−48`. The new count is six. `cc-parse-expr` emits the runtime calculation of three, and `cc-emit-store-local` emits the store to slot five. The compiler is writing instructions, not currently storing three into a C stack frame.

For `static int count=3;`, allocation reserves eight data bytes and returns an offset S. The symbol is `sk-global`, int, payload S. `cc-parse-const` calculates builder-cell three; `cc-globals-store-8le` writes `03 00 00 00 00 00 00 00` into the globals buffer at S. Local count stays five. Final placement/fixups later make the storage available to generated code; this initializer is not re-emitted as a store for each runtime block entry.

In either independent function, the scope pop hides the symbol by restoring the earlier symbol count. It does not erase the retained symbol bytes, reset local-slot allocation, or reclaim the static's global bytes. Generated local-frame lifetime and generated global-storage lifetime are separate from compiler lookup visibility.

Changing the static scalar to `static int count[3];` selects `cc-bss-alloc` with 24 bytes. The row is `sk-global` with int element type, returned tagged BSS slot, and array length three. Local count remains five. This branch has no initializer expression and relies on zero-filled BSS storage. It does not allocate a pointer to a separately allocated array.

**Wrong path to diagnose.** “Static local means a local slot that isn't cleared” chooses the wrong storage interface. “Scope pop destroys the static” mistakes loss of lookup visibility for destruction of generated storage. “Both initializers call the constant evaluator because they contain literals” overlooks the branch chosen by declaration kind.

**Changed case.** Remove `=3` from both scalar declarations. The ordinary local still claims one slot and emits no initialization store, so no value is promised. The static scalar still reserves eight data bytes; with the chapter's initialized-global-buffer premise, they remain zero. The declarator does not emit a zero store for either case.

**Next step.** Retry with an initializer containing arithmetic and identify its phase before calculating the arithmetic. If the phases are clear, compare block exit, function return, and compiler completion without assigning all three the same lifetime effect.

Source check: [static and ordinary branches](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L475-L503) and [global storage contracts](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L1168-L1210).

## C15-04 — Explain the two descriptor chains

**Hint 1.** Record the descriptor that exists at the exact moment each field is appended. Do not fill earlier zeros using later knowledge.

**Hint 2.** The currently defined tag is registered before any fields. An unknown different tag is not allocated by soft lookup.

**Hint 3.** In the A-then-B order, `A.b` stores zero; `B.a` stores A's descriptor.

**Checked solution.** Use N, A, and B as symbolic compiler descriptor addresses. Nonpointer int has word 131072; struct-pointer depth one has word `3*65536+1=196609`.

| Descriptor / field | Type | Offset | Associated descriptor |
|---|---|---:|---|
| N / `value` | Int, depth 0 | 0 | 0 |
| N / `next` | Struct, depth 1 | 8 | N |
| A / `x` | Int, depth 0 | 0 | 0 |
| A / `b` | Struct, depth 1 | 8 | 0 |
| B / `y` | Int, depth 0 | 0 | 0 |
| B / `a` | Struct, depth 1 | 8 | A |

Each completed descriptor has field count two and object size sixteen. For N, registration precedes `next`'s soft lookup. For A's field `b`, B does not exist yet and soft lookup returns zero. When B's field `a` is built, A already exists. Building B does not patch A's existing field record.

For `p->next->value`, the pointer local supplies N. The first lookup adds offset eight and publishes `next`'s type and N. The next arrow materializes the pending member address to obtain the pointer stored there, then uses N to select `value` at offset zero. The expression may still represent a pending place after field selection; a later value consumer decides when to load `value`.

For `pa->b->y`, the first selection obtains the address of `b` and propagates its descriptor zero. The second field operation checks for a descriptor and reaches error 100. In this source order, that check occurs before it could carry out the next arrow's materialization and named-field lookup. A valid runtime B object behind the pointer cannot replace missing compiler metadata.

For `pb->a->x`, the first selection propagates descriptor A. The next arrow materializes the pointer stored in `a`, and the A descriptor locates `x` at offset zero. The result follows from the provided valid pointer/object premises; the declarations alone do not initialize the linked objects.

If the two definitions are reversed, B's `a` now gets zero and A's `b` gets descriptor B. Consequently `pa->b->y` has the necessary chain, while `pb->a->x` reaches missing descriptor zero. Reordering changes which cross-reference was unknown at construction, not the eight-byte field offsets.

Table relocation is different: the stable header still exists and points to the current table. A fresh field-record lookup reaches relocated contents. A legacy zero is no header identity at all. Keeping headers stable solves movement of known identities; it cannot discover an identity the field never stored.

**Wrong path to diagnose.** Updating `A.b` automatically after B is parsed invents a fixup mechanism absent from soft lookup. Treating `next` as another inline Node would confuse a pointer member with a recursively embedded object. Claiming parser recursion explains self-reference misses the pre-registration step.

**Changed case.** Give Node a third field `struct Node *previous;`. That field receives offset sixteen and descriptor N; final size is twenty-four. Both links share N, and no second Node descriptor is needed. To change the forward-reference behavior instead, you must select a different producer contract, such as the named native aggregate provider; changing header stability alone is insufficient.

**Next step.** If you lost the descriptor during materialization, replay only the two cells “generated RDI meaning” and “compiler associated descriptor.” If you filled in a future descriptor early, annotate every lookup with which tags currently exist, then retry the reversed order.

Source check: [soft lookup and pre-registration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L251-L354) and [field-consumer order](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1130-L1180).

## C15-05 — Allocate an object or allocate its pointer

**Hint 1.** Only the zero-pointer-depth branch reserves descriptor size divided by eight. Every positive depth takes one pointer slot here.

**Hint 2.** A three-member value object requires three slots; its base payload is the deepest one.

**Hint 3.** With C=4 and N=3, `item`'s payload is 6. The following declaration begins with count 7.

**Checked solution.** Let L denote the completed Link descriptor, with total size 24.

| Name | Type | Payload slot | Object base/address | Associated descriptor | Count afterward |
|---|---|---:|---|---|---:|
| `item` | Struct value, depth 0 | 6 | `RBP−56` | L | 7 |
| `owner` | Struct pointer, depth 2 | 7 | `RBP−64` | L | 8 |
| `tail` | Int, depth 0 | 8 | `RBP−72` | 0 | 9 |

`item` occupies bytes `RBP−56` through `RBP−33` inclusive. Its members begin at `RBP−56`, `RBP−48`, and `RBP−40`. These correspond to slots 6, 5, and 4. Starting field zero at the shallowest new slot, slot 4, would make positive member offsets extend toward older slots instead of traversing the reserved range.

`owner` occupies one eight-byte slot even though its pointer depth is two. No pointed-to pointer or Link object is allocated as part of this declaration. Recording L does not assert that applying one arrow directly to a depth-two pointer is a valid expression; this exercise concerns the producer's storage facts.

With `struct Link *item;` instead, the new sequence is:

| Name | Payload slot | Address | Count afterward |
|---|---:|---|---:|
| `item` | 4 | `RBP−40` | 5 |
| `owner` | 5 | `RBP−48` | 6 |
| `tail` | 6 | `RBP−56` | 7 |

Both pointer rows still associate L; tail's descriptor remains zero. The changed `item` can use the specialized pointer branch's optional `= expression` initializer, such as the chapter's bounded `=0` case, which emits a store to its one pointer slot. The original value branch requires a semicolon directly after the name and has no initializer support.

**Wrong path to diagnose.** Reserving six slots for a pointer-to-pointer multiplies storage by depth rather than storing one pointer value. Using descriptor size 24 as a slot count introduces a byte/slot unit error. Leaving later slots unchanged after shrinking `item` misses the monotonic count update.

**Changed case.** At initial count 30, the three-slot value branch would exceed the legacy capacity when it calls `cc-fn-add-slots`; the one-slot pointer branch would reach 31. This distinction follows from storage shape, not from how many objects might later be reachable through the pointer.

**Next step.** If depth caused confusion, draw only the bytes allocated by each declaration, excluding all objects merely pointed to. If the base was wrong, number members from zero and require their addresses to increase within one contiguous reservation.

Source check: [struct-local production](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L690-L738).

## C15-06 — A lookahead is not a signature checker

**Hint 1.** First trace the speculative reader; then restore it and trace the consuming parser. Do not merge them into four permanently consumed tokens.

**Hint 2.** Comments disappear at the lexer interface. The parameter skip counts punctuation tokens, not function types.

**Hint 3.** After the parser has consumed the outer parameter-list opening `(`, depth is one. The `(` before `*nested` raises it to two.

**Checked solution.** The mark saves the original pending `(` and other lexer state. Lookahead reads that `(`, then `*`, with the comment skipped by tokenization. Both tests match, so it returns true after resetting the mark. The original `(` is pending again. The real function-pointer parser then consumes `(`, `*`, `fp`, `)`, and the outer parameter-list `(`.

The skip sequence is:

| Consumed token | Depth afterward |
|---|---:|
| Starting state after outer `(` | 1 |
| `int` | 1 |
| `(` | 2 |
| `*` | 2 |
| `nested` | 2 |
| `)` | 1 |
| `(` | 2 |
| `int` | 2 |
| `)` | 1 |
| Final outer `)` | 0 |

At zero, skipping stops with pending flag clear. None of these tokens constructs a parameter signature. Given next free slot C, `fp` is registered as `sk-local`, type `ty-func` at depth one (`4*65536+1=262145`), payload C, and claims one slot, making count C+1. The declaration has no initializer, so it emits no initialization store. The consumed base spelling `int` does not become a checked return-signature descriptor through this word.

For `int *p;`, the first lookahead token is `*`, not `(`. It resets immediately and returns false; no second lookahead read is necessary. The ordinary declarator then counts the star and consumes `p`. A successful lookahead cannot be replaced with checking two adjacent bytes because token boundaries admit the illustrated whitespace/comment gap.

The separate helper-gate question gives LP64 true and `cc-native-float-types-fwd` false. Encountering `double` during the skip reaches error 214. This conditional spelling rejection does not validate the remaining signature. Under ordinary LP64 statement dispatch, the native declaration provider normally receives native type starts before this legacy special shape; the exercise explicitly asks about the skip helper's local contract.

**Wrong path to diagnose.** Starting the real parser at `fp` forgets that lookahead reset. Treating the nested parentheses as a stored nested function descriptor invents work absent from the depth loop. Calling the floating gate executable floating-point support confuses accepted spelling with runtime operations.

**Changed case.** Remove the final outer `)` and end the input. The depth remains one until EOF, where the skip helper dies with 184. It does not silently accept the unmatched list, and no promised recovery state follows the failure.

**Next step.** If reset was missed, write the reader state before and after the entire peek as the same symbol L, with only its Boolean result new. If nesting was missed, trace parentheses alone first, then reinsert non-parenthesis tokens without changing their counts.

Source check: [function-pointer detector and skip loop](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L368-L446).

## C15-07 — Finish the local contract

**Hint 1.** The first token after `return` decides whether the semicolon was already consumed. That changes the final token action.

**Hint 2.** Result placement precedes the two RBX restores, and both precede the epilogue. These are generated operations, not immediate changes to the compiler's machine state.

**Hint 3.** For `return r;`, the peeked identifier is put back before `cc-parse-expr` starts.

**Checked solution.** For `return;`, the parser reads the semicolon and recognizes the bare form. It emits an operation zeroing RAX, two `POP RBX` instructions through `cc-emit-switch-unwind`, then the epilogue. It does not expect a second semicolon. The legacy epilogue's default callee-restore hook adds nothing, followed by `RSP=RBP`, saved-RBP pop, and `RET`.

For `return r;`, the parser reads `r`, puts it back, and calls `cc-parse-expr`. With the given initialized local and legacy expression contract, generated code loads value nine into RDI and provides a materialized result; local materialization needs no additional load beyond the local-reference path. The default return-value hook moves RDI into RAX. Next come two `POP RBX` instructions, then the epilogue. The parser finally expects the source semicolon left pending by expression parsing.

Emitting an epilogue before expecting the semicolon does not execute a return from the compiler. It appends generated bytes and continues parsing. Nor does the bare form's emitted zero assert that the parser has fully checked the enclosing function's return-type rules.

Under LP64, the valued path additionally invokes `cc-return-shape-fwd` with source type/descriptor followed by destination return type/descriptor, then emits conversion from the expression type to the enclosing return type. The shape hook's default discards all four inputs. Target providers may add checks or alter result transport; the source still calls the result hook before unwind and epilogue. The bare branch does not go through that valued shape/conversion sequence.

C17 must establish how switches save RBX and how each control-flow exit chooses its unwind count. C18 must establish the complete parameter/local frame and prologue/epilogue integration. This answer needs only the supplied depth-two obligation, not an invented full stack snapshot.

For the final dispatch question, `cc-parse-stmt` first scans prefixes and reads `int`. With LP64 enabled and the native predicate true, it calls `cc-native-decl-fwd` and exits before reaching the legacy `cc-parse-decl` branch. Having learned the legacy keyword algorithm does not make it the selected native algorithm.

**Wrong path to diagnose.** Omitting the RBX restores because RSP is reset loses the saved-register obligation. Fetching another semicolon after the bare form consumes unrelated following input. Routing LP64 `int` straight into legacy collapse ignores the earlier provider test.

**Changed case.** Set switch depth to zero. Both returns emit no `POP RBX` instructions, but their result, epilogue, and delimiter differences remain. Changing depth removes only the unwind obligation; it does not remove the function's return or frame teardown.

**Next step.** If token handling was wrong, compare bare and valued branches using only “read/put back/expect.” If code order was wrong, label every action as compiler parsing, generated result placement, generated register restoration, or generated frame teardown, then merge the sequences.

Source check: [return and unwind](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L759-L803), [epilogue](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L349-L359), and [native-first statement dispatch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/112-cc-stmt.fth#L865-L890).

## A later independent check

After working on another topic, choose one declaration you have not traced and state the initial profile, symbol scope, local count, and available descriptors before predicting its products. Use the source as a reference if you want; keep the worked answer closed. A useful self-check is whether you can explain every number's unit and owner: compiler address, descriptor offset, symbol ID, slot index, generated byte address, or runtime value.

If the result is wrong, repair the first differing transition rather than rewriting the entire trace. If the result is right but the explanation relies on “C normally does this,” repeat it using the particular branch and provider selected here. These tasks propose checks of independent application; no human learner result has been measured in this documentation pass.
