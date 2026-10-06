# C03 practice: hints, worked solutions, and changed cases

[Return to Preprocessing regions and includes](../chapters/03-preprocessing-regions-and-includes.md)

These are manual derivations from the pinned source described in C03, not executed compiler results. Keep the chapter's eight-byte-cell, byte-offset, valid-storage, legacy-main-path, and successful-I/O assumptions unless a question changes one. The examples test preprocessing states, not whether the fixtures are complete C programs.

Try an explanation as well as a final number. If you cannot begin, choose the first hint; if one transition is missing, use the second. You can go directly to the solution when a worked comparison would help. After checking, use the changed case to see whether the reason survives a different boundary.

## C3-01 — Distinguish input from output

### Hints

1. Give the input position and output position separate columns. Which word changes each?
2. Peek returns byte 10 at input offset 1. The emitter checks proposed output length 3 against capacity 3 before storing it.

### Worked solution

Initially input is `(A,3,1)`, output is `(S,2,3,36)`, line=1, and S's meaningful bytes are `Q;`.

| Operation completed | Result or attempted byte | Input position | Output position | Meaningful output | Line |
|---|---:|---:|---:|---|---:|
| Peek | 10 | 1 | 2 | `Q;` | 1 |
| Advance | — | 2 | 2 | `Q;` | 1 |
| Emit saved byte | 10 | 2 | 3 | `Q;\n` | 2 |
| Attempt emit | 33 (`!`) | 2 | 3 | `Q;\n` | 2 |

The last operation checks `3+1 > 3` and exits with error 36 before storing. With the stated line and diagnostic-write assumptions, the attempted message is `cc: line 2: error 36` followed by newline. It does not return to let a caller continue this trace.

Advance neither writes output nor increments line. The line change belongs to emitting byte 10. A common wrong answer increments twice because it mentally combines reading and writing into one operation. That combination is exactly what separate cursors prevent.

### Changed case

Start again but make the sink capacity four. Both emissions now fit: input position=2, output position=4, output `Q;\n!`, line=2. If the current input byte were a stored zero instead, peek would return zero while `cc-prep-eor?` would still be false. Only the length comparison establishes end-of-region.

## C3-02 — Restore a parent

### Hints

1. The quote at offset 13 has already been consumed before the parent is saved. Its newline has not.
2. At depth two, slot 0 belongs to the root and slot 1 belongs to `a.h`. The sink belongs to neither frame.

### Worked solution

Immediately after `B\n` is copied:

- Active region is `(I1,2,2)` at include depth 2
- Saved slot 0 is `(R,17,14)`
- Saved slot 1 is `(I0,17,14)`
- Output is `B\n`, position=2, line=2, pending=0

Returning from `b.h` decrements depth to 1 and uses slot 1. The restored byte at position 14 is `a.h`'s include-line newline. Finishing that directive leaves it for the scanner. Copying this newline and `A\n` appends three bytes, giving `B\n\nA\n`, position=5, line=4. Returning again decrements depth to zero and restores slot 0. Its newline and `R\n` append three more bytes.

The predicted final output is `B\n\nA\n\nR\n`, bytes `66 10 10 65 10 10 82 10`, length eight. There are five newline bytes, so the preprocessor's output-progress line becomes six. The top-level completion then stores source length eight and initializes the next reader at position zero, line one.

If a mistaken include-return step resets output position to the pre-include value zero, later emissions overwrite the child's output prefix. Saving a parent's input cursor is required to resume its source; resetting the shared output cursor discards completed work. No sink frame is pushed for the plain includes in this example.

### Changed case

Remove only the final newline from `b.h`, so its region is `(I1,1,0)` on entry. The child produces `B`, position=1, line=1. The retained newline from `a.h`'s include directive now follows that byte directly. Complete the remaining steps to obtain `B\nA\n\nR\n`, length seven, four newlines, final output-progress line five. The next reader still starts at line one.

If your result starts `B\n\n`, you retained a newline that the changed child no longer contains. Revisit which file owns each newline rather than removing an arbitrary blank line afterward.

## C3-03 — Find a lifetime error

### Hints

1. Both root-level includes are loaded while the parent's depth is zero.
2. The second load can change the bytes at the saved address without changing that address's numeric value.

### Worked solution

`one.h` loads into slot 0. While it is scanned, a borrowed name/body span can validly refer into that slot. Returning to the root ends the need to preserve `one.h` as a live input region. Loading `two.h` at root depth zero writes into slot 0 again. A retained definition pointing there may now refer to unrelated bytes, a mixture of overwritten and leftover bytes, or a span beyond the new file's logical length.

The required repair to the hypothetical design is an ownership rule: copy all bytes needed for the retained definition into storage whose lifetime covers later uses, and retain spans into that storage. The real macro mechanism uses the macro pool for names and bodies; C04 opens its allocation and record operations. Merely saving another copy of the address or parent triple preserves no payload.

A live parent's span is different. While `one.h` is at depth one and loads its own child, that child uses slot 1. Slot 0 remains preserved until `one.h` finishes. The relevant condition is simultaneous lifetime, not whether both files are called headers.

The final source sink also owns copied bytes independently. Reusing slot 0 does not rewrite bytes already emitted into the source buffer.

### Changed case

Use direct packed storage, base P and top 20. A child of length five starts at P+20, making top 25. Its nested child of length three starts at P+25, making top 28. On the nested return, top becomes 25; another nested child may overwrite the bytes beginning P+25, but not the live parent's `[P+20,P+25)` span. On the parent's return, top becomes 20, permitting reuse of its five bytes too.

The offsets changed; the lifetime rule did not. Popping top does not erase bytes, but their leftover contents are not a continued preservation guarantee.

## C3-04 — Keep path and read bounds distinct

### Hints

1. The legacy fallback is independent of `src/main.c`. Direct quotes and direct angles begin at different places in the search order.
2. `path-out` counts path characters without the zero. `cc-read-all`'s spare byte is not a zero it stores.

### Worked solution

Assuming each preceding candidate fails to open:

- Direct quoted `a.h`: `src/a.h`, `inc/a.h`, `vendor/a.h`
- Direct angle `a.h`: `inc/a.h`, `vendor/a.h`
- Legacy quoted `a.h`: `a.h`, `tests/cc/a.h`

Search stops at the first nonnegative file descriptor. The legacy fallback has nine prefix bytes and three name bytes: `path-out=12`, zero at offset 12, thirteen bytes of required storage. The helper does not count the terminating zero in the path length.

A legacy include read returning 262,144 bytes fills its slot. The positive-read branch adds that count and checks `262144+1 <= 262144`, which is false. It exits with code 32, even if those bytes were exactly the whole file. It does not perform an additional EOF probe. No ordinary include scan follows that failure, and the later close in `cc-prep-load-file` is not reached through normal return.

A plausible wrong answer treats the 1024-byte path buffer and the 262,144-byte content slot as the same bound. One limits the spelling used to find a file; the other limits the bytes read from it.

### Changed cases

1. In direct mode use absolute `/opt/a.h`. It is tried as supplied, with no configured-directory fallback in `cc-prep-open-include`.
2. Let a path have 1023 nonzero bytes. It fits with its zero at offset 1023. One more path byte makes the check fail with 33 before that append writes. A long configured directory needing an added slash must still fit the subsequent bounded path copy.
3. Let the selected direct include pool have capacity 100 and top 90. The next file has only ten bytes of available read room; a result of ten fails with 32. A result of nine followed by zero succeeds, making top 99. This is a paper capacity, not a proposed source setting.
4. Suppose `cc-prep-direct` becomes true without calling the larger workspace selector. The selected packed include pool remains the default 1 MiB. Policy selection is not memory allocation.

## C3-05 — Recover swallowed newlines

### Hints

1. `skip-to-eol` crosses a block comment as a whole, even when it contains newline.
2. Stop immediately after `*/`: one newline is owed, and another is still the current input byte.

### Worked solution

In the chapter's legacy profile, the first `#` is recognized at file line start. The unrecognized name is read, but no include/define/conditional action matches it. The remaining directive text is discarded through `cc-prep-skip-to-eol`, using count mode.

The first newline is inside `/*x\n y*/`. The block walker consumes it and increments pending to one without writing. At the newline after `*/`, skip-to-eol stops. Output remains empty, position=0, line=1. The main scan then flushes pending: emit newline, pending=0, position=1, line=2. It clears line-start after directive handling. On the next iteration, ordinary newline handling consumes the retained terminating newline, emits it, and sets line-start true: position=2, line=3.

Reading `R` produces output `\n\nR`, position=3, line=3. Its following newline gives `\n\nR\n`, position=4, line=4. The directive's spelling is gone, but its two physical newline bytes have both been represented.

A `#` inside the block comment does not start another directive: the scanner is inside a construct walker, not calling directive lookahead for each internal byte. Even an internal newline does not make the comment's next byte a fresh directive candidate.

For a line beginning with a block comment before `#`, inspect `cc-pp-location-enabled`. With that flag zero, directive lookahead skips spaces and tabs only and stops at the slash. Setting only `cc-prep-direct` does not enable the richer prefix walker. C05 explains what the location-enabled prefix supports and rejects; it is not a promise of unrestricted C phase-two behavior.

### Changed case

Replace the first two lines by the single physical line `#unknown /*x*/\n`. There is no swallowed newline, so pending remains zero. Flush writes nothing. The retained line-ending newline is still emitted once, and copying `R\n` gives `\nR\n`, length three, output-progress line three.

If you kept two initial newlines, compare the input bytes. If you kept none, compare the stopping contract of skip-to-eol with the consuming contract of the main newline branch.

## Choose a useful next step

- If input and output positions still mix together, redo C3-01 with two explicit columns before attempting another nested trace
- If the final output is right but saved triples are not, pause after each closing quote in C3-02 and write the parent state before entering the child
- If storage reuse is clear, explain the direct packed changed case without consulting the solution; identify the preserved interval rather than relying on a slot number
- If profile answers were overconfident, write the two flag values and selected pool capacity above the next example before predicting it

After other material, return to C3-02 without the completed table and remove a different newline. Being able to explain the changed ownership and line count is useful evidence of this mechanism; it does not establish general compiler correctness or learning transfer to an unrelated system.
