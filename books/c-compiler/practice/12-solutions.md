# C12 practice help: places, values, and delayed loads

[Back to the chapter](../chapters/12-places-values-and-delayed-loads.md)

These solutions are checked manual derivations from revision `bbcc1732152af2d884737272eed870d2410ffe8e`, not compiler output. No builds, Forth/C examples, generated programs, or source-fix experiments were run. Memory values are stipulated premises; every proposed emitted effect is conditional on the chapter's valid-storage assumptions.

The default is legacy unless a problem changes it. K/S/T/D mean kind, local slot, encoded type, and associated descriptor. Q/F/N/A/I mean qualification, field-record pointer, null provenance, array count, and inner row width. “Sentinel” means the Forth `true` value, −1. Stack top is on the right.

## Entry check and a route back

A slot number is compiler metadata naming a frame coordinate, not the stored value. Adding eight to an address computes a different address without reading memory. Writing a descriptor into a builder cell does not emit that descriptor into future RDI.

If the first answer was uncertain, use C08's payload examples and C09's slot formula. If the second was uncertain, annotate the opening `t.stars` trace with separate “address arithmetic” and “load” rows. If the third was uncertain, draw two boxes labeled builder and generated program and place D and G in different boxes. Then retry one expression without the solution open. A setup or notation problem is a reason to repair the setup or notation, not to infer inability.

## Graduated hints

### C12-01 hints

1. Ask what the producer has emitted before asking what materialize adds
2. `cc-deref-pending?` accepts only `lv-deref` and `lv-deref-byte`
3. Bare `r` starts with RDI=2 and K=`lv-local`; the slot survives the materializer

### C12-02 hints

1. Read all writes inside `cc-mark`, not only its older comment
2. `cc-mark-deref` calls `cc-mark`; it does not preserve a prewritten descriptor
3. After false is consumed, K is `lv-deref` and S is sentinel. Fill the other seven cells from the reset body

### C12-03 hints

1. Field count bounds the search; capacity only describes reserved records
2. Compare lengths before bytes; an equal-length name can still fail
3. For `stars`, record 0 fails on length and record 1 supplies offset 8. Add that offset to G, not to D

### C12-04 hints

1. The index uses the same current expression metadata as the base
2. Put element type/stride on a builder-state line and the saved address on a generated-stack line
3. Inline `w` uses LEA; pointer `p` must read its slot to obtain P. The latter's element is plain char

### C12-05 hints

1. Compare grouping's called word with public `cc-parse-expr`
2. A pending field address is different from a default local's already-loaded value
3. A future store needs `G+8` to survive value production. It need not load the old 4 first

### C12-06 hints

1. Begin every case with primary's reset; literal arms do not all reset again
2. A numeric zero sets N, whereas the enum arm calls `cc-mark-int-value`
3. An unresolved function name uses the imm64 address-fixup list. A native string's count measures decoded bytes including one final NUL

### C12-07 hints

1. Separate the LP64 width flag from the System V provider's gate
2. The System V hook writes K/S as well as emitting LEA
3. For the matrix, one index skips an entire row: four bytes per int times three ints per row

### C12-08 hints

1. Separate current expression cells, live symbol IDs, stable descriptor headers, movable field records, and borrowed source bytes
2. Recursion can overwrite a cell without destroying the arena object it used to name
3. A table move preserves D but can invalidate F as the current field pointer. It does not automatically refresh arbitrary caller caches

## Checked solutions

### C12-01 — Label the three results

All cases start independently from the chapter's fixture.

| Expression and stage | Future RDI | K | S | T | D |
|---|---|---|---|---|---|
| `r`, after producer | 2 | `lv-local` | 4 | `int` | 0 |
| `r`, after first materialize | 2 | `lv-local` | 4 | `int` | 0 |
| `r`, after second materialize | 2 | `lv-local` | 4 | `int` | 0 |
| `t.stars`, before materialize | `G+8` | `lv-deref` | Sentinel | `int` | 0 |
| `t.stars`, after first | 4 | `lv-value` | Sentinel | `int` | 0 |
| `t.stars`, after second | 4 | `lv-value` | Sentinel | `int` | 0 |
| `w[2]`, before materialize | `B+16` | `lv-deref` | Sentinel | `int` | 0 |
| `w[2]`, after first | 5 | `lv-value` | Sentinel | `int` | 0 |
| `w[2]`, after second | 5 | `lv-value` | Sentinel | `int` | 0 |

`int` is the encoded type 131072. The local producer has already emitted one qword read at `RBP−40`. The field's first materialization emits one qword read at `G+8`. The array's first materialization emits one qword read at `B+16`. Producing G, adding eight, obtaining B with LEA, producing literal 2, and scaling/adding do not read the selected object contents.

The generated PUSH/POP for the array do access expression staging storage. Those are target memory operations too, but they are not reads of `w[2]`. A fully precise account distinguishes the base's temporary save/reload from the eventual element load. No second materialization appends another scalar load because neither result remains pending.

**Common wrong turn.** “All three become `lv-value`” treats materialize as a full reset. The inspected body changes K/S only inside its pending-dereference branch; `lv-local` does not enter that branch.

**Changed case.** With `r=0`, the producer still publishes K=`lv-local`, S=4, T=`int`, D=0, and N=0. Its runtime zero does not become recognized null-constant provenance. For `t.rows`, lookup returns offset zero, so the pending address is G; materialization predicts the stipulated 7 and publishes `lv-value`, retaining T=`int`.

**Acceptance check.** You should identify the value versus address before each load and keep the local's slot after materialization. If only the second part was missed, reread the materializer's final two writes and test it against `lv-local` directly.

### C12-02 — Repair publication order on paper

The proposed D/T/Q writes all precede the reset, so none survives. Calling `cc-mark-deref` with false yields:

| Cell | Result |
|---|---|
| K | `lv-deref` (2) |
| S | Sentinel (−1) |
| T | 0 |
| D | 0 |
| Q | 0 |
| F | 0 |
| N | 0 |
| A | 0 |
| I | 0 |

For the stated intended result, first mark the pending destination, then publish T=`int *` (131073), D=8000, Q=1 and any other meaningful supplied metadata. The example is a low-level ordering fixture; ordinary int-pointer production would not normally need an associated struct descriptor. Saving facts on a builder stack before the reset and restoring them afterward is also correct. Writing them twice is unnecessary if they are already available after marking.

A normal legacy materialization of that pending qword address appends a load, changes K to `lv-value` and S to sentinel, but keeps T/D/Q and other retained cells. The default decay hook is empty. In contrast, `cc-mark-not-lvalue` changes K/S and clears all seven other cells, without emitting the memory load. Calling the mark alone would relabel an address as a value without fetching the intended contents.

**Common wrong turn.** Retaining D because “the descriptor itself is still allocated” confuses object lifetime with the current cell's contents. D's allocation can survive while the cell that pointed to it has become zero.

**Changed case.** `cc-mark-typed-value` first resets all nine cells through `cc-mark-not-lvalue`, then publishes T=`int` and D=0. Final K=`lv-value`, S=sentinel, T=131072, D=0; Q/F/N/A/I are all zero. No old char-field pointer, array count, or inner width leaks into the fresh result. This helper emits no load or literal by itself.

**Acceptance check.** Name both the erased metadata and the absence of an emitted load. If the ordering is clear, proceed to the changed case without copying the reset table.

### C12-03 — Follow a field without mixing addresses

Let the descriptor's current field records be R0 and R1. `cc-find-field` saves the supplied needle address/length and D in its three search cells, then loops over count two:

1. Record R0 names `rows`, length four. Needle `stars` has length five, so skip byte comparison and advance
2. Record R1 names `stars`, length five. Its five bytes match the needle
3. Publish `cc-ff-result-record=R1`, result descriptor 0, result type 131072, and result array 0 in this legacy profile
4. Return byte offset 8 on the builder data stack

The field consumer appends addition of eight to the existing target base 12000, predicting field address **12008**. It marks qword pending and republishes the field's type/descriptor. The lookup itself reads builder names/records; it neither reads target address 12008 nor stores R1 in generated RDI.

For needle `start`, R0 again fails on length. R1 passes length but fails the byte comparison at the final character. The loop exhausts count and ends with error **90**. Its failure does not publish a valid new field result; do not treat leftover result globals from a prior successful call as the answer.

Descriptor zero is rejected by the **field parser** before lookup with error **100**. A valid descriptor with count zero passes that presence check but `cc-find-field` reads no field records and ends with **90**. Capacity eight does not make any of those unpopulated slots searchable.

**Common wrong turn.** `D+8` accesses a builder-header coordinate, not the target member. Offset eight is added to the object base G only after descriptor lookup returns it.

**Changed case.** In the separately supplied LP64 layout, `stars` still matches record 1 but returns offset **4**, so target address is **12004**. Result type remains int, descriptor remains zero, and result array is zero because no array field was supplied. The native member producer also publishes F=the matched record and combines inherited/member qualifiers. The default typed materializer uses a **four-byte** int load. Neither the name length nor the builder record's byte stride determines that load width.

**Acceptance check.** Separate all three failure/success situations: no descriptor, no matching field, and a found field whose value has not yet been loaded.

### C12-04 — Preserve two different things

For `w[2]`, `[` is already current and its symbol ID is on the builder data stack. The helper accepts its local kind and positive count four, emits LEA of slot 3, and predicts B=`RBP−32`. Since this is an inline array, its element type stays int rather than losing a pointer layer.

| Transition | Builder saved return facts | Generated temporaries | Future RDI / RCX |
|---|---|---|---|
| Before index | `[int,false]` | `[]` | RDI=B |
| Emit PUSH | Same | `[B]` | RDI=B |
| Literal 2 | Same | `[B]` | RDI=2 |
| Shift by 3 | Same | `[B]` | RDI=16 |
| POP RCX | Same | `[]` | RDI=16, RCX=B |
| ADD | Same | `[]` | RDI=B+16 |
| Consume `]`; publish | Saved facts consumed | `[]` | RDI=B+16 |

Final K=`lv-deref`, S=sentinel, T=int, D=0. No element load was needed. Index parsing uses fresh current expression metadata, but cannot overwrite the two saved builder facts or the base already staged in the generated program. The bracket has been consumed; later input belongs to the caller's next token read.

For a valid local `char *p` with zero array count, the identifier-index helper uses a qword local load to obtain P. This is a pointer-slot read before indexing. It removes one pointer layer, so the saved element type is plain char and the byte-step flag is true. Emit PUSH P, literal 2, no shift, POP RCX=P, ADD to predict `P+2`. Publication is K=`lv-deref-byte`, S=sentinel, T=char (65536), D=0. Only a later materialization reads the selected character, with one-byte zero extension on this legacy path.

**Common wrong turn.** “Char always means stride one” overlooks pointer depth. An array element that is a char pointer occupies eight bytes here.

**Changed case.** For an inline array of `char *`, let its base be V. The first `[2]` consumes the array dimension and retains element type `char *` (65537), so stride is eight. It leaves pending address `V+16`, K=`lv-deref`, T=`char *`. Assume the qword there contains valid pointer P.

The general postfix `[1]` first materializes that pending pointer slot, predicting RDI=P. It saves type `char *`, stages P, parses literal 1, uses byte stride with no shift, and produces `P+1`. Final K=`lv-deref-byte`, T=char; a future materialization reads the character. The first pointer-slot load is necessary to obtain the second base; the final character load is still deferred. Both generated base temporaries have been popped when their index helper returns.

**Acceptance check.** Explain why one indexing step removes an array dimension while the next removes a pointer layer. If this distinction is unstable, repeat only the type/stride decisions before reconstructing both stacks.

### C12-05 — Choose the consumer

Grouping uses `cc-parse-assign-fwd` in legacy, then requires `)`. It does not itself call the public materialized expression entry.

- `(r)` inherits RDI=2, K=`lv-local`, S=4, T=int, D=0
- `(t.stars)` inherits RDI=`G+8`, K=`lv-deref`, S=sentinel, T=int, D=0

An eager call to `cc-parse-expr` inside grouping would request materialization. It would add no further local load and would leave `r`'s local identity intact. It would load the pending field, predicting RDI=4 and K=`lv-value`; that would remove the pending-address representation needed by a destination consumer. Thus `(r)` alone is an inadequate test of whether grouping preserves all kinds of places.

For a future plain store of supplied value 9, preserve target destination `G+8` while obtaining 9. Retain the destination's legacy qword width; for a typed field, type/descriptor/qualification/field information may also be needed by its store contract. At the actual low-level store interface, RDI must contain 9 and RCX must contain `G+8`. The store writes eight bytes in this legacy fixture. There is no need to read the previous 4 before a plain store. C14 owns how assignment syntax recognizes this destination, saves it across the RHS, and arranges the registers.

This answer does not imply all qualifiers permit a store or every `lv-value` address is assignable. The question supplies an ordinary writable field and asks only for the consumer boundary.

**Common wrong turn.** Describing an assignment parser here invents an unneeded prerequisite. Naming the destination, its lifetime across value production, and the emitter's value/address convention is sufficient.

**Changed case.** Let the pending field's own target address be H, its stored struct pointer be P, and its associated pointee descriptor be D. Grouping preserves RDI=H, K=`lv-deref`, T=struct pointer, and D. Materialization loads P, changes K to `lv-value` and S to sentinel, and preserves D/T. A following arrow needs actual pointer P plus builder D; if grouping left it pending, arrow's materializer obtains P. If it was already materialized, arrow needs no second pointer load. Field lookup then uses D, not H or P, to find the next offset.

**Acceptance check.** Preserve descriptor identity across a load without confusing it with either target address.

### C12-06 — Produce a value without an object load

Start with primary's reset independently in each legacy case. Q/F/A/I remain zero throughout these scalar examples.

| Operand | Future RDI | K / S | T / D | N |
|---|---|---|---|---|
| Numeric `0` | 0 from immediate | `lv-value` / sentinel | 0 / 0 | True |
| Character `'A'` | 65 from immediate | `lv-value` / sentinel | 0 / 0 | False |
| Supplied enum value 0 | 0 from immediate | `lv-value` / sentinel | 0 / 0 | False |
| Known function name | Its known target address from MOVABS | `lv-value` / sentinel | 0 / 0 | False |

The enum arm calls `cc-mark-int-value`, which clears N; legacy also leaves T zero. The numeric arm records null provenance directly. Equal future bit patterns therefore need not have identical provenance metadata. None of these cases requires reading the target object's stored value; the literal value or known address is embedded in an instruction. The enum value itself was read from a builder symbol row.

For an unresolved prototype, `cc-parse-func-ref` emits a **ten-byte MOVABS placeholder**, records the imm64 operand's **eight-byte field offset**, and appends it to the symbol's **address-fixup list**. It is not a CALL or a rel32 call fixup. With unevaluated true it still emits the temporary placeholder but drops the ID/patch-offset pair instead of adding the fixup node. C14's enclosing unevaluated-expression contract owns discarding temporary output; this helper alone does not roll back the output position.

For LP64 with the native inline string provider, adjacent `"A\0" "B"` becomes bytes `41 00 42 00` in hexadecimal: A, explicit zero, B, final implicit zero. K remains `lv-value`, T becomes `char *`, D=0, A=4, I=0; future RDI is the target address of the first decoded byte. The first nonstring token is pending when the provider returns.

The legacy producer processes just its current token `"A\0"`, emitting `41 00 00`: explicit zero plus an additional final terminator. It does not consume/concatenate the second string token and does not publish an array extent; A remains zero from primary reset. This is the producer's behavior, not a promise that the surrounding legacy grammar accepts adjacent strings.

**Common wrong turn.** Counting the two visible letters misses embedded and terminating zero bytes; treating “zero bits” as “null-constant provenance” misses the reset performed by the enum arm.

**Changed case.** LP64 `2147483648LL` selects nonpointer signed long long, encoded `15*65536 = 983040`, size eight. N is false. The positive value is outside signed imm32 range, so the integer literal emitter uses the full imm64 form. The legacy numeric zero had T=0 and N=true; this comparison changes both selected profile and literal, so state both reasons rather than attributing everything to the suffix.

With unevaluated turned off in the unresolved-function fixture, the same placeholder now adds an address-fixup node. Its later function-definition/demanded-shim completion can patch the operand. The function's unknown value zero is not a literal null pointer constant.

**Acceptance check.** Distinguish information read by the builder from generated target loads, and give the exact unit counted by the string extent.

### C12-07 — Name the actual profile

Let x's slot number be s and its valid address L=`RBP−8*(s+1)`. Use independent appropriately sized storage premises in each profile.

| Selection | Producer's emitted work | Metadata after producer | What materialize adds |
|---|---|---|---|
| Legacy | Qword local load | K=`lv-local`, S=s, T=int | Nothing; slot remains |
| LP64, original hook | LEA L, signed four-byte load | K=`lv-local`, S=s, T=int | Nothing; slot remains |
| LP64, installed 121 hook, System V true | LEA L only | K=`lv-deref`, S=sentinel, T=int | Signed four-byte load, then K=`lv-value` |

The caller initially marked the local, but the System V hook replaces K/S. The caller then republishes T/D and restores saved qualification/inner metadata. It does not restore `lv-local` after the hook. Signed LP64 int loading sign-extends four bytes to the expression-register width; an eight-byte RDI does not require an eight-byte object read.

For the supplied LP64 inline matrix, use T=`int *`, D=0, A=4, I=3, Q as supplied. The base is already storage, so the helper skips materialization before saving it. It saves T/D across recursion on the builder data stack, I/Q on the return stack, and M on the generated stack. Literal index 2 replaces current metadata but not those snapshots.

Pointee size is four; saved I multiplies stride to **12**. Scaling gives **24**; restoring M and adding produces **M+24**. Because I was nonzero, publication is an address-like typed value with T=`int *`, D=0, A=3, I=0, and restored Q. It denotes the selected row without loading its first integer. Generated staging is balanced.

**Common wrong turn.** “LP64 local references are always pending” conflates a data model with a specific hook. “A matrix index steps four” ignores the retained row width.

**Changed case.** With 121's hook installed but System V false and LP64 true, its fallback calls `cc-emit-load-local-typed`: LEA plus the signed four-byte load, leaving K=`lv-local`, S=s. Loading the provider did not activate its System V branch.

For the separate short matrix, pointee size is two, row stride `2*3=6`, scaled offset `2*6=12`, and result address **M+12**. It again publishes A=3, I=0, retains pointer-shaped short type and Q, and does not load an element. The output now uses the general scale helper's IMUL-by-six path; it is neither byte no-op nor the specialized shift-by-three case.

**Acceptance check.** Name both profile gates and all three preservation locations. If the matrix is the only difficulty, leave the ABI comparison aside and trace the stride units: bytes/element × elements/row × rows skipped.

### C12-08 — Check owners and policy boundaries

The saved things have different owners:

| Saved item | Nested expression parse | Scope pop and ID reuse | Growth of D's field table |
|---|---|---|---|
| Symbol ID s | Not inherently invalidated, but current expression may no longer refer to it | Can become stale, then name a different declaration | Symbol identity itself unchanged |
| Stable descriptor D | Allocation remains; current D cell may be overwritten | Allocation can remain after the referring symbol loses visibility | Header identity remains; its table pointer changes |
| Field pointer F | The caller's saved pointer can remain, but current F cell may change | Not automatically freed by pop | Can point into the retained old table, no longer current |
| Borrowed name span | Still depends on its source owner | Pop does not copy/free the bytes | Record copying copies the span, not characters |
| Current Q/F metadata cells | Shared cells can be reset or overwritten | Not an independent symbol-lifetime mechanism | No general automatic update of arbitrary saved expression F |

No event in this list establishes all the other owners' lifetimes. A symbol ID must be re-resolved when its declaration can have left the live prefix. A field record must be reacquired through the current descriptor when the table can have moved. Name bytes must still be live and unchanged. Outer expression facts needed after recursion must be saved deliberately, not recovered from whatever current cells now contain.

`cc-field-load-fwd` and `cc-field-store-fwd` consume `(ty rec)`. The default load reads through future RDI; the default store uses value RDI and address RCX. `cc-field-value-type-fwd (ty rec -- ty)` returns the loaded/promoted value type. `cc-field-use-fwd (rec --)` checks whether a use is allowed without itself loading the value. The initial defaults drop the field record; the value-type default returns its input type and the use default is a no-op. Under a qualifying System V bitfield record, 129 replaces those behaviors. A provider name is not sufficient without its activation/record predicate.

**Common wrong turn.** “The arena never freed it, so F is valid” establishes readable old bytes at best, not current-table membership. “Materialize cleared everything” confuses its narrow K/S transition with the reset helper.

**Changed case.** With scope and table unchanged but the owning name bytes overwritten, the span address/length can remain equal while a later lookup observes the new bytes. Keeping that pointer did not preserve the original spelling. This is a paper lifetime counterexample, not advice to alter source during compilation.

For the separate LP64 temporary-record scalar member, dot remembers that the base kind was `lv-temporary`, performs lookup and offset addition, and publishes the selected typed dereference. It records F and combined Q, then materializes the nonarray member and sets K=`lv-temporary`. For an ordinary int field this adds its typed four-byte load; S is sentinel and T=int. The scalar is available, but this member does not become an assignable place merely because an address existed during selection. An inline-array member follows the different no-scalar-load path described in the chapter.

**Acceptance check.** Tie each retained fact to an owner or explicit save. If you can do so independently, revisit the three opening expressions later with their answers closed; immediate familiarity alone does not establish retention or transfer.

## What this feedback establishes

The answers check the requested transitions against the pinned definitions and supplied premises. They do not substitute for compiler execution or a real reader's attempt. Use a discrepancy to locate the next useful step: repair an address/value distinction, reread one reset, isolate a pointer-depth decision, or separate the two profile gates. After the comparison, close the solution and try the changed case rather than treating recognition of this explanation as independent success.
