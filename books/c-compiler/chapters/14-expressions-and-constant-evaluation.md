# 14. Expressions, stores, and values computed now

For `a = b += 3`, the parser must remember where `a` lives while it temporarily becomes busy with `b`. For `1 || (1 / 0)` in an expanded preprocessing condition, it must read the division without performing it. Both problems involve recursion, but their saved values belong to different machines.

This chapter closes the expression parser. You will follow a complete expression from its first operand through postfix operations, unary operators, assignments, and its final consumer. Then you will follow the constant evaluator, which computes a builder cell instead of appending runtime arithmetic. The central question is always: **what must survive the next recursive call, and who owns it?**

**Edition and evidence.** This account uses [`100-cc-expr.fth`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth) and the type-query/cast handshake in [`110-cc-decl.fth`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L573-L670), at revision `bbcc1732152af2d884737272eed870d2410ffe8e`. Source descriptions are inspected implementation; every numerical trace is a **manual prediction**, not an executed result. No compiler build, Forth example, C example, generated program, or bootstrap was run for this chapter. Target callbacks are bounded interfaces, not claims of full C or ABI conformance.

## Choose a route and recover the state

The short route is **One operand, many suffixes**, **Preserve the outer destination**, **Finish the row**, and **Compute a constant now**, followed by C14-04 and C14-09. Read calls, unary parsing, and the explicitly marked depth sections when you want the complete source closure. You can stop after either full trace: the saved state and next question are stated there.

Prerequisites are [C12's places and delayed loads](12-places-values-and-delayed-loads.md), [C13's precedence and branches](13-precedence-and-short-circuit.md), [C06's token replay](06-tokens-and-lookahead.md), and [C10's call/address fixups](10-calls-literals-and-deferred-addresses.md). Before continuing, try these checks:

1. If `*p` leaves a pending address P, does grouping it as `(*p)` require a load?
2. Which stack preserves a table-row address while parsing a runtime binary RHS? Which stack will preserve the generated left operand?
3. Does putting back the current token move the byte cursor backward?
4. Does invoking an emitter's execution token compute the emitted operation's result now?

[Entry feedback and all exercise help](../practice/14-solutions.md) are separate. If one distinction is uncertain, repair that distinction with one small state drawing. There is no need to restart every earlier chapter.

Use two columns throughout:

- **Builder:** Forth cells/stacks, token state, symbols, descriptors, expression metadata, output positions, and fixup records
- **Generated program:** future RDI/RCX/RAX values, target memory, and the runtime stack manipulated by appended instructions

Stack pictures put the top at the right. They show only expression-owned saved facts, omitting Forth call-return machinery and generated function frames. Addresses P, A, and B are symbolic; arithmetic examples assume valid storage and bounded operands. Byte counts are decimal.

C12's expression record has **nine cells**, not four: kind, local slot, type, descriptor, qualifiers, field-record pointer, null provenance, array length, and inner row width. Its five kinds are `lv-value`, `lv-local`, `lv-deref`, `lv-deref-byte`, and `lv-temporary`. `cc-mark` writes kind/slot and clears the other seven; a producer republishes the facts it preserves afterward. A descriptor is builder metadata, not an object's generated address.

A pending dereference contains a destination address until a consumer requests its value. A legacy `lv-local` already contains a loaded value and retains its slot. Under System V, the local-load provider can instead leave a pending address. Materialization calls array decay, loads a pending scalar through the field/type hook, and changes that pending kind to value. It does not automatically erase every local identity. Recursive parsing overwrites the shared record; it does not preserve a tree of earlier records for you.

## One operand, many suffixes

A **primary** begins with a literal, name, cast, or grouped expression, then consumes zero or more postfix operations. A postfix operation applies to the expression already built on its left. That permits a chain such as `head->s[1]++` without a separate parser for every possible chain.

Here is the complete controlling loop's entry point:

```forth
: cc-parse-primary
  cc-mark-not-lvalue                              \ default: not an lvalue
  cc-parse-operand cc-parse-postfix-ops ;
```

[`cc-parse-operand`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L947-L975) reads one token. A literal provider gets first refusal: its default returns false, while a handled result must have consumed/published its literal. Otherwise numbers use the immediate-width emitter, characters use their decoded integer value, strings use C12's literal producer, and names use C08/C12's lookup dispatch. Numeric and character zero record null provenance; that is a fact about the parsed expression, not a runtime zero test. LP64 numbers also receive their checked integer type. An opening parenthesis first probes for a cast, then falls back to grouping. An unrecognized start reaches error 97.

The [postfix loop](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1182-L1218) reads another token and dispatches `++`/`--`, `[`, or `.`/`->`. With LP64 enabled it also recognizes `(` as an indirect call on the current expression. Each operation updates the same expression record; the next suffix consumes that updated result. The first non-postfix token is put back. There is one default reset at the beginning of the primary, not an unconditional reset between suffixes.

**Paper chain, legacy profile.** Supply a valid local `head`, whose value H points to a record. Its descriptor says field `s` is a `char *` stored at offset 8. Memory at H+8 contains Q, and byte Q+1 contains 65. No declaration parsing is needed yet; these are the supplied C08 rows and live-storage premises.

| Completed source | Future RDI meaning | Builder facts needed next |
|---|---|---|
| `head` | H, already loaded local pointer | Local identity, pointer type, record descriptor |
| `head->s` | Address H+8 of the pointer field | Pending dereference, `char *` type |
| `head->s[1]` | Address Q+1 of one character | Pending byte dereference, `char` type |
| `head->s[1]++` | Old character value 65 | Non-lvalue result retaining `char` type |

Arrow materializes the base pointer if needed, looks up the field, and adds its offset. Indexing then materializes the *pointer field*, obtaining Q; it saves that base while parsing the index. Its pre-index `char *` type selects stride one. The update loads the old byte, increments that byte in memory, and leaves the old value as the expression result. Predicted byte Q+1 becomes 66. Adding an offset was never itself a load.

C12 opens field lookup and indexing in detail. The composition rule adds an important lifetime: save pre-index type, descriptor/row information, and qualification before the index's recursive expression overwrites the shared metadata. In LP64, an inline matrix already denotes storage, so indexing avoids manufacturing a decayed pointer first; row width multiplies element stride, and indexing a row republishes the remaining array extent. Field selection carries the selected field record into typed loads/stores. A scalar member selected from an aggregate temporary remains a non-lvalue temporary. These are [the actual index/member callers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1064-L1180), not extra syntax in the suffix loop.

Grouping uses assignment grammar in legacy mode and comma grammar in LP64, then requires `)`, error 96 otherwise. It deliberately avoids public `cc-parse-expr`, whose final materialization could consume the pending address. Consequently `(*p)++` can still update the pointee, and `(a)=7` can still retain a legacy local slot.

## Calls have argument boundaries

A call parser enters with `(` already consumed. The identifier dispatcher distinguishes a named call from a plain name; LP64's postfix loop additionally permits a call through a computed expression. The distinction matters before any ABI choices.

Assume f is a valid callee and a/b are valid scalar locals. For `f(a=2, b+=3)`, the comma separates two arguments. It must not disappear into a comma-expression parser. The [legacy call path](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L586-L672) calls public expression parsing, but legacy expressions have no comma operator. The LP64 argument parser explicitly calls assignment parsing and then materializes. Under LP64, `f((a=2,b+=3),4)` instead has two arguments because parentheses provide a nested comma-expression boundary. Parentheses are doing grammar work, not merely decoration.

Legacy call parsing performs these steps:

1. Start an argument count at zero. If the next token is `)`, retain zero
2. Otherwise put it back, parse/materialize an argument, append a push of RDI, and increment the count
3. Continue after commas; require the final `)`, with error 121 for a bad delimiter
4. Reject counts above six with error 122
5. Emit pops for indices count−1 down to zero: indices 0–5 map to RDI, RSI, RDX, RCX, R8, and R9
6. Emit the call, then copy returned RAX into expression-result RDI

For independently supplied argument values 2, 7, and 4, staging is `[2,7,4]`. Pops go into RDX=4, RSI=7, then RDI=2. The reverse pop order reverses the stack effect, not the source's left-to-right parsing order. The index helper assumes its caller has enforced 0–5; its last case is R9, not a general unlimited-register allocator.

A defined `sk-func` supplies its virtual target address. The relative displacement is target minus the address after the five-byte call. A prototype with address zero gets a rel32 placeholder attached to that symbol's call-fixup list. C10 explains the list; C18's function-definition consumer supplies the target and walks it. A local function-pointer symbol takes the indirect RAX call path. Other legacy callees are rejected by the identifier or call checks (94/123). A function address's imm64 fixup list is a different list from a call's rel32 list.

The restricted register sequence does not establish general System V call safety. In particular, balanced argument pushes/pops alone do not settle nested-call alignment or whole-frame accounting. Those belong to C18 and G04. LP64's default is a different, private all-stack convention, opened in the depth section below.

## Unary position decides what an operator asks for

C13's multiplication parser sees `*` *after* a left operand. Here `cc-parse-unary` sees it *before* an operand, so it requests dereference. Likewise unary `&` requests an address rather than combining integer bits. Unary recursion handles `**p` by completing the inner pointer-producing expression before the outer dereference.

For `*p`, parse `p` recursively and materialize it, obtaining the pointer value P. Then mark P as a pending pointee address. The consumer decides whether to load or store. For `**p`, the inner pending address must be materialized to obtain the pointer used by the outer `*`. One deferred load has become necessary; the final pointee load is still deferred. Legacy `char *` selects byte width; other legacy dereferences use qword width. LP64 derives the pointee type and descriptor, so `lv-deref` does not imply eight bytes.

Legacy address-of accepts a simple local identifier, resolves its slot, and emits LEA. Missing identifier, unknown name, and nonlocal destination reach 114, 115, and 116. This path does not recursively parse `&*p` or `&w[i]`, nor does it promise the richer native type publication. LP64's recursive address path is different; see the depth section before transferring an example across profiles.

Unary minus, logical not, and complement recursively parse and materialize their operands. Legacy minus/complement emit NEG/NOT and publish a plain value. Logical not uses the value-not hook and publishes an integer result. LP64 minus/complement promote small scalar types, invoke their operation hooks, convert to the promoted type, and publish typed values. LP64 unary plus materializes, runs its shape-policy hook, promotes, and converts, despite needing no arithmetic opcode. **Legacy runtime unary plus is not recognized here.** Constant unary plus is recognized later; the two grammars must not be copied over one another.

### Updates return either the old or the new value

From independent initial state `b=4`:

- `b++` leaves 4 and stores 5
- `++b` stores 5 and leaves 5

In the [legacy postfix path](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1035-L1062), a local's old value is already in RDI, so an in-place slot increment preserves it. A pending address moves into RCX; a byte/qword load obtains the old value and the matching memory update changes storage. The result is marked non-lvalue, then its operand type is restored. `b++--` therefore reaches the second suffix without an assignable result and fails with 98. Valid fields and indexed elements are not categorically excluded.

The [prefix path](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1402-L1460) has a plain-local fast path. `cc-name-alone?` marks the full lexer state, peeks for a suffix/call, then resets. Thus `--b->n` is not misread as decrementing the pointer variable b. A plain local is bumped then loaded; otherwise the parser puts the candidate back, recursively parses a unary operand, requires a pending address (113 otherwise), bumps through RCX, and loads the new value. Both legacy update forms change storage by one, even for a pointer. Native typed updates use pointee stride instead.

## The parenthesis handshake: type or expression?

After `(`, a parser cannot decide from punctuation alone whether `(char)321` is a cast or `(a)` is grouping. It asks a type-start query supplied by the declaration file, without requiring declarations themselves to have been taught.

The contract is concrete. [`cc-type-start?`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L583-L624) examines the current token. In legacy mode it recognizes supported type keywords, qualifiers, `struct`, `enum`, and identifiers whose symbol kind is typedef. Under LP64 it delegates to `cc-native-type-start-fwd`. `cc-parse-type-name` consumes a type name and leaves the following token pending. It returns the encoded type and publishes `cc-cast-desc`; native providers additionally publish qualification and array-shape facts through their named handoff cells.

The legacy type-name algorithm clears `cc-cast-desc`, skips initial qualifiers, and chooses a base. A struct uses soft tag lookup to publish its descriptor; enum uses the integer base and optional tag; a typedef supplies base and existing pointer depth. Keyword combinations start from int, with char/void selecting those bases. Qualifiers are skipped and additional stars are counted, including qualifiers after stars; the encoded type combines base and total pointer depth. This is the actual restricted type-name grammar. Full native declarators and qualification records belong to C23/G03.

[`cc-try-cast`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L626-L670) consumes one candidate after `(`. If it is not a type start, it puts that token back and returns false; grouping resumes from it. On success:

1. Parse the destination type and save it on the builder return stack
2. Reject an LP64 array type-name with 238 and require `)`
3. Save destination qualification and descriptor above the type
4. Parse a unary operand, which may itself contain a cast, and materialize it
5. Recover the outer destination facts, perform conversion/policy work, then publish the outer result

For legacy `(char)(int)321`, the inner cast must not become the outer destination. Inner int leaves the value bits alone. The outer plain-char cast emits zero extension of the low byte; the predicted value is 65. Both cast results are non-lvalues. The return-stack snapshots exist because recursive casts share `cc-cast-desc` and all nine current-expression cells.

The cast path separates three hooks. Under LP64, `cc-cast-types-fwd` checks source/destination policy without emitting conversion and `cc-cast-value-fwd` performs conversion. After either profile’s conversion, `cc-cast-null-fwd` decides whether source type, destination type, previous null provenance, and *saved destination* qualifiers justify retained null provenance. Defaults respectively discard the type pair, call `cc-emit-convert-value`, and return false. A cast to void is not a special emitted “discard” instruction in this scalar convention. Later function-pointer, aggregate, and long-double policies have named providers in G03/G09/G15.

### `sizeof`: a query with two implementation routes

Legacy [`cc-parse-sizeof`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1311-L1400) requires parentheses and dispatches a small syntax set:

| Form | Legacy source algorithm |
|---|---|
| `int`, `char`, `void` | Set byte count to 8, 1, or 0 |
| `struct TAG` | Require a known struct tag and use descriptor total size |
| Typedef name | Use its encoded type's `ty-size` |
| Stars after a type | Each star overrides byte count with pointer size 8 |
| Local struct value/pointer | Descriptor size / 8 |
| Other local inline array | Recorded length × 8 |
| Other local scalar | Its type's size |

The caller then requires `)`, emits the size immediate, and marks a non-lvalue. This is not a general unevaluated-expression parser: `sizeof(x++)` does not fit the local-identifier branch's required next token. Unsupported type spelling/name/category is rejected by its 102–110 checks.

LP64's `cc-native-sizeof` accepts a type query or a unary expression, and temporarily emits while discovering its type. It saves output position, global-fixup count, and the prior unevaluated flag, sets unevaluated true, parses, computes size, then restores those three facts. An expression's array length and row width prevent ordinary decay from destroying its extent. `sizeof (a)[0]` includes the postfix `[0]`; the parenthesized primary is not automatically the end of the operand. A bare operand goes through unary parsing.

For a valid LP64 scalar `int x`, `sizeof(x++)` therefore visits the update parser, derives int size four, discards the temporary emitted update sequence by restoring output position, and emits only the retained size result. Runtime `cc-parse-sizeof` publishes unsigned-long type. The constant unary parser can call `cc-native-sizeof` for the byte count directly. Neither route proves that every compiler mutation was rolled back. The exact rollback and provider contract are expanded below.

## Complete the conditional arms

C13 established the emitted branch skeleton for `condition ? left : right`: test condition, branch to false, emit true, jump over false, then join. Both source arms are parsed. Only one emitted arm runs for a particular condition.

The [actual arm grammar](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2145-L2198) is profile-dependent:

- Legacy: true arm assignment, false arm assignment
- LP64: true arm comma expression, false arm assignment

Thus `c ? a=2 : b=3` permits assignments in both arms. The false arm's assignment parser re-enters ternary, giving `c ? a : d ? b : e` its nested right arm. Under LP64, `c ? a=2,b=3 : d=4` contains both comma-separated expressions in the true arm. In `c ? a=2 : b=3,d=4`, the final comma belongs outside the conditional; it is not swallowed into the false arm. These statements describe this implementation's grammar, not a substitution of a standard grammar for inspected code.

On matching `?`, materialize/test the condition and save the false-branch fixup. After parsing/materializing the true arm, save its native metadata if relevant and create its jump-over-false fixup. Require `:`, error 117 otherwise. Patch the false branch to the current position, parse/materialize the false arm, and complete the join. If there was no `?`, put back the lookahead and preserve the lower expression's state.

Legacy joining patches the true jump and marks a non-lvalue. Native joining also needs both types: the true arm's type, descriptor, row width, null provenance, and qualifiers survive the false parse on the builder data stack. Later conversion code must act on the value from whichever arm actually ran. The depth section shows why System V asks for two conversion paths instead of treating the last parsed arm as the universally executed one.

## Preserve the outer destination

Assignment parses a ternary expression, snapshots its kind and local slot, and looks for `=` or a compound operator. Its RHS recursively calls **assignment**, not the next tighter binary level. That is why `a=b=1` gives the outer store the value produced by the inner store.

`cc-assign-op?` tests punctuation and looks up compound spellings in the operator table's `bo-compound` column. The ordinary `+` row and its `+=` spelling share an emitter, but their lookup columns differ. `cc-apply-compound-op` expects a compound spelling and fails with 118 if no row exists. Plain `=` bypasses arithmetic entirely. If no assignment operator follows, discard the tentative kind/slot snapshot and put back the token; do not materialize or reset the original expression merely because it passed this level.

### Trace: `a = b += 3;`

**Legacy premises:** scalar locals a and b have distinct slots A and B, with initial values 9 and 4. The semicolon belongs to the statement parser. Generated temporary stacks below start empty.

| Step | Builder's surviving facts | Predicted generated action/state |
|---|---|---|
| Parse `a =` | Save A and `=` | Local producer loaded 9; plain assignment does not push that old value |
| Parse inner `b +=` | Outer `[A,=]`, then inner `[B,+=]` | Load 4; push old value, temporary stack `[4]` |
| Parse literal `3` | Both destination snapshots survive | RDI=3; current metadata now describes a literal |
| Finish inner compound | Recover `+=`, B | RCX=3, pop RDI=4, append ADD; RDI=7; stack `[]` |
| Store inner result | Outer A and `=` still saved | Store 7 into B; publish non-lvalue |
| Finish outer plain store | Recover `=`, A | Store the same 7 into A; publish non-lvalue |

The predicted final state is a=7, b=7, expression value 7, with no expression-owned generated temporaries. Nothing consulted “the current local slot” after the inner parse to rediscover A. A survived in builder return state. An old value survived on the generated stack only where the compound operation needed it.

This distinction is the [legacy local assignment algorithm](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2323-L2359). A result equal to a stored value is still a non-lvalue result; it does not retain permission to assign through the completed assignment expression.

### A memory destination needs its address saved too

Supply a valid pointer p with value P, a writable qword at P initially holding 10, and independent local b=4. Compare two independent traces:

- `*p = b+3`: save `[P]`; parse RHS to 7; recover P; store 7. There is no need to read the old pointee 10
- `*p += b+3`: save `[P,10]`; parse RHS to 7; recover 10 for addition, yielding 17; recover P; store 17

In the compound case, destination P outlives the old value because it is pushed first and popped last. Builder return state preserves kind and compound spelling. The old value's width comes from `lv-deref-byte` versus `lv-deref`; the matching final store uses one byte or eight bytes. These [plain and compound dereference paths](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2360-L2417) are both present.

For plain assignment, the actual appended rearrangement first moves RHS to RCX and pops destination to RDI, then uses push/move/pop to obtain the store convention RDI=value, RCX=address. For compound assignment, after combining old RDI with RHS RCX, a pop directly restores destination into RCX. This small asymmetry follows from what each path saved, not from a different store interface. A destination kind without a supported local/address path fails with 120.

The legacy byte store writes the low byte; it does not automatically make the assignment expression's RDI a narrowed byte result. Keep a bounded example such as 10+7 when predicting identical stored and returned numbers. Native assignment explicitly converts to the destination type before storing.

## Finish the row

Now join the earlier chapters' pieces in the recurring legacy expression `w[r] = 1 + r * 2;`. Supply r=2 in slot 4, base B=RBP−32 for the four-element local array w, and its C08 element metadata. No previous value of w[2] is needed.

1. The identifier-index path emits B, saves it, parses r to 2, scales by eight, and adds. RDI will hold B+16; metadata says pending int destination
2. Assignment sees `=`, saves destination B+16 on the generated stack and kind on the builder return stack. It does not load w[2]
3. The RHS additive level saves literal 1. Its multiplicative child saves r's value 2, parses literal 2, and combines them to 4
4. The additive level recovers 1 and combines it with 4 to produce 5
5. The outer assignment recovers B+16 and rearranges registers to value 5/address B+16; its qword store writes w[2]
6. The assignment marks a non-lvalue. Public expression materialization adds no load. The semicolon remains available to the statement parser

The expression-owned generated stack evolves as `[B+16]`, `[B+16,1]`, `[B+16,1,2]`, `[B+16,1]`, `[B+16]`, `[]`. Builder stacks separately preserve parser rows and destination kind. Multiplication and addition were emitted for later runtime execution; this was not constant folding because the builder happened to know our paper premise r=2.

**Pause point:** we have a predicted store of 5, a result value of 5, balanced expression temporaries, and a pending semicolon. On returning, ask what changes when a compiler consumer needs the answer *during compilation*. That is the next mechanism.

### The public boundary and LP64 comma

[`cc-parse-comma` and `cc-parse-expr`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2426-L2442) keep two different promises:

```forth
: cc-parse-comma
  cc-parse-assign
  cc-target-lp64 @ if,
    begin,
      cc-next-token-keep [char] , cc-tok-punct?
    while,
      cc-check-static-init
      cc-emit-materialize cc-parse-assign
      [lit] 0 cc-last-expr-null !               \ comma results are not constants
    repeat,
    cc-putback-token
  then, ;

: cc-parse-expr
  cc-parse-comma
  cc-emit-materialize ;
```

Legacy comma parsing is only the initial assignment call. LP64 loops across commas: each discarded left expression is materialized, then the next assignment is parsed; null-constant provenance is cleared. The last operand's remaining state is not forcibly materialized by the comma helper. Grouping can therefore preserve that state until a later consumer decides. The public expression entry always materializes the result, ensuring that external scalar consumers receive a value rather than an unconsumed pending scalar address. An aggregate's established address-as-value convention still applies.

The static-initializer guard here, and at selected native loads/calls/updates/assignments, checks static-init mode **and not unevaluated** before raising 219. It is a coordinated set of call sites, not a blanket guarantee around every legacy expression. G09 owns symbolic static constants.

## Compute a constant now

An array bound or expanded preprocessing condition needs a builder value. It cannot wait for the generated program to run. The constant parser therefore walks related precedence rules but calls the operator table's `bo-eval` word, not `bo-emitter`.

The [builder arithmetic words](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1579-L1626) provide operations the seed host does not supply directly:

- Negation computes zero minus n; inversion uses NAND of n with itself
- XOR computes `(a OR b) AND NOT(a AND b)` using a saved intermediate
- `cc-flag` maps a Forth false/true flag to C's 0/1
- Signed division checks the divisor, divides absolute magnitudes with unsigned `/`, then restores a negative quotient when operand signs differ
- Remainder divides magnitudes and subtracts quotient×divisor, then restores the dividend's sign
- `cc-pow2` doubles one n times; left shift multiplies by it
- Arithmetic right shift divides a nonnegative value; for a negative value it inverts, divides the nonnegative complement, then inverts back
- Comparisons invoke their seed comparison and normalize the flag

For bounded -7 and 3, division predicts -2, remainder -1. For -7 shifted right once, invert to 6, divide by 2 to 3, invert to -4. These are derivations of specific helpers under the stated 64-bit cell model, not blanket equivalence with x86 arithmetic over every count, overflow, or extreme signed value. The default comparison words inherit seed comparison limitations; typed preprocessing has explicit opposite-sign handling described below. A zero divisor reaches 124 only if the division helper is actually invoked.

### Grammar without generated arithmetic

The [default operand/unary/binary parser](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2513-L2574) accepts numbers, characters, enum constants, and parenthesized constant expressions. A non-enum name outside PP fails with 125; in PP mode a remaining identifier supplies zero. LP64 numeric tokens also undergo literal-suffix validation. Bad operand starts and missing closing parentheses reach 126 and 127.

Unary recursion accepts `-`, `+`, `!`, and `~`. Logical not normalizes to 0/1 and clears unsignedness. LP64 adds `sizeof` through the unevaluated size query. This is not the full runtime expression grammar: no assignment, update, call, ordinary dereference, or comma operator is supplied by the default constant grammar.

Instead of eight nearly identical binary words, `cc-cx-binary(level)` recurses to level−1; zero selects unary. At each level it repeatedly finds a matching table row, saves that row and the left unsigned flag, recursively obtains a tighter RHS, and applies the evaluator. Iteration makes same-level operations left-associated. The builder data stack carries actual numbers. There are no generated operand pushes in this ordinary arithmetic route.

For `2 + 3 * 4`, the additive invocation holds builder value 2 while multiplication obtains builder values 3 and 4 and returns 12. The evaluator for `+` then returns 14. A runtime parser for the same spelling would append immediate loads and arithmetic; it would not hand 14 to an array allocator during the parse.

### Read a dead arm, suppress its operations

`cc-cx-skip` means “do not evaluate dead binary operations,” not “stop parsing.” Constant `&&` and `||` save its previous value before each RHS. AND sets it true when the left value is zero; OR sets it true when the left value is nonzero. They still call the RHS parser, then restore the saved flag and normalize the combined logical result. They never clear an already active outer skip merely because an inner condition happens to look live.

At binary application, suppression discards operands and operator row and supplies placeholder zero instead of calling the evaluator. Typed PP additionally maintains its flag rules while suppressing the operation. Unary parsing and operand validation still occur. Consequently a dead division can avoid 124 while malformed syntax still fails.

The [constant conditional](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2603-L2628) saves outer skip, suppresses the true arm when condition is zero, parses it recursively, restores outer skip, saves true-arm unsignedness and value, requires `:`, and suppresses the false arm when condition is nonzero. After parsing false, it keeps the selected value, ORs the arms' unsignedness, and restores outer skip. Missing colon reaches 128. Both arms have this constant grammar; they do not inherit runtime assignment/comma arms.

### Trace: an expanded preprocessing condition

Take the **12-byte** expanded text `1 || (1 / 0)`, living at builder address A. Let S be `cc-src-buf`, old reader limit U, and old lexer snapshot L. Assume a normal non-nested public PP evaluation call and live text throughout. This is a source-derived success trace, not a test run.

The wrapper is small enough to inspect whole:

```forth
: cc-pp-eval-text
  cc-cx-save cc-lex-mark
  cc-src-len @ >r
  over + cc-src-buf - cc-src-len !                  ( a )
  cc-src-buf - cc-src-pos !
  [lit] 0 cc-tok-pending !
  true cc-cx-pp !
  [lit] 0 cc-cx-skip !
  cc-parse-const
  cc-next-token-keep  tok-kind @ tk-eof <> if, [lit] 129 cc-die then,
  [lit] 0 cc-cx-pp !
  r> cc-src-len !
  cc-cx-save cc-lex-reset ;
```

Source: [`cc-pp-eval-text`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2630-L2651).

1. Save L in `cc-cx-save` and U separately on the builder return stack. Set reader position to A−S and limit to A+12−S; clear pending-token replay. Set PP true and skip false
2. Parse the left builder cell 1. Even with the System V constant provider loaded, PP selects the default grammar
3. OR saves prior skip=false, sees nonzero left, and sets skip=true before parsing the parenthesized RHS
4. Division still parses 1, `/`, and 0. At application, skip=true discards their binary evaluation and returns placeholder 0. No division helper is invoked. The closing `)` is still required
5. OR restores skip=false and combines truth values to builder cell 1
6. Require EOF. Clear PP, restore U, and reset L. Return 1 to the preprocessing caller, which continues to own the expanded text

The source-relative offsets can be negative when A lies below S. Both endpoints use the same base; the parser does not require this scratch text to have been copied into the original source buffer.

**Exactly what returns?** The [64-byte lexer block](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/020-cc-arena.fth#L14-L28) contains eight cells: source position, source line, token kind, token number/punctuation value, token-string address, token-string length, keyword ID, and pending-token flag. All eight are restored, including any old pending token. Source length is outside that block and restored separately. `cc-src-buf` is used as the coordinate base, not replaced. PP is set to false, not restored from a saved prior value. Skip is initialized false and nested parsers restore their outer value; the wrapper does not save a caller's arbitrary skip state. Unsigned scratch is not part of the lexer snapshot.

This is a **successful-return** contract. A `cc-die` path is not exception cleanup that promises to restore state and resume. The single `cc-cx-save` buffer is not a nestable stack of PP invocations. Do not expand the claim into “everything is rolled back.”

Change the input to `0 || (1 / 0)`: the RHS is live and division reaches 124. Append a trailing `2` to the original input: expression parsing can return a value, but the wrapper rejects the remaining token with 129. Outside PP, a dead non-enum name still fails 125; inside PP, that remaining identifier becomes zero. Suppressed evaluation and accepted grammar are different questions.

## Depth: LP64 changes the local algorithms, not just widths

This section completes the native branches physically present in 100/110. It does not open the later System V scheduler, full native declarators, floating arithmetic, bitfield layout, or aggregate transport. A loaded provider and an enabled profile are separate facts. LP64 alone does not mean System V, floating execution, or symbolic constants.

### Private stack calls and result metadata

The [default native argument parser](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L488-L584) parses assignment arguments, materializes each, rejects a plain struct argument with 212, and pushes one eight-byte slot per value. It handles the empty `)` case and checks the nonempty list's closing delimiter with 121. It then reverses the argument slots in place: for each i below n/2, swap offsets 8i and 8(n−1−i) from RSP using RAX/RCX scratch. With three arguments, `[arg0,arg1,arg2]` becomes `[arg2,arg1,arg0]`, top at the right. After CALL pushes its return address, arg0 is nearest that return address.

A named function goes directly to a known address or receives a rel32 fixup when its symbol address is zero. During unevaluated parsing, the native unresolved-call path discards the placeholder's registration rather than attaching it to a live call list. After the call, `cc-native-drop-args` adds 8n to RSP if n is nonzero, and RAX is copied to RDI.

For a named pointer object, load its target from a local slot or global storage *before* arguments, then push it below them. For a postfix indirect call, materialize the current target and push it in the same position. Reverse only the n argument slots. The target remains at `[RSP+8n]`; load it into RAX, call RAX, and discard n+1 slots. Each owned staging slot has a matching cleanup. This is the private convention's local algorithm, not the System V register/overflow planner.

Named-call dispatch queries result qualification and `(type,descriptor)` **before** parsing nested arguments and preserves them on the builder return stack. The defaults return no qualifiers; a direct function's declared type is its result type, while other callable symbols default to int, with associated descriptor from the symbol query. The default postfix indirect provider itself publishes int/descriptor zero. `cc-native-function-desc-fwd` defaults to discarding the symbol ID and returning zero; later signature providers supply richer identity.

The default call/indirect hooks are bound to these private-stack bodies. [`121`'s call providers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L972-L992) supply signature-backed queries, and its scalar call paths at [1121–1157](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1121-L1157) are the G04 scheduling boundary. `131` wraps them for G15 aggregate transport. C23 owns the complete private-frame convention. Unknown-identifier and intrinsic hooks from C12 remain bounded: defaults return a negative sentinel and false respectively; successful providers must supply a symbol or consume the complete intrinsic. They do not grant arbitrary names permissive call semantics.

### Typed update and address operations

[`cc-native-inc-dec`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L977-L1026) receives delta (+1 or −1) and postfix flag. It checks static-init restrictions, snapshots qualifiers/type/descriptor/field record into `cc-change-*`, after `cc-change-check-fwd` validates the value; its default invokes the integer-use policy. For `lv-local`, emit its LEA; otherwise require a pending address, error 113. Then:

1. Push destination and load the old value through `cc-field-load-fwd(type,field)`
2. For postfix only, push old value too
3. Call `cc-change-value-fwd`; its default adds delta times scalar step one or pointee size
4. In the default hook, convert from promoted type to destination type (including boolean 0/1)
5. For postfix, pop old value into RDX; pop destination into RCX and store through the field hook
6. For postfix, restore old value from RDX into RDI; otherwise keep the new value
7. Publish field value type plus saved descriptor and qualifiers as a typed non-lvalue

For LP64 `int *p` with value P, postfix `p++` predicts stored P+4 and returned P. For a legacy pointer update, the stored value advances by one. The same token is therefore not a profile-independent stride promise. Field hooks may alter storage width/promotion; G14 owns bitfields. `cc-change-*` is one completed update's scratch, not persistent state across recursive operand parsing.

The [native address-of branch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1462-L1537) recursively parses unary, rejects `lv-temporary` with 116, and asks the field-use hook whether this field can supply an address. A local produces LEA. Other accepted address-like states are pending memory, a nonzero associated descriptor, retained array extent, or function type; unsupported shapes fail 116. Arrays call `cc-array-address-fwd(type,descriptor,count,inner)`, whose default drops extents and adds one pointer level. Other types gain a level except the special already-value `func *` case. Type, descriptor, and saved qualifiers are then republished. System V's ranked-array provider preserves a complete array node rather than relying on that default.

This is why `&*p` can reuse the already computed address under the native path without loading the pointee. Field-use defaults consume the field pointer without checking; G14's replacement can reject address-taking for a bitfield. An interface default is not a complete legality checker.

### The precise `sizeof` rollback boundary

[`cc-native-sizeof`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1271-L1309) saves O=`cc-out-pos`, G=`cc-gfixup-count`, and E=`cc-expr-unevaluated`. It sets unevaluated true before either expression or type parsing.

After `(`, read a candidate token and ask the type-start hook. A type route obtains `(type,descriptor)` through `cc-sizeof-type-fwd`, then calls the size-policy hook. Its local caller also accepts following bracketed constant counts, multiplying the size by each and requiring `]`, before requiring `)`. An expression route puts the candidate back, resets the initial expression mark, parses the grouped expression and any following postfix operations, then queries size. Without an opening parenthesis, put back the candidate and parse unary.

Expression-size calculation first invokes field-use policy. If array length is retained, compute pointee size × length, additionally × inner row width when nonzero. Otherwise compute the expression type/descriptor size. The type-size hook defaults to `cc-expr-type-size`; System V's provider includes richer type-name array shape. The successful return restores E, G, O in reverse order.

For `sizeof(x++)`, E permits otherwise guarded unevaluated work, O removes temporary instructions, and G removes temporary global-reference fixups. Native call/function-address producers cooperate by suppressing relevant function-fixup registration while unevaluated. The reader intentionally advances past the operand. Expression/type scratch and arbitrary provider allocations are not all restored by these three assignments. G03/G15 must preserve the unevaluated contract when replacing a provider; they cannot assume a general transaction repaired their state.

### Two scalar conversion paths at a conditional join

The true arm's saved tuple is `(type,descriptor,inner,null,qualified)`. At the false arm's completion, the native parser puts its saved true jump beside that tuple and invokes `cc-aggregate-ternary-fwd`. Default behavior returns false and leaves everything for scalar processing. A handled provider must consume the tuple/fixup, complete the join, and publish the result; `131` supplies that [aggregate temporary contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L426-L447), whose full lesson belongs to G15.

For the scalar fallback, `cc-expr-save-native-types` joins saved true facts with current false facts in C13's `cc-expr-left/right-*` scratch. The array policy and value-ternary policy hooks then check/adjust the common-type decision. Defaults are no-ops.

If `cc-value-ternary-split-fwd` is false, patch the true jump to a single join and emit common-type conversion there. Both paths reach that shared conversion. If it is true, the false path gets a source-specific right-to-common conversion followed by a new jump; patch the old true jump to the following left-to-common conversion; patch the new jump after it. In source order, the retained layout is:

```text
true arm  → jump to true conversion
false arm → false conversion → jump to joined result
true conversion
joined result
```

This is a schematic layout, not copied source or measured machine bytes. The false arm was parsed last, but its source type cannot be used to convert the true arm's runtime value. [`cc-sysv-ternary-split`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L695-L696) returns the System V flag; the original default returns false. Floating conversion policy is a G10 seam, not opened here.

Finally publish common type and selected common descriptor. Pointer results combine left/right qualifiers with OR; common row width is retained. Null provenance was input to the policy; it is not automatically preserved by the final reset/publish. This local algorithm completes the runtime ternary contract without claiming all provider type rules have been taught.

### Native assignment still owns its stores

[`cc-parse-native-assign`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2240-L2321) rejects temporary destinations with 120, checks static-init mode, and turns a local into an address with LEA. Otherwise it accepts pending memory or the plain-struct address convention. Before recursive RHS parsing it saves, in order, qualifiers, field record, type, descriptor, and operator on the builder return stack. Push destination on the generated stack; for compound assignment, field-load and push old value too. Only after RHS parsing/materialization returns does it restore those facts into `cc-assign-*`.

For plain scalar assignment, call `cc-value-shape-fwd(source type/descriptor,destination type/descriptor)`, convert RHS to destination type, pop destination into RCX, and field-store. Default shape policy drops all four cells; richer pointer/signature compatibility comes from 121. Publish the field value type, saved descriptor, and qualification. This conversion before store differs from the legacy byte-store path's unqualified RDI value.

For compound scalar assignment, derive the left value type via the field hook and save left/right types into C13's common-type scratch. Find the `bo-compound` row, invoke compound-array and binary-array policies, and make shift common type the promoted left type. Pointer additive compounds scale the RHS by pointee size. Move RHS to RCX, pop the old left value into RDI, convert both to common type, and invoke the native binary emitter. Convert that result back to destination type, pop destination, store, and publish. The destination's address survives longer than the old value, exactly as in the legacy trace.

A plain struct destination takes a separate current-file algorithm. Reject compound forms after the aggregate-compound policy (default discards type/descriptor). For `=`, the aggregate-assignment policy may validate the saved/current shapes; its default is a no-op. RDI carries source address. Copy it to RSI, pop and preserve destination in RDI, load byte count from destination type/descriptor into RCX, and emit `REP MOVSB`. Recover the original destination address afterward and publish destination type/descriptor/qualification. This copy loop belongs to 100 and cannot be replaced in the explanation by “a later target handles aggregates.” G15 owns the additional validity, temporary, and transport policies layered over it.

## Depth: three constant contracts, two exact gates

Do not treat “native constants” as one switch. There are three relevant contracts:

1. The **default cell evaluator** in 100 uses the constant grammar described above
2. **Typed preprocessing arithmetic** inside that evaluator is enabled exactly by `cc-cx-pp AND cc-target-lp64`
3. With 125 loaded, the deferred public parser selects its **target integer-constant provider** exactly when `cc-target-sysv AND NOT cc-cx-pp`; otherwise it calls the default parser

Direct-preprocessing mode alone is neither gate. LP64 outside PP alone does not enable the typed-PP evaluator. Under System V, PP still routes through the default grammar and then uses its typed arithmetic branch because LP64 is enabled.

[`cc-cx-eval`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2461-L2499) receives `(left,right,row,left-unsigned)`. The right unsigned flag is current. A shift keeps the saved left flag; other operations OR left and right flags. Numeric PP operands mark unsignedness from a checked unsigned suffix or a high-bit-set cell. Comparisons use sign-aware helpers: if signs differ, signed less-than selects the negative operand, while unsigned less-than places the high-bit-set operand above the other. Equal-sign cases use the seed comparison. Comparison results clear unsignedness.

Unsigned division/remainder use the seed unsigned divisor operation; unsigned right shift divides by `2^n` without sign restoration. Other cases dispatch the table evaluator. Skip suppression still prevents executing the dead binary operation. Logical results are signed 0/1; conditional results combine the arm flags even while keeping only one arm's value. These are local flag algorithms, not a complete C integer-type lattice or a proof over arbitrary shift counts.

For a bounded changed case, typed PP `-1 < 1U` combines flags as unsigned: the all-ones cell represents the larger unsigned value, so the predicted result is 0 and its resulting flag is signed. For `8U >> 1`, the left flag remains unsigned and the predicted value is 4. Those examples require PP **and** LP64; importing ordinary eight-byte runtime type metadata into this one-flag evaluator would describe a different mechanism.

[`125`'s public selector](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/125-cc-consteval.fth#L594-L610) uses a typed static-constant parser returning `(value,type,descriptor,symbol)`. Its integer wrapper rejects a symbolic identity or noninteger type and then the public selector drops the type to preserve the caller's single-cell result contract. The full tuple, symbolic addresses, relocations, and typed grammar belong to G09/G02. In 100, `cc-parse-static-const-fwd` and the identifier/address/string leaf hooks initially point to `cc-const-unsupported`, which terminates with 240. They do not magically provide symbolic evaluation before a target binds them.

## Close the deferred references

The grammar is recursive and Forth definitions arrive in source order. Deferred cells let an early call/index/group parser name a later expression entry. The final bindings do not add another parsing pass; they connect the already taught contracts:

```forth
' cc-parse-expr   is cc-parse-expr-fwd
' cc-parse-comma  is cc-parse-comma-fwd
' cc-parse-assign is cc-parse-assign-fwd
' cc-parse-unary  is cc-parse-unary-fwd
```

These are [all four final bindings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2653-L2657). The constant path is separately bound to the *deferred public* `cc-parse-const`, not directly and permanently to its default body. That extra indirection is why later target rebinding remains visible to parenthesized constants and other forward callers. `cc-pp-eval` separately binds to `cc-pp-eval-text`, closing C05's evaluator promise.

After 110 defines the type parser, [`cc-try-cast-fwd`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L670) binds to `cc-try-cast`; its [last three lines](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/110-cc-decl.fth#L805-L808) connect the sizeof type-start query and `(type,descriptor)` adapter. Native type-name/type-start providers in 115/121 remain C23/G03's fuller grammar. Their result contract is usable here without teaching every declarator first.

The remaining value seams have narrow roles. Literal defaults return unhandled; test/not/negate/complement defaults append the existing scalar operations; plus/ternary defaults perform no additional work; integer-use defaults consume the proposed type; shape defaults discard their four facts. `cc-value-init-fwd` defaults to discarding source/destination and is a later initializer seam, not a step that every expression executes. G10's floating and G15's aggregate providers may replace these policies. Callers still own the recursion, staging, and publication just traced.

## Practice: predict before opening feedback

These ten paper exercises use the pinned implementation. They do not request compilation or source changes. Record the decisive intermediate state as well as the result. [Graduated hints and checked manual solutions](../practice/14-solutions.md#hints) are available immediately. After checking, use a changed case to see whether the repaired reasoning holds; copying the solution is supported practice, not independent evidence.

### C14-01 — Compose a suffix chain

Use the legacy `head->s[1]++` premises from the chapter, but change the source to `head->s[2]--` and supply byte Q+2=70. Show RDI's meaning after each suffix, every required load, final memory/result, and the token ownership of the following semicolon. Why must the pre-index type survive recursive index parsing?

### C14-02 — Keep argument separators

Supply a valid f callee and distinct scalar locals a/b in each profile. Compare legacy `f(a=2,b=3)` with LP64 private-call `f((a=2,b=3),4)`. Count arguments, identify the parser boundary that consumes each comma, and draw argument staging immediately before the call. Then change the native call to a postfix indirect target T: where is T relative to RSP after argument reversal, and how many slots are removed afterward?

### C14-03 — Old/new and byte/stride

From independent legacy states b=4 and byte at P=65 with a valid `char *p=P`, trace `b++`, `++b`, and `(*p)++`. Identify the failure boundary for `b++--`. Then compare legacy versus LP64 postfix update of a valid `int *q=Q`, including stored pointer and returned value.

### C14-04 — Protect an outer assignment

With distinct legacy slots A/B and a=9,b=4, complete a trace for `a = b -= 3;`. Show builder destination/operator snapshots and generated old-value staging separately. Change the outer operator to `+=` in an independent initial state. Which additional value must survive, and what are both final locals?

### C14-05 — A place has two consumers

With valid legacy qword P initially 10 and b=4, compare `*p = b+3` and `*p *= b+3` from independent states. Draw saved generated values in order and identify when P is recovered. Transfer the plain-store explanation to `w[r]=1+r*2` with r=3 and valid four-element w at B; derive destination, stored value, and surviving delimiter without assuming old w[3].

### C14-06 — Type query or grouped expression?

Trace legacy `(char)(int)321`, including the destination facts protected across recursion. Contrast legacy and LP64 `sizeof(x++)` for a valid scalar int x. In LP64 list exactly the saved/restored facts and say whether parsing visited the update. Explain how `sizeof (a)[0]` chooses its operand when a is a valid array.

### C14-07 — Join the selected arm

Under LP64 compare `c ? a=2,b=3 : d=4` and `c ? a=2 : b=3,d=4`, with valid distinct scalar locals. Mark the true/false/outside comma boundaries. Explain why source-specific conversion of a true-arm int and false-arm long needs the true type saved across the false parse. Draw the split conversion layout without inventing machine addresses.

### C14-08 — Evaluate now, still check syntax

Derive default constant `-7/3`, `-7%3`, `-7>>1`, and `2+3*4` on paper under the chapter's bounded cell assumptions. Compare `1 || (1/0)` with `0 || (1/0)`, and explain what changes if the dead RHS has a missing `)`. Why is legacy constant `+3` a different grammar case from legacy runtime `+3`?

### C14-09 — Restore the reader precisely

Let S=1000, expanded-text address A=900, length 12, old source limit U=500, and old lexer state `(position=40,line=7,kind=punct,num=';',string-address=800,string-length=2,keyword-id=0,pending=true)`. Evaluate the supplied `1 || (1 / 0)` text on paper. Give entry reader endpoints, skip transitions, result, and every restored field. Which flags are reset rather than snapshot-restored? What changes with a trailing `2`?

### C14-10 — Identify the active contract

Assume 125 is loaded. For each combination, choose the public constant parser and whether its typed-PP branch applies: (a) LP64 false/System V false/PP false; (b) LP64 true/System V false/PP false; (c) LP64 true/System V false/PP true; (d) LP64 true/System V true/PP false; (e) LP64 true/System V true/PP true. In case (e), predict `-1 < 1U` and identify the result's unsigned flag. Finally explain which facts a native assignment must save before RHS recursion that a later provider cannot reconstruct from the RHS metadata.

## What is now closed?

You can follow a whole runtime expression without mistaking an address for a value or the builder stack for the generated stack. You can preserve a destination through nested assignment, locate a call's argument boundaries, explain old versus new update results, and separate a cast/sizeof type query from grouping. You can also trace a default constant through immediate arithmetic, dead-arm suppression, and exact successful PP reader restoration.

[C15](15-declarations-and-recursive-records.md) next constructs the symbol rows, slots, and descriptors that these traces took as premises. C18 will integrate call frames; C23 and G03/G04/G09/G10/G14/G15 open the named provider contracts. No new execution or learning-study claim follows from this source-based closure. The exercises supply opportunities to test the reasoning; an actual reader's attempt remains the evidence for whether it has become usable.
