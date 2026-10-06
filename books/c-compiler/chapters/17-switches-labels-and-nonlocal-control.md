# 17. Switches, labels, and nonlocal control

A `break` in a switch and a `continue` in that same switch can leave through different doors. The `break` reaches the switch's cleanup instruction. The `continue` may bypass that instruction on its way to an enclosing loop. If both jumps merely received the right address, one path could still leave the generated stack wrong.

Start with a switch that uses only the first door. Take `n` and `pad` to be initialized legacy integer locals, with `pad=10` at the start of each independent trace:

```c
switch (n) {
case 2: pad = pad + 2;
case 5: pad = pad + 5; break;
default: pad = 0;
}
```

Predict `pad` for n=2 and n=5. In particular, does entering `case 2` also execute the assignment after `case 5`, or must another comparison succeed first? The missing break after the first assignment will let us distinguish two orders that would otherwise look interchangeable.

**Profile and evidence.** We use the legacy Linux/x86-64 path in [112-cc-stmt.fth, revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth), with `cc-target-lp64=0` unless a native section says otherwise. The traces are manual derivations, not runs or a C-conformance claim. Assume adequate storage and balanced expression temporaries. Helpers and profile limits are identified where used; pinned definitions settle differences from the historical [book30](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/30-statements-if-while-for-return.md).

## Emit the bodies before their selector

This source chooses a bodies-first pass: emit each body as it is read, keeping the assignments in source order for fall-through, and record its case address. After the closing brace, emit the **selector**, the chain of comparisons choosing a case. Another design could put the selector first and use forward case fixups; unknown addresses do not force this layout. The source bytes are already buffered. This choice needs neither a separate saved representation of the bodies nor a replay of them to place the switch's selector.

That placement creates a second problem. A generated program entering the switch must run the selector first. The compiler therefore leaves an initial forward-jump field before the bodies and patches it when the selector's position is known. This is C10's deferred-branch idea applied to a whole selection, rather than a single condition.

Here **builder** means the Forth compiler running now; the **generated program** runs the emitted instructions later. As [C14](14-expressions-and-constant-evaluation.md) established, `cc-parse-expr` emits instructions that will calculate the controlling value in RDI. The switch then emits `PUSH RBX` and `MOV RBX,RDI`: preserve RBX's previous value, then keep the controlling value in RBX for the comparisons. Emitting those instructions does not perform their register changes in the builder.

The generated entry has one eight-byte save to undo. Call the common cleanup destination **end-A**; it will contain `POP RBX`. The two orders can now be written without pretending the compiler follows a particular future branch:

```text
Builder output order:
  expression; save RBX; copy value; initial JMP
  case bodies in source order; body-end JMP
  comparison chain; default/no-match JMP
  end-A: POP RBX

Generated execution order on a match:
  expression; save RBX; copy value; initial JMP to chain
  comparisons; JE backward to the matching body
  body, including any source-order fall-through
  break/body-end JMP to end-A; POP RBX
```

The builder emits every body once; a later run of the generated program selects where to enter them.

### A case record is data for the builder

On reaching `case 2:`, the builder needs to remember two facts: the constant two, and the address where that body's next instruction will go. The constant is calculated now by `cc-parse-const`; it is not an expression for the generated program to reevaluate. Call the body's target address V2. The later `case 5:` similarly supplies five and V5.

The builder puts each new `(constant, target)` record at the front of a list. Reading case two and then case five therefore gives the record order `(5,V5), (2,V2)`, while the emitted bodies still occur as body2 then body5. The records are compiler data, not emitted instructions; V2 and V5 identify positions in the generated code. The default's target is kept separately.

### Legacy dispatch: walk the recorded cases

Now both body addresses exist. The dispatch emitter visits the newest record first: emit a comparison of RBX with its constant, then JE to its target, and continue with the next record. JE means “jump if equal.” In our example the emitted tests ask whether n is five, then whether n is two. If neither comparison succeeds, a final jump selects the default body.

The initial jump sends the generated program to this chain before it can execute any assignment. A successful JE jumps backward to the selected body. It does not re-run the controlling expression, and it does not arrange another comparison after that body's assignment. Once inside the bodies, ordinary instruction order and explicit source jumps determine what happens next.

## A switch gives break a cleanup destination

The second assignment is followed by `break`. `cc-parse-break-stmt` requires its semicolon, emits a forward JMP, and records that jump on this switch's break list. It does not emit a pop. The switch parser will patch the jump to end-A, immediately before the single `POP RBX` that restores the entry save. Adding a pop at both the break and its destination would restore twice.

The default assignment also needs to leave. Without a jump after the last body, execution would fall into the selector and start testing again. The compiler emits that body-end jump unconditionally and adds it to the same break list. Both exits will therefore reach the same pop.

Follow the three possible entries, keeping the source-order bodies in view:

| Controlling value | Selector chooses | Assignments reached | Final pad | Exit |
|---:|---|---|---:|---|
| n=2 | Second comparison, V2 | Add two, then add five | 17 | Explicit break to end-A |
| n=5 | First comparison, V5 | Add five | 15 | Explicit break to end-A |
| n=9 | Default target | Store zero | 0 | Body-end jump to end-A |

For n=2, the five-comparison failed **before** the two-comparison succeeded. That failure does not prevent execution from later falling through into the five-case body. **The selector's reverse order has not reversed the bodies.** If both cases had ended with breaks, our example would have hidden this distinction.

Every listed path performs exactly one restoration. When the generated entry pushes the old RBX, its stack pointer RSP moves from a boundary S to S−8 and stores that old value there. At end-A, POP RBX restores the value and moves RSP back to S. These are generated stack changes, not builder-stack operations.

Bodies may then use RBX as scratch: dispatch has finished and body completion skips it. The controlling value need not survive all body work, but the saved *previous* RBX must be restored at exit.

### Without default

Remove only `default: pad = 0;` from the source. Keep `pad=10` initially. What should happen for n=9 now, and why should n=2 still follow its earlier path? Decide where the selector's no-match path must go so that the saved RBX is restored even though no assignment ran. [Check this small change](../practice/17-solutions.md#without-default).

The other door from the opening question remains: `continue` leaves without visiting end-A.

## When continue bypasses the cleanup

Put the same switch inside a loop and replace its `break` with `continue`. The destination is now the loop's next condition or step, not the switch's end-A. The jump bypasses the pop we placed there. To avoid leaving the saved RBX on the stack, this path must pop it **before** jumping.

[C16](16-conditions-and-loops.md) supplied two separate lists of unfinished jumps. A switch installs its own break list but leaves the enclosing loop's continue list in use. `cc-loop-switch-depth` remembers how many switches were open when that loop began. `cc-switch-depth` counts the switches open at the current source position; parsing the switch's entry save increments it once. Neither variable counts how often the generated loop will run. Their difference tells the compiler how many switch saves this continue crosses.

The exact [continue consumer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L608-L620) emits:

```forth
: cc-parse-continue-stmt
  [char] ; cc-expect-punct-c
  cc-switch-depth @ cc-loop-switch-depth @ - cc-emit-switch-unwind
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-continue-fixup ;
```

The difference is a count of switches crossed, not a count of braces or all enclosing constructs. Its provider in [110](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L759-L771) is:

```forth
variable cc-switch-depth
variable cc-loop-switch-depth

\ cc-emit-switch-unwind ( n -- )  Emit n `pop rbx` instructions.
: cc-emit-switch-unwind                           ( n -- )
  begin,
    dup [lit] 0 >
  while,
    cc-emit-pop-rbx
    1-
  repeat,
  drop ;
```

It emits one pop per positive count. It neither changes `cc-switch-depth` nor executes those pops now. A negative input produces no pops, not a diagnosis; valid nesting and a correct loop snapshot are part of the calling contract.

Consider a loop entered at depth zero, containing switch A. Inside A is another loop, entered at depth one, containing switch B. At a statement in B, current switch depth is two:

| Exit in B | Destination owner | Pops before its jump/return | Why |
|---|---|---:|---|
| `break` | B's break list, end-A for B | 0 | B's destination executes its one cleanup pop |
| `continue` | Inner loop's continue list | 1 | Current depth 2 minus loop snapshot 1 |
| `return value;` | Function return sequence | 2 | Both switch saves must be restored before the epilogue |

After B's parser and the inner loop's parser finish, the outer loop's continue head and snapshot zero are restored. A later `continue` still inside A emits one pop. In contrast, a `continue` in the inner loop but outside B emits zero: it remains inside A. A `break` from that inner loop also leaves A's save in place, because its loop-end destination lies inside A.

Switch depth is different: each switch increments it once on entering its emitted-save region and decrements it once after emitting its normal cleanup. It need not save a copy on the builder's return stack because well-nested recursion balances the counter. A return or goto encountered while compiling a body emits another runtime exit path; it does not close the parser's lexical switch. Later source statements still need the same depth information.

[C15's return path](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L774-L803) places the result, emits `cc-switch-depth` pops, then emits the epilogue. Resetting RSP during frame teardown is not a substitute for restoring RBX's contents. None of these parsers maintains a separate validity counter that reliably diagnoses every `break` or `continue` outside an allowed construct. An unowned fixup is not a valid exit merely because its node can be allocated.

## Work a complete switch layout

The paths are settled. Now use the same control-flow skeleton in a schematic byte-layout exercise.

### State key

Keep these quantities apart: the builder's Forth data/return stacks, the builder's output-byte cursor, and the future CPU's registers/stack. We write B.D and B.R for the builder stacks, with the rightmost item on top. A node address N belongs to builder memory; an output offset q names a byte field in the generated file; a target address V is `0x400000+offset`. Generated RSP=S names a future stack boundary, never a builder node. Byte lists run from low to high addresses and multibyte fields are little-endian.

For two short checks, (1) a JMP's four-byte field begins at output offset 101 and its target is offset 160: what displacement belongs there? (2) does builder `>r` emit a generated PUSH? [Check the answers](../practice/17-solutions.md#entry-check), or refresh [C10's field/list contracts](10-calls-literals-and-deferred-addresses.md#a-node-has-two-builder-cells-even-for-a-four-byte-patch).

`cc-emit-push-rbx` appends `53`; `cc-emit-mov-rbx-rdi` appends `48 89 FB`; `cc-emit-pop-rbx` appends `5B`. Legacy comparison uses a seven-byte CMP RBX with a sign-extended imm32. The constants two and five fit that signed-32 range. `cc-emit-je-vaddr` emits `0F 84` followed by a four-byte displacement, six bytes in total. Its absolute target argument still produces a relative branch, measured from the end of that field. Assume every displacement fits rel32. Source: [JE encoder](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L94-L101).

For this exercise, **stipulate** that expression emission has just ended at offset 1000. Use replacement regions of 12, 7, and 10 bytes for the three bodies, respectively. These are chosen replacement-body extents, not measured encodings of the assignments. Everything else below uses the actual listed control-instruction widths.

| Output offsets | Emitted item | Stored record or patch field |
|---|---|---|
| 1000 | PUSH RBX | Generated save |
| 1001–1003 | MOV RBX,RDI | Controlling value for dispatch |
| 1004–1008 | Initial JMP | q=1005, pending selector start |
| 1009–1020 | First body | K=2, V2=`0x400000+1009` |
| 1021–1027 | Second body | K=5, V5=`0x400000+1021` |
| 1028–1032 | Explicit break JMP | q=1029, switch's break list |
| 1033–1042 | Default body | VD=`0x400000+1033` |
| 1043–1047 | Body-end JMP | q=1044, same break list |
| 1048–1054 | CMP RBX,5 | Newest case first |
| 1055–1060 | JE V5 | q=1057 |
| 1061–1067 | CMP RBX,2 | Older case second |
| 1068–1073 | JE V2 | q=1070 |
| 1074–1078 | JMP VD | q=1075 |
| 1079 | POP RBX | end-A |
| 1080 | Next instruction | Switch complete |

### Byte-layout detail: calculate the branches

For a field at q and a destination at output offset T, compute `T−(q+4)`. The executable base cancels only because both coordinates refer to this same image.

| Branch | Calculation | Four field bytes |
|---|---|---|
| Initial JMP to selector | `1048−1009=39` | `27 00 00 00` |
| Explicit break | `1079−1033=46` | `2E 00 00 00` |
| Body-end JMP | `1079−1048=31` | `1F 00 00 00` |
| JE case 5 | `1021−1061=−40` | `D8 FF FF FF` |
| JE case 2 | `1009−1074=−65` | `BF FF FF FF` |
| JMP default | `1033−1079=−46` | `D2 FF FF FF` |

Keep `case-head=5→2` beside `body2→body5→default`. If only a displacement differs, recheck the field-end subtraction. C17-02 applies these coordinates to the no-default change.

### Source detail: case-node storage and traversal

The earlier `(constant, target)` pairs are implemented as linked nodes. Here are the storage and traversal operations behind that conceptual list.

`cc-switch-cases-head` holds the first pointer in a linked list of these records. A record is a **node** in builder memory, separate from the emitted instructions. Each node contains three eight-byte cells, 24 bytes in total:

| Byte offset within node | Cell contents |
|---:|---|
| 0 | Case constant K, converted when the selected profile requires it |
| 8 | Absolute target virtual address V of the body's next instruction |
| 16 | Next builder-node pointer, zero at the end |

[`cc-add-switch-case`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L431-L467) receives `(K,V)`, allocates 24 bytes, stores V at node+8 and K at node, links node+16 to the old head, and installs the new head. It temporarily saves the node on the builder's return stack so it can consume K and V without losing the allocation. It emits no instruction.

The resulting physical chain is `head → {5,V5,...} → {2,V2,0}`. The address of a node in compiler memory is not V2 or V5: those values identify instructions in the generated program. `cc-switch-default-vaddr` holds the separate default target.

`cc-emit-switch-dispatch` starts at the head and, for each node, loads K from node+0, emits its comparison, loads V from node+8, emits JE to V, then follows node+16 until it reaches zero. This is the offset-level implementation of the newest-first walk already traced.

Source: [dispatch walker](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L491-L502). The walk neither frees its nodes nor clears the head.

### Parser detail: how the switch is assembled

Now follow the parser that builds this layout, including the compiler state it protects across nested switches.

The complete control algorithm of [`cc-parse-switch`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L508-L596) is:

1. Save outer case head, default target, break head, and switch type on B.R, in that order. Set the three current heads/target to zero
2. Require `(`; parse the controlling expression; call the integer-use hook with its type; record its promoted type through `cc-unary-type`; require `)`
3. Emit PUSH RBX and MOV RBX,RDI; increment lexical switch depth; emit the initial JMP placeholder and save its field offset on B.R
4. Require `{`. Under LP64 only, push a symbol scope
5. Read until `}`. Handle top-level `case` and `default` directly. Put every other leading token back and call `cc-parse-stmt-fwd`
6. Emit an unconditional body-end JMP placeholder and add it to this switch's break list. It prevents completed bodies from falling into the selector
7. Pop the initial field offset and patch it to the current position, the selector start. Walk the case list to emit the comparison/JE pairs
8. If a default target exists, emit a jump to it. Otherwise add another forward JMP to the break list for no match
9. Patch this switch's entire break list to here, end-A. Emit POP RBX and decrement lexical switch depth
10. Restore outer type, break head, default target, and case head in reverse order. Under LP64 only, pop the symbol scope

The required `{` is an implementation boundary: this parser does not accept every general C statement as the switch body. Its inline body reader differs from calling the ordinary compound parser. In particular, **the legacy switch's own braces do not push or pop a symbol scope**. An ordinary nested `{ ... }` still calls `cc-parse-compound` and has that parser's scope behavior. Native switch braces do push and pop. A textbook rule about block scope cannot replace this branch inspection.

The brace loop, like the compound loop, has no dedicated EOF recovery branch. We trace well-formed bounded bodies and do not invent a missing-brace message. Body declarations can emit initialization code before the first case, but the initial jump bypasses such code on direct entry to a later case. Emitting a declaration does not establish that every generated path executed its initializer.

### Reading case and default labels

`cc-switch-case` calls `cc-parse-const`, converts K with `cc-switch-label`, reads and checks `:`, then records `cc-here-vaddr`. A missing colon on this path is error 170. The body address is the next emitted byte: stacked case labels can therefore share an address.

`cc-switch-default` instead expects `:` with the ordinary punctuation helper and stores the current target address in `cc-switch-default-vaddr`. Zero means no default. It does not allocate a case node. Consequently the two colon failures do not use identical checks: default uses the ordinary kind/value errors 142/143.

Neither registration word checks for duplicate case values, and default registration overwrites a prior nonzero default target. Reverse comparison order is harmless for distinct converted case values; it is not a duplicate-case diagnostic. Our valid examples use distinct constants and at most one default.

If there is no default, the selector's final jump is another forward break-list entry. If there are no cases either, the chain emits no comparisons and the final no-match jump goes straight to the pop. The body-end jump is still emitted even if earlier branches make it unreachable. Omitting it as a presumed optimization would need a different reachability argument; this algorithm does not make one.

### Native detail: convert before choosing comparison width

Two and five fit the short comparison. Now change the controlling type to an unsigned 32-bit integer and use `case -1:`. The converted constant is no longer the 64-bit value −1. The native path must preserve that distinction when it chooses instructions.

Legacy `cc-switch-label` returns K unchanged. With LP64 selected, it examines `cc-switch-type`, the recorded promoted controlling type. If its size is four bytes, it masks K to 32 bits. For a signed controlling type, it then subtracts `2^32` when bit 31 is set. For an unsigned type it keeps the masked nonnegative value. Eight-byte controlling types take no conversion in this helper.

For the same source constant −1:

| Promoted controlling type | Recorded builder-cell value | Required runtime comparison |
|---|---|---|
| LP64 signed 32-bit int | −1, represented as all one bits | RBX equals sign-extended −1 |
| LP64 unsigned 32-bit int | 4,294,967,295 (`0x00000000FFFFFFFF`) | RBX equals that zero-extended value |
| Legacy route | K unchanged | Legacy imm32 encoding contract applies |

The controls' value-producing paths must supply the corresponding representation. `cc-unary-type` in `100` promotes nonpointer types smaller than four bytes to int; it is a type-metadata operation, not itself an emitted conversion. The integer-use hook initially drops its type input. A later [binary64 provider](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/127-cc-binary64.fth#L247-L251) rejects its floating types with 232. Naming that hook does not establish complete controlling-expression type validation in every profile.

[`cc-emit-switch-compare`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L449-L502) chooses between:

- `48 81 FB imm32`: seven-byte CMP RBX,sign-extended-imm32
- Under LP64, for K outside signed-32 range: ten-byte MOVABS RDI,K followed by `48 39 FB`, CMP RBX,RDI

The range test computes the low-64-bit sum `K+2^31`, divides **unsigned** by `2^32`, and chooses the wide form for a nonzero quotient. Values in signed-32 range yield a shifted unsigned value below `2^32`, including negative values whose cell arithmetic wraps appropriately. Thus −1 can use imm32, but unsigned-32 4,294,967,295 must use MOVABS. Writing `FF FF FF FF` into the short form would compare with 64-bit −1, the wrong value for that unsigned case. Legacy always selects the short form, so this chapter's legacy numeric examples stay in its faithful signed-32 comparison range.

Sources for the supporting contracts: [promoted metadata and integer-use defaults in 100](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L175-L217), [encoders in 090](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L258-L273), and [JE encoder in 112](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L94-L101).

## Recursion must restore the owner, not just the target

Recall [C15's scope distinction](15-declarations-and-recursive-records.md): (4) does restoring symbol count also restore local-slot allocation? [Check that distinction](../practice/17-solutions.md#entry-check) before adding nested jump lists.

Let an outer switch currently own case head C, default target D, break head B, and type T. Just before its body, B.R contains the saved surrounding values followed by its initial jump field q. During an inner switch call, the relevant suffix becomes:

```text
B.R: [... outer-saved-values, q,
      C, D, B, T, inner-q]
```

These are builder cells, including arena pointers and output offsets. They are not saved RBX values. The inner call creates its own case nodes and break nodes under reset heads. It first consumes inner-q when its selector start becomes known. It then finishes its own breaks, emits its cleanup pop, and restores T, B, D, C. The outer call can continue adding cases to C and breaks to B, with q still waiting for the outer selector.

Loops swap break **and** continue ownership, as C16 established, but leave the current switch case head/default/type available. Switches swap break and switch state, but leave continue ownership available. This selective saving explains both arrangements:

- In a switch inside a loop, `break` belongs to the switch and `continue` belongs to the loop
- In a loop inside a switch, `break` belongs to the loop; after that loop is parsed, a later break again belongs to the switch

Under LP64, the dispatcher additionally recognizes `case` and `default` while parsing a nested statement. It checks nonzero switch depth, records the label, and recursively parses the following statement. Thus a case in an ordinary inner block can still use the open switch's case head. The switch body's own reader intercepts its immediate case/default tokens directly; it records a label and returns to its body loop rather than recursively consuming a following statement in that branch. These two entry routes share registration helpers but have different token boundaries.

Legacy dispatch lacks those extra case/default branches. Its supported route is the inline switch-body interception, not a promise that labels nested arbitrarily within other statements work. An inner switch naturally installs its own owner, so a label parsed inside that inner switch belongs to it. The exact [LP64 dispatcher extension](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L865-L880) rejects a case/default seen through that route at depth zero with 170.

## Labels have a function-wide identity

A switch learns every case address before emitting its selector. A named jump can arrive in the opposite order:

```c
if (n) goto done;
pad = pad + 2;
done:
pad = pad + 5;
```

Use a function body outside switches, with initialized locals and `done` not a typedef. At `goto done;`, the target instruction has not been emitted. What can the compiler remember so that the later definition can finish this and any other earlier jump to `done`?

An unfinished JMP field is enough for the instruction. A shared table row for `done` connects those fields to the eventual definition.

A switch case is a constant and a target, owned by the current switch. A named label instead has an identifier, can be referenced before definition, and belongs to the current function. The label table is separate from the ordinary symbol table. Braces do not remove its rows.

The [table and workspace selectors](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L623-L685) use five parallel arrays of eight-byte cells. `cc-label-count` bounds the active prefix. `cell[]` turns `(id,array-base)` into `array-base+8*id`.

| Array accessor | Meaning of cell id |
|---|---|
| `cc-label-name-addr` | Borrowed builder address of the name in retained source storage |
| `cc-label-name-len` | Name length in bytes |
| `cc-label-vaddr` | Absolute generated target address; zero means undefined |
| `cc-label-fixup` | Builder-node head for pending forward gotos |
| `cc-label-switch-depth` | Lexical switch depth at definition |

### Lookup, creation, and definition are different events

The [small table operations](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L686-L737) have distinct contracts:

1. `cc-label-vaddr-of ( id -- V )` fetches the target cell. `cc-label-set-vaddr ( V id -- )` stores it. `cc-label-fixups ( id -- list-cell-address )` returns the **address of the owner cell**, not its head value
2. `cc-label-find ( name-address length -- id-or-neg1 )` supplies the name/length array bases and active count to `cc-name-find`. That helper compares lengths then bytes, searching count−1 down through zero. An absent name yields −1
3. `cc-label-create` first checks `count+1 <= cap`, otherwise error 171. It uses the old count as the new ID, stores name length and borrowed name address, zeros target/fixup/depth cells, increments count, and returns the ID
4. `cc-label-find-or-create` keeps the input name pair while searching. On success it discards that pair and returns the existing ID; on failure it creates a row. Repeated references therefore share a single owner
5. `cc-define-label` finds or creates the row, rejects a nonzero target with error 172, stores `cc-here-vaddr`, and stores current switch depth. Its final operation depends on profile

Zero target is a sentinel because these generated code addresses are nonzero. ID zero is a perfectly valid first label; it must not be confused with that target sentinel or with an empty list head. The table stores source pointers, not copied strings: retained source storage must outlive lookup.

For legacy, definition fetches the row's head and calls `cc-walk-and-patch-fixups`, resolving every pending goto to the current position. The walker does not clear the head or reclaim nodes, and this definition word does neither afterward. Later duplicate definitions are rejected by the nonzero target. For LP64, definition intentionally does **not** walk the list: its nodes have another shape and require a later completion event.

Function entry resets `cc-label-count` to zero, not every backing byte. The next created row overwrites its name pair and zeros its target, head, and depth before that row becomes active. Thus equal spelling in different functions does not inherit an old address or an old pending list. The verified entry consumers are [legacy `cc-parse-function`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L273-L280), [private-stack native `cc-native-function`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/117-cc-native-program.fth#L55-L60), and [System V `cc-sysv-function`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L1233-L1238). Their complete frame mechanisms belong to C18 and later provider chapters.

## A legacy goto finishes at the label

After `goto` has been consumed, [`cc-parse-goto-stmt`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L770-L802) reads the target. A nonidentifier is error 173. The name is looked up or created. In the legacy branch, the compiler then emits one POP RBX for **every** currently open switch before choosing the jump form:

- Defined target: fetch its absolute V and pass it to `cc-emit-jmp-vaddr`, which emits `E9 rel32` directly
- Undefined target: emit a JMP placeholder and add its field offset to that label's owner cell through `cc-add-fixup-to-list`

Both branches finally require `;`. As elsewhere, emission before delimiter validation does not imply rollback on malformed input.

The undefined-target node is C10's 16-byte shape `{field-offset,next-pointer}`. Suppose label `done` receives forward branches with fields q=1201 and q=1251, emitted after any needed pops. The second reference prepends its node:

```text
label row for done:
  V=0, head=N2
N2: {1251,N1}
N1: {1201,0}
```

When `done:` is defined at target offset 1320, its row receives `0x400000+1320`, and definition patches:

- q=1251 with `1320−1255=65`, bytes `41 00 00 00`
- q=1201 with `1320−1205=115`, bytes `73 00 00 00`

The nodes contain offsets, not addresses of their output fields in builder memory. Patching derives those buffer locations through the output patch API. A later goto to the already-defined row uses its target immediately; “takes an absolute target address” does not mean “emits an absolute-jump encoding.”

The unconditional full unwind imposes an important **legacy restriction**: the destination must be outside every switch. Even a goto from one point to another within the same switch emits all current pops; the later switch cleanup would no longer have the expected save. Recording a depth column does not fix this legacy branch because it does not read the destination depth.

There is also a completion limit. Legacy [`cc-parse-function`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L293-L310) emits its implicit return and pops scope without calling `cc-native-finish-gotos`. A legacy `goto missing;` whose label is never defined is therefore not caught by that native finisher at legacy function completion. Do not claim error 174 for that route, or confuse named-label completion with the separate unresolved-function checks in program completion. Our usable legacy examples require every referenced label to be defined.

## Native gotos reconcile source and destination depth

LP64 selects a different branch inside the same goto parser. A known target has both V and a definition depth. The compiler can adjust the saves immediately, then emit its direct relative jump. An unknown target lacks the destination depth as well as its address. Merely patching four branch bytes at label definition cannot insert a variable number of missing PUSH/POP instructions at the original site.

The solution is a **trampoline**: a short generated block elsewhere that performs the adjustment then jumps to the true label. The original placeholder is eventually patched to the trampoline, not straight to the label.

The [depth-adjustment helper](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L744-L767) is complete here:

```forth
: cc-native-goto-adjust ( source-depth target-depth -- )
  - dup 0< if,
    [lit] 0 swap -
    begin, dup while, cc-emit-push-rbx 1- repeat, drop
  else, cc-emit-switch-unwind then, ;
```

For source depth s and destination depth d, it emits s−d pops when s>d, d−s pushes when s<d, and nothing when equal. Entering a deeper label does not evaluate skipped controlling expressions or initialize skipped locals. The pushes preserve the current RBX value to provide the additional save slots expected at subsequent exits. This is the inspected depth-adjustment mechanism, not a proof of correct handling of arbitrary transfers between different switch ancestry or arbitrary C constructs. Depth records count, not the identity of every enclosing switch.

`cc-native-goto-fixup ( label-id field-offset -- )` allocates a 24-byte node, stores the offset at +0, **current source switch depth** at +8, and old head at +16, then updates that label's head. The count is captured at the goto site; it is not read later from whichever lexical context the parser happens to be in.

| Node family | +0 | +8 | +16 |
|---|---|---|---|
| Legacy goto / break / continue | rel32 field offset | Next pointer | No cell |
| Switch case | Case constant | Target V | Next pointer |
| Native forward goto | rel32 field offset | Source depth | Next pointer |

Using the generic two-cell walker on a native goto list would interpret source depth as a next-node address. Equal allocation sizes for the last two rows do not make their meanings interchangeable either.

### Finish after emitting the ordinary return path

`cc-native-finish-gotos` visits label IDs from zero to count−1 and traverses each head newest-first. For every node it:

1. Checks the row's target V; zero dies with 174
2. Patches the node's original rel32 field to **the current output position**, which will start this node's trampoline
3. Retrieves the saved source depth and the row's definition depth, preserving ID and node pointer across those loads
4. Calls `cc-native-goto-adjust`, emits a relative JMP to the row's V, then follows node+16

The Forth stack at the start of a node iteration is `[id,node]`. Before adjustment the shuffles arrange `[id,node,source-depth,target-depth]`; adjustment consumes only the last two. The final jump consumes its fetched V and leaves `[id,node]` for advancing. The finisher neither clears all heads nor frees arena storage. Its normal lifecycle calls it once before the next function resets the active label count.

The private-stack native function provider in [117](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/117-cc-native-program.fth#L64-L74) and System V provider in [121](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L1245-L1253) both emit an implicit return/epilogue **before** calling this finisher. Normal function fall-through therefore returns rather than accidentally falling into trampoline code. A forward goto still has the active frame and appropriate source saves when it jumps to its trampoline; the trampoline runs before that path has returned.

### Work two distinct source depths to one label

Take an LP64 function with a label at target offset 2300, definition depth zero. Earlier forward gotos have q=2001 at depth one and q=2101 at depth two. The label's head is the newer depth-two node, followed by depth one. Assume ordinary function-end code is complete and trampoline emission begins at offset 2400.

| Node processed | Trampoline operations and offsets | Original field patch | Final jump field |
|---|---|---|---|
| q=2101, source depth 2 | POP at 2400; POP at 2401; JMP at 2402–2406 | `2400−2105=295`: `27 01 00 00` | q=2403, `2300−2407=−107`: `95 FF FF FF` |
| q=2001, source depth 1 | POP at 2407; JMP at 2408–2412 | `2407−2005=402`: `92 01 00 00` | q=2409, `2300−2413=−113`: `8F FF FF FF` |

The same final label needs two different entry blocks because the source paths have different cleanup obligations. The current compiler switch depth may be zero at function completion; substituting that zero for the node's saved source depth would omit both cleanups. At runtime each source jump reaches only its own block, performs its own pops, and then jumps back to offset 2300. No path is intended to fall through from the first trampoline into the second.

For a known target, the same depth arithmetic is emitted at the goto site directly. For example, s=0 and d=2 emits two pushes then a jump; s=d emits only the jump. Unknown targets use this later mechanism even when their eventual depths turn out equal. Deferring until function completion makes both required facts available without expanding a previously emitted site.

**Pause/resume.** Save one node as `(q,s)` and its row as `(V,d)`. On returning, first derive the number and direction of adjustments; only then choose the trampoline's address and compute branch bytes. If you can do one node independently, continue with a second source depth rather than repeating identical arithmetic.

## The identifier fork needs one speculative token

How does the compiler recognize `done:` as a label rather than a variable or typedef? Recall [C06's token record and lexer marks](06-tokens-and-lookahead.md), then check (3): if a mark restores a consumed identifier whose pending flag was zero, is it now pending? [Check the flag](../practice/17-solutions.md#entry-check) before following the reads.

Given these independent statement starts, the leading token kind is the same:

```c
int_ptr p;
done: pad = 1;
pad = 2;
```

Assume `int_ptr` resolves to an `sk-typedef` with payload encoding int-pointer depth one, `pad` is an ordinary local, and `done` does not name a typedef. The first statement is a declaration; the second begins with a named label; the third is an expression. Ordinary symbol lookup supplies the first distinction. A following colon supplies the second.

The exact [lookahead body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L819-L826) is:

```forth
: cc-peek-after-is-colon?
  cc-peek-mark cc-lex-mark
  cc-next-token
  tok-kind @ tk-punct = tok-num @ [char] : = and
  dup 0= if,
    \ Not a colon — rewind.
    cc-peek-mark cc-lex-reset
  then, ;
```

The caller has already consumed the identifier through `cc-next-token-keep`, so pending is zero. The mark records that current identifier and the source cursor immediately after it, along with the remaining lexer-state cells. `cc-next-token`, deliberately the fresh tokenizer, reads the following token. Comments and whitespace between name and colon are handled by ordinary tokenization.

- If it finds `:`, the result is true and there is **no reset**. The colon is current and already consumed; pending remains zero. The caller must not expect another colon
- Otherwise it restores the entire original mark. The current token is the identifier again, with the original cursor, line, and pending flag. In this entry contract pending is still zero. The expression-statement adapter subsequently calls `cc-putback-token`, making the identifier available to expression parsing

The source comments describe the false result as leaving the identifier pending and the true result as “without consuming.” Read those as loose descriptions, not the exact postconditions. The body is a **commit-on-colon** lookahead. A mark restores the saved flag; it does not invent a putback.

For `pad = 2;`, let L be the state just after consuming `pad`. The peek temporarily reads `=`, then restores L. `cc-parse-expr-stmt` sets pending. The expression parser's first keep-read clears pending and returns `pad` without moving the cursor; a later fresh read gets `=` again. Neither the name nor the operator is lost or duplicated in the committed parse.

For `done /* gap */ : pad=1;`, the peek reads the colon past the comment and keeps that new state. The caller had saved the name's address and length on B.D **before** peeking, because `tok-*` now describes the colon. It gives that saved name pair to `cc-define-label`; the next unread token is `pad`.

The shared `cc-peek-mark` works because the interval between mark and decision only tokenizes; it does not recursively invoke another parser lookahead that would overwrite the same mark. This is a local non-overlap contract, not a generally reentrant snapshot service. C16's recursive body/replay work needed its separately allocated lexer mark for exactly that reason.

### Typedef first, then colon, then expression

[`cc-parse-ident-stmt`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L838-L858) implements this decision order:

1. Search the ordinary symbol table using the current identifier's name span
2. If found and kind is `sk-typedef`, fetch its encoded type, extract base and pointer depth, and call C15's `cc-parse-decl-with-base`. Return without colon lookahead
3. Otherwise discard the failed/non-typedef lookup result and save the name pair. Call `cc-peek-after-is-colon?`
4. On true, define the saved label. Under LP64, recursively call `cc-parse-stmt-fwd` for the following labeled statement; under legacy, return immediately after the definition
5. On false, discard the saved name pair and call the expression-statement adapter, which puts the restored identifier back, parses the expression, and requires `;`

As in [C15](15-declarations-and-recursive-records.md), the typedef payload's depth supplies the starting depth for each declarator, so the admitted legacy `int_ptr p;` gives p depth one. The parser does not treat the spelling `int_ptr` as a type merely because it resembles one; it requires the row's kind.

Under LP64, the earlier dispatcher branch asks `cc-native-type-start-fwd` or tests keyword `typedef`. The actual [provider in 115](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth#L83-L91) recognizes existing typedef identifiers, so an ordinary native typedef-led declaration goes to `cc-native-decl-fwd` before reaching this legacy adapter. This is the statement-level declaration seam opened by C15, not an additional declaration implementation in this chapter.

There are two boundaries worth keeping visible. First, a name that currently resolves as a typedef takes the declaration route before any colon check; the separate label table alone does not provide complete C namespace disambiguation for that collision. Our label examples avoid it. Second, the legacy label branch returns after the colon, whereas the LP64 branch consumes the labeled substatement recursively. A surrounding compound/function body's repeated statement calls can pick up the legacy label's following statement next. A single-body caller such as `while (n) again: pad=1;` cannot be assumed to receive the whole labeled statement from one legacy call. C16's “one statement” contract deliberately excluded this legacy label-prefix boundary.

Together, these decisions extend C16's dispatcher without changing its ordinary expression adapter: LP64 nested case/default checks come first, native type starts get first refusal, and later identifier handling performs the remaining lookup/colon/expression fork. Parser ownership determines which token is read next; surface indentation does not.

### Reference: selected label storage

The row operations stay the same when storage changes. A larger workspace must replace all five array bases and their common bound. C17-05 uses these exact addresses.

Each accessor reads a selected base cell. The five initial object/base-cell pairs are:

- `cc-label-default-name-addr` / `cc-label-name-addr-buffer`
- `cc-label-default-name-len` / `cc-label-name-len-buffer`
- `cc-label-default-vaddr` / `cc-label-vaddr-buffer`
- `cc-label-default-fixup` / `cc-label-fixup-buffer`
- `cc-label-default-switch-depth` / `cc-label-switch-depth-buffer`

The top-level initialization stores each default object's address in its paired base cell; each default array reserves `64*8=512` bytes. `cc-label-limit` initially contains `cc-label-default-cap`, 64, and `cc-label-cap` reads the selected limit. This indirection lets storage selection change without changing every client.

`cc-label-default-workspace` reinstalls the five default bases and limit 64. `cc-label-direct-workspace` allocates once, caching the mapping in `cc-label-direct-base`, then installs limit `cc-label-direct-cap=1024` and these offsets from mapping base A:

| Column | Direct base | Extent |
|---|---|---:|
| Names | A | 8,192 bytes |
| Lengths | A+8,192 | 8,192 bytes |
| Target addresses | A+16,384 | 8,192 bytes |
| Fixup heads | A+24,576 | 8,192 bytes |
| Definition depths | A+32,768 | 8,192 bytes |

The whole mapping is `1024*40=40,960` bytes, ten 4,096-byte pages. Each column spans two pages. The mapping request uses `cc-workspace-map` with failure code 171. Re-selecting a nonzero cached base does not allocate again. These selectors change all five bases and the limit together; they do not reset the count, migrate active rows, copy names, or expand the node arena. Select them before normal initialization, not halfway through a live function. The source comment attributes the chosen bound to a 739-label function in its direct-GCC workload; that is a source-reported motivation, not a count measured in this chapter.

## Practice: identify the owner before doing arithmetic

For a path question, mark the body reached and the save restored. For a byte question, add the field offset and its destination. The [practice feedback](../practice/17-solutions.md) supplies hints and checked reasoning; the changed prompts below keep their answers separate.

### C17-01 — Count the saves crossed

(a) A switch A is open at depth one. Inside it, loop L was entered at depth one. Inside L, switch B raises the current depth to two. Independently trace a `break`, `continue`, and valued `return` inside B: give the list/destination owner, emitted pre-jump pops, and any destination cleanup pop. Explain whether emitting a return changes the parser's depth.

(b) After [Native gotos reconcile source and destination depth](#native-gotos-reconcile-source-and-destination-depth), give the immediate adjustment for an LP64 goto from this point to an already-defined label at depth one. Does that destination satisfy the legacy goto restriction?

### C17-02 — Remove the default without losing the exit

Starting from the worked switch layout, remove the ten-byte default body entirely and remove its label. Keep every earlier body and explicit break unchanged. The unconditional body-end jump is still emitted immediately after the explicit break.

(a) Trace n=9 and n=2 after removing the default. Identify the destination of the selector's no-match path and explain why “no default means no final branch” is wrong for this layout.

(b) After the [byte-layout detail](#byte-layout-detail-calculate-the-branches), reconstruct the new selector start, end-A, next instruction, and all six branch field offsets, displacements, and four-byte values.

### C17-03 — Convert before choosing an encoding

Under LP64, compute the stored case K and compare width for: (a) K=−1 with signed 32-bit control; (b) K=−1 with unsigned 32-bit control; (c) K=4,294,967,301 with signed 32-bit control; (d) K=2,147,483,648 with signed 64-bit control. Include the length of each compare-plus-JE pair. Explain what the short immediate would incorrectly compare against in (b). If both `case -1:` and `case 4294967295:` occur under unsigned 32-bit control, what does registration actually do, and why can we not invoke the distinct-case assumption?

### C17-04 — Restore one owner without stealing another

Immediately before an inner switch, the outer switch owns tuple `(case=C,default=D,break=B,type=T)`. Continue head is K, loop snapshot is zero, current switch depth is one, symbol count is M, and local-slot count is L. The inner switch declares one direct local, then enters an ordinary compound declaring another local. For this exercise, each declaration is specified to claim one new slot. Describe saved/current/restored control state and the final symbol/local counts in legacy and LP64. Which inner nodes may remain allocated after restoration? Why is preserving K essential?

### C17-05 — Use the selected table, not an imagined larger one

With default capacity selected and count 63, request a new label, then look up that same spelling again, then request another new spelling. Give IDs/counts and the failure code and point. In an independent successful run, what prevents defining the same row twice? For direct workspace base A, calculate the addresses of row 1023's target, fixup-head, and depth cells, and the first byte past the whole mapping. Explain why changing only the limit to 1024 would be insufficient.

### C17-06 — Close a legacy forward reference

Two legacy gotos to `done` have already emitted their fields at q=1601 and q=1701. The first source depth is two; the second is zero. The fields are measured after any required pops. `done:` is defined at output offset 1800, outside every switch. Draw the node chain after the second reference, derive both patches, and state the pops emitted at each source. A later known-target JMP begins at 1900 at depth zero; derive its field and bytes. What happens to list storage and the owner head on definition? In a separate function, may you promise native error 174 for a never-defined legacy target?

### C17-07 — Finish native gotos from different depths

An LP64 label is at offset 3300, depth zero. Its pending head records `(q=3101,source-depth=1)`, then `(q=3001,source-depth=2)`, then zero. Function-end trampoline emission starts at 3400 after the ordinary return sequence. Derive every trampoline instruction offset, both original-site patches, both final-jump fields, and the first free output offset. Explain why source depths cannot be replaced by the finisher's current lexical depth, and why the generic 16-byte walker is the wrong consumer.

### C17-08 — Preserve the right token and the right parser boundary

Take the three independent starts `int_ptr p;`, `done /* gap */ : pad=1;`, and `pad=2;` with the symbol facts stated in the identifier section. Under legacy, list lookup decisions, peek/reset/putback events, current token and pending flag at the key boundaries, and the parser that gets the next unread token. For the successful colon path, explain why the saved name span matters. Under LP64 with the actual native type-start provider, which statement bypasses the identifier adapter? If `done` instead resolves as a typedef, is colon lookahead still reached first?

### Changed reattempts, with answers closed

Choose the change that tests your first mismatch after reading feedback. These prompts change an obligation, representation, or parser boundary rather than only a name.

1. For C17-01(a), remove switch B and put the exits directly in L's body inside A. Which saves must remain for break and continue? After part (b), also repeat its goto comparison at depth one
2. For C17-02(a), use an empty switch with no cases or default and trace its path to cleanup. After part (b), begin just after expression emission at offset 1000, retain the same entry instruction widths, and derive every branch and the pop offset
3. For C17-03, use signed 64-bit control and K=−2,147,483,649. Select the encoding and explain what truncation to the short immediate would change
4. For C17-04, replace only the inner switch with a loop, leaving the outer switch open. Ignore declarations in this variant. Which control owners are replaced, what snapshot is taken, and does loop entry add a switch save?
5. For C17-05, begin a new function after a prior row zero had a nonzero target, head, and depth. Trace reset then creation of a new row zero; which old bytes remain irrelevant and which fields must be overwritten?
6. For C17-06, after the [native depth-adjustment section](#native-gotos-reconcile-source-and-destination-depth), put both the source and an already-defined target inside the same switch at depth one. Contrast legacy emitted cleanup with LP64 depth adjustment, without claiming full general goto correctness
7. For C17-07, retain all offsets and source depths but set the target's definition depth to three. Recalculate the trampoline layout and branches
8. For C17-08, use `while (n) again: pad=1;`, with ordinary initialized names and `again` not a typedef. Compare the label parser's consumed unit under legacy and LP64. Which caller next gets the assignment in each route?

## Carry forward both obligations

A patched target says where the generated CPU will go. A correct exit also needs the saved-register and stack state expected there. Switch parsing supplies the common cleanup destination; loop snapshots tell continue which saves it crosses; named labels supply function-wide identities; native forward-goto nodes preserve the source depth until a destination is known.

You can now distinguish four completion events: switch selector emission, switch-end patching, legacy label definition, and native function-end trampoline emission. Keep those events separate when reading C18's function construction. Resetting per-function tables starts a fresh ownership lifetime; it does not prove that every unfinished promise in the previous one was checked.
