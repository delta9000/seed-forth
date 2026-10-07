# 13. Precedence and short-circuit expressions

[Previous: Places, values, and delayed loads](12-places-values-and-delayed-loads.md) · [Practice help](../practice/13-solutions.md)

The triangle program computes `1 + r * 2`. If `r` is two, the intended result is five. Reading the tokens from left to right and immediately applying every operator would instead compute `(1 + 2) * 2`, giving six. We need a reason the multiplication finishes first.

There is a second problem hiding in `p && *p`. The builder must read the whole expression, including `*p`, but the generated program must avoid the pointee load when `p` is zero. Choosing an arithmetic order and choosing an execution path are related parsing jobs with different emitted mechanisms.

This chapter follows both jobs from tokens to instructions. By the end, you should be able to identify which parser owns an operator, track a saved left operand through nested parsing, explain left association using subtraction, and connect each short-circuit branch to the builder that patches it. You will also be able to distinguish an unchanged operand state from the new value published after an operation.

**Edition and evidence.** All implementation links pin [`bbcc1732152af2d884737272eed870d2410ffe8e`](https://github.com/delta9000/seed-forth/tree/bbcc1732152af2d884737272eed870d2410ffe8e). The central source is [`100-cc-expr.fth`, operator table through conditional parser](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1628-L2198). Traces are manual derivations from inspected source, not compiler or generated-program runs. No build, Forth example, C example, or bootstrap was executed for this chapter. Bounded numerical examples avoid overflow, invalid shifts, and division faults; they are not a general correctness or language-conformance claim.

## Choose your route

The main route uses the default legacy profile: `cc-target-lp64=0` and `cc-target-sysv=0`. Read through **A conditional chooses an arm**, then try C13-01 through C13-06. The optional **Typed depth** section opens the LP64 branches in the same parser; it is not required to predict five from the triangle expression. Experienced readers can attempt the stack and branch exercises first and return to the transition they cannot justify.

Bring three earlier contracts:

- [C06](06-tokens-and-lookahead.md): the current token is a record; putting it back makes that record pending, without rewinding source bytes
- [C09](09-instructions-inside-an-executable.md) and [C10](10-calls-literals-and-deferred-addresses.md): an emitter appends bytes; a branch fixup identifies a field to patch later
- [C12](12-places-values-and-delayed-loads.md): an expression can publish a value or an address awaiting a load, and the consumer decides when to materialize it

Try this entry check before reading the refresh:

1. Does putting back the current token create a second token?
2. If `t.rows` publishes a pending target address, what must a numeric addition consumer do before saving its left operand?
3. A relative branch's four-byte displacement field starts at file offset F. From which offset is its displacement measured?

The [entry-check feedback](../practice/13-solutions.md#entry-check) is separate. If one answer is uncertain, repair that particular contract; you do not need to restart the compiler book.

## Typed updates now have two seams

`cc-native-inc-dec` calls `cc-change-check-fwd` before inspecting the lvalue
and delegates the new payload to `cc-change-value-fwd`. The default still scales
pointer steps by pointee size. It converts from the promoted type back to the
destination: for `_Bool b=1`, `b++` stores 1 and `b--` stores 0. Floating and
x87 providers replace these hooks; the existing integer/pointer traces keep
their inputs. See [the update path](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L984-L1026).

## One builder, one future program

Our recurring fixture supplies the symbol and storage facts that C15 will later construct. In the legacy profile, local `r` occupies slot 4 and contains two; its address is `RBP−40`. A global `struct tri` object `t` has target address G. Its `rows` field is at offset zero and contains four. Its `stars` field is at offset eight. All referenced storage is valid. Declaration syntax is not a prerequisite for this trace.

Use C12's metadata notation: K is lvalue kind, S is local slot, T is encoded type, and D is associated descriptor. The remaining cells are Q, qualification; F, field record; N, null provenance; A, array count; and I, row width. These are **nine builder cells**, with five possible kinds: `lv-value`, `lv-local`, `lv-deref`, `lv-deref-byte`, and `lv-temporary`. We will display only the relevant fields, not pretend the other cells disappeared.

For bare `r`, the legacy producer appends a load and publishes K=`lv-local`, S=4, T=int, D=0. Future RDI therefore holds two. Materialization ordinarily adds nothing for this already-loaded local. For `t.rows`, future RDI initially holds G, with K=`lv-deref`, S=sentinel, T=int, D=0. Here materialization appends a qword load and changes K to `lv-value`, retaining the type. The sentinel is Forth `true`, whose value is −1; it is not a target address.

The [`cc-emit-materialize` contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L259-L297) calls the array-decay hook, then loads only a pending dereference. It is not a universal reset of assignability. An actual default binary operation later calls `cc-mark-not-lvalue`, which writes K=`lv-value`, S=sentinel and clears the other seven cells. Keep those two transitions separate.

We also need separate stack names:

| State | Owner and lifetime | Contents in this chapter |
|---|---|---|
| Builder data stack | Forth, during parsing | Lookup arguments; LP64 left metadata saved across recursive parsing |
| Builder return stack | Forth, during parsing | Saved operator row addresses or branch fixup offsets, alongside ordinary call machinery |
| Generated operand stack | Future machine, during expression execution | Left operand values stored by emitted `PUSH RDI` instructions |

When we write a stack as `[a, b]`, the rightmost item is the top. Builder stack diagrams show the lesson's saved items only, omitting ordinary return addresses and unrelated surrounding state. Generated-stack diagrams show expression temporaries above a stable baseline, omitting the function's frame and return address. No operator-table address or builder descriptor is pushed into the generated program by this staging pattern.

## A ladder of promises

Each ordinary binary parser first asks a tighter parser for an operand. It then repeatedly consumes its own operators and asks that tighter parser for the right operand. The following table runs from tightest to loosest:

| Level | Parser suffix | Operators | Child that parses one operand |
|---:|---|---|---|
| 1 | `mul` | `* / %` | `unary` |
| 2 | `add` | `+ -` | `mul` |
| 3 | `shift` | `<< >>` | `add` |
| 4 | `rel` | `< > <= >=` | `shift` |
| 5 | `eq` | `== !=` | `rel` |
| 6 | `bit-and` | `&` | `eq` |
| 7 | `bit-xor` | `^` | `bit-and` |
| 8 | `bit-or` | `\|` | `bit-xor` |

Every suffix names `cc-parse-SUFFIX`. Above these come logical AND, logical OR, the conditional `?:`, and assignment. They have dedicated control flow rather than ordinary table rows.

For now, `cc-parse-unary` has a bounded promise: parse one prefix/postfix/primary operand and publish its future RDI meaning plus metadata. A number, `r`, `t.rows`, `*p`, or a parenthesized expression can satisfy that promise. C12 taught the relevant place producers; C14 opens the complete operand, call, update, and unary dispatch. The promise does **not** say every operand is already loaded or already a non-lvalue.

The outside entry is profile-dependent. In legacy mode, `cc-parse-expr` parses assignment grammar and then materializes. With LP64 enabled, it parses comma grammar and then materializes. Parentheses use assignment grammar in legacy mode and comma grammar in LP64 mode **without that final mandatory materialization**, preserving C12's destination state. C14 completes those outer grammars. The file's opening grammar comment describes the older, smaller shape; the bodies and target branches determine this edition's contract.

Some calls use deferred words such as `cc-parse-assign-fwd` because a grouping or conditional parser must re-enter a grammar whose definition appears later in the Forth file. The final bindings connect those calls to their parser words. This is a definition-order mechanism, not a stored syntax tree. The parser immediately appends code while it walks the token stream; our grouping notation describes the computation it emits, not an AST that it allocates.

### No match means no new expression

Suppose the input is bare `t.rows;`. The unary child returns its pending address. Each of the eight ordinary binary layers sees the semicolon rather than its own operator. It hands that token back and returns **the same expression state**. Logical AND, logical OR, and conditional parsing likewise leave that state intact if their operators are absent.

This identity case matters. If every level unconditionally loaded or marked a new value, a later assignment parser could lose the destination before it saw `=`. A layer earns the right to consume its left operand as a value only when it has recognized an operation that requires one. The final public expression consumer may still materialize; that is a separate owner.

## The operator table records choices

The eight repeated shapes differ in which tokens they accept and how they combine values. Their shared table has sixteen operator rows, five eight-byte cells per row:

| Byte offset | Field | Meaning |
|---:|---|---|
| 0 | `bo-op` | Ordinary punctuation code, such as `+` or `pt-shr` |
| 8 | `bo-compound` | Assignment punctuation code, such as `pt-plus-eq`, or zero |
| 16 | `bo-level` | One of the eight numeric levels |
| 24 | `bo-emitter` | Forth execution token of an instruction-emitting word |
| 32 | `bo-eval` | Forth execution token of an immediate arithmetic word |

Thus `bo-size` is **40 bytes**, not five bytes. The ordinary rows occupy 640 bytes. A final zero `bo-op` cell terminates the table; the lookup checks that cell before inspecting another field, so the sentinel needs no complete forty-byte record.

Here are the adjacent addition and subtraction rows, exactly as they occur in [`cc-binops`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1664-L1682):

```forth
char +      pt-plus-eq     level-add      cc-binop, cc-emit-add-rdi-rcx    +
char -      pt-minus-eq    level-add      cc-binop, cc-emit-sub-rdi-rcx    -
```

[`cc-binop,`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1663-L1665) receives the first three fields on the builder data stack. `rot , swap , ,` stores them in op/compound/level order. The two following `' ,` operations read the emitter and evaluator names, resolve their Forth execution tokens, and store those tokens. This happens while the compiler's table is being defined, not when a generated C program evaluates addition.

The two last columns answer different questions:

- Executing `cc-emit-add-rdi-rcx` **now** appends instructions predicted to compute RDI←RDI+RCX **later**
- Executing the Forth `+` evaluator computes a builder-cell result **now** from two builder operands

A runtime parser selects `bo-emitter`. C14's constant parser selects `bo-eval`, with its own state, checks, and typed/provider branches. Sharing a row does not establish equivalence over every overflow, shift, conversion, or error case. In particular, the source's signed-division helpers are not part of this chapter's runtime parsing path.

The default multiplicative rows select signed multiply, signed quotient, or signed remainder emitters. Shift rows select left shift and arithmetic right shift; relational/equality rows select comparisons returning zero or one; bitwise rows select AND, XOR, or OR. Those instruction bodies use C09's register contract. The table chooses a body; the native chooser below may substitute an unsigned alternative.

The compound field lets C14 locate the same arithmetic operation for `+=` or `-=`. It does not make `+=` an additive token here: ordinary lookup searches `bo-op`, not `bo-compound`. The four relational and two equality rows have zero compound fields. Logical and conditional operators are absent because computing both operands before applying one arithmetic instruction would defeat their control-flow contract.

## One token can pass through several levels

[`cc-binop-row`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1687-L1699) takes a key and field offset. It saves the offset on the builder return stack, starts at `cc-binops`, checks the sentinel, and compares the selected field. A match returns that row's builder address. A miss advances forty bytes; reaching the sentinel returns zero. Its temporary field offset is removed on either return.

[`cc-binop?`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1700-L1716) adds three decisions:

1. Call `cc-next-token-keep`
2. If the token is punctuation, look up `tok-num` in `bo-op`
3. Return the row only if its stored level equals the requested level

A nonpunctuation token, an unknown operator, or another level's operator returns zero. The helper leaves that token current. **Its caller puts the token back.** This division of responsibility avoids pretending that a failed table search restores the whole lexer.

For `1 + r * 2;`, after the first operand the multiplication parser inspects `+`. The token has an additive row, so it is the wrong level. The multiplication parser sets the pending flag and returns. The addition parser's next-token call clears that flag and sees the same `+`, without advancing source bytes, then consumes it as its own operator.

After parsing the final `2`, the semicolon can similarly be inspected and handed back by multiple enclosing levels. There is still one current token record and one pending bit, not a stack of copied semicolons. Each next-token call either replays the current record or obtains a new one. C06's [two small interface words](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/050-cc-lex.fth#L646-L666) implement that distinction.

## One complete binary template

This is [`cc-parse-add`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1898-L1914), with its source comments retained:

```forth
: cc-parse-add
  cc-parse-mul
  begin,
    level-add cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-target-lp64 @ if,
      cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    then,
    cc-emit-push-rdi                              \ save left
    cc-parse-mul                                  \ rdi = right
    r> cc-target-lp64 @ if, cc-native-binop-apply else, cc-binop-apply then,
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many
```

Read the loop boundary before the arithmetic. `dup` leaves one row for the body while `while,` consumes its truth test. On failure it leaves one zero, which the final `drop` removes. On success, `>r` saves the row while recursive parsing uses the data stack. The matching token is already consumed; materializing the left operand is now justified.

The LP64 block saves five metadata cells on the **builder data stack**: type, descriptor, row width, null provenance, and qualification. Legacy mode skips it. Either way, `cc-emit-push-rdi` appends a **future machine push**. It does not save the builder's row or type. The child then parses the right operand; shared expression metadata now describes that right operand.

After the child returns, `r>` restores the saved row. Legacy application follows this complete body:

```forth
: cc-binop-apply
  cc-emit-materialize                             \ right must be a value
  cc-emit-mov-rcx-rdi                             \ rcx = right
  cc-emit-pop-rdi                                 \ rdi = left
  bo-emitter + @ execute                          \ rdi = left OP right
  cc-mark-not-lvalue ;
```

The [source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1862-L1870) therefore establishes a strict operand order: materialize right, copy it to RCX, recover left into RDI, apply left OP right, publish a plain value. Subtraction will make a reversed copy/pop unmistakable.

All eight levels use this shape. Multiplication's child is unary; each next level uses the preceding level in the ladder. This explains precedence: a tighter child must finish before its caller can apply the waiting operator. Repeating the caller's loop explains **left association**: the completed result becomes the left operand of the next operator at the same level. Recursion and iteration do different jobs.

## Trace `1 + r * 2` from both sides

Assume the supplied legacy fixture, so `r=2`, and an initially empty generated temporary stack. Name the table row addresses row+ and row*. These names are symbolic builder addresses, not runtime values. Parsing begins down the ladder until the unary producer emits literal one.

| Step | Builder's action and saved rows | Instructions' predicted future effect |
|---:|---|---|
| 1 | Multiplication declines `+`; addition receives it and saves `[row+]` | RDI=1, temporaries `[]` |
| 2 | Addition materializes its literal and appends the left push | RDI=1, temporaries `[1]` |
| 3 | Its multiplication child parses local `r`; that child's `*` matches and adds row*, giving `[row+, row*]` | Local load gives RDI=2; temporaries remain `[1]` |
| 4 | Multiplication materializes the already-loaded local and appends its push | RDI=2, temporaries `[1, 2]` |
| 5 | Multiplication's unary child emits literal two | RDI=2, temporaries `[1, 2]` |
| 6 | Restore row*; materialize RHS, emit move-right/pop-left/multiply; builder rows return to `[row+]` | RCX=2; pop makes RDI=2 and temporaries `[1]`; multiply gives RDI=4 |
| 7 | Multiplication hands back `;`; addition restores row+ and applies it | RCX=4; pop makes RDI=1 and temporaries `[]`; add gives RDI=5 |
| 8 | Addition and outer levels decline `;` and return | RDI remains 5; no outstanding expression temporaries |

At step 3 the loaded `r` is still K=`lv-local`, S=4. Step 4's materialization does not erase that identity. Step 6's **operation** does: default application resets the result to K=`lv-value`, S=sentinel, with the other seven cells zero. Addition does the same at step 7. There is no surviving destination for the arithmetic result.

The source order of the appended arithmetic is multiplication then addition. The builder never had to know the runtime value of `r`; two is our supplied premise for predicting the later machine state. A different valid stored value changes the predicted arithmetic without changing the parser's row ownership.

If you lose the trace, stop at step 5 and copy only this checkpoint: builder rows `[row+, row*]`; generated temporaries `[1, 2]`; future RDI=2. The next question is “Which row returns first, and which saved operand does its emitted pop retrieve?” This is enough to resume without rereading every lexer step.

## Subtraction exposes association and operand order

Now parse `t.rows - 1 - r;`, still with rows=4 and r=2. The grouping implied by the additive loop is `(t.rows - 1) - r`.

The first unary result is the pending address G. The multiplication layer finds no operator and preserves it. On seeing the first minus, addition saves row−, materializes `t.rows`, and appends the left push. Future execution loads four and saves `[4]`. The right multiplication child obtains literal one and stops at the second minus, handing that token back. Application copies right one to RCX, pops left four into RDI, and emits subtraction, yielding three with no temporary left.

The additive loop then sees the second minus. It saves the row again and pushes the **previous result**, three. Its child loads local `r`, producing two. Application puts two in RCX, retrieves three into RDI, and subtracts, giving one. The generated temporary stack is empty again.

| Application | Left recovered into RDI | Right copied into RCX | Result |
|---|---:|---:|---:|
| First minus | 4 | 1 | 3 |
| Second minus | 3 | 2 | 1 |

At no time does the right child consume `1-r` as one additive operand: the child is multiplication, not addition. A right-recursive additive grammar would produce a different grouping; this implementation uses a loop. Explicit parentheses can re-enter the wider grammar, so `t.rows - (1 - r)` has a different path. C12's grouping preserves the inner result for its outside consumer rather than imposing a load merely because parentheses occurred.

The same ladder explains `1 + r << 1`: addition completes before shift. The shift emitter uses the low byte CL of RCX as its instruction operand, with x86-64's count masking at execution. That machine contract is not permission to assign meaningful C semantics to arbitrary out-of-range shifts. Our exercises use small valid counts.

The relational and equality emitters compare left RDI against right RCX and return zero or one. Bitwise AND, XOR, and OR operate on both computed operands. Unary `&` is recognized where an operand is expected; binary `&` is recognized after a completed left operand. Token spelling alone does not determine that role.

## Short-circuiting is emitted control flow

For `p && *p`, supply a legacy local `int*` pointer `p` in slot 5. It is either zero, or a valid pointer P to a readable legacy integer. In the nonzero cases below, the pointee is six or zero. The parser does not know which case will occur.

After the lower levels parse `p`, no matching binary operators have changed its metadata. Logical AND recognizes `&&` and only then materializes its left operand. The legacy local was already loaded. The default `cc-value-test-fwd` appends `TEST RDI,RDI`; JZ will branch when the value is zero.

The key placement is next: the first conditional jump is appended **before the RHS's code**. The builder still calls the RHS parser. Unary `*p` obtains the pointer value and publishes a pending pointee address; the lower binary levels preserve it. Logical AND's right-value consumer then materializes, placing the pointee load after the first jump. The generated program can skip that load even though the builder had to parse it.

### Three fixups, one owner

Name the offsets of the three displacement fields fL, fR, and fE. Each is a builder-side output-file offset returned by a placeholder emitter. The [`&&` body](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2076-L2100) owns them until their targets are known:

| Emission point | Builder return-stack saved items | Purpose |
|---|---|---|
| After testing left | `[fL]` | First JZ skips RHS and reaches the false block |
| After parsing, materializing, and testing right | `[fL, fR]` | Second JZ also reaches the false block |
| After emitting result one | `[fL, fR, fE]` | Unconditional jump skips the false block |

The generated layout, in order, is: left code; test; JZ to false; right code; test; JZ to false; load one; JMP to join; false block loading zero; join. This is a symbolic summary of the emitted layout, not a claim of a recorded disassembly.

At the false-block boundary, the source performs:

```forth
    r> r>                                         ( f-end f-RHS ; R: f-LHS )
    cc-patch-rel32-to-here                        \ patch f-RHS
    r>                                            ( f-end f-LHS )
    cc-patch-rel32-to-here                        \ patch f-LHS
    [lit] 0 cc-emit-mov-rdi-imm32
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-int-value
```

The first `r>` recovers fE onto the builder data stack; the second places fR above it. Patching consumes fR and leaves fE. Recovering and patching fL still leaves fE. Only after appending the zero result does the final patch consume fE. Both conditional jumps reach the same false block; the unconditional jump reaches the join after that block. The original return-stack saves are balanced.

C09's [patch contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L388-L439) writes displacement `target−(field_offset+4)`. A JZ placeholder has two opcode bytes followed by the field; JMP has one. The returned offset identifies the field, not the opcode, and is neither a target virtual address nor an address to be evaluated by the C program.

### Follow the future branches

| Supplied runtime state | First JZ | Pointee load? | Second JZ | Result |
|---|---|---|---|---:|
| p=0 | Taken to false | Skipped | Skipped | 0 |
| p=P, memory at P is 6 | Not taken | Loads 6 | Not taken | 1 |
| p=P, memory at P is 0 | Not taken | Loads 0 | Taken to false | 0 |

A nonzero result is normalized to one; the expression does not return six or P. `cc-mark-int-value` publishes K=`lv-value`; in legacy mode the reset leaves T zero, while LP64 explicitly publishes int type. In both modes this is a logical result rather than the original pointer destination.

Replacing `&&` with bitwise `&` removes this branch protection: both operands are evaluated by the ordinary fold. Likewise `(p != 0) & (*p != 0)` computes two comparisons before AND. Do not use a null pointer as a safe execution premise for those expressions. A malformed RHS or unknown name is still parsed and can be rejected even in a logical expression whose generated left value would skip it. Runtime skipping is not source skipping.

### OR reverses the decisive branch

[`cc-parse-log-or`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2102-L2126) uses the same three-fixup ownership pattern but emits JNZ to a **true** block. It emits zero on the fall-through path, jumps over that block, and emits one at the shared true target.

For `a || b`, nonzero `a` skips `b`; zero `a` reaches it. The child is logical AND, so `a || b && c` gives AND the tighter grouping. Each logical parser also loops: after one operation, its normalized result becomes the left side of another operation at the same level. Additional branches may be emitted, but no ordinary operand-stack push is needed merely to retain a logical left value. Its truth has already selected a branch.

## A conditional chooses an arm

The conditional parser first obtains a logical-OR condition. Without `?`, it puts back the token and preserves that condition's state. With `?`, it materializes and tests the condition, appends JZ to the future false arm, parses/emits the true arm, and appends a jump past the false arm.

For the bounded legacy expression `r ? 4 : 9`, the generated structure is:

| Region in output order | Effect or destination |
|---|---|
| Condition and test | Obtain r and test for zero |
| Conditional jump | Go to false-arm start if r is zero |
| True arm | Produce four |
| End jump | Skip the false arm |
| False arm | Produce nine |
| Join | Continue with the selected result in RDI |

There are two saved fixups. After the true arm, the parser checks for `:`; a wrong token kind or punctuation reaches error 117. It recovers the end fixup and false fixup, patches the false fixup to the current position, and saves the end fixup again while parsing the false arm. On the legacy path it patches the end fixup after the false arm and calls `cc-mark-not-lvalue`. With r=2 the predicted result is four; with r=0 it is nine. Unlike a logical result, the selected value is not normalized to zero or one.

Both arms are parsed. Their complete grammar is C14's next lesson: legacy uses assignment grammar for both; LP64 uses comma grammar for the true arm and assignment grammar for the false arm. Those recursive calls also support a conditional nested in an arm. We are establishing the branch skeleton here, not substituting “two arbitrary unary operands” for the actual grammar.

The [LP64 continuation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L2145-L2198) must retain the true arm's five metadata fields while parsing the false arm. After both types are available, a scalar conversion join or an aggregate handler completes the result. The aggregate handler's protocol is “consume the saved metadata and end fixup and publish the result if handled; otherwise leave them for the scalar continuation.” Its default returns false. C14 opens the scalar split/join sequence; G15 opens the record snapshot provider. Do not apply the legacy one-jump join as an exact instruction layout for every native conditional.

## Typed depth: preserve meanings across the same recursion

The parser's LP64 branch is controlled by **`cc-target-lp64`**. The System V providers additionally use **`cc-target-sysv`**. LP64 storage gives int four bytes and long/pointer eight; it does not by itself imply every System V callback is active. These distinctions were introduced in C07 and C12.

### Saved metadata is durable; scratch is temporary

Before parsing the right operand, each binary loop materializes the left and leaves five builder cells on its data stack, in order: T, D, I, N, Q. These facts survive the child's changes to `cc-last-*`. The table row is independently protected on the builder return stack. The left **machine value** is independently protected by the emitted push.

After recursion, `cc-native-binop-apply` first saves the row in `cc-expr-op-row`, materializes the right, and calls `cc-expr-save-native-types`. That helper consumes the saved left facts and copies the current right facts into the `cc-expr-left-*` and `cc-expr-right-*` scratch cells. There are left/right type, descriptor, inner width, null provenance, and qualification cells, plus `cc-expr-common` and `cc-expr-op-row`.

These scratch cells become safe to use only **after** recursive operand parsing is finished. Nested operations may reuse them earlier. They are neither persistent expression records nor AST nodes. Field-aware materialization can also update the operand's effective type before this snapshot; copying stale pre-load type assumptions would miss that contract.

### The default common-type algorithm

The inspected [helpers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1718-L1790) implement these steps:

1. `cc-expr-promote` leaves a pointer unchanged; a nonpointer smaller than four bytes becomes int
2. `cc-expr-common-type-default` promotes both operands, then chooses a pointer if either is a pointer, preferring the left when both are pointers
3. Otherwise it chooses the wider operand type
4. For equal widths, if either is long long, it selects long long, unsigned when either operand is unsigned
5. For other equal-width cases it selects the right type if the right is unsigned; otherwise it selects the left

This states the implementation's default selection algorithm. A source comment citing a language standard is not a proof of every language conversion rule or legality condition. Additional providers can inspect types or replace common-type selection.

For ordinary integer fixtures, unsigned char plus short promotes both to int. Unsigned int plus signed long selects the eight-byte signed long. Signed long long plus unsigned long selects unsigned long long under the equal-width/rank branch. These are **type-selection predictions**, with actual values and conversions supplied separately.

Shifts have a local override: after the initial common-type calculation and array callback, the apply routine replaces `cc-expr-common` with the **promoted left type**. Thus a long shift count does not make an unsigned-int left operand into long. Relational and equality operations later replace the result common type with int, because the result is a truth value.

### Scaling happens at a particular register boundary

The [native application body](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/100-cc-expr.fth#L1818-L1860) follows this order:

1. Materialize right, recover left/right metadata, and invoke `cc-array-binop-fwd`
2. Apply the shift-type override if needed
3. At additive level, if left is a pointer and right is not, scale right while it is still in RDI
4. Move right to RCX and pop left into RDI
5. For `+`, if left is not a pointer and right is, scale left in RDI
6. Convert left and right to the selected common representation, then emit the operation
7. For pointer-minus-pointer, divide the byte difference by the left pointee step unless that step is one; select long result type
8. Select int for comparisons, convert the result, and publish typed value metadata

`cc-expr-left-step` and `cc-expr-right-step` use the corresponding type and descriptor to find pointee size, multiplying by a nonzero saved row width. The pointee-size helper handles aggregate and ranked-array descriptors and explicitly gives LP64 `void*` arithmetic byte stride. This is the implementation's GNU-style extension, not a claim about portable C pointer arithmetic.

Take valid LP64 int pointers into one array, with p=P and q=P+12. Then `p+2` scales the right two to eight bytes before moving it to RCX; addition predicts P+8. For `2+p`, the pointer reaches RCX first, then the recovered left two is scaled to eight. For `q-p`, subtraction first yields twelve bytes, and the emitted signed division by four yields three elements of type long. A saved row width three would make an int-based step twelve instead of four. These fixtures assume compatible live objects and in-range arithmetic; the scaling routine alone is not a universal pointer-legality checker.

### Conversion, operation, publication

The default conversion hooks in [`090`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/090-cc-emit.fth#L1286-L1338) receive source and destination types. Their integer defaults use the destination width and signedness to truncate and sign- or zero-extend RDI or RCX. Later floating providers need both types. A final `cc-emit-convert-rdi` normalizes the selected result representation before `cc-mark-typed-value` resets metadata and republishes T and D.

`cc-native-binop-emit-default` chooses unsigned alternatives when `cc-expr-common` is unsigned: unsigned quotient/remainder, logical right shift, or unsigned `< <= > >=`. Other operations use the table emitter. The default table's `>>` row is arithmetic right shift, but the logical-shift emitter already exists and is selected here. Pointers are unsigned for this chooser. Equality needs no separate signed comparison.

For unsigned-int u=`0x80000000`, `u >> 1` uses the promoted left type, zero-extended operands, and logical shift, predicting `0x40000000`. For a bounded signed-long value −8, `>> 1` uses arithmetic shift and predicts −4. These are different selected instruction contracts, not a reason to infer that every table row always uses signed arithmetic.

Publication also restores the appropriate supporting facts. `cc-expr-common-desc` selects the left or right descriptor whose type matches the common type for struct/function/array bases; otherwise it returns zero. `cc-expr-common-inner` similarly selects pointer row width, or zero for a nonpointer. Pointer results combine left/right qualification with OR. `cc-mark-typed-value` clears old slot, field, null, and array-count state before these specific facts are republished. A runtime zero arithmetic result does not automatically acquire null-constant provenance.

### Know which provider owns the extension

The callback boundaries are concrete contracts, not unexplained replacements for the core algorithm:

| Boundary | Default and inputs | Named provider and gate |
|---|---|---|
| `cc-array-binop-fwd` | No-op; reads completed left/right metadata and operator scratch | [`121`, `cc-sysv-array-binop`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L777-L805), active for System V operands with array base types; checks ranked-pointer operation/shape compatibility, or raises 237; G03 opens descriptor policy |
| `cc-array-compound-fwd` | No-op; reads completed operand scratch during compound assignment | [`121`, `cc-sysv-array-compound`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L806-L811); its array gate requires pointer left/integral right; C14 owns the caller |
| `cc-array-ternary-fwd` | No-op; receives completed arm metadata through scratch and may adjust common type/descriptor | [`121`, `cc-sysv-array-ternary`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L812-L843), System V gated; checks void/pointer/null/shape cases and combines row qualifiers; C14/G03 open the join/policy |
| Common type, conversions, binary emission | Integer defaults described above | [`127`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/127-cc-binary64.fth#L164-L270) supplies floating choices when its System V-gated scalar float/double predicate matches; otherwise falls back; G10 opens arithmetic and conversion |
| Truth test and final common-type wrapper | Default test emits `TEST RDI,RDI`; common type returns a selected type | [`131`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L404-L447) checks record/opaque-scalar use before chaining to floating providers; its conditional handler can consume the saved-arm protocol; G15 opens value transport |

With these providers loaded, the final common-type binding is `cc-ag-common-type`, which checks scalar eligibility and delegates to `cc-fp-common-type`; that falls back to the default integer helper. The final truth-test binding similarly chains `cc-ag-test` to `cc-fp-test` to the integer test when appropriate. A record's address representation does not authorize treating the record as a scalar truth value.

For an ordinary System V scalar local, [`cc-sysv-local-load`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L285-L290) publishes a pending address instead of immediately loading. The binary loop's materialization still occurs at the right point: after matching an operator, before saving a value. For a typed field, C12's field-load/value-type callbacks can extract and promote it first; G14 owns the bitfield provider. The precedence mechanism remains recognizable precisely because its operand contract included delayed loads from the beginning.

## Practice without looking ahead

There are seven main exercises. The first five test table/token ownership, nested staging, association, unchanged expression state, and short-circuiting. Two additional exercises isolate the conditional join and optional typed/provider reasoning, so neither has to be hidden inside the basic arithmetic trace. Hints, complete solutions, and changed-case feedback are in [C13 practice help](../practice/13-solutions.md).

### C13-01 — Find the consumer

A table begins at builder address B. Number rows from zero. Using the source table, give the address of subtraction's emitter cell and identify what executing it does now. Contrast the evaluator cell. Then trace the current token and pending flag when multiplication rejects `+` and addition accepts it.

Changed case: input is `r += 2;`. Does additive lookup accept `+=`? Identify the column a later assignment consumer needs, without implementing assignment.

### C13-02 — Complete the missing staging

For legacy `1 + r * 2`, r=2, stop just after emitting the final literal. Give the builder saved rows, generated temporary stack, and future RDI. Then list every move/pop/arithmetic transition to the final result. Explain which facts exist while building and which exist only when the output runs.

Changed case: trace `1 - r * 2` with r=3. State the final operand order rather than relying only on the number.

### C13-03 — Explain the grouping

Independently trace legacy `t.rows - 1 - r`, rows=4 and r=2. Name the parser that declines the second minus and the parser that consumes it. Show the temporary-stack balance after each subtraction.

Changed case: use `t.rows - (1 - r)` with the same values. Find the first point where the saved generated operands differ. Then determine the grouping and result of `1 + r << 1`.

### C13-04 — Preserve a place until needed

Compare legacy `t.rows;` and `t.rows + 0;`. Stop both traces at return from `cc-parse-log-or`, before any outside final expression materialization. Give future RDI's meaning, K/S/T/D, and whether the field has been loaded. Explain why arithmetic zero does not make the second case identical to the first parser path.

Changed case: replace `t.rows` with local `r`. Distinguish what materialization does from what actual binary application does.

### C13-05 — Patch and select

For the chapter's `p && *p` layout, suppose displacement-field offsets are fL=100, fR=116, fE=128; the false block begins at 132 and the join at 139. These are supplied paper output coordinates. Calculate all three displacements, then show the builder saved-fixup sequence through patching. Predict result and pointee-load reachability for p=0, p=P with `[P]=6`, and p=P with `[P]=0`.

Changed case: use `p || *p`, retaining those corresponding block coordinates for an independent OR layout. Identify the jump kind, shared block value, fall-through value, and safe pointer premises needed when the RHS executes. Does a generated skip remove the requirement to parse the RHS?

### C13-06 — Keep the selected value

For legacy `r ? 4 : 9`, show the two fixup owners, their patch order, and result for r=2 and r=0. Explain how this differs from logical normalization. State what the parser does if `?` is absent.

Changed case: use `r ? t.rows : 9`, with the chapter's valid object and rows=4. Locate the true-arm materialization relative to the end jump. What does the r=0 runtime path skip, and what does the builder still inspect?

### C13-07 — Typed pipeline, optional

Under LP64 with valid scalar operands, predict the common types of unsigned char plus short, unsigned int plus long, and signed long long plus unsigned long. Then use int pointers p=P and q=P+12 into one array: trace scaling/register placement for `p+2`, `2+p`, and `q-p`.

Changed case: an unsigned-int left value `0x80000000` is shifted right by a long count one. Give the type override, selected shift, result, and publication facts. Finally distinguish the LP64 parser gate from the System V gate that activates ranked-array checks and pending local production.

## Carry these invariants forward

The ladder delegates tighter syntax; the loop folds operators at one level leftward. A rejected token is handed back once by each consumer without duplicating its record. Builder row addresses and metadata survive recursion on builder stacks; generated operand values survive future execution on the machine stack. No AST is required for this emitter.

A level that consumes no operator preserves its child's expression state. An actual scalar operation materializes its operands and publishes a new value. Logical and conditional operations parse their source regions but arrange branches so only the required runtime paths execute. The fixups belong to the builder that emitted their placeholders until their targets are patched.

C14 now has the contracts it needs to complete whole expressions: operand and call parsing, updates, assignment destinations, conditional arms, comma boundaries, and a separate constant evaluator that computes builder values rather than emitting this runtime arithmetic. If you pause here, keep one stack checkpoint and one three-fixup diagram; on returning, reconstruct their next transitions before opening the answers.
