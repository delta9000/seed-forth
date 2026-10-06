# Defining words and phases feedback

Return to [Chapter 8](../chapters/08-defining-words-and-phases.md). Use a hint
or a worked comparison whenever it helps. All outcomes below are manual
derivations for the pinned Linux/x86-64 seed, not executed results. Stacks
have their top at the right, cells occupy eight bytes, and byte listings
are hexadecimal unless labeled otherwise. Model addresses are paper
locations, not a safe live execution setup.

When checking an answer, name the executing word, the word being built,
and any input token consumed. Those three labels often reveal a phase
mistake before any byte arithmetic is needed.

## S8-01 — Separate the three phases

**Hint 1.** Separate reading the source of `constant` from executing the
machine code that source produces. The second colon's immediate flag is
clear.

**Hint 2.** During the definition of `constant`, `[lit] 0` emits code that
will later push zero. During a later call to `constant`, that code supplies
the zero for the state reset; it does not read a new numeric token.

**Worked solution.** A complete timeline is:

| Phase | Executing mechanism | Dictionary work | Relevant data effect |
|---|---|---|---|
| 1. Define `constant` | Outer loop dispatches the source tokens | First `:` writes `constant`'s header; compiled calls and literal form its body; `;` appends its return | No seven was supplied or captured |
| 2. Process `[lit] 7 constant seven` | Interpret-mode `[lit]` supplies seven; then the compiled body of `constant` runs | The executed inner `:` consumes `seven` and writes its header; `push-body,` writes its 19-byte body | Seven is consumed into the generated value field; `[99, 7]` becomes `[99]` |
| 3. Execute `seven` | The generated native body runs | No header or code emission | `[99]` becomes `[99, 7]` |

In phase 1, the first colon runs in interpret mode and reads the name
`constant`. STATE becomes one. When the outer loop encounters the second
colon, its flag is clear, so it appends a call to that colon's xt. The
colon does not execute now and cannot consume `push-body,` as a name now.
The final semicolon is immediate, so it ends the definition of `constant`.

In phase 2, the stored call really executes colon. It consumes the next
input token, `seven`, builds a header, and sets STATE to one. Execution
then continues through `constant`'s already-built body. The processor
calls `push-body,` directly; no outer-loop token dispatch occurs between
those compiled instructions. STATE therefore does not turn those calls
back into compile requests.

`push-body,` emits the new word's return byte. The compiled zero, call to
`state`, and call to `!` restore STATE to zero. Finally, the return byte
belonging to `constant` resumes its caller. These are two distinct return
bytes with different jobs and locations.

**Plausible wrong path.** “STATE is one, so `push-body,` must be compiled
instead of executed.” That rule applies when the outer loop dispatches
an ordinary token. Here the next action is already a native call inside
an executing definition. State alone does not identify which mechanism
is making the decision.

**Changed case.** Close the timeline and substitute
`[lit] 300 constant three-hundred`. The three phases are unchanged, but
the captured value is now 300. Its eight value bytes are
`2C 01 00 00 00 00 00 00`, because `300 = 44 + 1×256`.
`push-body,` still emits 19 bytes; a value requiring more than one byte
does not enlarge the fixed eight-byte field. Later `three-hundred` pushes
the whole cell value 300, not only 44.

**Check your explanation.** It should distinguish the source semicolon,
the return emitted into the created word, and the return executed by the
defining word. “There are two colons” is not enough to explain their times.

## S8-02 — Locate the metadata and body

**Hint 1.** Count the letters of `seven`, then add ten header bytes. An xt
points past that entire header.

**Hint 2.** The value begins ten bytes into the body, after the two
room-and-save instructions and the two-byte `movabs` prefix. Distinguish
this body offset from the entry's header offsets.

**Worked solution.** The three expressions return different addresses:

| Expression | Result | Role |
|---|---:|---|
| `latest` | 2000 | Address of LATEST's system cell |
| `latest @` | 1000 | Address of the newest entry, `seven` |
| `' seven` | 1015 | Body address, the execution token |

Tick consumes `seven` from input. That name is not a second data-stack
input. The full layout, with `H=1000`, is:

| Address range | Contents |
|---|---|
| 1000–1007 | Link to previous dictionary entry |
| 1008 | Flags, initially `00` after colon |
| 1009 | Name length `05` |
| 1010–1014 | Name `seven`: `73 65 76 65 6E` |
| 1015–1018 | `48 83 ED 08` |
| 1019–1022 | `48 89 7D 00` |
| 1023–1024 | `48 BF` |
| 1025–1032 | Captured seven: `07 00 00 00 00 00 00 00` |
| 1033 | Return byte `C3` |
| 1034 | Next unwritten location, the final HERE contents |

Tracing the actual `immediate` from `[99]` gives:

```text
latest         [99, 2000]
@              [99, 1000]
[lit] 8        [99, 1000, 8]
+              [99, 1008]
[lit] 1        [99, 1008, 1]
swap           [99, 1, 1008]
c!             [99]
```

The byte at 1008 becomes one. HERE remains 1034; LATEST still holds 1000.
The call changes the metadata in place rather than emitting a new body.

If the previous flags byte were decimal 128, the result would still be
one, not 129. The definition neither reads nor ORs the old flags. A second
call would again leave one, so “toggle” is also the wrong operational
description.

Changing the final `c!` to `!` writes eight bytes at 1008–1015:
`01 00 00 00 00 00 00 00`. It overwrites the name length, all five name
bytes, and the first byte of the body, as well as writing the flag.
The intended one-byte metadata update has become a header-and-code
corruption. Do not try to infer a valid later execution from that state.

**Plausible wrong path.** Using 2008 for the flag location adds eight to
the system cell address without fetching its entry pointer. In the
chapter's system layout that is HERE's cell address, not any flag field.

**Changed case.** Independently reset the entry start to 1000 and define
value seven under the seven-byte name `seventh`. Its header has 17 bytes;
xt is 1017; the value begins at 1027; return is at 1035; next HERE is 1036.
The flags and length fields remain at 1008 and 1009 because their offsets
precede the variable-length name. The body is still 19 bytes.

This changed name tests the boundary between fixed header fields and the
variable body-start address. A memorized xt of 1015 would fail it.

## S8-03 — Capture the right kind of address

**Hint 1.** Evaluate `here` or `here-addr` before letting `constant` consume
its input. Creating the header subsequently moves HERE; it cannot change
the value already supplied on the data stack.

**Hint 2.** At the later point, keep two separate facts visible:
address-of-HERE is 2008; contents-of-HERE is 1200.

**Worked solution.** With an older value 99, the first construction begins:

```text
Before here                  [99]          HERE contains 1000
After here                   [99, 1000]
After constant saved-here     [99]          captured value is 1000
```

Creating `saved-here` itself writes a header and body and advances HERE.
Those changes occur after `here` fetched 1000. They do not revise the
captured value field. When HERE later contains 1200, executing
`saved-here` still changes `[99]` to `[99, 1000]`.

The separate reset for the second construction gives:

```text
Before here-addr                   [99]          HERE's cell is at 2008
After here-addr                    [99, 2008]
After constant saved-here-cell     [99]          captured value is 2008
```

At the later point, `saved-here-cell` pushes 2008. Following it with `@`
fetches the current contents of that cell, 1200. The created word still
pushes a fixed value; the explicit fetch gives the changing result.

| Later expression | Data result | Explanation |
|---|---|---|
| `saved-here` | 1000 | Captured old cursor |
| `saved-here-cell` | 2008 | Captured address of cursor cell |
| `saved-here-cell @` | 1200 | Fetch through that fixed cell address |

`saved-here @` reads a cell beginning at 1000. It does not fetch from
2008. Under this model the first declaration placed its own header at
1000, so if that header remains intact, this fetch reads its link field.
The memory word follows the numeric address it receives, not our intent.

**Plausible wrong path.** “A constant made using `here` stores the operation
`here`.” The emitted template contains the eight bytes of a value, not a
call to the word that happened to produce it.

**Changed case.** Suppose the goal really is a word that fetches the current
cursor on every execution. A teaching definition `: current-here here ;`
compiles a call to `here`; it does not use `constant`. With HERE later
1200, it pushes 1200; after HERE later becomes 1400, it pushes 1400.
Alternatively, with the address constant already made, a body
`saved-here-cell @` performs the explicit indirect fetch. Both differ
from a captured old cursor because their runtime instructions perform a
read each time. These predictions assume the same fixed sysvar layout.

## S8-04 — Repair the displacement origin

**Hint 1.** Mark the start, first displacement byte, and first byte after
the instruction separately: 1000, 1001, and 1005.

**Hint 2.** The target arithmetic is based on the processor's return
destination, 1005, even if the writer computes a wrong displacement.

**Worked solution.** The desired displacement is:

```text
target - end-of-instruction = 1100 - 1005 = 95
```

Decimal 95 is hexadecimal `5F`. The five bytes are therefore
`E8 5F 00 00 00`, at 1000–1004. HERE becomes 1005. The destination check
is `1005+95=1100`.

In the actual definition, `c,` has already advanced HERE to 1001 before
the expression `here [lit] 4 + -`. It computes the required origin
`1001+4=1005`.

Changing four to five computes `1001+5=1006`, so the wrong displacement
is `1100-1006=94`, encoded `5E 00 00 00`. The processor still adds it
to 1005. The actual destination would be `1005+94=1099`, one byte before
the intended target. The opcode and overall instruction length are
unchanged; the defect is the encoded distance.

A displacement of positive 2147483648 is outside the signed 32-bit range.
`,4` can emit `00 00 00 80`, but the processor interprets that displacement
as negative 2147483648. Representable bytes do not establish the intended
relative address. The helper contains no range diagnostic, so stop the
contract-level derivation at that failed range condition.

**Plausible wrong path.** Subtracting 1000 treats the call's start as the
origin. That gives 100 and would land at 1105. The start is useful for
placing bytes; the end is the origin for interpreting their displacement.

**Changed case.** Keep the start at 1000 but move the target to 1005.
The correct displacement is zero, and the bytes are `E8 00 00 00 00`.
This is the address calculation only: a useful called routine still
needs suitable code and call/return behavior at that destination. Moving
the target to 900 instead gives -105 and `E8 97 FF FF FF`, as in the
chapter. The same origin rule works on both sides of the call.

## S8-05 — Follow a consumed semicolon

**Hint 1.** Some tokens are read by the currently executing word rather
than by the outer loop. Tick reads a name but does not execute the name's
lookup result.

**Hint 2.** Mark both stacks at the runtime call to `lit`. The return
stack supplies an address of data; `lit` reads through it and changes
where it will return.

**Worked solution.** After the initial `:` reads `semi`, the new header
exists, HERE is its model body start `B`, and STATE is one. The outer loop
encounters `[char]`. Its immediate flag is set, so it executes now.

Within `[char]`, the call to `char` executes tick. Tick consumes the first
semicolon token and finds its xt. `drop` discards that xt, and `tib c@`
pushes ASCII 59. The semicolon's name was read, but the semicolon word was
not executed. The compiler remains inside `semi`.

`lit-xt` supplies the address of `lit`, `call,` consumes that address to
write a five-byte call, and `,` consumes 59 to write the inline cell.
The next semicolon token is then read by the outer loop. It is immediate,
so it appends the return byte and restores STATE to zero.

| Body locations | Meaning |
|---|---|
| `B` through `B+4` | Call to `lit`, with a suitable relative displacement |
| `B+5` through `B+12` | `3B 00 00 00 00 00 00 00`, the cell value 59 |
| `B+13` | `C3`, compiled by the second semicolon |
| `B+14` | Next HERE after the complete definition |

The body occupies 14 bytes. We cannot give concrete call-displacement
bytes without a numeric relationship between `B` and `lit`'s xt, so the
layout deliberately leaves that field symbolic.

At runtime, suppose `semi` starts with data stack `[99]`. Let `Rold`
stand for any older return-stack entries:

```text
Entering semi:     D [99]       R [Rold, return-from-semi]
CALL lit:         D [99]       R [Rold, return-from-semi, B+5]
lit reads cell:   D [99, 59]   return address B+5 is held temporarily
lit restores:     D [99, 59]   R [Rold, return-from-semi, B+13]
lit returns:      D [99, 59]   R [Rold, return-from-semi]
semi's RET:       D [99, 59]   R [Rold]
```

The `RET` at `B+13` is the first instruction after the inline cell. The
cell itself is never decoded as instructions along this path. `lit`'s
specialized return-address rewrite is what makes that layout valid.

Now consider the three interpret-mode character/lookup expressions, each
with an independent empty data stack and a following token `A`:

| Expression | Result or boundary when `A` is undefined |
|---|---|
| `char A` | Tick returns zero, `drop` discards it, TIB's first byte supplies 65 |
| `' A` | Tick returns zero |
| `' A execute` | Tick returns zero; `execute` then lacks a valid executable xt |

Stop the last case at that failed precondition. Zero is a lookup result,
not a fallback word or a no-op. It is safe for `char` to discard it;
it is not valid input to `execute` under the supplied contract.

**Plausible wrong path.** Seeing the token `;` and assuming it must close
a definition ignores who consumed the token. Lookup alone does not
dispatch its result.

**Changed case.** On paper, replace the first semicolon token with `A`:
`: capital-a [char] A ;`. The body is still 14 bytes, but the value field
begins `41` instead of `3B`, and later execution pushes 65. No word named
`A` is required. A different boundary is `char (x`: the multi-byte token
`(x` is not the reader's exact one-byte comment marker, so its first byte
is 40. By contrast, whitespace and a token exactly `(` cannot be treated
as ordinary quoted tokens by bypassing the reader in `char`.

## Choose your next check

For phase mistakes, reconstruct S8-01 with the source hidden. For address
mistakes, redraw the entry and system cells separately. For a displacement
mistake, calculate the final destination from the emitted distance rather
than trusting the intermediate arithmetic.

After intervening work, try the live-cursor changed case and explain why
it needs a runtime fetch. Then recover the `lit` layout from only its
calling contract. A successful worked trace, an independent reconstruction,
and a later reconstruction are different checks; this companion provides
opportunities for them without claiming that they have already happened.
