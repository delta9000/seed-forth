# C22 hints and solutions

These are source-derived paper solutions to [C22's practice](../chapters/22-two-pass-assembly-and-bootstrap-handoff.md#practice-explain-the-coordinate-or-artifact-before-calculating), not new executions. Use one hint at a time. The answer-free reattempts at the end change a meaningful condition without placing an answer beside the prompt.

## C22-01 — Complete the original two-pass trace

**Hint 1.** Count output bytes, not characters of assembly text.

**Hint 2.** Labels have zero width. Each `!` field has width one; the relative subtraction starts after that field.

**Hint 3.** The first `EB` occupies offset 0, so its field ends at offset 2.

**Solution.** `top=0`, `end=4`, final offset=7. The forward value is `4−2=2`; the backward value is `0−7=−7`. The latter's low byte is `256−7=249=F9`:

```text
EB 02 41 00 90 EB F9
```

Rewind resets the text cursor and IP; it also resets the output position and selects pass 2. It preserves the expanded bytes and the completed label table/count. `asm-init` would set the label count to zero, making those stored records unavailable to lookup even if their memory contents physically remained.

**Common wrong path.** Values 4 or 3 for the first field subtract the opcode or field start instead of the field end. Rewinding the cursor alone would leave IP at the wrong target position.

## C22-02 — Length and base change together

**Hint 1.** Direct double quotes produce each character byte and a terminating NUL.

**Hint 2.** `&end` emits an absolute address. Appending it after the backward field does not change that field's own end.

**Hint 3.** The three-character string contributes four bytes, so `end` is at offset 6.

**Solution.** The expanded sequence is `:top EB !end 41 42 43 00 :end 90 EB !top &end `, with one final separator space. `top=0x700000` and `end=0x700006`. The output totals 13 bytes:

```text
EB 04 41 42 43 00 90 EB F7 06 00 70 00
```

The forward field ends at 2 and uses `6−2=4`. The backward field is at 8 and ends at 9, giving `0−9=−9`, low byte `F7`. The absolute field occupies offsets 9–12 and contains `0x700006` little-endian.

The two relative fields depend on the string's length, with the common base canceling. The absolute field depends on both the base and the target's offset. The NUL counts because expansion emits a `00` byte after the direct string body; it is not only an in-memory source-text terminator.

**Common wrong path.** Subtracting the full final length 13 for `!top` includes the later absolute field. Each reference uses its own field end, not the file end.

## C22-03 — Separate number, relative label, and explicit difference

**Hint 1.** All six widths stay the same when changing the configured base.

**Hint 2.** `$a` and `&a` emit the address; `~a` subtracts its field end. `%end>a` subtracts two labels.

**Hint 3.** `a=0x1200`, `end=0x1210`, and `~a` starts at offset 3.

**Solution.** The first two fields are numbers and never subtract IP:

| Token | Offset / width | Value | Predicted bytes |
|---|---|---|---|
| `!-2` | 0 / 1 | −2 | `FE` |
| `@0x1234` | 1 / 2 | `0x1234` | `34 12` |
| `~a` | 3 / 3 | `0−6=−6` | `FA FF FF` |
| `$a` | 6 / 2 | `0x1200` | `00 12` |
| `&a` | 8 / 4 | `0x1200` | `00 12 00 00` |
| `%end>a` | 12 / 4 | `0x1210−0x1200=16` | `10 00 00 00` |

The total is 16 bytes. The absolute two-byte label range is 0–65535, and `0x1200=4608` is within it; default `0x600000` is not. `%end` instead calculates `0x1210−(0x120C+4)=0`, so only the final four bytes change to `00 00 00 00`.

**Common wrong path.** Treating the word after `>` as the configured origin rather than a label happens to agree for this particular `a`; the rule must still be stated as target-label address minus base-label address.

## C22-04 — Derive both short-reference boundaries

**Hint 1.** Use the relative-label bounds, −128 through 127, for references to names.

**Hint 2.** The forward reference's own opcode and field precede the gap. They follow the gap for the backward case.

**Hint 3.** Forward value is N; backward value is `−(N+2)`.

**Solution.** Forward N can reach 127, giving displacement 127, byte `7F`. N=128 fails with 244. Backward N can reach 126, giving `−128`, byte `80`. N=127 gives −129 and fails with 244.

`!256` is a numeric form accepted at its inclusive upper boundary; its low byte is `00`. `!257` fails with 245. `!-129` is accepted at its numeric lower boundary and has low byte `7F`. The number policy accepts values that do not fit a conventional signed eight-bit interval. Acceptance and subsequent low-byte storage are separate operations.

**Common wrong path.** Applying the numeric lower bound to the backward label would incorrectly accept one extra gap byte. Both tokens start with `!`, but their body classification chooses different limits.

## C22-05 — Move the duplicate after an earlier reference

**Hint 1.** Complete pass 1 before resolving either reference.

**Hint 2.** The label search begins at the newest stored record, regardless of where the current reference occurs.

**Hint 3.** The initial reference itself consumes one byte, so the first declaration's offset is 1.

**Solution.** In insertion order, the records contain `x=base+1` and `x=base+2`. Both pass-2 references find the latter. The first field ends at offset 1 and uses `2−1=1`; the last ends at offset 3 and uses `2−3=−1`. The bytes are:

```text
01 90 FF
```

The first reference is not undefined and does not bind to the first declaration. Lookup sees the completed table, and reverse search selects the last stored matching name. A found label at address zero returns `(0 true)`, which differs from failure `(0 0)` because of the flag.

**Common wrong path.** Nearest-preceding-label intuition invents a scope rule this implementation does not have. Duplicate definitions are not rejected either.

## C22-06 — Locate the first rejecting phase

**Hint 1.** Pass 1 validates bare hex but only counts reference widths.

**Hint 2.** For bare hex, character validity is tested before odd length.

**Hint 3.** A reaches pass 2; B and C do not.

**Solution.** A sizes successfully to two bytes. In pass 2, it emits `90`, then fails at `!missing` with 235. Its writer has not been reached. B fails in pass 1 with 246 because `Z` is nonhex. C fails in pass 1 with 247 because `F` is a valid hex digit but the token has odd length. Neither B nor C newly emits an output byte during sizing, and neither opens the output file.

The successfully processed prefix still obeys the invariant. For A, after emitting `90`, output position is 1 and IP is base+1. The invariant does not promise that the next token can be resolved. For B/C, sizing the prefix `90` establishes its width before validation rejects the next token.

**Common wrong path.** Saying pass 1 emits a placeholder for `!missing` confuses counting with writing. Saying B fails with 247 ignores the implementation's check order.

## C22-07 — Preserve the storage contract

**Hint 1.** Read “name address” as a pointer, not a copied string.

**Hint 2.** The target-IP cell does not let lookup recover the original name bytes.

**Hint 3.** Capacity checks use prospective count plus one and permit equality with the cap.

**Solution.** Each label record contains an expanded-buffer address, a length, and a target IP. Overwriting the expanded buffer destroys the bytes used by name comparison and also removes the input the second pass must reread. A correct lifetime rule is: retain the unchanged expanded buffer, along with its length and complete label table, until both assembly passes finish. Rewinding the cursor preserves that storage.

Given the capacity scenario, pass 2 can append exactly 1,048,576 bytes. The attempted 1,048,577th append fails with 241 before writing that byte. Its successful first-pass size did not reserve a larger output buffer. The 8,192nd label store succeeds; the 8,193rd fails with 242 before its record is stored.

**Common wrong path.** Assuming `n < cap` rather than the actual `n <= cap` rejects the last valid slot. Applying C21's special raw-input `length+1` post-read rule to every buffer invents a restriction the output appender does not have.

## C22-08 — Do the records establish a saved executable?

**Hint 1.** Separate the in-memory output from the named file and from its previous contents.

**Hint 2.** The writer runs only after both passes complete.

**Hint 3.** The inspected code drops the write result rather than comparing it with the requested count.

**Solution.** A's remaining file is stale evidence. The new invocation fails before open and therefore neither truncates nor replaces it. Its mere existence says nothing about successful output of the failing invocation.

B requests a write of 148 bytes but receives 100. The code discards 100, closes, and does not diagnose or retry the missing 48 bytes. A later normal completion cannot establish full-file storage. Removing a stale file beforehand helps identity but does not solve a short write.

An actual post-write byte comparison with the expected complete fixture would support the equality claim. A verified length of 148 alone is useful but weaker: equal lengths can contain different bytes. The exercise supplies a hypothetical record, not evidence that a new comparison was performed.

**Common wrong path.** Promoting output cursor 148 into an on-disk size skips the I/O boundary. Promoting requested mode 0755 into guaranteed executability similarly ignores umask and existing-file permissions.

## C22-09 — Change the supplied-header fixture

**Hint 1.** Removing the dead instruction changes layout even though that instruction was not meant to execute.

**Hint 2.** The removed instruction is seven bytes. Everything before it keeps its offset.

**Hint 3.** The branch still ends at offset 139, which now also names `skip`.

**Solution.** `skip` moves from 146 to 139 (`0x60008B`), and `ELF_end` moves from 148 to 141 (`0x60008D`). The branch displacement is `139−139=0`, so its four field bytes become `00 00 00 00`; its opcode remains `E9`.

The entry remains at 120, or `0x600078`, so the low entry bytes remain `78 00 60 00`. Each size field now begins `8D 00 00 00`, followed by the supplied high zero half. The predicted exit status remains 42: RDI is set to 42, and the jump reaches the syscall. This is a source-derived prediction; a recorded successful process exit would be additional evidence.

**Common wrong path.** “Dead code cannot affect anything” overlooks address layout and file size. It need not affect the intended exit value to affect many output bytes.

## C22-10 — Recover the source-built handoff

**Hint 1.** Follow every `.M1` text artifact through an assembler before allowing it to run.

**Hint 2.** Step 5 deliberately reuses the same `self-v1` text for both assembly routes.

**Hint 3.** Step 6 compares `.M1` files; step 7 compares each tool with its own rebuild.

**Solution.** Bootstrap v1 emits `self-v1-amd64.M1` from M2-Planet's self-source. `130` plus its larger companion inputs assembles it into `cc-out-v2-fasm`. That compiler emits `WORK/M1.M1` from the M1 C source vector; `130` assembles that into `OUT/M1`. The parallel hex2 compilation/assembly produces `OUT/hex2`.

Those two source-built tools assemble the original `self-v1-amd64.M1` into `cc-out-v2`. The first handoff comparison is `OUT/cc-out-v2` versus `OUT/cc-out-v2-fasm`: same-M1, two assembly routes, ELF output equality.

Step 6 compares `OUT/self-v2-amd64.M1` with `OUT/self-v3-amd64.M1`. Step 7 compares `WORK/M1-gen2` with `OUT/M1`, then `WORK/hex2-gen2` with `OUT/hex2`.

A GCC-compiled M1 executable is a different implementation artifact. Bootstrap step 5 uses the source-built M1/hex2 pair just traced. The separate `mescc-tools-check.sh` route, under its default GCC reference setting, runs the GCC-built M1/hex2 pair on the same C-derived M1 and compares the resulting ELF with Forth assembly of that text. Matching the two tool implementations' executable bytes is not required by either assembly-route predicate.

**Common wrong path.** Names such as `M1.M1` conceal a representation change if read as interchangeable instances of “M1.” Name the artifact type each time.

## C22-11 — Read the oracle literally

**Hint 1.** Locate the final supplied input or compared file rather than relying on a test's name.

**Hint 2.** A compiler's output text is not its generated program executing.

**Hint 3.** The greeting uses captured stdout, whose trailing newlines are removed by shell command substitution.

**Solution.** All five claims overreach:

1. `exit42-check` supplies already converted hex2 to the Forth assembler, so it does not by itself exercise Forth macro expansion
2. The final `m2planet-check` compares two emitted M1 text files for the tiny C source. That part does not assemble/run the tiny program
3. The hex2 smoke check compares four raw bytes under `--non-executable`. Four magic bytes are not the complete 120-byte envelope, still less the fixture and an execution check
4. The 52,808 count belongs to the output assembled from the M1 tool's C-derived M1 text, compared across two assembly routes. It is not the size of the host-GCC-built producer
5. Captured-string equality checks the remaining string after trailing-newline removal, together with a separate zero-exit requirement. It cannot establish the count of original trailing newline bytes

**Common wrong path.** “Byte-identical to reference” does not identify an oracle until the two exact operands and their producers have been named.

## C22-12 — Return without the original trace

**Hint 1.** Decide numeric-versus-label handling before doing any subtraction.

**Hint 2.** A deterministic transformation can discard distinctions present in its input.

**Hint 3.** For `!p`, the field begins at offset 1; the relevant end is 2.

**Solution.** `:p 00 !p` at base zero emits `00 FE`: p is zero, field end is 2, and `0−2=−2`. Lookup's true flag distinguishes the found zero address from failure. Replacing `!p` with numeric `!0` emits `00 00`; zero is the immediate value and no IP subtraction occurs.

Comment removal can map distinct text bytes to the same expanded text and hence, under the fixed conditions, the same output bytes. That does not contradict determinism. The reverse implication is invalid: equal output does not recover distinctions the transformation discarded.

Step 6's summary must say that v2 and v3 emitted identical M1 text for the specified self-source input/profile. It does not compare the compiler executable files themselves.

**Common wrong path.** Reasoning “same sigil, same formula” misses the body classification. Reasoning “same output, same source” assumes an invertible transformation where none was supplied.

## Answer-free changed cases

Choose one after using feedback. State the invariant first, then keep your calculation separate from the previous solution.

- Change C22-02 to base `0x710000`, string `"Z"` (ASCII `Z=0x5A`), and final absolute field `&top`. Recompute the fields affected by each independent change
- Change C22-05 to `!x :x 90 90 :x !x`. Identify both target records before resolving either reference
- Change C22-09 by keeping the dead instruction but inserting `00` immediately before `:ELF_end`, after the syscall. Which header and branch fields change, and which expected behavior remains conditional on the same target contract?
- Suppose two later generated M1 files differ by comments but their assembled ELFs compare equal. Decide which of a Stage-A-style text comparison, bootstrap step-5-style route comparison, and step-6-style textual fixed point this evidence can satisfy, naming any still-missing inputs or comparison operands
