# Chapter 11 — Control-Flow Combinators (the climax of Part I)

```text
Missing capability: no if/else/while available at the Forth library level.
New pattern: emit a branch placeholder, push the patch offset on the data stack, patch when target is known.
Artifact after this chapter: if,, then,, else,, begin,, while,, repeat,, and the rest of the set.
Proof link: the seed-level rehearsal of emit-remember-patch — the pattern the C compiler reuses in Ch 30.
```

This is the chapter Part I has been building toward: nine immediate
words in `010-lib.fth` (lines 194–290) that give us `if,`/`then,`/
`else,` and `begin,`/`while,`/`repeat,` without a single new line of
machine code.  Every combinator is just `c,` (Ch 2), `,4` (Ch 9),
and `,` running at compile time, emitting a 5-byte CALL to the seed's
`branch` or `0branch` primitive followed by an inline 8-byte target
cell; the stack picture left behind by each one is a *fixup* that
its partner patches when the matching keyword is parsed.  Open
`010-lib.fth` to lines 194–290, with `branch`'s inline-cell calling
convention — spelled out in the comment block of the Canonical source
below — in mind.

By the end you'll be able to explain how `branch` and `0branch` read
their destinations from the 8 bytes that follow their CALL site,
compute an x86-64 CALL's `rel32` offset by hand and check it against
`comma-call`'s output, and trace `if, ... then,` end-to-end through
emitted bytes, compile-time stack, fixup, and runtime jump.  The
machine code of `branch`, `0branch`, and `'` themselves is deferred
to Part II Chs 17 and 19; the ELF layout that makes absolute target
addresses work is Ch 13, two chapters away.

---

```
        ,_,
   __(@___)___    "sixty lines of Forth that change how you read
   ~~~~~~~~~~~~    the rest of the book.  take your time."
```

## 1. The big picture: `if` is not a keyword

If you've written a parser before, you have a mental model of how
control flow works.  The parser recognises `if` as a special token,
matches the `then` or `else` that follows, builds an AST node for
the conditional, and the code generator turns that node into branch
instructions.  Six places in the compiler know about `if`.

Forth doesn't work that way.  In Forth, **`if`** — or here,
`if,` — **is a word**, defined in user code, sixty lines from the
top of `010-lib.fth`.  It is no more privileged than `dup` or
`emit`.  When the seed sees `if,` inside a `:` ... `;`, it does
exactly what it would do for any other word: look it up, run it.
The only difference is that `if,` is marked IMMEDIATE (Ch 10), so
it runs *now*, at parse time, instead of being compiled into the
word being defined.

What does `if,` do when it runs?  It writes bytes into HERE.
Specifically, a five-byte CALL instruction targeting the seed's
`0branch` primitive, followed by eight reserved bytes for the
branch target, and leaves the address of those eight bytes on the
data stack as a *fixup*.  The matching `then,` later reads HERE,
stores it into the fixup slot, and — voilà — a conditional jump.

There is no special case in the compiler.  There is no parser
involvement.  Sixty lines of Forth implement every control
structure in this codebase.  The C compiler in Part III piggybacks
on the same machinery.

This is the conceptual climax of Part I.  By the end of the
chapter, you'll have read the bytes that make it work.

## 2. The seed's branch primitives, in one paragraph

`branch` and `0branch` are seed primitives.  Their calling
convention is unusual: they don't take their target from the data
stack.  Instead, when their machine code runs, they pop the *return
address* from the call stack — which by x86 calling convention
points at the byte just after the CALL that invoked them — and use
*that* address to read 8 bytes from memory.  Those 8 bytes are the
target.  `branch` jumps to it unconditionally; `0branch` jumps to
it if the top of the data stack is zero, otherwise it adds 8 to
its return address to skip past the target slot and resumes
execution there.

The full machine-code treatment is Ch 19.  For this chapter, treat
the convention as a black box: **emit a 5-byte `CALL branch` or
`CALL 0branch`, then emit 8 bytes of target address right after.**
At runtime, the primitive reads those 8 bytes and jumps.

## 3. `branch-xt` and `0branch-xt`: a load-time snapshot

```forth
' branch  constant branch-xt
' 0branch constant 0branch-xt
```

`'` (tick) is a seed primitive that reads the next token from input
and pushes the address of that word's body — its **execution
token**, or *xt*.  `' branch` pushes the body-address of the seed's
`branch` primitive.  We then call `constant` (Ch 10) to capture
that address into a Forth-level name `branch-xt`.

The whole point is to avoid hard-coded addresses.  The seed
binary's layout — where exactly `branch` lives in memory — could
change as `000-seed.hex0` is edited.  Instead of writing `[lit] 1506
constant branch-xt` and updating that number every time the seed
moves, we let `'` resolve the address at load time.  Subsequent
edits to the seed don't require touching `010-lib.fth`.

This is the canonical Forth answer to "how do I reference a thing
whose address I don't know yet?"  Capture it by name, at the
earliest moment the name resolves, and use the captured value
thereafter.

## 4. `comma-call`: the rel32 calculator

x86-64 CALL takes a 32-bit *relative* offset.  The CPU computes
`rip = rip + rel32` at execution time, where `rip` already points
past the CALL instruction.  To make `CALL` land on `target`, we
need:

```
rel32 = target - (address-just-after-CALL)
      = target - (HERE_at_start_of_CALL + 5)
```

The `5` is the size of the CALL instruction: 1 byte for opcode
`0xE8` plus 4 bytes of rel32.

```forth
: comma-call
  [lit] 232 c,                 \ 0xE8 CALL opcode
  here [lit] 4 + - ,4 ;        \ rel32 = target - (HERE+4); emit 4 LE bytes
```

The body has a subtle bookkeeping move.  After `[lit] 232 c,` emits
the opcode byte, HERE has *already advanced by one*.  So at the
moment we compute the offset, HERE points at the *first byte of the
rel32 field*.  Adding 4 to it gives the address just past the
4-byte rel32, which is the same as the address just past the whole
5-byte CALL — exactly the base the CPU will use at execution time.

So `target - (HERE_now + 4)` is the right value.  Then `,4` emits
its low 4 bytes in little-endian order (Ch 9), and the 5-byte CALL
is complete.

Pulling out the "+4 quirk": that 4 (rather than 5) is the
fingerprint of "the opcode byte has already been written."  If you
wrote `here [lit] 5 + -`, you'd be assuming the opcode hasn't been
written yet — and you'd land one byte off.  Make sure you trace
this on paper at least once.

## 5. Forward branches: `if,` and `then,` as a pair

```forth
: if,
  0branch-xt comma-call
  here                         \ slot address, returned as fixup
  [lit] 0 ,                    \ reserve 8 bytes
;
immediate

: then,
  here swap ! ;
immediate
```

`if,` does three things:

1. **`0branch-xt comma-call`** — emit a 5-byte CALL targeting the
   seed's `0branch` primitive.  After this, HERE has advanced by 5.
2. **`here`** — push the current HERE on the data stack.  This is
   the address where the 8-byte target slot is about to be reserved.
3. **`[lit] 0 ,`** — write 8 zero bytes at HERE (`,` is the
   seed-provided cell-writer; for now, accept that it works like a
   single `,8` of zero).  HERE advances by 8 more.

After `if,` finishes, the stack has one new entry: the address of
the 8-byte slot we just zeroed.  This is the **fixup**.  We need to
go back and patch it later.

This is the book's first full **emit, remember, patch** sequence:
emit bytes now, remember the unresolved slot, patch the slot when
the target becomes knowable.

`then,` is the patcher.  Its body is two tokens:

| token  | stack            | reasoning                       |
|--------|------------------|---------------------------------|
| (in)   | `fixup`          |                                 |
| `here` | `fixup HERE`     | fetch the current HERE          |
| `swap` | `HERE fixup`     | put fixup on top for `!`        |
| `!`    | empty            | store HERE into the 8-byte slot |

After `then,`, the 8-byte slot at `fixup` contains the current
HERE.  At runtime, if the flag passed to `0branch` was zero, the
primitive reads those 8 bytes and jumps to that address — which is
exactly where the user's code resumed after `then,`.  Conditional
forward branch achieved.

Trace a tiny example.  `: maybe  if, [lit] 65 emit then, ;` where
the caller pushes a flag.  `[lit] 65` compiles to `CALL lit` (5 bytes)
plus the inline 8-byte cell holding 65 — 13 bytes in all — and `emit`
compiles to a 5-byte `CALL`.  So the byte stream HERE accumulates is:

```
[at HERE+0]   E8 ?? ?? ?? ??               ; CALL 0branch (rel32, patched by if,)
[at HERE+5]   ?? ?? ?? ?? ?? ?? ?? ??      ; 8-byte target slot (zero-filled)
[at HERE+13]  E8 ?? ?? ?? ?? <8-byte cell> ; CALL lit + literal 65 (13 bytes)
[at HERE+26]  E8 ?? ?? ?? ??               ; CALL emit (5 bytes)
[at HERE+31]  then, patches the slot at HERE+5 to contain HERE+31]
```

If the flag is zero at runtime, `0branch` reads the slot at HERE+5
(which `then,` filled with the address HERE+31, just past `emit`) and
jumps there — skipping the `[lit] 65 emit` entirely.  If the flag is
non-zero, `0branch` skips its own slot and falls through into the
literal-push and emit.

## 6. `else,`: chained fixups

```forth
: else,
  branch-xt comma-call
  here                         \ start of new (else-end) target slot
  [lit] 0 ,                    \ reserve 8 bytes
  swap                         \ ( fixup-else fixup-if )
  here swap !                  \ patch fixup-if -> just past unconditional branch
;
immediate
```

`else,` is the cleverest of the nine words.  At entry, the data
stack has the **fixup-if** from the matching `if,`.  At exit, the
stack has a *new* **fixup-else**, which the matching `then,` will
patch.

Mechanically:

1. **`branch-xt comma-call`** — emit an unconditional CALL to
   `branch`, the leap-over-else-arm.
2. **`here [lit] 0 ,`** — reserve a fresh 8-byte slot for the
   unconditional branch's target, and remember its address (the new
   fixup).
3. **`swap`** — bring the old fixup-if to the top.
4. **`here swap !`** — patch fixup-if so the `0branch` lands
   *here*, at the start of the else-arm (just past the
   unconditional branch we just emitted).

So when control reaches the `0branch` at runtime:
- if flag was zero, jump to the start of the else-arm (just past
  the unconditional `branch`);
- if flag was non-zero, fall through into the if-arm, then hit the
  unconditional `branch` which jumps over the else-arm.

After the user types the else-arm body and then `then,`, the
fixup-else is patched to HERE — landing past the end of the
else-arm.  Both arms converge at the same address.

Read this twice.  The trick is that `else,` does *two* fixups: it
both patches the previous one and emits a new one.

## 7. Backward loops: `begin,` / `while,` / `repeat,`

```forth
: begin,  here ;             immediate
: while,
  0branch-xt comma-call
  here [lit] 0 , ;            immediate
: repeat,
  swap branch-xt comma-call ,  \ unconditional `CALL branch` + back-target cell
  here swap !                  \ patch loop-exit fixup -> just-past-repeat
;
immediate
```

`begin,` is a one-liner.  It just records HERE as the *back-target*
— the address loop iterations will jump back to.  No code is
emitted.

`while,` is identical to `if,` in mechanism: emit `CALL 0branch`
and reserve an 8-byte fixup slot.  The semantics: at runtime, pop a
flag; if zero, jump to the patched target (loop-exit).  The
back-target from `begin,` stays underneath the new fixup on the
data stack.

`repeat,` is the loop-closer.  Its first line is the trickiest in
the chapter:

```
swap branch-xt comma-call ,
```

At entry the stack is `( back-target fixup-exit )`.  `swap` makes
it `( fixup-exit back-target )`.  `branch-xt comma-call` emits the
unconditional CALL: `comma-call` pops only the `branch-xt` it was
just handed, so afterward the stack is `( fixup-exit back-target )`
again — but now HERE has advanced past the CALL.  Then `,` (the
cell-writer) pops `back-target` and writes
its 8 bytes at HERE — that's the back-target *cell*, the absolute
address the unconditional `branch` will read at runtime.

Now the stack is `( fixup-exit )`, and HERE is just past the 13-byte
(5 + 8) unconditional-backward-jump.  The second line:

```
here swap !
```

is the same pattern as `then,`: store HERE into the fixup-exit
slot.  When the loop body runs and `while,`'s flag is zero, the
`0branch` reads that slot and jumps just past the unconditional
back-jump — i.e., out of the loop.

Net: `begin, BODY while, BODY repeat,` compiles to a backward jump
at the bottom with a forward-bailout fixup at the top, classical
post-test loop with mid-body exit.

## 8. A worked example end to end

Compile this:

```forth
: cnt
  begin, dup [lit] 0 > while,
    dup [lit] 48 + emit [lit] 1 -
  repeat, drop ;
```

Walk every combinator.  Recall the byte budget per compiled token:
each ordinary word compiles to a 5-byte `CALL`, and `[lit] N`
compiles to `CALL lit` (5 bytes) plus an 8-byte cell holding `N` —
13 bytes total.

1. `:` parses the name `cnt`, builds the dictionary header, sets
   STATE=1.  HERE is at the start of `cnt`'s body — call it `B`.
2. `begin,` runs immediately: pushes `B` to the data stack.  Stack: `( B )`.
3. `dup [lit] 0 >` is compiled normally — `dup` (5) + `[lit] 0` (13)
   + `>` (5) = 23 bytes.  Now HERE = `B+23`.
4. `while,` runs immediately.  Stack on entry: `( B )`.
   - `0branch-xt comma-call` emits 5 bytes.  HERE = `B+28`.
   - `here [lit] 0 ,` pushes `B+28` (the address of the fixup slot)
     and reserves 8 bytes for the slot.  HERE = `B+36`.
   - Stack: `( B B+28 )` — back-target, then loop-exit fixup.
5. `dup [lit] 48 + emit [lit] 1 -` compiles to 5 + 13 + 5 + 5 + 13 +
   5 = 46 bytes.  HERE = `B+82`.
6. `repeat,` runs immediately.  Stack on entry: `( B B+28 )`.
   - `swap` → `( B+28 B )`.
   - `branch-xt comma-call` emits 5 bytes (HERE = `B+87`); the stack
     is back to `( B+28 B )` because `comma-call` consumed the
     `branch-xt` it had just pushed.
   - `,` pops `B` and writes its 8 bytes as the back-target cell.
     HERE = `B+95`.  Stack: `( B+28 )`.
   - `here swap !` — stores `B+95` into the slot at `B+28`.  Stack:
     `( )`.
7. `drop` compiles normally — emits a 5-byte CALL.  HERE = `B+100`.
8. `;` closes the definition with a `ret`, sets STATE=0.

At runtime, with `5` on the stack and a call to `cnt`:
- iteration 1: dup → `(5 5)`; push 0 → `(5 5 0)`; `>` → `(5 -1)`;
  `while,`'s `0branch` sees non-zero, falls through; emit `'5'`;
  decrement → `(4)`; `repeat,`'s `branch` jumps back to `B`.
- iterations 2..5: same, emitting `4 3 2 1`.
- iteration 6: dup → `(0 0)`; push 0 → `(0 0 0)`; `>` → `(0 0)`;
  `while,`'s `0branch` sees zero, jumps out.  Falls past `drop`.
- `drop` consumes the remaining `0`.  `;` returns.

Output: `54321`.  Verified by the Try-it below.

## 9. The reveal

Sixty lines of Forth implement structured programming.  No parser
change.  No new VM opcodes.  Just immediate words that emit
`branch` and `0branch` calls with inline 8-byte target slots.

**This is the moment Forth becomes self-extensible.**

```
       __
   __( o)>   "told you `if` is a word.  thirty lines.  no keywords."
   \___/
```

Any control construct you can imagine — `case`/`of`, `switch`,
exception unwinding, generators, even multi-level exits — is now a
thirty-line file away.  You'd open `010-lib.fth`, add a couple of
immediate words that emit branches in a new pattern, and the user
language has a new keyword.

The C compiler in Part III uses these combinators directly to
implement `if`, `else`, `while`, and `for` in the *generated* code.
And inside its own implementation, it uses them in the *generating*
code.  The same nine words wear both hats.

If you've ever wondered what people mean when they say Forth is "a
programmable programming language," this is exactly what they
mean.  No metaclasses, no macros, no AST manipulation — just a
mode flag, a flag bit, and `c,`.

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
slots) that the gforth playground does not reproduce.  The Try-it
snippets below run against a built seed-forth.

Forward branch with else-arm:

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo ': pick  if, [lit] 65 else, [lit] 66 then, emit ;'
  echo '[lit] 1 pick'      \ flag non-zero -> if-arm  -> "A"
  echo '[lit] 0 pick'      \ flag zero     -> else-arm -> "B"
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

Expected: `AB`.

Counting loop (the worked example from section 8):

```sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo ': cnt  begin, dup [lit] 0 > while, dup [lit] 48 + emit [lit] 1 - repeat, drop ;'
  echo '[lit] 5 cnt'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

Expected: `54321`.

`./test.sh` exercises both patterns via `test-010-lib.fth` if you'd
rather see them inside a larger battery.

## Exercises

1. **★★ Trace.** Hand-compile the bytes that `: pick-or-go  flag if, [lit] 1
   else, [lit] 2 then, ;` emits.  Confirm both branches end at the
   same address.

2. **★★ Trace.** Show on paper that `rel32 = target - (HERE_now + 4)` where
   `HERE_now` is the HERE pointer *after* `[lit] 232 c,` has advanced
   past the opcode byte.  Where does the `+4` come from?

3. **★★ Extend.** Write `again, ( back-target -- )` which emits an unconditional
   backward jump.  It is the simplest member of this family — three
   lines.

4. **★★★ Extend.** Add a real control structure: implement `do, ( limit start --
   loop-ctx )` and `loop, ( loop-ctx -- )` that count `start` up to
   `limit-1`, leaving the current count accessible via a new word `i`.
   Solutions vary in how they store the loop variables — return stack
   or a private cell.  Compare yours to the classical Forth `do/loop`
   convention.

5. **★★ Trace.** Why does this chapter use `' branch constant branch-xt`
   instead of a literal address?  What would have to change in
   `000-seed.hex0` for the literal-address version to break?

## Takeaways

- `if`, `then`, `else`, `begin`, `while`, `repeat` are user code, not
  language built-ins.  They are immediate words that emit `branch`
  and `0branch` CALL instructions with inline 8-byte target slots.
- A *fixup* is the address of a reserved branch slot.  Forward
  combinators leave fixups on the data stack at compile time;
  matching combinators consume them and patch in the resolved target.
- The durable pattern is emit, remember, patch: write incomplete
  bytes now, carry the address of the missing value, and fill it in
  when the later word knows the target.
- This is the moment Forth becomes self-extensible.  Every control
  construct in this codebase from here forward — and in the C
  compiler in Part III — uses or extends these nine words.

Next: Chapter 12 — `allot`, `create`, `variable`, `bytes-eq`, where
the last 80 lines of `010-lib.fth` complete the defining-word
machinery and add the first non-trivial byte-string operation.
