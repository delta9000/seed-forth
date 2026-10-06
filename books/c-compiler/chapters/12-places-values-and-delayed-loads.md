# 12. Places, values, and delayed loads

[Previous: A bounded legacy runtime](11-a-bounded-legacy-runtime.md) · [Practice help](../practice/12-solutions.md)

Suppose the triangle's current row has `r=2`, `t.stars=4`, and `w[2]=5`. All three expressions can supply an integer. Yet their producers do not all leave that integer ready in the same way. Bare `r` has already been loaded; `t.stars` and `w[2]` can still denote the places from which a later consumer will load. Why keep that distinction?

Because the same place can be read or written. Computing the address of `w[2]` does not require reading its old contents. The parser keeps enough information for the next consumer to choose. This chapter follows that information from a name, through a field or one literal subscript, to the precise point where a load is requested.

By the end, you should be able to predict what future RDI means, explain every cell of the expression metadata, preserve facts across a nested parse, and identify which profile supplies a load's width. You will also distinguish a compiler descriptor from a target address, and a grouped place from a new computed value.

## Start with supplied records, not declaration grammar

Bring [C06's current token and one-token hand-back](06-tokens-and-lookahead.md), [C07's encoded types and stable descriptors](07-types-and-stable-descriptors.md), [C08's symbol accessors](08-names-and-lexical-scope.md), and [C09–C10's instruction and address emitters](09-instructions-inside-an-executable.md). Three quick checks locate the prerequisites:

- Does a symbol's local slot 4 mean its current value is four?
- Does adding eight to an address read the eight bytes there?
- Does copying a descriptor pointer into builder metadata emit that pointer into the generated program?

All three answers are no. A slot names storage; addition calculates an address; a metadata write changes the compiler's own state. If those distinctions are secure, read through [Parentheses preserve the inner result](#parentheses-preserve-the-inner-result) before attempting C12-01 through C12-05. The typed-profile and callback reference sections can wait until you need them.

Use these supplied C08-style rows. C15 will construct the local records; C19 owns the file-scope object producer. Neither the tag declaration alone nor field lookup creates `t`.

| Name | Symbol meaning supplied to this chapter | Target storage premise |
|---|---|---|
| `r` | `sk-local`, type `int`, slot 4, no array count | Qword at `RBP−40` contains 2 |
| `w` | `sk-local`, element type `int`, base slot 3, array count 4 | Base B=`RBP−32`; qword at `B+16` contains 5 |
| `t` | `sk-global`, type `struct tri`, associated descriptor D, allocated global slot | Target base G; qword at `G+8` contains 4 |
| `tri` | `sk-struct`, value D | Builder descriptor: `rows` at offset 0, `stars` at offset 8, both `int`; total size 16 |

The symbol rows and memory contents are inputs to a paper fixture, not observed output. Assume live, correctly laid-out storage, enough builder and target-stack capacity, and no overlap between expression staging and the objects. Unmentioned array elements need no initialized value for our address calculation.

**Evidence and profile.** The chapter describes inspected [100-cc-expr.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth) at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`. Every trace and exercise answer is manually derived and unexecuted. The core uses the legacy direct-ELF profile: `cc-target-lp64=0`, `cc-target-sysv=0`, eight-byte local/field slots. Optional sections explicitly change the profile and supplied layout. No compiler build, Forth/C execution, generated-program execution, source repair, or conformance claim accompanies these traces.

## Three results, one question: value or place?

An **lvalue** identifies a place that some operations may use as a destination. This implementation has several representations for such places. A **pending dereference** means future RDI contains an address whose contents have not yet been loaded. **Materialize** is the name of the operation that asks for the value currently represented by an expression.

Keep the two machines separate throughout:

- Builder state: Forth stacks, token cells, symbol IDs, descriptors, output offsets, and the mutable `cc-last-*` cells
- Generated-program state: future RDI, RCX, RBP, target memory, and the stack changed by emitted PUSH/POP instructions

“RDI becomes 2” below abbreviates “the appended instructions are predicted to produce 2 when the generated program runs under the stated premises.” It never reports the compiler's host register contents.

### Bare `r`: load now, retain the slot

`cc-parse-local-ref` reads the type and saves it before marking the result. It obtains slot 4, marks `lv-local` with that slot, emits the local load, then republishes the type. The predicted state is:

| Stage | Future RDI | Builder kind | Slot | Type | Associated descriptor |
|---|---|---|---|---|---|
| Produce `r` | 2, read from `RBP−40` | `lv-local` | 4 | `int` | 0 |
| Ask to materialize | Still 2; no further load emitted | `lv-local` | 4 | `int` | 0 |

Slot identity survives because a later destination consumer may need to store back to `r`. Materialization has no pending dereference to discharge. It does **not** universally erase assignability. [Source: legacy scalar local producer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L852-L859).

### `t.stars`: choose an offset before loading

The global producer emits G through C10's deferred global-address mechanism. It records D in builder metadata. In this legacy struct branch it leaves a pending-address kind; the dot consumer deliberately does not materialize that base.

Dot lookup searches D for `stars` and returns offset 8. The emitter appends addition of that offset. The field producer resets the old expression facts and publishes `lv-deref`, type `int`, and associated descriptor zero because this field is a scalar integer.

| Stage | Future RDI | Builder facts that matter |
|---|---|---|
| Produce `t` | G | Pending address, D identifies `tri` |
| Select `stars` | `G+8` | `lv-deref`, no local slot, type `int`, descriptor 0 |
| Materialize field | 4 | `lv-value`, no local slot; type remains `int` |

Only the last row appends the qword load of `t.stars`. Adding the offset does not read the field. D is not added to G and is never the target object address. [Sources: global producer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L754-L792), [field selection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L1108-L1158).

### `w[2]`: preserve the base while producing an index

Use literal `2`, so precedence is not a prerequisite. The bracket helper calls a deferred expression parser whose contract is: consume the index expression, leave its following delimiter available, and append code yielding its materialized result. For this fixture the expression is one literal. C13 opens the operator cascade; C14 closes the full assignment/comma grammar.

Stack pictures run bottom-to-top from left to right. Only expression-owned target temporaries are shown; Forth return addresses are omitted from the builder picture.

| Step | Builder facts saved across the index | Future RDI | Generated temporary stack |
|---|---|---|---|
| Emit local-array LEA | Element `int`, byte-step=false | B | `[]` |
| Emit PUSH of base | Same | B | `[B]` |
| Parse literal `2` | Same, despite overwritten current metadata | 2 | `[B]` |
| Emit shift left by 3 | Same | 16 | `[B]` |
| Emit POP RCX, then ADD | Same until publication | `B+16` | `[]` |
| Require `]`; mark and publish | Current kind=`lv-deref`, type=`int` | `B+16` | `[]` |
| Materialize, if requested | Kind becomes `lv-value` | 5 | `[]` |

The builder's saved type and stride are not pushed onto the target stack. Conversely the emitted PUSH saves B for the future program, not for Forth's return stack. Two different preservation problems occur at the same recursion boundary. [Source: identifier subscript](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L373-L437).

Stop before the last row and you have a destination for a future store. The named **C14 store-consumer contract** is to preserve that destination while obtaining the right-hand value, then emit a store of the appropriate width and publish the assignment result. Its grammar and staging are not assumed here. A plain store need not first read `w[2]`.

**Stop/resume point.** Retain `r: loaded 2, slot 4`; `t.stars: address G+8`; `w[2]: address B+16`. On returning, predict which two materialization requests append a load. If the addresses and values blur, replay only one field or subscript before adding the metadata inventory.

## Nine cells form the current expression record

There is one shared mutable expression record, not an AST node for every expression. The source's older “four facts” comment does not enumerate the pinned implementation's nine cells. For compact traces, K/S/T/D denote kind, slot, type, and descriptor. The remaining five are Q/F/N/A/I below.

| Cell | Short name | Meaning and owner |
|---|---|---|
| `cc-last-lvalue-kind` | K | Interpretation of future RDI, from the five kinds below |
| `cc-last-ident-slot` | S | Local slot identity when K=`lv-local`; otherwise normally sentinel `true`, or −1 |
| `cc-last-expr-type` | T | C07 encoded base kind and pointer depth |
| `cc-last-struct-desc` | D | Associated builder descriptor: record, array node, or function signature under the relevant provider |
| `cc-last-expr-qualified` | Q | Qualifier set; const=1, volatile=2, restrict=4 |
| `cc-last-field-rec` | F | Borrowed current field-record pointer, or zero |
| `cc-last-expr-null` | N | Recognized null-constant provenance, not a runtime zero test |
| `cc-last-expr-array-len` | A | Retained undecayed array count, or zero |
| `cc-last-expr-array-inner` | I | Retained row-width metadata, or zero |

“Current” is important: recursive parsing replaces these cells. A retained arena descriptor can outlive the current expression, but the cell holding its address will not preserve an outer expression automatically. Q is metadata, not a processor flag; F is a builder record address, not a member address; N does not follow from a variable happening to contain zero.

The [five kind constants](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L96-L110) are:

| Kind | Number | Interpretation |
|---|---:|---|
| `lv-value` | 0 | Non-lvalue result; can be a scalar value or an address representing an array/function/aggregate |
| `lv-local` | 1 | Default local value already loaded, with a retained local slot |
| `lv-deref` | 2 | Pending address; legacy qword load, LP64 type-directed load |
| `lv-deref-byte` | 3 | Pending byte address in the legacy distinction |
| `lv-temporary` | 4 | Non-lvalue aggregate or materialized member state used by later providers |

Thus `lv-value` does not mean “integer rather than address,” and `lv-deref` does not universally mean “eight-byte object.” The kind describes how consumers use the representation. Type and profile describe the storage width.

### Reset first, publish second

This complete reset is the central invariant:

```forth
: cc-mark
  cc-last-lvalue-kind !
  cc-last-ident-slot !
  [lit] 0 cc-last-expr-qualified !
  [lit] 0 cc-last-field-rec !
  [lit] 0 cc-last-struct-desc !
  [lit] 0 cc-last-expr-type !
  [lit] 0 cc-last-expr-null !
  [lit] 0 cc-last-expr-array-len !
  [lit] 0 cc-last-expr-array-inner ! ;
```

[Source: `cc-mark` and wrappers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L112-L141).

`cc-mark (slot kind --)` consumes the two builder cells and clears the other seven. `cc-mark-not-lvalue` supplies sentinel/`lv-value`; `cc-mark-local-lvalue` supplies `lv-local` after its caller's slot; `cc-mark-deref` turns a byte flag into kind 3 or 2 and uses the sentinel slot. None emits a load.

A producer that writes T and then calls `cc-mark-deref` loses T. The local and index producers therefore save outer facts before the reset and publish afterward. `cc-mark-typed-value (ty desc --)` embodies the same order: reset to non-lvalue, then write D and T. `cc-mark-int-value` resets, then publishes explicit `int` only under LP64; its legacy result keeps T=0. `cc-deref-pending?` tests exactly kinds 2 and 3, not every expression carrying an address.

The later binary parser follows a related rule: merely passing a result through a level without consuming an operator does not reset it. Applying an operator produces a new result. C13 depends on that difference; otherwise bare names would lose their destination information before C14 could inspect it.

## Materialization is a specific transition

Here is the actual materializer, after the hook bindings described below:

```forth
: cc-emit-materialize
  cc-array-decay-fwd
  cc-deref-pending? if,
    cc-target-lp64 @ if,
      cc-check-static-init
      cc-last-expr-type @ cc-last-field-rec @ cc-field-load-fwd
      cc-last-expr-type @ cc-last-field-rec @ cc-field-value-type-fwd cc-last-expr-type !
    else,
      cc-last-lvalue-kind @ lv-deref-byte = if,
        cc-emit-load-byte-via-rdi
      else,
        cc-emit-load-via-rdi
      then,
    then,
    true cc-last-ident-slot !
    lv-value cc-last-lvalue-kind !
  then, ;
```

[Source: field hooks, decay, materialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L253-L291).

First call array decay, whose default emits and changes nothing. A provider may transform array metadata at this boundary; therefore “materialize is always a no-op for every array” would be too broad. Then test whether a dereference is pending. Legacy chooses byte versus qword from K. LP64 supplies T and F to the field-aware load, then asks the field-value-type hook for the loaded value's type.

After a pending load, write S=sentinel and K=`lv-value` directly. This is deliberately **not** a call to `cc-mark-not-lvalue`: T, D, and relevant other metadata must survive. A pointer field's descriptor is still needed by a following arrow even after its stored pointer has been loaded. The LP64 value-type hook can change T, as bitfield promotion requires.

A second materialization sees no pending dereference and appends no second scalar load. Default `lv-local` similarly needs no load and keeps its slot. Do not replace these cases with the slogan “materialization makes everything non-assignable.” The caller needing a fresh non-lvalue result must publish one through its own operation.

`cc-check-static-init` is a separate guard. It exits with 219 exactly when `cc-native-static-init` is true and `cc-expr-unevaluated` is false. It does not prohibit every parse in a static initializer or every use of a name. This file calls it at particular runtime-producing sites; C14 opens unevaluated `sizeof`, and the later initializer chapter owns entry into static-init mode. [Source: state and guard](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L40-L55).

## Turn a member name into an offset

`cc-find-field (name-address name-length descriptor -- offset)` owns seven scratch cells: `cc-ff-needle-addr`, `cc-ff-needle-len`, `cc-ff-desc`, and results `cc-ff-result-desc`, `cc-ff-result-type`, `cc-ff-result-array`, `cc-ff-result-record`. It searches the descriptor's published count, not its allocated capacity.

For `stars`, record 0's length four does not match five. Record 1's length five does; `bytes-eq` then checks all five bytes. On the first match the helper records the field-record address, associated descriptor, and type. It copies array length only under LP64, otherwise records zero, and returns the byte offset. `start` passes the length check but fails the byte comparison. No match ends with error 90; no successful result or rollback state is promised after that failure. [Source: complete search](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L293-L339).

The field parser adds this offset to the target base, then publishes the field result. Before lookup it requires a nonzero D (error 100), and after the operator it requires an identifier token (error 101). These checks differ from “valid descriptor with no matching field” (90).

Dot uses an existing record address. Arrow needs the stored pointer value: it calls materialize first. A legacy struct-pointer local already holds that pointer, so arrow emits no extra pointer load; a struct-pointer global or pointer-valued member may still be pending and does emit one. In either case lookup uses the builder descriptor retained across materialization.

A chain can therefore carry two different addresses in succession. Given a valid descriptor for a `next` pointer field and valid object storage, the first arrow computes the address of `next`. Materializing that field loads the next object's address. The next arrow selects a field in that next object using the propagated descriptor. C14 composes postfix chains; C15 explains how a self-referential field obtains that descriptor in the first place.

The legacy field producer marks qword pending, then republishes its field type and associated descriptor. It does not turn a legacy char member into a packed one-byte field: legacy field allocation and this direct member load use eight-byte slots. A char pointer stored in such a field still carries type information for a later byte subscript.

C07's lifetime limits still apply. The search result is overwritten by the next field lookup. The header D is stable, but a saved F can become stale when its table grows. Borrowed name bytes must remain alive and unchanged. A copied record does not copy its name's characters. Reacquire current records through the live descriptor when the table may have moved.

## Two subscript entries share an address calculation

The core trace entered `cc-parse-array-index` directly from a legacy identifier followed by `[`. A general postfix `[` can instead apply to a result such as a pointer field. C14 owns the loop that repeatedly dispatches postfix operators; this chapter owns both address-producing mechanisms.

### Identifier subscript: four base cases

The legacy identifier helper first accepts only `sk-local` or `sk-global`; other kinds fail with 91. It chooses the base from kind and positive array count:

| Symbol case | Emitted base operation | Future RDI before index staging |
|---|---|---|
| Inline local array | LEA local base slot | Address of first element |
| Local pointer | Load local slot | Pointer value stored in the local |
| Inline global array | Global-address reference | Address of first element |
| Global pointer | Global-address reference, then qword load | Pointer value stored in the global |

For an inline array, one subscript consumes the array dimension and retains the symbol's element type. For a pointer, it removes one pointer-depth level. The resulting element is byte-stepped only when its base is plain char and its depth is zero; everything else uses stride eight on this legacy path.

For example, an inline array of `char *` retains `char *` as its element type and steps eight bytes. A plain `char *` variable loses one pointer layer and steps one byte. Testing only the base kind would confuse them. `cc-char-ptr?`, used by the general postfix path, similarly requires both base `ty-char` and depth exactly one.

The helper saves element type and byte-step flag on the builder return stack before parsing the index. It pushes the base onto the generated stack, calls `cc-parse-expr-fwd`, scales, restores the base into RCX, and adds. It then requires punctuation `]` or raises 92. Finally it marks byte/qword pending and republishes the saved element type. The source's exact tail makes that order visible:

```forth
  r> cc-mark-deref
  r> cc-last-expr-type ! ;
```

[Source: the four paths and publication](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L373-L437).

This legacy helper preserves the element type, not a general aggregate-descriptor graph. Do not infer arbitrary struct-array support from its ability to emit an eight-byte step. Nor does the bracket check establish runtime bounds checking: our `w[2]` is in range because the fixture states count four and index two.

### General postfix subscript: first obtain the pointer

`cc-parse-postfix-index` first calls `cc-index-base-fwd`; its local default is a no-op. In the legacy branch it materializes the existing result to obtain the pointer value, saves its type, stages the pointer, and parses the index. Exact `char *` means stride one and byte pending; otherwise stride eight and qword pending. If the saved pointer depth is positive, publication reduces it by one. Its missing-`]` error is 99, distinct from the identifier helper's 92. [Source: general postfix subscript](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L1042-L1105).

Consider a supplied pointer field `label` whose type is `char *`, stored at target address H and containing pointer P. Before the subscript, K=`lv-deref`, RDI means H, and T=`char *`. The helper first appends a qword load, giving P. It preserves that type while literal 2 replaces current metadata, then adds two without a shift and publishes a byte-pending address `P+2`, type `char`. A later materialization reads that byte. Loading the pointer and loading the selected character are separate operations.

## Names and literals produce the starting state

A primary begins by resetting to non-lvalue, then asks `cc-parse-operand` for an operand and applies postfix operations. This initial reset matters for literals: they publish selected fields into the fresh state rather than each calling `cc-mark` again. C14 opens the entire primary/postfix loop. Here we follow its producer contract.

### Dispatch a name without losing its delimiter

`cc-parse-ident` first calls the intrinsic hook. False means continue; true means the provider consumed and produced the complete construct. Next ordinary symbol lookup returns an ID or a negative sentinel. A failed lookup can ask the unknown-name hook; a still-negative result raises 93. ID zero is a valid success, not false failure.

An enum constant is handled before any suffix peek: emit its stored integer using the immediate emitter, mark an integer value, and return. Other names peek one token:

- `(` selects a call. Legacy requires a function symbol or local function-pointer symbol; otherwise error 94. C14 owns arguments and calls
- `[` selects the special identifier-index helper only when LP64 is off
- Otherwise put the peeked token back, then dispatch by kind to function, global, or local reference; another kind raises 95

With LP64 on, `[` is also put back: the normal producer supplies the typed base and the postfix helper later consumes the bracket. This is why the LP64 and legacy paths reach the same `w[2]` spelling through different helpers. [Source: identifier dispatch and defaults](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L861-L926).

`cc-tok-punct? (code -- flag)` and `cc-tok-kw? (id -- flag)` test both kind and payload without advancing input. C06 explained why: a nonpunctuation token can retain an old punctuation number in a stale payload cell. Putting back the current token marks it for one replay; it does not rewind source bytes.

### Bare local and global producers

The earlier `r`/`t` traces covered two entries in this complete legacy reference map:

| Producer case | Future RDI | Published facts after reset |
|---|---|---|
| Plain local struct | LEA of field-zero slot | `lv-value`, D; T remains 0 in this branch |
| Local struct pointer | Loaded pointer from local slot | `lv-local`, S, D; T remains 0 in this branch |
| Local inline array | LEA of first-element slot | `lv-value`; legacy bare-array branch does not retain type/count |
| Other local scalar | Loaded qword | `lv-local`, S, saved T |
| Global struct or struct pointer | Global object/slot address | `lv-deref`, D; T remains 0 in this branch |
| Other global inline array | Global first-element address | `lv-value`; no retained type/count here |
| Other global scalar | Global slot address | `lv-deref`, saved T |

[Sources: all global and local branches](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L746-L859).

These are exact producer results, not a claim that metadata is equally rich in both profiles. The legacy special identifier-index path can consult the original symbol even though the bare-array producer would have reset its type. Whole-record value operations also need their later profile contracts; carrying an address alone grants no general assignment or arithmetic permission.

### A function name is an address-producing use

`cc-parse-func-ref (id --)` queries its descriptor hook before emitting. For a known nonzero function address, it emits MOVABS of that address. For value zero, meaning a forward prototype here, it emits an imm64 placeholder and records its operand offset in the symbol's **address-fixup** list. C10 already opened that list and its completion event; this is neither a CALL instruction nor its relative-call list.

When `cc-expr-unevaluated` is true, this unknown-address path discards the ID/patch offset instead of registering a fixup. C14 will explain why temporary expression emission can then be removed. Legacy publishes a non-lvalue with no retained descriptor. LP64 publishes `ty-func` at pointer depth one plus the queried descriptor. [Source: function reference](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L721-L744).

### Numbers, characters, and strings

`cc-parse-operand` reads one token and first offers it to `cc-value-literal-fwd`. Its default returns false. A successful replacement must publish the complete typed result before returning true.

For a number, LP64 invokes C07's `cc-integer-literal-type`; both profiles record whether the literal value is zero in N. C10's `cc-emit-mov-rdi-int` chooses the supported immediate form. A character token similarly records null provenance, explicitly publishes `int` under LP64, and uses the imm32 emitter. None performs a target memory load. A variable whose runtime value is zero does not thereby receive N=true.

A string producer emits or places decoded bytes and their address, then the operand publishes `char *`. Legacy emits a jump over one decoded string plus NUL and MOVABS of its address. The native default concatenates adjacent string tokens: remove each temporary terminator, read the next token, put back the first nonstring, emit one final NUL, record the decoded extent including that NUL in A, patch the jump, and emit the address. Thus `"A\0" "B"` occupies four decoded bytes, not two visible letters. C10 owns the detailed byte placement and escape decoding. [Sources: string producers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L668-L719), [operand dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L938-L966).

An identifier delegates to the name producer. An opening parenthesis asks the cast probe first, then falls back to grouping. An unrecognized operand start raises 97. Cast recognition is a named type-query interface supplied by 110 and opened in C14; it is not an assumption that every parenthesis begins a cast.

## Parentheses preserve the inner result

The entire grouping helper is short:

```forth
: cc-parse-paren
  cc-target-lp64 @ if, cc-parse-comma-fwd else, cc-parse-assign-fwd then,
  cc-next-token-keep
  [char] ) cc-tok-punct? 0= if,
    [lit] 96 cc-die
  then, ;
```

[Source: preserving grouping](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L928-L936).

It calls an inner grammar that does not mandate final materialization, then consumes the required closing parenthesis. Legacy uses assignment grammar; LP64 uses comma grammar. Those entry points parse lower-precedence forms too, including our one-name or one-field examples. Their full grammar is C13/C14's work.

For `(r)`, the inner producer's loaded value and slot survive. For `(t.stars)`, the pending field address survives. The public `cc-parse-expr` is different: after its grammar it calls `cc-emit-materialize`. Substituting that public entry inside grouping would eagerly load the pending field and lose its destination representation. The local case is a useful countercheck: even that eager call would ordinarily leave `lv-local` unchanged, so testing only `(r)` would conceal the distinction.

The deferred entry points solve definition order and recursion, not phase confusion. Their small contracts are:

- `cc-parse-expr-fwd ( -- )` binds to `cc-parse-expr`: parse and finally materialize, leaving the following delimiter available
- `cc-parse-comma-fwd`, `cc-parse-assign-fwd`, and `cc-parse-unary-fwd` bind to the corresponding same-file parsers, each with `( -- )` and result publication in the current expression record; they do not promise the public entry's final materialization
- `cc-parse-const-fwd ( -- value)` calls deferred `cc-parse-const`, initially bound to `cc-parse-const-default`; its result is a builder cell, not future RDI
- `cc-try-cast-fwd ( -- handled?)` binds in 110 to `cc-try-cast`: after an opening parenthesis, a failed type-start probe puts its candidate token back; success consumes the cast and publishes its result
- `cc-sizeof-type-start-fwd ( -- flag)` binds in 110 to `cc-type-start?`, testing the current token; `cc-sizeof-type-fwd ( -- ty desc)` binds to `cc-native-sizeof-type`, parsing a type name and supplying its descriptor

[Sources: same-file closure](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L2602-L2634), [cast provider](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L642-L670), [type-query bindings](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L805-L808). This chapter requires only the stated index/grouping contracts. C13 next opens precedence, and C14 supplies the complete grammar, stores, casts, and evaluator closure.

## Optional profile depth: type-directed places

Read this section when a four-byte int, an inline matrix, or a System V local seems inconsistent with the legacy trace. Choose the profile before constructing symbols/descriptors; changing a flag does not migrate existing records.

### Sizes and typed publication

`cc-expr-symbol-desc (id -- desc)` returns the symbol's associated descriptor only for bases struct, array, or function, otherwise zero. `cc-expr-type-size (ty desc -- bytes)` uses array-node size for a plain array, struct total size for a plain struct with nonzero descriptor, and `ty-size` for pointers and other cases. It does not make descriptor zero a completed record.

`cc-expr-pointee-type` removes one pointer layer if present. `cc-expr-pointee-size` then sizes that result, except that LP64 `void *` gets a one-byte arithmetic step. That exception is separate from `ty-size(void)=0`; do not change a `sizeof` answer to explain pointer stepping. `cc-unary-type` keeps pointer types, promotes a nonpointer smaller than four bytes to `int`, and otherwise keeps its input. These helpers manipulate builder type words, not target values. [Source: type helpers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L143-L185).

`cc-mark-typed-deref (ty desc --)` has three address-representation exceptions before its scalar case:

1. Plain array: take count/inner from its descriptor, publish an element-pointer-shaped typed value plus element descriptor, then restore A/I
2. Plain function: publish a typed value retaining its address
3. Plain struct with descriptor: publish a typed value representing the complete object's address

Only the remaining case creates a pending byte/nonbyte dereference according to `ty-size`, then republishes T/D. Loading the first word of a plain aggregate would not produce the aggregate value representation. [Source: typed dereference marking](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L224-L240).

LP64 global production preserves symbol qualifiers and inner shape across publication. A positive inline count yields an address-like typed value with one added pointer layer and A=count; otherwise it uses typed-dereference marking. LP64 local production similarly uses LEA for inline arrays and plain aggregates. Scalar locals take the load hook, then the caller republishes T/D/Q/I. This last division of responsibility is consequential.

### LP64 is not the System V local-load switch

With LP64 on and the original `cc-native-local-load-fwd` binding, `cc-emit-load-local-typed (slot ty --)` emits LEA then a type-directed load; K remains `lv-local`. An int occupies four bytes even though its frame coordinate still uses eight-byte slot units.

With 121's provider loaded **and `cc-target-sysv` true**, the hook is:

```forth
: cc-sysv-local-load ( slot type -- )
  cc-target-sysv @ if,
    drop cc-emit-lea-rdi-local
    true cc-last-ident-slot ! lv-deref cc-last-lvalue-kind !
  else, cc-emit-load-local-typed then, ;
```

[Sources: default typed local load](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L1340-L1347), [System V replacement](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L285-L290).

The producer now leaves the local's address pending and clears its special slot identity. Later materialization supplies the load. If int storage at L contains −3, legacy predicts a qword read at production; default LP64 predicts a signed four-byte read at production; System V predicts LEA at production and that signed four-byte read at materialization. All yield −3 under independently suitable storage premises, but they read at different times and retain different destination representations. Merely loading 121 while its target flag is zero takes the fallback branch.

The default typed loads choose one-, two-, four-, or eight-byte operations and the appropriate signed/unsigned extension through C09's emitter contracts. Stores choose the written width; result conversion is requested separately rather than supplied by the store itself. In this profile K=`lv-deref` can therefore describe a four-byte int. Neither its name nor the eight-byte Forth cell width chooses object width.

### Typed subscripts, qualification, and temporary members

The LP64 postfix-index path saves Q on the builder return stack. If A is zero it materializes the base; an inline matrix with A nonzero already denotes storage and skips that conversion. It saves T/D on the builder data stack, I on the return stack, and the base on the generated stack before recursively parsing the index. Afterward it calls the integer-use hook on the index type.

Stride is pointee size, multiplied by saved I when nonzero. `cc-emit-scale-rdi` emits nothing for one, a specialized shift for eight, otherwise IMUL by an immediate. Its RCX counterpart emits nothing for one and IMUL otherwise. Restoring the base and adding gives the selected address. After `]` validation, nonzero I publishes the saved typed value and turns I into the new A; otherwise it reduces pointer depth and invokes typed-dereference marking. Finally it restores Q. The index's own metadata cannot replace the outer element shape. [Sources: scalers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L242-L251), [typed index algorithm](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L1057-L1084).

For a supplied LP64 inline int matrix at M, represented with A=4 and I=3, literal index 2 advances by `2*(4*3)=24` bytes and leaves a row with A=3. A subsequent scalar index would step four. This is a local algorithm example; the full ranked-array node producer and its legality rules belong to C23/G03.

Native field selection saves whether dot began on `lv-temporary`. It performs the same descriptor lookup and offset addition, then publishes either a typed inline-array address with A/I or a typed dereference. It records F and combines inherited Q with the selected field's qualifiers using bitwise OR. For a member of a temporary record, a nonarray member is materialized and then marked `lv-temporary`; an array member retains its inline-storage address/extent and also gets that kind. Address representation therefore does not grant assignability to a temporary member. Full aggregate production/transport belongs to G15; this local consumer behavior is in 100.

System V decay in `cc-sysv-array-decay` qualifies a ranked array's node when applicable. For retained nonzero inner width it constructs a qualified row node, publishes an array-pointer typed value, and restores Q. Its body is gated by System V, not merely LP64. `cc-sysv-index-base` rejects a nonpointer base; `cc-sysv-member-base` checks struct base and dot/arrow depth/shape. Both local defaults do nothing, so those legality checks must not be attributed to the unbound core. [Sources: decay](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L162-L177), [base policies](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L221-L246).

## Reference: callback contracts and their actual defaults

A hook is a callable contract with a replaceable provider. It is not permission to assume an unimplemented feature. The following catalog accounts for this chapter's seams, including operations whose parsing callers arrive in C13/C14. `--` stack effects describe builder cells; register effects describe appended target instructions. Load order selects the installed provider, and its own predicate selects behavior.

### Place, name, and literal seams

| Hook | Initial contract and binding in 100 | Named later provider and boundary |
|---|---|---|
| `cc-field-load-fwd` | `(ty rec --)`; default drops rec and calls `cc-emit-load-typed-via-rdi`, reading address RDI | `cc-bf-load` in 129 selects bitfield extraction when its record qualifies; `cc-ag-field-load` in 131 leaves System V plain aggregate addresses intact and otherwise delegates to bitfield load; G14/G15 |
| `cc-field-store-fwd` | `(ty rec --)`; default drops rec and calls `cc-emit-store-typed-via-rcx`, value RDI/address RCX | `cc-bf-store` in 129 preserves surrounding bits for a recognized bitfield, otherwise default; G14; C14 supplies the store caller |
| `cc-field-value-type-fwd` | `(ty rec -- ty)`; default drops rec, retaining type | `cc-bf-value-type` supplies recognized bitfield promotion; G14 |
| `cc-field-use-fwd` | `(rec --)`; default drops it, no emitted operation | `cc-bf-use` rejects a recognized bitfield in callers that forbid that use; G14/C14 |
| `cc-array-decay-fwd` | `( -- )`; `cc-array-decay-default` is empty | `cc-sysv-array-decay`, System V metadata conversion described above; G03 |
| `cc-index-base-fwd`, `cc-member-base-fwd` | Empty `cc-postfix-base-default`; index has `( -- )`, member preserves `(op -- op)` | `cc-sysv-index-base`/`cc-sysv-member-base`, gated by System V; G03 |
| `cc-native-local-load-fwd` | `(slot ty --)`; `cc-emit-load-local-typed`; caller republishes type/descriptor | `cc-sysv-local-load` may also change K/S; G03/G04 |
| `cc-native-string-fwd` | `( -- )`, current token string; `cc-parse-native-string-literal`; emits address and A, returns first nonstring pending | `cc-sysv-object-string` in 123 uses object placement exactly when object mode AND not unevaluated, otherwise native inline fallback; G02 |
| `cc-native-intrinsic-fwd` | `( -- handled?)`; `cc-native-intrinsic-noop` returns zero | `cc-va-intrinsic` in 126 handles named variadic builtins only with System V enabled; owns complete construct when true; G12 |
| `cc-native-unknown-ident-fwd` | `( -- id-or-negative)`; `cc-native-unknown-ident-default` returns `true` (−1), not a success flag | `cc-sysv-unknown-ident` in 121 can create an implicit function record only with System V on and a following `(`; ordinary missing names remain failures; G03 |
| `cc-native-function-desc-fwd` | `(id -- desc)`; default `cc-native-function-desc` drops ID and returns zero | `cc-sysv-function-desc` obtains a checked signature with System V on, otherwise default. In 123, `cc-sysv-object-function-desc` rebinds the hook: object mode AND not unevaluated registers an absolute function-address relocation before delegating. This is not a universally query-only hook; G02/G03/G04 |
| `cc-native-call-result-fwd` | `(id -- ty desc)`; default uses function symbol type or int for a nonfunction, plus `cc-expr-symbol-desc` | `cc-sysv-call-result` queries signature return type/descriptor with System V on; G03/G04 |
| `cc-native-call-qualified-fwd` | `(id -- qualified)`; default drops ID and returns zero | `cc-sysv-call-qualified` queries signature qualifiers with System V on; G03/G04 |

The call dispatch saves return qualifiers, type, and descriptor before nested arguments overwrite current expression state, then republishes after the call. This names the caller boundary without requiring argument parsing here. The field defaults do not themselves enforce every qualifier or C legality rule. In 129, `cc-bf?` recognizes a bitfield exactly when System V is enabled, the record pointer is nonzero, and its recorded bit width is nonzero; otherwise these providers take their default paths.

Provider sources: [123 function-address relocation wrapper](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L96-L101), [129 field operations](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/129-cc-bitfield.fth#L99-L147), [131 aggregate field load](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/131-cc-aggregate-abi.fth#L60-L72), [123 object strings](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L113-L129), [126 intrinsics](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/126-cc-varargs.fth#L213-L227), [121 name and signature providers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L895-L941).

### Typed value operations declared beside the metadata

These [initial bindings](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L187-L222) are independent contracts, not one generic “native operation.”

| Hook | Exact initial behavior | State or later responsibility |
|---|---|---|
| `cc-value-literal-fwd` | `cc-value-literal-default ( -- handled?)` returns 0 | `cc-f64-literal` in 127 handles current `tk-float` only under System V, publishes double/descriptor zero; 128 supplies numerical conversion, G10/G11 |
| `cc-value-test-fwd` | `( -- )`, `cc-emit-test-rdi` | Emits flags from current scalar; C13 tests conditions |
| `cc-value-not-fwd` | `( -- )`, `cc-emit-not-zero-flag` | Emits logical-not result; C14 caller publishes its result metadata |
| `cc-value-negate-fwd` | `( -- )`, `cc-emit-neg-rdi` | Emits integer negation; C14 |
| `cc-value-complement-fwd` | `( -- )`, `cc-emit-not-rdi` | Emits bitwise complement; C14 |
| `cc-value-plus-fwd` | Empty `cc-value-plus-default ( -- )` | No opcode; later provider checks current value's shape; C14 |
| `cc-value-ternary-fwd` | Empty `cc-value-ternary-noop ( -- )` | Scalar join policy uses saved/common expression state; C13/C14 |
| `cc-value-ternary-split-fwd` | `cc-value-ternary-split-default ( -- flag)` returns 0 | `cc-sysv-ternary-split` returns the System V flag; selects separate arm-conversion paths |
| `cc-aggregate-ternary-fwd` | Default pushes false, leaving saved left facts and fixup untouched | Successful provider consumes `(left-type left-desc inner null qualified true-fixup)`, patches join, publishes result, and returns true; G15 |
| `cc-value-integer-use-fwd` | `cc-value-integer-use-default (ty --)` drops type | Pure acceptance check, no load; used after index parsing |
| `cc-value-shape-fwd` | `cc-value-shape-default (source desc destination desc --)` drops all four | Pure shape check before assignment/conversion, C14 |
| `cc-value-init-fwd` | `cc-value-init-default (source destination --)` drops both | Separate initializer seam, not invoked for every expression |

127's `cc-fp-test/not/negate/complement/integer-use` providers select floating behavior using their System V nonpointer-float predicates and otherwise keep the integer path; `cc-fp-ternary` remains empty. `cc-fp-initialize` converts when either type is a supported floating type. 131 wraps computing uses with aggregate/opaque-scalar rejection through `cc-ag-test/not/negate/complement/integer-use`, and binds `cc-ag-plus`, `cc-ag-initialize`, and `cc-ag-ternary`. Its aggregate predicate is a nonpointer struct with System V enabled. These providers distinguish transporting a record's address from computing with it. G10/G15 open their algorithms; C13/C14 open the current callers.

For shape, 121 installs `cc-sysv-value-shape`, gated by System V and using current null provenance where required. 131 installs `cc-ld-value-shape`, adding long-double mismatch policy before delegating. These pure checks should not be described as emitting conversions. Likewise a false handled flag means “continue with the ordinary path,” whereas a no-op policy hook has no handled result to test.

Provider sources: [127 literal and floating type predicates](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/127-cc-binary64.fth#L7-L69), [127 value operations](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/127-cc-binary64.fth#L164-L250), [121 shape policy](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L734-L747), [131 initializer policy](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/131-cc-aggregate-abi.fth#L379-L390), [131 value/conditional providers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/131-cc-aggregate-abi.fth#L418-L459), [131 shape wrapper](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/131-cc-aggregate-abi.fth#L501-L507).

## Practice: explain the first changed fact

Eight exercises separate representation, publication, lookup, staging, consumer choice, literal production, profile selection, and ownership. Use the tables as references; memorizing numeric kind IDs is not the objective. [Graduated hints and checked manual solutions](../practice/12-solutions.md) are separate. A short attempt can be a state table, annotated source, or spoken explanation. If a prerequisite blocks you, use the matching hint or worked comparison and then try the changed case; there is no required period of struggling before opening help.

1. **C12-01 — Label the three results.** Use the opening legacy fixture. For bare `r`, `t.stars`, and `w[2]`, give future RDI, K/S/T/D before and after one materialization. Then request materialization again. Identify every target memory read and distinguish it from address arithmetic
2. **C12-02 — Repair publication order on paper.** A proposed producer writes D=8000, T=`int *`, Q=1, then calls `cc-mark-deref` with false. Derive all nine cells afterward. Describe the correct ordering if it must publish those facts, and contrast materialization with `cc-mark-not-lvalue`
3. **C12-03 — Follow a field without mixing addresses.** Descriptor D has legacy `rows`/`stars` at offsets 0/8, count two, capacity eight; target base G=12000. Trace searches for `stars` and `start`, including side results and field address. Contrast descriptor zero with a valid descriptor of count zero
4. **C12-04 — Preserve two different things.** Trace legacy `w[2]` from `[` through publication, showing builder saved facts and generated temporary stack separately. Repeat for a valid local `char *p` containing P, selecting `p[2]`. State element type, stride, pending kind, and memory read timing
5. **C12-05 — Choose the consumer.** Compare `(r)` and `(t.stars)` using grouping's actual helper. Explain what an eager public-expression call inside grouping would change. Stop at the pending field address and describe the information a future plain store of supplied value 9 must preserve, without deriving assignment grammar
6. **C12-06 — Produce a value without an object load.** Starting from fresh primary state each time, derive legacy metadata for number `0`, character `'A'`, a supplied enum constant of value 0, and a known function name. For an unresolved prototype, identify the emitted placeholder/list and the unevaluated difference. Separately compare LP64 native adjacent strings `"A\0" "B"` with legacy one-token string production
7. **C12-07 — Name the actual profile.** Use an independent scalar `int x` at valid slot address L. Compare legacy, LP64 with the default local hook, and LP64 with the System V provider enabled: producer instructions, K/S, materialization, and load width. Then trace the LP64 matrix subscript with A=4, I=3, base M, element int, and index 2
8. **C12-08 — Check owners and policy boundaries.** A caller retains symbol ID s, descriptor D, field pointer F, a borrowed field-name span, and current Q/F metadata. Explain what survives a nested expression parse, a scope pop followed by ID reuse, and growth of D's field table. Identify which field hooks consume `(ty rec)`, which one returns a type, and which checks a forbidden use without loading

### Changed prompts, with the answers closed

Use fresh state and the matching exercise's premises unless changed here. These are additional attempts, not compiler-editing or execution instructions.

- **C12-01:** Set `r=0`, keeping its symbol unchanged. Does it acquire null-constant provenance? Replace `t.stars` by `t.rows`, whose qword value is stipulated as 7
- **C12-02:** Begin with an unrelated pending char field carrying nonzero F/A/I. Publish a fresh typed integer value with descriptor zero through `cc-mark-typed-value`. Which facts remain?
- **C12-03:** Change to a supplied LP64 descriptor with the same names but offsets 0/4, size eight, and no array fields. Search for `stars`; keep target base 12000
- **C12-04:** Replace `p` by an inline local array of `char *`, and assume the selected pointer addresses a readable character string. Trace the first `[2]`, then the general postfix `[1]`
- **C12-05:** Supply a pending field that stores a valid struct pointer P with descriptor D. Compare grouping it with materializing it, then state what a following arrow needs to retain
- **C12-06:** Change the numeric token to LP64 `2147483648LL`; compare its type/provenance with the legacy zero case. In the unresolved function fixture, turn unevaluated off after considering it on
- **C12-07:** Keep 121's local-load provider installed but turn System V off while leaving LP64 on. Separately change the matrix's element type from int to short, keeping dimensions and index
- **C12-08:** Keep the scope active and the descriptor table unchanged, but overwrite the owning name bytes in a paper thought experiment. Separately give a temporary record a scalar int field under LP64: predict its member's final kind and load behavior

## Carry a representation, then let its consumer decide

The opening question now has a precise answer. A producer appends instructions and publishes metadata describing their future result. A field or subscript may leave a destination address; a default local may already hold a loaded value while retaining its slot. Materialization runs decay, loads only a pending dereference, and preserves the facts the loaded value still needs. Grouping preserves the inner representation until a real consumer acts.

C13 can now teach precedence without hiding when an operand must be loaded. C14 will join these producers with postfix/unary operations, calls, updates, assignments, and constant evaluation; C15 will construct the local/type records supplied here. The present evidence establishes source-backed contracts and bounded manual predictions. It does not establish executed behavior or demonstrated learner performance.
