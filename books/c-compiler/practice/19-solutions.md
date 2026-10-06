# C19 hints and solutions

These solutions use the chapter's fresh legacy direct-ELF profile and manual, source-derived model. They are not execution records. Try a prediction before opening the relevant answer if you want an independent check; hints and complete solutions remain available when useful.

## C19-01 — From a complete program to a process result

**Hint 1.** Keep the builder cursor separate from target RSP. A patch changes neither the cursor nor the length of the function.

**Hint 2.** The entry is at 120, the CALL's opcode at 129, and its four-byte field at 130. The relative base is after that field.

**Hint 3.** The eager prefix ends at `120+26+376=522`. Add the fixed prologue, explicit return, and fallback tail separately.

**Solution.** `main` starts at file offset 522, target address `0x40020A`. Its 34 bytes are `11+7+3+5+3+5`; the next output offset is 556. The entry's displacement is `522−134=388`, stored `84 01 00 00`. The CALL at 129 is `E8 84 01 00 00`. `p_filesz` is 556, stored `2C 02 00 00 00 00 00 00`; `p_memsz` remains 81,920. The ELF entry is `0x400078`.

With initial target RSP=S, CALL stores the return address `0x400086` at S−8. PUSH RBP stores the old frame base at S−16; the frame reserve moves RSP to S−272. The explicit result becomes RAX=7. Epilogue and RET restore RSP=S and resume the stub at 134. The stub copies seven to RDI and requests syscall 60. Seven is an exit argument, not printed text. The later fallback zero is unreachable from the explicit RET.

**Changed cases.** `return 8;` changes the literal byte at file offset 536 but preserves all layout numbers. Empty `main` has 19 function bytes and ends at 541; entry CALL still targets 522 and still uses displacement 388. The fallback path returns zero. The corresponding file-size field is `1D 02 00 00 00 00 00 00`.

**If your result differs.** A displacement of 392 usually subtracts the field start instead of its end. An entry address of `0x40020A` confuses ELF process entry with the C function destination. A result of zero for the original follows source/emission order across a RET that actually leaves the function. Reattempt with an explicit return of nine and identify the one changed file byte before using the answer above.

## C19-02 — Create descriptions without creating objects

**Hint 1.** Enum values and type encodings occupy symbol payloads, but they mean different things.

**Hint 2.** Register an enumerator before incrementing its default. For a typedef, inherited pointer depth is already in the payload.

**Hint 3.** `ty-int=2`, `ty-func=4`; the packing calculation is `base*65536+depth`.

**Solution.** A, B, and C are `sk-enum`, with unused type field zero and payloads 0, 3, and 4. The next default after C is five. E is consumed and discarded as a tag, with no enum-tag row. A's symbol is already available when the builder constant evaluator computes B's `A+3`.

IP is `sk-typedef`, unused type field zero, payload `0x20001` (131073). IPP is likewise a typedef, with payload `0x20002` (131074): the parser fetches IP's encoding and adds one star. FUNCTION gets payload `0x40001` (262145), base `ty-func` and pointer depth one. Its parameter tokens were skipped with balanced parentheses; no checked return/parameter signature survives this typedef path.

These declarations alone add no target object, runtime instruction, or initializer write. They do add builder symbol metadata. A later expression using an enumerator may cause target instructions to be emitted, but registering the name is not that later use.

**Changed case.** X=5, Y=6, Z=8, and next default=9. F is again discarded as a tag. Eight follows from evaluating the explicit `Y+2`; it does not inherit the would-be default seven.

**If your result differs.** B=4 suggests incrementing before registration after its explicit initializer. IPP at depth one loses the inherited star. A target pointer value of `0x20001` confuses a type description with a runtime address. Reattempt with `typedef IP **IPPP;`: its payload should preserve one inherited star plus two new ones. The result is `0x20003`.

## C19-03 — Let lookahead return the input intact

**Hint 1.** The class is a tentative value until a depth-zero terminator is found. The saved lexer state is a separate thing.

**Hint 2.** `=` and `[` set a flag only at parenthesis depth zero. That flag prevents later parentheses from changing a variable to a prototype.

**Hint 3.** For `int a[(3)];`, class stays variable when `(` arrives because `[` has already set the flag.

**Solution.** `int f(void);` starts as variable, becomes prototype on `(`, increments depth to one, returns to zero at `)`, and returns prototype at `;`. The body form has the same intermediate states but selects function-definition class when `{` occurs at depth zero. In `int g=(3);`, `=` first sets the variable flag; parentheses only adjust depth. In `int a[(3)];`, `[` does the same. Both end as variables. In every case mark/reset restores the pending first `int`, so the selected parser receives it on its next `cc-next-token-keep`.

The separate struct lookahead begins with `struct` current, saves state, reads two more tokens, tests whether the second is `{`, and restores state. For admitted `struct TAG {` this selects C15's definition builder. The predicate does not validate the tag token itself. `struct TAG *p;` falls through to ordinary classification.

For the prototype trace, call the first unresolved row P and the definition row D. The initial prototype adds P with address zero. The use adds a field to P's pending-call list. The definition finds P before appending D, patches P's call/address lists to D's target, and clears those heads. D is outside the function-local scope, so it survives function completion. The later prototype finds newest row D already `sk-func` and adds no row; a later call consequently finds D.

Always appending a prototype would introduce a newer unresolved row that hides D. The same name could then appear undefined to later calls despite an emitted body. The actual rule preserves function identity without validating repeated signatures.

**If your result differs.** Returning the token after `{` mistakes classification for actual consumption. Calling `g` a prototype ignores the earlier equals sign. Reattempt with `int h = ((3));` and record depth 0→1→2→1→0 while the variable flag remains set. Its class is still variable, and the original `int` is pending after reset.

## C19-04 — Give the record an object

**Hint 1.** D describes the layout. It does not provide storage for `t`.

**Hint 2.** The new scalar branch allocates in data; the array branch allocates in BSS and does not perform scalar name reuse.

**Hint 3.** A sixteen-byte record consumes data offsets 0–15, so the following scalar begins at slot 16.

**Solution.** All three object names are `sk-global`. `t` has packed type `ty-struct` at depth zero, data slot 0, and associated descriptor D. It occupies sixteen zeroed data bytes. `g` has int at depth zero, slot 16, and takes eight more data bytes. `extern` does not suppress that initial allocation. `a` has int element encoding, slot `2^40+0`, and array length three, requesting 24 BSS bytes.

The second scalar declaration of `g` finds the existing global row, reuses slot 16, and writes `07 00 00 00 00 00 00 00` there. The builder constant evaluator and data-buffer store establish these bytes; no target startup assignment is emitted. Final data length is 24, BSS extent 24. The first sixteen data bytes remain zero.

**Changed pointer case.** `struct tri *t;` takes eight data bytes at slot 0 rather than sixteen, with type `ty-struct` at depth one and associated descriptor D. It allocates a pointer cell, not a tri object. `g` moves to slot 8, data length becomes sixteen, and its initializer occupies data offsets 8–15. The independent BSS allocation remains tagged offset zero, extent 24. `t`'s pointer cell starts at zero; no valid pointed-to tri object follows from that fact.

**Repeated array case.** In the original state, a second `int a[3];` follows the array branch again. It allocates another 24 BSS bytes, registers a newer `a` at slot `2^40+24`, length three, and raises BSS extent to 48. The earlier allocation is not reclaimed. This describes the inspected branch, not a promise about standard-C redeclaration semantics.

**If your result differs.** Making `t` eight bytes loses the descriptor-size condition; making its pointer sixteen bytes confuses the described object with the pointer cell. Reattempt with a known record size 24 and a pointer to that same record: the scalar-size helper yields 24 and eight respectively. Only the depth-zero known record needs the full layout.

## C19-05 — Finish three addresses

**Hint 1.** Reserve and initialize before placement; obtain addresses only after all code and late bodies are emitted.

**Hint 2.** Save the data base before copying. Save the BSS base after copying and its conditional alignment padding.

**Hint 3.** At cursor 1027, `cursor & 7` is three, so five more bytes reach a multiple of eight.

**Solution.** Code-end 1003 gives data base `0x400000+1003=0x4003EB`. Appending 24 data bytes reaches 1027. Nonempty BSS selects five padding bytes, reaching 1032 (`0x408`), so BSS base is `0x400408`, extent 24.

- Field 802 receives `t` address `0x4003EB`: `EB 03 40 00 00 00 00 00`
- Field 818 receives `g` address `0x4003FB`: `FB 03 40 00 00 00 00 00`
- Field 834 receives `a` address `0x400408`: `08 04 40 00 00 00 00 00`

Cursor and file size end at 1032. The full `p_filesz` field is `08 04 00 00 00 00 00 00`. File plus BSS requires 1056 bytes, below the 81,920 minimum, so `p_memsz` remains `00 40 01 00 00 00 00 00`.

**Changed code-end.** At 1008, data base becomes `0x4003F0`. Appending 24 reaches 1032 exactly; padding is zero. BSS base, final cursor, and ELF sizes therefore remain unchanged. `t` becomes `0x4003F0`, bytes `F0 03 40 00 00 00 00 00`; `g` becomes `0x400400`, bytes `00 04 40 00 00 00 00 00`. `a` remains at `0x400408`. Increasing code length by five consumed the old five padding bytes rather than increasing file length.

`cc-finalize-globals` owns these object-address patches. It reads slot and field-offset pairs from the global-fixup arrays. The entry CALL belongs to `cc-call-main-patch` and receives a four-byte relative displacement from `cc-patch-call-main`; it is not an eight-byte object address. Putting it in the global arrays would supply the wrong ownership, width, and representation.

**If your result differs.** Aligning the data base before copying changes the inspected operation order. Adding 24 BSS bytes to the file cursor confuses memory extent with file-backed payload. Reattempt with BSS extent zero and code-end 1003: after the same 24 data bytes, cursor is 1027, no padding is appended, and the prospective BSS base is `0x400403` even though it owns no allocated bytes.

## C19-06 — Demand, define, or leave unused

**Hint 1.** The late-pass condition ORs two heads. “No calls” alone does not imply “no pending use.”

**Hint 2.** An address field receives a complete target virtual address, not a displacement.

**Hint 3.** File offset 700 is hexadecimal `0x2BC`; add the fixed load base before encoding it.

**Solution.** The `strlen` row contains the saved symbol ID at row+24. Its nonempty address list makes the OR condition true. With no prior demanded row, current target address is `0x4002BC`. The pass stores that address in the symbol's value cell, walks the empty call list without a patch, walks the address list and writes `BC 02 40 00 00 00 00 00` at field 602, clears both heads, then executes the emitter token at row+16. The emitter appends the body at that recorded target. The eight-byte field at 602 is already in output; patching it does not advance cursor 700.

The emitter execution token belongs to the running Forth builder. The new symbol payload belongs to the generated address model. Swapping them would put an address from the wrong execution into the program.

If the row is unused, both heads are zero and the late pass emits nothing. If a user definition has already patched and cleared both lists, no built-in replacement is emitted. A pending use of `memset` without a user definition has no late emitter; the subsequent scan reaches error 206. A prototype with no uses leaves both heads empty and is not rejected merely for address zero.

If a function use remains unresolved and no main definition exists, 206 comes first because the function-row scan precedes the `cc-main-vaddr` test. A zero main address with no unresolved use reaches 207. This scan does not check the legacy goto-label table.

**If your result differs.** Omitting the body because the call list is empty ignores the second head. Writing `700−606` to the address field uses the CALL formula on MOVABS. Reattempt with a CALL field at 650 waiting for the same target: its displacement is `700−(650+4)=46`, bytes `2E 00 00 00`. Both sites can target one body while requiring different patch forms.

## C19-07 — Separate four meanings of “finished”

**Hint 1.** Distinguish completed buffer construction, completed file I/O, a valid future control destination, and evidence from a build comparison.

**Hint 2.** An unused prototype has no obligation on either fixup head. An output write can report fewer bytes than requested.

**Hint 3.** The last source line is an invocation. A later library file cannot supply a dependency to a driver that already began executing.

**Solution.** Four corrections are needed:

1. Cursor 556 predicts the requested image length. The writer requests that many bytes once and discards its result; it does not establish a stored 556-byte artifact
2. ELF entry is `0x400078`. The C `main` in the original fixture is `0x40020A`, reached by the stub's patched CALL
3. The end check requires that no function has pending call/address uses, and that main has a recorded destination. It permits unused unresolved prototypes and does not prove all recognized names have bodies
4. The load helper holds the executing `120` until after matching optional libraries, including those numbered above 120. That ordering fact and the chapter's arithmetic do not reproduce Stage A or compare its artifacts

The twelve-byte `/tmp/cc-out\0` object is builder memory produced by `c,` at compiler load time. The final bare `cc-main` invokes the previously defined driver; its `bye` ends the builder after the write attempt. `cc-out-init` resets the output cursor; `cc-globals-init` resets global/BSS usage, global-reference count, and data-buffer contents. Those operations are not an explicit reset of every symbol, arena, profile hook, and main address for repeated compilation in arbitrary state.

For the independent mixed check:

| Field/use | Owner while pending | Completion event / representation |
|---|---|---|
| Loop break/continue jump | Appropriate loop-owned fixup head | Loop parser learns the continue/break destination; patch rel32 |
| Ordinary forward function CALL | Function symbol's call-head | Definition, or demanded late body, supplies target; patch rel32 |
| Function-address MOVABS | Function symbol's address-head | Definition, or demanded late body, supplies target; patch absolute imm64 |
| Global-address MOVABS | Global-reference slot/field arrays | Global placement supplies data/BSS base; patch absolute imm64 |
| Entry CALL | `cc-call-main-patch`, with destination in `cc-main-vaddr` | Successful program completion calls `cc-patch-call-main`; patch rel32 |
| ELF file-size field | Fixed offset 96 in header | After globals/padding, `cc-finalize-elf` patches low four bytes from final cursor |

All these operations overwrite a field, but their owners and knowledge become ready at different times. “Patch everything at function end” and “patch everything at global finalization” both erase distinctions needed by the inspected driver.

**Changed reattempt.** An unused late function is first mentioned only through an address expression; after late emission, its symbol lists are empty. Explain why “no pending lists at the end” does not mean “the program never used that function.” Completion can remove a pending obligation precisely because it has been satisfied.

## Using the results

If the numerical answer is right but its owner is wrong, return to the matching state table before attempting a larger program. If the owner is right but one field differs, check units, little-endian order, and field-end versus field-start. If both are secure, set the solutions aside and revisit the mixed owner question after another chapter; explaining it now does not by itself establish later retention or execution skill.
