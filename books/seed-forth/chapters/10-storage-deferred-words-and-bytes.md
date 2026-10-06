# 10. Storage, deferred words, and byte sequences

[Previous: Control flow by patching](09-control-flow-by-patching.md) · [Practice help](../practice/10-solutions.md) · [Edition coverage](../../COVERAGE.md)

Suppose a reader sees the name `main`. We want to recognize those four bytes, remember how many matches occurred, and leave room to change the recognition rule later. A stack can carry each answer, but a reusable counter, a saved name, and a replaceable operation need different arrangements.

One distinction matters immediately: **data-stack values survive a word returning**. A word can leave a result for its caller, as every arithmetic example has done. Named storage adds another way to find data later, without keeping its value or address at a particular stack position. Here, “persistent” means surviving later word calls within this process. It does not mean saving to disk or surviving a restart.

By the end, you should be able to lay out a created object, explain a deferred call before and after rebinding, preserve a borrowed token by copying it, and trace a byte comparison through both stacks. We will combine those mechanisms into a small reader-built recognizer. Its acceptance criteria are stack and memory states; no printer is required.

## Bring the contracts, then choose a stopping point

You need addresses and byte/cell access from [Chapter 2](02-addresses-and-bytes.md), balanced return-stack borrowing and shuffles from [Chapter 4](04-return-stack-and-shuffles.md), bounded comparisons from [Chapter 5](05-comparisons-and-characters.md), and the writers from [Chapter 6](06-memory-updates-and-writers.md). [Chapter 8](08-defining-words-and-phases.md) introduced headers, execution tokens, `constant`, character literals, and the 19-byte push body. [Chapter 9](09-control-flow-by-patching.md) supplies the immediate control-flow words, including `exit,`.

Check three prerequisites before adding new state:

- Does `here` give HERE's cell address or its contents?
- Does executing `' tag` return the value that `tag` would push?
- May a word return while one of its own `>r` temporaries remains parked?

The answers are: contents; no, tick returns the code address of the named word, or zero if lookup fails; and no, the temporary would obstruct its return destination. Revisit the relevant chapter if the reasons are uncertain. If the contracts are secure, the layout tables and S10-02 through S10-05 offer a shorter route.

**Evidence and model.** This is the Linux/x86-64 seed at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`. All results below are checked paper derivations, not executions. Cells are eight bytes, addresses count bytes, and multi-byte values are little-endian. Both stack tops are at the right. `U` denotes the all-ones true cell, also interpreted as signed -1.

Invented numeric addresses are paper locations, never suggested live scratch addresses. Assume enough stack space, valid storage, no address wrap, and no overlap between payload regions, live code, stacks, system cells, and the token buffer. Copy sources and destinations are disjoint. Counts are nonnegative, at most `2^63-1`, and further bounded by actual available storage. The short examples use at most 256 bytes. These assumptions are caller obligations, not checks added by this prose.

The chapter has three useful stopping points: after named storage, after deferred dispatch, and after the comparison trace. Save the indicated state instead of trying to retain every byte offset at once.

## Reserve bytes without inventing their contents

The library's allocation helper is:

```forth
: allot  here-addr @ + here-addr ! ;
```

Its data effect is `( n -- )`. With HERE containing 1000 and data stack `[99, 4]`, the stages are:

| After | Data stack | HERE contents |
|---|---|---:|
| Start | `[99, 4]` | 1000 |
| `here-addr @` | `[99, 4, 1000]` | 1000 |
| `+` | `[99, 1004]` | 1000 |
| `here-addr !` | `[99]` | 1004 |

The four payload bytes at 1000–1003 have not been written. If they previously held `90 91 92 93`, they still hold that sequence. If their prior contents were unspecified, they remain unspecified. Do not infer zero initialization from allocation, even if a particular operating-system mapping began as zero-filled memory.

“Reserve” here means advance our cursor within an already available region. `allot` does not request memory from Linux, check capacity, check ownership, or protect reserved pages. A huge count can move the cursor into unusable memory. A cell pattern interpreted as negative can move it backward through modular arithmetic. Neither is part of this chapter's nonnegative allocation contract.

After reserving bytes, later reads need explicit initialization. After allocating zero bytes, the cursor is unchanged and no fresh storage has been obtained. Keep the amount and the validity of the destination region separate: a mathematically correct cursor sum is not evidence that the region belongs to this allocation.

## Give a data area a name

`create` defines a word whose later execution pushes an address:

```forth
: create  : here [lit] 19 + push-body, [lit] 0 state ! ;
```

The input contract is `create ( "name" -- )`: the quoted name denotes input text consumed by the defining word, not a stack argument and not literal quotation marks to type. The new word has runtime effect `( -- data-address )`.

Recall Chapter 8's defining phases. When `create` itself runs, its compiled call to `:` reads the next name, builds its header, and sets STATE to one. HERE then points to the new body's first byte, its execution token. `push-body,` emits 19 bytes that push one chosen cell value and return. Here that chosen value is **the body start plus 19**, the address immediately after the code. Finally, `create` resets STATE to zero because it finished the new definition itself.

Take the paper input:

```forth
create tag [lit] 4 allot
```

Start with HERE=1000, STATE=0, LATEST holding some valid older entry `L`, and stack `[99]`. The helper words already exist; `tag` is a fresh name. Its three-byte name gives this layout:

| Byte range | Meaning | Result after both operations |
|---|---|---|
| 1000–1007 | Link field | Eight-byte value `L` |
| 1008 | Flags | 0 |
| 1009 | Name length | 3 |
| 1010–1012 | Name | Bytes for `tag` |
| 1013–1031 | Runtime code | 19-byte push body; embedded value 1032 |
| 1032–1035 | Data area | Four reserved, uninitialized bytes |
| 1036 | Next cursor position | HERE contains this address |

LATEST now contains 1000, STATE is zero, and the data stack is still `[99]`. The code's execution token is 1013. Executing `tag` pushes 1032. Executing `' tag` instead pushes 1013. No automatic fetch occurs when `tag` runs: `tag c@` would read the first data byte, but that byte must first be initialized.

In general, with header start `E` and name length `N`, the body begins at `E+10+N`, and the data starts at `E+10+N+19`. The 19 is a **code size**, not the entire dictionary-entry size. There is no alignment padding or terminator between these fields.

`create` alone reserves no payload bytes. Its data address initially equals HERE. Fill or reserve that area before defining another word; the next header would otherwise start at that same location. Later running `tag` does not reopen its data area for emission: `c,` still writes at current HERE. To replace a byte already owned by `tag`, use an explicit address with `c!`.

## A variable adds one initialized cell

The complete definition is short:

```forth
: variable  create [lit] 0 , ;
```

`variable ( "name" -- )` delegates name-reading and the push body to `create`. The primitive comma then writes an eight-byte zero at the current cursor and advances HERE by eight. The new word still pushes an address, with runtime effect `( -- cell-address )`.

For a separate paper reset, let `variable hits` begin at HERE=2000. Its four-letter name puts the body at 2014 and its cell at 2033. HERE ends at 2041. All eight bytes at 2033–2040 are zero; executing `hits @` therefore pushes zero. The unaligned cell address is consistent with this seed's byte-packed x86-64 layout.

These study inputs distinguish returning a value from storing one:

```forth
: demo-seven  [lit] 7 ;
demo-seven
[lit] 7 hits !
hits @
```

Starting with `[99]` after `hits` has been created, the fresh word `demo-seven` leaves `[99, 7]`. The store supplies a *second* seven, writes it to `hits`, and leaves the earlier `[99, 7]`. The final fetch leaves `[99, 7, 7]`. The first result did not disappear when `demo-seven` returned. Named storage gave us an additional, independent retrieval path.

Compare the shared template: `constant` pushes its supplied value; `create` pushes its following data address; `variable` does the latter and emits one zero cell there. You choose the representation from the later operation you need: use a value, access bytes, or update a cell.

**Stop/resume.** Save `tag`: header 1000, code 1013, data 1032, cursor 1036. On return, explain which address tick returns and which one a byte store needs. That distinction will reappear in deferred dispatch.

### Deeper boundary: `skip-vm-pages` is a profile-specific jump

The neighboring source helper is:

```forth
: skip-vm-pages  state [lit] 4096 + here-addr ! ;
```

It assigns HERE the address one page above STATE. In this revision, STATE is at `0x413000`, so the new cursor is `0x414000`. The intervening fixed regions include the downward-growing data stack below `0x411000`, the I/O scratch byte at `0x412000`, the token buffer at `0x412800`, and the sysvar page.

The source requires HERE still to be below `0x410000` when this helper is used. Existing code/data must have stayed clear of the actual live stack and other reserved state; the later destination must also be available and unused. Moving the cursor cannot repair an earlier collision or relocate existing data. These are stronger obligations than noticing that a proposed buffer is large.

This helper does not add 4096 to the old HERE, find a free page, grow a mapping, or reserve a sized block. Calling it again after allocating above its fixed destination can rewind HERE onto existing data. It belongs to a specific layout transition in this profile, not a general-purpose allocator to insert into our examples.

## Name an operation before choosing its implementation

Ordinary compiled calls select the execution token found when the caller is compiled. That is useful until two routines need to call one another before both exist. A deferred word provides an already-defined entry point whose selected target can be supplied later.

The library captures two primitive execution tokens and a code-size constant, then defines `defer` and `is`:

```forth
' @       constant fetch-xt
' execute constant execute-xt
[lit] 29 constant defer-code-size

: defer
  : here defer-code-size + push-imm64,
  fetch-xt call,  execute-xt call,  ret,
  [lit] 0 ,  [lit] 0 state ! ;

: is  ' defer-code-size + ! ;
```

Tick has input contract `( "name" -- xt-or-zero )`. It reads a name from the input stream and performs lookup; it does not run that word. `execute` consumes an execution token and transfers control to that code. Any additional inputs and outputs are the chosen target's contract. It does not check that the token is valid or that the stack fits the target.

`defer ( "name" -- )` makes a header followed by **29 bytes of code and an eight-byte dispatch cell**. If the code starts at `B`, the layout is:

| Offset from B | Size | Meaning |
|---|---:|---|
| 0–17 | 18 bytes | `push-imm64,` pushes `B+29`, the cell address |
| 18–22 | 5 bytes | Call `@` using `fetch-xt` |
| 23–27 | 5 bytes | Call `execute` using `execute-xt` |
| 28 | 1 byte | Return instruction |
| 29–36 | 8 bytes | Dispatch cell, initially zero |

The embedded address is fixed, while the contents fetched from it can change. The sum is `18+5+5+1=29`; unlike `create`, this word does more than push a value and return. The dispatch cell is data after the return instruction, not another instruction to fall into.

`is ( xt "name" -- )` reads the name of an **already-created deferred word**, adds 29 to its code address, and stores the supplied xt there. It neither creates the named word nor verifies its kind. A missing name gives zero from tick; an ordinary word lacks the promised dispatch-cell layout. Either violates `is`'s preconditions and can cause an invalid or destructive store. Our binding examples run in interpret mode; `is` is not an immediate binding syntax to transplant unexamined into a colon definition.

Before binding, the dispatch cell holds zero. Calling that deferred word would feed zero to `execute`, which attempts a transfer to address zero. There is no safe “do nothing” default or library error result. Stop at the invalid target contract rather than promising a particular recoverable failure.

## Follow a stable call through a changing cell

Here is a complete teaching setup, assuming fresh names:

```forth
: answer-one  [lit] 1 ;
: answer-two  [lit] 2 ;
defer answer
: indirect-answer  answer ;
: direct-answer  answer-one ;
' answer-one is answer
```

Neither caller has executed during its definition. Both can now be called. Suppose `answer`'s body is at paper address `B` and its dispatch cell at `C=B+29`. Let `X1` be the code address of `answer-one`.

When `indirect-answer` calls `answer` with data stack `[99]`, the deferred body goes through `[99, C]`, then `[99, X1]` after `@`. `execute` removes `X1` and enters `answer-one` with `[99]`; that target pushes one. Its return resumes after the deferred body's call to `execute`, then the deferred body's own return resumes its caller. The result is `[99, 1]`, with call state restored.

Now perform:

```forth
' answer-two is answer
```

The cell at `C` changes from `X1` to `X2`. The previously compiled call in `indirect-answer` still targets `B`; its bytes need no patch. A later call follows the same path through the cell and leaves two. `direct-answer` still calls `answer-one` and leaves one, because its call never consulted the dispatch cell.

This is the practical distinction between early binding and deferred dispatch. Ordinary calls retain a selected code address. Deferred callers retain the deferred entry's code address, while that entry fetches its selected target each time. Merely redefining an ordinary name does not rewrite old call sites either. Rebinding also requires compatible target contracts; replacing a no-input producer with a two-input consumer would break existing callers even though the stored xt was valid.

**Stop/resume.** Save the path “caller → deferred code → dispatch cell → target.” On return, identify which one location `is` changes and which address the old caller still uses.

## Read a token without claiming to own it

Before the next loops, give two familiar sequences their library names:

```forth
: 1+  [lit] 1 + ;
: 1-  [lit] 1 - ;
```

Their effects are `( n -- n+1 )` and `( n -- n-1 )`, with the usual cell-width wrap. Our loop bounds keep counts nonnegative and address increments away from wrap. A name like `1-` does not itself check that decrementing is appropriate.

Chapter 8 introduced `tib ( -- a )`, the token input buffer address, derived as `state [lit] 2048 -`. Call it `T` in paper traces. The seed's reader places the next token there. Tick can invoke that reader, but its result is a lookup answer, not the token length. The library obtains address and length like this:

```forth
: token
  tib [lit] 256 + tib
  begin, 2dup > while, bl over c! 1+ repeat,
  2drop  ' drop
  tib [lit] 0
  begin, 2dup + c@ bl <> while, 1+ repeat, ;
```

Its input contract is `( "tok" -- a u )`. For this use, supply a next ordinary, nonempty token accepted by the reader. It contains no separating whitespace and has at most 255 bytes. Reader comment markers retain their meaning; this is not a way to quote arbitrary text or whitespace. We make no general end-of-input contract for this wrapper.

The first loop carries `[end, p]`, initially `[T+256, T]`. `2dup >` preserves the pair and tests `end>p`. On a true test, `bl over c!` writes a blank byte, 32, at `p`; `1+` advances `p`. It writes offsets 0 through 255, then exits with `[T+256, T+256]`. `2drop` removes both pointers.

`' drop` reads the token and discards its lookup result. The text need not name a defined word. For `main`, offsets 0–3 become `109 97 105 110`; offset 4 stays 32 from the fill. The reader need not append a terminator.

The second loop carries `[T, u]`, initially `[T, 0]`. `2dup + c@` fetches the byte at `T+u` while preserving the pair. `bl <>` asks whether it is not a blank. Four nonblank bytes increment `u` to four; offset four is blank, so the loop stops at `[T, 4]`.

The 255-byte reader limit is essential. For a maximum-length accepted token, offset 255 remains the blank sentinel. The scan has no independent capacity check; it relies on that reader contract. The first loop's nearby-pointer comparison also stays within Chapter 5's valid difference bound in this profile.

**Borrowed bytes are temporary.** `token` has returned an address into shared storage, not allocated a private string. Another reader operation can overwrite it. Even returning to the outer input loop lets that loop read its next word into the same TIB. Consequently, spelling `token main bytes,` as separate outer-loop operations does not preserve `main`: reading `bytes,` can replace it before the copy starts. Put reading and consuming inside one already-compiled word, as `s,` does next.

## Copy while the borrowed bytes are valid

The copier and its reading wrapper are:

```forth
: bytes,
  begin, dup while,
    over c@ c,  1- swap 1+ swap
  repeat,
  2drop ;

: s,  token bytes, ;
```

`bytes, ( a u -- )` copies `u` bytes from `a` to HERE, advancing the cursor. Its loop tests a copy of `u`; a zero length makes no byte reads or payload writes. For positive lengths, `over c@` reads the current source byte, `c,` writes it, `1-` reduces the count, and `swap 1+ swap` advances the source address.

Start with stack `[99, T, 4]`, source `main`, and HERE=`P`, with source and four writable destination bytes disjoint. At each completed body:

| Iterations completed | Stack | Destination prefix | HERE |
|---:|---|---|---|
| 0 | `[99, T, 4]` | None written | P |
| 1 | `[99, T+1, 3]` | `109` | P+1 |
| 2 | `[99, T+2, 2]` | `109 97` | P+2 |
| 3 | `[99, T+3, 1]` | `109 97 105` | P+3 |
| 4 | `[99, T+4, 0]` | `109 97 105 110` | P+4 |

The final `2drop` leaves `[99]`. The source is unchanged. This is a forward copy, not a promised overlapping-range move. A destination inside still-unread source bytes could alter later reads; our disjoint-storage contract rules that out. There is no capacity check here either.

`s, ( "tok" -- )` performs the read and copy during one invocation, before the outer loop can read another word. In a separate paper reset with `tag` not yet defined:

```forth
create tag s, main
```

defines `tag`, then writes the four name bytes immediately after its body. The name `main` is data supplied to `s,`, not an executed dictionary word. No length or terminating byte is stored. Remember four separately. Allocating four bytes before this `s,` would leave a four-byte gap and copy after it; `allot` and emission each advance HERE.

The saved data survives later token reads because the copy lives in its own allocated dictionary region. Persistence comes from storage and nonoverwriting discipline, not from the input buffer address becoming permanent.

## Compare a bounded number of bytes

The last definition in the library is:

```forth
: bytes-eq
  begin,
    dup [lit] 0 >
  while,
    >r
    over c@ over c@ <> if,
      r> drop 2drop [lit] 0 exit,
    then,
    1+ swap 1+ swap
    r> 1-
  repeat,
  drop 2drop true ;
```

`bytes-eq ( a1 a2 u -- f )` returns `U` if the first `u` bytes match, otherwise zero. Supply two readable ranges of the stated bounded nonnegative length; our paper ranges are separate and nonoverlapping. It writes neither range. It compares a supplied prefix length, not two self-describing strings. To recognize an entire name, check lengths as well.

The loop test `dup [lit] 0 >` preserves the remaining count and tests whether it is positive. The domain matters: `>` is the signed, subtraction-based helper. Treating an arbitrary large unsigned pattern as a length is outside this contract. In our domain, a positive count takes another step and zero finishes.

For a successful match, put `main` at both paper addresses `A` and `B`, and start with `D=[99, A, B, 4]`. Let `R0` denote the complete older return stack below this invocation's return destination. At boundaries between completed helper calls:

| Point | D | R |
|---|---|---|
| Enter comparison | `[99, A, B, 4]` | `[R0, ret(bytes-eq)]` |
| First `>r` | `[99, A, B]` | `[R0, ret(bytes-eq), 4]` |
| First `over c@` | `[99, A, B, 109]` | Same |
| Second `over c@` | `[99, A, B, 109, 109]` | Same |
| `<>`, then branch test consumes flag | `[99, A, B]` | Same |
| `1+ swap 1+ swap` | `[99, A+1, B+1]` | Same |
| `r> 1-` | `[99, A+1, B+1, 3]` | `[R0, ret(bytes-eq)]` |

Why does the second `over` copy `B` rather than `A`? The first fetched byte sits on top, so `B` is now second-from-top. The byte inequality test consumes both fetched values, leaving the two addresses ready to advance. Balanced calls such as `over` manage their own return-stack temporaries above this invocation's parked count.

Subsequent equal passes leave `[99, A+2, B+2, 2]`, then `[99, A+3, B+3, 1]`, then `[99, A+4, B+4, 0]`. The next test is false. `drop 2drop` removes the count and both addresses, and `true` leaves `[99, U]`. The final return consumes `ret(bytes-eq)`, restoring `R0`.

### An early mismatch must clean up both stacks

Reset the left bytes to `main` and the right bytes to `mail`: `109 97 105 108`. The first three passes agree. On the fourth pass, the stack before `>r` is `[99, A+3, B+3, 1]`. This time `110 <> 108` produces true and enters the mismatch arm:

| After | D | R |
|---|---|---|
| Branch enters arm | `[99, A+3, B+3]` | `[R0, ret(bytes-eq), 1]` |
| `r>` | `[99, A+3, B+3, 1]` | `[R0, ret(bytes-eq)]` |
| `drop 2drop` | `[99]` | `[R0, ret(bytes-eq)]` |
| `[lit] 0` | `[99, 0]` | `[R0, ret(bytes-eq)]` |
| Compiled return from `exit,` | `[99, 0]` | `R0` |

This mismatch occurs late, but it follows the early-return path: it never executes the pointer advance or loop back edge afterward. With `mail` versus `sail`, the first bytes already differ and the same cleanup occurs with count four parked. No later bytes need to be read.

`exit,` ran during compilation to emit a return instruction. It is that instruction which runs now. Removing `r> drop` would leave the remaining count where the return destination must be. A zero data result alone would not make that control state valid. Replacing it with `r@ drop` would also fail: copying and discarding a count does not remove the parked original.

For **zero length**, the first loop test is false. No `c@` occurs and no count is parked. From `[99, A, B, 0]`, the cleanup leaves `[99]`, then `true` gives `[99, U]`. Two empty prefixes agree. This does not establish that the surrounding storage holds equal full names, or invite invalid addresses into other operations.

The invariant is now visible: after `k` successful passes, the first `k` pairs agree, both pointers have advanced by `k`, the remaining count is `u-k`, and no borrowed count remains at the loop head. A mismatch establishes inequality and restores both stacks before returning. Exhausting the bounded count establishes equality of exactly that many bytes.

**Stop/resume.** Save `[99, A+3, B+3, 1]` for `main` versus `mail`. On returning, derive the mismatch cleanup without looking at its table. Then change the last right byte to 110 and derive the successful ending instead.

## Build a small recognizer from the pieces

Our teaching program recognizes the entire token `main`, counts successful recognitions, and routes recognition through a deferred word. Before reading the completed version, decide which component owns each fact: the four saved bytes, their length, the counter cell, and the selected classifier's xt.

**Complete paper starting state.** The pinned seed and all `010-lib.fth` words are already available. STATE is zero, logical data stack is `[99]`, and ordinary caller return state is intact. All `demo-` names below are fresh. HERE points into enough unused writable/executable dictionary space for these small definitions and their data, disjoint from TIB, system cells, stacks, and existing objects; all emitted calls meet Chapter 8's reach assumption. The supplied input contains exactly the shown ordinary tokens and sufficient delimiters. No builds or execution are part of this exercise.

```forth
create demo-key s, main
[lit] 4 constant demo-key-size
variable demo-hits
defer demo-classify

: demo-main?
  dup demo-key-size <> if,
    2drop [lit] 0 exit,
  then,
  demo-key swap bytes-eq ;

: demo-next
  token demo-classify
  dup if, [lit] 1 demo-hits +! then, ;

' demo-main? is demo-classify
```

`demo-main? ( a u -- f )` first compares the supplied length with four. Its unequal-length arm consumes both inputs and returns zero without comparing any bytes. On the other path, `[a, 4]` becomes `[a, 4, K]` after `demo-key`, then `[a, K, 4]` after `swap`, where `K` is the saved key's data address. That is precisely the comparator's contract.

`demo-next ( "tok" -- f )` reads and classifies within one invocation. No intervening reader call overwrites the TIB. Its `dup` keeps the result while `if,`'s runtime test consumes another copy. On true, `+!` increments the initialized counter; on false, the counter is untouched. Both paths leave one flag. The deferred target is bound before any call to `demo-next`.

After the setup, stack `[99]` remains, the key bytes are `109 97 105 110`, `demo-hits` contains zero, and the dispatch cell holds the xt of `demo-main?`. Now derive this input in order:

```forth
demo-next main
demo-next mail
demo-next mainly
```

The acceptance states after each completed call are `[99, U]` with counter one; `[99, U, 0]` with counter one; and `[99, U, 0, 0]` with counter one. Saved key bytes remain unchanged. Runtime classification advances no HERE cursor and leaves no parked return-stack temporary. `mainly` is rejected by length, even though its first four bytes match. These are predictions supported by the traces, not a report that the program ran.

## Practice

Use separate paper resets. [Hints, checked solutions, and changed cases](../practice/10-solutions.md) are available whenever useful.

### S10-01 — Account for every region

Start `create tag [lit] 4 allot` at HERE=1000 as above. Give header, code, data, final HERE, LATEST, and STATE. What do `tag` and `' tag` separately push? Suppose all four reserved bytes previously contained 90. Trace `char m tag c!` from `[99]`. Which bytes are now initialized by this program, and is `tag @` a valid way to read just those four bytes? Compare the data guarantee with a newly created `variable hits`.

### S10-02 — Rebind without recompiling

Use `answer-one`, `answer-two`, `answer`, and the two callers above. Give both callers' results before and after `' answer-two is answer`, resetting D to `[99]` for each call. If `answer`'s code begins at 3000, identify exactly which cell `is` updates. Diagnose calling `answer` before its first binding, and attempting `' answer-one is answer-two`. Which precondition fails in each case?

### S10-03 — Preserve a counted token

Construct `demo-counted, ( "tok" -- )`, which stores a one-byte length followed by the token bytes, using `token`, `dup`, `c,`, and `bytes,`. All accepted tokens have lengths 1–255. For input `main`, initial HERE=P, and D=`[99]`, give the five emitted bytes, cursor, and final stack. Explain why this must copy before another input read. How does the format differ from `s,`?

### S10-04 — Find the unsafe return

For left `main`, right `mail`, and count four, trace the mismatch arm with both stacks. A changed version uses `r@ drop 2drop [lit] 0 exit,`. Locate its failure despite the apparently correct result flag. Then derive the zero-length case and the equal-prefix count-three case. State exactly what each true answer establishes.

### S10-05 — Change the policy, keep the caller

Starting from the completed recognizer, independently define `demo-not-main? ( a u -- f )`: accept exactly those supplied tokens that `demo-main?` rejects. Use that existing predicate and one more word. Bind the new policy to `demo-classify`, reset `demo-hits` to zero, and derive `demo-next main`, `demo-next mail`, and `demo-next mainly`, starting D at `[99]`. Give final stack, counter, unchanged data, and the call-site argument. Do not redefine `demo-next`.

## Return with a question, then continue

If an answer differs, find the first violated contract: confusing code and data addresses, assuming allocation initialized bytes, keeping TIB contents across a read, or returning with a parked count. Use that exercise's hint and retry its changed case. You can finish the storage portion independently before adding the reader and comparator.

After other material, revisit S10-03 and S10-05 with answers closed. Explain both why the bytes survive and why the old caller follows the new policy. Those mechanisms complete this library-level arc; they do not establish that the full seed machine code or later compiler is correct. The machine-code audit and remaining work are listed in [edition coverage](../../COVERAGE.md).

## Source and evidence

The inspected definitions are [`allot`, `skip-vm-pages`, `create`, and `variable`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L374-L402), [`defer` and `is`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L404-L429), [`token`, `bytes,`, and `s,`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L431-L451), and [`bytes-eq`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L453-L469). Supporting library mechanisms are [`1+` and `1-`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L42-L45), the [push-body helpers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L192-L225), and [`tib` and character handling](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L239-L264).

The seed evidence is [`execute_code` and bounded `read_word`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L387-L451), [`tick_code` and `colon_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L506-L536), and the [outer input loop](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L664-L689). This chapter replaces the learning path of [older Chapter 12](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/12-defining-words-and-bytes-eq.md), correcting its statement about data values disappearing on return and avoiding its implied initialization guarantee for `allot`. No build, Forth execution, timing result, or real-reader learning outcome is claimed. The [edition record](../../EDITION.md) states the shared boundary.

Begin the byte-level pass with [Executable and entry](11-executable-and-entry.md).
