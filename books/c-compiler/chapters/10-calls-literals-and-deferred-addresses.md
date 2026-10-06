# 10. Calls, literals, and deferred addresses

[Previous: Instructions inside an executable](09-instructions-inside-an-executable.md) · [Practice help](../practice/10-solutions.md)

A caller can name `line` before the compiler has emitted `line`. A global can have a reserved storage slot before the compiler knows where the data area will start. Neither fact forces the compiler to stop. It can emit a field with a temporary value, remember what that field means, and replace it when the missing address becomes known.

The difficult part is keeping those meanings separate. A four-byte CALL displacement, an eight-byte function address, and an eight-byte global address may all begin as zero. They require different records, different calculations, and different completion events.

By the end, you should be able to stage a restricted scalar call, derive both kinds of function patch, follow their arena nodes to completion, place an escaped string without executing its bytes, and finish a data-plus-BSS layout. These are paper-reading capabilities. This chapter contains no newly executed compiler, Forth, C, or generated-program example.

## Bring four contracts, then choose a route

[C02](02-buffers-arenas-and-failure.md) supplies owned buffers, eight-byte builder cells, arena allocation, and unchecked patch primitives. [C06](06-tokens-and-lookahead.md) supplies borrowed token spans and the escape decoder. [C07](07-types-and-stable-descriptors.md) and [C08](08-names-and-lexical-scope.md) supply profile-dependent types and kind-dependent symbol payloads. [C09](09-instructions-inside-an-executable.md) supplies the instruction key and executable coordinates:

- `cc-out-pos @` is a byte offset in the output buffer, not a builder address
- The fixed executable base is `0x400000`; `cc-here-vaddr` is that base plus the current output offset
- Multi-byte fields are little-endian, with the lowest byte at the lowest offset
- A rel32 field measures from the instruction immediately after its four bytes
- The generated CPU stack and the builder's Forth stacks are separate machines' state

Here and in the feedback, logical stacks have their top at the right. Machine-stack addresses are shown explicitly. All chosen addresses denote valid storage, counts are nonnegative, arithmetic does not wrap unexpectedly, and patches lie in previously emitted fields. These assumptions do not add checks to the implementation.

**Quick diagnostic.** A CALL begins at file offset 100, and its target is at file offset 140. Which offset must be saved, how many bytes are patched, and what displacement is stored? The answers are 101, four, and `140−105=35`. An arena node that stores 101 is neither at target address `0x400065` nor necessarily at builder address 101. If that last distinction is uncertain, use the coordinate table below. If all three answers and their reasons are clear, skim the call and node traces, then try the mixed exercises.

**Source boundary.** The primary source is [090-cc-emit.fth at revision 7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth). We open small consumers in `100`, `112`, `114`, and `116` so every deferred-address promise here reaches a patch. Later chapters still own their full parsing, scope, and control flow. Numerical states and produced bytes below are manually derived from those definitions, not observed compiler output.

## First make a call whose destination is already known

The main path is the **restricted legacy convention**: `cc-target-lp64` is zero, expressions produce one scalar value in RDI, up to six arguments travel in registers, and a return value arrives in RAX. The register order is:

| Argument index | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| Register | RDI | RSI | RDX | RCX | R8 | R9 |
| POP bytes | `5F` | `5E` | `5A` | `59` | `41 58` | `41 59` |

This matches the familiar integer-register order without establishing a complete System V ABI implementation. Register order alone says nothing about aggregate classification, preservation of every required register, variadic calls, or alignment through arbitrary nested expressions. Our call traces begin at a stated valid call boundary. Restoring a stack depth after argument staging is not a proof about every intermediate nested call.

In the restricted branch of [`cc-parse-call`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L589-L666), each argument is parsed left-to-right and its RDI value is pushed. This is this implementation's evaluation order, not a general C-language guarantee. After checking the count, the compiler emits pops in reverse index order. Why reverse? The last evaluated argument is nearest the machine stack's top, but it belongs in the last argument register.

For a call with values `(2,3,42)`, start with machine RSP=S and no outstanding staging values:

| Generated action | Machine RSP afterward | Relevant state |
|---|---:|---|
| Evaluate 2; PUSH RDI | S−8 | `[S−8]=2` |
| Evaluate 3; PUSH RDI | S−16 | `[S−16]=3` |
| Evaluate 42; PUSH RDI | S−24 | `[S−24]=42` |
| POP RDX, index 2 | S−16 | RDX=42 |
| POP RSI, index 1 | S−8 | RSI=3 |
| POP RDI, index 0 | S | RDI=2 |
| CALL | S−8 at callee entry | `[S−8]` holds the return address |

The last row is a **new** push performed by CALL. It is not one of the argument saves, and it is not a builder fixup node. RET later consumes that return address. After the callee returns, `cc-emit-mov-rdi-rax` emits `48 89 C7`, moving the result back into the expression register.

`cc-emit-pops-for-args` starts its counter at `n−1`, emits the selected pop while the counter is nonnegative, and decrements. For zero arguments it emits none. `cc-emit-pop-by-arg-index` maps 0 through 4 explicitly and otherwise selects R9; it does not independently reject index 6. The caller's six-argument check, error 122, is therefore part of the usable contract. A malformed closing parenthesis uses error 121. The later expression chapter explains how tokens reach these checks.

### One star, down to a relative call

For `putchar('*')`, the character value is 42. The immediate emitter produces `48 C7 C7 2A 00 00 00`; staging it uses PUSH RDI and POP RDI before the call. In the eager legacy arrangement, the 120-byte header and 26-byte entry stub put the start of `putchar` at file offset 146, target address `0x400092`.

Now choose a separate illustrative CALL at offset 1024, with RDI=42 already prepared. This chosen callsite is an arithmetic fixture, not a measured parser layout. It lies beyond the eager-runtime block. The CALL ends at offset 1029:

```text
relative displacement = 146 − 1029 = −883
four-byte representation = 8D FC FF FF
CALL bytes at 1024 = E8 8D FC FF FF
result move afterward = 48 89 C7
```

[`cc-emit-call-vaddr`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L444-L483) emits E8 first. At that point the current position names the operand's first byte, so it subtracts `cc-here-vaddr+4` from the target and emits the low four bytes.

For the small runtime bridge, assume a successful one-byte write. At shim entry the return address is already on the CPU stack. `putchar` pushes RDI to make a scratch area whose first byte is `2A`, asks Linux to write one byte to file descriptor 1, removes its scratch, and returns. RAX then contains 1, so the caller's result move makes RDI=1. It does not return 42 on this path. C11 opens the syscall bytes, failures, and the contrasting `fputc` contract; no actual write is performed here.

## Receive arguments, or call through a stored pointer

The five additional spill emitters in `090` reuse C09's local effective-address helper. A **spill** here copies an incoming argument register into its reserved local memory slot so later expressions can reuse registers. The first argument uses the existing `cc-emit-store-local`; the other five vary the source-register field.

With a valid frame RBP=P and slots 0–5 assigned to the six parameters, the following bytes are derived:

| Parameter | Emitter | Instruction bytes | Written address |
|---:|---|---|---|
| 0 | `cc-emit-store-local` | `48 89 7D F8` | P−8 |
| 1 | `cc-emit-store-local-from-rsi` | `48 89 75 F0` | P−16 |
| 2 | `cc-emit-store-local-from-rdx` | `48 89 55 E8` | P−24 |
| 3 | `cc-emit-store-local-from-rcx` | `48 89 4D E0` | P−32 |
| 4 | `cc-emit-store-local-from-r8` | `4C 89 45 D8` | P−40 |
| 5 | `cc-emit-store-local-from-r9` | `4C 89 4D D0` | P−48 |

All are eight-byte stores. `4C` supplies REX.W plus REX.R, extending the ModR/M source field to R8 or R9. It differs from the REX.B used by the R8/R9 POP encodings. Every spill calls `cc-emit-local-ea`; despite the short-form examples, these helpers can select a four-byte displacement. For RSI into slot 16, the result is `48 89 B5 78 FF FF FF`, addressing P−136. The encoder chooses an address representation; it does not allocate a frame slot or establish that the caller owns it. C18 owns that policy and the complete prologue.

A local function pointer requires another separation. Once argument values occupy RDI, RSI, and so on, loading the pointer into RDI would overwrite argument zero. `cc-emit-load-local-into-rax` instead reads the local into RAX. For slot 2, it emits `48 8B 45 E8`. `cc-emit-call-rax` then emits `FF D0`: an indirect near call through the address already in RAX. Its ModR/M `/2` selects CALL, rather than naming a second source register. It still pushes a return address.

The restricted call consumer accepts this local-pointer route when the symbol is `sk-local` with base type `ty-func`; unsupported alternatives reach error 123. It is not a promise to call any arbitrary expression or global function pointer through this branch. An indirect CALL has no rel32 target field to fix later: the runtime value in RAX determines its destination.

## One unknown function needs two lists

Consider this complete source-shaped example as motivation, without claiming it was compiled here:

```c
int line(int pad, int stars);
int main(void) {
    int (*draw)(int, int);
    draw = line;
    return line(2, 3);
}
int line(int pad, int stars) {
    return pad + stars;
}
```

The assignment needs the function's address as a value; the return expression needs a direct call. Both initially refer to an unresolved `sk-func` symbol whose value is zero. They share a future destination but do not share the same patch operation.

| Use | Bytes emitted before resolution | Returned field offset | Required patch |
|---|---|---|---|
| Direct forward call | `E8 00 00 00 00` | Opcode offset+1 | Four-byte signed relative displacement |
| Function used as a value | `48 BF 00 00 00 00 00 00 00 00` | Instruction offset+2 | Eight-byte absolute target address |

The first comes from `cc-emit-call-rel32-placeholder`; the second from `cc-emit-movabs-rdi-imm64-placeholder`. The latter MOVABS means MOV with a 64-bit immediate: `BF` is the register-specific opcode `B8+7`. Neither placeholder is a linker relocation record. Both are fields in this builder's output buffer that this builder will patch.

From C08, `cc-sym-call-fixups ( id -- cell-address )` and `cc-sym-addr-fixups` return mutable **head cells**. With the default providers those cells are in `cc-sym-extra` and `cc-sym-extra2`. Fetching a head cell yields the first node pointer, or zero for an empty list. The distinct heads preserve which operation each field requires.

### A node has two builder cells, even for a four-byte patch

`cc-add-fixup-to-list ( offset head-cell -- )` allocates 16 arena bytes. At node+0 it stores the output field offset; at node+8 it stores the previous head; then it stores the new node address in the caller-owned head cell. The implementation is small enough to follow directly:

```forth
: cc-add-fixup-to-list                            ( off var -- )
  [lit] 16 cc-alloc                               ( off var node )
  >r                                              ( off var ; R: node )
  swap r@ !                                       ( var ; R: node )
  dup @ r@ [lit] 8 + !                            ( var ; R: node )
  r> swap ! ;                                     ( -- )
```

The Forth return-stack temporary preserves the node address during three stores. It does not emit PUSH or POP instructions into the future C program. The node's first cell is eight bytes because it stores a builder integer offset; that does not make the corresponding CALL operand eight bytes.

Let H be a valid call-head cell, initially zero, and let the arena return addresses 9000 then 9016. Prepend field offset 513, then field offset 561:

| After action | H contains | Cell at 9000 | Cell at 9008 | Cell at 9016 | Cell at 9024 |
|---|---:|---:|---:|---:|---:|
| First prepend | 9000 | 513 | 0 | Unallocated here | Unallocated here |
| Second prepend | 9016 | 513 | 0 | 561 | 9000 |

Walking starts at 9016, patches field 561, follows its next pointer to 9000, patches field 513, then stops at zero. Prepending reverses recording order. That is harmless here because independent fields all receive calculations for the same target; no sorting by file position is required.

The coordinate distinctions are now concrete:

| Value | Meaning | Permitted next operation |
|---|---|---|
| H | Builder address of the owner's head cell | Fetch or replace the head |
| 9016 | Builder address of an arena node | Read node cells |
| 561 | Output byte offset stored in a node | Patch at output-buffer-base+561 |
| `0x400300` | Target virtual address of `line` | Encode an address or compute a displacement |

Adding `0x400000` to a builder pointer is not an address translation. Nor does passing node address 9016 to the output patcher select the node's recorded offset automatically. Select the right representation before doing arithmetic.

### Open the patch walkers now

The two loops in [`112-cc-stmt.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L139-L171) accept a head **value**, not the head cell's address. Both save the target in `cc-fixup-target-tmp`, a shared builder scratch cell. Their bodies differ at the patch:

```forth
: cc-walk-and-patch-to-vaddr                      ( head target -- )
  cc-fixup-target-tmp !                           ( head )
  begin,
    dup [lit] 0 <>
  while,
    \ Stack: ( node-ptr ).  Read the fixup-offset (node[0]).
    dup @                                         ( node off )
    \ rel32 = target - (cc-base-vaddr + off + 4)
    cc-fixup-target-tmp @                         ( node off target )
    over cc-base-vaddr + [lit] 4 + -              ( node off rel32 )
    \ Patch 4 bytes at off with rel32.
    over cc-out-patch-4le                         ( node off )
    drop                                          ( node )
    \ Advance to next node: head := node[8].
    [lit] 8 + @                                   ( next-node )
  repeat,
  drop ;
```

The call walker preserves `node` while computing `target−(base+off+4)`. `over` supplies the output offset required by `cc-out-patch-4le`, whose input order is value then offset. After removing the now-unneeded offset, `8 + @` follows the next builder pointer.

```forth
: cc-walk-and-patch-imm64-to-vaddr                ( head target -- )
  cc-fixup-target-tmp !                           ( head )
  begin,
    dup [lit] 0 <>
  while,
    dup @                                         ( node off )
    cc-fixup-target-tmp @                         ( node off target )
    swap cc-out-patch-8le                         ( node )
    [lit] 8 + @                                   ( next-node )
  repeat,
  drop ;
```

The address walker needs no subtraction: each field receives the target itself. Both loops leave the list owner untouched and free no arena nodes. Their shared temporary also means these are not independent reentrant walker contexts.

### Finish the forward function's whole patch life

Use fresh, chosen paper coordinates, separate from the two-node demonstration:

1. A CALL starts at offset 512, so its four-byte field is at 513. One 16-byte node on the call head records 513
2. An address-taking MOVABS starts at 528, so its eight-byte field is at 530. A different 16-byte node on the address head records 530
3. The definition of `line` begins at target address `0x400300`

The CALL displacement becomes `0x400300−(0x400000+513+4)=251`, so bytes at 513–516 become `FB 00 00 00`. The MOVABS field at 530–537 becomes `00 03 40 00 00 00 00 00`. The target is identical; both width and representation differ.

[`cc-parse-function` in 114](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth#L232-L264) captures the prior symbol ID before registering the new definition. With a prior function symbol, it fetches the call head, runs the relative walker at `cc-here-vaddr`, and writes zero to that owner cell. It then does the corresponding address walk and clears that head. The target is the next emitted byte, the start of the function, rather than an address guessed from the prototype.

Clearing belongs to the definition consumer, not to the walkers. It marks those promises discharged; it does not reclaim their 32 arena bytes. The head cells must remain valid until this operation, and the arena nodes must remain intact while reachable. Resetting or reusing arena storage before walking would destroy the records. C02's arena lifetime and C08's symbol lifetime remain separate responsibilities.

There is another real completion route. [`cc-emit-late-shims` in 116](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L788-L804) checks whether either function head is nonzero, assigns a target, patches both lists, clears both heads, then emits the body. Address-taking alone can demand a late shim. After that opportunity, `cc-check-fns-defined` rejects remaining call or address uses with error 206; absence of `main` is error 207. An unused unresolved prototype with both heads zero is not the same situation. No promise here waits for a separate external linker.

**Pause point.** To resume, keep the two offsets 513 and 530, the target `0x400300`, and the question “which walker belongs to each?” Recompute one patch before moving to data placement. You need not memorize the Forth loop to preserve its invariant.

## Literal values choose widths; addresses require all eight bytes

`cc-emit-movabs-rdi-imm64` emits `48 BF` followed by eight little-endian bytes, ten bytes in total. Unlike C09's seven-byte `48 C7 C7 imm32`, it does not sign-extend a four-byte operand. It can carry a full address or a full 64-bit bit pattern.

For nonnegative magnitudes within the legacy comparison's stated domain, `cc-emit-mov-rdi-int` chooses the seven-byte form through 2,147,483,647 and the ten-byte form above it. At the boundary:

| Value | Selected bytes |
|---:|---|
| 2,147,483,647 | `48 C7 C7 FF FF FF 7F` |
| 2,147,483,648 | `48 BF 00 00 00 80 00 00 00 00` |

Trying `48 C7 C7 00 00 00 80` for the second row would sign-extend `0x80000000`, producing the 64-bit representation of −2,147,483,648. Saving three bytes would change the value.

The exact implementation has two predicates. Legacy uses `v > 2147483647`; LP64 uses unsigned `v / 2147483648` and selects MOVABS when that quotient is nonzero. The latter also handles magnitudes with bit 63 set. Do not reinterpret the legacy comparison as a general unsigned-64 magnitude test. A leading minus is handled as a unary operation elsewhere, not as permission to feed every negative value through this literal-selection contract.

This is the emitter's two-way choice, not a proof that it finds the shortest possible x86 encoding. Nor does choosing an encoding decide the C type of the literal. C06 retains its spelling for later classification; C07 and later expression policy govern types. Width of the encoded immediate, builder-cell width, and C object width are three different questions.

## Put string bytes where control flow cannot fall through them

A string token retains source spelling. Its pointer is a borrowed builder address into source storage. The generated program needs a target address pointing to **decoded output bytes**. `cc-emit-string-bytes ( source-address source-length -- )` provides the copy-and-decode step; `cc-parse-string-literal` provides the control-flow wrapper.

The legacy wrapper in [`100`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L677-L723) emits a JMP placeholder, captures the current target address as the string start, emits decoded bytes plus a terminator, patches the JMP to the current position, and finally emits MOVABS of the saved string address. Runtime control skips the bytes and lands on the address load. The bytes remain readable at the saved address.

Use source body `*\n`, whose three source bytes are star, backslash, and `n`. Start at chosen output offset 600:

| Output range | Bytes | Meaning |
|---|---|---|
| 600–604 | `E9 03 00 00 00` after patch | Jump from next offset 605 to 608 |
| 605–607 | `2A 0A 00` | Star, decoded newline, implicit NUL |
| 608–617 | `48 BF 5D 02 40 00 00 00 00 00` | RDI receives `0x40025D`, address of offset 605 |

The saved JMP field offset is 601. Its displacement is `608−(601+4)=3`, the emitted string extent including the terminator. The source body length is three; the decoded payload length before the terminator is two. They happen to yield three emitted bytes here for different reasons. Neither the source address nor the source length belongs in MOVABS.

### Escape consumption is not “skip two”

C06's shared [`cc-decode-escape`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth#L387-L428) receives an address immediately after a backslash and returns `(byte,n)`, where n counts consumed source bytes **after** that backslash. The emitter outputs the byte, advances the source pointer by `n+1`, and reduces the remaining length by the same amount. Ordinary bytes advance by one. A trailing backslash with no following byte is copied literally by the emitter's fallback; that is not a claim that malformed C is diagnosed or valid.

The decoder already handles `\n`, `\t`, `\r`, `\a`, `\b`, `\f`, and `\v`; one through three octal digits; and hexadecimal digits following `x`. Other escaped characters yield themselves. Numeric results are masked to one byte. For source body `A\101\x2A!`:

| Source step | Returned byte | n after backslash | Whole source advance |
|---|---|---:|---:|
| `A` | `41` | Not an escape | 1 |
| `\101` | `41` | 3 | 4 |
| `\x2A` | `2A` | 3 | 4 |
| `!` | `21` | Not an escape | 1 |

Ten source bytes become four payload bytes, followed by implicit `00`. Hex consumption continues through every following hex digit; octal stops after at most three. The decoder's API has no length argument, so callers rely on valid retained source and readable stopping bytes, as established in C06. It is not a general bounded decoder for arbitrary detached memory slices.

An explicit `\0` contributes a payload zero; the emitter still adds the implicit final zero. For `A\0B`, bytes are `41 00 42 00`. A later NUL-terminated scan would stop before B, but B still occupies output space and contributes to the JMP displacement.

**Optional profile depth.** With `cc-target-lp64` nonzero, `cc-parse-string-literal` dispatches through `cc-native-string-fwd`. Its initial provider, `cc-parse-native-string-literal`, concatenates adjacent string tokens after decoding. It emits each piece, subtracts one from the output position to remove that piece's temporary terminator, and finally emits one NUL. The output-position difference, including embedded zeros and the final terminator, becomes `cc-last-expr-array-len`. For adjacent `"A\0" "B"`, the combined bytes are `41 00 42 00`. This concatenating wrapper is gated; the shared escape decoder itself is not an LP64-only feature.

## Global slots are promises about two different areas

Inline strings are settled while their wrapper is emitted. Globals require a later placement event, because more code and demanded runtime bodies may still precede the data area.

The storage definitions in [`090`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L1098-L1232) describe two areas:

| Area | Builder state | Slot returned | File bytes later? |
|---|---|---|---|
| Data | `cc-globals-buf`, used length `cc-globals-pos` | Offset from data start | Yes |
| BSS, zero-filled tail | Extent `cc-bss-pos` | `cc-bss-flag + offset` | No object bytes |

`cc-globals-cap` is 65,536 bytes. `cc-bss-cap` is 268,435,456 bytes. `cc-bss-flag` is 1,099,511,627,776, or `2^40`, large enough to distinguish these bounded slot ranges. The tag is metadata, not an address bit to retain in the target pointer. A data slot of zero is valid; it does not mean “no global.” A first BSS slot is the tag itself.

`cc-globals-alloc` checks old data position plus requested bytes against its cap, returns the old position, and advances the position. `cc-bss-alloc` does the analogous operation but adds the tag to its returned slot. Errors are 80 and 82 respectively. These primitives neither align each request nor assign a C type. Declaration consumers supply suitable sizes and forms.

`cc-globals-init` sets data position, BSS position, fixup count, and data-base variable to zero, then explicitly clears all 65,536 bytes of `cc-globals-buf`. Reserving data therefore exposes zero bytes until initializers replace them. `cc-globals-store-8le ( value slot -- )` writes eight successive low bytes of the value into that buffer, dividing unsigned by 256 between bytes. It expects a data slot and valid extent; it is not a generic typed aggregate initializer or a BSS writer.

The legacy declaration consumer in [`116`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L369-L431) gives ordinary scalars eight data bytes, whether or not they have initializers. A known struct value receives its descriptor size rounded to eight. Its array form reserves N×8 BSS bytes and records the array length. These are this restricted consumer's forms, not a universal claim that every array under every profile belongs in BSS. Native initialized aggregates and their declaration policy are later material.

### One reference, two parallel cells

A global reference cannot yet know its target address. `cc-emit-global-ref ( slot -- )` emits `48 BF` and eight zero bytes, capturing the immediate-field offset between opcode and operand. It passes that offset and the slot to `cc-gfixup-add`.

These records use two parallel arrays, not the function-node arena lists. At index i, `cc-gfixup-out-pos` holds the operand offset and `cc-gfixup-slot` holds the storage slot. The count gives their shared live prefix. `cc-gfixup-add` checks `count+1`, stores the slot and offset at the same saved index, and increments count once. A second reference to the same object needs another record because it has another output field to fill.

For example, a MOVABS beginning at offset 800 for data slot zero records `(802,0)`; a MOVABS at 816 for the first BSS slot records `(818,2^40)`. Those slot numbers identify allocated storage. Scalar loading or array decay is decided by the later expression consumer; the low-level emitter has produced an **address** in RDI, not the object's value.

## Finish a complete data-plus-BSS placement

Use this small complete source-shaped case to identify the objects:

```c
int t = 4;
int spare;
int blanks[3];
int main(void) {
    blanks[0] = t;
    return spare;
}
```

Now use a fully stated paper layout rather than inventing a parser dump. The restricted declaration contract gives `t` data slot 0, `spare` data slot 8, and `blanks` BSS slot `2^40`. Data length is 16; BSS length is 24. The first eight data bytes are `04 00 00 00 00 00 00 00`; the remaining eight remain zero. Suppose address fields have been recorded at 802 for `t`, 818 for `blanks`, and 834 for `spare`, and finalization begins at output position 1003.

[`cc-finalize-globals`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L489-L515) performs five concrete steps:

1. Save `cc-here-vaddr` in `cc-globals-base-vaddr`: `0x400000+1003 = 0x4003EB`
2. Append data-buffer indices 0 through 15. Output position becomes 1019
3. Because BSS extent is nonzero, append zero bytes until `cc-out-pos & 7` is zero. Five padding bytes produce position 1024
4. Save `cc-here-vaddr` in `cc-bss-base-vaddr`: `0x400400`. Copy BSS extent 24 into `cc-bss-size`
5. Walk record indices from zero through `cc-gfixup-count−1`, select the base from the slot tag, and patch each eight-byte operand

The exact patch loop is:

```forth
  [lit] 0
  begin, dup cc-gfixup-count @ < while,
    dup cc-gfixup-slot     cell[] @                \ slot
    dup cc-bss-flag < if,
      cc-globals-base-vaddr @ +                     \ vaddr = base + slot
    else,
      cc-bss-flag - cc-bss-base-vaddr @ +           \ vaddr = bss base + offset
    then,
    over cc-gfixup-out-pos cell[] @                \ patch-offset
    cc-out-patch-8le
    1+
  repeat, drop ;
```

The loop preserves index i under the derived address, then fetches the corresponding operand offset from the other array. It does not add the executable base twice and does not copy BSS object bytes into the file.

| Record | Selected calculation | Patched operand bytes |
|---|---|---|
| `t`, field 802 | `0x4003EB+0` | `EB 03 40 00 00 00 00 00` |
| `blanks`, field 818 | `0x400400+(2^40−2^40)` | `00 04 40 00 00 00 00 00` |
| `spare`, field 834 | `0x4003EB+8` | `F3 03 40 00 00 00 00 00` |

This also shows that the data base itself is not rounded up before appending. The conditional padding aligns the subsequent BSS base. With BSS length zero, that padding loop is skipped; the BSS-base variable is still set to the then-current address and `cc-bss-size` becomes zero.

C09's ELF finalizer now has everything it needs. Final file size is 1024, including the five padding bytes. File-plus-BSS is 1048, below the header's minimum memory extent of 81,920, so `p_memsz` remains `00 40 01 00 00 00 00 00`. The `p_filesz` low four bytes become `00 04 00 00`; their already-zero upper half remains unchanged. The 24 BSS bytes describe zero-filled memory after the file image, not bytes appended by this finalizer. Remaining minimum memory headroom is not another C object allocated by this example.

## Workspace choices and the limits of a patch promise

The global-reference arrays have a selected capacity. Their default is 16,384 records, with two 131,072-byte arrays, `cc-gfixup-default-out-pos` and `cc-gfixup-default-slot`. The mutable pointer cells `cc-gfixup-out-pos-buffer` and `cc-gfixup-slot-buffer` select the active arrays; the accessors return their addresses. `cc-gfixup-limit` holds the active count limit, and `cc-gfixup-cap` fetches it.

`cc-gfixup-default-workspace` selects those defaults. `cc-gfixup-direct-workspace` lazily maps one pair for 17,920 records if `cc-gfixup-direct-base` is zero, then selects it. The mapping is `17920×16 = 286720` bytes, 70 pages of 4096 bytes; the second column begins 143,360 bytes after the first. Subsequent selection reuses that mapped pair. Mapping failure and reference-count overflow both use error 81 in their respective paths.

Neither selector resets count nor migrates existing records. Select before collecting references. Changing the active pointers midway would cause the unchanged count to describe the wrong storage. `cc-globals-init` resets usage but does not choose a workspace; it also does not establish final BSS base or ELF BSS size, which finalization supplies. No particular external driver should be said to choose the direct pair without inspecting that driver's calls.

The choices are independent: a larger output buffer, a larger arena, LP64 types, and a larger global-fixup pair are not synonyms. A default 32,768-byte arena could hold at most 2,048 of these 16-byte nodes if nothing else used it, but descriptors and other records share it. Function nodes can exhaust the arena with error 10 even when global-array capacity remains. BSS extent consumes neither one node per byte nor one file byte per byte.

The ordinary cap checks permit equality. The next excess global reference raises 81; excess data bytes raise 80; excess BSS extent raises 82; an output append beyond its selected capacity raises 21. Multi-byte emission can have appended earlier bytes before a later append fails. No transaction rollback is implied. Global finalization can likewise fail while appending data or padding.

Appending and patching have different safety contracts. `cc-out-patch-4le` and `cc-out-patch-8le` assume valid offsets and fields. These consumers do not establish a general check for arbitrary patch offsets or signed-rel32 reach. Our small layouts meet those premises; larger claims would need their own evidence. Clearing function heads does not erase their nodes, and global finalization does not clear its record count. Treat finalization as the ordered end-of-emission step, not an idempotent operation to repeat casually: a second invocation would append the data again.

### Keep profile switches explicit

The legacy path above uses `cc-target-lp64=0` and `cc-target-sysv=0`. The TinyCC recipe in [`tools/tcc-compile.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc-compile.fth) explicitly enables LP64 and direct preprocessing, sets bootstrap floatbits to 1, maps an 8 MiB arena, and chooses `cc-native-program`. Its private call ABI passes arguments in eight-byte stack slots, with argument zero nearest the return address. That is not System V merely because it shares MOV and CALL emitters.

Conversely, [`cc-sysv-enable` in 121](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L1256-L1260) explicitly enables System V, LP64, and direct preprocessing, sets bootstrap floatbits to zero, and clears named target state. An appropriate System V program or object driver must also be selected. Its scheduling and complete ABI policy belong later.

Loading provider definitions alone does not select their target. The `121` fixup-head providers use offsets 32 and 40 of a matching persistent implicit-function record only when System V is enabled and that record exists; otherwise they delegate to the default symbol cells. The common node representation survives this owner-cell change. Similarly, push/pop tracking hooks can gain builder bookkeeping without adding instructions to the simple POP encodings above. Do not infer a whole ABI from one hook or one shared emitter.

## Practice: nine ways to lose an address

[Hints and checked manual solutions](../practice/10-solutions.md) are separate from these attempts. Nine exercises distinguish argument order, displacement arithmetic, node ownership, field width, decoding, storage placement, capacities, instruction fields, and completion timing. One large mixed problem would make those errors harder to locate. Use the register and byte tables as references; unnecessary memorization is not the goal.

1. **C10-01 — Reverse the right thing.** A valid restricted call evaluates values 10, 20, 30, 40, 50, 60 in that order, starting at RSP=S. List saved memory positions, pop register order and bytes, final registers, and RSP before CALL and at callee entry. Explain the failure if pops instead start with RDI. What check protects the six-register bound?
2. **C10-02 — Move the star call.** Keep `putchar` at offset 146, but move the illustrative CALL to offset 640. Derive its operand offset, next-instruction offset, displacement, and five bytes. After a stipulated successful one-byte write, give RAX and then RDI after the caller's result move.
3. **C10-03 — Prepend, walk, discharge.** Head cell H is initially zero; the arena supplies 9000 and 9016. Record call fields 513 then 561. Derive all node cells, walk order, and patched bytes for target `0x400300`. Which operation clears H, and which operation frees the nodes? Explain why neither 9016 nor H is an output offset.
4. **C10-04 — Same target, different field.** A CALL begins at 700 and a function-address MOVABS begins at 720. Both wait for target `0x400200`. Derive each field offset, width, patch value, and bytes. Then choose the literal encoding for 2,147,483,648 and explain why it cannot use the sign-extended form.
5. **C10-05 — Count spelling and payload.** At output offset 900, emit the legacy string wrapper for source body `A\101\x2A!`. Derive source length, payload bytes, implicit terminator, JMP field/displacement, string target address, MOVABS start and operand bytes, and final output position.
6. **C10-06 — Place both areas.** Use fresh state: 16 data bytes, first object at slot 0, another at slot 8; BSS extent 24, object slot `2^40+8`; finalization starts at output position 1010. Derive data base, padding count, BSS base, final file size, both bases' roles in the three references, and ELF memory size. Does this finalizer align the data base?
7. **C10-07 — Choose before recording.** At default global-fixup count 16,383, append one record, then attempt another. State the resulting counts or error. A colleague proposes switching to direct workspace after the first append and keeping the count. Diagnose the missing operation; contrast a fresh direct selection before collecting references and name its capacity and mapping size.
8. **C10-08 — Preserve the prepared arguments.** A local function pointer occupies slot 16. Derive its load into RAX and the indirect-call bytes. Separately derive an R8 spill into slot 16. Explain why the REX extension bit differs from POP R8 and why using an RDI load for the call target would be wrong after staging arguments.
9. **C10-09 — Name the completion event.** A function CALL, a function-address MOVABS, a global-address MOVABS, an inline-string JMP, and an ELF file-size field need their final values. For each, name what is unknown, where it is remembered, who supplies it, and the patched width/formula. Explain why “patch everything when globals are finalized” fails. Include an address-only use of a late shim and an unused unresolved prototype.

### Changed prompts, with the answers closed

Use each exercise's original state except where changed here. These are new attempts, not instructions to edit or run the compiler.

- **C10-01:** Change six arguments to zero; then consider seven. Which steps emit no bytes, and which caller check becomes decisive?
- **C10-02:** Stipulate raw write result −9 instead of a successful transfer. Which values survive through this particular shim and caller move?
- **C10-03:** Start with an existing node at 8000 holding `(401,0)`, then prepend the same two fields. Derive all three patches and the changed arena use for this operation.
- **C10-04:** Keep both instruction offsets but move the target to `0x400500`. Separately select an encoding for bit pattern `0x8000000000000000` with LP64 enabled; explain why that profile matters.
- **C10-05:** Replace the body by `A\0B`, then compare LP64 adjacent tokens `"A\0" "B"` with the native string provider selected. Count bytes rather than visible characters.
- **C10-06:** Keep data length 16 and start position 1010, but set BSS extent to zero. Remove the BSS reference and recompute padding and both finalizer outputs.
- **C10-07:** Begin with a freshly selected direct workspace at count 17,919. Attempt two appends, then distinguish count exhaustion from a failed initial mapping.
- **C10-08:** Move the local pointer and R8 spill to slot 15. Which instruction fields shrink, and which register-selection bits stay the same?
- **C10-09:** Leave both lists nonempty for an ordinary prototype after late-shim emission. Contrast that outcome with successfully patched fields whose obsolete arena nodes remain allocated.

## Carry forward the owner and the completion event

The legacy driver orders output initialization and global initialization before header and program emission, then global finalization, then ELF finalization, then writing. Within program emission, a string wrapper closes its own jump immediately, a function definition or demanded late shim closes its two lists, and the program consumer patches the entry stub's call to `main`. Global address arrays wait for final data placement. ELF sizes wait for final file and BSS extents.

Every deferred field needs a known representation, a valid place to remember its use, and an event that supplies the missing fact. This chapter opened those patch events; it did not establish execution, arbitrary C acceptance, full System V interoperability, or a complete output-write success check. Its checked paper traces and feedback are inspectable teaching evidence, not a learner study or a compiler correctness proof.
