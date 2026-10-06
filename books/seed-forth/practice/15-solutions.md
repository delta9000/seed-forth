# Dictionary headers and token input: hints and solutions

Return to [Chapter 15](../chapters/15-dictionary-and-token-input.md).
These are checked manual derivations for the pinned Linux/x86-64 seed, not
observed executions. Instruction offsets are hexadecimal. Logical stack top
is at the right, cells are eight bytes, and addresses satisfy the chapter's
memory assumptions. Token-input traces assume successful one-byte reads or
stable EOF unless a changed case explicitly tests that boundary.

Try a hint before reading the solution when that helps. Then close the
solution and attempt the changed case. Notice whether you can predict the
result and explain the deciding instruction without following the worked
answer. No exercise requires running or modifying the seed.

## S15-01 — Rebuild identity

**Hint 1.** The link field is a pointer to a header, not to code. Lay down
its eight little-endian bytes before the two one-byte fields.

**Hint 2.** `0branch` has seven name bytes. Start its code after `8+1+1+7`
bytes, and follow links by reading a whole eight-byte value at each entry.

**Worked solution.** The initial `0branch` header starts at file offset
`0617`, virtual address `0x400617`. Its previous-link value is `0x400601`,
its flag byte is zero, and its length byte is seven. All seventeen bytes are:

```text
file range [0617,061F): 01 06 40 00 00 00 00 00  link to branch
file offset  061F:       00                       flags
file offset  0620:       07                       length
file range [0621,0628): 30 62 72 61 6E 63 68     name "0branch"
```

The code offset is `0617+0x11=0628`, giving xt `0x400628`. This is not
`0x400617`, the header start, or `0x400621`, the name start.

Following the first link reaches `branch` at `0x400601`. Following its link
reaches `[lit]` at `0x4005B2`. The first two links therefore visit `branch`
and `[lit]`; the starting entry itself is `0branch`. `[lit]` has immediate
flag one, but following links does not consult that flag. Continuing through
the full initial table eventually reaches `dup`, whose link value is zero.

A newly defined `dup` changes a future name search: the newest matching entry
wins. A native CALL already targeting `0x4000C7` does not perform another
name lookup. Its encoded displacement remains unchanged, so it reaches the
old primitive. A retained xt equal to `0x4000C7` also still identifies that
code. This assumes neither old body nor caller has been separately overwritten.

**Wrong path to diagnose.** Adding only seven to the header address forgot
the ten fixed bytes. Writing `40 06 01` for the link mixed up little-endian
byte weights. Claiming that the old primitive can never run again confused
search order with control transfer to an address.

**Changed case.** A completed new `dup` header is at `0x401020`, with link
`0x400617`, flags zero, and the usual three-byte name. Reconstruct it and
predict future lookup before checking:

```text
17 06 40 00 00 00 00 00 00 03 64 75 70
```

The new xt is `0x40102D`. Once LATEST points at `0x401020`, future lookup of
`dup` returns that xt and saves header `0x401020` in LAST_FOUND. The old
compiled CALL still reaches `0x4000C7`. The changed case adds a runtime
header; it does not alter the 32-entry initial ledger.

## S15-02 — Follow a partial match

**Hint 1.** At an equal-length candidate, distinguish RCX, which stays at
the header, from R8 and R9, which move through the two names.

**Hint 2.** The unequal byte takes the branch at `0337` before either INC
or the DEC. Only the hit block stores LAST_FOUND.

**Worked solution.** At entry, `rdi=4`, `rbp=P`, `[P]=T`, `[P+8]=99`.
The opening load and ADD set `rsi=T`, `rbp=P+8`; RDI stays four. The newest
entries fail the length test until `here` at header `0x400359` is reached.
Its name begins at `0x400363`.

| Comparison stage | R8 | R9 | RDX | Bytes and next action |
|---|---|---|---:|---|
| Before first pair | `0x400363` | T | 4 | `68` = `68`: advance twice, decrement count |
| Before second pair | `0x400364` | T+1 | 3 | `65` = `65`: advance twice, decrement count |
| Before third pair | `0x400365` | T+2 | 2 | `72` = `72`: advance twice, decrement count |
| Before fourth pair | `0x400366` | T+3 | 1 | Candidate `65` differs from token `64` |
| Branch at `0337` | `0x400366` | T+3 | 1 | Jump to link load without advancing those values |

The link load puts `0x4002F5`, the `find` header, into RCX. That candidate
also has length four, so R8, R9, and RDX are freshly initialized; the token
comparison restarts at T, not T+3. Its first `f` fails against `h`. Later
four-byte names include `emit`, `nand`, `swap`, and `drop`; none matches.
After `dup`'s link yields zero, the loop test reaches the miss block.

The miss return sets RDI zero and leaves RBP at `P+8`, giving `[99,0]`.
LAST_FOUND remains `0x400359`, the stipulated preceding hit. It has not been
updated to the last candidate or cleared. RBX, if it held four from
read_word, still holds four; find has not modified it.

The normal REPL tests RDI after the call to find. Its `jnz .found` is not
taken for zero, so it reports the token, restores the previous data top,
and reads again. LAST_FOUND is loaded only inside `.found`. This is the
specific control-flow reason no stale header flags influence this miss.
After report_token clobbers RDI to one, the cleanup loads 99 from `[P+8]`
and advances RBP to `P+16`.

**Wrong path to diagnose.** Advancing the comparison pointers after the
fourth pair ignored the taken branch. Returning `0x400359` confused the
stored header with an xt. Returning the previous xt on failure invented a
cache behavior that the XOR at `0355` explicitly prevents.

**Changed case.** Replace the token with `her`, length three. What happens
at the `here` candidate? Its name length four differs before R8 and R9 are
initialized for this candidate; no name bytes are compared there. The
initial table contains no `her`, so the final result is again zero and
LAST_FOUND stays unchanged. A prefix equal to the first three bytes of
`here` is insufficient because the lengths must match first.

## S15-03 — Separate cell, cursor, and target

**Hint 1.** Write HERE's cell address `0x413010` on one line and its current
contents `0x401000` on another. Comma writes through the contents, then
updates the cell.

**Hint 2.** Execute must save the xt before replacing RDI with the operand
under it. JMP uses the existing return destination rather than pushing one.

**Worked solution.** For comma, take `rdi=0x1234`, `rbp=P`, `[P]=99`:

| Group | Relevant result |
|---|---|
| Load cursor at `0383` | `rax=0x401000` |
| Store at `038B` | Memory `0x401000..0x401007` becomes `34 12 00 00 00 00 00 00` |
| Increment/update in `[038E,039A)` | `rax=0x401008`; `[0x413010]=0x401008` |
| Pop/return in `[039A,03A3)` | `rdi=99`, `rbp=P+8`; stack `[99]` |

Now here subtracts eight from RBP, stores 99 at P, and fetches the new
contents of HERE. It returns `[99,0x401008]`, with `rdi=0x401008`, `rbp=P`.
The reused data-stack slot does not undo the separate dictionary store.

In a separate reset from `[99]`, latest pushes `0x413008`, the address of
LATEST's cell. A following fetch replaces it with the initial header value
`0x400617`, giving `[99,0x400617]`. Latest alone has not searched a name or
returned `0branch`'s xt, which would be `0x400628`. Likewise here already
fetches its system cell; adding `@` reads a cell at the emission cursor.

For the separate execute trace, let `rdi=0x400254`, `rbp=Q`, `[Q]=65`,
`[Q+8]=99`, and `[rsp]=K`. Just before JMP:

```text
rax = 0x400254       saved emit xt
rdi = 65            emit's input, restored from [Q]
rbp = Q+8           [rbp] is now the older 99
rsp unchanged       [rsp] remains K
```

The target sees `[99,65]`. Its eventual RET returns to K because execute
added no new return address. Emit's own contract consumes 65 after its write
attempt, leaving 99. A JMP preserves that return ownership; replacing it
with CALL without providing further return handling would change it.

**Wrong path to diagnose.** Storing `0x1234` at `0x413010` would replace
HERE with the operand rather than emit the operand at HERE. Jumping before
restoring RDI would make emit see the low byte of its own xt instead of 65.

**Changed case.** Suppose HERE is valid but unaligned at `0x401003`, and the
input value is `U=2^64-1`. Comma writes eight `FF` bytes at
`0x401003..0x40100A`, then stores `0x40100B` in HERE. It does not round the
cursor to a multiple of eight. This checks the byte-packed layout, not a
promise that arbitrary unaligned destinations or overlaps are safe.

For a second transfer check, execute `dup-xt` from `[99,dup-xt]`. Execute
first exposes `[99]`; the target then duplicates 99, yielding `[99,99]`.
Execute's final stack effect depends on the selected target beyond consuming
the xt.

## S15-04 — Preserve two input results

**Hint 1.** Vertical tab `0B` is not among `20`, `09`, `0A`, and `0D`.
The key push is temporary only because read_char explicitly removes it.

**Hint 2.** Comment recognition happens after token completion and requires
length one. For a line comment, the delimiter already in DL is tested first.

**Worked solution.** With old `rdi=99`, `rbp=P`, key returns the successful
input byte `0x0B` as a new stack item:

```text
After key:          rdi=0x0B, rbp=P-8, [P-8]=99
After copying RDI:  rdx=0x0B, rdi=0x0B, rbp=P-8
After load and ADD: rdx=0x0B, rdi=99, rbp=P
```

The restored stack is `[99]`. All four character comparisons are unequal.
The final compare against carriage return leaves ZF=0, and RET preserves
it. The helper has therefore returned two results without a net data-stack
change: RDX is `0x0B`, and ZF is zero. It is not an EOF indication because
EDX is nonzero. If read_word encounters it outside a comment, it stores it
as an ordinary token byte.

The first returned ordinary tokens are:

| Input | First ordinary token | Why |
|---|---|---|
| `( note ) dup` | `dup`, length 3 | The one-byte `(` marker ends at space; character scanning consumes through `)` and restarts |
| `() dup` | `()`, length 2 | Length is not one, so comment-byte tests are bypassed |
| Backslash, line feed, `dup` | `dup`, length 3 | Backslash is a one-byte marker and its already-read delimiter is line feed; restart occurs before consuming `d` |

With initial stack `[99]` and `T=0x412800`, the first and third return
`[99,T,3]`; the second returns `[99,T,2]`. These are token-reader results,
not promises that subsequent lookup succeeds. In the initial dictionary,
`()` is absent and would be a normal lookup miss.

**Wrong path to diagnose.** Treating `()` as an empty comment incorrectly
recognized `(` before knowing the token's length. Reading another byte
before checking the line-comment delimiter could swallow the next line's
first byte. Treating vertical tab as whitespace imported a larger character
class than the four explicit comparisons implement.

**Changed case.** Replace the line-feed delimiter after the backslash with
a carriage return, then supply `dup`, line feed, `here`. The carriage return
ends the one-byte marker token but does not end the line comment. Its loop
therefore consumes `dup` through the line feed. The first returned ordinary
token is `here`, length four. Two routines can classify the same byte
differently because “token whitespace” and “end of line comment” are separate
conditions here.

If EOF is reached inside `( note`, the comment loop restarts read_word;
with stable EOF the additional read returns zero and the final pair is
`[T,0]`, not an unterminated-comment diagnostic.

## S15-05 — Diagnose a boundary promise

**Hint 1.** Read the store, increment, and BH test in their actual order.
Count both the retained token bytes and the two report suffix bytes.

**Hint 2.** There is no terminator store in read_word and no return in
fatal_token. Follow the fatal branch rather than assuming the normal REPL
miss path remains reachable.

**Worked solution.** The claim is wrong at each boundary:

- The accepted maximum is 255, but the reader does not truncate and return
- With RBX=255, it stores the 256th byte at `T+255`, increments to 256,
  observes BH=1, and branches to fatal_token before reading another byte
- There is no NUL terminator promise; the normal return path supplies an
  explicit length, and this overlong path does not return a pair at all
- Fatal reporting does not call find or reach an ordinary lookup-miss cleanup
- Fatal_token attempts a report and exits with status two; it supplies no
  rollback of prior dictionary/compiler state

Report_token stores `3F 0A` at `T+256` and `T+257`, so the intended output
span is `[T,T+258)`. It sets EDX=258, ESI=T, EAX=1, and EDI=1, requesting
`write(1,T,258)`. Thus the intended message is the first 256 token bytes,
question mark, and line feed. A short/error write is not checked or retried.
The following fatal instructions set EAX=60 and EDI=2 and issue raw exit.
Under the chapter's ordinary single-thread contract, the seed terminates
with status two even if the report write failed.

For a normal short token, the returned address still names the shared
producer-owned TIB. Another read can overwrite it, and reporting appends
into it. A durable copy requires copying the exact `u` bytes elsewhere
before such reuse. Merely retaining `[T,u]` does not retain those byte values.

**Wrong path to diagnose.** Claiming only 255 bytes were stored missed that
the limit is tested after INC. Counting 257 output bytes omitted one suffix
byte. Treating report_token as stack-transparent ignored its `mov edi,1`;
its normal caller must explicitly discard the expendable current item and
restore the cached top.

**Changed case.** Supply exactly 255 non-whitespace, nonzero bytes followed
by stable EOF. The 255th store leaves BH=0; the next read returns zero,
which completes the ordinary token. Its length is not one, so comment
classification is bypassed. The helper returns `[T,255]`, with RBX=255 and
no appended terminator. A later normal REPL miss would attempt a 257-byte
report, drop the current result, then read EOF and take its normal exit-zero
path; this differs from the fatal overlength path. Prior compile-mode writes
would still not be rolled back.

Now replace the next unread byte of an otherwise nonempty stream with NUL
before any token. Key returns zero, and read_word returns `[T,0]`; the normal
REPL treats it as EOF. That does not prove the stream has no later bytes.
For a negative read, even that reasoning is unavailable: key may load stale
scratch instead, and this reader has no independent error result.

## A short return check

Without rereading the solutions, explain these three distinctions:

1. A header address, its name address, and its xt
2. A borrowed token pair and a durable copy of token bytes
3. A successful lookup's LAST_FOUND update and a miss's return value

If one answer is uncertain, return to the corresponding trace rather than
repeating the entire chapter. Then try one changed case with the answer
hidden. These checks can guide another attempt; they are not evidence that
an unattempted case or later retention has already been mastered.
