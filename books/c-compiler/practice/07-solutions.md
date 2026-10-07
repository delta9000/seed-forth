# C07 practice help: types and stable descriptors

[Back to the chapter](../chapters/07-types-and-stable-descriptors.md)

These are checked paper solutions under the chapter's valid-storage, bounded-arithmetic contracts. No compiler, Forth example, C example, or test was executed. Try the requested state before opening its solution. If the answer differs, locate the first divergent representation: type word, byte size, descriptor address, record address, field count, or object offset. The hints can be used separately; the solutions do not require a prescribed period of struggle.

## C7-01 — Pack, extract, and question an input

**Hint 1.** Long's base code is 6. Pointer depth goes below the reserved byte, not immediately beside the base code.

**Hint 2.** Calculate `6*65536+3`. To list cell bytes, repeatedly take the remainder on division by 256, then continue with the quotient.

**Checked solution.** The packed word is `393216+3 = 393219`, hexadecimal `0x00060003`. Its low-to-high decimal bytes are:

```text
3 0 6 0 0 0 0 0
```

`ty-base` first obtains `393219/65536 = 6`, then retains its low sixteen bits, leaving 6. `ty-ptr` retains the low eight bits, leaving 3. In either profile it is a pointer, so `ty-size` answers eight before examining the base.

Depth 256 gives `393216+256 = 393472`, or `0x00060100`. Bit 8 is set in the reserved gap; the low byte is zero. Extraction still produces base 6 but depth zero. The packer does not reject the input, so its returned number alone cannot establish a valid type word. Treating it as depth zero would lose the originally requested pointer information.

Changing the valid base to `ty-struct` gives `3*65536+3 = 196611`, bytes `3 0 3 0 0 0 0 0`. Depth is still three, so the LP64 size result stays eight. The type word changes; determining which struct is pointed to also needs the associated descriptor.

**Wrong path to diagnose.** Bytes `6 0 3 0 ...` reverse base and depth. Reporting a three-byte object mistakes depth for storage size. Reporting a struct-pointer size from its descriptor skips `ty-size`'s pointer-first branch.

**Changed case.** Use `ty-void` first at depth zero, then depth one. The words are 0 and 1; sizes are 0 and 8; alignments are 1 and 8. This contrast tests the branch order: a pointer to void has storage even though the nonpointer void helper has size zero. It does not authorize a void object declaration.

**Check your explanation.** A complete answer separates the metadata number, its stored bytes, the described object's size, and any needed descriptor identity.

## C7-02 — Preserve literal identity

**Hint 1.** Start with spelling and unsigned value as separate columns. Three examples have the same numeric value but do not all have the same suffix or first character.

**Hint 2.** An empty suffix is valid. LL is recognized before unsuffixed value-range selection. The U-only threshold is 2^32, not 2^31.

**Checked solution.** LP64 and floatbits off give:

| Spelling | Value | Accepted suffix state: unsigned, longness | Base kind | Type word | Size |
|---|---:|---|---|---:|---:|
| `2147483648` | 2147483648 | False, 0 | `ty-long` = 6 | 393216 | 8 |
| `0x80000000` | 2147483648 | False, 0 | `ty-uint` = 11 | 720896 | 4 |
| `2147483648LL` | 2147483648 | False, 2 | `ty-llong` = 15 | 983040 | 8 |
| `4294967296U` | 4294967296 | True, 0 | `ty-ulong` = 12 | 786432 | 8 |

For each empty suffix, reset leaves false/0 and all three optional consumers leave an empty span. The final emptiness test succeeds. For LL, the first U consumer does nothing, the L consumer takes two matching capital letters and records 2, and the last U consumer does nothing. For U, the first consumer takes U and records true; the other consumers see no remaining bytes.

At value 2^31, division by 2^31 is one, so the small-int path is unavailable. The hexadecimal spelling begins with zero and its value divided by 2^32 is zero, selecting unsigned int. The decimal spelling does not begin with zero, selecting long because its value remains below 2^63. The LL spelling uses the earlier long-long branch. For the U-only example, division by 2^32 equals one, selecting unsigned long.

For suffix `lL`, reset gives false/0. The first U consumer leaves both bytes. The L consumer takes lowercase l, records longness 1, but does not take uppercase L because the letters differ. The final U consumer also leaves L. The nonempty remainder makes parsing fail. `cc-integer-literal-check` consequently exits with code 240. The partial longness value 1 is not a successful type result.

With legacy selected, `cc-integer-literal-type` itself takes its early branch: nonpointer `ty-int`, word 131072, size eight. This includes bypassing its own suffix-check call. It does not establish how every surrounding parser path handles malformed input.

**Wrong path to diagnose.** Giving decimal and hexadecimal spellings one type because their values match discards inspected input. Giving LL a long type because both are eight bytes discards rank information.

**Changed case.** For valid LP64 `9223372036854775808LL`, division by 2^63 equals one. Even without U, the long-long branch selects `ty-ullong`, word `16*65536 = 1048579`, size eight. Unsuffixed decimal at that value instead selects `ty-ulong`, word 786432. These are the source's bounded typing decisions, including its stated extension; no overflow or full-language proof is inferred.

## C7-03 — Separate three kinds of bytes

**Hint 1.** First calculate generated-object layout. Only afterward calculate header and table storage in the compiler's arena.

**Hint 2.** Native LP64's largest field alignment is four. Round the position before count and round the final object size; do not round every char's size to eight.

**Checked solution.** Legacy append advances by eight for every field:

| Field | Assigned offset | Total after append |
|---|---:|---:|
| lead | 0 | 8 |
| count | 8 | 16 |
| tail | 16 | 24 |

The fields occupy eight-byte slots under this producer. The descriptor's alignment cell remains its initial zero because this legacy appender does not set it; do not invent an aggregate-alignment result of eight from slot spacing. The legacy consumers use the pertinent size/count layout contract.

Native LP64 lays out the same fields as follows:

| Field | Size/alignment | Position before alignment | Offset | End after field |
|---|---|---:|---:|---:|
| lead | 1/1 | 0 | 0 | 1 |
| count | 4/4 | 1 | 4 | 8 |
| tail | 1/1 | 8 | 8 | 9 |

Count requires `(1+4−1)/4*4 = 4`. Maximum alignment is four. Final rounding gives `(9+4−1)/4*4 = 12`. Padding occupies offsets 1–3 and 9–11. The table describes positions and extents, not the contents of those padding bytes.

Both modes allocate a 56-byte header and an initial table with eight records. Legacy reserves `56+8*40 = 376` builder bytes; native LP64 reserves `56+8*48 = 440`. Those totals do not include name bytes, which the records borrow, or other compiler metadata. The generated objects occupy 24 and 12 bytes respectively. None of these counts is interchangeable.

For the LP64 union, every field offset is zero. The maximum field size is four, maximum alignment four, and final size four. Sharing a placement does not make three simultaneously independent objects.

**Wrong path to diagnose.** Multiplying three fields by the metadata stride computes neither the initial table reservation nor the C object size: the table reserves eight records, and the object follows a separate placement rule.

**Changed case.** Use the explicit System V record provider, retaining an ordinary three-field LP64 struct layout with no bitfields. The shared prefix still describes offsets 0,4,8 and size 12, while initial metadata reservation becomes `56+8*72 = 632` bytes. Different compiler metadata footprints can describe the same C object layout. Detailed System V producer behavior remains a later subject.

## C7-04 — Repair a stale record pointer

**Hint 1.** Maintain three independent values: header address, table address, and arena pointer. Only the first stays fixed throughout this trace.

**Hint 2.** Requesting record 8 requires nine available records. The capacity becomes sixteen; the index remains eight, not sixteen.

**Checked solution.** Header D=1000 occupies 56 bytes, so the first table begins at 1056. Eight legacy records reserve 320 bytes and bring the arena pointer to 1376. After publication, field count is eight.

Requesting index 8 passes `8+1 <= 16`, then triggers growth because capacity 8 is not greater than index 8. A sixteen-record table reserves 640 bytes at 1376, bringing the pointer to 2016. Its entire span is initially cleared. Copying the old 320 bytes retains existing records. The header then stores table 1376 and capacity 16. Returned record address is `1376+8*40 = 1696`.

No step inside `cc-sd-field-rec` publishes an additional field. Count is still eight until its caller fills and publishes the ninth. Retained arena bytes are `56+320+640 = 1016`; live header/current-table bytes are 696.

The cached old first-record address is 1056. Its offset cell is `1056+24 = 1080`. The live first-record address is 1376, whose offset cell is 1400. A store at 1080 changes the retained old copy. Reacquiring `cc-sd-field-rec(D,0)` gives 1376, so a subsequent setter reaches 1400.

Requesting index 16 asks for a seventeenth slot, exceeding the legacy member limit. Error 50 occurs before growth. There is no successful returned record to use afterward.

For `cc-zalloc(9)` starting at 3000, `cc-alloc` reserves sixteen bytes, `[3000,3016)`, and advances its pointer to 3016. The zeroing loop writes only `[3000,3009)`, addresses 3000 through 3008. The remaining seven reserved bytes have no initialized value established by this operation.

**Wrong path to diagnose.** Saying the old pointer is freed confuses stale identity with deallocation. Saying the old pointer is current because it remains readable misses the header's redirection. Saying zalloc clears allocator padding gives its loop a larger end address than the source computes.

**Changed case.** Keep arena start=1000 but set its byte limit to 1000. Header and first table still fit, using 376 bytes. The attempted replacement would bring total use to 1016 and therefore fails through allocator code 10. Immediately before that exit, the stored arena pointer is still 1376 and the header still selects its old table/capacity. The member-count test passed; arena capacity was the independent blocker. No rollback or recoverable return is implied.

## C7-05 — Complete identity without replacing it

**Hint 1.** The pointer field needs the node descriptor's address, not its final size, to record its pointee identity.

**Hint 2.** Compare equality of type words, equality of layout facts, and equality of descriptor addresses separately.

**Checked solution.** Initially D names a 56-byte zeroed header: size=0, count=0, table=0, capacity=0. Its tag is registered before the fields are produced. After legacy appends:

| Field | Type word | Offset | Associated descriptor | Header after append |
|---|---:|---:|---|---|
| value | 131072: int, depth 0 | 0 | 0 | count=1, size=8 |
| next | 196609: struct, depth 1 | 8 | D | count=2, size=16 |

The first request allocates the field table. The second fits in it. `next` occupies one pointer slot; its descriptor slot references D, so the metadata graph has a link back to its own header. No embedded full node is needed to determine the pointer's eight-byte storage size. After completion, the same D supplies the final size and member list.

An unknown tag represented by descriptor zero has no such retained header to update. The legacy soft lookup's sentinel does not promise that a future definition will repair prior zero entries. Conversely, D's initial size zero means only that its current header facts are unfinished; it does not certify a complete zero-size aggregate.

A separately allocated E can hold identical field layouts and the same nonpointer struct type word 196608. D and E still name different descriptor identities. Equality of type words establishes common encoded kind/depth; equality of sizes/offsets establishes agreement of those layout facts; neither establishes descriptor identity. This is not a complete C type-compatibility algorithm.

**Wrong path to diagnose.** Replacing D with a new “finished descriptor” would leave earlier fields pointing at the unfinished one unless every reference were repaired. This design instead keeps D and mutates its facts. Calling a pointer field infinitely large mistakes a pointer to a node for a node embedded by value.

**Changed case.** Under native LP64, value uses bytes 0–3, padding 4–7, and next 8–15. The final size remains 16 and offsets remain 0/8; aggregate alignment is eight. Matching these final numbers with legacy does not mean the int field has the same width. Use the selected profile when interpreting a scalar field.

## C7-06 — Reconstruct an array graph

**Hint 1.** The constructor converts a nonzero inner count into a separate element-array node. Completed nodes have inner=0.

**Hint 2.** Calculate a row first, then multiply its size by the outer count. The outer node's element type changes to nonpointer `ty-array`.

**Checked solution.** `int-type = 2*65536 = 131072`. A nonpointer array type word is `14*65536 = 917504`. With LP64 int size/alignment 4/4, the inner row B stores:

```text
type=131072, descriptor=0, count=3, inner=0,
size=12, alignment=4, qualifiers=0
```

Outer A stores:

```text
 type=917504, descriptor=B, count=2, inner=0,
 size=24, alignment=4, qualifiers=0
```

The leading spaces are presentation only; both lines describe cells, not executed output. Each node reserves 56 bytes. Array rank is one at B and two at A. Scalar `ty-size` on the outer array word would return its fallback, so obtaining 24 requires the descriptor-aware consumer.

For short and inner count five, `short-type = 5*65536 = 327680`, with LP64 size/alignment 2/2. The replacement row B2 has type=327680, descriptor=0, count=5, inner=0, size=10, alignment=2, qualifiers=0. Outer A2 has type=917504, descriptor=B2, count=2, inner=0, size=20, alignment=2, qualifiers=0. Changing both element size and row count tests shape multiplication rather than copying the earlier total.

Qualifying original outer A with const combines old set 0 with bit 1. The result differs, so `cc-sysv-qualify-node` constructs a new outer node C with qualifier set 1 and the same element type, B descriptor, count, size, and alignment. A remains unqualified; another declaration sharing it does not silently change. A further request to add const to C leaves the set unchanged and can return C itself.

**Wrong path to diagnose.** Putting 3 permanently in A's inner cell misses canonicalization. Giving the outer node scalar int as its element type loses the fact that one outer element is a complete row. Mutating A's qualifier cell in place is not the inspected shared-node qualification interface.

**Changed case.** Add volatile to C. The combined set is `1 or 2 = 3`, so another qualified outer node is produced, still size 24 and alignment 4. A pointer to any of these outer-array types remains eight bytes. Distinct qualification and row shape do not turn pointer depth into an array dimension count.

## C7-07 — Follow the whole lookup contract

**Hint 1.** The loop bound is field count, not table capacity. Compare lengths before byte contents.

**Hint 2.** For memory accounting, add every retained table capacity first, multiply once by the selected stride, then add the fixed header. Name bytes and other metadata are outside this subtotal.

**Checked solution.** For `stars`, length five, index 0 names `rows` of length four and is skipped before byte comparison. Index 1 has equal length and equal bytes. With legacy stride 40, its record address is T+40. Lookup stores:

- `cc-ff-result-record = T+40`
- `cc-ff-result-type = 131072`
- `cc-ff-result-desc = 0`
- `cc-ff-result-array = 0`

It returns offset 8. For generated-object base 8000 the addressed field begins at 8008. T+40 is a builder record address and is not added to the generated object's base.

For `start`, record 0 again fails the length comparison. Record 1 has matching length but mismatching bytes (`t` versus `s` at the final position). The search reaches field count without a match and exits with code 90. It does not return -1 or a usable default offset. Do not reuse result globals from a previous successful lookup as if a failed lookup had established new values.

With count zero and capacity eight, the loop performs no record fetches and immediately reaches the field-not-found exit. Reserved slots are not published members, even if some happen to contain zeroes or earlier writes.

Starting with an empty descriptor and appending fields one at a time through count 513, the retained capacities sum to:

```text
8+16+32+64+128+256+512+1023 = 2039 records
2039*72 = 146808 table bytes
146808+56 = 146864 header-and-table bytes
```

The live table alone holds 1023 records, or 73656 bytes. The subtotal excludes source names, qualification nodes, other descriptors, and any other arena user. The 1023-member policy does not promise that a particular arena can supply the required bytes.

Two independent saved-reference failures are enough: table growth makes a cached record address stale; reusing or discarding the source storage invalidates borrowed name bytes. Other valid observations include reusing arena storage or switching the record-stride profile while old tables remain live. Keeping only D stable does not repair these other dependencies.

**Wrong path to diagnose.** Scanning capacity rather than count turns spare storage into fields. Assuming every read of retained old bytes is meaningful confuses continued allocation with current ownership and interpretation. Multiplying 513 by 72 ignores capacity slack and retained earlier tables. The count alone does not determine allocation history: a direct jump to a high field index can allocate a different sequence of tables.

**Changed case.** Keep a live descriptor with count two and a correctly reacquired record pointer, but replace the borrowed five name bytes `stars` with `start` in their owner buffer. A later lookup follows the new bytes; the saved address/length did not preserve the spelling. This illustrates an ownership violation in the hypothetical state, not an instruction to modify compiler input during a real parse.

## Return check

In a later reading session, without copying the tables, draw five boxes: a symbol's type word, its descriptor pointer, the fixed header, the current field table, and a generated C object. Add arrows only where the representation really contains an address. Then explain where pointer depth, field count, field name bytes, and an object's field offset live. Compare afterward with the chapter. If one connection fails, revisit that connection rather than rereading every section.

Correct immediate traces show supported or independent performance on these cases. Delayed reconstruction and changed-case reasoning are additional checks; this manuscript does not claim that unattempted exercises establish retention or transfer.
