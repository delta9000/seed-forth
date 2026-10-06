# 2. Buffers, arenas, and failure ownership

[Previous: Compiler entry and profile](01-compiler-entry-and-profile.md) · [Practice help](../practice/02-solutions.md) · [Edition coverage](../../COVERAGE.md)

Before the compiler can explain `tri.c`, it must keep several versions of its work alive. The raw input still contains preprocessing directives. The lexer needs the source after preprocessing. The output writer needs bytes that may be patched later. A pointer to one of these regions is useful only while the bytes it names still belong to that job.

Our question is concrete: **after a read, allocation, or output append, which bytes are valid, where is the next position, and what stops the next operation from crossing the boundary?** By the end, you should be able to trace those states, distinguish a failed capacity check from an unchecked caller obligation, and explain what an error's line number actually identifies.

## Bring the contracts; keep the state visible

C01 supplies the builder/target distinction and Forth entry bridge. Here the Forth compiler is the running **builder**; its buffers are not the future C program's heap. We use eight-byte cells, byte addresses, little-endian multi-byte values, unsigned `/`, and stack tops at the right. `[lit]` supplies a decimal literal. `@` fetches a cell; `!` stores one; `c@`/`c!` transfer one byte. `+!` adds to a stored cell.

Three quick checks: does `cc-src-pos` name an address or its stored count? Does `c!` advance a cursor? Does reserving bytes initialize their contents? The answers are address, no, and no. If any reason is uncertain, revisit [named storage](../../seed-forth/chapters/10-storage-deferred-words-and-bytes.md) or [memory updates](../../seed-forth/chapters/06-memory-updates-and-writers.md). Experienced readers can start with the state tables and exercises.

### A reading key for the Forth excerpts

You can use the following contracts without first rebuilding their machine
code. If a contract is new, try the small example in its refresher before
tracing the longer compiler word.

| Notation in this chapter | Contract needed here | Targeted refresher |
|---|---|---|
| `swap`, `over`, `nip` | `[a,b]` becomes `[b,a]`, `[a,b,a]`, or `[b]`, respectively | [Shuffles and two stacks](../../seed-forth/chapters/04-return-stack-and-shuffles.md) |
| `>r`, `r@`, `r>` | Move a value to temporary return-stack storage, copy that temporary, then retrieve it; keep borrowing balanced before the containing word returns | [Return ownership](../../seed-forth/chapters/04-return-stack-and-shuffles.md) |
| `if, ... else, ... then,` | Compile a choice whose execution consumes a flag: nonzero selects the first arm, zero the second; `else,` may be absent | [Control flow](../../seed-forth/chapters/09-control-flow-by-patching.md) |
| `begin, ... while, ... repeat,` | Compile a loop: execute the prefix, consume its flag, run the body and repeat if nonzero, otherwise leave the loop | [Loops and balanced exits](../../seed-forth/chapters/09-control-flow-by-patching.md) |
| `exit,` | Compile an early return from the containing word; temporary return-stack ownership must already be balanced | [Early-return discipline](../../seed-forth/chapters/09-control-flow-by-patching.md) |
| `>`, `>=`, `0<` | Compare within the stated bounded domain; `0<` reads a cell's sign bit, while the subtraction-based two-operand comparisons need a valid difference range | [Comparison domains](../../seed-forth/chapters/05-comparisons-and-characters.md) |
| `+!`, `1+`, `1-` | Add to a stored cell, increment a value, decrement a value; only the first takes a storage address | [Stored updates](../../seed-forth/chapters/06-memory-updates-and-writers.md) and [small value helpers](../../seed-forth/chapters/10-storage-deferred-words-and-bytes.md) |
| `read`, `write`, `open`, `close` | Each makes one raw Linux request; the returned value must be interpreted rather than assumed successful | [I/O contracts](../../seed-forth/chapters/07-linux-io-contracts.md) |
| `defer`, tick (`'`), `is` | Create an indirect callable word, obtain a named word's execution token, and bind the indirect word to that behavior | [Deferred words](../../seed-forth/chapters/10-storage-deferred-words-and-bytes.md) |

The commas belong to the Forth word names. The source constructs control flow
when a definition is made; our body traces show what that compiled control
flow does when the word later runs. An unbalanced return-stack temporary is
not rescued merely by taking an early exit.

A short check: after `[5, 9] over`, the stack is `[5, 9, 5]`. After `[7] >r`,
the logical data stack is empty and the temporary is seven; `r@` copies seven
back without consuming the temporary, and `r>` subsequently retrieves it.
If either distinction is unclear, use that refresher before the allocator or
patcher trace. You may return directly here afterward.

**Evidence boundary.** This chapter describes inspected source at `7d7e1996d1753118181d43e1a413960d3a1ec24b`: [020-cc-arena.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/020-cc-arena.fth) and [030-cc-io.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth). All example states are paper derivations, not executed observations. Invented addresses and capacities are paper models of the named operations, not live addresses or proposed source changes. Assume valid owned storage, enough stack space, and small nonnegative counts with no address or arithmetic wrap unless a boundary is explicitly being examined.

A **buffer** is a region reserved for bytes. Its **base** is the first address; its **capacity** is the number of available bytes. A **length** counts meaningful bytes already present. A **cursor** identifies the next position to read or write. Here cursors usually count bytes from a base, although the arena keeps an actual address. An **offset** is such a distance, not an address by itself.

A **span** is an address and a length: `(A, n)` names bytes at offsets 0 through `n−1`. We write this as `[A, A+n)`, excluding the final address. A span does not copy the bytes or transfer ownership. Its **lifetime** is the interval during which the owner preserves that storage and its intended contents.

## One owner and one meaning for each cursor

The default storage is reserved in the Forth dictionary using `create` and `allot`:

| Region | Default capacity | Meaningful extent or next position | Main responsibility |
|---|---:|---|---|
| Raw input, `cc-in-buf` | 1,048,576 bytes (1 MiB) | `cc-in-len @` | Input loader writes; preprocessor reads |
| Expanded source, `cc-src-buf` | 2,097,152 bytes (2 MiB) | `cc-src-len @`; reader `cc-src-pos @` | Preprocessor produces; lexer reads |
| Output, `cc-out-buf` | 1,048,576 bytes (1 MiB) | `cc-out-pos @` | Emitter appends and patches |
| Arena, initially `cc-arena-base` | 32,768 bytes | Address in `cc-arena-ptr @` | Variable-sized compiler records |

MiB means 1,048,576 bytes. These are limits, not promises that every input will fit or that twice as much space always suffices for preprocessing. Larger selectable storage appears in [the workspace section](#select-storage-before-using-it); there is no automatic growth.

Before creating the large default buffers, `030` calls `skip-vm-pages`. This profile-specific library word assigns HERE=0x414000 so dictionary allocation skips the seed's fixed stack, I/O, token, and system-variable regions. The source assumes earlier allocation has stayed below the reserved pages. It does not ask Linux for memory or discover a safe destination. Each subsequent `create` also emits a dictionary header and body, so 0x414000 is not a promised input-payload address.

The public buffer words fetch selected values. For example:

```forth
: cc-in-buf ( -- address ) cc-in-buffer @ ;
: cc-in-cap ( -- bytes ) cc-in-limit @ ;
```

The pairs `cc-src-buf`/`cc-src-cap` and `cc-out-buf`/`cc-out-cap` work the same way. Callers use these accessors rather than assuming a default address. Changing a selected pointer changes where later operations act; it does not move existing bytes.

### A small state block makes reading reversible

The lexer turns source bytes into tokens. Its current position and current-token information occupy one 64-byte block, eight cells:

| Offset | Name | Meaning |
|---:|---|---|
| 0 | `cc-src-pos` | Offset of next source byte |
| 8 | `cc-src-line` | Current one-based source line |
| 16 | `tok-kind` | Category of current token |
| 24 | `tok-num` | Number, character, or punctuation value |
| 32 | `tok-str-addr` | Address of current name/string bytes |
| 40 | `tok-str-len` | Their length |
| 48 | `tok-kw-id` | Keyword identifier when relevant |
| 56 | `cc-tok-pending` | All-ones/-1 means a token was put back |

Each name is a constant whose value is the address of its cell, so `cc-src-line @` fetches the line. Later lexer marks copy this block away and restore it. That restores the eight values; it does not copy the strings they point at, the source buffer, output, or arena. The pointed-to bytes must remain valid. C06 will open the marking mechanism.

Initialization is deliberately narrower than a full snapshot reset:

```forth
: cc-src-init
  [lit] 0 cc-src-len !
  [lit] 0 cc-src-pos !
  [lit] 1 cc-src-line ! ;
```

This makes the source logically empty and rewinds the reader. It does not erase its backing bytes or reset the other six token cells. `cc-out-init` similarly sets only `cc-out-pos` to zero. Resetting a length ends the old content's logical use without requiring a memory-clearing pass.

## Read a file by tracking progress

The library's `read ( fd buf count -- n )` makes one Linux request. A file descriptor, or **fd**, identifies an open input/output endpoint; stdin is fd 0. A positive result is bytes transferred, zero denotes end of input for this file-reading use, and a negative raw result denotes an error. A request is not a guarantee that all requested bytes arrive.

`cc-read-all ( fd buf cap code -- n )` saves its inputs in `cc-ra-*` variables and sets the accumulated count to zero. Its loop is:

```forth
  begin,
    cc-ra-fd @  cc-ra-buf @ cc-ra-n @ +  cc-ra-cap @ cc-ra-n @ -  read
    dup [lit] 0 >
  while,
    cc-ra-n +!
    cc-ra-n @ 1+ cc-ra-cap @ cc-ra-code @ cc-check-cap   \ full: die
  repeat,
  drop cc-ra-n @ ;
```

If `n` bytes have arrived, their span is `[B, B+n)`. The next request starts at `B+n`, after that prefix, and asks for `cap−n` bytes. The duplicated result controls the loop; its original copy is added to the accumulated count only when positive.

Take a paper buffer of capacity 8, base B, and successive read results 3, 2, 0:

| Request | Count before | Destination and request size | Result | Count after | Why |
|---:|---:|---|---:|---:|---|
| 1 | 0 | B, 8 bytes | 3 | 3 | Add progress; `3+1 <= 8` |
| 2 | 3 | B+3, 5 bytes | 2 | 5 | Preserve first three bytes; `5+1 <= 8` |
| 3 | 5 | B+5, 3 bytes | 0 | 5 | Loop stops; return accumulated count |

The function returns **five**, not the original buffer address. The caller already knows B, so it can form span `(B, 5)`. Nothing here appends a terminating zero byte.

Why check `n+1 <= cap`? This design refuses a completely full buffer before trying another read. With capacity 8, a result of 8 on the first request causes the supplied error even if the file ends exactly there. Capacity minus one is the largest accepted payload. The spare byte is a policy margin, not a terminator that this routine writes.

**Important limit:** the loop tests only whether the raw result is positive. A negative result takes the same exit path as zero and returns the prefix count. There is no retry or distinct read-error diagnostic in this word. Its name describes its aim; the implementation gives the narrower guarantee above. The globals also mean independent overlapping invocations cannot each retain their own read state.

`cc-load-stdin` first calls `cc-src-init`, then invokes this reader with fd 0, the selected input buffer and capacity, and error code 20. It stores the returned count in `cc-in-len`. Rewinding first makes an input-capacity failure report line 1. It does not turn an ignored negative read result into an error.

### Peek, consume, and cross a line

`cc-eof?` tests `pos >= len`. `cc-peek-char` returns zero if that is true; otherwise it fetches the byte at `cc-src-buf+pos`, without changing state. `cc-next-char` calls peek, increments position, and increments line only if the returned byte equals newline (10).

For a source span containing `A`, newline, `B`, with length 3:

| Operation | Returned byte | Position after | Line after |
|---|---:|---:|---:|
| Initialize reader for this existing span: pos=0, line=1 | — | 0 | 1 |
| Peek | 65 | 0 | 1 |
| Next | 65 | 1 | 1 |
| Next | 10 | 2 | 2 |
| Next | 66 | 3 | 2 |
| Peek at EOF | 0 | 3 | 2 |
| Next at EOF | 0 | 4 | 2 |

The last row is intentional: `next` advances even at EOF. Use the length-based predicate to reason about completion. A real zero byte inside a span also makes peek return zero; the byte alone cannot distinguish that case from EOF.

**Pause point.** Save `(B, cap=8, n=5)` and `(source length=3, pos=3, line=2)`. On returning, explain why the first next read asks for three bytes while the second next-character call advances beyond its length.

## A failure owns a code, not a recovery path

Capacity checks consume a proposed extent, a limit, and a diagnostic code:

```forth
: cc-check-cap
  >r > if, r> cc-die then,
  r> drop ;
```

For `[7, 8, 20]`, `>r` parks 20 on the return stack, `>` tests `7>8`, and the false arm removes the parked code. The normal result stack is empty. For `[9, 8, 20]`, the true arm retrieves 20 and calls `cc-die`, which exits the process. This is not an exception that returns a restored compiler state.

The check assumes sane counts and arithmetic. It neither checks a proposed address nor repairs overflow that occurred while computing `n`. The library's order comparisons use a subtraction sign and require operands whose difference fits the signed range. The small buffer counts here satisfy that condition.

`cc-die` attempts to print `cc: line N: error CODE` followed by newline to stderr, fd 2, then supplies CODE to the library's `die`. Its line comes from `cc-src-line`, meaning the reader's line in the flattened, preprocessed stream. It is not a filename-and-original-line map for included files. The message has no storage-profile tag. Before normal source initialization, do not infer a meaningful source location merely because the formatter printed a number.

Two helpers explain the formatting. `cc-err-write ( a u -- )` parks length and address, rebuilds `(2, a, u)`, calls `write`, and drops its result. `cc-err-dec` owns a 20-byte digit buffer. It obtains each remainder as `u−(u/10)*10`, converts it to an ASCII digit, and fills from the end backward. For 42 it stores `2` at offset 19, then `4` at offset 18, and writes span `(digits+18, 2)`. For zero its loop still stores one `0`. Twenty bytes suffice for an unsigned 64-bit decimal value.

The prefix, separator, and newline are stored byte sequences of lengths 9, 8, and 1. These diagnostic writes are also single requests with ignored results. Thus the source establishes an attempted diagnostic and an exit, not guaranteed complete stderr delivery. Keep that distinction when interpreting a missing or partial error message.

## Allocate records without disturbing the dictionary

The library's `allot` advances HERE, where new Forth definitions are built. The compiler's **arena** is a separately owned region for many small records. A **bump allocator** gives out the current address and advances one pointer; it has no operation to free an individual record.

```forth
: cc-alloc                                       ( n -- addr )
  [lit] 7 + [lit] 8 / [lit] 8 *                  \ align up to 8 bytes
  cc-arena-ptr @ swap over +                     ( old-top new-top )
  dup cc-arena-start @ -  cc-arena-limit @ [lit] 10 cc-check-cap
  cc-arena-ptr ! ;                               ( -- old-top )
```

For a positive small request, `(n+7)/8*8` rounds its size up to a multiple of eight. Suppose start=1000, limit=24, pointer=1000, and request=9:

| After operation | Data stack | Pointer stored |
|---|---|---:|
| Rounded size | `[16]` | 1000 |
| `cc-arena-ptr @ swap over +` | `[1000, 1016]` | 1000 |
| Form proposed used bytes and supply limit/code | `[1000, 1016, 16, 24, 10]` | 1000 |
| Successful capacity check | `[1000, 1016]` | 1000 |
| Store new pointer | `[1000]` | 1016 |

The returned address names the start, not the end. The requested nine bytes fit within the reserved sixteen; the allocator initializes neither them nor the padding. A following request of eight uses the remaining eight bytes exactly, returning 1016 and setting pointer=1024. A further positive request fails with code 10 before the pointer store.

**Faded example.** From that full state, request zero. Fill in rounded size, proposed used bytes, returned address, and final pointer before checking: 0, 24, 1024, 1024. An empty allocation can return an end address without granting any byte to read or write. It is not a fresh distinct block.

Rounding sizes preserves the starting address's residue modulo eight. It does not independently align that start. If start=1003, successive rounded allocations still begin at addresses congruent to three modulo eight. An eight-aligned mapped start yields aligned blocks; byte-packed dictionary `create` alone does not establish that condition. Also, `cc-alloc` does not reject arbitrary negative or overflowing requests before its additions. Use it within the bounded compiler-record contract, not as a checked general-purpose allocation API.

The default start and pointer initially name the 32 KiB dictionary region. Allocated records remain valid while their region is retained and not reused. These files provide no per-record free and no arena reset on `cc-src-init` or `cc-out-init`. Saving a lexer position does not undo allocations. This simple lifetime avoids moving records while other records point at them; its cost is retaining allocations together.

## Append bytes, then patch remembered positions

Output position is both the next append offset and the length of the emitted prefix. The emitter checks before writing:

```forth
: cc-emit-byte
  cc-out-pos @ 1+ cc-out-cap [lit] 21 cc-check-cap
  cc-out-buf cc-out-pos @ + c!
  [lit] 1 cc-out-pos +! ;
```

With position=7 and capacity=8, the prospective length is 8, so the byte is stored at offset 7 and position becomes 8. Unlike `cc-read-all`, output may fill its capacity exactly. The next byte fails with code 21 before its store. `c!` writes the low eight bits of its supplied value.

`cc-emit-4le` emits the low four bytes using repeated unsigned division by 256; `cc-emit-8le` emits a four-byte low half, divides the original value by 256 four times, then emits the high half. For 1297, the four emitted decimal bytes are `17 5 0 0`: `1297 = 5*256+17`. Every individual byte is checked. There is no whole-field reservation: if only two bytes remain, a four-byte emission can store two bytes and then exit on the third.

Back-patching means replacing bytes whose positions were remembered earlier. `cc-out-patch-byte ( v offset -- )` adds the selected output base to the offset and stores one byte. `cc-out-patch-4le` and `cc-out-patch-8le` park the original offset with `>r`, peel off bytes in the same low-to-high order, and write at successive offsets. `r@` retains the offset for intermediate stores; the final `r>` removes it. Patching leaves `cc-out-pos` unchanged.

For an existing six-byte output `65 66 17 5 0 0`, patching 305419896 (hexadecimal 12345678) at offset zero produces `120 86 52 18 0 0`. Position remains six. Patch helpers have **no capacity or initialized-prefix check**. Their caller must establish that every patched byte belongs to the intended output span. An in-capacity patch beyond its logical end does not extend that end.

### Requesting a write is not establishing a complete file

`cc-write-output` expects an address of a NUL-terminated path, opens it with flags 577 and requested mode 493 (octal 0755), and exits with code 22 if the fd is negative. Here 577 combines write-only, create, and truncate. The subsequent source is:

```forth
  >r                                              ( ; R: fd )
  r@ cc-out-buf cc-out-pos @ write drop           \ write all bytes
  r> close drop ;
```

The implementation makes **one** write request for the whole emitted prefix, then closes. It discards both results. With six output bytes and a write result of four, it does not request the missing two. With a negative write result, it still proceeds to close. The source comment expresses the intended whole-file operation; there is no write-all retry loop here. Even a fully populated output buffer therefore does not establish that a complete executable reached disk.

## Shared names need shared representations

Three compact helpers prepare later stages. `ident-start?` accepts an ASCII letter or underscore; `ident-cont?` also accepts digits. Thus `7` can continue an identifier but cannot start one under these classifiers. These words classify one byte, not a whole name or a Unicode character sequence.

`cell[] ( i arr -- addr )` computes `arr + i*8`. A **parallel-array table** keeps one field per array, using the same index in each. A name table has an address array and a length array; neither `cell[]` nor fetching an entry checks the table boundary.

`cc-name-find ( a u addrs lens count -- i | -1 )` stores the sought span and table bases in globals, starts at index `count−1`, and searches downward. At each index it first checks the stored length. Only an equal-length candidate reaches `bytes-eq`, which compares exactly that many bytes. On a match `exit,` returns the index already on the stack; exhausting the loop leaves -1.

Suppose entries 0, 1, 2 name `row`, `rows`, `row`. Searching for the three-byte `row` returns 2 immediately. Searching for `rows` skips index 2 on length, then returns 1 after byte comparison. Count zero starts at -1 and reads no table entries. Newest-first order lets later definitions hide earlier ones without rewriting the older entries. As with the reader's globals, this is shared scratch state, not independent state for overlapping calls. Name spans must remain valid for later lookup; storing an address alone does not preserve its bytes.

## Select storage before using it

This section is a deeper reference for the opt-in workspace. The default learning path needs the invariant: **select addresses and limits first, then initialize and fill them**. Selection itself preserves cursor and length cells and copies no payload.

The direct-GCC I/O constants are raw/source/output capacities of **3/7/4 MiB**. Source comments attribute their choice to measured workloads; this manuscript has not repeated those measurements. They are fixed policies, not adaptive estimates. `cc-io-default-workspace` restores all three default address/limit pairs. `cc-io-direct-workspace` checks the cached `cc-io-direct-base`; if zero, it maps the sum, 14 MiB, and stores the returned base M. It then selects adjacent spans:

| Selected region | Base | Capacity |
|---|---|---:|
| Raw | M | 3 MiB |
| Source | M+3 MiB | 7 MiB |
| Output | M+10 MiB | 4 MiB |

Selecting direct storage again reuses M. Selecting default storage does not unmap M. These words neither retry a capacity failure with a larger allocation nor enlarge the seed's existing segment.

`cc-workspace-round ( bytes code -- page-bytes )` rejects invalid sizes before computing `(bytes+4095)/4096*4096`: accepted sizes are positive and no larger than 9,223,372,036,854,771,712. The upper bound is `2^63−4096`, keeping the addition within positive signed range. A request of 4097 rounds to 8192; 4096 remains 4096. These checks belong to this helper, not automatically to every allocator.

`cc-workspace-syscall` requests Linux `mmap` with address hint 0, rounded length, protection 3 (read/write), flags 34 (private/anonymous), fd -1, offset 0, syscall number 9. Its deferred entry, `cc-workspace-syscall-fwd`, is initially bound to that word. The indirection allows a compatible implementation to be selected without changing callers. `cc-workspace-map` preserves its caller's error code, rounds, calls the deferred entry, and rejects a nonpositive result through `cc-die`. The I/O selector supplies code 20. No successful-return claim applies after that exit path.

The arena has a separate mapping selector, `cc-arena-map ( bytes -- )`, in `020`. It saves the requested limit, makes its own anonymous read/write mapping request, rejects a negative result with code 10, and sets both arena start and pointer to the returned address. It does **not** call `cc-workspace-round`, cache its result, copy older arena records, or release an older mapping. Its caller supplies the bounded policy size. Do not infer the I/O helper's guards or lifetime policy from the similar name.

## Practice: predict, explain, then change a boundary

Use paper state only; no compiler execution or source changes are needed. [Separate hints and checked solutions](../practice/02-solutions.md) include changed cases. If a step is unclear, inspect its intermediate stack or span rather than guessing the final number.

1. **C2-01 — Distinguish capacity from accepted length.** For capacity 8 and base B, trace read results 3, 4, 0: destinations, requested counts, accumulated counts, returned span. Change the second result to 5. Then change it to a negative error. Which cases reach a diagnostic, and why?
2. **C2-02 — Complete an allocation trace.** With start=1000, limit=24, pointer=1000, allocate sizes 1, 9, 0, then 1. Derive rounded sizes, returned addresses, and pointer states. Which operation fails? Explain what changes if start and pointer are initially 1003.
3. **C2-03 — Separate append, patch, and delivery.** Capacity=6 and position=0. Append bytes 65 and 66, then emit 1297 with `cc-emit-4le`. Patch 305419896 at offset 0. Derive the six bytes and position. Predict one more append. If the file write returns four, what does `cc-write-output` actually do next?
4. **C2-04 — Track a borrowed source and its location.** Given source bytes `A`, newline, `B`, length=3, pos=0, line=1, perform three next calls, peek, then next. Which cells change? At that final state, what diagnostic does code 21 attempt? Does copying the 64-byte lexer state preserve the source bytes or identify an included file's original line?
5. **C2-05 — Keep a new workspace's state honest.** A compiler has input length=100 and output position=6 in default storage. It selects the direct workspace, then selects it again. For a successful first mapping at M, derive all three base/limit pairs, mapping count, and the two stored lengths. What initialization is still needed before compiling a fresh source? Explain separately why a table lookup for `row` in [`row`, `rows`, `row`] returns index 2.

## What we established

The compiler separates raw, expanded, output, and record storage; pointers and counts give each operation a local contract. Reads accumulate progress but reserve one byte of capacity. Output appends can fill their buffer, while patches rely on caller-established bounds. Arena sizes are rounded without initializing contents or individually freeing records. A line-numbered process exit is different from a recoverable error, and ignored I/O results limit what successful return tells us.

[C03: Preprocessing regions and includes](03-preprocessing-regions-and-includes.md) follows the preprocessor as it turns owned input and include spans into one expanded source stream. Keep the lifetime question with you: who preserves the bytes after a pointer to them has been saved?

### Evidence and remaining checks

The [word-to-source map](../source-map.csv) links each of the two files' 35 colon definitions to its immutable source span and this teaching home. The state block, buffer declarations, constants, and deferred entry supply shared storage beyond those definitions.

The pinned [arena smoke test](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/test-020-cc-arena.fth) checks distinct successive allocations, +16 spacing, preservation of a stored cell, and byte comparisons. It does not directly test address modulo eight or exhaustion. The [I/O smoke test](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/test-030-cc-io.fth) supplies `Ab\nC` manually and checks reader states, four/eight-byte emission, and patch results. It bypasses stdin loading and file output; it does not establish short-read, short-write, or mapping behavior.

These are descriptions of inspected tests, not reports that they were run. [010-lib.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth) supplies the storage, comparison, syscall, and deferred-call contracts. [050-cc-lex.fth](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth) confirms the later eight-cell mark/reset boundary. The [historical chapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/21-arena-and-io-buffers.md) provides context; its blanket capacity and delivery language is not substituted for the exact definitions here. Real-reader learnability and executed example behavior remain unverified.
