# C13 practice help: precedence and short-circuit expressions

[Back to the chapter](../chapters/13-precedence-and-short-circuit.md)

These are checked manual derivations for the chapter's pinned source and supplied profiles. They are not execution results. Stack displays put the top at the right and show only lesson-owned saved items. Keep hints and solutions available: an attempt is useful, but help does not require a waiting period.

## Entry check

1. **No.** Putback sets the pending flag for the existing current token. The next `cc-next-token-keep` clears the flag and reuses that record without advancing source bytes
2. **Materialize before saving the value.** For legacy `t.rows`, that appends a qword load through its pending target address. Saving the address as though it were the number would give the arithmetic the wrong operand
3. The displacement is measured from **F+4**, immediately after the four-byte displacement field

If the first answer differed, revisit C06's pending flag. If the second differed, reconstruct C12's address/value transition. If the third differed, draw the opcode and operand field separately. Each repair is small enough to check independently.

## Hints

### C13-01 hints

1. Row numbering starts at zero; locate subtraction after the three multiplicative rows and addition
2. Separate row stride from field offset
3. The emitter and evaluator are both Forth execution tokens, but their called words have different contracts. Lookup also chooses a field explicitly

### C13-02 hints

1. The additive parser cannot finish while its multiplication child is still parsing
2. Keep two lists: saved table rows while building, saved numeric operands in the future program
3. At the final literal, the generated temporaries contain the outer left one below the multiplication's left operand

### C13-03 hints

1. Addition's right child is multiplication. Ask which operators that child is allowed to consume
2. After an application, the additive loop runs again with the completed result as its new left operand
3. Parentheses re-enter the wider grammar. They can therefore keep an inner subtraction inside the outer right operand

### C13-04 hints

1. Stop at the requested parser boundary, before public `cc-parse-expr` applies its final materialization
2. A no-match path puts back a token; an operation path calls an application helper
3. Materialization and `cc-mark-not-lvalue` are different transitions, especially for an already-loaded legacy local

### C13-05 hints

1. Every displacement uses field offset plus four, regardless of opcode length
2. Both conditional jumps reach the same result block; the unconditional jump goes past it
3. Recovering fE first does not patch it first. It waits on the builder data stack while the false-target fixups are consumed

### C13-06 hints

1. The conditional jump selects the false-arm start, while the unconditional jump bypasses the false arm
2. Each arm's value is retained as a value, rather than replaced with its truth
3. The true arm is materialized before its end jump is emitted, even if a particular generated execution will take the false branch

### C13-07 hints

1. Apply promotion, pointer choice, width choice, then the equal-width branches in that order
2. Before `MOV RCX,RDI`, RDI holds the right operand; after the pop it holds the left
3. Shifts replace the preliminary common type with the promoted left type. Provider gates are a separate question from that local rule

## Checked solutions

### C13-01 — Find the consumer

Subtraction is row **4**: multiplication, division, remainder, addition, then subtraction. The row begins at `B + 4×40 = B+160`. Its emitter cell is at **B+184**; its evaluator cell is at **B+192**.

Executing the token stored at B+184 invokes `cc-emit-sub-rdi-rcx`, which appends the instruction for future RDI←left−right. It does not immediately subtract two C runtime values inside the builder. Executing the evaluator token at B+192 invokes Forth `-` on builder operands now. The two column addresses are builder storage, not target addresses embedded by the ordinary operand-staging pattern.

The token handoff has four relevant states:

| Event | Current token | Pending flag | Consequence |
|---|---|---|---|
| Multiplication inspects the next token | `+` | Clear | Its row exists, but its level is additive |
| Multiplication exits its loop | `+` | Set | Caller owns the decision to put it back |
| Addition calls next-token-keep | Same `+` | Clear | No source-byte advance for this replay |
| Addition accepts its row | `+` was consumed | Clear | It proceeds to parse the right operand |

The next right-operand read obtains a subsequent token, unless that operand parser has its own justified putback activity. There is no extra copy of plus to remove.

**Changed case.** `+=` is not a key in `bo-op`, so ordinary additive lookup returns zero and the caller hands it back. The assignment consumer uses `bo-compound` and can find the addition row through `pt-plus-eq`. That shares an arithmetic emitter; it does not make assignment part of the additive grammar.

**Wrong path and repair.** B+44 mixes one-cell offsets with a forty-byte row stride. Treating emitter execution as an immediate arithmetic result mixes phases. Write one address equation and one sentence naming the called word's action, then retry the compound-token case without the table open.

### C13-02 — Complete the missing staging

At the requested stop for `1+r*2`, r=2:

- Builder saved rows: `[row+, row*]`
- Generated expression temporaries: `[1, 2]`
- Future RDI: 2, from the final literal
- Current expression metadata describes that literal; it no longer describes the earlier local `r`

The inner application proceeds first. Its right materialization is a no-op for the literal. `MOV RCX,RDI` gives RCX=2. `POP RDI` retrieves multiplication's left two and leaves `[1]`. Multiplication produces RDI=4. The helper resets expression metadata to a plain legacy value. Its saved row* has been consumed, leaving builder row+.

The outer application then materializes the completed right value, copies four into RCX, and pops one into RDI. The generated temporary list becomes empty. Addition produces five and again publishes a plain value. The builder has no remaining saved row for this expression.

The builder stacks exist while it emits these instructions. The numeric temporary list and register values describe the later generated-machine execution under the supplied r=2 premise. The builder need not know that value to emit the sequence.

**Changed case.** For `1-r*2` with r=3, the corresponding stop is builder `[row−, row*]`, generated `[1,3]`, future RDI=2. Multiplication copies right two to RCX, pops left three, and yields six. The outer subtraction copies right six to RCX and pops left one into RDI, yielding **1−6=−5**. Both stacks' lesson-owned saves balance.

**Wrong path and repair.** Six for the original case applies addition too early. Five for the changed case may indicate reversed final subtraction. Reconstruct the move-right/pop-left pair before each arithmetic step; then explain the changed result without relying on multiplication's commutativity.

### C13-03 — Explain the grouping

For `t.rows-1-r`, the first left operand materializes G into four and is pushed. The right multiplication parser produces one, sees the second minus, finds an additive rather than multiplicative row, and returns it pending. The **outer additive parser** applies the first subtraction before consuming that pending minus in its next loop iteration.

| Stage | Generated temporaries | Future RDI/RCX |
|---|---|---|
| Save first left | `[4]` | RDI=4 |
| Finish first right | `[4]` | RDI=1 |
| Recover and subtract | `[]` | RCX=1, RDI=4 then 3 |
| Save completed left | `[3]` | RDI=3 |
| Finish second right | `[3]` | RDI=2 |
| Recover and subtract | `[]` | RCX=2, RDI=3 then 1 |

The grouping is `(4−1)−2`, and the result is **1**. Each application removes exactly its own staged left value.

**Changed case.** In `t.rows-(1-r)`, the outer left four is saved, but the right child encounters parentheses and re-enters assignment grammar, which includes addition. While parsing the inner subtraction, generated temporaries become `[4,1]`: outer four remains saved while inner one is staged. This is the first additional push that the unparenthesized trace does not perform. The inner application yields `1−2=−1` and leaves `[4]`. The outer application then yields `4−(−1)=5`, leaving `[]`.

For `1+r<<1`, addition is tighter than shift. With r=2, the additive child yields three; the shift layer stages that value and obtains count one. The grouping is **(1+2)<<1**, predicting **6** under this small bounded integer fixture.

**Wrong path and repair.** Saying the unparenthesized expression yields five silently lets a multiplication child consume subtraction, or silently chooses right association. Mark each parser's allowed token set on the source, then repeat only the changed grouping case. Parentheses are a grammar re-entry, not a numeric sign change.

### C13-04 — Preserve a place until needed

At return from logical OR, before any public expression materialization:

| Input | Future RDI meaning | K | S | T / D | Field load emitted? |
|---|---|---|---|---|---|
| `t.rows;` | Target address G | `lv-deref` | sentinel | int / 0 | No |
| `t.rows+0;` | Numeric value 4 | `lv-value` | sentinel | 0 / 0 | Yes |

In the first case every enclosing binary/logical layer declines its operator and preserves the unary child's pending-address state. In the second, additive matching justifies materializing the left field. The parser still stages four, obtains zero, and emits addition. Default application then resets seven metadata cells, including T and D. A zero literal does not turn this parser into a constant-folding identity optimization.

**Changed case.** For bare local `r;`, future RDI already holds two: K=`lv-local`, S=4, T=int, D=0. For `r+0;`, the matching additive parser calls materialize, but the local is already loaded and that call does not erase its slot identity. The actual binary application later publishes K=`lv-value`, S=sentinel, T=0, D=0, with future RDI still two.

Both changes therefore preserve the *numerical* value under the supplied premises while changing the expression's *destination metadata*. Passing through a parser is not the same operation as consuming an operator.

**Wrong path and repair.** Marking the bare field a value moves materialization to the wrong owner. Giving `r+0` slot 4 preserves an identity after an operation that resets it. If these were confused, use two colored labels or two text columns, “materialize” and “publish operation result,” and place each mutation in the right column. Color is optional; the names carry the distinction.

### C13-05 — Patch and select

The supplied coordinates give:

- fL displacement: `132−(100+4) = 28`
- fR displacement: `132−(116+4) = 12`
- fE displacement: `139−(128+4) = 7`

All are positive forward displacements. Little-endian fields would contain `1C 00 00 00`, `0C 00 00 00`, and `07 00 00 00`, respectively. These bytes are derived arithmetic, not observed emitted output.

The patching sequence shows why return-stack order is not patch order:

| Action | Builder data-stack saved fixups | Builder return-stack saved fixups |
|---|---|---|
| All placeholders emitted | `[]` | `[fL,fR,fE]` |
| First two `r>` | `[fE,fR]` | `[fL]` |
| Patch current false target using fR | `[fE]` | `[fL]` |
| Recover fL | `[fE,fL]` | `[]` |
| Patch same false target using fL | `[fE]` | `[]` |
| Emit zero, patch join using fE | `[]` | `[]` |

For p=0, the first JZ reaches the zero block, so the pointee load and second test are skipped; result zero. For p=P with `[P]=6`, both conditional branches fall through; the one result is loaded, then the end jump bypasses zero; result one. For p=P with `[P]=0`, the first branch falls through, the pointee load runs, and the second JZ reaches the zero block; result zero.

**Changed case.** OR emits **JNZ** to the shared **one** block, while its fall-through path produces **zero** before the end jump. With corresponding block positions its displacement arithmetic is unchanged, though the jump conditions and result constants differ.

For `p || *p`, a nonzero valid p skips the pointee load and gives one. With p=0, OR reaches `*p`; this fixture supplies no valid readable object at the null pointer. There is therefore **no safe numerical prediction for that dereference path** from these premises. It would be wrong to carry AND's null-pointer protection over to OR. A separate scalar expression such as `a || b`, with valid scalar producers and a=0, b=6, would reach b and produce one.

Every RHS is still parsed. A generated branch cannot make malformed syntax or an unknown identifier disappear from the builder's input.

**Wrong path and repair.** Patching fE to the shared result block instead of past it overwrites the earlier result path. Treating OR as a safe null guard reverses its decisive condition. Write the branch predicate beside each arrow, then follow one zero and one nonzero case before reattempting without the worked table.

### C13-06 — Keep the selected value

The conditional parser owns fFalse and fEnd. After the condition's test it saves fFalse; after emitting the true arm it saves fEnd above it. It checks the colon, recovers fEnd then fFalse, patches fFalse to the false-arm start, and saves fEnd again during false-arm parsing. The legacy continuation finally patches fEnd to the join and marks a non-lvalue result.

For r=2, the zero branch is not taken, so true-arm four is produced and the end jump skips nine. For r=0, the zero branch skips the true arm and its end jump, reaching false-arm nine. The results are **4** and **9**, not one and zero. Conditional choice retains the selected arm's value; logical operators publish normalized truth.

If `?` is absent, the conditional parser puts back the inspected token and leaves the logical-OR child's expression state unchanged. That may still be a destination state.

**Changed case.** For `r ? t.rows : 9`, true-arm parsing publishes the field's pending address. The conditional parser materializes it **before** appending the end jump. Under the fixture, this produces four on a true runtime path. With r=0, the first branch skips both true-arm address formation/load and its end jump, producing nine instead.

The builder still parses `t.rows`, performs its name/field lookup, emits its address and load sequence, checks the colon, and parses nine. Runtime reachability does not remove these source obligations.

**Wrong path and repair.** Returning one for r=2 imports the logical-normalization rule into a different operator. Placing true-arm materialization after the join could affect both paths. Name each region's owner and put the materialization inside its selected arm before redrawing the branches.

### C13-07 — Typed pipeline, optional

The requested common-type selections under the stated LP64 integer defaults are:

| Operand types | Decisive step | Selected common type |
|---|---|---|
| unsigned char + short | Both smaller than four bytes promote | int |
| unsigned int + long | Eight-byte long is wider than four-byte unsigned int | long |
| signed long long + unsigned long | Equal width; long-long branch; one operand unsigned | unsigned long long |

These apply the inspected helper; they do not replace its actual algorithm with an assumed standards rule.

For valid int pointers into the supplied array:

- `p+2`: left P is staged. Right two is scaled by four while in RDI, becoming eight. Then RCX=8, popped RDI=P; addition predicts **P+8**, a pointer result
- `2+p`: left two is staged. Right P is moved to RCX; left two is popped into RDI and scaled by four; addition again predicts **P+8**, a pointer result
- `q-p`: left P+12 is staged, right P goes to RCX, and left is popped. Subtraction yields twelve bytes. The normalization sequence stages that difference, loads step four, arranges RCX=4/RDI=12, and emits signed quotient, yielding **3**, type long

If a corresponding saved inner row width were three for the int-based step calculation, the step would be twelve. A pointer advance by two such rows would advance twenty-four bytes. Descriptor/row information is builder metadata used to choose the emitted scale; it is not a second runtime operand stack.

**Changed case.** For unsigned-int `0x80000000 >>` a long count one, the preliminary common type would select long by width. The shift override replaces it with promoted **unsigned int**. The integer conversions normalize the operands to that representation; unsigned dispatch selects **logical right shift**. The predicted result is **`0x40000000`**, type unsigned int, K=`lv-value`, S=sentinel, D=0. Publication clears old field, null-provenance, and array-count metadata; nonpointer inner width is zero. A long count does not widen the result type.

The parser selects its native binary branch through **`cc-target-lp64`**. `121`'s ranked-array checks and pending local production use **`cc-target-sysv`**, with the array checks additionally requiring array-based operand types. Merely setting LP64 does not establish that those System V operations are active. With the later providers loaded, common-type and truth-test wrappers must also be followed through `131` and `127` for their actual value-category contracts.

**Wrong path and repair.** Scaling P instead of integer two confuses operand meaning at the register boundary. Giving the shift a signed-long result misses the local override. Treating every LP64 local as pending ignores the provider gate. Repair one distinction at a time, then repeat a different pointer order or shift-left type without the answer table.

## What a successful attempt establishes

A correct trace with references demonstrates supported performance on these mechanisms. A fresh changed-case attempt without the worked solution is stronger evidence of independent use. Neither establishes general compiler correctness or long-term retention. If your arithmetic was right but your stack owner or metadata was wrong, keep that distinction visible in one more attempt; the next chapter depends on those lifetimes when assignment has to preserve an outer destination.
