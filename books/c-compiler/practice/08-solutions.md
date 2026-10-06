# C08 practice help: names and lexical scope

[Back to the chapter](../chapters/08-names-and-lexical-scope.md)

These are checked manual solutions under the chapter's valid-storage and bounded-arithmetic assumptions. No compiler, Forth example, C example, or test was executed. Use the hints separately if useful; the full solutions remain available. When an answer differs, find the first mistaken distinction: ID versus address, visible prefix versus retained bytes, profile versus namespace policy, or stored set versus combined set.

## C8-01 — Build the row

**Hint 1.** The current count is the new ID. The next count is checked before any store.

**Hint 2.** The payload is on top of the five inputs. Each store consumes one input while the ID stays available on the return stack.

**Checked solution.** The capacity test is `8 <= 8192`, so the append may proceed. It uses ID 7, stores the five inputs in reverse stack order, initializes five auxiliary cells, and then makes count 8.

| Store order | Column at ID 7 | Value |
|---:|---|---:|
| 1 | `cc-sym-val` | 2 |
| 2 | `cc-sym-type` | 131072 |
| 3 | `cc-sym-kind` | 1 (`sk-local`) |
| 4 | `cc-sym-name-len` | 4 |
| 5 | `cc-sym-name-addr` | 5000 |
| 6 | `cc-sym-extra` | 0 |
| 7 | `cc-sym-extra2` | 0 |
| 8 | `cc-sym-desc` | 0 |
| 9 | `cc-sym-inner` | 0 |
| 10 | `cc-sym-qualified` | 0 |

The type cell is at `100000+7*8 = 100056`. Its value is 131072, which encodes nonpointer int. Neither the address nor that encoded number is the local object's current value. Payload 2 names slot 2; the documented slot displacement is `−8*(2+1) = −24`. These facts do not specify any bytes stored in the generated object.

**Wrong path to diagnose.** Returning ID 8 confuses the updated count with the appended index. Treating the logical record as eighty contiguous bytes uses the wrong layout: each column has its own base. Clearing only `extra` and `extra2` misses three initialization stores in the pinned definition.

**Changed case.** Change the kind to `sk-enum` and the payload to 2 while retaining the name span and type argument. The ID and physical store sequence are unchanged, but the payload now is an enumerator's integer value. There is no local-slot displacement to compute. Changing kind can change meaning without changing the number stored.

**Next step.** If the store order was wrong, reconstruct the five-element input stack once. If only ID/count differed, draw the live interval `[0,count)` before and after append, then retry at count 12.

## C8-02 — Recover an outer declaration

**Hint 1.** Track markers and live IDs separately. An empty scope still adds a marker.

**Hint 2.** The first inner pop restores count 4. The next append therefore uses ID 4, regardless of bytes already occupying that row.

**Checked solution.** Starting live IDs are 0–2. The function push records 3; its local `rows` receives ID 3 and raises count to 4. The inner push records 4; inner `rows` and `scratch` receive IDs 4 and 5, raising count to 6.

| Point | Count / depth | Live IDs | Lookup `rows` | Saved ID 4 |
|---|---|---|---:|---|
| Before inner pop | 6 / 2 | 0–5 | 4 | Live inner `rows` |
| After inner pop | 4 / 1 | 0–3 | 3 | Stale; old row bytes remain |
| After sibling push | 4 / 2 | 0–3 | 3 | Still stale |
| After sibling `stars` append | 5 / 2 | 0–4 | 3 | Live ID, now a different declaration |
| After sibling pop | 4 / 1 | 0–3 | 3 | Stale again; `stars` bytes remain |
| After function pop | 3 / 0 | 0–2 | 1 | Still stale |

The first pop removes the inner suffix from lookup. The sibling append overwrites row 4's five supplied fields and zeroes its five auxiliary fields. It does not overwrite row 5. Lookup for `rows` after that append checks `stars` at 4, then finds the outer local at 3. The final pop hides the outer local too, restoring the earlier global `rows` at 1.

No discarded symbol cell is cleared by any pop. Neither are marker cells erased: reducing depth changes which markers are active. Pop mutates depth and symbol count. Appending is what initializes reused symbol storage.

With an empty sibling scope, push saves 4 and pop restores 4. There is no intervening append, so row 4 still contains the old inner `rows` bytes throughout, but those bytes remain outside the live prefix. Default lookup still returns ID 3 until the function pop, then ID 1. A stale row that happens to have a plausible spelling is not live.

**Wrong path to diagnose.** Reporting inner `rows` after its pop treats retained bytes as visibility. Reporting a restored stack pointer invents a write absent from `cc-scope-pop`. Assuming sibling `stars` must use slot 1 confuses reused symbol ID with the chapter's explicitly supplied slot 3.

**Changed case.** Suppose the sibling append has kind `sk-global` instead of `sk-local`. The sibling pop still discards it because its index is at or above the saved count. Kind does not protect a record from count truncation. Its generated storage, if any, follows a separate owner's policy.

**Check your explanation.** A complete answer identifies the cause of restored lookup and gives no invented deallocation or frame-restoration behavior.

## C8-03 — Choose the lookup policy

**Hint 1.** Write two independent questions: which IDs are live, and which kinds does this lookup admit?

**Hint 2.** The default ignores kind. Enabled System V ordinary lookup skips `sk-struct`; its tag lookup accepts only that kind.

**Checked solution.** With count 3, IDs are 0=tag, 1=typedef, 2=tag, all spelling `tri`:

| Count | Policy | Ordinary hook result | Tag hook result |
|---:|---|---:|---:|
| 3 | Default | 2 | 2 |
| 3 | Named System V policy enabled | 1 | 2 |
| 2 | Default | 1 | 1 |
| 2 | Named System V policy enabled | 1 | 0 |

After count becomes 2, ID 2 is outside the scan. The default tag hook then finds the typedef at 1 because it performs no tag filter. Under System V, ordinary lookup finds that same typedef, while tag lookup skips it and returns ID 0.

ID 0 is success. The interface's failure sentinel is −1, so test for a negative result rather than false/zero. In Forth's true/false convention, −1 is true and zero is false; a raw Boolean test would reverse the desired interpretation at these boundary results.

`cc-target-lp64` selects associated-descriptor storage and other data-model behavior, not this kind filter. `070` installs identical defaults. The `121` providers choose filtered behavior using `cc-target-sysv`; when that flag is off, their hooks delegate to the default. Loading a provider, selecting a data model, and enabling its target policy are distinct operations.

**Wrong path to diagnose.** Returning 0 from the default tag hook merely because it is called “tag” assumes behavior that its bound implementation does not provide. Returning the newest record in every mode ignores eligibility filtering.

**Changed case.** Let count be 1 and ID 0 be the only `tri` tag. Both default hooks return 0. Enabled System V tag lookup returns 0, but ordinary lookup returns −1 because no eligible ordinary record exists. At count zero, every one of these searches returns −1 without reading a symbol row.

**Next step.** If policy and scan order blurred together, first cross out ineligible kinds, then scan the remaining IDs backward. Repeat with a newer enumerator: it is an ordinary candidate under the named System V filter.

## C8-04 — Return a place to mutate

**Hint 1.** The two default definitions end in `cell[]`, without `@`.

**Hint 2.** Multiply the symbol ID by eight, then add the appropriate column base. For the persistent record, offsets 32 and 40 are already byte offsets.

**Checked solution.** With ID 4:

| Query | Result | Meaning |
|---|---:|---|
| Default call-fixup hook | `20000+4*8 = 20032` | Address of call-list head cell |
| Default call-fixup hook, then `@` | 3000 | Current call-list head value |
| Default address-fixup hook | `90000+4*8 = 90032` | Address of address-list head cell |
| Default address-fixup hook, then `@` | 0 | No pending address-load sites |

The zero result after fetching is a sentinel stored in a real writable cell. To install the first address-list node, a caller needs address 90032. It must not try to use zero as the head-cell address. Similarly, 3000 names the first call-list node; it is not the location of the symbol's head cell.

With System V enabled and the supplied matching persistent record P=500000, the bound hooks return:

- Call head cell: `P+32 = 500032`
- Address head cell: `P+40 = 500040`

An extra `@` requests the current head stored in each persistent cell. Those contents were not supplied, so their numeric values cannot be inferred from the default-column contents. If the target is off, or there is no matching implicit-declaration record for the function, the providers fall back to the default cells.

**Wrong path to diagnose.** Returning 3000 directly from the default hook adds a fetch that the source does not perform. Returning `P+32*8` applies cell scaling twice: the record offsets are in bytes. Assuming the persistent cells contain the defaults' heads invents a copy absent from this fixture.

**Changed case.** After the function's scope is popped, ID 4 is reused for a local object. Passing that cached ID to the hook no longer identifies the original function. The provider's persistent record may still exist, but it cannot turn an unrelated current ID into the old declaration. A caller must obtain the correct live function identity under its lookup/declaration contract.

**Check your explanation.** State both what the hook returns and what a subsequent fetch would mean. A number without its role is insufficient for deciding where a mutation belongs.

## C8-05 — Separate aliased metadata

**Hint 1.** `extra` is shared by legacy array length and associated descriptor. LP64 moves only the descriptor access to `desc`.

**Hint 2.** Apply writes in the given order. The second write can overwrite the first even when the accessor names differ.

**Checked solution.** The fresh row begins with five zero auxiliary cells. The final physical state is:

| Cell | Legacy | LP64 |
|---|---:|---:|
| `extra` | 8000 | 4 |
| `extra2` | 96 | 96 |
| `desc` | 0 | 8000 |
| `inner` | 12000 | 12000 |
| `qualified` | 0 | 0 |

The first legacy write puts 4 in `extra`. The descriptor setter replaces it with 8000. Inner metadata and object size use separate columns in both profiles.

Consequently, the reads are:

| Reader | Legacy result | LP64 result |
|---|---:|---:|
| Array length | 8000 | 4 |
| Associated descriptor | 8000 | 8000 |
| Inner metadata | 12000 | 12000 |
| Object size | 96 | 96 |

The legacy array-length result 8000 is not evidence for an 8000-element array. It is the result of applying two incompatible interpretations to one cell. This exercise deliberately tests the low-level storage alias; it does not claim a declaration with these facts belongs to the legacy supported subset. Likewise, stored inner metadata 12000 is not automatically a validated array node.

If the legacy-populated row is subsequently read with LP64 selected, the descriptor accessor now reads `desc=0`; array length still reads `extra=8000`. Nothing migrated D. If the LP64-populated row is read with legacy selected, its descriptor accessor reads `extra=4`, not D. Switching the flag changes which cell is read, not which address is a valid descriptor.

`cc-sym-set-object-size` consumes 96 and the ID, then performs a store. It leaves no cell address on the stack. A misleading adjacent comment cannot change the instruction sequence.

**Wrong path to diagnose.** Giving legacy independent length and descriptor values imagines separate storage. Treating 4 as a descriptor after a profile switch promotes an invalid interpretation into valid owned storage.

**Changed case.** Pop the row's scope and append a fresh scalar at the same ID. Its five auxiliary cells become zero even if the discarded record held nonzero values in all five. The five main fields are replaced by the new arguments. Arena data formerly referenced by D or A is not freed by either pop or this initialization; resetting a pointer cell is different from freeing its pointee.

**Next step.** If the alias was missed, write the physical cell names beside both accessor names before calculating. Retry with the legacy writes reversed: final `extra=4`, so both readers report 4, and the intended descriptor was lost instead of the intended count.

## C8-06 — Follow the newest qualifier

**Hint 1.** Every nonzero set allocates 24 bytes and becomes the head. The zero operation consumes its inputs but creates no node.

**Hint 2.** Query follows list order. A newer value 2 replaces the lookup result for R; it is not automatically ORed with 1.

**Checked solution.** After all four setter calls, the arena pointer is 3072, because exactly three nodes were allocated:

| Node address | Next | Key | Set |
|---:|---:|---:|---:|
| 3048 | 3024 | 10048 (R) | 2 |
| 3024 | 3000 | 10096 (S) | 3 |
| 3000 | 0 | 10048 (R) | 1 |

The head is 3048. Allocation is `3*24 = 72` bytes; there is no extra rounding loss because 24 is already a multiple of eight. Query R returns 2 from the head. Query S skips the head and returns 3 from the next node. Setting zero for R neither removes its nodes nor changes the head, so it still returns 2.

For a table move with old base 10000 and byte count 384, the moved interval is `[10000,10384)`. Both old keys lie in it. R's offset is 48; S's is 96. The hook re-keys every matching node:

| Node address | Next | New key | Unchanged set |
|---:|---:|---:|---:|
| 3048 | 3024 | 20048 | 2 |
| 3024 | 3000 | 20096 | 3 |
| 3000 | 0 | 20048 | 1 |

Node addresses and list links have not moved. Querying the current record addresses gives the same associations: `20048 → 2`, `20096 → 3`. Queries using old numeric keys 10048 and 10096 now return zero in this fixture because no node still matches them. The old field-table bytes may remain allocated; this does not keep their old addresses as the current keys.

**Wrong path to diagnose.** Returning 3 for R after setting 2 silently combines nodes. Returning zero after the zero setter invents deletion. Moving only the first matching node leaves older associations keyed to old storage and does not match the provider's all-node walk.

**Changed case.** Add nodes keyed by 9999 and 10384 before the move. Neither moves: the first precedes the interval and the second is exactly its excluded end. A key 10383 would move to 20383 under the numeric range test, although callers should supply real valid field-record addresses rather than arbitrary in-range bytes. The move hook does not validate record alignment.

**Check your explanation.** Separate node storage, key storage, and target field records. Only keys change in this hook; the list is neither compacted nor freed.

## C8-07 — Meet the exact boundaries

**Hint 1.** `cc-check-cap` rejects a prospective count greater than capacity, not equal to capacity.

**Hint 2.** Successful append at count 8191 uses ID 8191. Successful push at depth 63 uses marker index 63.

**Checked solution.** The final available symbol row can be used:

| Starting state | Prospective count | Result |
|---|---:|---|
| Symbol count 8191 | 8192 | Fits; initialize ID 8191, return it, set count 8192 |
| Symbol count 8192 | 8193 | Error 60 before any symbol store |
| Scope depth 63 | 64 | Fits; store current symbol count at marker 63, set depth 64 |
| Scope depth 64 | 65 | Error 61 before any marker store or depth increment |

Scope capacity measures simultaneously active markers. It does not limit the total number of pushes over an entire compilation when pops intervene. Symbol capacity measures the current live prefix; scope pops can make rows available for reuse.

For a separate pop attempt at depth zero, `cc-scope-pop` invokes error 62 before decrementing depth or reading a marker. Through C02's `cc-die`, these errors diagnose the current preprocessed-source line and terminate. There is no normal returned state after a failing operation; saying the check precedes a write is not a promise of recovery or continuation after failure. The fixture does not specify a source-line number, so none can be predicted.

The arrays were allotted to their fixed capacities. A larger arena provides more storage for arena allocations such as descriptors and qualifier nodes, not more entries in these arrays. Arena exhaustion remains independently possible even when symbol and scope counts fit.

**Wrong path to diagnose.** Rejecting prospective count 8192 leaves a valid final slot unused. Accessing marker −1 on a zero-depth pop ignores the leading check. Equating 64 scopes with 64 symbols confuses two independent counts.

**Changed case.** Begin at symbol count 8192 with a valid active marker containing 8000. Pop restores count 8000; the next append fits, uses ID 8000, and makes count 8001. Old rows 8001–8191 may retain bytes but remain outside the live prefix. Separately, two nested empty pushes can both save 8000; their pops restore the same count twice while depth changes each time.

**Next step.** If the boundary was off by one, draw indices from zero through capacity−1 and compare that last index with the count after filling it.

## C8-08 — Audit a cached declaration

**Hint 1.** Four different owners and identity rules are involved. “The bytes still exist” is only one possible precondition.

**Hint 2.** A count truncation affects symbol visibility; table growth affects field-record locations; neither operation copies or repairs borrowed name bytes.

**Checked solution and acceptance criteria.** A sufficient diagnosis separates the references:

| Saved reference | What happened | What a later user must establish |
|---|---|---|
| Inner symbol ID | Pop made it nonlive; a later append may reuse it for another declaration | Reacquire the intended live declaration or use another explicit identity mechanism; `id<count` alone is insufficient after reuse |
| Borrowed name pointer | Neither pop nor growth necessarily changes the source bytes | Retain the correct length and prove the source owner still supplies those stable bytes; this span alone is not a declaration identity |
| Stable descriptor D | Scope pop does not free it; field-table growth keeps the header in place | Its arena allocation must still be valid, and it must still be the intended descriptor; no claim of source-name visibility follows from its survival |
| Field-record pointer R | Growth copies the table and publishes a replacement; the old bytes remain a stale copy | Reacquire the current record through D and the intended valid field index; ensure that index still denotes the intended field |

The qualifier move hook repairs keys inside its own list. It does not walk the client's cache or refresh arbitrary R values. The client cannot infer that a saved record pointer is current because `cc-field-qualified` associations were updated elsewhere.

Retaining arena bytes helps D's storage remain available, but it does not restore a discarded symbol's identity or make old field records current. It says nothing about separately owned source storage. Likewise, matching name bytes does not prove two records are the same declaration: nested scopes deliberately allow matching spellings with different meanings under the low-level table model.

Scope pop cannot repair invalid borrowed spans, restore symbol generations, relocate external field pointers, free arena allocations, undo changes to outer rows, restore local-slot counters, patch pending calls, or enforce complete C namespace rules. It restores count from one checked marker. A complete answer should make that positive mechanism clear, rather than only listing things it lacks.

**Wrong path to diagnose.** Calling all four references dangling is too broad: the stable header and source bytes may still be valid. Calling all four safe because memory remains is equally wrong: visibility and current identity are stricter than physical retention. The important distinction is which prerequisite failed for which intended use.

**Changed case.** Keep the scope active, never append another symbol, and grow only D's table. The original symbol ID remains live under those assumptions; its borrowed name may remain valid; D remains stable; R is still a stale field-record location after growth. This isolates table movement from scope lifetime. In a second contrast, do not grow the table but overwrite the borrowed name bytes: R can remain current while name lookup is corrupted.

**Return check.** In a later session, without this table visible, explain why a saved symbol ID and a saved descriptor address require different validation after leaving a block. Then check the two owner/lifetime stories against the chapter. A correct immediate rephrasing is useful practice; it is not by itself evidence of delayed retention or broader transfer.
