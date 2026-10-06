# 18. Functions and call-frame accounting

At zero-based row two (`r=2`) of the recurring `tri.c`, `main` calls `line(1, 5)`. The caller has an array element containing five. The callee repeatedly changes its parameter `n` until it reaches zero. Why does `w[2]` still contain five when control returns? Where do the two parameters live, and what brings the machine back to the caller's exact stack boundary?

A function definition joins mechanisms we have already opened: names, parameter types, local slots, instructions, statements, and return control. The useful new skill is **accounting across the join**. By the end, you should be able to register a function without losing it at scope exit, construct its parameter records, derive its frame and spills, trace a complete call and return, and identify a call whose balanced stack operations nevertheless have the wrong alignment.

**Edition and evidence.** This chapter describes all 310 lines of [`114-cc-func.fth` at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth). Its main path is the legacy, fixed-address Linux/x86-64 compiler, with `cc-target-lp64=0`, `cc-target-sysv=0`, and the default emission/lookup hooks. All traces are manually derived from inspected source. No compiler, Forth example, C example, generated executable, or bootstrap was run for this chapter. Source comments naming “SYS-V” describe the selected argument registers; they do not establish a complete System V ABI implementation.

## Choose a route and check the prerequisites

**First session: answer why `w[2]` stays five.** Follow these links in order:

1. [State key](#state-key)
2. [Three lifetimes meet at one definition](#three-lifetimes-meet-at-one-definition)
3. [Two parameter names, two slots](#two-parameter-names-two-slots)
4. [The fixed frame](#reserve-once-initialize-selectively) and [six parameter stores](#six-specific-stores-connect-registers-to-names)
5. [The default fall-through return](#the-default-fall-through-return)
6. [Follow `line(1, 5)` across the boundary](#follow-line1-5-across-the-boundary), then [C18-04](#c18-04--reconstruct-a-complete-call-frame)

You can stop when you can place the copied parameters and recover the caller's RSP and RBP. The extra body-local variation and alignment account can wait for another session.

**Choose a later session by its outcome:**

- **Publication and compiler scope:** read [publication](#publish-the-function-before-opening-its-scope), [function resets](#begin-each-function-with-clean-control-bookkeeping), [body/scope ownership](#let-statements-consume-their-own-interiors), and [compiler visibility restoration](#restore-compiler-visibility), then do [C18-01](#c18-01--publish-patch-and-retain) and [C18-08](#c18-08--restore-names-without-reusing-slots). The [name-bookkeeping reference](#reference-function-name-bookkeeping) supplies the saved-name details
- **Parameter parsing and limits:** read the [return-spelling consumer](#consume-a-return-spelling-without-inventing-a-signature), the [parameter-token details](#parser-detail-decide-whether-there-are-any-parameters), and the [slot-limit failure point](#parser-detail-the-slot-limit-failure-point) through [the six-spill boundary](#parsing-seven-is-not-receiving-seven), then do [C18-02](#c18-02--follow-the-parameter-tokens), [C18-03](#c18-03--keep-type-and-descriptor-channels-separate), and [C18-05](#c18-05--distinguish-three-limits)
- **Returns and actual call boundaries:** read [explicit exits](#every-normal-route-out-needs-a-result-and-a-return-destination), the [body-local variation](#add-a-body-local-and-an-explicit-result), and [balance versus alignment](#balanced-is-not-necessarily-aligned), then do [C18-06](#c18-06--reconstruct-the-exits) and [C18-07](#c18-07--test-the-actual-call-boundary)
- **Optional provider comparison:** [Compare the later seams](#compare-the-later-seams-without-merging-their-mechanisms) supplies what you need for [C18-09](#c18-09--choose-a-provider-from-evidence). The [source inventory](#source-closure-and-what-to-carry-forward) is a reference

If you can already solve a session's exercise, use its boundary sections to check your assumptions.

Use the prerequisites for your chosen session:

- [C08](08-names-and-lexical-scope.md), for publication and compiler scope: newest-first symbol lookup, kind-dependent payloads, and a scope marker that saves a symbol count
- [C09](09-instructions-inside-an-executable.md), for the first call session: CALL/RET, the eleven-byte prologue, the default five-byte epilogue, and slot address `RBP−8*(slot+1)`
- [C10](10-calls-literals-and-deferred-addresses.md), for publication: distinct rel32 call and imm64 address fixup lists
- [C14](14-expressions-and-constant-evaluation.md), for the first call session: left-to-right legacy argument staging, reverse register pops, and RDI as expression result
- [C15](15-declarations-and-recursive-records.md), for the detailed allocation, parameter, and return sessions: monotonic slot reservation, descriptor association, and explicit-return emission. The first call trace supplies its particular caller-array coordinates directly
- [C06](06-tokens-and-lookahead.md), for the parameter-parser session: current versus pending tokens and a full lexer mark/reset

For the publication session, check whether popping a compiler scope moves the generated program's RSP, and whether payload zero means the same thing for a local and an unresolved function. For the later call-boundary session, ask whether an inner call's own push/pop must remove an outer call's already-pushed argument too. [Entry feedback](../practice/18-solutions.md#entry-check) explains these distinctions; they need not delay the first call trace.

### State key

Throughout, **builder** means the Forth compiler executing now. **Target** means the generated C program when it eventually runs. Builder stack diagrams put the top on the right. Target addresses increase upward numerically; a target PUSH decreases RSP by eight, and RSP names the occupied top cell after a push. Target words and pointers here are 64 bits, memory is byte-addressed, and instruction fields are little-endian. Chosen addresses are paper coordinates, not an observed `tri.c` memory dump.

## Three lifetimes meet at one definition

Compilation of `void line(int pad, int n) { ... }` creates a permanent-for-this-translation-unit function entry and temporary-for-this-parse local entries. Execution later creates a fresh target frame on every call. These are three different lifetimes:

| Item | Created when | Lifetime owner |
|---|---|---|
| Function symbol and emitted body | The builder parses the definition | Translation-unit symbol/output state |
| Parameter and ordinary local symbols | The builder parses the header/body | Compiler lexical scopes |
| Parameter values and local storage | The target executes CALL and the prologue | That particular target invocation |

A recursive call creates another target frame; it does not recursively compile the source definition. Likewise, finishing compilation's function scope does not execute the function's epilogue. Losing a compiler name and returning from a running function are different events.

For the first session, continue at [Two parameter names, two slots](#two-parameter-names-two-slots). The following reference serves the later publication and parameter sessions.

### Reference: function-name bookkeeping

The four variables at the top of `114` carry facts across helper calls:

- `cc-fn-name-addr` and `cc-fn-name-len` retain the name span after subsequent tokens overwrite `tok-*`
- `cc-fn-param-count` counts parameters in the current definition
- `cc-fn-prior-sym-id` remembers the prior lookup result before a newer function record hides it

The name variables copy an address and length, not the name bytes. Their validity still depends on C06's retained source-buffer lifetime. `cc-main-name-bytes` supplies four comparison bytes beginning with `main`; `cc-is-main? ( address length -- flag )` first requires length four, then compares exactly four bytes. `mainly`, `Main`, and a non-four-byte name fail that test. A length mismatch drops both inputs and returns zero; equal bytes return the comparison's true flag.

Source: [bookkeeping and name test](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L12-L30).

## Consume a return spelling without inventing a signature

`cc-parse-fn-return-type` is a **consumer**, not a legacy signature constructor. It skips storage classes and qualifiers using C15's helper, then reads a type token:

1. For keyword `struct`, it requires and consumes an identifier, failing with 185 otherwise
2. For `enum`, it invokes the optional-tag consumer
3. For a basic type keyword, it consumes any further basic type keywords with `cc-more-type-kws`, then discards the resulting base
4. For a non-keyword, it requires an identifier, failing with 186 otherwise; this branch does not look that spelling up as a typedef
5. It counts trailing stars with `cc-count-stars` and discards the count

The star scanner leaves the next token pending. Thus after consuming `const char *`, the function name remains available to the definition parser. The keyword branch does not perform exhaustive validation of allowed return-type combinations. This is the source's limited scanning behavior, not a claim that arbitrary accepted spellings form valid C types.

`cc-parse-function` next reads the name and requires an identifier, with error 187 on failure. It saves the span and consumes `(` through `cc-expect-punct-c`. That expectation uses C15's errors 142 for a non-punctuation token and 143 for the wrong punctuation.

The eventual function symbol is always registered with legacy `int`, pointer depth zero. A source return spelling such as `char *` is not preserved there. Every result still uses one RAX-sized value under this path, and there is no full parameter signature recorded for argument checking. This explains why recognizing `(void)` below should not be mistaken for storing the standard distinction between old-style and prototype declarations.

Source: [return-spelling consumer and function-name entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L173-L230).

## Publish the function before opening its scope

The ordering in `cc-parse-function` is the central symbol invariant:

```text
consume return spelling, name, and (
find the prior visible symbol for the name
append the new function symbol with address = current output address
resolve both lists belonging to the prior function, if there is one
record main's address when the name matches
reset per-function state
push the function scope
parse parameters and body
pop that scope
```

Why look up first? C08's lookup returns the newest visible matching spelling. Looking up after append would find the new definition, whose fixup heads were initialized to zero. The promises attached to the earlier prototype would be missed.

Why append before scope push? The scope marker saves the count *including* the new function. Popping at the end then removes parameters and body locals while retaining the definition for later functions. The same early publication lets a body find its own function address for recursion, provided no newer local name hides it.

### Trace the two lists and the saved count

Use chosen builder state: live symbol count is 4; a prior prototype for `line` is ID 1; next output offset is 768 (`0x300`); image base is `0x400000`. The prototype's call list contains field offset 513, and its address list contains field offset 530. All lists and source spans are valid, and enough builder capacity is available.

| Completed builder action | Count | Relevant result |
|---|---:|---|
| Find prior spelling | 4 | Save prior ID 1 |
| Append definition | 5 | New ID 4: `sk-func`, int/depth 0, value `0x400300` |
| Walk prior call list | 5 | Patch field 513 with `0x400300−(0x400000+513+4)=251` |
| Clear prior call head | 5 | ID 1's call-head cell now holds zero |
| Walk prior address list | 5 | Patch field 530 with absolute `0x400300` |
| Clear prior address head | 5 | ID 1's address-head cell now holds zero |
| Push function scope | 5 | Save marker 5 |
| Append `pad`, then `n` | 7 | IDs 5/6 carry slots 0/1 |
| Pop function scope after body | 5 | IDs below 5 remain visible; ID 4 still names `line` |

The patched relative bytes are `FB 00 00 00`; the absolute bytes are `00 03 40 00 00 00 00 00`. C10 opened both walkers. Here the owner supplies the target and explicitly clears **both** heads. Walking alone does not clear them, and clearing does not free their arena nodes. The prior symbol's value is not rewritten to the new address by this routine; the newer definition wins lookup.

The saved prior ID can name something other than a function. Resolution runs only if it is nonnegative *and* its kind is `sk-func`. It does not reinterpret an object's auxiliary metadata as a function fixup list. This function parser does not perform a general duplicate-definition/signature compatibility check. Nor does it search past a newer nonfunction match to find an older prototype.

At this point no parameter or body instructions have been appended. Parameter parsing adds compiler metadata but no target code, so the current output address remains the first byte of the forthcoming prologue. Patching existing fields also leaves the append cursor unchanged. Recording `cc-main-vaddr` uses that same address only when `cc-is-main?` succeeds. It does not invoke `main`, patch the entry CALL, or create the process-entry stub; C19 owns those operations.

Source: [publication, both fixup walks, and main detection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L232-L271). C19's prototype producer supplies an unresolved `sk-func` value zero and avoids re-adding an already-visible function; see [`cc-register-fn-proto`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L290-L330).

## Begin each function with clean control bookkeeping

Before pushing the scope, `cc-parse-function` sets six builder cells to zero:

| Cell | What zero establishes for this function |
|---|---|
| `cc-fn-local-count` | The next parameter/local slot is slot 0 |
| `cc-label-count` | No label records are live for lookup |
| `cc-break-stack-head` | No active break-fixup list inherited from another function |
| `cc-continue-stack-head` | No active continue-fixup list inherited from another function |
| `cc-switch-depth` | No lexically open switches |
| `cc-loop-switch-depth` | No inherited loop-entry switch depth |

`cc-fn-param-count` is reset separately by the parameter-list parser. Clearing the label count does not clear every byte of the label arrays. Resetting list heads neither walks nor frees old lists. These resets prevent accidental cross-function ownership; they do not establish that an earlier malformed body had all its branches resolved.

Here is the precise body interface used from C16/C17, so this chapter does not require their drafts to be open:

- `cc-parse-stmt ( -- )` normally consumes one complete statement or supported declaration from the next pending/unread token and appends its code. The [legacy named-label branch](17-switches-labels-and-nonlocal-control.md#typedef-first-then-colon-then-expression) consumes only the label prefix; the repeated body loop picks up the following statement on its next call. Recursive statement consumers use `cc-parse-stmt-fwd`
- A nested compound receives `{` already consumed, pushes a compiler scope, parses until its matching `}` is consumed, then pops that scope; it does not rewind the local-slot counter
- Loops save and restore both enclosing break and continue heads. Switches save and restore break ownership while retaining the surrounding continue head; switch emission also creates a target saved-RBX obligation
- `cc-switch-depth` counts those lexically open switch obligations. Explicit return unwinds the full count; continue uses the depth difference from its enclosing loop. Legacy goto assumes a destination outside every switch
- Labels belong to the function-wide label table, separately from block-local symbol visibility. `114` does not call the native `cc-native-finish-gotos` finalizer or an equivalent undefined-label check; its end path does not promise the native finisher's error 174

The reset does not preserve some outer function context on a stack. This top-level definition path is not a nested-function compiler. It relies on the body consumers restoring their nested control state on normal parser return.

Sources: [function resets](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L273-L284), [compound entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L18-L35), [statement dispatcher](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L860-L905), and [switch-unwind interface](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L740-L803).

## Give each parameter a local identity

### Two parameter names, two slots

A parameter's source name gets a compiler record before any invocation supplies its value. For `line(int pad, int n)`, the parser creates two local records: `pad` names slot 0 and `n` names slot 1. Both the parameter count and the next-slot count become two. No target instruction has stored either argument yet. During a later call, the spill instructions copy the incoming register values into those slots.

For the call-frame route, continue at [Reserve once, initialize selectively](#reserve-once-initialize-selectively). The next sections explain how the parser produces these records from tokens.

### Parser detail: decide whether there are any parameters

`cc-parse-param-list` enters with `(` already consumed and no parameter-list token yet consumed by this helper. It resets the parameter count and reads the next token:

- `)` ends `()` immediately, with zero parameters
- A first token `void` triggers a full lexer mark. The helper reads one fresh token, saves whether it is `)`, and restores the mark
- If the saved answer is true, it consumes `)` again and returns with zero parameters
- Otherwise it puts the restored `void` back and enters the ordinary parameter loop
- A non-`void`, non-`)` first token is put back and enters the same loop

The decision survives restoration on the builder return stack. The mark includes cursor, current token, and pending status, as C06 established. It is not enough to restore only the byte cursor.

For `(void *p)`, the peek sees `*`, not `)`. Reset restores the consumed `void` state; putting it back makes it available as the loop's type token. For `(void)`, the peek's `)` is not left permanently consumed by the inspection: reset undoes that read, and the success branch deliberately reads it again. Both successful zero-parameter forms end with `)` consumed, not pending. Neither builds a signature distinguishing these two source forms.

### Parser detail: build one record per `type name`

The loop repeats the following complete algorithm:

1. Skip leading `const`/`volatile`/`restrict` qualifiers, leaving the first other token pending; read that type token
2. If it is `struct`, perform the strict tag lookup and save its descriptor in `cc-pending-struct-desc`; start with base `ty-struct`, pointer depth zero
3. For another keyword, clear the pending descriptor. Consume an optional enum tag when relevant. Start with `ty-char` for `char`, otherwise `ty-int`; consume remaining basic type keywords, allowing a later `char` to select the char base; start pointer depth at zero
4. For an identifier, find its symbol. Missing means error 180; a found non-typedef means 181. Clear the pending descriptor and unpack the typedef's **payload type word** into base and existing pointer depth
5. A token of neither keyword nor identifier gives error 182
6. Count additional stars, add them to the inherited pointer depth, and pack with `ty-make`
7. Read a required parameter name. A nonidentifier gives error 183
8. Append an `sk-local` with that name, packed type, and payload equal to current `cc-fn-local-count`; associate the pending descriptor with the returned ID
9. Claim one slot through `cc-fn-add-slots`, then increment the parameter count
10. Read the next token. A comma starts another iteration. Otherwise put that token back, reread it, and require `)`, with error 184 on failure

This is not the full declarator grammar from the later native provider. A name is required, arrays are not adjusted by this loop, and an inline `int (*fn)(int)` declarator is not handled here. A function-pointer **typedef** can supply its pre-encoded base/depth. The identifier-type path preserves that type encoding but explicitly clears the associated struct descriptor; do not infer that every typedef carries a complete descriptor through this parameter producer.

Keyword acceptance is also narrower in representation than its spelling may suggest. Ordinary legacy integer spellings collapse to int except char; `(void *p)` takes the ordinary non-char keyword path and produces int-base depth one here. A raw `struct TAG` parameter still claims only one slot: this loop does not implement passing a multiword aggregate by value. Our valid call traces use scalar integer/pointer values, at most six, with matching caller/callee expectations.

### Parser detail: work the builder stack for `pad`

For the first parameter in `line(int pad, int n)`, let `a/u` be the valid source span for `pad`, `T` its packed int type, `C=0` the next free slot, and `j` the new symbol ID. Builder top is at the right:

```text
[T]
[T, a, u]                 fetch the parameter name span
[a, u, T]                 rot
[a, u, sk-local, T]        push kind, then swap
[a, u, sk-local, T, 0]     fetch next slot
[j]                       cc-sym-add
[]                        associate descriptor zero with j
[]                        claim one slot; increment parameter count
```

After `pad`, both counts are one. After `n`, both are two; `pad`'s payload is 0 and `n`'s is 1. The builder did not put the integer arguments 1 and 5 in those records. Those values belong to the later invocation.

For a contrasting parameter `const struct tri *p`, strict lookup obtains descriptor D; the row has base struct, pointer depth one, one slot, and associated descriptor D. D describes the pointee; the slot will hold a pointer value, not a copy of the compiler descriptor. With a prior typedef `FUNCTION` whose payload encodes `ty-func` at depth one, `FUNCTION callback` retains that base/depth. Adding a star would raise the depth to two. The producer does not prove that every downstream indirect-call use accepts every such constructed type.

**Pause point.** Save “function marker includes its definition; `pad` slot 0, `n` slot 1; both counts 2; `)` consumed.” On returning, predict the first emitted byte and which target instruction first writes parameter storage. This checkpoint separates completed compiler metadata from target work that has not happened yet.

Sources: [ordinary parameter loop](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L42-L119), [empty/void cases](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L121-L147), and C15's [qualifier/star helpers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L121-L140) and [basic keyword scanner](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L531-L554).

## Reserve once, initialize selectively

After parameters, the parser consumes `{` and emits a prologue using `cc-frame-slots*8`. C15 established `cc-frame-slots=32`, so this is **256 bytes for every legacy function**, including an empty one. The eleven bytes are:

```text
55 48 89 E5 48 81 EC 00 01 00 00
push rbp; mov rbp,rsp; sub rsp,256
```

The fixed reservation avoids waiting until the body has revealed every local. The cost is unused space in small functions and a fixed limit in larger ones. Parameters and ordinary locals share slots 0–31. Nested block exit changes symbol visibility but never reuses a slot. A local static uses the separate storage mechanism from C15 and does not consume these frame slots.

### Six specific stores connect registers to names

`cc-emit-spill-params` has six independent threshold tests. For count at least one it stores RDI to slot 0; at least two stores RSI to slot 1; and so on. A **spill** here means storing an incoming register value into its stable local slot. All stores are qword stores; they do not resize the slot or select a narrower width because the source spelled `char`.

| Threshold | Incoming register | Local slot/address | Complete bytes |
|---:|---|---|---|
| 1 | RDI | 0: `RBP−8` | `48 89 7D F8` |
| 2 | RSI | 1: `RBP−16` | `48 89 75 F0` |
| 3 | RDX | 2: `RBP−24` | `48 89 55 E8` |
| 4 | RCX | 3: `RBP−32` | `48 89 4D E0` |
| 5 | R8 | 4: `RBP−40` | `4C 89 45 D8` |
| 6 | R9 | 5: `RBP−48` | `4C 89 4D D0` |

Each row is four bytes because slots 0–5 fit C09's disp8 address form. R8/R9 need the REX.R bit, accounting for `4C` instead of `48`. These instructions write memory without changing RSP. For `line`, the prologue plus its two stores occupies `11+4+4=19` bytes; the first body instruction follows those bytes. With six parameters the prefix is 35 bytes. With zero it is eleven.

Incoming registers can be overwritten by the body's expression work and calls. The frame slots retain the parameter copies until explicitly changed or the invocation ends. This is why `n=n-1` can update the local copy while `putchar` is free to use RDI for another argument.

For the first session, continue at [The default fall-through return](#the-default-fall-through-return). The following limits matter for the later parameter session and C18-05.

### Parser detail: the slot-limit failure point

`cc-fn-add-slots` checks the proposed count against 32 before incrementing the counter; exceeding it terminates with 162. That is not transaction rollback for the entire declaration. The parameter loop appends its symbol and associated descriptor **before** asking this helper to claim a slot. If an attempted thirty-third parameter reaches this check, its row has already been appended, the local count remains 32, and the parameter-count increment has not happened. Compilation terminates; no recovered table state is promised.

### Parsing seven is not receiving seven

The parameter loop has no six-parameter guard. Given seven ordinary named parameters and enough symbol capacity, it assigns slots 0–6 and leaves both counts at seven. Slot 6 is `RBP−56`, within the 256-byte frame. The spill routine still emits only the six listed stores: there is no seventh-register test and no load from an incoming stack-argument area. No incoming value for slot 6 is established by this prefix.

Meanwhile C14's legacy caller rejects **more than six argument expressions** with error 122, after parsing/staging them and before emitting the register pops and call. Frame capacity, header acceptance, and caller support are three different limits. A function with seven declared parameters is not thereby supported as a correctly callable seven-argument function. The legacy path also does not compare an argument count against a stored parameter signature. Calling that definition with fewer arguments does not supply the missing initialization guarantee.

This boundary is part of the inspected implementation. We do not replace it with a source fix, invent a seventh-register convention, or describe successful header parsing as successful argument transfer.

Sources: [spills](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L149-L170), [fixed-frame selection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L286-L292), [slot limit](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L29-L46), [register-store encoders](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L180-L216), and [legacy caller](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L580-L666).

## Let statements consume their own interiors

`cc-block-end?` answers one small question about the current token: is its kind punctuation **and** its payload `}`? Testing only the payload would ignore the token's classification.

The function's body loop reads a token, calls that predicate, and stops when it is true. Otherwise it puts the token back and calls `cc-parse-stmt`. It repeats after that parser has consumed its syntax; for a legacy named label, that means the label prefix, with its following statement picked up on the next iteration. The outer closing `}` is already consumed when the loop ends.

For this token fragment:

```c
{ int count; { int count; } return 7; }
```

The function parser has consumed the first `{` itself. Its loop hands `int count;` to the statement dispatcher. On seeing the next `{`, it puts it back; the dispatcher consumes it and invokes the compound parser. That nested parser owns the inner declaration, its matching `}`, and its scope pop. The function loop therefore does not stop at the inner brace. It resumes at `return`, and later consumes the actual outer `}`.

There is no extra compound-parser scope for the function's outer braces: the function scope already contains its parameters and top-level body locals. Nested compound scopes add markers above it. With no parameters in the fragment, the outer `count` gets slot 0 and the inner one slot 1; hiding the inner symbol does not lower the next-slot count of two.

The loop does not stop when it emits an explicit return. It keeps compiling later statements until the matching brace, even if some emitted instructions will be unreachable. It also has no separate end-of-file escape or missing-brace recovery path in `114`; malformed input is not granted a synthetic closing brace.

Source: [`cc-block-end?`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L32-L36) and [body loop](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L294-L302).

## Every normal route out needs a result and a return destination

C15's explicit-return parser supplies two legacy routes:

- `return;` consumes the semicolon, emits RAX=0, unwinds all open switch saves, then emits the epilogue
- `return expression;` puts back the first expression token, compiles/materializes the expression into RDI, invokes the default result hook to move RDI to RAX, unwinds switches, emits the epilogue, and consumes the required semicolon

In the stated legacy profile there is no return-shape check or typed conversion here; those conditional operations belong to LP64 providers. A bare return's zero is this emitter's behavior, not a rule that every C function may legally return without a value.

Switch unwind is runtime register/stack work. If two switch saves are open, a valued return emits the result transfer, two `POP RBX` instructions, and then the epilogue. The contract assumes expression evaluation has removed its own temporaries so those POPs reach the actual switch-save cells. Resetting RSP from RBP alone would discard storage but would not restore RBX's saved contents. The default epilogue's callee-restore hook emits no additional bytes; the switch consumer owns these saves.

### The default fall-through return

After the outer body brace, `cc-parse-function` **always** appends `cc-emit-xor-rax-rax` and `cc-emit-epilogue`. With default hooks that is eight bytes:

```text
48 31 C0 48 89 EC 5D C3
xor rax,rax; mov rsp,rbp; pop rbp; ret
```

It is the fall-through path, needed by `line`, whose last source statement is `putchar('\n');`. It also exists after `main`'s explicit returns. An executed explicit RET has already transferred control to the caller, so the later implicit sequence does not overwrite that returned value on that path. If some other path reaches the end, it returns zero under this implementation. No reachability analysis removes redundant bytes.

For the first session, continue at [Follow `line(1, 5)` across the boundary](#follow-line1-5-across-the-boundary). Compiler visibility is a separate part of the later publication/scope session.

### Restore compiler visibility

Finally the builder calls `cc-scope-pop`. This restores the symbol count saved after function registration. It hides parameters and remaining function-local symbols but emits no instructions, frees no arena objects, and does not reset `cc-fn-local-count`. The next function's entry reset handles that counter. Return execution and scope restoration are now connected without conflating them.

Source: [explicit-return implementation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L770-L803) and [implicit return plus scope pop](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L304-L310).

## Follow `line(1, 5)` across the boundary

Return to the canonical [C01 example](01-compiler-entry-and-profile.md#read-enough-c-to-follow-the-example), without changing its source. At `r=2`, `t.rows=4`, so `t.rows−1−r=1`, and `w[r]=1+r*2=5`. The call's arguments are those two values. C15 established that `main` has no parameters, array `w` at base slot 3, and `r` at slot 4, for five claimed slots.

For this trace assume:

- We are at a statement boundary in a valid invocation of `main`, with RSP `S=0x1000`, RBP `P=0x1100`, and no live expression temporary or switch save below S
- The argument expressions finish their own temporary pushes/pops, the known `line` address is valid, and sufficient target stack memory is writable
- Both functions use the stated legacy convention, their required parameter values have been supplied, and all calls reached in the trace meet the conditions under which their bodies operate
- K denotes the instruction immediately after the CALL to `line`; instruction addresses otherwise remain symbolic

The caller's array starts at `P−32=0x10E0`; `w[2]` is at `P−16=0x10F0`, holding five. Its variable `r` is at `P−40=0x10D8`, holding two. These are above the caller's reserved-frame bottom S.

Before reading the table, where will CALL put K, and which later instruction first writes `n`'s slot?

| Completed target action | RSP | RBP | Important state |
|---|---|---|---|
| Evaluate first argument, push RDI | `0x0FF8` | `0x1100` | `[0x0FF8]=1` |
| Evaluate second argument, push RDI | `0x0FF0` | `0x1100` | `[0x0FF0]=5` |
| Pop last argument into RSI | `0x0FF8` | `0x1100` | RSI=5 |
| Pop first argument into RDI | `0x1000` | `0x1100` | RDI=1 |
| CALL `line` | `0x0FF8` | `0x1100` | `[0x0FF8]=K` |
| PUSH RBP | `0x0FF0` | `0x1100` | `[0x0FF0]=0x1100` |
| MOV RBP,RSP | `0x0FF0` | `0x0FF0` | Callee base Q established |
| SUB RSP,256 | `0x0EF0` | `0x0FF0` | Reserve the callee's frame |
| Spill RDI to slot 0 | `0x0EF0` | `0x0FF0` | `[0x0FE8]=1`, named `pad` |
| Spill RSI to slot 1 | `0x0EF0` | `0x0FF0` | `[0x0FE0]=5`, named `n` |

Staging cells have been popped before CALL. CALL and PUSH RBP can reuse their addresses because those staged argument copies no longer own them. The argument values reached registers first, then different callee storage through spills.

The frame layout, from higher to lower addresses, is:

```text
0x1000       caller's pre-call stack boundary S
0x0FF8       return destination K                  = Q+8
0x0FF0       saved caller RBP, 0x1100               = Q
0x0FE8       pad, slot 0                            = Q-8
0x0FE0       n, slot 1                              = Q-16
...          other reserved slots, contents unknown
0x0EF0       slot 31; callee's baseline RSP          = Q-256
```

Each displayed cell is eight bytes. The ellipsis contains reserved but uninitialized local storage, not extra saved return destinations. At a later expression push, RSP would move below `0x0EF0`; the local slots stay at their RBP-relative addresses.

`line`'s loops change its own slots to zero. They do not store to `main`'s `w[2]` at `0x10F0`. After the final `putchar`, with its call sequence complete and no open switch saves, the implicit return proceeds:

| Completed target action | RSP | RBP | RAX/control |
|---|---|---|---|
| XOR RAX,RAX | `0x0EF0` | `0x0FF0` | RAX=0 |
| MOV RSP,RBP | `0x0FF0` | `0x0FF0` | Frame extent discarded |
| POP RBP | `0x0FF8` | `0x1100` | Caller base restored |
| RET | `0x1000` | `0x1100` | Resume at K, RAX=0 |
| Caller's MOV RDI,RAX | `0x1000` | `0x1100` | RDI=0 as expression result |

The source call is an expression statement, so that incidental zero is ignored. `w[2]` remains five. The returned frame bytes are not erased, but the completed invocation no longer owns them as live locals. This trace proves no output syscall succeeded; it explains storage and control under the stated body/call premises.

You have reached the first session's stopping point: the caller's frame is restored and `w[2]` is unchanged. Try [C18-04](#c18-04--reconstruct-a-complete-call-frame), including its six-parameter changed case, before continuing.

### Add a body local and an explicit result

For the later returns session and C18-06, keep the same frame construction but use this illustrative admitted definition:

```c
int add(int pad, int n) {
    int total;
    total = pad + n;
    return total;
}
```

After its two parameters, local count is two. C15's ordinary declaration gives `total` slot 2 and raises the count to three, without changing the already-emitted 256-byte reservation. For callee base Q, its address is `Q−24`; with the preceding chosen Q=`0x0FF0`, that is `0x0FD8`. The declaration emits no initialization store.

For incoming values two and three, the spills establish `pad=2` and `n=3`. C13's binary-expression sequence loads the left value, pushes it temporarily below the frame baseline, loads the right value, moves it to RCX, and pops the left value back to RDI. ADD produces five; assignment stores five to `total`. Its temporary is gone before the return expression loads `total`, moves five to RAX, and executes the epilogue. The caller receives five in RAX and then RDI, with its original RSP restored. The later implicit zero-return bytes are present but are not reached on this explicit-return path. These are derived value/storage transitions, not an executed `add` test.

## Balanced is not necessarily aligned

The ordinary integer/pointer System V stack-boundary comparison used here is: RSP is a multiple of 16 immediately before CALL, and therefore has remainder eight on callee entry after the pushed return address. The fixed-frame prologue restores remainder zero by pushing RBP and subtracting 256. This limited alignment rule is specified in the [x86-64 psABI draft 0.21, §3.2.2, page 14](https://refspecs.linuxfoundation.org/elf/x86_64-SysV-psABI.pdf), consulted October 6, 2026. It is one ABI condition, not a complete interoperability test or a claim about every wider-vector calling case.

The important premise is the caller's **actual RSP at the call instruction**. The prologue establishes an aligned baseline only when its own incoming call satisfies that premise. An odd number of live eight-byte saves below the baseline flips the remainder to eight. An even number preserves zero. The size of the reserved local frame is not the number of currently live temporary pushes.

### One live outer argument is enough to change the answer

Consider this illustrative expression with valid scalar callees:

```c
combine(10, leaf(20))
```

Start at the same aligned body baseline `S=0x1000`, outside switches, with no pre-existing expression temporary. Assume `leaf` can complete under the shown machine state; the point is to test the alignment promise, not to predict a particular fault. C14's left-to-right staging emits the following transitions:

| Completed action | RSP | Remainder modulo 16 | Live staged values, bottom-to-top |
|---|---|---:|---|
| Outer first argument 10 pushed | `0x0FF8` | 8 | `[10]` |
| Inner argument 20 pushed | `0x0FF0` | 0 | `[10,20]` |
| Inner pop into RDI | `0x0FF8` | 8 | `[10]` |
| CALL `leaf` | `0x0FF0` | 0 | Outer 10 plus inner return control |
| Inner PUSH RBP; MOV RBP,RSP | `0x0FE8` | 8 | Outer 10 still belongs to outer call |
| Inner SUB RSP,256 | `0x0EE8` | 8 | Inner body baseline is misaligned |
| Inner epilogue and RET complete | `0x0FF8` | 8 | `[10]` |
| Push inner result as outer argument 2 | `0x0FF0` | 0 | `[10,result]` |
| Outer POP RSI; POP RDI | `0x1000` | 0 | `[]` |
| CALL `combine` | `0x0FF8` | 8 | Correct entry remainder for this call |

The inner push/pop pair is balanced. It restores RSP to `S−8`, the value before **its own** argument staging, because the outer 10 still needs to survive. It does not restore S. Thus `leaf` was called with remainder eight instead of zero, and its ordinary fixed prologue does not repair that parity. The later call to `combine` meets this one condition after both outer arguments are popped.

The nearby legacy call comment about balanced nested sequences does not establish universal alignment: balance is relative to an entry value, while alignment is a property of that value. The emitted sequence contains no legacy dynamic padding step. Existing expression saves or switch-RBX saves can likewise affect the remainder; they must be included in the actual live-stack count. Conversely, nesting alone is not the decisive condition: `combine(leaf(20), 10)` reaches `leaf` before either outer argument has been staged.

Keep the conclusions bounded. This paper counterexample demonstrates the failed alignment precondition; it does not show that the displayed legacy instructions necessarily fault, and it is not a new runtime experiment. It also explains why this chapter teaches a restricted calling convention rather than certifying general System V calls. C23/G04 later open different frame/call providers; they are not silently substituted into this trace.

**Stop/resume point.** Save “before inner CALL: RSP=S−8; own pushes balance to their starting RSP; outer value remains live.” When returning, change the number of already-staged outer arguments and derive parity before consulting the table. If only addresses are confusing, first trace remainders 0/8 without names or values.

## Compare the later seams without merging their mechanisms

This optional comparison supports C18-09. Two later function drivers reuse some interfaces but change their ownership rules. Their full bodies belong to C23 and G04, respectively. The following is an inspected seam comparison, not an alternative implementation to run in this chapter:

| Question | Legacy `114` | Native `117` / System V provider `121` |
|---|---|---|
| Where is the function address published? | Append a newer `sk-func`; patch prior entry's two lists | Reuse/install the selected record, publish its address, patch and clear its two heads |
| Is the return spelling retained? | Consumed; definition symbol gets int/depth 0 | Native type/descriptor are retained; `121` also builds/checks a function signature |
| How do parameters get storage? | Positive local slots, six register stores | `117` private stack parameters use negative slot coordinates; active `121` uses its signature/parameter placement hooks |
| How is the frame size chosen? | Emit 256 immediately | Emit zero as a placeholder, save its four-byte field offset, later patch aligned `local-count*8` |
| What body completion is added? | Implicit zero return, then scope pop | Native goto finalization; active `121` additionally requires its tracked stack depth to be zero |
| What reserved local policy applies? | Start count 0 | `117` starts 0; active `121` starts 1 for its saved-callee policy |

In `117`, parameter index i is represented as slot `−(i+3)`. C09's slot formula therefore addresses `RBP+8*(i+2)`: the first parameter is at `RBP+16`. That is incoming stack storage under the private convention, not a legacy seventh parameter at `RBP−56`. The native frame field is captured at `cc-out-pos−4` just after the prologue; after the body its size becomes `align_up(local-count*8,16)`. The later lesson explains its parser/context and private caller in full.

`121`'s `cc-sysv-function` falls back to `cc-native-function` when `cc-target-sysv` is false. Active System V selects signature checks, parameter/varargs hooks, saved-callee state, and tracked temporary depth; merely loading its name or setting LP64 does not make `114` acquire those behaviors. We do not infer complete ABI support from this short comparison.

Sources: [`117`, native parameter/frame seams](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/117-cc-native-program.fth#L1-L77) and [`121`, function/signature driver](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L1193-L1260).

## Practice: join the records, bytes, and lifetimes

Use paper or read-only source inspection. These tasks request no builds, implementation changes, or example execution. [Graduated hints and checked solutions](../practice/18-solutions.md) are separate. Give at least one decisive intermediate state, not only the final number.

### C18-01 — Publish, patch, and retain

Start with symbol count 8 and prior `line` prototype ID 2. Its call head records field offset 901; its address head records field offset 930. The definition begins at output offset 1200, image base `0x400000`. Trace prior lookup, new ID, both patches and head clears, scope marker, two parameter IDs, and final visible count. Give both patch byte sequences. Explain what fails if prior lookup or scope push moves across append.

### C18-02 — Follow the parameter tokens

For independent inputs `()`, `(void)`, and `(void *p)`, enter immediately after `(`. Trace current/pending tokens at the zero-parameter decision and at return. For the last input give the produced base, pointer depth, slot, and descriptor. Then explain why unnamed `(int)` and the ordinary-loop suffix `int x]` reach different errors.

### C18-03 — Keep type and descriptor channels separate

Assume a visible struct tag `tri` with descriptor D and a typedef `FUNCTION` whose payload encodes function base, depth one. Parse `(const struct tri *p, FUNCTION fn, unsigned char *s)`. Build the three symbol rows and both counters. Show the builder stack at the five-argument `cc-sym-add` boundary for `fn`. Explain what extra information is and is not inherited from a typedef.

### C18-04 — Reconstruct a complete call frame

For `line(2,3)`, use caller RSP `0x2000`, caller RBP `0x2100`, and return destination K. Give every staging/pop/CALL/prologue transition, parameter addresses, slot 31, and the default fall-through epilogue's pointer states. State the prefix and implicit-return byte counts. Explain why callee writes to `n` do not change a separately owned caller scalar used to supply the argument.

### C18-05 — Distinguish three limits

Compare seven named scalar parameters, six parameters plus an ordinary local array of 26 legacy ints, and six parameters plus an array of 27. State parameter/local counts, initialized parameter slots, total reserved bytes, and applicable caller or allocation errors. For the failing local declaration, distinguish the counter check from rollback of earlier symbol writes. Do not pretend the header's acceptance supplies a seventh incoming value.

### C18-06 — Reconstruct the exits

A valid function has two open switch saves when it reaches `return 7;`. Explain the order of result transfer, RBX restoration, frame teardown, and semicolon consumption. Contrast `return;` and fall-through after all structured body statements have finished. Why is the always-emitted implicit tail not executed after a taken explicit return? What must be true of expression temporaries when switch unwind begins?

### C18-07 — Test the actual call boundary

Start with a supported reconstruction of the worked case: at aligned baseline S, outside switches and with no older temporary, trace `combine(10, leaf(20))` using remainders modulo 16. Then trace `combine(leaf(20),10)`. State what own-argument balance proves and what it does not prove. Which precise caller/body premise is missing if someone claims that the fixed 256-byte frame guarantees every nested call is aligned?

### C18-08 — Restore names without reusing slots

Before a definition, symbol count is 3. The new function has two parameters, followed by `int outer; { int inner; } int after;`. Trace symbol IDs, scope markers, and slot counts through the nested pop and function pop. Separately list the function-entry resets and explain why label state, symbol state, and target frame state are not one stack.

### C18-09 — Choose a provider from evidence

A paper trace shows first parameter slot −3, a prologue immediate initially zero, and a final frame patch based on five claimed local slots rounded to 16 bytes. Which named provider fits? Derive its first parameter's RBP-relative address and patched size. Contrast what `114` would emit for five claimed slots, and name two facts that would still be needed before calling the trace a general System V implementation.

### Changed-case prompts, with answers kept separate

After checking an exercise, close the solution and change the consequential condition:

- **C18-01:** Remove the prior prototype, then separately make the newest same-spelling row a nonfunction. Trace which heads, if any, this consumer touches
- **C18-02:** Replace `(void *p)` with `(void **p)`; then insert a qualifier before `void`. Follow the actual first-token special case rather than applying a C grammar rule from memory
- **C18-03:** Replace `FUNCTION fn` with `FUNCTION *fn`, and place a newer ordinary local named `FUNCTION` in scope before parsing this independent parameter list
- **C18-04:** Change caller baseline to `0x3000` and use a six-parameter callee. Name the last spilled slot and all saved-control cells without assuming unused slots are zero
- **C18-05:** Begin with 31 successfully allocated named parameters and attempt the next two. Separate header parsing, slot allocation, spill emission, and calling support
- **C18-06:** Use `return n;` with one open switch and a fully evaluated local value nine. Then consider a hypothetical missing switch restore while retaining MOV RSP,RBP
- **C18-07:** Use `combine(10,20,leaf(30))`, then return to the original expression while adding one pre-existing switch save below the aligned body baseline
- **C18-08:** Replace the inner block with an empty block, then with a local static. Track which counters change and what remains allocated after each scope pop
- **C18-09:** Change the local count to six, then consider active `121` with its initial saved-callee slot. Identify which count includes that reserved slot before rounding

If the frame is right but the alignment claim is wrong, keep the frame and retrace the live eight-byte saves. For a token or symbol mismatch, return to that producer's first differing step.

## Source closure and what to carry forward

All named declarations and algorithms in `114` have a home in this chapter:

| Pinned source region | Items explained |
|---|---|
| Lines 12–30 | Four bookkeeping variables, `cc-main-name-bytes`, `cc-is-main?` |
| Lines 32–36 | `cc-block-end?` and its current-token contract |
| Lines 42–119 | `cc-parse-param-list-loop`: type/name/descriptor construction, counters, delimiters, errors |
| Lines 121–147 | `cc-parse-param-list`: empty and exact `(void)` cases, mark/reset fallback |
| Lines 149–170 | `cc-emit-spill-params`: all six guarded stores |
| Lines 173–198 | `cc-parse-fn-return-type`: spelling consumption and discarded return metadata |
| Lines 200–310 | `cc-parse-function`: publication, both fixup heads, main address, resets, scope, parameters, frame, body, implicit return, restoration |

The important invariant is now a chain: **publish the callable address; retain only function-lifetime compiler state; assign parameter/local slots; establish and initialize the target frame; meet every actual call boundary's preconditions; return using saved control; restore compiler visibility separately**. A missing link cannot be supplied by the fact that another link succeeded.

C19 completes translation-unit work: file-scope forms, entry-stub patching, final symbol checks, and storage finalization. This chapter supplies its function-definition contract. The native frame-patch and signature-aware ABI implementations remain C23/G04 mechanisms. Our evidence is pinned-source inspection plus manual traces and checked exercise reasoning, with execution, rendered-layout review, and actual-reader learning outcomes still unverified.
