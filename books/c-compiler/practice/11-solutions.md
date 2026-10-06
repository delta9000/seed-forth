# C11 practice help: a bounded legacy runtime

[Back to the chapter](../chapters/11-a-bounded-legacy-runtime.md)

These are checked **manual derivations** for the pinned default legacy profile. No compiler, generated program, Forth example, or runtime test was executed. The kernel results in the exercises are supplied premises, not observations. Use the hints when useful; the answers remain directly accessible. A correct number with the wrong unit is not yet a correct runtime contract.

## Entry check

1. The call's next instruction begins at offset **705**. Relative displacement is measured from there, not from the opcode at 700 or operand start at 701
2. **Three bytes** are newly supplied input. Capacity twelve permits storage; request eight asks for progress; result three reports that progress. No terminator is implied
3. Argument four arrives in **RCX** for this restricted generated-function call, but in **R10** for a Linux/x86-64 syscall

If the first answer differs, revisit C10's relative field. If the second differs, draw separate capacity, request, and valid-input extents. If the third differs, keep the two register rows visible through one transfer example. These are focused repairs, not reasons to restart the book.

## Hints

### C11-01 hints

1. There are two different pushes: `CALL` preserves a return address, then the shim preserves the eight-byte argument
2. Only the shim's `POP` writes RDI before returning. Nothing after the syscall writes RAX in `putchar`
3. Compare that last fact with `fputc`'s byte load into EAX and the generic write wrapper's sign test

### C11-02 hints

1. `JNZ` distinguishes zero from nonzero. Do not silently replace it with a greater-than-zero condition
2. Record the scratch byte before each supplied read and after it. A zero-extension load returns a number from 0 through 255

### C11-03 hints

1. Cross out every mode character after the first; the body never reads them
2. `fopen` tests whether the raw result is negative. `fclose` clears EAX without testing the raw result

### C11-04 hints

1. Before the syscall, the fourth function argument must become the first syscall argument
2. Preserve size three across the syscall on the stack. Divide the actual result, not the requested count
3. Mark the exact eleven-byte transferred span before grouping it into elements

### C11-05 hints

1. Round each requested allocation separately: `(product+7) & -8`, under the chapter's nonoverflowing assumptions
2. `free` has only a `RET`. The malloc tail jump supplies size one but reuses the same allocator state
3. The RIP-relative base is region offset 76 plus seven instruction bytes. Add the displacement only after that

### C11-06 hints

1. `REP MOVSB` knows a count, not the meaning of a zero byte. Copy exactly three positions
2. `strrchr` compares and possibly records a match before testing for end of string
3. A readable four-byte region with no NUL is insufficient for an unbounded string scan

### C11-07 hints

1. The late-emission test combines the call and address heads with OR
2. A relative-call field is four bytes; the recorded function-address field is eight. Their walkers are different
3. `memset` is absent from the late-emitter table

### C11-08 hints

1. Identify the actor that produced each apparent success: builder, close adapter, or allocator
2. Ask whether that actor inspected the result or enforced the property being claimed
3. Profile labels identify selected mechanisms; they do not create observations or add instructions

## Checked solutions

### C11-01 — Keep the character, request, and result separate

Immediately after `CALL`, memory at S−8 holds the caller's return address and RSP=S−8. The shim's `PUSH RDI` makes RSP=S−16 and stores 42 in `[S−16,S−8)`. Its little-endian bytes are:

```text
2A 00 00 00 00 00 00 00
```

The two slots have different meanings. S−16 supplies a one-byte readable buffer; S−8 holds the address eventually consumed by `RET`.

Immediately before the write:

| Register | Value | Meaning |
|---|---|---|
| RAX | 1 | Write syscall number |
| RDI | 1 | Stdout descriptor |
| RSI | S−16 | Buffer address |
| RDX | 1 | Requested byte count |

On either supplied returning result, `POP RDI` reloads 42 and restores RSP to S−8. `RET` consumes the return address and restores RSP to S. Neither instruction changes RAX.

| Supplied raw result | RSP after return | RAX after return | RDI before caller's result move | RDI after result move |
|---:|---|---:|---:|---:|
| 1 | S | 1 | 42 | 1 |
| −9 | S | −9 | 42 | −9 |

For the adapter comparison:

| Supplied raw write result | `putchar` | `fputc` | Generic `write` |
|---:|---:|---:|---:|
| 1 | 1 | 42 | 1 |
| −9 | −9 | 42 | −1 |

`fputc` overwrites the raw result with the zero-extended saved byte. The generic wrapper changes a negative result to −1. Only `putchar` leaves the raw negative value unchanged. The requested count was already one before the kernel returned; the result reports what happened to that request and cannot retroactively change its size.

**Wrong paths to diagnose.** Returning 42 from `putchar` confuses RDI's temporary restoration with RAX's return role. Ending at RSP=S−8 omits the effect of `RET`; ending at S+8 consumes a nonexistent third stack item. Saying one means “ASCII one” assigns the wrong unit.

**Repair and reattempt.** If registers were confused, write only RAX and RDI across the final three instructions. If stack slots were confused, label them “scratch” and “return” before applying any pop. Then try C11-01R without the return table.

### C11-02 — Follow the input branch

Incoming RDI is hexadecimal `0x63`, decimal 99. The scratch initially contains low byte `63`; its other seven bytes are zero for this supplied complete register value. Each row below is a separate call with that same initial state.

| Supplied read result and memory effect | Zero? | Branch | Returned RAX | New character established? |
|---|---|---|---:|---|
| 1; scratch becomes `FF` | No | Byte load | 255 | Yes, byte value 255 |
| 0; scratch unchanged | Yes | Load −1; skip byte load | −1 | No; ordinary EOF case |
| −9; scratch unchanged | No | Byte load | 99 | No; old scratch byte was exposed |

The zero-extension instruction maps byte `FF` to positive 255. It does not sign-extend it to −1. Conversely, −9 is nonzero, so it does not take the EOF branch. The final byte value 99 is a consequence of the supplied unchanged scratch state, not a newly read `c` character.

A claim that every nonpositive result becomes −1 would require a different conditional rule. The inspected body checks zero only. If the incoming scratch value or failure's memory effect were unspecified, the exact stale-byte result would also be unspecified by the exercise.

**Wrong paths to diagnose.** Returning −9 is the policy of a raw-result adapter, not this one. Returning −1 on both zero and −9 invents a signed comparison absent from the body. Returning −1 for `FF` confuses byte signedness with `MOVZX`.

**Repair and reattempt.** Put three supplied values, positive/zero/negative, into the predicate “equals zero.” Only then follow the selected branch. C11-02R changes the byte while retaining a successful positive read result.

### C11-03 — Read the mode policy literally

All three calls pass creation-mode argument 420 decimal, octal `0644`. The flag choices depend on one byte:

| Mode text | Inspected first byte | Flags | Selected operation |
|---|---|---:|---|
| `r+` | `r` | 0 | Read-only open |
| `w+` | `w` | 577 / `0x241` | Write, create, truncate |
| `ab` | `a` | 1089 / `0x441` | Write, create, append |

There is no branch for plus or binary mode. Supplying creation-mode bits is not a guarantee of exact resulting file permissions: the kernel and process environment own the external operation. In the read-only case, the mode argument does not turn this into a create request.

A raw open result zero is nonnegative and survives as zero. A raw result −13 is negative and is replaced by zero. Thus both become the same representation. The returned value alone cannot distinguish a valid descriptor zero from failure. This is relevant when an earlier descriptor such as stdin has been closed; the small integer zero is not inherently unavailable for a later open.

For supplied raw close result −9:

- `fclose` clears EAX and returns **zero**
- Late `close` takes its negative-result branch and returns **−1**

Neither stores 9 in an `errno` variable. Zero from `fclose` cannot certify successful closing.

**Wrong paths to diagnose.** Choosing read/write flags for `r+` imports a hosted-library mode parser. Treating fd zero as impossible substitutes a convention for descriptor lifetime. Treating the two close adapters as aliases overlooks the instructions after `SYSCALL`.

**Repair and reattempt.** Trace the source's two character comparisons, then the independent result sign test. Try the unrecognized first byte in C11-03R to check whether the actual fallback, rather than familiar library behavior, controls the answer.

### C11-04 — Complete the transfer accounting

At generated-function entry:

```text
RDI=B      RSI=3      RDX=5      RCX=7
```

`fread` saves size three on the stack, computes 3×5=15, moves the count to RDX, pointer B to RSI, and descriptor 7 to RDI. Clearing EAX prepares syscall number zero:

```text
RAX=0      RDI=7      RSI=B      RDX=15
```

The supplied result is eleven. After the syscall, popping the saved size restores RCX=3, regardless of the syscall's use of RCX. The positive-result branch clears EDX and divides unsigned `0:11` by three. Quotient RAX is **3**, remainder RDX is **2**.

The newly written span is `[B,B+11)`. Three complete elements occupy `[B,B+9)`. Bytes at B+9 and B+10 form a partial fourth element; they were transferred even though the quotient does not count a complete fourth element. Bytes B+11 through B+14 have no new-input guarantee from this request. No byte at B+11 is automatically made a terminator.

For `fwrite`, preparation instead selects syscall one, with the same descriptor, buffer, and requested fifteen bytes. Its returned result is **11 bytes**, not three elements. The return policies are:

| Supplied raw result | `fread` return | Division? | `fwrite` return |
|---:|---:|---|---:|
| 11 | 3 complete elements | Yes, 11 / 3 | 11 bytes |
| 0 | 0 | No | 0 |
| −5 | −5 | No | −5 |

This table describes returning paths. It does not imply a successful full transfer on zero or negative values. Buffer direction matters: read requires writable storage; write requires readable storage. The valid product and capacity are supplied here rather than checked by either shim.

**Wrong paths to diagnose.** Returning five divides the requested count rather than the actual progress. Returning three from `fwrite` imports `fread`'s division. Declaring only nine bytes written into B overlooks the partial element. Treating all fifteen bytes as fresh input assumes full progress.

**Repair and reattempt.** First draw the eleven-byte valid-input prefix; then overlay three-byte element boundaries. If the distinction is clear, C11-04R removes it numerically by making one element equal one byte. Explain the hidden unit difference anyway.

### C11-05 — Keep heap storage and heap payload apart

The initial position is H+24. `calloc(3,5)` computes fifteen requested bytes and rounds up to sixteen:

```text
3*5 = 15
15+7 = 22
22 & -8 = 16
```

It returns the old position **H+24** and stores **H+40** as the next position. The rounded claimed interval is `[H+24,H+40)`; the caller requested fifteen bytes within it.

`free(H+24)` executes only `RET`. The position remains H+40. It neither clears the bytes nor makes that interval available to the next request.

`malloc(9)` sets the second argument to one and tail-jumps to calloc. The product nine rounds to sixteen. It returns **H+40** and stores **H+56**. It does not return H+24 merely because that earlier pointer was passed to `free`.

| Point | Heap base | Position | Newly returned pointer |
|---|---|---|---|
| Initial | H | H+24 | — |
| After calloc | H | H+40 | H+24 |
| After free | H | H+40 | No useful return specified |
| After malloc | H | H+56 | H+40 |

For the RIP-relative load, the instruction ends at region offset `76+7=83`. Add displacement 22 to reach **105**. At region file offset 408, the position cell is at `408+105=513`, hexadecimal `0x201`. Its target address is **`0x400201`**.

That address identifies the inline cell **holding** the current heap pointer. H+24 and H+40 identify returned slices of the separate mmap mapping. After the sequence, the cell at `0x400201` contains H+56. Neither its file offset 513 nor its target address `0x400201` is the allocated slice just returned.

For the chapter's pause point, which begins instead at position H+16, `malloc(9)` returns H+16 and advances to H+32. Keep these separate starting fixtures separate.

**Wrong paths to diagnose.** Returning H+56 from the second allocation confuses the advanced position with the saved return value. Using region offset 98 calculates `76+22` from the instruction start and omits its seven-byte length. Treating 513 as a runtime pointer changes coordinate systems without adding the image base. Reusing H+24 invents a free-list operation.

**Repair and reattempt.** Draw one box for the state cell and an arrow from it to a position inside the large mapping. Update the arrow while preserving the old pointer in RAX. Then attempt C11-05R, which changes both requested size and region placement in separate subcases.

### C11-06 — Transfer a string with an explicit boundary

The three copied source bytes are `2A`, `61`, and `2A`. With DF clear, the copy advances both cursors once per byte and consumes the repetition count:

| State | RAX | RDI | RSI | RCX | D's four known bytes |
|---|---|---|---|---:|---|
| After result/count preparation | D | D | A | 3 | `7F 7F 7F 7F` |
| After first byte | D | D+1 | A+1 | 2 | `2A 7F 7F 7F` |
| After second byte | D | D+2 | A+2 | 1 | `2A 61 7F 7F` |
| After third byte | D | D+3 | A+3 | 0 | `2A 61 2A 7F` |

The return is **D**. RAX preserves the original destination, not the current cursor. The source terminator at A+3 was never copied. D's four known bytes contain no NUL, so a bounded valid `strlen(D)` trace is not justified: the scan would need to read farther, and no readable terminated extension was supplied. It is not enough to say the expected length is three because three bytes were copied.

The independent source searches return:

- `strrchr(A,'*')` → **A+2**, the later matching star
- `strrchr(A,0)` → **A+3**, the terminator itself

The second result follows because matching happens before the end test. `strrchr` includes the terminating byte in the search.

With DF set, the supplied forward-copy premise is lost. `MOVSB` starts at A and D but then decrements the pointers, so the next accesses would be A−1 and D−1. The exercise did not provide valid source/destination extents in that direction. The body supplies no `CLD` to restore the missing condition.

**Wrong paths to diagnose.** Returning D+3 selects the wrong register. Inserting a zero at D+3 invents a string-copy policy. Returning zero for the search character zero tests end before equality, reversing the actual sequence. Predicting the same copy with either DF value omits part of the machine contract.

**Repair and reattempt.** Write the count above the source bytes and cross off exactly that many bytes. Do not use the word “string” until termination is established. C11-06R includes the terminator and varies the full character argument without changing its low byte.

### C11-07 — Demand a body without calling it

The combined head test is nonzero because the address head is N. Therefore `cc-emit-late-shims`:

1. Stores the current generated target address as the symbol's value
2. Calls the relative-call walker with an empty head, which patches nothing
3. Calls the imm64 address walker with head N and patches every waiting address field to the same target
4. Clears both owner head cells
5. Executes the row's `cc-emit-strlen-shim` token, appending **fourteen bytes**

No other late body is required by this fixture. The list walkers and owner-head stores do different jobs: visiting a list does not itself clear its owner's head. An address-only use still needs executable code at the address it will load.

An unused `memset` prototype has no pending sites and does not, by its mere presence, produce error 206. This statement assumes the rest of the program meets its own requirements, including a defined `main`. With a pending address use and no user definition, there is no late `memset` emitter to resolve it. The unresolved-use check reaches **206**. Registration is not an automatic link to host libc.

The emitter token belongs to a Forth word executing in the builder. It names the producer of the machine bytes. The generated function address identifies where those produced bytes are mapped in the later process. Loading the emitter token into a generated function pointer would confuse actor, address space, and calling convention.

**Wrong paths to diagnose.** Emitting nothing uses “called” as a substitute for the actual OR condition. Patching the address with a relative displacement uses the wrong field width and meaning. Saying `memset` is the twentieth shim confuses raw-name storage with a supplied body.

**Repair and reattempt.** Draw two independently labeled list heads beside one function symbol. Put a node on only one, then trace the same OR test. C11-07R changes which symbol still owns pending uses.

### C11-08 — Separate three claims of success

The three implications need different evidence:

1. **Builder exit zero → complete generated file:** C02's legacy writer discards write and close results. The exit status does not report whether every output byte was written. Even a complete file would still need separate evidence for loading and reaching entry
2. **`fclose` zero → successful file operation:** This shim overwrites the returning raw close result with zero. That zero alone establishes neither successful closing nor successful earlier writes; the earlier transfer results also matter
3. **Nonzero allocation return → valid allocation:** The runtime does not validate mmap failure, arithmetic overflow, or remaining capacity. A nonzero number may be derived from failed mapping state or point beyond the mapping. The chapter's successful allocation conclusion needs its explicit mapping, arithmetic, capacity, and lifetime premises

Calling the profile “System V libc” would supply neither missing instructions nor missing observations. The default profile has specific bodies and legacy data-model choices. A different selected runtime needs its own contract and evidence, rather than a relabeling of this one.

A sufficient answer names the missing check or observation for each implication. “We should test more” is too vague to distinguish file completeness from allocation validity. Conversely, this exercise does not prove that every file write or allocation fails. It explains why the offered evidence is insufficient.

**Wrong paths to diagnose.** Treating absence of proof as proof of failure overcorrects. Treating a source-level comment as an executed result changes evidence type. Treating a familiar register order as full hosted-library compatibility changes profile.

**Repair and reattempt.** Put each claim into the form “observation X establishes property Y under premises P.” Identify the missing P or missing observation. C11-08R introduces one real observation but keeps its scope bounded.

## Changed-case checks

Keep the chapter's [answer-free changed prompts](../chapters/11-a-bounded-legacy-runtime.md#changed-cases-fresh-prompts-no-answers-here) separate while attempting them. These checks explain the consequential difference in each new case.

### C11-01R

The pushed value 255 occupies `FF 00 00 00 00 00 00 00`. The supplied raw write result is zero, so `putchar` returns **0**, `fputc` returns **255**, and generic `write` returns **0**. No byte of output progress is established. The difference comes from post-syscall policy, not a different requested character or count.

### C11-02R

A successful one-byte read of NUL has raw result 1 and scratch byte zero. It takes the nonzero branch and returns **0**, establishing one new byte whose value is zero. EOF has raw result zero and returns **−1**, establishing no new byte. These are distinguishable in this shim, unlike an interface that used byte zero as its EOF sentinel.

### C11-03R

First byte `x` matches neither `w` nor `a`. Flags remain **0**, creation-mode argument remains **420**, and supplied nonnegative descriptor **4** is returned unchanged. The body does not reject `x` as an invalid mode string. A hosted-library expectation cannot add that missing branch.

### C11-04R

For the separate `fread(B,1,10,7)` and `fwrite(B,1,10,7)` cases, each request is ten bytes and the supplied seven-byte progress fits it. `fread` returns **7 elements** and `fwrite` returns **7 bytes**. The numbers coincide because one element occupies one byte; their derivations and units remain distinct. A zero-count read returning zero yields zero without division and without new input. It does not establish EOF from an attempted positive-count transfer.

### C11-05R

With position H+80, a zero-size request rounds to zero, returns **H+80**, and leaves the position there. `malloc(1)` then rounds to eight, also returns **H+80**, and advances to **H+88**. The first request did not claim a positive-length slice whose reuse would require free.

Moving the whole calloc region from file offset 408 to 428 moves the position cell from **513 to 533**, target address from **`0x400201` to `0x400215`**. Its region-relative offset remains 105, and all internal RIP displacements remain unchanged. The externally visible function address moves twenty bytes too; references to it need the corresponding target coordinate. The independent heap base H need not move merely because executable code moved in this paper layout.

### C11-06R

Copying four bytes makes D hold `2A 61 2A 00`. The copied region now supplies a readable terminator at D+3. `strrchr(D,256)` compares only the low byte of 256, which is zero, and returns **D+3**. It does not search for a two-byte encoding of 256, and it does not reject the high bits. The copy itself returns D, with cursors D+4 and A+4.

### C11-07R

No late strlen body is emitted because its user definition already resolved and cleared both lists. `memcpy`'s pending call and address lists make its row demanded. The pass assigns one target, patches the four-byte relative-call field through the call walker and eight-byte absolute field through the address walker, clears both heads, and emits **nine bytes** once. Two use kinds do not require two copies of the same body.

### C11-08R

An observed star write supports the narrowly recorded claim that the identified earlier executable, in that environment and run, successfully performed that one-byte output operation. It may provide useful historical evidence when its provenance is retained. It does not by itself establish that the executable came from the pinned source, that every I/O error is handled, that allocations are checked, or that the whole current Linux bootstrap succeeds. Even same-revision execution would remain evidence for the tested path and conditions, not every possible runtime behavior.

## Choose the next attempt from the discrepancy

- If a byte and a count were exchanged, annotate units in C11-01R or C11-04R
- If an address was right numerically but belonged to the wrong process, redraw C11-05's inline cell and separate mapping, then try its moved-region case
- If a familiar library name overrode the instructions, compare C11-03R's first-byte branch or C11-07R's unresolved lists
- If all worked cases are accurate, attempt C11-08R later without the answer and explain the evidence boundary in your own words

These suggestions respond to the attempted reasoning. They do not classify ability, require a fixed study interval, or turn one successful exercise into evidence of broad transfer. You can stop with the last correct state and return directly to the next uncertain transition.
