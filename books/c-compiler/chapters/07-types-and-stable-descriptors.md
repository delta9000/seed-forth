# 7. Types and stable descriptors

The recurring program declares `struct tri { int rows; int stars; };`. Its two fields have the same scalar type. Yet the compiler needs more than “integer” to turn `t.stars` into an address: it needs the identity of `tri`, the position of `stars` inside it, and the selected layout policy. What information belongs in one encoded word, and what must survive somewhere else?

By the end of this chapter, you should be able to pack and recover a type word, predict a scalar or integer literal's type under a named profile, and follow a field from a stable descriptor to its current record. You will also calculate small aggregate layouts, explain recursive descriptors, and distinguish storage capacity from a completed field list.

The conceptual prerequisite is [C02's ownership and arena contracts](02-buffers-arenas-and-failure.md), together with C01's distinction between the compiler and its generated program. C06 is useful background, but its lexer machinery is not required here. We introduce the small current-token interface when needed. Symbol lookup and scopes belong to C08; declaration grammar belongs to C15. Later target chapters open calling conventions and advanced aggregate rules.

**Evidence boundary.** The primary source is [060-cc-types.fth at this edition's pinned revision](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/060-cc-types.fth). Every numeric state below is a manual derivation from inspected definitions, not compiler output. Addresses are invented paper addresses in valid owned storage. Assume bounded nonnegative counts and no arithmetic wrap unless a boundary is explicitly discussed. No compiler build, Forth/C execution, or conformance test is claimed.

## Bring addresses; learn the bit notation here

A Forth cell occupies eight bytes. Stack tops are on the right. `@` fetches a cell; `!` stores a value at the address above it. `c@` and `c!` transfer one byte. A record is a group of related cells at fixed byte offsets: `D+16 @` means “fetch the cell sixteen bytes after address D,” not “fetch field number sixteen.”

Try two ownership checks before continuing:

- If an arena returns D for 56 bytes, does allocation alone make those bytes zero?
- If a cell stores address T, does changing that cell move the bytes at T?

Both answers are no. Initialization needs writes; changing a pointer redirects later accesses. C02's allocator and selected-buffer examples provide the recovery route if either distinction is uncertain. Experienced readers can use the profile and record tables as references and start with the growth trace.

A **bit** holds zero or one. Number bit positions from zero at the least-significant end. Position zero contributes 1, position one contributes 2, position two contributes 4, and position sixteen contributes 65,536. Eight bits form a byte. Hexadecimal notation, prefixed `0x` here, groups four bits per digit: decimal 255 is `0xff`, and 65,536 is `0x10000`. Numeric notation does not specify how a cell's bytes are stored.

A **left shift by sixteen** moves a value's bit pattern sixteen places toward larger positions; for our bounded inputs it is multiplication by 65,536. An unsigned **right shift by sixteen** discards the low sixteen bits; integer division by 65,536 gives that result. Division here discards a remainder: `131074 / 65536 = 2`.

A **mask** selects bit positions. Bitwise `and` keeps a one only where both operands have one. Thus `value and 255` retains only its low eight bits. Bitwise `or` keeps a position when either operand has one. These are operations on bit patterns, even when the result is later used as a true/false flag.

## The one-byte boolean base

Base code 17 is `ty-bool`. `_Bool` has size/alignment one in both models and
is unsigned; conversion yields zero or one rather than retaining an arbitrary
low byte. Its packed scalar type is `17*65536 = 1114112`. The existing integer
and descriptor exercises retain their supplied types. See [base and size rules](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/060-cc-types.fth#L35-L110).

## One word describes a kind and pointer depth

The source assigns two regions of a type word:

| Bit positions | Meaning | Allowed representation here |
|---|---|---|
| 0–7 | Pointer depth | 0 for a nonpointer; 1 for one pointer layer; 2 for two |
| 8–15 | Reserved gap | Zero |
| 16–31 | Base-kind code | One of the declared `ty-*` constants |
| 32–63 | Outside these encoded fields | Zero for the named constructors' ordinary inputs |

A pointer is a stored address of another object or function. Depth counts pointer layers, not bytes and not array dimensions. The C spellings `int`, `int *`, and `int **` therefore share a base kind while using depths zero, one, and two.

The three operations are compact enough to read together:

```forth
: ty-make
  swap [lit] 65536 * swap + ;
: ty-base
  [lit] 65536 / [lit] 65535 and ;
: ty-ptr
  [lit] 255 and ;
```

`ty-make ( base depth -- ty )` places the base above the sixteen-bit boundary and adds the depth below it. Addition has the effect of `or` only because valid inputs occupy disjoint positions. It does not validate or mask the inputs.

For `ty-int`, whose code is 2, and depth 2:

| Step | Stack | Reason |
|---|---|---|
| Inputs | `[2, 2]` | Base then depth |
| `swap 65536 *` | `[2, 131072]` | Move the base into positions starting at sixteen |
| `swap +` | `[131074]` | Add the low-position depth |
| Separate `ty-base` query | `[2]` | Divide to obtain 2; the 16-bit mask retains it |
| Separate `ty-ptr` query | `[2]` | The low byte is 2 |

The word is `0x00020002`. If stored as one little-endian eight-byte cell, its decimal bytes are `2 0 2 0 0 0 0 0`, lowest-address byte first. Neither those bytes nor the number 131074 are an `int **` object's address. They are metadata describing its type.

A useful boundary is depth 256. `ty-make` would add 256, placing a bit in the reserved gap, while `ty-ptr` would report zero. The helper did arithmetic successfully but did not construct a valid depth-256 type. Callers own the representation's limits. Do not “repair” an invalid input by trusting whichever accessor returns a plausible answer.

These are all base-kind declarations in `060`:

| Codes | Names |
|---|---|
| 0, 1, 2 | `ty-void`, `ty-char`, `ty-int` |
| 3, 4 | `ty-struct`, `ty-func` |
| 5, 6, 7, 8 | `ty-short`, `ty-long`, `ty-float`, `ty-double` |
| 9, 10, 11, 12 | `ty-uchar`, `ty-ushort`, `ty-uint`, `ty-ulong` |
| 13, 14 | `ty-ldouble`, `ty-array` |
| 15, 16 | `ty-llong`, `ty-ullong` |
| 17 | `ty-bool` |

The unsigned names describe unsigned integer kinds; `llong` means long long. These code numbers are identifiers, not byte sizes or a universal ordering of types. In particular, code 14 does not mean a fourteen-byte array.

## Sizes require a profile; rank requires identity

Two variables in `060` initially contain zero: `cc-target-lp64` and `cc-bootstrap-floatbits`. The first selects the LP64 scalar model when nonzero. The second selects a restricted floating-value representation inside that model. Loading these definitions does not enable either option.

`ty-size` checks pointer depth first, then void and plain char/_Bool, then the LP64 cases. Consequently every encoded pointer below occupies eight bytes regardless of its base or depth. For the **nonpointer base kinds listed below**, the source yields:

| Kind | Legacy size, bytes | LP64 size, bytes; floatbits off |
|---|---:|---:|
| `void` | 0 | 0 |
| Plain `char` | 1 | 1 |
| `_Bool` | 1 | 1 |
| Unsigned char | 8 | 1 |
| Signed/unsigned short | 8 | 2 |
| Signed/unsigned int | 8 | 4 |
| Signed/unsigned long | 8 | 8 |
| Signed/unsigned long long | 8 | 8 |
| `float` | 8 | 4 |
| `double` | 8 | 8 |
| `long double` | 8 | 16 |

The legacy column describes helper results, not a promise that the legacy declaration grammar accepts every spelling. Its early one-byte cases are plain `char` and `_Bool`; extending that one-byte result to `ty-uchar` would misread this implementation.

With LP64 and bootstrap-floatbits both enabled, all three floating kinds return eight instead. This is a bootstrap transport convention for integer bit patterns. It does not implement floating arithmetic or conversions. LP64 describes data sizes; it does not choose a calling convention. The [native provider](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth) and [System V selector](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth) supply distinct later paths.

**Alignment** is a placement requirement expressed in bytes. Alignment four means choose an offset divisible by four when the enclosing base is suitably aligned. `ty-align` uses `ty-size`, except that size zero becomes alignment one. Thus LP64 `int` has size/alignment 4/4, and any pointer has 8/8. The zero-size void answer is not permission to declare a void object.

Neither `ty-size` nor `ty-align` resolves aggregates. A nonpointer `ty-struct` or `ty-array` reaches the eight-byte fallback. That number is not its aggregate size or alignment. Nonpointer `ty-func` also reaches that fallback; it does not establish a function object size or encode a complete function signature. Consumers need the associated descriptor and the correct aggregate accessor.

**Signedness** determines how an integer bit pattern is interpreted and compared. `ty-unsigned?` returns true for pointers and the five explicit unsigned integer kinds. Plain char also returns true in legacy mode and false in LP64. Other scalar kinds return false; that answer alone does not classify them as supported signed integers. These are source decisions, not a claim that every C implementation uses signed plain char.

**Rank** is an ordering used when combining integer types. Equal size need not mean equal rank or equal identity. LP64 long and long long both occupy eight bytes, but have different base codes; long long ranks higher. `ty-long-long?` recognizes either long-long base only at pointer depth zero. An eight-byte pointer to long long is not a long-long scalar.

As a bounded consumer example, [100's `cc-expr-common-type-default`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth) preserves that distinction when equal-size integer operands include long long. Signed long plus signed long long selects long long; unsigned long plus signed long long selects unsigned long long under that helper. Expression conversions and target overrides will be opened later. Our present obligation is to retain information those decisions need, rather than collapse every eight-byte integer to one code.

## A number's spelling also carries type information

The type layer includes integer-suffix recognition and literal typing. We can learn that mechanism without learning the lexer: assume the current token is a numeric token, `tok-num @` contains its already obtained unsigned 64-bit value, and `tok-str-addr @` with `tok-str-len @` identifies its original spelling. C02 introduced these cells. The borrowed spelling must still exist when the type helper reads it.

A **suffix** is a trailing type hint such as `U`, `L`, or `LL`. `cc-integer-suffix-letter?` recognizes exactly `u`, `U`, `l`, and `L`. `cc-integer-suffix-start` advances an address/length pair until one of those letters, or until length zero. It is not another numeric parser: it assumes the lexer has supplied the relevant numeric spelling. Hexadecimal digits contain none of these four letters.

`cc-integer-suffix` resets two scratch variables, `cc-literal-unsigned` and `cc-literal-long`, then invokes `cc-integer-suffix-u`, `cc-integer-suffix-l`, and `cc-integer-suffix-u` in that order: optional U, optional L/LL, optional U. The U helper consumes one U/u only if an unsigned marker has not already been accepted. The L helper consumes one L/l and optionally an immediately following **identical-case** letter. It records longness 0, 1, or 2. The final answer is true only if no text remains.

For suffix `uLL`, the full trace is:

| Stage | Remaining span text | Unsigned flag | Longness |
|---|---|---|---:|
| Reset | `uLL` | False | 0 |
| First U helper | `LL` | True | 0 |
| L helper, first letter | `L` | True | 1 |
| L helper, matching second letter | Empty | True | 2 |
| Final U helper and empty test | Empty | True | 2 |

`LLu` is also accepted. `lL` leaves its second letter unconsumed; `LUL` leaves its final L; `uu` leaves its second u. All three fail. An empty suffix succeeds with both flags zero. Failed parsing can leave partially updated scratch flags, so a caller must check the returned flag rather than treat those cells as a valid result.

`cc-integer-literal-check` finds and parses the current suffix, exiting with code 240 on failure. `cc-integer-literal-type` immediately returns nonpointer `ty-int` in legacy mode. In LP64 it calls that check, then chooses a type from spelling, suffix, and value. These are the source's branches, in decision order:

1. With LL, select signed long long unless U is present or the value is at least 2^63; otherwise select unsigned long long
2. With a single L, make the analogous long/unsigned-long choice
3. With U and no L, select unsigned int below 2^32, otherwise unsigned long
4. Without a suffix, select int below 2^31
5. For larger unsuffixed values below 2^32, a spelling beginning with `0` selects unsigned int
6. Otherwise select long below 2^63 and unsigned long at or above it

Here `2^31 = 2,147,483,648`, `2^32 = 4,294,967,296`, and `2^63 = 9,223,372,036,854,775,808`. A threshold test uses unsigned division: below a positive threshold the quotient is zero; at or above it the quotient is nonzero. This avoids mistaking a value with bit 63 set for a negative value during a signed comparison.

Consider two spellings with value 2,147,483,648. Decimal `2147483648` is too large for the int branch and does not begin with zero; it selects long. Hexadecimal `0x80000000` has the same value but begins with zero and remains below 2^32; it selects unsigned int. The numeric payload alone cannot distinguish them. Their type words are respectively `6*65536 = 393216` and `11*65536 = 720896`.

Two more boundaries expose the policy. `4294967295U` selects unsigned int, while `4294967296U` selects unsigned long. A decimal unsuffixed value at 2^63 selects unsigned long as this compiler's stated bootstrap extension. This is an inspected implementation rule, not a substitute for a complete C literal-conformance argument. Nor does the legacy helper's early return establish that every malformed numeric spelling is accepted everywhere.

**Pause and predict.** What changes if `2147483648` becomes `2147483648LL`? Size remains eight in LP64, but base kind becomes long long, preserving its different rank. If that answer came only from the byte count, revisit the previous section's identity distinction.

## A descriptor supplies the missing identity

Both `struct tri` and `struct node` have base `ty-struct`. At depth zero their type word is 196608. That equality does not say their fields, sizes, or identities are equal. A **descriptor** is a compiler-owned record carrying the additional facts. Its address identifies the record to which later facts belong.

`cc-sd-alloc` obtains a zeroed 56-byte header. This header's address stays fixed; its field table is separate:

| Byte offset in header | Contents | Access |
|---:|---|---|
| 0 | Aggregate total size in generated-program bytes | `cc-sd-total-size`, `cc-sd-set-total-size` |
| 8 | Number of published fields | `cc-sd-field-count`, `cc-sd-set-field-count` |
| 16 | Aggregate alignment | `cc-sd-align`, `cc-sd-set-align` |
| 24 | Union flag | `cc-sd-union?`, `cc-sd-set-union` |
| 32 | Target-owned state cell | Later System V bitfield cursor |
| 40 | Current field-table address, initially zero | `cc-sd-table` |
| 48 | Table capacity in records, initially zero | `cc-sd-table-cap` |

`sd` abbreviates struct descriptor; the same header also serves unions in the LP64 producer. Every reader fetches the listed cell. Each setter takes `(value descriptor --)` and stores there. These accessors neither check descriptor validity nor calculate layout.

Three sizes must stay separate. The header occupies **56 builder bytes**. A field record occupies a profile-dependent number of **builder bytes**. The value in header offset zero describes the **generated C object's bytes**. A 16-byte `tri` does not have a sixteen-byte metadata header.

The connection to names is a deliberately small interface for now. In [070-cc-sym.fth](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/070-cc-sym.fth), a struct-tag symbol keeps its descriptor in its value cell. A struct-typed variable uses `cc-sym-set-struct-desc` and `cc-sym-struct-desc-of`. Those accessors select the legacy extra column or LP64's separate descriptor column. A field record has its own descriptor slot. C08 explains how a name finds its symbol; C07 needs only the guarantee that the correct descriptor travels alongside the type word.

### A record tells us where one field lives

For table address T and field index i, the record address is `T + i*R`, where R is the selected record stride in bytes. Index zero names the first record.

| Byte offset in field record | Contents | Reader / setter |
|---:|---|---|
| 0 | Borrowed name address | `cc-sf-name-addr` / `cc-sf-set-name-addr` |
| 8 | Name length in bytes | `cc-sf-name-len` / `cc-sf-set-name-len` |
| 16 | Encoded field type; element type for the inline-array convention | `cc-sf-type` / `cc-sf-set-type` |
| 24 | Field's byte offset inside its C aggregate | `cc-sf-offset` / `cc-sf-set-offset` |
| 32 | Associated aggregate or pointee descriptor, or zero | `cc-sf-desc` / `cc-sf-set-desc` |
| 40 | Inline array length; zero for scalar | `cc-sf-array-len` / `cc-sf-set-array-len`, LP64 records only |

All readers take the record address. Setters take the value followed by the record address. For a scalar int field, descriptor zero means no aggregate descriptor is needed. A struct pointer can have the same eight-byte storage size while needing its pointee descriptor for a later field access.

`cc-sd-record-bytes-default` returns 40 in legacy and 48 in native LP64. The callable `cc-sd-record-bytes` is deferred: `defer` creates an indirect word, tick obtains an implementation's execution token, and `is` binds it. The [129 provider](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/129-cc-bitfield.fth) returns **72** when the explicit System V target is selected, otherwise the default. Its extra cells retain bitfield information and a second array dimension. We need its stride contract here, not its bitfield algorithm.

Likewise, `cc-sf-array-inner` and its setter are deferred. `cc-sf-array-inner-default` discards the record address and returns zero. `cc-sf-set-array-inner-default` accepts zero without writing; nonzero exits with code 213. The System V provider uses the cell at offset 64. This is an explicit capability boundary, not an unimplemented cell you may write in a forty-byte record.

Choose the profile before allocating descriptors and keep it consistent while they are live. A forty-byte table cannot be reinterpreted as forty-eight-byte records by toggling a flag.

## Derive `tri` once under each layout contract

The header stores layout results; `060` does not assign field offsets. Two later **producer interfaces** explain the results we will consume without requiring their grammars.

The legacy [`cc-sd-append-field` in 110](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth) places a field at the previous total size, then adds eight and increments field count. Every legacy field consumes an eight-byte slot, including a char field. For `tri`, after appending `rows` the state is `(count=1, size=8, offset=0)`; after `stars` it is `(count=2, size=16, offset=8)`.

The native LP64 producer [`cc-nadd-field` in 115](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/115-cc-native.fth) uses field size/alignment and maintains the largest alignment. For an ordinary struct it rounds the current size upward before placing the next field. The aggregate producer rounds the final size to the aggregate alignment. For positive alignment a, that rounding is `(n+a−1)/a*a`; integer division removes the incomplete multiple. For example, rounding 5 to alignment 4 gives `8/4*4 = 8`.

Thus LP64 `tri` places its first four-byte int at offset 0 and its second at offset 4. Its final size/alignment is 8/4. `t.stars` consequently means base-of-t plus 8 in legacy and base-of-t plus 4 in this LP64 layout. The type word for each field remains 131072 in both. The changed profile changes the interpretation of that word and the descriptor's layout results.

A contrast makes padding visible:

```c
struct sample { char lead; int count; char tail; };
```

| Producer | `lead` offset | `count` offset | `tail` offset | Size before final rounding | Final size |
|---|---:|---:|---:|---:|---:|
| Legacy eight-byte field slots | 0 | 8 | 16 | 24 | 24 |
| Native LP64 ordinary struct | 0 | 4 | 8 | 9 | 12 |

In LP64, lead uses byte 0; bytes 1–3 are padding before count; count uses 4–7; tail uses 8; bytes 9–11 are final padding. Padding occupies space but is not another named field. This calculation establishes neither initial byte values nor a calling convention.

For a union, the LP64 producer assigns each field offset zero and keeps the maximum occupied size, then rounds the result to maximum alignment. The corresponding union of these three fields therefore has offsets 0,0,0 and size/alignment 4/4. A union shares storage among alternatives; this layout fact alone supplies no rule about which alternative a program may read.

## Keep the header stable while the table grows

`cc-zalloc ( bytes -- address )` combines two distinct jobs: call C02's `cc-alloc`, then clear exactly the requested byte span with byte stores. It saves the returned start, walks from start to start+bytes, and returns the saved start. A request for nine reserves sixteen arena bytes but clears only nine; allocator padding is not automatically cleared. A header request of 56 reserves and clears exactly 56, so all seven cells start at zero.

The initial field-table policy is eight records. `cc-sd-field-cap` chooses a member limit of 16 in legacy or 1023 in LP64. The constants `cc-sd-max-fields`, `cc-sd-lp64-max-fields`, `cc-sd-header-bytes`, and `cc-sd-initial-fields` name those four policies. A member limit and an arena byte limit are independent: a permitted member count can still exhaust arena storage.

`cc-sd-field-rec ( descriptor index -- record )` checks that index+1 does not exceed the selected member limit, using error 50. If the index is outside table capacity, it invokes `cc-sd-grow`, then calculates `table+index*stride`. It does **not** require index to be below field count and does **not** increment that count. It serves builders reserving a next record as well as readers retrieving existing records. Callers must supply a nonnegative index and distinguish those two uses.

Here is a complete legacy storage trace. Start with arena pointer 1000 and enough capacity:

| Operation | Result and newly established state |
|---|---|
| Allocate header D | D=1000; reserve/clear `[1000,1056)`; all header cells zero |
| Request record 0 | Allocate 8×40=320 bytes at T=1056; pointer becomes 1376; header table=1056, capacity=8 |
| Producer fills eight records | Field count becomes 8; records start at 1056,1096,…,1336 |
| Request record 8 | Grow to 16 records; allocate 640 bytes at U=1376; pointer becomes 2016 |
| Copy old capacity | Copy 320 bytes from T to U; the new allocation was zeroed first |
| Publish replacement table | Header at D now stores table=1376, capacity=16 |
| Return requested record | U+8×40=1696; field count is still 8 |
| Producer writes/publishes ninth field | It fills record 1696, then updates field count to 9 |

Why can other metadata keep D? No operation moves the header. Why can it not keep record pointer 1056 as the current first field? The live first record now begins at 1376. The old bytes remain allocated, but they are a stale copy. Mutating offset cell `1056+24` would no longer update the live record's offset cell `1376+24`.

`cc-sd-grow` starts from twice the current capacity, raises it to at least eight, doubles until the requested count fits, and caps it at the member limit. The normal entry through `cc-sd-field-rec` has already checked that requested count. Direct callers must preserve that precondition. Growth clears the new table, copies **old capacity × stride** bytes, invokes `cc-sd-table-moved ( old new bytes -- )`, then stores the new pointer and capacity. Its scratch descriptor variable makes this shared mutable machinery, not independent overlapping allocations.

`cc-sd-table-moved-default`, the default moved hook, drops its three arguments. In native mode, `cc-nqualified-move` updates qualification entries keyed by field-record address. For native LP64 record index 2, the old address is T+96 and its replacement is U+96 because this profile uses a 48-byte stride; the offset is preserved while the base changes. [070's qualification records](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/070-cc-sym.fth) are linked 24-byte nodes containing next pointer, record address, and qualifier set. The reader finds the newest matching record; a nonzero setter adds a node, while a zero setter adds nothing. The move hook preserves those associations. It does not refresh arbitrary cached pointers in callers.

The arena does not free outgrown tables. Our ninth-field example has retained 56+320+640=1016 bytes, although only 56+640 are currently used by its header/table. A first field reserves eight records, so “less than twice as much table space as fields” is not true for every small aggregate. At larger sizes doubling amortizes growth, but retained tables remain a real cost. If an initially empty LP64 descriptor appends fields one at a time through count 513, the allocated capacities are 8,16,32,64,128,256,512,1023: 2039 retained record slots. Record stride must still be supplied before converting that count to bytes.

**Stop/resume point.** Keep three facts on your scratch page: D=1000, current table=1376, old table=1056. On resuming, explain which address a recursive type may retain, and which a field mutator must reacquire. If those addresses have blurred together, repeat only the replacement-table rows before moving on.

## Allocate identity before all its facts are known

Consider a linked node:

```c
struct node { int value; struct node *next; };
```

A **recursive reference** points back to the same type being defined. It need not imply an infinite-sized object: `next` stores an eight-byte pointer, not another complete node inside itself.

The legacy producer allocates a zeroed descriptor D and registers the tag before reading the body. While D is unfinished, the `next` field can store type `ty-make(ty-struct,1) = 196609` and associated descriptor D. After both fields, the legacy header says count=2 and size=16, with offsets 0 and 8. The pointer already stored in the field still names the same header. Completing its fields changes facts behind that identity.

Under the native LP64 layout interface, value occupies bytes 0–3, padding occupies 4–7, and next occupies 8–15: size/alignment 16/8. This example happens to have the same offsets and total size as legacy, even though its int uses fewer bytes. Matching total sizes cannot identify a profile.

An unfinished descriptor is not interchangeable with descriptor zero. D names allocated storage whose facts can later change; zero is a sentinel for absent metadata. The native aggregate producer can retain an existing tag's header for later completion. The legacy soft tag lookup may instead return zero for an unknown opaque reference; it does not promise a later definition will retroactively repair every saved zero.

Nor does a zeroed header announce a legal, complete zero-size object. It has no separate completeness flag here. Consumers must use their own validation and context. A pointer's storage size can be determined before its pointee layout; accessing a field or embedding a complete aggregate requires more information. C15 will explain which declarations produce and consume those states, rather than treating these low-level accessors as grammar validators.

## Array descriptors retain shape beyond pointer depth

Arrays provide another reason to carry a descriptor. Four consecutive ints have an element type, a count, a total size, and an alignment. A pointer depth alone records none of the count or row shape. Not every parser array uses the same representation: the field-record `array-len` cell and symbol array metadata remain live conventions. The seven `cc-ad-*` readers in `060` define an additional array-node interface:

| Offset | Reader | Value |
|---:|---|---|
| 0 | `cc-ad-type` | Element type word |
| 8 | `cc-ad-desc` | Element's associated descriptor |
| 16 | `cc-ad-count` | Element count for this node |
| 24 | `cc-ad-inner` | Additional inner dimension at the producer interface |
| 32 | `cc-ad-size` | Total array size, bytes |
| 40 | `cc-ad-align` | Alignment, bytes |
| 48 | `cc-ad-qualified` | Element qualifier set |

These words fetch; none allocates or validates a node. The named producer we need is [`cc-sysv-array-node ( type descriptor count inner -- descriptor )`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth). It allocates 56 bytes, fills the cells, and canonicalizes a nonzero inner dimension into a nested element-array node. “Canonicalizes” means it gives equivalent row shapes the same structural form regardless of the entry form. The completed nodes each retain one dimension and store zero in `inner`.

For LP64 int, inputs `(131072,0,2,3)` describe two rows of three ints. Call the outer address A and the inner address B. The manually derived completed nodes are:

| Node | Element type | Element descriptor | Count | Inner | Size | Alignment | Qualifiers |
|---|---:|---|---:|---:|---:|---:|---:|
| B, one row | 131072 (`int`) | 0 | 3 | 0 | 12 | 4 | 0 |
| A, two rows | 917504 (`ty-array`, depth 0) | B | 2 | 0 | 24 | 4 | 0 |

The row size is `3*4=12`; the outer size is `2*12=24`. `cc-sysv-array-rank` counts these nested nonpointer array layers, producing two for A. This **array rank** means number of dimensions; it is unrelated to integer conversion rank. A pointer to the outer array still occupies eight bytes, though its descriptor describes a 24-byte pointee.

The producer bounds positive counts, supported element forms, dimension depth at 64, and size products at 1 GiB through named helpers. These checks belong to the producer, not automatically to `cc-ad-size`. They do not make arbitrary addresses valid descriptors. `cc-nsize`/`cc-nalignment` are later consumers that select array/aggregate descriptors instead of the scalar fallback.

The qualifier cell uses masks 1, 2, and 4 (bit positions 0, 1, and 2) for const, volatile, and restrict, as declared by `110`'s `cc-qualifier-bit`. A qualifier set is metadata about permitted operations; it does not change this example's byte count. A set containing const and volatile has value `1 or 2 = 3`. `cc-sysv-qualified-node` produces a node with a supplied set. `cc-sysv-qualify-node` combines a requested set with the existing one, returning the existing node if unchanged or a qualified copy otherwise. Copying avoids changing an array node another declaration already shares. The grammar, qualification rules, and array-to-pointer conversions belong to later chapters; these are the bounded producer promises supporting the shared accessors.

## Lookup consumes a live field list

A descriptor becomes useful when a consumer can answer “where is this field?” [`cc-find-field` in 100](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth) takes `(name-address name-length descriptor -- offset)`. This is member lookup within an already selected aggregate, not C08's symbol lookup among program names.

It scans indices zero through field-count minus one. At each record it compares lengths, then compares that many name bytes through `bytes-eq`. The first match supplies the field offset. It also stores the matched record, type, and associated descriptor in `cc-ff-result-record`, `cc-ff-result-type`, and `cc-ff-result-desc`. LP64 copies the inline array length into `cc-ff-result-array`; legacy sets that result to zero. Failure to find a field exits with code 90.

For legacy `tri`, search for `stars`, length five. Record 0 names `rows`, length four, so no byte comparison is needed. Record 1 has length five and bytes `stars`; lookup returns 8 and records type 131072, descriptor zero, and array length zero. An object base of 8000 therefore gives field address 8008. That object base is separate from both the descriptor address and the field-record address in the builder.

Search for `start` instead: lengths match record 1 but the final byte differs, so lookup exits with code 90. Searching an empty published field list reads no records. Lookup uses globals for its needle/results; consumers must preserve results they need before another lookup overwrites them. A saved result-record also becomes stale if its table subsequently grows.

The ownership rule closes the loop. Field records borrow their name bytes, normally from retained source storage; copying records copies pointer values, not those bytes. Header and table lifetimes belong to the arena. Generated C object storage belongs to a different phase. Keeping the header alive is necessary, but not sufficient, if its table, its borrowed names, or its selected record interpretation no longer matches the consumer.

## Practice: seven increasingly independent checks

Use paper states and the explicit profiles. [Hints, checked solutions, and changed cases](../practice/07-solutions.md) are separate from these attempts. One star means a focused application, two combine mechanisms, and three ask for independent diagnosis. These are task scopes, not ratings of the reader. If stuck, identify the first unknown intermediate value and use one hint; a full solution and a pause are both available.

1. **C7-01 — Pack, extract, and question an input. ★** Derive the word for `ty-long` at depth 3, its base/depth results, and all eight little-endian bytes. Explain why using depth 256 breaks the encoding contract even though `ty-make` returns a number. Change the base to `ty-struct` while retaining depth 3: which size result changes in LP64?
2. **C7-02 — Preserve literal identity. ★★** In LP64 with floatbits off, trace suffix states and final types for `2147483648`, `0x80000000`, `2147483648LL`, and `4294967296U`. Derive each type word and size. Diagnose `1lL` through the suffix helper. Change only the profile to legacy and state what `cc-integer-literal-type` itself returns, without making a whole-parser acceptance claim.
3. **C7-03 — Separate three kinds of bytes. ★★** Derive field offsets, padding, final size, and alignment where used for `struct sample` above under legacy and native LP64. How many builder bytes do its header and first table reserve in each profile? Contrast the LP64 union. Explain why a forty-eight-byte record does not imply a forty-eight-byte C field.
4. **C7-04 — Repair a stale record pointer. ★★★** Reconstruct the legacy D=1000 growth trace through requesting index 8, including retained bytes, returned record, and field count before publication. A caller then writes a new offset through the old record-0 pointer. Identify the wrong and right cells. Predict requesting index 16. Separately, for `cc-zalloc(9)` at arena pointer 3000, identify reserved versus cleared bytes.
5. **C7-05 — Complete identity without replacing it. ★★** Trace legacy `node` from a zeroed header D through the two fields. Give each field's type, offset, and associated descriptor; explain how `next` can already contain D. Contrast an unknown tag represented by zero and a second separately allocated but identically shaped descriptor E. Which equalities establish identity, and which do not?
6. **C7-06 — Reconstruct an array graph. ★★★** Under the System V array-node interface and LP64 sizes, derive the completed nodes from `(int-type,0,2,3)`. Then change the element to `short` and the inner count to 5. Give sizes, alignments, type words, counts, and inner values. Explain what qualifying the original outer node with const can change without changing its shared unqualified predecessor.
7. **C7-07 — Follow the whole lookup contract. ★★★** A valid legacy `tri` descriptor has count 2, table T, and records for `rows`/`stars` at offsets 0/8. Trace lookup for `stars` and `start`, including result metadata and object address for base 8000. Change the scenario: only capacity is 8, count is zero. Finally, start with an empty descriptor and append fields one at a time through count 513; compute its retained table/header bytes with the 72-byte System V record provider, and name two independent ways a saved field reference can become unusable.

### Changed cases: keep the answers closed

After checking an exercise, close its solution and try the matching prompt below. Use fresh paper states and the specified profile. These are the same changed cases whose checked answers appear under **Changed case** in the matching [practice section](../practice/07-solutions.md).

1. **After C7-01:** Use `ty-void` at depth zero, then depth one. Derive both type words, sizes, and alignments. Explain how the order of the helper's tests determines the difference.
2. **After C7-02:** In LP64 with floatbits off, type `9223372036854775808LL`, then the same decimal spelling without its suffix. Derive the threshold-test results, base kinds, type words, and sizes. Which source policy determines each choice?
3. **After C7-03:** Keep `struct sample { char lead; int count; char tail; };`, but select the explicit System V record provider with no bitfields. Derive its offsets, final object size, and initial header-plus-table reservation. Which quantities depend on the field-record stride?
4. **After C7-04:** Start a fresh legacy arena at 1000 with byte limit 1000. Allocate the header, fill and publish eight fields, then request index 8. Does each step succeed? Identify the decisive capacity check and the stored pointer/header state immediately before any exit.
5. **After C7-05:** Lay out `struct node { int value; struct node *next; };` using the native LP64 producer. Identify field bytes, padding, offsets, total size, and alignment. Compare with the legacy trace without inferring a field width from total size alone.
6. **After C7-06:** Let C be the const-qualified copy of the original outer array node for two rows of three LP64 ints. Request volatile qualification as well. Derive the combined qualifier set, returned-node identity behavior, size, alignment, and pointer size. Which existing nodes retain their prior contents?
7. **After C7-07:** In a paper state, keep the live legacy `tri` descriptor at count two and reacquire its current field record. Replace its borrowed five name bytes `stars` with `start` in the owning buffer. What does a later name comparison observe, and what did retaining only the address/length fail to preserve? This is an ownership thought experiment, not an instruction to alter input during compilation.

## What we can now keep straight

A type word carries a base kind and bounded pointer depth. Profile-specific helpers derive scalar size, alignment, signedness, and distinctions needed for later rank decisions. A descriptor carries aggregate identity and layout beyond that word. The header stays in place while its field table can move; the arena retains old bytes without making old record pointers current. Literal spellings, borrowed names, and array shapes each carry information that a numeric payload or byte count alone cannot recover.

C08 will connect these representations to names and scope lifetimes. C15 will reopen the producer interfaces as declaration mechanisms. Until then, the working test is precise: can you name the owner and meaning of every address, count, offset, and type in a field access?

### Evidence and limits

The `060` mechanisms covered here include all base declarations and mode flags; type packing/extraction, size, alignment, unsigned and long-long predicates; all suffix/literal helpers; every array, header, and field accessor/mutator; zeroed allocation; field-cap/stride policies; table growth and move notification; and the deferred inner-array interface. [010](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth) defines `bytes-eq`; [020](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/020-cc-arena.fth) supplies retained arena storage, [030](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/030-cc-io.fth) supplies shared indexing/lookup helpers, and [070](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/070-cc-sym.fth) supplies metadata associations. The named later providers are used only to bound those interfaces and the manual layout examples.

The [historical types-and-symbols chapter](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/book/24-types-and-symbols.md) is comparison material, not an alternative layout contract: this edition uses separate growing tables and a fixed 56-byte header. Source-matched derivations remain different from executed tests, complete C/ABI compliance, or evidence that representative readers have mastered the material. Those outcomes are not established by this manuscript.
