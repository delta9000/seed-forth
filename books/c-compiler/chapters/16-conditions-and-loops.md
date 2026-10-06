# 16. Conditions and loops

The triangle's `line` function contains `while (pad > 0)`, and `main` contains `for (r = 0; r < t.rows; r = r + 1)`. Both repeat work. Yet a `continue` would need different destinations: the `while` must test again; the `for` must first increase `r`. How does a compiler remember those destinations while it is still reading the body?

This chapter follows three kinds of unfinished work: one branch held across a recursive statement call, any number of exits collected in a loop's lists, and a `for` step whose source is read before its instructions can be emitted. You will connect each unfinished item to the parser that owns it and the event that finishes it. The same accounting explains nested loops without treating a compiler variable as a generated-program variable.

## Choose a route and check the entry contracts

Choose a session by the question you want to answer. Each has its own stopping point:

1. **First session: who owns an if's unfinished branch?** Read the entry/evidence contract below, [the two-machine notation](#keep-the-builder-and-the-future-program-separate), [one parser call](#one-parser-call-one-statement), and [if completion](#an-if-has-two-possible-completion-events), including its recursive example. Attempt [C16-01](#c16-01--trace-a-recursive-owner) and **Part A: if layout** of [C16-02](#c16-02--calculate-both-branch-origins). Stop at the [first-session checkpoint](#first-session-checkpoint); known-target branches belong to the next session
2. **Next session: where do loop exits go?** Read [known-target branches](#a-known-destination-still-becomes-a-relative-instruction), [loop-owned lists](#give-each-enclosing-construct-its-own-lists), [while](#a-while-owns-two-exit-destinations), and then [do](#a-do-loop-tests-after-its-body), skipping the intervening for sections for now. Complete C16-02 Part B, [C16-03](#c16-03--separate-three-kinds-of-nesting), and both parts of [C16-04](#c16-04--complete-a-loop-layout). The [switch-depth contrast](#when-a-switch-lies-inside-the-loop) supports C16-03's unwind question; the first loop trace uses zero depths. Stop when you can distinguish while/do continue targets and restore an outer loop's heads
3. **Replay session: how does for preserve the next statement?** With the loop contracts available, read [source versus execution order](#a-for-separates-source-order-from-execution-order) and [step replay](#replay-the-step-without-losing-the-next-statement). Attempt [C16-05](#c16-05--repair-a-replay-account), [C16-06](#c16-06--protect-an-outer-for), and [C16-08](#c16-08--change-the-triangles-behavior-deliberately). Stop when you can separate the saved lexer mark, source length, and outer for scratch
4. **Reference return: which parser gets this token?** Read the [complete dispatcher/profile reference](#close-the-dispatcher-without-hiding-its-other-clients) and attempt [C16-07](#c16-07--select-an-interface-without-importing-its-implementation). This can wait until after replay

If a route is already familiar, try its exercise first and recover only the transition you cannot justify. None requires reading another chapter from beginning to end.

Bring these small contracts as each route needs them; the list-node contract first enters the loop session:

- [C06's token interface](06-tokens-and-lookahead.md): a current token is a record; putting it back makes that record pending without moving the source cursor backward
- [C09's branch interface](09-instructions-inside-an-executable.md#patch-from-the-end-of-the-displacement-field): a rel32 field at output offset q reaches offset T by storing `T−(q+4)`
- [C10's two-cell lists](10-calls-literals-and-deferred-addresses.md#a-node-has-two-builder-cells-even-for-a-four-byte-patch): each arena node holds an output field offset and a next-node pointer; an owner holds the head
- [C13's expression boundary](13-precedence-and-short-circuit.md#a-ladder-of-promises): `cc-parse-expr` emits a runtime expression and materializes its result; it does not calculate the C value on the builder's data stack
- [C15's declaration boundary](15-declarations-and-recursive-records.md#exact-expectations-advance-the-parser): an expectation helper consumes the requested punctuation; a scope pop hides symbol rows but does not reset the local-slot count

Try four entry questions before the refresh. What happens to source position when a pending token is reread? Does calling an emitter immediately run its emitted instruction? Which coordinate does q name? After leaving a block, can we infer that the next local reuses its slots? [Check the entry answers](../practice/16-solutions.md#entry-check).

**Edition and evidence.** The primary source is [112-cc-stmt.fth at `7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth). This chapter owns its statement/compound/condition/loop mechanisms, expression-statement adapter, and core dispatcher. C17 opens switch dispatch, labels, and identifier disambiguation; we name their interfaces here before using them. C10 already opened the generic list append and both patch walkers, which we retrieve rather than silently assume.

The default profile is legacy Linux/x86-64, `cc-target-lp64=0`, `cc-target-sysv=0`, eight-byte builder cells and frame slots, and executable base `0x400000`. Examples assume well-formed bounded source, sufficient builder/target storage, valid initialized objects, and fitting signed rel32 displacements. All byte, parser, and runtime traces are **manual derivations from inspected source**. No compiler build, Forth or C execution, generated-program execution, or bootstrap was performed. The historical [book30](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/30-statements-if-while-for-return.md) supplies context; current definitions settle disagreements. In particular, this edition scans `for` steps as tokens and restores a full lexer snapshot plus a separate source length.

## Keep the builder and the future program separate

Use these conventions throughout:

| Notation | Meaning |
|---|---|
| B.D, B.R | Builder Forth data and return stacks; rightmost item is top |
| `[…]` in a builder trace | Only the lesson's saved cells; ordinary call machinery and unchanged surrounding cells are omitted |
| O or q | Decimal byte offset in the output file; q specifically names a displacement field |
| V | Target virtual address; for this profile `V=0x400000+O` |
| P, S | Symbolic target frame base and stack boundary, never builder node addresses |
| RDI, flags, RSP | State of the future processor executing generated instructions |
| `head=N` | A builder variable contains arena-node pointer N; zero means no node |

Byte lists run from low to high addresses and store multibyte numeric fields little-endian. A minus sign in a displacement describes signed arithmetic; its four stored bytes are the low 32-bit two's-complement representation. A builder `>r` saves a compiler cell; it does not emit a target PUSH. Conversely, `cc-emit-jmp-vaddr` appends a jump; it does not jump within the compiler.

The expression-value test is a deliberately small interface. [`cc-value-test-fwd`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L186-L191) initially calls `cc-emit-test-rdi`. That emits `48 85 FF`, or `TEST RDI,RDI`: future ZF is one for a zero value and zero for a nonzero value. The test preserves RDI. JZ then skips on false; JNZ repeats on true. These are future CPU flags, distinct from a Forth true flag used to select the builder's own `if,` branch. A typed provider can replace the test; selecting LP64 does not authorize assuming all future values are eight-byte integers or that every provider body lives here.

## One parser call, one statement

A body need not begin with `{`. In `while (pad > 0) pad = pad - 1;`, the assignment itself is the body. In `while (pad > 0) { putchar(' '); pad = pad - 1; }`, the compound is one outer statement containing two inner ones.

The statement interface is `cc-parse-stmt-fwd ( -- )`: begin at the next token, or at a token deliberately made pending, and parse the selected statement/declaration unit while appending its code. For the structured forms here, a completed call preserves the caller's builder stack items and stops after its own syntax. A parser may have read a following token and put it back, so “finished” does not imply that the source byte cursor sits immediately after the last semicolon. That distinction becomes essential for `for` replay. Legacy label units have a narrower boundary opened in C17; do not silently use an arbitrary label-prefixed sequence as an example of this promise.

The source solves a definition-order cycle with a deferred word:

```forth
defer cc-parse-stmt-fwd
```

Compound, `if`, and loop words can now compile calls to that named interface before the final dispatcher exists. At the end of the file, this exact binding installs the implementation:

```forth
' cc-parse-stmt is cc-parse-stmt-fwd
```

The quote supplies the Forth execution token; `is` installs that implementation for later calls. This is builder call routing, not an emitted C function pointer or a syntax tree. The [declaration](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L13-L17) and [final binding](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L904-L905) bracket the mutually recursive family.

**Optional provider detail.** [010's deferred-word provider](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L404-L429) stores the installed execution token in a cell reached by the deferred word. Its physical implementation is not needed to follow the recursive statement calls here.

### A compound owns its closing brace

The caller has consumed `{`. The complete [compound parser](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L19-L33) is:

```forth
: cc-parse-compound
  cc-scope-push
  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [char] } = and 0=
  while,
    cc-putback-token
    cc-parse-stmt-fwd
  repeat,
  \ '}' was consumed by the loop test.
  cc-scope-pop ;
```

For `{ int pad; { int n; } pad = 2; }`, let symbol count initially be M. The outer push remembers M; the declaration appends `pad`. The inner push remembers M+1; its declaration appends `n`; its closing brace restores count M+1. The later assignment can still find `pad` but not `n`. The outer closing brace restores M. The scope marker stack changes in the builder. No runtime branch or RSP adjustment is implied by either brace.

The loop test consumes `}` and does not put it back. Every other token is made pending so the dispatcher can read it as the start of the next unit. Replacing that putback with an ordinary next-token call would discard each statement's leading token. Popping a scope restores the visible symbol prefix, not local-slot allocation or arena allocation. Those policies remain C15's and C02's.

**Input/error boundary.** This is a well-formed-input trace. The compound loop has no dedicated EOF test or local recovery branch; an EOF token is not a closing brace and enters downstream parsing. Do not promise a particular missing-brace diagnosis from this loop alone. [The actual scope provider](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/070-cc-sym.fth#L152-L167) checks scope capacity with 61 and an unmatched pop with 62.

## An if has two possible completion events

The parser enters with `if` consumed. It owns the parentheses; `cc-parse-expr` owns the condition expression. Here is the complete [branch algorithm](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L49-L70):

```forth
: cc-parse-if
  lparen cc-expect-punct-c
  cc-parse-expr
  [char] ) cc-expect-punct-c

  cc-value-test-fwd
  cc-emit-jz-rel32-placeholder                    ( fixup-jz )

  cc-parse-stmt-fwd                             \ then-body

  \ Optional else.
  cc-next-token-keep
  tok-kind @ tk-kw = tok-kw-id @ kw-else = and if,
    \ jmp end ; patch jz to here ; else-body ; patch jmp to here.
    cc-emit-jmp-rel32-placeholder                 ( fixup-jz fixup-jmp )
    swap cc-patch-rel32-to-here                   ( fixup-jmp )
    cc-parse-stmt-fwd                           \ else-body
    cc-patch-rel32-to-here                        ( -- )
  else,
    cc-putback-token
    cc-patch-rel32-to-here                        ( -- )
  then, ;
```

Suppose the JZ begins at chosen output offset 600, the then-body occupies `[606,625)`, and the else-body will occupy 17 bytes. These coordinates are a paper layout, not a dump of `tri.c`.

| Builder event | B.D after event | Output position | Why |
|---|---|---:|---|
| Emit six-byte JZ | `[602]` | 606 | The saved value names the four-byte field |
| Parse then-body | `[602]` | 625 | Recursive statement parsing preserves the saved field offset |
| Recognize `else`; emit five-byte JMP | `[602,626]` | 630 | The true path needs to skip the else-body |
| Swap and patch the JZ to here | `[626]` | 630 | False path now lands after that JMP |
| Parse 17-byte else-body | `[626]` | 647 | Both bodies are emitted, regardless of any later condition value |
| Patch JMP to here | `[]` | 647 | True path skips exactly the else-body |

The JZ displacement is `630−(602+4)=24`, stored `18 00 00 00`. The JMP displacement is `647−(626+4)=17`, stored `11 00 00 00`. At runtime, zero RDI takes the first branch to the else-body; nonzero RDI executes the then-body and jumps over the else-body. Patching after emitting the separating JMP is what keeps the false path from landing on an instruction that would immediately skip its own body.

Without `else`, the parser emits no separating JMP. It puts the following token back, patches the sole field to 625, and returns. That displacement is `625−606=19`, or `13 00 00 00`. The following token might be `return`, `}`, or the next statement's identifier. Its continued presence in `tok-*` matters only because `cc-tok-pending` is set.

### Recursion gives the nearest if its else

Take valid initialized integer locals and this source:

```c
if (pad) if (n) pad = pad - 1; else n = n - 1;
return;
```

Name the outer and inner JZ fields qO and qI. Outer parsing keeps B.D=`[qO]` while recursively parsing its body, the inner `if`. The inner emits qI, producing `[qO,qI]`. Its then-body leaves both items in place. The inner's optional-else read sees `else`, so it emits and resolves its own second jump. When that inner call finishes, B.D is again `[qO]`, and its `else` has already been consumed.

Only then does the outer parser look for an `else`. It sees `return`, puts it back, patches qO to its end, and returns. Thus the nearest still-parsing `if` claims the `else`; no separate “dangling else” search is required. Future execution when `pad=0` skips the entire inner statement. When `pad` is nonzero, `n` chooses between the two assignments. The compiler parsed both assignments even when a particular future run cannot reach one.

If braces instead surround the inner statement, the inner's no-else read can see `}`, put it back, and return. The compound consumes that brace; the outer's subsequent lookahead may then claim an `else` outside it. Token ownership, rather than indentation, determines that boundary.

### First-session checkpoint

After C16-01 and C16-02 Part A, stop when you can explain which recursive parser consumes `else`, what token remains pending afterward, and why each saved field is patched at that event. Save qO and qI as field offsets, not target addresses. On returning, reconstruct that token ledger before adding known-target branches or loop lists.

## A known destination still becomes a relative instruction

Forward branches need placeholders because their destinations are unknown. A loop's backward destination is already known, so [these two emitters](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L79-L93) calculate the field immediately:

```forth
: cc-emit-jmp-vaddr                               ( target-vaddr -- )
  [lit] 233 cc-emit-byte                          \ E9 opcode
  cc-here-vaddr [lit] 4 + -                       \ rel32
  cc-emit-4le ;

\ cc-emit-jnz-vaddr ( target-vaddr -- )  Emit `0F 85 <rel32>` to absolute target.
\ After emitting `0F 85`, cc-out-pos points at the rel32 slot's first byte.
: cc-emit-jnz-vaddr                               ( target-vaddr -- )
  [lit]  15 cc-emit-byte                          \ 0F prefix
  [lit] 133 cc-emit-byte                          \ 85 opcode
  cc-here-vaddr [lit] 4 + -                       \ rel32
  cc-emit-4le ;
```

“vaddr” describes the input coordinate; it does not make the emitted instruction an absolute-address jump. After the opcode bytes, `cc-here-vaddr` names the field's first byte. Adding four reaches the next instruction, the origin of the relative calculation. The target address remains below those temporary calculations on B.D until subtraction consumes it.

If output position is 700 and the target is `0x400280`, corresponding to offset 640:

| Emitter | Field offset | Next-instruction offset | Displacement | Complete bytes |
|---|---:|---:|---:|---|
| JMP | 701 | 705 | `640−705=−65` | `E9 BF FF FF FF` |
| JNZ | 702 | 706 | `640−706=−66` | `0F 85 BE FF FF FF` |

The extra opcode byte changes the displacement. Subtracting 700 in both cases would point too far forward. The same formula works for an already-known forward destination. There is no general signed-range check in these helpers; the caller's fitting-rel32 premise still matters.

**Reference return, C17.** The adjacent [`cc-emit-je-vaddr`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L95-L101) uses `0F 84` and the identical subtraction. JE and JZ name the same zero-flag branch encoding. C17 uses it after comparing switch values; here its full interface is known without importing that switch algorithm. These helpers live in `112` beside their users for organization, not because `cc-here-vaddr` was unavailable to `090`.

## Give each enclosing construct its own lists

A single `if` needs a fixed number of fields. A loop body can contain many `break` or `continue` statements, including ones nested inside `if` statements. Two builder head variables collect them. They contain node pointers, not counts, target addresses, or generated stack pointers.

| State in `112:118–125` | Owner and meaning |
|---|---|
| `cc-break-stack-head` | Current breakable construct's rel32-node head; a loop or switch can own it |
| `cc-continue-stack-head` | Current loop's rel32-node head; an intervening switch does not replace it |
| `cc-fixup-target-tmp` | Walker scratch holding the common target virtual address during a walk |
| `cc-for-top-vaddr` | Current `for`'s target address before condition evaluation |
| `cc-for-end-fixup` | Current `for`'s condition-JZ field offset |
| `cc-for-step-start`, `cc-for-step-end` | Source byte offsets bounding the current `for` step, end-exclusive |

The four `cc-for-*` cells return in the replay session; the first loop trace needs the two heads and walker scratch.

The names “stack-head” describe saved nesting contexts; the lists themselves are linked arena nodes. The complete [append adapters](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L118-L134) select the mutable head cell:

```forth
: cc-add-break-fixup                              ( off -- )
  cc-break-stack-head cc-add-fixup-to-list ;

: cc-add-continue-fixup                           ( off -- )
  cc-continue-stack-head cc-add-fixup-to-list ;
```

Retrieve C10's mechanism: `cc-add-fixup-to-list ( off head-cell -- )` allocates sixteen bytes, stores off at node+0, stores the previous head at node+8, and publishes the new node as head. In contrast, `cc-walk-and-patch-to-vaddr ( head target -- )` takes the fetched head value. For each node it reads off, writes `target−(0x400000+off+4)` into that output field, and follows node+8. It changes neither the owner cell nor output position and frees no nodes. Passing the address of the head cell instead would interpret the wrong memory as a node.

**Reference return, C10.** The second walker, `cc-walk-and-patch-imm64-to-vaddr`, follows the same node format but writes the absolute target into eight-byte fields without subtraction. It belongs to C10's function-address uses, not to these break/continue lists. A node format does not determine the patch width; the selected walker does. Both walkers use `cc-fixup-target-tmp` and do not establish independently reentrant walker contexts. [Their complete bodies and worked derivation are in C10](10-calls-literals-and-deferred-addresses.md#open-the-patch-walkers-now), pinned to [112:139–171](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L139-L171).

The [current-destination wrapper](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L173-L176) supplies one missing argument:

```forth
: cc-walk-and-patch-fixups                        ( head -- )
  cc-here-vaddr
  cc-walk-and-patch-to-vaddr ;
```

If a list holds field offsets 361 then 341 and current output position is 405, the walk stores `405−365=40` at 361, then `405−345=60` at 341. Reversed recording order is harmless because each calculation is independent. Empty head zero performs no patch. Completed loop parsing restores an outer owner head; it does not reclaim the completed list's arena storage.

### Break and continue consume syntax before adding work

**Switch-free starting point.** In the first loop trace, both `cc-switch-depth` and `cc-loop-switch-depth` are zero. Their difference is zero, so the unwind callback emits no restore instruction. Keep that small contract while reading the adapters; the [switch contrast](#when-a-switch-lies-inside-the-loop) below explains nonzero depths when you need them.

The full [statement adapters](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L605-L620) are:

```forth
: cc-parse-break-stmt
  [char] ; cc-expect-punct-c
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-break-fixup ;

\ cc-parse-continue-stmt ( -- )  "continue" already consumed.
\ Unwind the scrutinee pushes of any switches between here and the loop
\ being continued before jumping out of them.
: cc-parse-continue-stmt
  [char] ; cc-expect-punct-c
  cc-switch-depth @ cc-loop-switch-depth @ - cc-emit-switch-unwind
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-continue-fixup ;
```

The leading keyword is already consumed. The semicolon expectation precedes the placeholder and node allocation. There is no loop-validity check in either adapter: the source explicitly assumes valid enclosing contexts. A head equal to zero means “no recorded exits yet,” not “no loop exists.” These words alone do not diagnose `break;` outside a loop/switch or `continue;` outside a loop.

### When a switch lies inside the loop

**Optional depth for the switch-free trace; needed for C16-03's unwind question.** We need C15's named switch-depth interface, but not yet its producer. Each open switch has one saved target RBX to restore. `cc-switch-depth` counts those lexical obligations; `cc-loop-switch-depth` records the depth when the current loop was entered. `cc-emit-switch-unwind ( n -- )` appends n `POP RBX` instructions for a nonnegative count. It does not alter the builder's depth variables or pop B.R. C17 establishes how switches create the obligations and route normal exits.

A continue from depth three to a loop entered at depth one emits two restores before its JMP. A loop entered inside a switch at depth one, with no newer switch around the continue, emits zero. Restoring the enclosing switch in that second case would discard state the surrounding construct still owns. Break emits no explicit unwind here: its current owner's exit destination performs any required switch restoration. Return uses a different count, all open switches, as C15 established.

## A while owns two exit destinations

The recurring body is:

```c
while (pad > 0) { putchar(' '); pad = pad - 1; }
```

The builder will parse that body once and emit a backward edge. Future execution may visit it repeatedly. The condition's first instruction is both the backward destination and the `continue` destination, so `pad > 0` is reevaluated after each visit.

Before reading the source, name the saved state: outer break head Bo, outer continue head Co, previous loop depth Do, current switch depth D, condition-top address Vtop, and condition field qE. In the first switch-free trace, Do=D=0. The stacks below show only this parser's saved cells, with top at the right.

| Event | B.D after event | B.R after event | Obligation completed or preserved |
|---|---|---|---|
| Save/reset owners | `[]` | `[Bo,Co,Do]` | Active heads become zero; loop depth becomes D |
| Emit condition/JZ; save top | `[qE]` | `[Bo,Co,Do,Vtop]` | End field and backward destination survive body parsing |
| Parse body recursively | `[qE]` | `[Bo,Co,Do,Vtop]` | Body can add exits to the active lists |
| Patch continues | `[qE]` | `[Bo,Co,Do,Vtop]` | `r@` reads Vtop without removing it |
| Emit backward JMP | `[qE]` | `[Bo,Co,Do]` | `r>` consumes Vtop as the jump's destination |
| Patch condition and breaks | `[]` | `[Bo,Co,Do]` | Both now reach the position after the JMP |
| Restore owners | `[]` | `[]` | Restore Do, Co, then Bo |

### Read the complete while body

On a source-detail pass, match this [complete parser](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L192-L226) to the ledger. If the ledger is enough for your first pass, continue to [the byte layout](#check-the-while-bytes) and return to the listing later:

```forth
: cc-parse-while
  \ Save outer break/continue list heads + loop switch-depth on rstack.
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  cc-loop-switch-depth   @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  cc-switch-depth @ cc-loop-switch-depth !

  lparen cc-expect-punct-c
  cc-here-vaddr                                   ( top-vaddr )
  cc-parse-expr
  [char] ) cc-expect-punct-c
  cc-value-test-fwd
  cc-emit-jz-rel32-placeholder                    ( top fixup-end )

  \ Park top-vaddr on rstack so it survives the body parse.
  swap >r                                         ( fixup-end ; R: ... top )

  cc-parse-stmt-fwd                             \ body

  \ Continue target = top-vaddr.  Walk continue list (no-op if empty).
  cc-continue-stack-head @ r@ cc-walk-and-patch-to-vaddr

  \ Emit jmp top, then patch jz fixup.
  r> cc-emit-jmp-vaddr                            ( fixup-end )
  cc-patch-rel32-to-here

  \ Break target = here.  Walk break list (no-op if empty).
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;
```

### Check the while bytes

The two uses of Vtop have different lifetimes: `r@` lets the continue walk read it without removing it; `r>` then supplies it to the backward JMP emitter. Meanwhile, qE remains on B.D until the exit position is known.

For a separate paper layout, let top offset be 300, condition JZ start 320 (qE=322), a continue JMP field be 341, a break JMP field be 361, and the final backward JMP start 400. Then:

- The continue field becomes `300−(341+4)=−45`, bytes `D3 FF FF FF`
- The final backward JMP reaches 300 with `300−405=−105`, bytes `E9 97 FF FF FF`
- The condition JZ reaches end offset 405 with `405−326=79`, bytes `4F 00 00 00` in its field
- The break field also reaches 405 with `405−365=40`, bytes `28 00 00 00`

The break target must be after the backward JMP. Patching it to 400 would turn “leave” into “repeat.” A continue reaches the beginning of condition evaluation, not merely its final TEST instruction; otherwise the loop could reuse a stale RDI value.

### Nested loops borrow the same globals safely

Suppose the outer loop has already recorded break node B1 and continue node C1. Entering an inner loop saves those heads and resets both active heads to zero. After the inner body records B2 and C2, its owner patches only B2 and C2. It restores B1 and C1 on exit. A later outer break prepends B3 with next=B1; it does not link to B2.

| Builder point | Active break head | Active continue head | Ownership consequence |
|---|---|---|---|
| Before inner entry | B1 | C1 | Outer exits are pending |
| After inner save/reset | 0 | 0 | New records cannot attach to outer lists |
| After inner body | B2 | C2 | Only inner exits are reachable from active heads |
| After inner completion/restoration | B1 | C1 | Outer parser resumes its own unfinished work |
| After later outer break | B3 → B1 | C1 | Outer completion will patch both outer breaks |

B1 through C2 are symbolic builder node addresses, not target labels. Inner nodes remain allocated after their obligations are discharged. Saving and restoring the heads supplies nesting; the generic walker does not discover which loop a jump belongs to.

For the original `pad` loop with initial `pad=2`, the conditional runtime prediction is: test true, print one space, store one; test true, print another space, store zero; test false, leave. Neither the builder's loop-parsing count nor its scope depth becomes two because this future execution repeats twice.

## A for separates source order from execution order

The triangle has already declared `r`, so its header uses assignment initialization:

```c
for (r = 0; r < t.rows; r = r + 1) {
    w[r] = 1 + r * 2;
    line(t.rows - 1 - r, w[r]);
    t.stars = t.stars + w[r];
}
```

Source order is init, condition, step, body. Required emitted order is init, condition, body, step, backward JMP. The parser emits directly rather than building a stored syntax tree. It resolves this mismatch by scanning over the step without compiling it, compiling the body, and then replaying the step's source window into the output buffer at its new position. The source bytes themselves never move.

The [first half of `cc-parse-for`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L247-L290) performs these transitions:

1. Save the outer values of all four `cc-for-*` scratch cells on B.R, in order top, end-fixup, step-start, step-end. A nested `for` will overwrite them, so saving only the exit-list heads would be insufficient
2. Push a symbol scope and consume `(`. Fetch the first init token. A semicolon means no init; it is already consumed
3. Otherwise, with LP64 enabled and the native type-start predicate true, call the native declaration provider. In the default legacy path, put the token back, parse an expression, and expect `;`
4. Only after init, save/reset break and continue heads and snapshot loop switch-depth, as for `while`. The new loop's exit context is not active during its init
5. Record the condition-top target address. Fetch the next token: a semicolon means an omitted condition; otherwise put it back, parse the condition, and expect `;`
6. Emit the value test and JZ placeholder. Store its field offset in `cc-for-end-fixup`, then the earlier top address in `cc-for-top-vaddr`

An omitted condition has a concrete implementation, not an uninitialized RDI:

```forth
    [lit] 1 cc-emit-mov-rdi-imm32 cc-mark-int-value
```

That exact [line 280](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L276-L288) emits integer one and publishes matching expression state before the value-test callback. `cc-mark-int-value` invokes the metadata reset and, under LP64, explicitly records int type. Without that publication, a typed test could interpret a synthetic integer using stale expression metadata. The parser still emits TEST and JZ for the omitted condition; it does not optimize them away.

Default legacy initialization here is an expression or nothing. Do not infer support for `for (int r=0; …)` from the fact that ordinary block statements accept `int`. The native branch has its own provider contract: the current first declaration token and collected parser state are available; the declaration provider consumes its declaration including the terminating semicolon. The for-scope keeps such a declared name visible through condition, body, and replayed step, then hides it. A compound body adds another nested scope, which closes before replay. Full native declarator bodies remain later material.

### Find the matching close parenthesis as tokens

The [step scanner](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L297-L311) begins immediately after the condition semicolon:

```forth
  [lit] 0 cc-tok-pending !
  cc-src-pos @ cc-for-step-start !
  \ Scan to the matching ')'.  Track depth starting at 1 (we're already
  \ inside the outer for-paren).
  [lit] 1                                         ( depth )
  begin,
    dup [lit] 0 >  cc-eof? 0= and
  while,
    cc-next-token-keep
    lparen cc-tok-punct? if, 1+ then,
    [char] ) cc-tok-punct? if, 1- then,
  repeat,
  drop                                            ( -- )
  \ cc-src-pos is now just past ')'.  step-end = position of ')'.
  cc-src-pos @ 1- cc-for-step-end !
```

Depth begins at one because the outer header's `(` has already been consumed. For the valid step spelling `r = (r + 1)`, the grouping `(` changes depth 1→2, its `)` changes 2→1, and the header's final `)` changes 1→0. Only punctuation tokens change depth. A `')'` character token or a `")"` string token does not; comments are skipped by tokenization. This is precisely where counting raw parenthesis bytes would give the wrong boundary.

The end offset is the position of the header's final one-byte `)`, excluded from the step window. Whitespace preceding that parenthesis remains inside the window. The scanner checks EOF while searching, but does not separately reject a nonzero remaining depth before assigning `pos−1` and attempting the body. Our derivation therefore requires a matched header; it does not promise a clean dedicated “missing for parenthesis” error.

Next, `cc-parse-stmt-fwd` emits the body. The source is now after the body, possibly with a following token pending. At this exact output position, before replaying the step, the parser patches the continue list to here. This is why `continue` in a `for` performs the step, rather than jumping directly to the condition.

## Replay the step without losing the next statement

It is tempting to save only `cc-src-pos`. That would preserve a byte coordinate while losing which token those bytes belonged to. The current implementation instead uses a fresh arena-allocated lexer snapshot:

```forth
  cc-lex-state-size cc-alloc dup cc-lex-mark >r
  cc-src-len @ >r
  cc-for-step-end @ cc-src-len !
  cc-for-step-start @ cc-src-pos !
  \ Clear any pending putback before re-tokenising at the new position.
  [lit] 0 cc-tok-pending !
  \ Whitespace/comments alone do not make an omitted step an expression.
  cc-skip-ws-and-comments
  cc-src-pos @ cc-src-len @ < if,
    cc-parse-expr
  then,
  \ Restore lexer state.
  r> cc-src-len !
  r> cc-lex-reset
```

This exact [replay block](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L322-L335) allocates **64 bytes**, not a pair of cells. From [020's layout](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/020-cc-arena.fth#L19-L28), the mark contains:

| Mark byte offset | Saved cell |
|---:|---|
| 0 | Source position |
| 8 | Source line |
| 16 | Token kind |
| 24 | Token numeric/punctuation payload |
| 32 | Token string/name address |
| 40 | Token string/name length |
| 48 | Token keyword ID |
| 56 | Pending-token flag |

Source length is a separate variable in `030`, outside that block. Saving all eight cells does **not** save length, so the next `>r` preserves it separately. `cc-lex-mark` copies the complete state into the allocated block; `cc-lex-reset` copies it back. The [copy helpers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L666-L689) operate in eight-byte cells. The fresh block is not the shared `cc-peek-mark`: expression parsing during replay can itself use lookahead and overwrite that shared scratch mark.

### A full state transition with a pending token

Use a deliberately small, stipulated source layout. The five bytes `r=r+1` occupy `[40,45)`, with the header `)` at 45. Total source length is 140. The body is an `if` without an else. Its optional-else read sees the next statement's identifier `n` at byte 90, advances position to 91, and puts that token back. Let the saved line be 8. Other fields unused by an identifier may contain old values U and W; their values are irrelevant to classification, but are still copied.

The saved post-body state is:

`(pos=91, line=8, kind=ident, num=U, str=src-buf+90, str-len=1, kw=W, pending=true)`

| Transition | Source position/length | Token-state consequence | Output consequence |
|---|---|---|---|
| Mark post-body state | 91 / 140 | All eight cells copied to fresh block M | None |
| Save length, install step window | 40 / 45 | Pending cleared so the old `n` cannot be returned | None |
| Parse step | Advances within `[40,45)` | Replay replaces token fields; EOF is at window end | Append code for `r=r+1` after the body |
| Restore length | Replay position / 140 | Replay token state still present briefly | None |
| Reset from M | 91 / 140 | Exact saved `n` record and pending=true restored | Emitted step code remains |
| Next outer token read | Still 91 / 140 | Returns pending `n`, clears pending | No source byte reread |

A cursor-only restore would leave replay's token record in place. Leaving the pending flag set when entering replay would instead let the stale `n` masquerade as the step's first token. Clearing pending fixes the replay entrance; restoring the full mark fixes the return. They solve different problems.

Whitespace or comments alone are a valid omitted step. The explicit skip runs inside the temporary window, and the comparison `pos<len` calls the expression parser only if something remains. An omitted step still has a continue destination: it is the position where the backward JMP will be emitted.

Resetting the mark restores lexer state, not expression metadata, emitted bytes, or arena allocation. The fresh 64-byte mark and any replay allocations are not locally freed.

**Diagnostic boundary.** The saved line counter is restored afterward. The code does not separately save the step's original line and install it before replay, so do not infer exact original-step diagnostic line numbers during replay from this restoration mechanism. Nor does the window alone validate every malformed expression. These are boundaries of what the inspected state transitions establish.

### Close the loop in reverse ownership order

After restoring the post-body lexer state, the parser emits JMP to `cc-for-top-vaddr`, patches `cc-for-end-fixup` to the new end, and patches the break list to that same end. It restores outer loop-depth, continue head, and break head in reverse save order. Then it pops the for-scope and restores step-end, step-start, end-fixup, and top scratch cells in reverse order. [112:337–352](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L337-L352) supplies that closure.

For a nested `for`, the outer scratch tuple might be `(Vouter,qOuter,40,45)`. The inner parser temporarily replaces all four components, completes its own replay and patches, then restores exactly that tuple. The outer parser can now replay its own window. Restoring only its top address would still risk replaying the inner step or patching the inner condition again. Likewise, a full lexer mark cannot replace the four scratch saves: it contains no loop target or step-range cells.

For the triangle with `t.rows=4` and initial `t.stars=0`, the conditional runtime derivation is:

| r at successful condition | Body's `w[r]` | `t.stars` after body | r after step |
|---:|---:|---:|---:|
| 0 | 1 | 1 | 1 |
| 1 | 3 | 4 | 2 |
| 2 | 5 | 9 | 3 |
| 3 | 7 | 16 | 4 |

The next condition, `4<4`, is false. The body and step are skipped, and the following `if (t.stars == ROWS * ROWS)` can test sixteen against sixteen. This joins previously taught expression/storage contracts to this chapter's edges; it is not a measured whole-program result. A break in the body would skip the step. A continue would skip the remaining body but still execute the step.

**Stop/resume.** Keep the tuple “step `[40,45)`, post-body pending `n`, pos 91, length 140.” On returning, name the three distinct saved things: lexer mark, source length, and outer for scratch. Reconstruct one restoration before tracing another nested loop.

## A do loop tests after its body

A `do` form makes the first visit unconditional:

```c
do { pad = pad - 1; } while (pad > 0);
```

`cc-parse-do-while`, the [complete parser at 112:367–400](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L367-L400) saves/resets the same three loop-context values as `while`, then saves the current target address on B.R before parsing the body. Immediately after the body it patches continues to the current output position. Only then does it consume keyword `while`, `(`, the condition expression, `)`, and `;`.

Its decisive closing sequence is:

```forth
  cc-value-test-fwd
  r> cc-emit-jnz-vaddr                            \ jnz top

  \ Break target = here.
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;
```

That exact [tail](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L391-L400) uses JNZ because a true condition repeats. There is no initial condition JZ field to patch. The backward address was known before body emission. Break fields target the position after the JNZ, while continues target the start of condition evaluation. A continue sent to the body top would bypass the required test and could repeat indefinitely.

With initial `pad=0`, the body stores −1 before the test fails; the corresponding `while` body would not execute at all. With initial `pad=2`, the do-body stores one, the test repeats, then the body stores zero and the test ends. These bounded values fit the legacy signed arithmetic used here.

Compare the destinations without memorizing the parsers:

| Construct | Continue destination | Repeating edge | Break destination |
|---|---|---|---|
| `while` | First condition instruction | Unconditional JMP to condition | After backward JMP |
| `for` | First step instruction, or the backward JMP if step omitted | Unconditional JMP to condition | After backward JMP |
| `do` | First condition instruction after body | JNZ to body top | After JNZ |

Each parser chooses these addresses while producing the layout. The list append helper has no knowledge of which row it serves.

## Close the dispatcher without hiding its other clients

**Complete dispatcher/profile reference.** Return here for C16-07 after the control-flow mechanisms you need. This section closes every dispatcher route; it is not a prerequisite for succeeding at the replay trace.

An expression statement enters with its first token already read. The complete [adapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L828-L833) returns it to the expression parser:

```forth
: cc-parse-expr-stmt
  cc-putback-token
  cc-parse-expr
  [char] ; cc-expect-punct-c ;
```

It emits the expression's side effects and then consumes the semicolon. It does not push a discarded expression value onto a permanent generated stack or need a “discard RDI” instruction. Balanced expression temporaries remain the expression parser's responsibility. A lone semicolon bypasses this adapter entirely and emits no expression code.

The final [`cc-parse-stmt` dispatcher](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L865-L905) first calls `cc-skip-storage-quals`, then `cc-next-token-keep`. C15 established that the skipper resets/collects prefix facts and puts the first nonprefix token back; that token becomes the dispatch token. The source comment's word “skip” must not erase the prefix state its declaration clients use.

The LP64-only prelude precedes ordinary cases:

```forth
  cc-target-lp64 @ if,
    kw-case cc-tok-kw? if,
      cc-switch-depth @ 0= if, [lit] 170 cc-die then,
      cc-switch-case cc-parse-stmt-fwd exit,
    then,
    kw-default cc-tok-kw? if,
      cc-switch-depth @ 0= if, [lit] 170 cc-die then,
      cc-switch-default cc-parse-stmt-fwd exit,
    then,
    cc-native-type-start-fwd kw-typedef cc-tok-kw? or if,
      cc-native-decl-fwd exit,
    then,
  then,
```

For `case` or `default`, it requires a nonzero switch depth, otherwise 170, handles the label, and recursively parses the following statement before returning. For a recognized native type start or the `typedef` keyword, it delegates to the native declaration provider. These early exits prevent the same token reaching a later legacy branch. The `for` init path has a narrower test: it calls the native type predicate but does not repeat this explicit `kw-typedef` OR.

With no prelude match, the rest tests in this order:

| Leading token | Selected action and entry contract |
|---|---|
| `;` | Return immediately; the empty statement's semicolon is consumed |
| Basic type keyword | `cc-parse-decl`, with that keyword current; C15 owns its declaration loop |
| `enum` | Skip an optional tag, then parse a declaration with int base and pointer depth zero |
| `struct` | `cc-parse-struct-local-decl`, after the consumed keyword; legacy block dispatch is for a local object, not a struct definition |
| `return` | `cc-parse-return`, after the keyword; C15 owns expression/bare result, unwind, and epilogue ordering |
| `if`, `while`, `for`, `do` | The matching parser taught here, after its keyword |
| `switch` | `cc-parse-switch`, after its keyword; owns `(expression)` and its brace-delimited body |
| `break`, `continue` | The adapters above, after their keywords |
| `goto` | `cc-parse-goto-stmt`, after the keyword; consumes the label name and terminating semicolon |
| `{` | `cc-parse-compound`, after the opening brace |
| Identifier | `cc-parse-ident-stmt`, with the identifier current and consumed |
| Anything else | `cc-parse-expr-stmt`, which puts that token back |

Every recognized route exits the dispatcher. The final expression fallback is not proof that arbitrary tokens are legal expressions; downstream parsers still decide whether to accept them.

Here are the explicit boundaries of the three C17 clients. Switch parsing temporarily owns the break head, preserves the loop's continue head, creates its saved-RBX obligation, and supplies an exit destination that restores it. It intercepts its own `case`/`default` labels. Goto uses per-function label information and has profile-specific switch restrictions, so do not treat it as another loop continue. Identifier dispatch first recognizes an in-scope typedef name as a declaration; otherwise it distinguishes a following colon from an expression. In legacy mode a recognized label records its destination and returns as its own parser unit; with LP64 the label branch recursively parses the following statement. C17 opens the exact lookup, lookahead, unresolved-reference, and label-target mechanisms. No exercise here requires constructing those structures.

The adjacent JE emitter's complete arithmetic is already covered. The native declaration hooks are providers from `115`, the typed value-test seam can be rebound by `127`, and switch-depth state/unwind comes from `110`. Full provider internals remain later chapters; selecting a flag without the intended bindings is not the same profile. Sources: [identifier dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L835-L858), [switch ownership](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L508-L596), [native declaration providers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth#L478-L638), and [typed test binding](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/127-cc-binary64.fth#L220-L230).

## Practice: account for each unfinished obligation

These are paper tasks. Assume the chapter's legacy profile unless a task selects a native branch. Supplied byte coordinates are stipulated layouts, not actual compiler dumps. [Graduated hints and checked solutions](../practice/16-solutions.md) are separate. If you get stuck, identify whether the missing piece is token ownership, coordinate arithmetic, saved state, or runtime order; recover that one piece rather than rereading every page.

### C16-01 — Trace a recursive owner

Given valid initialized `pad` and `n`, trace `if (pad) if (n) pad=pad-1; else n=n-1; return;`. Track qO/qI on B.D, which parser consumes `else`, and the status of `return` when the outer if finishes. Predict which assignment is reached for `(pad,n)=(0,2)`, `(2,0)`, and `(2,2)`. Then put braces around only the inner `if (n) pad=pad-1;` and keep `else n=n-1;` outside those braces. Explain the changed owner. State what those braces do to builder scope and what runtime stack action they imply by themselves.

### C16-02 — Calculate both branch origins

**Part A: if layout, first session.** An if's JZ starts at offset 1000. Its then-body is 14 bytes. With an else, a five-byte JMP follows it, then a nine-byte else-body. Give both field offsets, both targets, both displacements and their four little-endian bytes. Recalculate the JZ without an else.

**Part B: known-target branches, next session.** Independently, compare a direct JMP and a direct JNZ starting at 1100 and targeting `0x40040A`. Give their complete bytes and explain why their displacement fields differ.

### C16-03 — Separate three kinds of nesting

In switch-free code, an outer loop has break head B1 and continue head C1. An inner loop records B2/C2, completes, and is followed by another outer break B3. Draw the active-head transitions and final outer chains. Explain which records each owner patches and whether patching frees nodes. Separately, predict the number of emitted RBX restores for continue at `(switch-depth, loop-switch-depth)=(3,1)` and `(1,1)`. Why can't empty list heads validate that break/continue are inside a permitted context?

### C16-04 — Complete a loop layout

**Part A: while layout.** A while's condition starts at 900; its JZ starts at 920; a continue field is 944; a break field is 965; the final backward JMP starts at 1000. Fill in destinations, displacements, and four-byte fields for those four edges. A proposed implementation patches breaks before emitting the backward JMP and sends continues to the final TEST rather than condition start. Diagnose both changes.

**Part B: do comparison.** After reading [the do section](#a-do-loop-tests-after-its-body), explain its continue destination and repeating branch, without assuming identical byte lengths.

### C16-05 — Repair a replay account

Use the worked snapshot with step `[40,45)`, source length 140, and post-body pending identifier `n` at source byte 90 with cursor 91. A proposed rewrite saves only cursor/length, leaves pending unchanged, parses the step, then restores those two integers. Identify two independent failures. List every cell in the real 64-byte mark, identify the separately saved value, and trace the real entrance/restoration order. Explain why using the shared lookahead mark is not an equivalent replacement. What happens when the step window contains only spaces and a comment?

### C16-06 — Protect an outer for

Take the valid header `for (; ; r = f(')', (r + 1)))` and assume a declared function `f` with a usable expression-call interface. Trace only the scanner's parenthesis depth and captured end boundary; do not generate the call. Explain the omitted condition's emitted value and metadata action. During the body, an inner for replaces the outer scratch tuple `(Vouter,qOuter,40,59)`. Name the saves/restores needed for the outer replay to work and explain why a lexer mark alone is insufficient. Compare default legacy and native-predicate-true routing for `for (int k=0; k<2; k=k+1) ;`.

### C16-07 — Select an interface without importing its implementation

Classify the dispatcher route and token-entry contract for `;`, `return;`, `{}`, `struct Node *p;` with an already-declared tag, and `pad=1;` with an ordinary local name. Now select LP64 and classify a basic declaration recognized by the native predicate, `case 2: pad=1;` at switch depth zero, and the same case at nonzero depth. Identify which of these require a C17 provider mechanism to derive more than the interface, and distinguish an expression-statement value left in RDI from a leaked target-stack cell.

### C16-08 — Change the triangle's behavior deliberately

In the triangle's for body, insert `if (r == 1) continue;` immediately before `w[r] = 1 + r * 2;`. Keep `t.rows=4`, initial `t.stars=0`, the original step, and the later equality test against sixteen. Predict visited body-work rows, assigned array elements, final `r`, `t.stars`, and the selected return. Then replace only `continue` with `break` and recompute. Explain which destinations cause the differences and why an unassigned `w` element need not be read. For an independent design, describe a control-flow layout that increments a target counter on every entry into the for-step block, including continues, while preserving break behavior. Assume an initialized, nonconflicting writable target counter; count entries into the step block. No declaration or output mechanism is required. A layout/rubric answer is enough; do not modify or execute the compiler.

### Changed reattempts, with answers closed

After feedback, choose the prompt matching your mismatch. These change a relevant assumption rather than only renaming a variable. Their checks are on the feedback page, not here.

1. For C16-01, use `if (pad) ; else if (n) pad=pad-1; return;`. Which optional-else read can see the token after the entire construct?
2. For C16-02, move only the else-body length from nine to zero, keeping its separating JMP. Which displacement changes, and what becomes zero?
3. For C16-03, a continue is inside three open switches and its loop was entered at depth two. Which saved obligations must remain?
4. For C16-04, add seven emitted bytes to the body before the final backward JMP, moving that JMP from 1000 to 1007 but leaving the earlier fields fixed. Recalculate the four fields.
5. For C16-05, the post-body token is `}` pending at cursor 121 and original length 180. After replay, what must the outer compound consume, and should the cursor advance on that first read?
6. For C16-06, replace the step with whitespace and `/* ) ( */` only. Which parenthesis closes the header, and does the replay invoke the expression parser?
7. For C16-07, an identifier names an in-scope typedef rather than a variable. Under legacy routing, which adapter now owns it, and which C15 interface does it call?
8. For C16-08, put `if (r == 1) continue;` after the `t.stars` update. Which totals change compared with the original triangle, and why?

## Carry forward the completion event

You can now trace why an if preserves one field across a recursive body, why nested loops must save owners rather than share unfinished lists, and why a for preserves more than a source cursor. Every loop owns two destinations with distinct meanings; every saved builder value has a restoration or completion event. The generated program follows the resulting edges later.

C17 will open switch and label producers under the interfaces just stated. Keep the distinction between “unknown destination” and “unknown owner”: a fixup delays an address, but the parser must already know whose job it will be to finish that address.
