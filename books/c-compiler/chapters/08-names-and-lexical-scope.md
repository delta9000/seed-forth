# 8. Names and lexical scope

Three declarations can spell a name `rows`. The compiler must choose one when it sees a use of `rows`, then choose a different one after leaving an inner block. The letters have not changed. What changes is which declaration is visible.

This chapter turns that question into a small state machine: append symbol records, search backward, and restore a saved count. By the end, you should be able to trace nested shadowing, distinguish a symbol ID from its payload and a mutable cell address, select metadata under an explicit profile, and explain why a discarded ID cannot be kept as permanent identity. You will also follow qualifiers when a field table moves.

The prerequisites are [C02's allocation and ownership](02-buffers-arenas-and-failure.md), [C06's borrowed token spans](06-tokens-and-lookahead.md), and [C07's type words and descriptors](07-types-and-stable-descriptors.md). Declaration grammar, generated stack frames, instruction patching, and ABI rules remain later mechanisms. We use their named interfaces only where a symbol record needs a meaning.

**Evidence boundary.** The primary source is [070-cc-sym.fth at revision 7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/070-cc-sym.fth), with the storage, indexing, and type contracts in `020`, `030`, and `060`. All examples below are unexecuted manual derivations. Paper addresses stand for valid, separately owned storage; they are not measured addresses. Counts are nonnegative and arithmetic is assumed not to wrap. A low-level state trace does not establish that every corresponding C program is accepted.

## A quick check before following the names

A Forth cell is eight bytes. Stacks are written bottom-to-top, left-to-right. `@` fetches a cell; `!` consumes a value and an address, storing the value there. `cell[] ( index array-base -- address )`, from [030-cc-io.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth), computes `array-base + 8*index`.

Before reading further, predict these two answers:

- With array base 20000, what address does index 4 select?
- If that cell contains 9000, is the selected address also 9000?

The address is 20032; its stored value is 9000. These numbers serve different jobs. If that distinction is uncertain, revisit C02's pointer-cell examples. If it is familiar, use the next two tables as references and move to the shadowing trace. The chapter's central work is deciding which cell and which meaning a consumer needs, not memorizing column names.

## One logical record, ten physical columns

A **symbol** is a compiler record connecting a name to a declaration's facts. Its **ID** is an index into ten parallel arrays. “Parallel” means that index 4 in every array contributes one field to logical record 4; it does not mean concurrent execution. These fields are not adjacent as one eighty-byte record.

| Array | Meaning at a live ID |
|---|---|
| `cc-sym-name-addr` | Address of the first name byte |
| `cc-sym-name-len` | Number of name bytes |
| `cc-sym-kind` | One of the six `sk-*` categories |
| `cc-sym-type` | Encoded type information where the producer uses this field |
| `cc-sym-val` | Payload interpreted according to kind |
| `cc-sym-extra` | Array length, legacy associated descriptor, or default call-fixup head |
| `cc-sym-extra2` | Default address-fixup head or object-size metadata |
| `cc-sym-desc` | Separate associated-descriptor storage selected by LP64 |
| `cc-sym-inner` | Inner-array metadata supplied by the producer |
| `cc-sym-qualified` | Qualifier set, separate from the encoded type word |

`cc-sym-cap` is 8192. Each column reserves `8192*8 = 65536` bytes; all ten reserve 655360 bytes, or 640 KiB. This excludes the scope stack, names, descriptors, and linked lists. The arrays have fixed capacity here. Allocating more arena space does not enlarge them.

`cc-sym-count` identifies the live prefix: valid live IDs are `0` through `count−1`. At count zero there are none. A **live** record participates in the current symbol-table lifetime; it may still be hidden by a newer record with the same name. The helpers that fetch fields do not test whether a supplied ID is live. Callers must establish that precondition.

The name is a **borrowed span**, an address plus a byte count. `cc-sym-add` stores those two values without copying bytes or adding a NUL terminator. Source names commonly point into retained preprocessed source; callers can also supply other stable storage, such as dictionary-backed names for predeclared runtime entries. The helper imposes a lifetime contract, not a universal source-buffer origin. C06's token can advance while those underlying bytes stay available. Moving the lexer cursor is different from overwriting, releasing, or relocating that storage.

Suppose the stored span is address 5000, length four, containing `rows`. A lookup using different storage containing the same four bytes can match. Conversely, changing the borrowed bytes to `ribs` changes what the table compares, even though its address cell is unchanged. The owner must keep the name bytes valid and stable for every lookup that uses them. Restoring a symbol count cannot repair an invalid borrowed pointer.

### Kind decides what the payload means

The six declarations in `070` are:

| Kind | Code | Meaning of `cc-sym-val` |
|---|---:|---|
| `sk-global` | 0 | Encoded global-storage slot: a data offset or a tagged offset for zero-filled storage (BSS), interpreted by the storage/emission interface |
| `sk-local` | 1 | Local slot index; the documented convention is displacement `−8*(slot+1)` |
| `sk-func` | 2 | Function virtual address when known; zero is used for an unresolved function |
| `sk-struct` | 3 | Address of an aggregate descriptor header |
| `sk-enum` | 4 | Integer value of an enumerator |
| `sk-typedef` | 5 | Encoded type word named by the typedef |

These are category codes, not sizes. `sk-enum` describes an enumerator such as a named integer constant, not a promise that every enum tag has its own record category. Later aggregate producers also use `sk-struct` for struct/union tag records.

A local whose payload is 2 identifies slot 2. It does not mean that the generated C variable currently contains the integer 2. Under the documented slot convention its displacement is −24. Computing that displacement does not establish a complete stack-frame layout or when the slot is initialized. Those belong to later producers and consumers.

Likewise, a typedef's payload is a type word, whereas a struct tag's payload is descriptor D. A generic rule that reads `cc-sym-type` for every possible kind would miss the typedef convention. The type field may be zero for records whose producer puts the relevant information elsewhere. First select a kind-aware interpretation; then read the appropriate field.

## Append one record before publishing the new count

`cc-sym-add ( name-address name-length kind type value -- id )` takes five inputs. With count 4, the new ID is 4. The source first checks whether `count+1` fits the capacity, using error 60. Only then does it store fields.

For a local `rows`, suppose the inputs are `[5000, 4, 1, 131072, 2]`. Here 131072 is C07's nonpointer `int` type word. The following states are manually derived; the return stack holds ID 4 throughout the stores.

| Step | Remaining data stack | Write |
|---|---|---|
| Save new ID on return stack | `[5000,4,1,131072,2]` | None |
| Store payload | `[5000,4,1,131072]` | `val[4]=2` |
| Store type | `[5000,4,1]` | `type[4]=131072` |
| Store kind | `[5000,4]` | `kind[4]=1` |
| Store name length | `[5000]` | `name-len[4]=4` |
| Store name address | `[]` | `name-addr[4]=5000` |
| Initialize remaining metadata | `[]` | Five auxiliary cells become zero |
| Increment count; retrieve ID | `[4]` | `count=5` |

Each store obtains a fresh copy of the saved ID. Inputs are consumed from the top, so payload is written before name address even though name address was passed first. The five initialization stores are worth keeping together:

```forth
  [lit] 0 r@ cc-sym-extra  cell[] !
  [lit] 0 r@ cc-sym-extra2 cell[] !
  [lit] 0 r@ cc-sym-desc cell[] !
  [lit] 0 r@ cc-sym-inner cell[] !
  [lit] 0 r@ cc-sym-qualified cell[] !
```

These cells may contain metadata from a previous occupant of ID 4. Resetting all five prevents a new scalar from inheriting an old array length or a new function from inheriting old pending-call metadata. The first five fields need no separate clearing because the arguments overwrite them.

Only after initialization does the word increment `cc-sym-count`, then return the ID. This ordering makes the live-prefix invariant easy to follow; it is not a concurrency or crash-recovery guarantee. The compiler helpers use shared mutable state.

No duplicate-name test appears in `cc-sym-add`. Calling it twice with the same spelling appends two records. Whether a source declaration is an allowed shadow, a redeclaration to merge, or an error is a caller's decision. The table itself supplies storage and search order.

## Search backward, then ask which namespace was selected

`cc-sym-find-default ( name-address name-length -- id-or-minus-one )` supplies the name columns and current count to `cc-name-find`. That helper starts at `count−1`, checks equal lengths, then checks the name bytes with `bytes-eq`. A match returns immediately; otherwise it decrements the index. Reaching −1 means no match.

For live records `0: rows`, `1: drawing`, `2: rows`, a search for `rows` starts at ID 2 and returns 2. A search for `draw` rejects ID 2 by bytes, ID 1 by length, and ID 0 by bytes, then returns −1. Equal lengths are only a filter. The first `rows` record was never overwritten; it lost the lookup competition.

The empty-table case starts directly at −1 and reads no row. A successful result can be zero, so a caller must distinguish negative failure from a valid zero ID. Testing the result as a Boolean would misclassify ID 0 and can treat −1 as true. `cc-name-find` keeps its needle and column pointers in scratch globals, `cc-nf-a`, `cc-nf-u`, `cc-nf-addrs`, and `cc-nf-lens`; it is not an independently reentrant search context.

Worst-case lookup visits every live row. With N rows it performs N length checks; same-length candidates additionally require byte comparisons. This cost is exchanged for a small implementation and a direct shadowing rule. No hashing or copied name ownership is hidden inside it.

A **namespace policy** chooses which categories compete for a spelling. Newest-first order alone does not select that policy. `070` defines two deferred hooks and installs the same default in both:

```forth
' cc-sym-find-default is cc-sym-find
' cc-sym-find-default is cc-sym-find-tag
```

A deferred word is a call whose implementation can be rebound. With these defaults, ordinary lookup and tag lookup both search all live rows, without filtering kind. The names of the hooks express intended roles, not different behavior by themselves.

The exact later providers establish a bounded alternative. [`cc-nfind-tag` in 115-cc-native.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth) searches backward among `sk-struct` records. [`cc-sysv-find-ordinary` and `cc-sysv-find-tag` in 121-cc-sysv.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth) are bound to the shared hooks: with `cc-target-sysv` off they retain the default; with it on, ordinary lookup excludes `sk-struct`, while tag lookup uses `cc-nfind-tag`. LP64's descriptor-storage switch is not itself this namespace switch.

Consider three live records of the same spelling `tri`: ID 0 is a tag, ID 1 a typedef, and ID 2 a newer tag. Both default hooks return 2. With the named System V policy enabled, ordinary lookup returns 1 and tag lookup returns 2. A later ordinary declaration could hide the typedef without hiding the tag. Members remain C07's descriptor-local names, not rows competing in this scan. These inspected filters are enough to predict the example; they are not evidence of every C namespace, declaration, or scope rule.

## Restore visibility with a stack of counts

A **lexical scope** here is a lifetime boundary in the source's nesting. A scope marker records the symbol count when that boundary begins. `cc-scope-stack` stores up to `cc-scope-cap = 64` markers in eight-byte cells, reserving 512 bytes. `cc-scope-depth` counts active markers, not symbols.

`cc-scope-push` checks `depth+1` against 64 with error 61, writes the current symbol count at marker index `depth`, and increments depth. It adds no symbol and copies no record. Two nested empty scopes can therefore save the same count.

`cc-scope-pop` checks for depth zero before decrementing it. The checked core is:

```forth
: cc-scope-pop
  cc-scope-depth @ 0= if, [lit] 62 cc-die then,
  [lit] 1 cc-scope-depth -!
  cc-scope-depth @ cc-scope-stack cell[] @
  cc-sym-count ! ;
```

Decrementing first selects the most recently stored marker. Restoring that count removes a suffix of the live table. No field-by-field deletion is needed because subsequent searches start below the restored count.

### Follow an inner name out and back

Use the following stipulated event stream, consistent with the table's contracts. It illustrates nested declarations without claiming a full parser run. Initially count is 3 and depth is zero:

| ID | Name | Kind | Payload |
|---:|---|---|---|
| 0 | `tri` | `sk-struct` | Descriptor D |
| 1 | `rows` | `sk-global` | Storage offset 24 |
| 2 | `draw` | `sk-func` | Known virtual address 6000 |

The local rows below use type 131072. Their supplied slot numbers are explicit inputs from a hypothetical producer; the scope helpers do not calculate them. Markers are shown oldest-to-newest, with the newest on the right.

| Event | Count | Markers | Default lookup of `rows` |
|---|---:|---|---:|
| Starting state | 3 | `[]` | 1 |
| Push function scope | 3 | `[3]` | 1 |
| Add local `rows`, slot 0 → ID 3 | 4 | `[3]` | 3 |
| Push inner block | 4 | `[3,4]` | 3 |
| Add local `rows`, slot 1 → ID 4 | 5 | `[3,4]` | 4 |
| Add local `scratch`, slot 2 → ID 5 | 6 | `[3,4]` | 4 |
| Pop inner block | 4 | `[3]` | 3 |
| Push sibling block | 4 | `[3,4]` | 3 |
| Add local `stars`, slot 3 → ID 4 | 5 | `[3,4]` | 3 |
| Pop sibling block | 4 | `[3]` | 3 |
| Pop function scope | 3 | `[]` | 1 |

At the deepest point, lookup checks `scratch` at ID 5 before finding `rows` at ID 4. After the first pop, both IDs 4 and 5 lie outside the live prefix. Lookup starts at ID 3, so the earlier `rows` becomes visible again without being reconstructed.

Now predict what a saved ID 4 means after adding `stars`. It indexes the new `stars` row. Its kind remains local, but the name and slot have changed. An ID has no generation number protecting it from reuse. Immediately after pop it was stale; after append it silently names a different declaration. Even checking that `id<count` cannot prove it still denotes the original declaration.

No generated stack pointer changes in `cc-scope-pop`. It does not restore a local-slot counter, free object storage, emit an instruction, rewind the arena, clear discarded rows, clear old markers, reset qualifier lists, or undo mutations to records below the saved count. The supplied slot 3 for `stars` deliberately avoids inferring slot reuse from symbol-ID reuse. Storage allocation and code generation require separate policies.

A global-kind record added after a marker also disappears on that pop. Records survive because their indices precede the saved count, not because pop recognizes their kinds. Restoring a count is a visibility mechanism, not a complete C storage-duration implementation.

**Stop/resume point.** Save `count=4`, markers `[3]`, and “ID 4 was inner rows but is stale.” On returning, predict the ID assigned by the next append and explain why it need not receive the old local slot. If the trace got tangled, follow only count and marker depth once, then add the lookup column.

## Read metadata through the meaning-specific interface

`cc-sym-kind-of`, `cc-sym-type-of`, and `cc-sym-val-of` each take an ID, compute its column address, and fetch a value. The remaining accessors distinguish meanings that share physical storage. Unless stated otherwise, readers consume `(id -- value)` and setters consume `(value id -- )`.

| Reader / setter | Physical storage and interpretation |
|---|---|
| `cc-sym-array-len-of` / `cc-sym-set-array-len` | `extra[id]`: array element count; zero for a scalar under that convention |
| `cc-sym-struct-desc-of` / `cc-sym-set-struct-desc` | Legacy: `extra[id]`; LP64: `desc[id]`; associated descriptor |
| `cc-sym-array-inner-of` / `cc-sym-set-array-inner` | `inner[id]`: producer-supplied inner-array metadata |
| `cc-sym-object-size-of` / `cc-sym-set-object-size` | `extra2[id]`: object size in bytes for object records using this convention |

The object-size setter executes `cell[] !`, so its stack effect is `(bytes id -- )`; the nearby source comment showing `(id -- cell)` does not describe that body. A reader must follow the definition rather than infer a return value from that comment.

For the recurring `struct tri`, tag ID 0 holds D in its payload. An object named `t` instead holds its local slot or encoded global-storage slot in the payload and carries D through the associated-descriptor accessor. Those two routes reach the same stable header; they do not use the same symbol column. The header can remain valid after the symbol referring to it becomes invisible because their lifetimes have different owners.

Profile-dependent storage matters most when two facts must coexist. In legacy, writing array length 4 and then associated descriptor D to the same ID overwrites `extra[id]`: both readers now fetch D. The legacy convention distinguishes meanings using the type/context and cannot represent those two independent facts there simultaneously. In LP64, length 4 stays in `extra`, while D goes into `desc`. That separation supports richer producer conventions without changing the ten-column indexing rule.

The word name “struct-desc” is historical: later typed producers can carry associated array or function-type descriptors through the selected descriptor channel. The shape and interpretation remain the producer's contract. Similarly, `cc-sym-array-inner-of` returns stored inner metadata; it does not compute rank, construct an array node, or validate its address. C07 taught array-node readers separately. An array count, an associated descriptor, an inner dimension, and an object byte size are related facts, not interchangeable numbers.

Switching `cc-target-lp64` after records have been populated does not migrate any cells. A record written in legacy may have D in `extra` and zero in `desc`; selecting LP64 afterward makes the descriptor accessor read zero. Choose the profile consistently rather than treating the flag as a conversion operation.

### A forward reference needs a writable head cell

A **fixup list** records places in emitted output that need a later address. Its list operations need to replace the head as sites are added. Therefore `cc-sym-call-fixups-default ( id -- cell-address )` computes `extra[id]`'s address without fetching it. `cc-sym-addr-fixups-default` does the same for `extra2[id]`.

The corresponding deferred hooks, `cc-sym-call-fixups` and `cc-sym-addr-fixups`, initially use those defaults. Call fixups concern relative call sites; address fixups concern sites loading a function's address. Later patchers define the instruction details. Here, both interfaces promise a writable cell holding a list head, with zero meaning no pending sites.

Suppose the `extra` column starts at 20000 and function ID is 4. The default hook returns 20032. If that cell holds H=9000, adding `@` produces 9000. ID 4, cell address 20032, and head value 9000 are three different answers. Writing a new head to 9000 would target the list node, not the head cell. A zero head makes the mistake more visible: fetching zero does not give the caller a place to store its first node.

The System V provider supplies one important lifetime boundary. `cc-sysv-call-fixups` and `cc-sysv-address-fixups` can use a persistent implicit-declaration record when the target is enabled and a matching function record exists. Its call and address head cells are at offsets 32 and 40. Otherwise the hooks fall back to the default symbol columns. This lets the provider preserve pending-site identity across reuse of scoped symbol IDs. It does not make a stale ID safe to pass afterward: resolve the current symbol under the caller's contract.

Consequently, clients should use the hooks rather than hard-code the default columns. `extra2` can be object-size metadata for an object or a default address-fixup head for a function, but those are alternative interpretations. No accessor automatically verifies that the kind matches the chosen interpretation.

## Qualifiers have their own lifetime and keys

`cc-sym-qualified[id]` holds a symbol's qualifier set directly. `070` creates and clears this column but provides no named getter/setter pair for it; producers use `cell[] @` or `cell[] !`. The set is separate from C07's base-kind and pointer-depth word. The bounded producer interface [`cc-qualifier-bit` in 110-cc-decl.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth) assigns const=1, volatile=2, restrict=4; combined const/volatile is 3. Recording these bits does not itself enforce language rules.

Fields need qualifiers too, but they are addressed through descriptor-table records rather than symbol IDs. `cc-qualified-fields` is the head of a separate linked list. Every node occupies 24 arena bytes:

| Node offset | Stored value |
|---:|---|
| 0 | Next node, or zero at the end |
| 8 | Field-record address used as the key |
| 16 | Qualifier set |

`cc-field-set-qualified ( set record -- )` allocates and prepends a node only when set is nonzero. It writes all three cells: record and set first, old head as next, then publishes the new head. `cc-field-qualified ( record -- set )` walks from that head and returns the first matching node's set, or zero if none matches. Newest matching node wins; it does not combine older sets.

Take field-record address R and a starting head of zero. With arena pointer 3000 and sufficient room, the manual trace is:

| Operation | New node | Head | Query R |
|---|---|---:|---:|
| Set 1 for R | At 3000: `(next=0,key=R,set=1)` | 3000 | 1 |
| Set 2 for R | At 3024: `(next=3000,key=R,set=2)` | 3024 | 2 |
| Set 0 for R | No allocation or write | 3024 | 2 |
| Query a different record S | No mutation | 3024 | 0 |

The third row is the useful surprise: a zero setter is a no-op, not removal. Nor does the second row produce 3. To record combined bits, the caller must supply 3. The older node remains allocated and linked even though it no longer supplies the result for R.

C07's growing field tables expose another boundary. A field-record address can move while descriptor D stays stable. `060` calls the deferred `cc-sd-table-moved ( old new bytes -- )` before publishing its replacement table; the default drops the arguments. The native provider `cc-nqualified-move` walks all qualifier nodes and changes keys within `[old,old+bytes)` to `new+(key−old)`.

For old base T=10000, new base U=20000, and 384 copied bytes, key 10048 becomes 20048. Key 10384 is outside the half-open interval and stays unchanged. If two nodes used key 10048, both move, preserving their order and therefore newest-node behavior. The hook does not free nodes, change qualifier sets, or update arbitrary field pointers cached elsewhere. Its role is to preserve this particular association as the table moves.

A scope pop changes neither the qualifier-list head nor the arena pointer. Conversely, a moved field table does not change symbol IDs. Track these lifetimes separately: scope controls live symbol records; arena ownership controls allocated descriptors, tables, and nodes; the source owner controls borrowed name bytes.

## Practice: eight checks with different failure modes

[Graduated hints, checked paper solutions, and changed cases](../practice/08-solutions.md) are separate from these attempts. One star means a focused trace, two combine mechanisms, and three ask for diagnosis across lifetimes. These labels describe tasks, not readers. Start with an attempt; use a hint, full solution, or stop/resume point whenever helpful.

1. **C8-01 — Build the row. ★** Start with count 7 and enough capacity. Add a local named `rows` at address 5000, length 4, type 131072, payload 2. Derive the ID, store order, final count, and all ten fields. If the type column begins at 100000, locate the written type cell. Explain why payload 2 is not the variable's current value.
2. **C8-02 — Recover an outer declaration. ★★** Reproduce the nested trace from count 3 through the sibling `stars` declaration and final pop. At each pop identify live IDs, the `rows` result, and the status of saved ID 4. Then replace the sibling declaration by an empty scope. Which bytes are cleared by either pop?
3. **C8-03 — Choose the lookup policy. ★★** Live IDs 0,1,2 spell `tri` and have kinds tag, typedef, tag. Give both lookup-hook results with defaults and with the named System V policy enabled. Pop to count 2 and repeat. Explain the result of finding ID 0 and why LP64 alone is insufficient to determine the namespace policy.
4. **C8-04 — Return a place to mutate. ★★** Let `extra` start at 20000, `extra2` at 90000, and function ID be 4. Their head values are 3000 and zero. Derive both default hook results and both fetched values. Then use a matching persistent implicit-declaration record P=500000 with System V enabled. Which addresses do the hooks return, and what does an extra `@` request?
5. **C8-05 — Separate aliased metadata. ★★** Starting from a fresh row, set array length 4, associated descriptor D=8000, inner metadata A=12000, and object size 96, in that order. Derive the four reads and physical cells under legacy and LP64. Treat this as a low-level storage fixture, not a claim that a legacy declaration with all four facts is supported. Explain the result of switching profiles without migrating data.
6. **C8-06 — Follow the newest qualifier. ★★★** Starting with no nodes and arena pointer 3000, set 1 for R=10048, set 3 for S=10096, set 2 for R, then set zero for R. Derive the complete chain, allocation total, and both queries. Apply a native table move from 10000 to 20000 for 384 bytes. Which keys and query results change?
7. **C8-07 — Meet the exact boundaries. ★★** With count 8191, derive one successful append and the next attempted append. With scope depth 63, derive one successful push and the next attempted push; then separately diagnose pop at depth zero. Give error codes and identify which checks precede which mutations. Explain why additional arena capacity changes none of these limits.
8. **C8-08 — Audit a cached declaration. ★★★** A client saves an inner symbol ID, its borrowed name pointer, descriptor D, and a field-record pointer R. It later pops that scope, appends another symbol, and grows D's field table. Diagnose each saved reference separately. Does retaining arena bytes make all four safe? State what the client must establish before using each, and what a scope pop cannot repair.

### Changed cases to attempt with the solutions closed

These are the same changed cases discussed in the feedback, collected here without their answers. Use the relevant main exercise's starting state unless a change below replaces it.

- **C8-01:** Change the kind to `sk-enum`, keeping payload 2. Which interpretation changes, and which stores stay the same?
- **C8-02:** Make the sibling declaration `sk-global`. Does it survive the sibling pop? Explain the criterion without assuming a storage-allocation policy.
- **C8-03:** Keep only ID 0, a `tri` tag. Compare both hooks under both policies, then repeat with count zero.
- **C8-04:** Pop the function's scope and reuse ID 4 for a local object. Does the persistent-record provider make the cached ID safe? State what must be resolved again.
- **C8-05:** Pop the populated row's scope, then append a scalar at the same ID. Trace all five auxiliary cells and distinguish clearing pointer cells from freeing their former pointees. For a separate alias check, reverse the legacy length/descriptor writes.
- **C8-06:** Before moving the table, include keys 9999 and 10384. Which pass the numeric range test? Contrast key 10383, and separate passing that test from being a valid field-record address.
- **C8-07:** Start at symbol count 8192 with a valid active marker containing 8000. Pop, then append once. Separately, push and pop two empty scopes at count 8000.
- **C8-08:** Keep the scope active and perform no append, but grow D's table. Reassess all four references. Then contrast no growth with overwritten borrowed name bytes.

## The invariant to carry forward

Symbols form a live prefix of ten fixed columns. Append initializes a row; newest-first lookup chooses among eligible rows; pop restores a saved prefix length. A record's kind and selected profile determine its payload and metadata meanings. An ID, a stored value, a mutable cell address, a descriptor header, and a field-record pointer each have their own role and lifetime.

You now have enough machinery to explain why an outer `rows` reappears, why a reused ID can deceive a cache, and why a qualifier association needs repair when its record moves. Later chapters can consume these interfaces while teaching how declarations, objects, calls, and fixup patching are actually produced.

### Evidence and limits

Coverage includes all declarations and definitions in `070`: ten arrays, both counts and scope storage, six kinds, both qualifier-list operations, append, default and deferred lookups, every value accessor and setter, both default/deferred fixup interfaces, and checked scope push/pop. [020-cc-arena.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/020-cc-arena.fth) supplies checked capacity, failure, and arena allocation; [030](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth) supplies indexing and byte-name lookup; [060](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/060-cc-types.fth) supplies the type/profile and table-move contracts. Later sources are used only for the named interfaces identified above.

The [historical types-and-symbols chapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/24-types-and-symbols.md) is comparison material. The pinned definitions determine this chapter's capacities, storage choices, and lifetime claims. Source inspection and manually checked exercises establish neither execution results nor full C conformance. Reader learnability remains a reasoned design judgment until representative readers attempt the material.
