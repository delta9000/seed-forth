# C14 practice help: expressions and constant evaluation

[Back to the chapter](../chapters/14-expressions-and-constant-evaluation.md)

These are checked **manual source derivations** for revision `bbcc1732152af2d884737272eed870d2410ffe8e`. They are not compiler runs, generated-program observations, or conformance tests. Every memory value, valid pointer, and symbol record is a supplied premise. Use as much help as is useful; a partial state trace is enough to identify the next repair.

## Entry check

1. Grouping does not require a pointee load. It preserves the inner pending-address state by using assignment/comma parsing rather than public final materialization
2. The builder's return stack saves a table-row address. Appended push/pop instructions preserve the runtime left operand on the generated program's stack
3. Token putback sets replay state; it does not rewind the byte cursor
4. An emitter execution token appends instructions. An evaluator execution token computes builder cells now. The shared word `execute` does not make their contracts identical

If a distinction was missed, redraw just that transition with columns headed “builder now” and “generated later.” Then attempt a changed expression before continuing. If the four answers were secure, the mixed profile check C14-10 offers a less-supported route.

## Hints

### C14-01 hints

1. Separate the pointer field's address H+8 from the pointer value Q stored there
2. The pre-index type is `char *`, so the element stride is one and the final pending destination is a byte
3. Postfix needs the old byte as its returned value, even after memory has been decremented

### C14-02 hints

1. An argument parser must stop at the comma that separates arguments. Parentheses can introduce an inner comma grammar under LP64
2. Name both moments: after staging and after any pops/reversal. A legacy call has already popped its argument temporaries when CALL executes
3. With two native arguments, the saved indirect target lies below two eight-byte slots

### C14-03 hints

1. An update's returned value and its stored value are different questions
2. Grouping `*p` preserves the pending address; materializing it early would discard the destination kind needed by postfix
3. A pointer update uses one in the legacy routine but pointee size in the LP64 typed routine

### C14-04 hints

1. Write outer `[A,operator]` before entering the inner RHS
2. An old value must be pushed only for a compound assignment
3. With outer `+=`, the generated stack after recognizing inner `-=` begins `[9,4]`, top at the right

### C14-05 hints

1. Plain assignment saves destination P. Compound assignment additionally saves the old value, above P
2. A multiplication compound still uses the compound-spelling table lookup; it is not parsed as binary `*` followed by `=`
3. For the array case, separate destination B+8r from the RHS value 1+2r

### C14-06 hints

1. The outer cast saves destination type, qualification, and descriptor before parsing the inner cast
2. LP64 sizeof saves output position, global-fixup count, and prior unevaluated flag. Reader advancement is intentional
3. In `sizeof (a)[0]`, the parenthesized expression is a primary that can still receive a postfix subscript

### C14-07 hints

1. LP64's true conditional arm calls comma parsing. Its false arm calls assignment parsing
2. A true arm jumps over the false arm's instructions. Ask where each path reaches a conversion derived from its own source type
3. The split layout needs a second jump after false conversion so that it bypasses true conversion

### C14-08 hints

1. Division uses absolute magnitudes and restores quotient sign; remainder restores the dividend's sign
2. Negative arithmetic right shift uses complement, unsigned division, then complement again
3. Skip is tested at binary application. It does not excuse a missing delimiter or unknown non-PP identifier

### C14-09 hints

1. Both new endpoints use the same S: start A−S, limit A+length−S
2. A saved pending token belongs to the old lexer snapshot, even if the evaluated scratch text reaches EOF
3. Distinguish a normal successful return from `cc-die`; there is no promised exception-unwind transaction

### C14-10 hints

1. There are two conditions, with PP on opposite sides: PP AND LP64; System V AND NOT PP
2. Loading 125 changes the deferred entry but does not force its typed provider in every call
3. The native destination snapshot includes field and qualification facts that are absent from the scalar RHS's metadata

## Checked solutions

### C14-01 — Compose a suffix chain

After `head`, future RDI is pointer H, obtained from the local. After `->s`, it is pending address H+8, whose type is `char *`. Indexing first loads the stored pointer Q from H+8, pushes Q, parses index 2, uses stride one, pops/adds the base, and leaves Q+2 as a pending byte destination. Postfix decrement moves that destination into RCX, loads old byte 70 into RDI, and decrements the addressed byte.

Predicted result: RDI=70 and byte Q+2=69. The result is non-lvalue with restored char type. A following semicolon is read by the postfix loop and put back; outer levels also hand it back until the statement consumer takes it. Repeated replay does not duplicate tokens or move the reader backward.

The index literal itself changes current-expression metadata. If the index consumer looked at that new type to choose stride, it would be consulting the index's type, not the base's element type. The saved pre-index `char *` is what selects one-byte stride and load.

Common wrong path: treating H+8 as Q. H+8 is storage containing the pointer; one materialization is required before adding the character index. For a changed reattempt, use a valid field of type `int *` in the legacy profile. The field load still obtains a pointer, but index 2 advances sixteen bytes and the pending element is a qword.

### C14-02 — Keep argument separators

Legacy `f(a=2,b=3)` has two arguments with values 2 and 3. The legacy public expression grammar stops before a comma because it contains no comma-operator loop. After both arguments are staged, the generated temporary stack is `[2,3]`. Before CALL, reverse-index pops give RSI=3 and RDI=2, and the expression-owned argument stack is empty.

LP64 `f((a=2,b=3),4)` also has two arguments, but their values are 3 and 4. Inner grouping invokes comma grammar: it consumes the comma between the two assignments and returns the last value, 3. The outer argument parser invokes assignment grammar; it stops at the comma after the closing parenthesis, leaving that separator for its own loop.

Under the private stack convention, staging `[3,4]` is reversed to `[4,3]`. Immediately before CALL, arg0=3 is at RSP and arg1=4 at RSP+8; after CALL's return-address push, arg0 is nearest the return address. A direct call removes two argument slots afterward.

For an indirect target T, the corresponding stacks are `[T,3,4]` then `[T,4,3]`. T is at RSP+16. The parser emits a target load from that offset into RAX and later removes three slots: two arguments plus T. That cleanup count does not include the return address, already consumed by the returning callee's RET.

Common wrong answer: counting the parenthesized comma as another argument or assuming LP64 uses the six-register convention. For a changed reattempt, add a third outer argument 5: reverse three argument slots, find T at RSP+24, and remove four owned slots.

### C14-03 — Old/new and byte/stride

From separate initial b=4 states:

| Expression | Predicted returned value | Predicted stored value | Decisive operation order |
|---|---:|---:|---|
| `b++` | 4 | b=5 | Local already loaded; increment slot while preserving RDI |
| `++b` | 5 | b=5 | Increment slot, then load it |
| `(*p)++` | 65 | byte P=66 | Preserve pending byte address through grouping; load old byte, then increment memory |

After the first update in `b++--`, the current expression is a non-lvalue. The second legacy postfix update finds neither `lv-local` nor a pending dereference and reaches error 98. This does not imply that field or index updates are unsupported.

For a legacy `int *q=Q`, `q++` returns Q and stores Q+1. Under LP64, the typed update obtains pointee size four, returns Q, and stores Q+4. Its generated staging preserves destination, then old Q; after calculating/converting the new value it recovers old Q through RDX for the postfix result. The native field/type hooks choose actual load/store width.

A useful changed check is prefix `++q`: storage changes by the same profile-specific step, but the result is the new pointer. Do not transfer the native stride rule back into the legacy emitter merely because both pointers occupy eight bytes.

### C14-04 — Protect an outer assignment

For `a = b -= 3`:

1. Parse a, load 9, and save outer builder facts `[A,=]`. No old a value is pushed
2. Parse b, load 4, push it, and save inner builder facts `[B,-=]` above the outer pair
3. Literal 3 returns; current shared metadata describes it, not A or B
4. Recover inner operator/slot. Move RHS 3 to RCX, pop old 4 into RDI, subtract to get 1, and store B=1
5. Recover outer operator/slot and store A=1. The final expression is a non-lvalue value 1

Generated old-value staging is `[4]` then `[]`. The builder snapshots, not those generated values, identify the local destinations.

For independent `a += b -= 3` from a=9,b=4, the outer compound also pushes old a=9. Before parsing inner literal 3, the generated stack is `[9,4]`; finishing inner subtraction gives b=1 with `[9]` remaining. Outer combination uses old 9 plus RHS 1, giving a=10 and expression value 10. Final stack is empty.

Common wrong answer: a=2 because both operators were treated as subtraction, or a=5 because the old b value was returned after `b-=3`. Assignment returns the stored arithmetic result here. Reattempt with outer `*=`: inner b still becomes 1, while a becomes 9.

### C14-05 — A place has two consumers

Plain `*p = b+3` stages `[P]`. It computes RHS 7 without reading the old qword at P, recovers destination, rearranges to RDI=7/RCX=P, and stores. Predicted memory P=7 and expression value 7.

Compound `*p *= b+3` stages `[P,10]`. RHS returns 7. Move it to RCX, pop old 10 into RDI, select multiplication through the compound column, and obtain 70. Pop P into RCX, store 70, and mark non-lvalue. The old value is consumed before the address because it was pushed afterward. Final memory and expression value are 70.

For `w[r]=1+r*2` with r=3, destination is B+24 and no old w[3] is required. Generated stack progression is `[B+24]`, `[B+24,1]`, `[B+24,1,3]`, `[B+24,1]`, `[B+24]`, `[]`. Multiplication produces 6, addition 7, and the final qword store writes w[3]=7. The semicolon remains available to the statement parser.

Common wrong path: loading the LHS before deciding whether `=` needs it. A pending address is already the right representation for a plain store. A changed byte-pointer example uses the same ownership order but byte loads/stores; a value exceeding 255 would require separately tracking the low-byte stored result versus the legacy expression's full RDI.

### C14-06 — Type query or grouped expression?

The outer `(char)` probe succeeds and saves char type, destination qualification, and descriptor. It then recursively parses `(int)321`; that inner cast has its own saved destination and publishes an int non-lvalue carrying 321. The outer snapshots survive the inner writes. After recovery, the legacy outer plain-char conversion zero-extends the low byte: 321 modulo 256 is 65. Final result type is char, kind non-lvalue, with the outer descriptor/qualification published.

Legacy `sizeof(x++)` reaches the local-name branch, whose next token must be `)`. It encounters `++`, so this expression is outside that accepted legacy form. It does not provide a general parse-and-rollback update mechanism.

LP64 `sizeof(x++)` saves output position O, global-fixup count G, and prior unevaluated flag E. It sets unevaluated true, parses the grouped expression including postfix update, obtains int size four, then restores E/G/O. Runtime sizeof emits the retained immediate four and publishes unsigned-long result metadata. The parser did visit `x++`; its temporary emitted update bytes were not retained. Lexer position advances past the operand; this is not a restoration of every compiler field or allocation.

For a valid LP64 int array a, `sizeof (a)[0]` parses grouped a, then continues its postfix chain with `[0]`. The size query applies to the resulting int element and predicts four, not the whole array size. The specific a extent is unnecessary beyond making element zero a meaningful supplied example.

Common wrong answer: “sizeof never parses its operand” or “restores all state.” The acceptance criterion is naming O/G/E and explaining the retained result separately from temporary output. For a changed query, `sizeof(a)` without `[0]` retains array extent and uses it in size calculation.

### C14-07 — Join the selected arm

In `c ? a=2,b=3 : d=4`, true-arm comma grammar consumes both assignments. If c is true, a becomes 2 and b becomes 3; the true arm's value is 3. If c is false, d becomes 4 and its arm value is 4. The selected runtime arm alone executes, though both were parsed.

In `c ? a=2 : b=3,d=4`, false-arm assignment grammar stops before the comma. The conditional completes, then the enclosing comma parser evaluates `d=4` regardless of c. If c is true, a becomes 2; if false, b becomes 3. In either case d becomes 4 and the complete comma expression's value is 4. These are predictions for distinct valid scalar locals.

The true-arm type is saved with descriptor, row width, null provenance, and qualifiers because parsing the false arm overwrites current-expression metadata. With split conversion selected, the emitted structure is:

```text
condition false → false arm
true arm → jump to true conversion
false arm → right-to-common conversion → jump to join
true conversion: left-to-common conversion
join: publish common result contract
```

Publication is builder metadata describing the joined result; it is not a runtime instruction at the join. The true path cannot execute a conversion chosen solely from the false arm's current type. The false path's new jump prevents it from subsequently executing the true conversion too.

Common wrong answer: two conversions in sequence on every path. Only one source arm and its associated conversion should contribute a selected scalar result. For a changed case with no `?`, ternary parsing puts back its lookahead and preserves the lower expression's metadata instead of creating a join.

### C14-08 — Evaluate now, still check syntax

Under the bounded helper model:

- `-7/3` divides magnitudes to 2 and restores differing-sign quotient: −2
- `-7%3` obtains magnitude remainder 1 and restores the dividend's sign: −1
- `-7>>1` complements −7 to 6, divides by 2 to 3, and complements to −4
- `2+3*4` computes multiplication 12 in builder cells before additive evaluation returns 14

These do not exercise extreme signed magnitudes, overflow, or arbitrary shift counts.

For `1 || (1/0)`, the OR parser saves outer skip=false, sets skip=true, parses the RHS, suppresses its binary divide, restores skip=false, and returns normalized 1. For `0 || (1/0)`, it does not activate suppression; division checks zero and reaches 124. A missing closing parenthesis still reaches 127 even in a suppressed RHS, because operand parsing checks delimiters independently of whether binary evaluation runs.

Legacy constant `+3` is accepted by `cc-cx-unary`; it returns the recursively parsed operand unchanged. Legacy runtime `cc-parse-unary` recognizes `+` only under LP64, so the same spelling is not supported as that legacy runtime unary form. Operator-table sharing does not merge the two grammars.

Common wrong answer: treating dead syntax as absent input. Reattempt with `0 && (1/0)`: evaluation is suppressed by AND's zero left value, but the closing parenthesis remains required.

### C14-09 — Restore the reader precisely

Entry scratch-reader position is A−S=−100. Its limit is A+12−S=−88. Negative source-relative coordinates are consistent because adding S maps them back to the live text's addresses 900 through 911; the exclusive endpoint is 912.

The wrapper saves the old 64-byte lexer block, separately saves source limit 500, clears pending replay, sets PP=true and skip=false. The left 1 makes OR save false and set skip=true across its RHS. Division is parsed but suppressed; the group closes, OR restores false and produces builder result 1. The wrapper consumes EOF.

On successful return the restored fields are:

| Field | Restored value |
|---|---|
| Source position | 40 |
| Source line | 7 |
| Token kind | Punctuation |
| Token number/code | Semicolon code |
| Token-string address | 800 |
| Token-string length | 2 |
| Keyword ID | 0 |
| Pending flag | True |
| Source limit, separately | 500 |

Token payload cells are restored even when a particular current kind does not use all of them. They are part of the snapshot, not recomputed from semicolon spelling.

PP is cleared to false rather than restored from an earlier saved value. Skip was initialized false; logical/conditional recursion restores the appropriate outer value, but the wrapper did not snapshot an arbitrary incoming skip flag. Unsigned scratch is not in the lexer block. The source-buffer base is unchanged. These distinctions matter if someone proposes nesting the wrapper or treating it as general state rollback.

With a trailing `2`, the complete-input check sees a non-EOF token and reaches 129. That is a terminating failure path, not a promised restored state from which parsing resumes. Do not report the success snapshot as an observed post-error state.

For a changed reattempt, choose A=1200 with the same S and length: endpoints become 200 and 212, while every successful restored field remains the same old snapshot. Coordinate sign was incidental; common base and exclusive limit were the invariant.

### C14-10 — Identify the active contract

With 125 loaded:

| Case | Public selection | Typed-PP branch inside default? |
|---|---|---|
| (a) LP64 false, System V false, PP false | Default cell parser | No |
| (b) LP64 true, System V false, PP false | Default cell parser | No |
| (c) LP64 true, System V false, PP true | Default cell parser | Yes |
| (d) LP64 true, System V true, PP false | Target integer-constant provider | Not this default-parser branch |
| (e) LP64 true, System V true, PP true | Default cell parser | Yes |

Case (e)'s `-1 < 1U` combines operand flags as unsigned. The all-ones cell from −1 compares above unsigned one, so the predicted comparison result is 0. Comparison publication clears the unsigned flag. That answer follows from the one-flag typed-PP algorithm, not a runtime common-type record or the target tuple parser.

Before native RHS recursion, assignment must preserve destination qualification, field record, type, descriptor, and operator on the builder return stack; it also turns/resolves the destination into a generated address and pushes it. Compound assignment additionally loads/pushes the old value. The scalar RHS's type, descriptor, and current kind cannot reconstruct the earlier destination's field identity or qualifiers. `cc-assign-*` is populated only after the recursive RHS returns, from those protected facts.

Common wrong answer: “125 loaded means every constant uses 125's typed body,” or “LP64 means the PP branch is active.” Reattempt by turning PP from false to true while leaving System V/LP64 true. The public selection changes to default, while the default's typed-PP flag becomes active. Two decisions changed in different parts of the call chain.

## Use feedback to choose the next step

If numeric results were right but state ownership was unclear, redo C14-04 or C14-05 with both stacks visible. If syntax boundaries were unclear, redo C14-02 or C14-07 before adding ABI detail. If profile facts were mixed, keep C14-10's two gates visible for one changed example, then try again without that table. A correct independent changed trace is more informative than rereading every page; an unattempted prompt is not evidence of transfer or retention.

A later return check can mix the mechanisms without their headings: present one expression that needs a runtime destination saved and one preprocessing span that needs reader state restored. Ask which actor owns each saved address, what becomes invalid after the recursive call, and what exact outcome the evidence supports. No fixed delay or score is prescribed here.
