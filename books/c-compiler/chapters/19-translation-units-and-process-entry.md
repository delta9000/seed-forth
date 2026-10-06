# 19. Translation units and process entry

Here is a complete program small enough to keep in view:

```c
int main(void) { return 7; }
```

There is no caller in its C source. Who calls `main`, and who receives the seven? Before reading on, predict three things: whether seven is printed, whether the processor starts at `main`, and whether an unused runtime function occupies any output bytes.

We will follow this program from source to a complete predicted file layout, then follow the generated instructions from process entry to exit. The later reference sessions open the other file-scope forms. The first story carries its needed byte and frame facts with it.

**Profile and evidence.** The inspected implementation is [`116-cc-prog.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth) and [`120-cc-main.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/120-cc-main.fth), at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`. Use a fresh legacy Linux/x86-64 builder, `cc-target-lp64=0`, `cc-target-sysv=0`, and the ordinary default hooks. Counts, bytes, and machine states below are source-derived predictions; no compiler, Forth program, generated executable, or build was run. C20 retains the separate work of comparing actual Stage-A artifacts.

For the paper trace, assume admitted syntax, retained source bytes, sufficient builder capacity, and nonwrapping address/count arithmetic. When we reach target execution, additionally assume the image is loaded at its specified addresses, a valid initially 16-aligned Linux process stack, and a successful exit request in this single-threaded process. Those assumptions make the transitions meaningful; they are not measurements of a created file.

## Start with two times and three coordinates

The **builder** is the Forth compiler running now. The **target** is the generated C program running later. Emitting an instruction changes the builder's output buffer. It does not execute that instruction in either program.

A **translation unit** here is the preprocessed source stream that this invocation parses through end of input. The driver produces one direct executable from that stream. It does not emit a relocatable object and ask a separate linker to supply unresolved bodies.

We count file offsets in decimal bytes from zero; hexadecimal numbers carry `0x`, and stored bytes appear as pairs such as `48`. Multibyte fields are little-endian. The fixed load base is `0x400000`, so a file-backed byte at offset 522 has target virtual address `0x40020A`. A builder pointer such as `cc-out-buf+522` refers to a different process's storage.

For this chapter's reasoning, recall two short rules:

- Appending bytes advances `cc-out-pos`; patching an existing field does not
- A four-byte CALL displacement is measured from the end of that field, the address of the next instruction

If those rules are uncertain, keep the three coordinates written beside the next trace. [C09](09-instructions-inside-an-executable.md#one-byte-three-coordinates) supplies the address bridge; the calculation below supplies its concrete use. An experienced reader can attempt C19-01 first and return only to the step that differs.

## The builder begins before the target has an entry point

The driving Forth definition is short enough to read whole:

```forth
: cc-main
  cc-load-stdin
  cc-preprocess
  cc-out-init
  cc-globals-init
  cc-emit-elf-header
  cc-parse-program
  cc-finalize-globals
  cc-finalize-elf
  cc-out-path cc-write-output
  bye ;
```

The first two calls read the C input and prepare the source stream for the lexer. This fixture needs no include or macro expansion. `cc-out-init` sets the output cursor to zero. `cc-globals-init` resets the data/BSS allocation and global-reference counts and zeros the globals buffer. Neither operation emits target code.

Next, `cc-emit-elf-header` writes 64 bytes of ELF header and one 56-byte load-segment description. ELF is the file envelope that tells the loader where the image belongs and where execution begins. The next offset is therefore `64+56=120`. Its entry field already names `0x400078`, the target address of offset 120. It does not yet name the still-unseen C definition of `main`.

The one load segment begins at file offset zero and virtual address `0x400000`. Its flags permit reading, writing, and execution. Its file size starts at zero, awaiting finalization; its memory size starts at 81,920 bytes. These are header fields, not generated instructions. [The exact header and size finalizer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/080-cc-elf.fth#L9-L80) explain why the program can contain both code and writable runtime state in this image.

## Reserve the first call before knowing its destination

`cc-parse-program` first calls `cc-emit-entry-stub`. A **stub** is a short bridge: this one will translate process-start state into a function call, then translate the returned value into an exit request.

The builder appends these 26 bytes immediately after the header. The table shows the initial, unpatched CALL field. Instructions use destination-first assembly notation; brackets mean a memory access, while LEA computes an address without loading the pointed-to value.

| File offset | Bytes before the CALL patch | Later target operation |
|---:|---|---|
| 120 | `48 8B 3C 24` | `mov rdi,[rsp]`: read argc |
| 124 | `48 8D 74 24 08` | `lea rsi,[rsp+8]`: form argv's address |
| 129 | `E8 00 00 00 00` | `call main`: destination still pending |
| 134 | `48 89 C7` | `mov rdi,rax`: copy the returned value |
| 137 | `48 C7 C0 3C 00 00 00` | `mov rax,60`: select Linux exit |
| 144 | `0F 05` | `syscall`: request exit with RDI's value |

At offset 129 the emitter appends opcode E8. The cursor is now 130, the first byte of the four-byte displacement. It stores **130**, not 129, in `cc-call-main-patch`, then appends four zeros. That saved offset identifies the field that will need repair. The rest of the stub brings the cursor to 146.

Nothing has called `main` yet. In particular, emitting the final SYSCALL bytes does not terminate the builder. The builder proceeds to construct the remainder of the file.

Source: [entry-byte appends and field recording](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L573-L622).

## The runtime occupies bytes even when this program does not call it

Before parsing user definitions, `cc-emit-shims` registers and emits eleven small runtime bodies. Registration makes their names available to C calls; emission gives those names actual target destinations. Their bodies are eager: they are appended whether this input uses them or not.

Here is the whole byte-count bridge needed for our program. The more detailed runtime behavior remains in [C11](11-a-bounded-legacy-runtime.md#which-bodies-are-present-and-who-owns-their-bytes).

| Eager body | Start offset | Region length |
|---|---:|---:|
| `putchar` | 146 | 29 |
| `exit` | 175 | 10 |
| `getchar` | 185 | 48 |
| `fputs` | 233 | 33 |
| `fputc` | 266 | 29 |
| `fopen` | 295 | 51 |
| `fclose` | 346 | 12 |
| `fwrite` | 358 | 20 |
| `fread` | 378 | 30 |
| `calloc` | 408 | 113 |
| `free` | 521 | 1 |

The lengths sum to 376, so the next output offset is `146+376=522`. The `calloc` region includes sixteen zero-initialized bytes of heap bookkeeping after its instructions. Calling all 376 bytes “instructions” would lose that distinction. Those cells are also separate from the user-global buffer.

The builder now registers eight late-runtime names, one external prototype, and twelve built-in typedef names. These steps add symbol records but no output bytes. A late body is emitted only if a call or address use remains pending after user definitions. Our input uses none of them, so the cursor stays 522.

Thus there are already three different products: bytes describing the executable, bytes containing code and runtime state, and builder-only name/type records. Appending a symbol record does not necessarily enlarge the target file.

Sources: [runtime registration order](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L638-L846) and [the counted eager emitters](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L559-L900).

## Read the definition and give the call a destination

The top-level loop reads `int`. It must decide whether this begins an object, a prototype, or a function body. `cc-top-classify` saves the lexer state, scans ahead, sees parentheses and then a `{` at parenthesis depth zero, and returns `top-fndef`. It restores the saved state before returning. The function parser therefore receives the original declaration, rather than starting somewhere inside the body. This loop emits every user function definition in source order, even when no call refers to it; it does not remove unused definitions.

The parser reads the name `main` and registers an `sk-func` record with the current target address:

```text
main's file offset = 522 = 0x20A
main's target address = 0x400000 + 0x20A = 0x40020A
```

The exact-name test also stores this address in `cc-main-vaddr`. This is the missing destination for the entry CALL. Its patch is deliberately left to program completion.

`(void)` creates no parameter records or spills. C18's fixed legacy prologue still reserves 256 stack bytes. Parsing `return 7;` emits the integer value into RDI, moves it into result register RAX, and emits the epilogue. At the closing brace the function producer unconditionally appends its fallback zero return, even though this particular path cannot reach it.

The entire generated function is therefore 34 bytes. Each row starts at the listed offset; ranges are inclusive.

| File range | Bytes | Reason for these bytes |
|---|---|---|
| 522–532 | `55 48 89 E5 48 81 EC 00 01 00 00` | Save RBP, establish frame, reserve 256 bytes |
| 533–539 | `48 C7 C7 07 00 00 00` | Put seven in RDI |
| 540–542 | `48 89 F8` | Transfer seven to RAX |
| 543–547 | `48 89 EC 5D C3` | Restore stack/frame and return |
| 548–550 | `48 31 C0` | Fallback result zero |
| 551–555 | `48 89 EC 5D C3` | Fallback epilogue |

The first row has `1+3+7=11` bytes. The following rows have `7+3+5+3+5=23`, giving `11+23=34`. The cursor becomes 556. The parser then hides the function's parameter/local scope; `main` itself was registered outside that scope and remains visible.

The source-to-byte bridge uses [function registration and body emission](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L220-L310), [valued return](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L783-L803), and [the fixed prologue/epilogue encoders](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L335-L359). Default hooks add no extra restore code here.

## Close the promises before closing the file

The source loop reaches EOF. The late-shim pass finds no waiting uses and emits nothing. `cc-check-fns-defined` finds no pending function call/address lists, and `cc-main-vaddr` is nonzero. Only then does `cc-patch-call-main` fill the saved field:

```forth
: cc-patch-call-main
  cc-main-vaddr @
  cc-base-vaddr cc-call-main-patch @ + [lit] 4 + -
  cc-call-main-patch @
  cc-out-patch-4le ;
```

Its subtraction is destination minus next instruction:

```text
0x40020A − (0x400000 + 130 + 4)
= 522 − 134
= 388 = 0x184
```

The four bytes at offsets 130–133 become `84 01 00 00`. The final CALL at 129 is `E8 84 01 00 00`; its next instruction is still at 134. The output cursor stays 556 because a patch overwrites an existing field.

This entry CALL is **not** an item on `main`'s pending function-call list. `cc-call-main-patch` owns this one special field; `cc-main-vaddr` supplies its destination. Ordinary forward C calls and function-address expressions use the symbol-owned lists from C10/C18. They have the same need for a future destination, but different owners and completion paths.

Back in `cc-main`, `cc-finalize-globals` finds no user data and no BSS allocation. It appends nothing. Both prospective global bases become `0x40022C`, the target address of cursor 556, but there are no global-reference fields to patch.

`cc-finalize-elf` writes 556 into the low four bytes of `p_filesz` at file offset 96. Its full eight-byte field becomes `2C 02 00 00 00 00 00 00`. The image plus BSS is smaller than the header's minimum 81,920, so `p_memsz` remains `00 40 01 00 00 00 00 00`. The ELF entry remains `0x400078`.

The result is a **predicted 556-byte image**, ready for a write attempt. The driver passes the NUL-terminated path `/tmp/cc-out` to `cc-write-output`, then ends the builder with `bye`. The writer opens with write/create/truncate flags, requests one write of the buffer, and closes. It rejects a failed open, but discards the write and close results. A 556-byte output cursor does not establish that a 556-byte file was successfully stored.

Sources: [completion order and checks](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L849-L884), [global placement](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L478-L514), and [one-write output path](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth#L171-L195).

## Now let the target follow those bytes

Switch times. Suppose the completed image is loaded under our stated target assumptions. Let the initial target RSP be S, a multiple of sixteen, and call the incoming RBP value P. The table shows machine state **after** each operation. CALL and PUSH consume eight bytes downward; RSP points at the occupied top cell after each push.

| Reached code | RSP afterward | Newly established fact |
|---|---|---|
| Entry at `0x400078`: two argument preparations | S | RDI=argc; RSI=S+8, the argv address |
| CALL at `0x400081` | S−8 | `[S−8]=0x400086`, the return destination; next code is `main` |
| `main`: PUSH RBP; MOV RBP,RSP | S−16 | `[S−16]=P`; RBP=S−16 |
| SUB RSP,256 | S−272 | The fixed frame is reserved |
| MOV RDI,7; MOV RAX,RDI | S−272 | RAX=7 |
| MOV RSP,RBP; POP RBP | S−8 | The saved P is restored; return destination is on top |
| RET at file offset 547 | S | Execution resumes at `0x400086`, file offset 134 |
| Entry's MOV RDI,RAX | S | Exit argument becomes 7 |
| MOV RAX,60; SYSCALL | S before the request | Request exit with value 7 |

The explicit RET returns to the stub, not to the next bytes of `main`. The unreachable zero at offset 548 therefore cannot replace the seven. The CALL also jumps over the eager runtime region; merely placing those bodies before `main` does not make them run first. No user stdout operation is reached, so seven is not printed. Under the successful exit assumption, the waiting parent would receive status 7.

The stub prepares argc and argv even though this `main(void)` ignores them. It supplies no third envp argument, constructor walk, hosted stream setup, or exit-handler machinery. Its first CALL meets the stated alignment condition because S starts aligned and the stub does not change RSP before CALL. C18's nested-call example shows why that local fact does not establish general System V ABI conformance.

We can now answer the opening question without inventing a C caller: the generated entry stub calls `main`, receives seven in RAX, and passes seven to Linux's exit interface. The builder's final `bye` and the generated exit request belong to different executions.

### Change one byte; then change the path

Change the source to `int main(void) { return 8; }`. Predict before checking: does the entry displacement change?

It does not. The literal instruction stays seven bytes long; its byte at file offset 536 changes from `07` to `08`. The location of `main`, the CALL displacement, and the 556-byte cursor stay the same. The target prediction changes to exit argument eight.

Now remove the explicit return entirely: `int main(void) { }`. The fixed prologue and fallback tail remain, but the fifteen explicit-return bytes disappear. The function becomes `11+8=19` bytes and the cursor becomes 541. Its start is still 522, so the entry displacement is still 388. This path reaches the fallback zero and predicts exit argument zero. A changed file length need not mean a changed entry CALL destination.

**Stop/resume point.** Save four facts: entry 120, CALL field 130, `main` 522, original end 556. On returning, explain why the return destination is 134 and why the fallback tail is present but unexecuted in the original. If only the subtraction is difficult, complete `522−(130+__)` first. If the mechanism is secure, continue with the independent practice or choose a reference session below.

## Choose a second session

The complete small-program story is now closed. The remaining sessions explain how the same driver handles a less empty translation unit:

- **Names and classification:** read the next three sections, then try C19-02 and C19-03
- **Objects and addresses:** follow the `tri`, `g`, and `a` trace, then try C19-04 and C19-05
- **Completion and loading:** revisit late names, final checks, and the executing last file, then try C19-06 and C19-07

These sections cover the remaining source mechanisms. They reuse C10's patch walkers, C11's runtime bodies, and C15's record builder rather than pretending those algorithms live in `116`.

## Reference: metadata can change parsing without adding target bytes

Consider this beginning of a different translation unit:

```c
enum E { A, B = A + 3, C, };
typedef int *IP;
```

Both declarations change what later source names mean. Neither, by itself, allocates a target object or emits a runtime assignment.

### Enumerators receive values in source order

`cc-parse-top-decl` has already consumed `enum`. `cc-parse-enum-def` reads and discards an optional tag such as E; it does not create an enum-tag record. If that first token is not an identifier, it puts it back for the opening-brace expectation. The parser requires `{`, sets `cc-enum-next-val` to zero, then processes one enumerator at a time.

| Enumerator | Builder calculation before registration | New symbol | Next default value |
|---|---|---|---:|
| A | No `=`; use current zero | `sk-enum`, unused type field 0, payload 0 | 1 |
| B | `cc-parse-const` calculates `A+3=3` | `sk-enum`, type 0, payload 3 | 4 |
| C | No `=`; use current four | `sk-enum`, type 0, payload 4 | 5 |

A's row exists before the constant parser reads `A+3`; newest-first symbol lookup can therefore supply its value. `cc-parse-const` computes a builder integer here. It does not emit target addition instructions. The next-value variable is scratch for this enum parser, not a global C variable named E.

The loop expects an identifier, otherwise error 190. After each registration it increments the default, then consumes a separator. A comma normally continues; a comma followed by `}` stops and puts the brace back. A direct `}` also stops and is put back. Any other separator reaches 192. On the shared exit, the brace and semicolon expectations consume `};` once. Empty enums do not pass the first identifier requirement. Use admitted constant expressions and bounded arithmetic; the loop adds no duplicate-enumerator or overflow analysis of its own.

Source: [enum state, optional tag, and separator ownership](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L30-L99).

### A typedef carries an encoding, not an object address

`cc-parse-typedef` also enters after its keyword. It stages the packed type in `cc-td-ty` while later reads replace the token fields. It recognizes keyword bases `int`, `char`, `void`, `struct TAG`, and `enum TAG`, or an existing typedef identifier. An existing typedef contributes its stored payload, preserving inherited pointer depth; each additional star increments that encoding.

For our `IP`, the base is `ty-int=2`, and the packing rule is `base*65536+pointer-depth`. One star gives `2*65536+1=131073`, hexadecimal `0x20001`. The parser records `IP` as `sk-typedef`, type field zero, payload `0x20001`. This number is a description of a type. It is neither a target pointer nor a reserved data slot.

A subsequent `typedef IP *IPP;` fetches `0x20001`, adds one star, and records `0x20002`. By contrast, `struct TAG` uses strict tag lookup but discards the returned descriptor before recording the `ty-struct` encoding. This word does not preserve a complete record layout in its typedef payload. `enum TAG` consumes an optional tag and uses the integer encoding.

There is a second declarator shape:

```c
typedef void (*FUNCTION)(void);
```

After the base, seeing `(` selects the function-pointer branch. It consumes stars, a name, `)`, and `(`, then skips the parameter tokens with a parenthesis-depth counter starting at one. Each inner `(` increments; each `)` decrements. When depth reaches zero, it records `FUNCTION` as `sk-typedef` with payload `ty-func` at depth one, `0x40001`, and consumes the final semicolon. The signature's return and parameter types are not retained as a checked function type.

The star count in this branch is consumed and discarded, without an explicit nonzero test. Its parenthesis loop has no separate EOF escape. Those are reasons to retain the admitted, balanced function-pointer spelling as a precondition, rather than promise a helpful error for every malformed input. Nor should the nearby historical comment about mere parse-through be expanded into a universal ban on later use: C18's parameter path preserves typedef encoding, and the legacy call consumer recognizes a matching local `ty-func` symbol. That is still a restricted local-pointer route, not a signature checker or arbitrary callable-expression mechanism.

The plain branch requires an identifier and records the staged encoding. Despite a nearby comment mentioning putback, the body uses the already-current identifier directly; it does not put it back. Both branches finish by expecting `;`.

The local error sites make this narrow contract inspectable: 193 for an unsupported keyword base; 194 for a missing typedef lookup; 195 for a found non-typedef; 196 for a base that is neither keyword nor identifier; 197 for a missing function-pointer name; and 198 for a missing plain alias name. Shared punctuation/tag helpers retain their own checks.

Sources: [both typedef paths](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L98-L195) and [packed type representation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/060-cc-types.fth#L19-L75).

## Reference: classify without consuming

The top-level loop must distinguish a definition from a use of a type before choosing a parser. It begins each item with C15's `cc-skip-storage-quals`, then reads the first token. EOF ends the loop. Otherwise `cc-parse-top-decl` owns the dispatch.

Its first three opportunities are specialized:

- Current `enum`: `cc-enum-def-ahead?` marks the lexer, reads the next token, skips one optional identifier, tests for `{`, and resets. A match enters the enum-definition parser
- Current `typedef`: enter `cc-parse-typedef` immediately, with the keyword consumed
- Current `struct`: `cc-struct-def-ahead?` marks, reads two tokens, tests whether the second is `{`, and resets. For admitted `struct TAG {`, enter C15's `cc-parse-struct-def`

These predicates emit nothing. The struct predicate itself does not validate that the intervening token is an identifier; the chosen definition parser has its own expectations. A `struct TAG *p;` or `enum E f(void);` falls through to ordinary classification because no definition brace follows the type name.

On that ordinary path the dispatcher puts the current first token back, then calls `cc-top-classify`. C06's lexer mark saves reader position, line, current-token fields, and the pending-token flag. Restoring it restores which token the selected parser sees next; it is more than rewinding a byte index.

The classifier starts with `top-var=0`, parenthesis depth zero, and `cc-top-var-seen=0`. Its only other results are `top-proto=1` and `top-fndef=2`. Here is its causal rule:

1. At parenthesis depth zero, `=` or `[` sets `cc-top-var-seen`. A later `(` should no longer make an initializer or array bound look like a parameter list
2. On `(`, set the tentative class to prototype only if that flag is still zero; always increment depth. On `)`, decrement depth
3. At depth zero, `;` returns the current class; `{` changes it to function definition and returns
4. EOF returns the current class. All three exits first restore the lexer mark

Trace four inputs from their first pending type token:

| Input | Decisive state changes | Returned class |
|---|---|---|
| `int f(void);` | `(` selects prototype, depth 1; `)` returns depth 0; `;` ends | `top-proto` |
| `int f(void) { return 1; }` | Same parentheses; `{` at depth 0 selects body | `top-fndef` |
| `int g = (3);` | `=` sets variable flag before `(` | `top-var` |
| `int a[(3)];` | `[` sets variable flag before `(` | `top-var` |

For all four, the next `cc-next-token-keep` after classification returns the original `int`. No token scanned for the decision has been permanently consumed.

This is a classifier for the admitted forms, not a complete declarator grammar. It tracks parentheses, not bracket/brace nesting, and a `{` at depth zero selects a function body even in an unsupported aggregate-initializer spelling. It does not become a syntax validator because it found a class. The selected parser still has to accept the form.

`cc-parse-top-decl` routes function definitions to `cc-parse-function`, prototypes to `cc-register-fn-proto`, and the remaining class to `cc-parse-global-decl`. Those parsers start with the type token pending and own the actual consumption. This is why scanning ahead need not duplicate their work or force them to resume mid-declaration.

Sources: [classifier and skip helper](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L226-L289), [definition lookahead and dispatcher](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L517-L570), and [lexer mark/reset](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L649-L689).

## Reference: a repeated prototype must not hide a body

A prototype such as `int later(void);` supplies a name before a body exists. `cc-register-fn-proto` consumes the return-type spelling using C18's permissive `cc-parse-fn-return-type`, requires a function-name identifier (199 on failure), then searches for that name.

If the newest match is already `sk-func`, it appends no row. If there is no match, or the newest match is another kind, it adds an `sk-func` row with integer result type and address zero. In both cases it calls `cc-top-skip-to-semi`, which consumes tokens through a semicolon at parenthesis depth zero. That helper balances parentheses but does not build a parameter signature; encountering EOF exits it without an additional missing-semicolon error there.

The no-new-row case matters in this order:

```c
int later(void);
int first(void) { return later(); }
int later(void) { return 3; }
int later(void);
int main(void) { return later(); }
```

1. The first prototype creates unresolved row P
2. The call in `first` emits a placeholder and attaches its field to P's call list
3. The definition creates newer row D at its current target address. C18's producer finds P first, patches its call and address lists, and clears both heads
4. The repeated prototype finds D, already `sk-func`, and adds nothing
5. The call in `main` finds D and emits a call to its known destination

If step 4 instead appended a new zero-address row, newest-first lookup would hide D behind an unresolved name. Avoiding that append preserves the usable definition. The parser does not thereby compare all repeated signatures or establish C linkage compatibility. Its invariant is narrower: a prototype does not replace an already-visible function record with a fresh unresolved row.

Source: [prototype registration and its three lookup branches](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L291-L333); the definition-side completion is [C18's prototype-resolution trace](18-functions-and-call-frame-accounting.md).

## Reference: declarations produce slots before addresses

C15 constructed the descriptor for the recurring record. Now complete its file-scope object producer, alongside an ordinary scalar and array:

```c
struct tri { int rows; int stars; };
struct tri t;
extern int g;
int a[3];
int g = 7;
```

Use fresh global-allocation state, and call the completed `tri` descriptor D. Its two fields are at offsets zero and eight, and its size is sixteen. D is builder metadata; the C object `t` needs separate generated storage.

Six scratch variables in `116` retain the current declaration's base, name address/length, selected slot, record descriptor, and pointer depth: `cc-gdecl-base`, `cc-gdecl-name-a/u`, `cc-gdecl-slot`, `cc-gdecl-desc`, and `cc-gdecl-ptr-depth`. They preserve these facts across token reads and constant parsing. They are not six user globals.

### Select the base, then parse each declarator

`cc-parse-global-decl` starts with descriptor zero and base `ty-int`. A `struct TAG` selects `ty-struct` and uses soft tag lookup: D if known, zero otherwise. This permits an opaque record-pointer spelling without requiring a body. For basic keywords, the parser distinguishes char, consumes enum tags, and uses C15's type-keyword helper for compound primitive spelling. Under our legacy profile the broad non-char spellings collapse to the integer storage model.

For a type-position identifier, this particular parser merely verifies that it is an identifier. It does **not** look up a typedef payload. Thus the earlier `typedef int *IP;` does not make file-scope `IP p;` inherit pointer depth here: this path retains initial int base and obtains depth only from stars written in this declarator. C15's ordinary local typedef lookup and C18's parameter lookup are different consumers. Classification having called something a declaration is not evidence of typedef resolution.

After qualifiers, the outer loop calls `cc-gdecl-declarator` once per comma-separated name. Each call counts its own stars, requires a name (203 on failure), saves its span, and reads the next token. A bad nonkeyword/nonidentifier base reaches 202. The declarator leaves the token following it current; the outer loop continues on comma and checks that its final current token is `;`, otherwise 205. It does not fetch a second semicolon.

### A new scalar allocates; a repeated scalar reuses

For a scalar, `cc-gdecl-declared` searches the newest matching name and returns its ID only if it is `sk-global`; absent or other-kind matches act as −1. A new scalar calls `cc-gdecl-scalar-bytes`:

```text
known struct value, zero pointer depth:
    bytes = ((descriptor-size + 7) / 8) * 8
otherwise:
    bytes = 8
```

Division here is integer division on admitted nonnegative sizes. A known sixteen-byte record needs sixteen bytes; its pointer needs eight. The fallback includes ordinary ints, chars, pointers, and an opaque record reference. It is not a promise that a descriptor-less record value has a usable full layout.

`cc-globals-alloc` returns an offset into the separate data buffer. `cc-gdecl-add` creates an `sk-global` row whose type packs base/depth and whose payload is that offset. For a new scalar, the parser also attaches the known descriptor. If a prior global exists, the scalar branch instead reuses its payload, without allocating a new slot or refreshing that row's type/descriptor.

An `=` invokes the builder constant evaluator and stores eight little-endian initializer bytes directly in the selected data slot. There is no emitted startup assignment. An absent initializer leaves the zeroed data bytes in place. Prefix `extern` does not suppress allocation in this legacy producer, so `extern int g;` creates a slot that `int g=7;` later reuses. Do not extend this to a promise of arbitrary compatible redeclarations, tentative-definition rules, or aggregate initialization.

### An array takes a different branch

If the token after the name is `[`, the declarator computes N with `cc-parse-const`, expects `]`, requests `N*8` bytes from `cc-bss-alloc`, registers a new global, and stores N as its array length. BSS denotes storage supplied as zeroed memory after the file image rather than copied object bytes in the file. Its slot encodes `cc-bss-flag+offset`, where `cc-bss-flag=2^40`; that tag tells the later finalizer which area owns the object.

This branch does not call `cc-gdecl-declared`: repeated arrays allocate again. Nor does it use a type-size calculation or attach the record descriptor as the new-scalar branch does. The allocation is N times eight even for a char or record spelling. Use the admitted one-dimensional, positive, bounded array case here; the body adds no independent positive-bound or multiplication-overflow check. Function-pointer globals and aggregate/array initializers are outside this parser's implemented declaration contract.

Now all five declarations have an inspectable effect:

| Completed declaration | Symbol payload / association | Data bytes claimed | BSS bytes claimed |
|---|---|---:|---:|
| `struct tri { ... };` | Tag refers to descriptor D, size 16 | 0 | 0 |
| `struct tri t;` | `t`: data slot 0, descriptor D | 16 | 0 |
| `extern int g;` | `g`: data slot 16 | 24 | 0 |
| `int a[3];` | `a`: slot `2^40+0`, array length 3 | 24 | 24 |
| `int g=7;` | Same `g` row and slot 16 | 24 | 24 |

The final data buffer contains sixteen zero bytes for `t`, followed by `07 00 00 00 00 00 00 00` for `g`. The array has reserved memory extent and a symbol, but contributes no 24-byte payload to this buffer. No final target address has been chosen for any of the three objects yet.

The old comment in `116` about eliding unsupported file-scope variables describes an earlier limitation. The inspected `cc-parse-global-decl` body allocates these objects. Use the body, not that historical sentence, to decide what the current legacy producer does.

Source: [global scratch state, scalar sizing, name reuse, and array branch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L335-L476), with [data/BSS allocation and initializer stores](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L1169-L1232).

## Reference: place the objects after all emitted bodies

Why defer object addresses? User functions and demanded late shims can still lengthen the file. A global reference emits a ten-byte `MOVABS RDI,imm64` with an eight-byte zero placeholder and records the field offset plus the object's slot. Once code emission is finished, `cc-finalize-globals` can give all those references their final destinations.

Keep the preceding data size 24 and BSS size 24. For this separate placement fixture, **supply** an end-of-code cursor of 1003 and recorded address fields at 802 for `t`, 818 for `g`, and 834 for `a`. These positions are chosen inputs to the finalizer trace, not a claimed compilation of a larger function body.

| Builder operation | Cursor afterward | Reason |
|---|---:|---|
| Save data base | 1003 | First data byte will be at target `0x4003EB` |
| Append 24 data bytes | 1027 | File now includes `t` and `g` |
| Append five zero padding bytes | 1032 | Nonempty BSS needs the following base eight-aligned |
| Save BSS base/extent | 1032 | Base `0x400408`, extent 24; no BSS payload appended |
| Patch three recorded address fields | 1032 | Patches overwrite existing bytes |

Data-slot references use `data-base+slot`. Tagged BSS references use `bss-base+(slot−2^40)`. Therefore:

| Reference field | Calculated address | Eight stored bytes |
|---:|---|---|
| 802 for `t` | `0x4003EB+0 = 0x4003EB` | `EB 03 40 00 00 00 00 00` |
| 818 for `g` | `0x4003EB+16 = 0x4003FB` | `FB 03 40 00 00 00 00 00` |
| 834 for `a` | `0x400408+(2^40−2^40) = 0x400408` | `08 04 40 00 00 00 00 00` |

The finalizer loops over data-buffer indices for the copy, then over global-fixup indices for patches. `cc-gfixup-slot` selects the area/offset; `cc-gfixup-out-pos` supplies the output field to overwrite. These are parallel arrays, not the linked function-fixup lists.

Data is not aligned before it is appended. Only the subsequent BSS base gets this conditional padding. If BSS extent is zero, the alignment loop is skipped. The finalizer still sets `cc-bss-base-vaddr` and copies the extent into `cc-bss-size`, supplying the ELF finalizer's input.

For our supplied state, `p_filesz=1032`, while required file-plus-BSS memory is `1032+24=1056`; `p_memsz` keeps its 81,920-byte minimum. Under the admitted below-4-GiB output bound, `cc-finalize-elf` patches only the low four bytes of the already-zero-high file-size field. It patches the memory-size low half only when `file-size+BSS-size` exceeds the minimum. It neither appends the BSS payload nor gives its remaining headroom names as additional C objects.

The sequence is one-way: finish bodies, append data/padding, resolve globals, finalize ELF sizes. Repeating global finalization would append data again; it does not clear the recorded fixup count or act as a general restart. C10 opens its entire patch loop and workspace choices; this session supplies the declaration producers that feed that algorithm.

**Pause point.** Save D=16, `t` slot 0, `g` slot 16, `a` tagged offset 0, code-end 1003, and BSS base 1032. If you obtain a wrong address, first decide whether you selected the wrong area or added the wrong offset. Recompute with code-end 1008 before trying a new declaration form.

Sources: [global finalization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L478-L514), [global-reference emission](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L1211-L1232), and [ELF size completion](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/080-cc-elf.fth#L65-L80).

## Reference: runtime names have three completion policies

The first story used the runtime's total prefix length. Here is the registration mechanism behind it. All `cc-name-*` strings are raw builder bytes made with `s,`; they have no length prefix. Calls to `cc-sym-add` supply each length explicitly. None of these name strings is automatically appended to the generated executable as a symbol table.

### Eager bodies are already defined

`cc-emit-shims` registers each name at `cc-here-vaddr`, then invokes its emitter. The order is exactly the eleven-name table in the first story. `exit` and `free` get a void result encoding; the other eager rows get int. This is registration for the restricted runtime, not a complete hosted C signature.

Because the row comes first, later source calls can find the start address without waiting for another linking phase. Registering and appending happen during builder execution; none of the shim's input/output or allocation effects happens then. The sixteen inline zero bytes in `calloc` are the exception to a code-only view of its region, not an invocation of its allocator.

### Late bodies wait on either kind of use

`cc-late-shims` contains eight builder-side rows in this order:

| Name | Length | Emitter stored in the row |
|---|---:|---|
| `malloc` | 6 | `cc-emit-malloc-late` |
| `open` | 4 | `cc-emit-open-shim` |
| `read` | 4 | `cc-emit-read-shim` |
| `write` | 5 | `cc-emit-write-shim` |
| `close` | 5 | `cc-emit-close-shim` |
| `strlen` | 6 | `cc-emit-strlen-shim` |
| `memcpy` | 6 | `cc-emit-memcpy-shim` |
| `strrchr` | 7 | `cc-emit-strrchr-shim` |

Each 32-byte row contains four eight-byte cells: name pointer at +0, name length at +8, Forth emitter execution token at +16, and a mutable symbol ID at +24. Eight rows consume 256 builder bytes; a final zero name-pointer cell makes the created table 264 bytes. The emitter token identifies builder code. It is not the future address a C function pointer should hold.

`cc-register-late-shims` walks until the zero name pointer. For each row it creates an int-result `sk-func` with address zero, stores the new ID at +24, and advances by 32. After user declarations, `cc-emit-late-shims` retrieves that ID and tests:

```forth
    dup cc-sym-call-fixups @  over cc-sym-addr-fixups @  or if,
```

Either nonzero head demands a body. For such a row, the pass stores the current target address in the symbol payload, patches the relative-call list, patches the absolute-address list, clears both heads, and only then executes the emitter token. Advancing to the next row does not depend on how many sites waited for this body.

The two patch forms have different arithmetic. A CALL field receives `target−(base+field-offset+4)` in four bytes; a function-address MOVABS field receives the target itself in eight bytes. A user definition may already have resolved and cleared these lists through C18's path, so the late pass emits no replacement in that case. An unused zero-address row also emits nothing. A used-but-not-called function can still demand a body through its address list.

Four small providers specialize `cc-emit-syscall-shim`: open supplies 2, read 0, write 1, and close 3. `cc-emit-malloc-late` looks up the current `calloc` symbol value and passes that target to the malloc emitter, which emits its tail jump. Newest-first lookup supplies the visible row; the comment calling it “the first” is not a different lookup rule. The remaining table entries use their direct emitters. C11 owns each generated runtime body's register, syscall, failure, and storage contract.

### A recognized external name may still have no body

`cc-emit-external-protos` registers `memset` with address zero, but no late row or eager emitter supplies it. A declaration or name record makes lookup possible; it does not complete a called or address-taken function. Without a user definition, a pending use remains for error 206.

`cc-emit-libc-typedefs` supplies a fourth category of registration, with no callable body at all: `FILE`, `int8_t`, `int16_t`, `int32_t`, `int64_t`, `uint8_t`, `uint16_t`, `uint32_t`, `uint64_t`, `size_t`, `ssize_t`, and `intptr_t`. Each is `sk-typedef`, unused type field zero, payload `ty-int` at pointer depth zero. In this profile those familiar names do not establish standard-width storage or a hosted FILE layout.

For a fresh symbol table, registration contributes `11+8+1+12=32` rows before source parsing. Our minimal `main` adds one global function row and no parameter/local rows, leaving 33 visible rows. This metadata count is independent of its 556 output bytes.

Sources: [raw names and eager registration](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L630-L740), [late table/providers/walks](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L743-L804), and [external/typedef registrations](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L806-L846).

## Reference: unresolved use and missing main are different failures

`cc-check-fns-defined` scans symbol IDs from zero up to the current count, considering only `sk-func` rows. For each it ORs the call-head and address-head values. Any remaining head causes error 206. Under LP64, this check first writes the offending name and a newline to the diagnostic stream; that conditional diagnostic does not change our legacy target or select a native function producer.

Only after the scan succeeds does the word test `cc-main-vaddr`. Zero causes error 207. This checks for a recorded `main` definition, not merely a prototype spelling in the symbol table.

| End-of-source state | Result at this boundary |
|---|---|
| `main` defined; unused `int absent(void);` | Empty lists do not trigger 206 |
| `main` defined; unresolved call to `absent` | Pending call triggers 206 |
| `main` defined; unresolved function-address use of `absent` | Pending address triggers 206 |
| Only a `main` prototype, no pending uses | No recorded main destination: 207 |
| Pending unresolved use and no main definition | Scan reaches 206 before the missing-main test |

The check's purpose is to prevent an unpatched CALL from behaving as a zero displacement, or an unresolved address load from producing zero. It does not inspect every jump label or prove the program's semantics. In particular, C17's legacy undefined-goto limitation is not repaired by scanning function symbols.

This explains the order in the complete orchestration word:

```forth
: cc-parse-program
  cc-emit-entry-stub
  cc-emit-shims
  cc-register-late-shims
  cc-emit-external-protos
  cc-emit-libc-typedefs
  cc-parse-function-list
  cc-emit-late-shims
  cc-check-fns-defined
  cc-patch-call-main ;
```

Check before the late pass, and valid waiting runtime uses would appear unresolved. Patch main before establishing a nonzero destination, and absence could be mistaken for a valid target calculation. Append global data before late bodies, and the final code/data placement would no longer follow the current driver. Each ordering constraint comes from a value that a later step requires.

Source: [final checks and orchestration](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L849-L884).

## Reference: the last file executes, not merely defines

`120-cc-main.fth` creates one data object and defines one driver. `cc-out-path` is twelve bytes of builder memory:

```text
2F 74 6D 70 2F 63 63 2D 6F 75 74 00
 /  t  m  p  /  c  c  -  o  u  t  NUL
```

The twelve explicit `c,` operations construct `/tmp/cc-out\0` while loading the compiler. They do not put the path in the generated C executable. Its trailing zero is needed by the builder's file-opening interface; symbol names made with `s,` instead use a separate supplied length.

Defining `cc-main` compiles a Forth word. The final bare `cc-main` at the bottom of `120` **invokes** it. Loading this file therefore starts input reading, compilation, the output-write attempt, and builder termination. It is not a passive library load suitable for source inspection by execution.

The dependency comment describes the core order from `010` primitives through arena/I/O, preprocessing, tokens, types, symbols, ELF, emitters, expressions, declarations, statements, functions, and program construction. Every called definition/provider must be available before the executing final call. In the pinned tree, optional compiler libraries can have numbers greater than 120. The inspected [`tools/compiler-layers.sh`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/compiler-layers.sh) therefore lists matching compiler libraries except `120`, then prints `120` last. Numeric order alone is not the executing-file rule.

The driver calls the legacy `cc-parse-program` directly. Loading a native provider or changing a width flag alone does not replace that call with `cc-native-program`, a System V driver, or an object-file producer. Those other paths have their own entry, type, frame, and finalization contracts.

The reset boundary matters too. `cc-main` calls the input/preprocessing routines plus output and global resets, but does not explicitly reset every symbol, arena, hook, or prior `main` variable for a compile-server loop. Our first story used a fresh builder. It did not establish that calling this driver twice in arbitrary existing state is equivalent to starting twice.

Finally, the file operation is the builder's I/O, not a request emitted for the target. `cc-write-output` opens with flags 577 (`O_WRONLY|O_CREAT|O_TRUNC`) and creation mode 493 (octal 0755). A negative descriptor reaches error 22. Otherwise it requests `cc-out-pos` bytes once, discards that result, closes, and discards the close result. “Requested all bytes” is the bounded source fact; no progress loop or full-transfer check turns it into observed complete writing.

Source: [the complete last file](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/120-cc-main.fth#L1-L40), with [its input/reset contract](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth#L53-L84) and [its output operation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth#L171-L195).

## Practice: complete a unit, then disturb one assumption

These are paper tasks under the chapter's legacy profile unless a prompt says otherwise. Use the named tables and source links as references; use the [graduated hints and checked solutions](../practice/19-solutions.md) when helpful. Each solution explains a likely wrong path and offers a changed reattempt. Nothing here requests a compiler or generated-program run.

### C19-01 — From a complete program to a process result

For `int main(void){return 7;}`, reconstruct the entry destination, main destination, CALL field/next-instruction offsets, displacement bytes, function length, final cursor, and two ELF size fields. Explain how the value reaches the exit request and why the fallback zero does not overwrite it. Then change the return to eight, and separately remove the explicit return. Which layout values and runtime predictions change in each case?

### C19-02 — Create descriptions without creating objects

Start with no user names. Process `enum E{A,B=A+3,C,}; typedef int *IP; typedef IP *IPP; typedef void (*FUNCTION)(void);`. Give each introduced name's kind and payload, state whether E gets an enum-tag row, and identify any target allocation/emission caused by these declarations alone. Explain how B can use A. Then predict `enum F{X=5,Y,Z=Y+2,};`, and state what the function-pointer typedef does and does not retain.

### C19-03 — Let lookahead return the input intact

For each of `int f(void);`, `int f(void){return 1;}`, `int g=(3);`, and `int a[(3)];`, trace the decisive classifier state and state the next token seen by the selected parser. Explain the separate `struct TAG {` test. Then trace prototype → use → definition → repeated prototype for one function, naming the row that owns the original fixup and the row found by a later call. Why is “always append a prototype” the wrong rule?

### C19-04 — Give the record an object

Use a completed two-member `tri` descriptor D, size sixteen, and fresh global state. Process `struct tri t; extern int g; int a[3]; int g=7;`. Give each object's symbol kind, slot, relevant descriptor/length, data bytes, and BSS extent. Explain the phase that establishes the seven. Then change the first declaration to `struct tri *t;` and repeat the storage calculation. Separately repeat `int a[3];`: does the scalar-reuse rule apply?

### C19-05 — Finish three addresses

Use the original C19-04 objects, code-end cursor 1003, and global-reference fields at 802 (`t`), 818 (`g`), and 834 (`a`). Complete the data-base, appended length, padding, BSS-base, three address patches, final cursor, and ELF sizes. Then move code-end to 1008. Explain which finalizer knows these addresses and why the entry CALL must not be added to the global-fixup arrays.

### C19-06 — Demand, define, or leave unused

A late `strlen` row has an empty call list but one address field waiting at output offset 602. Supply code-end cursor 700, no earlier demanded late row, and no user definition of `strlen`. Describe every late-pass action through emitter invocation and give the patched eight bytes. Compare three independent states: the same row unused, a user definition that already completed its lists, and a pending use of `memset` without a definition. Finally, choose the first error when both a used function and main remain undefined.

### C19-07 — Separate four meanings of “finished”

A colleague says, “The cursor is 556, so we have a 556-byte executable, its entry is main, all names have bodies, and loading files in numeric order reproduces Stage A.” Correct each claim using a particular source operation or boundary. Identify the twelve-byte path's owner, explain why the final bare `cc-main` must be last, and distinguish the driver resets from a full reusable-state reset. As an independent mixed check, assign an owner and completion event to a loop break/continue jump, ordinary function CALL, function-address MOVABS, global-address MOVABS, entry CALL, and ELF file-size field.

## What the complete paper program established

A C definition does not supply its own process entry. The builder first reserves a call, emits the runtime prefix, gives `main` a destination, closes pending function uses, patches the entry, places global objects, and finalizes the file envelope. Later, the target follows a different order: process entry calls main and turns its return value into an exit request. Metadata, file bytes, mapped storage, and executed effects remain separate throughout.

You can now derive the minimal program's 556-byte layout and explain its predicted exit value, then change the source without guessing which values must move. You can also locate the producer and completion event for enum values, typedef encodings, prototypes, scalar data, arrays, and global references.

What remains for C20 is evidence about an actual build: exact Stage-A inputs and artifact identities, successful file creation and execution where authorized, and the stated artifact comparisons. A source-derived layout is a useful prediction to compare against that evidence. It is not already a build comparison, a bootstrap fixed point, or a correctness proof.
