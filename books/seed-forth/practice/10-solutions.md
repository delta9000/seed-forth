# Storage, deferred words, and bytes: hints and solutions

Return to [Chapter 10](../chapters/10-storage-deferred-words-and-bytes.md). These are checked paper derivations under the pinned Linux/x86-64 source contracts, not executed observations. Data and return stack tops are at the right; `U` means the all-ones true cell. Counts are bounded and nonnegative; all specified storage is valid and disjoint. Invented addresses belong only to the paper model.

Start with the first hint when you want an orientation, the second for a specific transition, or the solution whenever useful. After feedback, close it before trying the changed case. Preserve older data items and restore caller return state in every successful word.

## S10-01 — Account for every region

**Hint 1.** Split the dictionary entry into header, code, and data. `create`'s 19 is the code size, not the header-plus-code size.

**Hint 2.** The three-byte name puts the code at `1000+10+3`. Add 19 for the address the new word pushes, then four for the final cursor. Tick returns the first of those two addresses.

**Worked solution.** The header occupies 1000–1012: the older LATEST value `L` at 1000–1007, flags zero at 1008, length three at 1009, and the name bytes at 1010–1012. The code occupies 1013–1031. Its embedded immediate is 1032, the data start. Four-byte `allot` reserves 1032–1035, leaving HERE=1036, LATEST=1000, and STATE=0. The original data stack `[99]` is unchanged.

Executing `tag` from `[99]` leaves `[99, 1032]`. Separately, `' tag` leaves `[99, 1013]`. The first is a data address; the second is an execution token. They refer to different parts of the same entry.

For the store, begin again at `[99]`, with bytes 1032–1035 all containing 90:

| Operation | D | Bytes at 1032–1035 |
|---|---|---|
| Start | `[99]` | `90 90 90 90` |
| `char m` | `[99, 109]` | `90 90 90 90` |
| `tag` | `[99, 109, 1032]` | `90 90 90 90` |
| `c!` | `[99]` | `109 90 90 90` |

`char` takes the first byte of its following token, so the `m` need not be a known word. This program has explicitly initialized only the first payload byte. The other three retain their stipulated prior values; `allot` did not write them. The store does not advance HERE, which remains 1036.

`tag @` reads eight bytes, not four. Four bytes alone do not satisfy that access's storage contract. Stop rather than inventing the neighboring bytes. A new `variable hits`, in contrast, emits eight zero bytes as its own initialized payload. `hits @` can fetch that cell under the valid-storage assumptions.

**Wrong path to diagnose.** Adding four to the body start would give 1017, inside the emitted code. The cursor must first pass all 19 code bytes. Similarly, a plausible-looking final cursor does not establish initialization; inspect which operation actually wrote each byte.

**Changed case.** Use a fresh four-letter name `name`, still beginning at 1000, then reserve four bytes. Derive before checking: header 1000–1013, code 1014–1032, data 1033–1036, final HERE=1037. The one extra name byte moves code and data together. Their separation remains 19 bytes. `allot` still leaves payload contents unchanged.

## S10-02 — Rebind without recompiling

**Hint 1.** Label the target of each compiled call. Only the caller through `answer` consults a dispatch cell.

**Hint 2.** `is` first finds `answer`'s code address, then adds 29. Its `!` writes eight bytes at that result; it does not change the caller's call instruction.

**Worked solution.** Each call below independently starts with `[99]`:

| Dispatch-cell contents | `indirect-answer` result | `direct-answer` result |
|---|---|---|
| xt of `answer-one` | `[99, 1]` | `[99, 1]` |
| xt of `answer-two` | `[99, 2]` | `[99, 1]` |

If `answer` starts at 3000, its code occupies 3000–3028 and the dispatch cell occupies 3029–3036. Binding stores the chosen target's xt at 3029. The deferred body's immediate still contains 3029; its fetch finds a new value there. The compiled call inside `indirect-answer` still targets code address 3000. The direct caller still targets `answer-one`'s code.

Before the first binding, the cell is zero. The deferred body pushes 3029, fetches zero, then supplies zero to `execute`. That violates the valid-execution-token precondition. It is not a harmless empty action, and the contract supplies no recovered stack or library error flag.

The proposed `' answer-one is answer-two` supplies a valid target xt but names the wrong kind of destination. `answer-two` was built by `: ... ;`, not `defer`; adding 29 to its code address does not establish a dispatch cell. `is` performs no kind check. Do not attempt the write or claim a meaningful post-store state.

**Wrong path to diagnose.** A name exists, but that does not prove every operation on its code address is valid. `is` requires both a valid target and the specific layout of a previously created deferred destination.

**Changed case.** After the successful second binding, bind `answer-one` again. The indirect caller returns one again without recompilation. Now imagine binding a valid word with contract `( a b -- sum )`. Why is its valid xt insufficient? Existing `[99]` calls lack the two inputs, so caller compatibility fails even though the dispatch-cell layout and store are correct.

## S10-03 — Preserve a counted token

**Hint 1.** `token` leaves address below length. Write a copy of the length first, retaining the original pair for `bytes,`.

**Hint 2.** Immediately after `token dup`, the stack is `[99, T, 4, 4]` for `main`. A byte writer should consume only that top four.

**Worked solution.** One definition is:

```forth
: demo-counted,  token dup c, bytes, ;
```

It has the requested input contract `( "tok" -- )`; it leaves no address or length on the data stack. Assume P through P+4 are valid writable destination bytes, separated from TIB and other live state.

| After | D | HERE | Destination content established |
|---|---|---|---|
| Start | `[99]` | P | None |
| `token` reads `main` | `[99, T, 4]` | P | None |
| `dup` | `[99, T, 4, 4]` | P | None |
| `c,` | `[99, T, 4]` | P+1 | P contains 4 |
| `bytes,` | `[99]` | P+5 | `4 109 97 105 110` |

The first byte stores a length value. It is not the ASCII digit character `4`, whose byte value would be 52. The accepted range 1–255 fits in one byte; `c,` therefore does not truncate an accepted length. There is no final terminator.

`token`, `dup`, `c,`, and `bytes,` execute during one compiled invocation. Neither writer reads input, so the source remains valid until it has been copied. After the word returns, later token reads may overwrite TIB, but the emitted destination bytes remain in their own region.

With the same initial P, `s, main` would write `109 97 105 110` and end at P+4. It stores no count. A reader of the counted format must start its payload at P+1; treating P as its first character would compare the length byte against `m`.

**Wrong path to diagnose.** `token c, bytes,` loses the only length when `c,` consumes it. `bytes,` then lacks the promised `( a u )` pair. Putting the right words on separate outer-loop lines introduces a different bug: the outer loop's next read can overwrite the borrowed source.

**Changed case.** Supply one 255-byte accepted token with sufficient disjoint destination space. The prefix is one byte containing 255, then exactly 255 payload bytes, for a 256-byte cursor advance. A 256-byte token is not another valid test of this format: the seed reader rejects it before `token` provides a successful result. The length prefix does not expand that input contract.

## S10-04 — Find the unsafe return

**Hint 1.** After three equal byte pairs, one comparison remains. Separate the remaining count from the return destination.

**Hint 2.** Compare what `r>` removes with what `r@` merely copies. Both can put a count on D, but only one repays the borrowed return-stack slot.

**Worked solution.** Let the byte ranges begin at A and B. After three successful passes, D is `[99, A+3, B+3, 1]` and R is `[R0, ret(bytes-eq)]`. The last `>r` parks one. The two fetches supply 110 and 108; `<>` returns `U`, and the conditional consumes that flag.

The correct arm therefore begins and ends like this:

```text
enter arm:       D [99, A+3, B+3]       R [R0, ret(bytes-eq), 1]
r>:              D [99, A+3, B+3, 1]    R [R0, ret(bytes-eq)]
drop:            D [99, A+3, B+3]       R [R0, ret(bytes-eq)]
2drop:           D [99]                 R [R0, ret(bytes-eq)]
[lit] 0:         D [99, 0]              R [R0, ret(bytes-eq)]
compiled return: D [99, 0]              R R0
```

The changed `r@` version creates the same data-stack copy but leaves R as `[R0, ret(bytes-eq), 1]`. Its `drop 2drop [lit] 0` still produces `[99, 0]`. Immediately before the compiled return, however, the top return-stack cell is one. It would be used as an instruction address instead of the caller's continuation. The trace stops at this violated return precondition; a correct-looking data flag does not repair it.

For initial count zero, `dup [lit] 0 >` gives a false condition without consuming the original zero. After the loop test consumes the flag, D is `[99, A, B, 0]`. `drop 2drop true` gives `[99, U]`. No byte reads or parked counts occurred. The answer establishes equality of the two empty prefixes.

For count three with `main` versus `mail`, the compared pairs are `m/m`, `a/a`, and `i/i`. The loop reaches `[99, A+3, B+3, 0]`, then returns `[99, U]`. This establishes only that the three-byte prefixes agree; the differing fourth bytes were outside the requested range.

**Changed case.** Compare `mail` versus `sail` with count four. The first pair, 109 versus 115, differs. The parked count is four, and the same correct cleanup returns zero after one pair of byte fetches. Compare zero length again: even these different first bytes are not read, and the empty-prefix answer remains true.

## S10-05 — Change the policy, keep the caller

**Hint 1.** `demo-main?` already consumes both inputs and leaves a canonical flag. The new policy must reverse that flag without retaining either input.

**Hint 2.** `0=` changes zero to `U` and `U` to zero. The reset store needs a value below `demo-hits`'s cell address.

**Worked solution.** Add this fresh definition and then perform the interpret-mode binding and reset:

```forth
: demo-not-main?  demo-main? 0= ;
' demo-not-main? is demo-classify
[lit] 0 demo-hits !
```

The definition has `( a u -- f )`, matching the former target. The binding consumes its supplied xt and the reset consumes its zero and destination. Starting with D=`[99]`, both leave `[99]`. The new definition advances HERE while it is compiled; the binding and counter reset themselves emit no new code or data. Do not confuse that setup activity with the following runtime checks.

| Completed call | Original `demo-main?` flag | New policy's flag | D | Counter |
|---|---|---|---|---:|
| `demo-next main` | U | 0 | `[99, 0]` | 0 |
| `demo-next mail` | 0 | U | `[99, 0, U]` | 1 |
| `demo-next mainly` | 0 | U | `[99, 0, U, U]` | 2 |

`mainly` takes the existing predicate's unequal-length path and returns zero there; the wrapper's `0=` turns that rejection into acceptance. This is why composing with the established predicate is enough: the new policy inherits both its byte comparison and its length check.

The final acceptance state is D=`[99, 0, U, U]`, `demo-hits` containing two, saved `demo-key` bytes still `109 97 105 110`, and `demo-classify`'s dispatch cell containing the xt of `demo-not-main?`. All call state is restored. The three runtime checks do not move HERE. TIB contents are temporary and may change on subsequent input reads.

`demo-next`'s existing call continues to target `demo-classify`'s original code address. That code fetches the new target from the same dispatch cell. No caller recompilation is needed. The counter's meaning has changed with the policy: it now counts non-`main` tokens. Resetting it prevents counts from two policies being mixed without explanation.

**Wrong path to diagnose.** Redefining `demo-classify` as an ordinary colon word would create a new dictionary entry; it would not redirect the old call inside `demo-next`. The intended operation is to update the original deferred word's dispatch cell through `is`.

**Changed case.** Rebind `demo-main?` and reset the counter again. Check `demo-next mainx` followed by `demo-next main`, starting at `[99]`. The first token's length five rejects it, so the states are `[99, 0]` with counter zero, then `[99, 0, U]` with counter one. A prefix-only implementation would incorrectly accept the first token; the explicit length check prevents that result.

## What your checks established

These derivations cover layout, initialization, stable dispatch, borrowed-buffer lifetime, bounded comparison, and a combined reader-built program. They establish predicted states under the named assumptions, not that a seed session was run or that a reader has retained the mechanisms. For a later independent revisit, explain one failure boundary as well as one successful trace, using the [chapter's stopping points](../chapters/10-storage-deferred-words-and-bytes.md).
