# C02 practice help: buffers, arenas, and failure ownership

[Back to the chapter](../chapters/02-buffers-arenas-and-failure.md)

These are checked paper solutions under the chapter's bounded-count, valid-storage model. No seed, compiler, or test was executed. Take the hint that helps; the full solutions remain available. If your answer differs, compare the first divergent state, then try the changed case without copying the original trace.

## C2-01 — Distinguish capacity from accepted length

**Hint 1.** A new request starts after the prefix already read. Keep request size separate from returned count.

**Hint 2.** The capacity test is on accumulated count plus one. A nonpositive result never enters that test's loop body.

**Checked solution.** With base B and capacity 8:

| Request | Address | Requested bytes | Returned count | Accumulated count | Capacity test |
|---:|---|---:|---:|---:|---|
| 1 | B | 8 | 3 | 3 | `4 <= 8`, passes |
| 2 | B+3 | 5 | 4 | 7 | `8 <= 8`, passes |
| 3 | B+7 | 1 | 0 | 7 | No positive-result body |

The function returns 7. Together with the caller's known B, that identifies the meaningful span `[B, B+7)`. Offset 7 remains outside the accepted payload; the routine does not write a zero terminator there.

Changing the second result to 5 makes the accumulated count 8. The test becomes `9 <= 8`, which fails through the supplied code. Those eight bytes may already have been placed in the buffer by the read, but no successful length is returned. There is no third read to discover whether the file ends exactly at capacity.

Changing the second result to a negative error takes the loop's exit path. The negative count is dropped and the accumulated count 3 is returned. There is no read-error diagnostic or retry here. With `cc-load-stdin`, only the capacity-failure case above reaches code 20; source initialization before the load makes its reported line 1.

**Wrong path to diagnose.** Returning 8 because “eight bytes fit” confuses writable capacity with this reader's stricter acceptance policy. Returning a negative count to the caller invents an error-propagation path that the final `drop cc-ra-n @` does not implement.

**Changed case.** Capacity is 1. A first result of zero returns length zero. A first result of one reaches proposed count `1+1=2`, exceeding capacity, and exits. The largest accepted payload is zero bytes, although the buffer contains one writable byte. Derive this before changing any implementation assumptions.

## C2-02 — Complete an allocation trace

**Hint 1.** Round each request separately. The arena's stored pointer is an address, while the checked used count is `new-pointer−start`.

**Hint 2.** Request nine consumes sixteen reserved bytes. A zero request does not move the pointer or create a nonempty fresh span.

**Checked solution.** Start=1000 and limit=24 give this sequence:

| Request | Rounded size | Old pointer | Proposed pointer | Proposed used count | Result |
|---:|---:|---:|---:|---:|---|
| 1 | 8 | 1000 | 1008 | 8 | Return 1000; pointer=1008 |
| 9 | 16 | 1008 | 1024 | 24 | Return 1008; pointer=1024 |
| 0 | 0 | 1024 | 1024 | 24 | Return 1024; pointer=1024 |
| 1 | 8 | 1024 | 1032 | 32 | Exit with code 10 before pointer store |

The final operation has no successful return or usable post-exit allocator state. Immediately before its failure, the stored pointer remains 1024 because the check precedes the update. The first two reserved regions do not overlap. Their payload and padding are uninitialized until callers write them.

With start=pointer=1003, the rounded sizes and used counts stay the same. Successful addresses are 1003, 1011, and 1027; final stored pointer before the failing check is 1027. All these addresses have residue three modulo eight. Size rounding preserves that residue rather than changing it to zero.

**Wrong path to diagnose.** Rounding the pointer 1003 up to 1008 silently substitutes a different algorithm. Source rounds `n`, then adds the result to the old pointer. A zero-length allocation at the end also does not authorize a byte store at that address.

**Changed case.** Return to start=1000 but set capacity=25. The same last one-byte request still fails: rounded use would be 32, not 25. One unused byte cannot satisfy an eight-byte rounded reservation. This is internal padding's capacity cost, not a disagreement in byte-address arithmetic.

## C2-03 — Separate append, patch, and delivery

**Hint 1.** Track position after each emitted byte. For 1297, divide by 256 and retain the low byte each time.

**Hint 2.** The patch changes four existing bytes but never updates the position. Then examine what the file writer does with its syscall result.

**Checked solution.** The two single-byte emissions leave position 2 and prefix `65 66`. Four-byte emission adds `17 5 0 0`, because 1297 has quotient 5 and remainder 17 on division by 256. The resulting span has all six available bytes:

| Stage | Decimal byte sequence at offsets 0–5 | Position |
|---|---|---:|
| After emission | `65 66 17 5 0 0` | 6 |
| After patch at offset 0 | `120 86 52 18 0 0` | 6 |

The patch value is hexadecimal 12345678, whose least-significant byte is hexadecimal 78, decimal 120. Low-to-high order gives 120, 86, 52, 18. Its four writes fit inside the already emitted span. An extra append checks proposed length 7 against capacity 6 and exits with code 21 before writing that byte.

For the file-writing question, consider the completed six-byte output before attempting that fatal append. If `write` returns four, `drop` discards four, then `r> close drop` retrieves and closes the descriptor and discards the close result. It does not advance a file-write cursor or request the remaining two bytes. The chapter establishes a request for six bytes, not complete delivery in this changed case.

**Wrong path to diagnose.** Position ten after patching would treat replacement as append. Claiming that the single `write` eventually retries confuses the compiler's input loop with its different output implementation.

**Changed case.** Start fresh with capacity 5, emit 65 and 66, then attempt the same four-byte value. Its first three bytes, 17, 5, and 0, fit at offsets 2–4. The fourth attempts proposed position 6 and exits with code 21. The emitter checks byte by byte; no whole-four-byte reservation or rollback was promised. Immediately before failure the stored position is 5.

## C2-04 — Track a borrowed source and its location

**Hint 1.** Peek does not change state. Next always increases position, even when peek produces its EOF result.

**Hint 2.** Only a returned newline increments line. The 64-byte state block contains pointer values, not all the bytes reached through those pointers.

**Checked solution.** Starting with pos=0 and line=1:

| Call | Result | Position | Line |
|---|---:|---:|---:|
| Next | 65 | 1 | 1 |
| Next | 10 | 2 | 2 |
| Next | 66 | 3 | 2 |
| Peek | 0 | 3 | 2 |
| Next | 0 | 4 | 2 |

Source length remains 3. These operations change only the reader's position/line cells within the block; they do not change token fields or the source bytes. At the final state, supplying code 21 to `cc-die` attempts this text followed by newline:

```text
cc: line 2: error 21
```

That is a predicted formatting result under successful diagnostic writes, not an observed message. The code is supplied to process exit even though diagnostic write results are ignored. The number 2 refers to the flattened source's reader line, not necessarily the corresponding original file's line.

Copying the state block preserves eight cell values, including any current token address and length. It neither copies the source bytes nor creates a mapping back to original include locations. Restoring those cells assumes their referenced storage remains meaningful. It also does not restore arena usage or output length.

**Wrong path to diagnose.** Ending at position 3 assumes an EOF guard in `cc-next-char`; the actual guard is inside peek and protects its byte fetch only. Naming an include file invents location metadata absent from the formatter's inputs.

**Changed case.** Replace the source span with one byte whose value is zero, length=1, pos=0, line=1. Peek returns zero while `cc-eof?` is false. After one next call, position=1, line=1, and EOF is true. The same byte result arises in two different length states; completion requires the state predicate.

## C2-05 — Keep a new workspace's state honest

**Hint 1.** Separate selected addresses/limits, payload bytes, and cursor cells into three lists. Inspect which list the selector writes.

**Hint 2.** Only a zero cached direct base triggers mapping. Name lookup begins at the last live index, not the first.

**Checked solution.** Assume the initially zero cache receives a successful first mapping at M. Both selections establish:

| Region | Selected address | Limit in bytes |
|---|---|---:|
| Raw input | M | 3,145,728 |
| Expanded source | M+3,145,728 | 7,340,032 |
| Output | M+10,485,760 | 4,194,304 |

The sum is 14,680,064 bytes, already a multiple of 4096. The first selection maps once and caches M; the second maps zero additional times. Input length remains 100 and output position remains 6 because neither selector changes them. Those counts do not establish that old default payload bytes were copied into the new regions; no copy occurred.

For a fresh source, select first, then use the ordinary loading/initialization sequence. `cc-load-stdin` calls `cc-src-init` to set source length=0, position=0, and line=1; it reads the selected raw region and replaces `cc-in-len` with the returned count. `cc-out-init` sets output position=0 before emission. Later stages have their own initialization contracts; these two calls do not claim to reset every compiler table or token cell.

The three-entry name lookup starts at `count−1=2`. Entry 2 has length three and bytes equal to the sought `row`, so `bytes-eq` succeeds and the early return leaves index 2. The older entry 0 is never reached. This behavior requires the address/length entries and their referenced bytes to remain valid; the table stores spans, not private copies made by the lookup.

**Wrong path to diagnose.** Resetting lengths as part of workspace selection adds behavior absent from both selectors. Searching entries upward changes newest-wins lookup to oldest-wins lookup, even though both might find matching text.

**Changed case.** Select default storage again, then direct storage a third time, without any intervening writes. The default pairs are restored during the middle selection; the final selection uses the same cached M and makes no new mapping. Neither transition initializes lengths or copies data. Separately search for `rows`: index 2 fails on length, index 1 succeeds after byte comparison. With count zero, the initial index is -1 and no array entry is read.

## Choose the next check from your attempt

If counts and addresses became mixed, redo one row with units beside every value. If states were right but the guarantees were too strong, explain one ignored I/O result and one unchecked patch boundary. If both were secure, return later to a changed case without its solution visible. A checked immediate trace supports that particular reasoning; it is not evidence that the implementation ran or that the mechanism will be retained without another attempt.
