# Chapter 11 — Control-Flow Combinators (the climax of Part I)

> **Status:** stub.  All nine combinator definitions are below as
> canonical source.  This is the longest chapter in Part I and the
> conceptual climax: by the end the reader understands that
> `if`/`then`/`else`/`begin`/`while`/`repeat` are *not language
> keywords* — they are sixty lines of user code that emit machine
> instructions at compile time.

## Goal

By the end of this chapter the reader can:

- explain how the seed's `branch` and `0branch` primitives consume an
  inline 8-byte target cell that follows their CALL site;
- compute the `rel32` offset for an x86-64 CALL by hand and verify
  that `comma-call` produces the same bytes;
- trace `if, ... then,` end-to-end: the bytes emitted, the stack
  state at compile time, the fixup, and the runtime control flow;
- write a new immediate combinator (e.g. `do, ... loop,` or
  `case, ... endcase,`) in the same idiom.

## Source coverage

`010-lib.fth` lines 194–290.  Nine definitions plus a long block
header that documents the calling convention:

| Word | Role | File line |
|---|---|---|
| `branch-xt` | constant holding the xt of seed `branch` | 231 |
| `0branch-xt` | constant holding the xt of seed `0branch` | 232 |
| `comma-call` | emit a 5-byte CALL to an absolute target | 239 |
| `if,` | forward branch + reserved slot, returns fixup | 247 |
| `then,` | patch a forward-branch fixup to current HERE | 256 |
| `else,` | unconditional forward jump + patch prior if, fixup | 263 |
| `begin,` | mark loop top (just records HERE) | 273 |
| `while,` | conditional loop-exit + fixup | 279 |
| `repeat,` | unconditional backward jump + patch while, fixup | 286 |

## Concepts introduced

- **Inline target cells.**  The seed's `branch` reads its destination
  from the 8 bytes that *follow* the CALL site, not from the data
  stack.  This is unusual; most VMs put branch targets on the stack.
- **The xt (execution token) idiom.**  `' word` (tick) at load time
  resolves the address of a word's body; `constant` captures it.  This
  is how `branch-xt` stays correct across `000-seed.hex0` layout
  changes.
- **Compile-time stack discipline.**  Every immediate combinator
  manipulates the stack *while the user's word is being compiled*.
  `if,` leaves a fixup; the matching `then,` consumes it.  Unbalanced
  combinators corrupt the data stack at compile time, which is
  spectacular.
- **`rel32` and the +4 quirk.**  For an x86-64 CALL, `rel32 = target -
  (HERE_after_opcode + 4)`.  The codebase's comment "HERE_now + 4"
  bakes the opcode-already-written assumption into the formula; trace
  this carefully.
- **The `immediate` flag.**  All nine combinators end with the word
  `immediate`, which sets the flag bit on the most-recently-defined
  dictionary entry (see Ch 10).  An immediate word runs *at compile
  time* even inside `:` ... `;`.

## Concepts carried in

- `c,` (Ch 2) — every combinator ultimately calls it.
- `,4` (Ch 9) — `comma-call` uses it for the 4-byte rel32.
- `,` ("comma," cell-sized writer) — used by `if,`, `while,`,
  `repeat,` to reserve / emit 8-byte cells.  Defined by the seed; see
  Part II, Ch 17.
- `constant` and `immediate` (Ch 10).
- `here` / `here-addr` (Ch 2) — for measuring "where are we?"
- `swap`, `dup`, `drop` — stack work, Chs 1, 8.

## Concepts deferred

- The seed's `branch`, `0branch`, and `'` primitives in machine code —
  Part II, Chs 18 and 19.
- The full ELF + memory layout that makes absolute target addresses
  work — Part II, Ch 13.

## Section plan

1. **The big picture: `if` is not a keyword.**  Open with the
   surprise.  In C, `if` is a token the parser knows about.  In Forth,
   `if,` is a 4-line word that emits a CALL and an 8-byte slot.  No
   parser involvement.  No special case in the compiler.
2. **The seed's branch primitives, in one paragraph.**  Just enough to
   set up the convention: `CALL <branch_or_0branch>` followed by 8
   bytes that name the target.  Full machine-code treatment waits for
   Ch 19.
3. **`branch-xt` and `0branch-xt`: a load-time snapshot.**  Why we use
   `' branch constant branch-xt` instead of inlining `0x5E2`.
4. **`comma-call`: the rel32 calculator.**  Walk the two-line body.
   Show on paper that for HERE = X and target T, rel32 = T − (X + 4).
   Compare with running `gforth -e "see comma-call"` (it won't show
   our seed's version, but the exercise of computing the offset is the
   same).
5. **Forward branches: `if,` and `then,` as a pair.**
   - `if,` emits `CALL 0branch`, then *reserves* 8 bytes with `[lit] 0
     ,`, and *returns the address of those 8 bytes* on the data
     stack as a fixup.
   - `then,` pops the fixup, fetches the current HERE, stores HERE
     into the slot.
   - Trace a single `: foo  flag if, [lit] 10 then, ;` byte by byte.
6. **`else,`: chained fixups.**  This is the cleverest of the nine.
   It emits an unconditional CALL+slot to jump *over* the else-arm,
   then *patches the previous `if,` fixup* to point at the start of
   the else-arm.  The result is that the else-arm runs only when the
   if-branch was taken (skipping the unconditional jump).
7. **Backward loops: `begin,` / `while,` / `repeat,`.**  `begin,` is
   a one-liner: it just records HERE.  `while,` is like `if,` but the
   fixup it leaves under the back-target.  `repeat,` emits an
   unconditional `CALL branch` followed by the back-target *as a
   literal cell* (no fixup), then patches the `while,` fixup to
   land past the unconditional jump.
8. **A worked example end to end.**  Take a small loop:
   ```forth
   : count-down  begin, dup [lit] 0 > while,
                   dup . [lit] 1 -
                 repeat, drop ;
   ```
   Show every byte emitted at compile time.  Show the stack state at
   each combinator.  Show what `count-down` looks like as a sequence
   of machine instructions.
9. **The reveal.**  Sixty lines of Forth implement structured
   programming.  No parser change.  No new VM opcodes.  Just immediate
   words that emit `branch` and `0branch` calls with inline targets.
   *This is the moment Forth becomes self-extensible.*  Any control
   construct you can imagine (case/of, switch, exception, generator)
   is now a 30-line file away.

## Canonical source

```forth file=010-lib.fth

\ ===== Control-flow combinators =====
\ Compile-time helpers that emit calls to the seed's `branch` and `0branch`
\ primitives, plus inline 8-byte target slots, structured per traditional
\ Forth idiom (begin/until/again/while/repeat/if/else/then).
\
\ The seed's branch/0branch primitives work with inline 8-byte target cells.
\ Their x86 machine code is:
\     pop rax           ; rax = return address = address of inline slot
\     mov rax, [rax]    ; rax = contents of slot = branch destination
\     push rax          ; push destination as new return address
\     ret               ; "return" to destination (indirect jump)
\
\ zbranch_code is the same except it first inspects TOS (in rdi/rdx) and
\ either loads the slot (branch taken) or skips past it (fall through).
\
\ This means the combinators must emit a 5-byte CALL rel32 followed
\ immediately by an 8-byte absolute target address.  The CALL lands
\ inside branch_code / zbranch_code which pop their own return address
\ (pointing at the slot), dereference it, and jump.
\
\ The slot is thus "consumed" — it does NOT remain on the return stack.
\ backward branches simply emit the back-target cell; forward branches
\ reserve a slot, return its address as a fixup, and patch it later.
\
\ slot-layout for a forward branch (e.g. if, ... then,):
\     E8 xx xx xx xx    ; CALL rel32 -> 0branch_code
\     <8-byte slot>     ; initially 0, patched by then, to target HERE
\ After CALL, rax -> slot; zbranch_code tests flag, either:
\   - flag==0: mov rax,[rax] -> load slot -> push -> ret to target
\   - flag!=0: add rax,8    -> skip slot -> push -> ret past slot
\
\ Names end in `,` per Forth-asm convention ("emits code") and to keep them
\ distinct from any plain runtime `if`/`then` words.
\
\ branch-xt / 0branch-xt — the xts of the seed's `branch` and `0branch`
\ primitives, captured via `'` at load time so any 000-seed.hex0 layout change
\ is automatically tracked.
' branch  constant branch-xt
' 0branch constant 0branch-xt

\ comma-call ( target -- )  Emit a 5-byte x86-64 CALL to absolute `target`
\ at HERE.  rel32 = target - (HERE + 5).  After `[lit] 232 c,` advances
\ HERE by 1, HERE points at the rel32's first byte and HERE+4 points just
\ past the 5-byte CALL — so rel32 = target - (HERE_now + 4).
\ Kept here so the control-flow combinators do not need another assembler layer.
: comma-call
  [lit] 232 c,                 \ 0xE8 CALL opcode
  here [lit] 4 + - ,4 ;        \ rel32 = target - (HERE+4); emit 4 LE bytes

\ if, ( -- fixup )  At compile time: emit `CALL 0branch` + reserved 8-byte
\ target slot.  Returns the slot's address as a fixup for `then,` or `else,`.
\ Runtime semantics: pops a flag; if flag = 0, jumps to the patched target
\ (the matching `then,`/`else,`'s HERE).  If flag is non-zero, falls through.
: if,
  0branch-xt comma-call
  here                         \ slot address, returned as fixup
  [lit] 0 ,                    \ reserve 8 bytes (` ,` emits a cell)
;
immediate

\ then, ( fixup -- )  Patch the fixup slot to current HERE so the matching
\ if,/while,/else, jumps here when its branch is taken.
: then,
  here swap ! ;
immediate

\ else, ( fixup-if -- fixup-else )  Emit unconditional `CALL branch` + slot
\ to leap over the else-arm; patch the if-fixup to land at the start of the
\ else-arm; return the new (else-arm-end) fixup for `then,` to patch.
: else,
  branch-xt comma-call
  here                         \ start of new (else-end) target slot
  [lit] 0 ,                    \ reserve 8 bytes
  swap                         \ ( fixup-else fixup-if )
  here swap !                  \ patch fixup-if -> just past unconditional branch
;
immediate

\ begin, ( -- back-target )  Mark the top of a loop; just records HERE.
: begin,  here ;
immediate

\ while, ( back-target -- back-target fixup )  Test flag, exit loop if false.
\ Emits `CALL 0branch` + reserved slot; returns the slot addr as the loop-exit
\ fixup, leaving back-target underneath for repeat,.
: while,
  0branch-xt comma-call
  here [lit] 0 , ;
immediate

\ repeat, ( back-target fixup -- )  Emit unconditional jump back to begin-target;
\ patch the loop-exit fixup to land just past it.
: repeat,
  swap branch-xt comma-call ,  \ unconditional `CALL branch` + back-target cell
  here swap !                  \ patch loop-exit fixup -> just-past-repeat
;
immediate

```

## Try it

These words use seed-specific machinery (`'`, `,`, the in-line branch
slots) that the gforth playground does not reproduce.  This is the
first chapter in Part I where the playground stops being sufficient
and you need a built seed-forth.

```sh
git submodule update --init --recursive
./build.sh         # the 2,040-byte seed
./test.sh          # exercises if, / then, via test-010-lib.fth
```

Read `test-010-lib.fth` once you have it building.  Search for `if,`
and `begin,` — the assertions will give you stack pictures at each
combinator.

## Exercises

1. **Hand-compile.** Trace what bytes `: pick-or-go  flag if, [lit] 1
   else, [lit] 2 then, ;` emits.  Confirm both branches end at the
   same address.

2. **The `+4` quirk.** Show on paper that `rel32 = target - (HERE_now
   + 4)` where `HERE_now` is the HERE pointer *after* `[lit] 232 c,`
   has advanced past the opcode byte.  Where does the `+4` come from?

3. **Add a combinator.** Write `again, ( back-target -- )` which emits
   an unconditional backward jump.  It is the simplest member of this
   family — three lines.

4. **Add a real control structure.** Implement `do, ( limit start --
   loop-ctx )` and `loop, ( loop-ctx -- )` that count `start` up to
   `limit-1`, leaving the current count accessible via a new word `i`.
   Solutions vary in how they store the loop variables — return stack
   or a private cell.  Compare yours to the classical Forth `do/loop`
   convention.

5. **The xt question.** Why does this chapter use `' branch constant
   branch-xt` instead of a literal address?  What would have to change
   in `000-seed.hex0` for the literal-address version to break?

## Takeaways

- `if`, `then`, `else`, `begin`, `while`, `repeat` are user code, not
  language built-ins.  They are immediate words that emit `branch`
  and `0branch` CALL instructions with inline 8-byte target slots.
- A *fixup* is the address of a reserved branch slot.  Forward
  combinators leave fixups on the data stack at compile time;
  matching combinators consume them and patch in the resolved target.
- This is the moment Forth becomes self-extensible.  Every control
  construct in this codebase from here forward — and in the C
  compiler in Part III — uses or extends these nine words.

Next: Chapter 12 — `allot`, `create`, `variable`, `bytes-eq`, where
the last 80 lines of `010-lib.fth` complete the defining-word
machinery and add the first non-trivial byte-string operation.
