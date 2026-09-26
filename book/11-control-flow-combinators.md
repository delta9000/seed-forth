# Chapter 11 — Control-Flow Combinators (the climax of Part I)

```text
Missing capability: no if/else/while available at the Forth library level.
New pattern: emit a branch placeholder, push the patch offset on the data stack, patch when target is known.
Artifact after this chapter: if,, then,, else,, begin,, while,, repeat,, until,, again,, and exit,.
Proof link: the seed-level rehearsal of emit-remember-patch — the pattern the C compiler reuses in Ch 30.
```

The library can compare, classify, and assemble machine code, and it
still cannot make a decision.  Every word runs straight through from
its first token to its `ret`.  The seed provides two jump
primitives, `branch` and `0branch`, but its parser has no `if`, and
the parser is hex that nobody is going to edit.  Yet the C compiler
in Part III contains hundreds of `if,`s.  Where do they come from?

`010-lib.fth` lines 265–372 fill that gap with eleven words, nine
of them immediate: `if,`/`then,`/`else,`, `begin,`/`while,`/`repeat,`,
the loop closers `until,` and `again,`, and `exit,`, plus two
constants holding the primitives' addresses.  None of them adds
machine code to the seed.  Each runs at compile time, writes a
5-byte CALL to `branch` or `0branch` followed by an 8-byte target
cell, and leaves the cell's address on the stack for its partner to
patch.  The machine code of
`branch`, `0branch`, and `'` is Chs 17 and 19.

## 1. The big picture: `if` is not a keyword

In most compilers the parser recognises `if` as a special token,
builds an AST node for the conditional, and the code generator turns
that node into branch instructions.  Every stage knows about `if`.

Forth doesn't work that way.  In Forth, **`if`** (here spelled
`if,`) **is a word**, defined in user code, two-thirds of the way
down `010-lib.fth`.  It is no more privileged than `dup` or
`emit`.  When the seed sees `if,` inside a `:` ... `;`, it does
exactly what it does for any other word: looks it up in the
dictionary.  The only difference is that `if,` is marked IMMEDIATE
(Ch 10), so it runs *now*, at parse time, instead of being compiled
into the word being defined.

What does `if,` do when it runs?  It writes bytes at HERE.
Specifically, a five-byte CALL instruction targeting the seed's
`0branch` primitive, followed by eight reserved bytes for the
branch target, and leaves the address of those eight bytes on the
data stack as a *fixup*.  The matching `then,` later reads HERE and
stores it into the fixup slot, which completes a conditional jump.

There is no special case in the compiler and no parser involvement.
`if` is a few dozen lines of library code away from existing, and
the rest of this chapter writes them.

## 2. The seed's branch primitives in brief

`branch` and `0branch` are seed primitives.  Their calling
convention is unusual: they don't take their target from the data
stack.  Instead, when their machine code runs, they pop the *return
address* from the call stack (which by x86 calling convention
points at the byte just after the CALL that invoked them) and use
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

The combinators need the addresses of those two primitives, so the
library looks them up once, at load time:

```forth
' branch  constant branch-xt
' 0branch constant 0branch-xt
```

`'` (tick) is a seed primitive that reads the next token from input
and pushes the address of that word's body: its **execution
token**, or *xt*.  `' branch` pushes the body-address of the seed's
`branch` primitive.  We then call `constant` (Ch 10) to capture
that address into a Forth-level name `branch-xt`.

The point is to avoid hard-coded addresses.  Where `branch` lives
in memory can change whenever `000-seed.hex0` is edited.  Instead
of writing `[lit] 4195857 constant branch-xt` (today's `0x400611`)
and updating that number every time the seed moves, we let `'`
resolve the address at load time.  Subsequent edits to the seed
don't require touching `010-lib.fth`.

## 4. `call,`: emitting the CALL

Every combinator emits its CALL with Ch 10's `call,` ( target -- ),
which lays down `E8` and the rel32 that makes the CALL land on
`target`.  Given `branch-xt` or `0branch-xt`, that is a CALL into
the branch primitive, and the 8-byte cell the combinator writes next
is the one the primitive will read.

## 5. Forward branches: `if,` and `then,` as a pair

With `call,` in hand, the forward-branch pair is short:

```forth
: if,
  0branch-xt call,
  here                         \ slot address, returned as fixup
  [lit] 0 ,                    \ reserve 8 bytes
;
immediate

: then,
  here swap ! ;
immediate
```

`if,` does three things:

1. **`0branch-xt call,`** emits a 5-byte CALL targeting the
   seed's `0branch` primitive.  After this, HERE has advanced by 5.
2. **`here`** pushes the current HERE on the data stack.  This is
   the address where the 8-byte target slot is about to be reserved.
3. **`[lit] 0 ,`** writes 8 zero bytes at HERE (`,` is the
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
primitive reads those 8 bytes and jumps to that address, which is
exactly where the user's code resumed after `then,`.

Trace a tiny example.  `: maybe  if, [lit] 65 emit then, ;` where
the caller pushes a flag.  `[lit] 65` compiles to `CALL lit` (5 bytes)
plus the inline 8-byte cell holding 65 (13 bytes in all), and `emit`
compiles to a 5-byte `CALL`.  So the byte stream HERE accumulates is:

```
[at HERE+0]   E8 ?? ?? ?? ??               ; CALL 0branch (rel32 from call,)
[at HERE+5]   ?? ?? ?? ?? ?? ?? ?? ??      ; 8-byte target slot (zero-filled)
[at HERE+13]  E8 ?? ?? ?? ?? <8-byte cell> ; CALL lit + literal 65 (13 bytes)
[at HERE+26]  E8 ?? ?? ?? ??               ; CALL emit (5 bytes)
[at HERE+31]  ; then, runs here: stores HERE+31 into the slot at HERE+5
```

If the flag is zero at runtime, `0branch` reads the slot at HERE+5
(which `then,` filled with the address HERE+31, just past `emit`) and
jumps there, skipping the `[lit] 65 emit` entirely.  If the flag is
non-zero, `0branch` skips its own slot and falls through into the
literal-push and emit.

## 6. `else,`: chained fixups

```forth
: else,
  branch-xt call,
  here                         \ start of new (else-end) target slot
  [lit] 0 ,                    \ reserve 8 bytes
  swap                         \ ( fixup-else fixup-if )
  here swap !                  \ patch fixup-if -> just past unconditional branch
;
immediate
```

`else,` handles two fixups at once.  At entry, the data
stack has the **fixup-if** from the matching `if,`.  At exit, the
stack has a *new* **fixup-else**, which the matching `then,` will
patch.

Mechanically:

1. **`branch-xt call,`** emits an unconditional CALL to
   `branch`, which will leap over the else-arm.
2. **`here [lit] 0 ,`** reserves a fresh 8-byte slot for the
   unconditional branch's target and remembers its address (the new
   fixup).
3. **`swap`** brings the old fixup-if to the top.
4. **`here swap !`** patches fixup-if so the `0branch` lands
   *here*, at the start of the else-arm (just past the
   unconditional branch we just emitted).

So when control reaches the `0branch` at runtime:
- if flag was zero, jump to the start of the else-arm (just past
  the unconditional `branch`);
- if flag was non-zero, fall through into the if-arm, then hit the
  unconditional `branch` which jumps over the else-arm.

After the user types the else-arm body and then `then,`, the
fixup-else is patched to HERE, just past the end of the
else-arm.  Both arms converge at the same address.

## 7. Backward loops: `begin,` / `while,` / `repeat,`

```forth
: begin,  here ;             immediate
: while,
  0branch-xt call,
  here [lit] 0 , ;            immediate
: repeat,
  swap branch-xt call, ,       \ unconditional `CALL branch` + back-target cell
  here swap !                  \ patch loop-exit fixup -> just-past-repeat
;
immediate
```

`begin,` is a one-liner.  It records HERE as the *back-target*,
the address loop iterations will jump back to.  No code is
emitted.

`while,` is identical to `if,` in mechanism: emit `CALL 0branch`
and reserve an 8-byte fixup slot.  The semantics: at runtime, pop a
flag; if zero, jump to the patched target (loop-exit).  The
back-target from `begin,` stays underneath the new fixup on the
data stack.

`repeat,` closes the loop.  Its first line needs a careful stack
trace:

```
swap branch-xt call, ,
```

At entry the stack is `( back-target fixup-exit )`.  `swap` makes
it `( fixup-exit back-target )`.  `branch-xt call,` emits the
unconditional CALL: `call,` pops only the `branch-xt` it was
just handed, so afterward the stack is `( fixup-exit back-target )`
again, but HERE has advanced past the CALL.  Then `,` (the
cell-writer) pops `back-target` and writes its 8 bytes at HERE.
That is the back-target *cell*, the absolute address the
unconditional `branch` will read at runtime.

Now the stack is `( fixup-exit )`, and HERE is just past the 13-byte
(5 + 8) unconditional-backward-jump.  The second line:

```
here swap !
```

is the same pattern as `then,`: store HERE into the fixup-exit
slot.  When the loop body runs and `while,`'s flag is zero, the
`0branch` reads that slot and jumps just past the unconditional
back-jump, out of the loop.

Net: `begin, BODY while, BODY repeat,` compiles to a backward jump
at the bottom with a forward-bailout fixup at the top: a pre-test
loop whose exit test sits wherever you put `while,` (at the top in
the common case, or mid-body).

## 8. `until,`, `again,` and `exit,`

Two more loop closers and one way out complete the set.

```forth
: until,
  0branch-xt call, , ;         \ `CALL 0branch` + back-target cell
immediate

: again,
  branch-xt call, , ;          \ `CALL branch` + back-target cell
immediate

: exit,  ret, ;
immediate
```

`until,` is `repeat,` without the forward half: `begin, BODY until,`
runs BODY, pops a flag, and jumps back to `begin,` while the flag is
0.  The body runs at least once, which is what a loop like "read
the next token, stop when it isn't a comma" wants.  `again,` jumps
back unconditionally.  Neither leaves a fixup, because neither has
a forward exit to patch.

A loop that `again,` closes can only be left by returning, and that
is `exit,`: it compiles Ch 10's `ret,`, a `C3` byte in the middle of
the word being defined.  Every colon word is machine code entered by
`CALL`, so a `ret` anywhere in its body returns to its caller at
once.  The one rule is that the return stack must be as the word
found it: `ret` pops the top of the return stack as the address to
return to, so an `exit,` between `>r` and the matching `r>` must
first take its own value off (`r> drop`).  `if,` and the loops keep
nothing on the return stack; their fixups live on the data stack at
compile time only.

`exit,` retires a pattern that runs through older Forth code: a
search loop that cannot stop early sets a `found` variable and keeps
going, testing the variable on every pass.  With `exit,` it returns
the answer the moment it has one:

```forth
: sign3  dup 0< if, drop [lit] 1 exit, then,
         0= if, [lit] 2 exit, then,  [lit] 3 ;
```

Ch 12's `bytes-eq` is the first library word written this way.

## 9. A worked example end to end

On a first pass you can skim the HERE offsets; the shape is
*back-jump at the bottom, bail-out fixup at the top*.  Compile this:

```forth
: cnt
  begin, dup [lit] 0 > while,
    dup [lit] 48 + emit [lit] 1 -
  repeat, drop ;
```

Walk every combinator.  Recall the byte budget per compiled token:
each ordinary word compiles to a 5-byte `CALL`, and `[lit] N`
compiles to `CALL lit` (5 bytes) plus an 8-byte cell holding `N`,
13 bytes total.

1. `:` parses the name `cnt`, builds the dictionary header, sets
   STATE=1.  HERE is at the start of `cnt`'s body — call it `B`.
2. `begin,` runs immediately: pushes `B` to the data stack.  Stack: `( B )`.
3. `dup [lit] 0 >` is compiled normally: `dup` (5) + `[lit] 0` (13)
   + `>` (5) = 23 bytes.  Now HERE = `B+23`.
4. `while,` runs immediately.  Stack on entry: `( B )`.
   - `0branch-xt call,` emits 5 bytes.  HERE = `B+28`.
   - `here [lit] 0 ,` pushes `B+28` (the address of the fixup slot)
     and reserves 8 bytes for the slot.  HERE = `B+36`.
   - Stack: `( B B+28 )`: back-target, then loop-exit fixup.
5. `dup [lit] 48 + emit [lit] 1 -` compiles to 5 + 13 + 5 + 5 + 13 +
   5 = 46 bytes.  HERE = `B+82`.
6. `repeat,` runs immediately.  Stack on entry: `( B B+28 )`.
   - `swap` → `( B+28 B )`.
   - `branch-xt call,` emits 5 bytes (HERE = `B+87`); the stack
     is back to `( B+28 B )` because `call,` consumed the
     `branch-xt` it had just pushed.
   - `,` pops `B` and writes its 8 bytes as the back-target cell.
     HERE = `B+95`.  Stack: `( B+28 )`.
   - `here swap !` stores `B+95` into the slot at `B+28`.  Stack:
     `( )`.
7. `drop` compiles normally, emitting a 5-byte CALL.  HERE = `B+100`.
8. `;` closes the definition with a `ret`, sets STATE=0.

At runtime, with `5` on the stack and a call to `cnt`:
- iteration 1: dup → `(5 5)`; push 0 → `(5 5 0)`; `>` → `(5 -1)`;
  `while,`'s `0branch` sees non-zero, falls through; emit `'5'`;
  decrement → `(4)`; `repeat,`'s `branch` jumps back to `B`.
- iterations 2..5: same, emitting `4 3 2 1`.
- iteration 6: dup → `(0 0)`; push 0 → `(0 0 0)`; `>` → `(0 0)`;
  `while,`'s `0branch` sees zero, jumps out and lands on `drop`.
- `drop` consumes the remaining `0`.  `;` returns.

Output: `54321`, which the Try-it below reproduces.

## 10. The reveal

Step back and count what just happened.  The seed's parser was not
touched and no primitive was added, yet the language now has
`if`/`else`/`then`, three kinds of loop and early return.  About
forty lines of
immediate words that emit `branch` and `0branch` calls with inline
8-byte target slots implement structured programming.  Forth is now
self-extensible.

Any other control construct (`case`/`of`, counted `do`/`loop`) is a
few immediate words away.

The C compiler in Part III uses these combinators throughout its
own Forth source: every loop and conditional in the *generating*
code is a `begin,` or an `if,`.  The *generated* code is different:
for C's `if`, `while`, and `for`, the compiler emits native x86
`jz`/`jmp` instructions through its own emitter
(`cc-emit-jmp-rel32-placeholder`, `cc-patch-rel32-to-here`).  What
carries over is the pattern, not the words: emit a placeholder,
remember its address, patch it when the target is known.

This is what people mean when they call Forth "a programmable
programming language": no macros and no AST, just a mode flag, a
flag bit, and `c,`.

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

\ if, ( -- fixup )  At compile time: emit `CALL 0branch` + reserved 8-byte
\ target slot.  Returns the slot's address as a fixup for `then,` or `else,`.
\ Runtime semantics: pops a flag; if flag = 0, jumps to the patched target
\ (the matching `then,`/`else,`'s HERE).  If flag is non-zero, falls through.
: if,
  0branch-xt call,
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
  branch-xt call,
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
  0branch-xt call,
  here [lit] 0 , ;
immediate

\ repeat, ( back-target fixup -- )  Emit unconditional jump back to begin-target;
\ patch the loop-exit fixup to land just past it.
: repeat,
  swap branch-xt call, ,       \ unconditional `CALL branch` + back-target cell
  here swap !                  \ patch loop-exit fixup -> just-past-repeat
;
immediate

\ until, ( back-target -- )  Pop a flag; jump back to begin, while it is 0.
\ A post-test loop: begin, BODY until, runs BODY at least once.
: until,
  0branch-xt call, , ;         \ `CALL 0branch` + back-target cell
immediate

\ again, ( back-target -- )  Jump back to begin, unconditionally: a loop
\ that only exit, can leave.
: again,
  branch-xt call, , ;          \ `CALL branch` + back-target cell
immediate

\ exit, ( -- )  Compile a `ret`: return from the word being defined, here.
\ Every colon word is x86 code entered by CALL, so a ret anywhere in its body
\ returns to its caller.  Rule: the return stack must be as the word found
\ it, so an exit, between >r and its r> must first r> (or r> drop) what it
\ pushed.  Loops and if, keep nothing on the return stack, so they are safe.
: exit,  ret, ;
immediate

```

## Try it

These words use seed-specific machinery (`'`, `,`, the in-line branch
slots) that the gforth playground does not reproduce.  The Try-it
snippets below run against a built seed-forth.

Forward branch with else-arm:

```sh
./build.sh
{ cat 010-lib.fth
  echo ': pick  if, [lit] 65 else, [lit] 66 then, emit ;'
  echo '[lit] 1 pick'      # flag non-zero -> if-arm  -> "A"
  echo '[lit] 0 pick'      # flag zero     -> else-arm -> "B"
} | ./seed-forth
```

Expected: `AB`.  One word, two runs, two different paths, chosen by
a word you just read.

Counting loop (the worked example from §9):

```sh
{ cat 010-lib.fth
  echo ': cnt  begin, dup [lit] 0 > while, dup [lit] 48 + emit [lit] 1 - repeat, drop ;'
  echo '[lit] 5 cnt'
} | ./seed-forth
```

Expected: `54321`.  That countdown is a loop the seed's parser has
never heard of, compiled by three library words.

`./test.sh` exercises both patterns via `test-010-lib.fth` if you'd
rather see them inside a larger battery.

## Exercises

1. **★★ Trace.** Hand-compile the bytes that `: pick-or-go  flag if, [lit] 1
   else, [lit] 2 then, ;` emits.  Confirm both branches end at the
   same address.

2. **★★ Trace.** Show on paper that `call,`'s `rel32 = target - (HERE_now + 4)`
   (Ch 10) is right, where `HERE_now` is the HERE pointer *after*
   `[lit] 232 c,` has advanced past the opcode byte.  Where does the
   `+4` come from?

3. **★★ Extend.** Write `?exit, ( flag -- )`, an immediate word that compiles
   "return now if the flag is non-zero".  Build it from the emitters
   `if,`, `exit,` and `then,` are made of, not from those words
   themselves: three lines.

4. **★★★ Extend.** Add a real control structure: implement `do, ( limit start --
   loop-ctx )` and `loop, ( loop-ctx -- )` that count `start` up to
   `limit-1`, leaving the current count accessible via a new word `i`.
   Solutions vary in how they store the loop variables (return stack
   or a private cell).  Compare yours to the classical Forth `do/loop`
   convention.

5. **★★ Trace.** Why does this chapter use `' branch constant branch-xt`
   instead of a literal address?  What would have to change in
   `000-seed.hex0` for the literal-address version to break?

## Takeaways

- `if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,`, `until,`
  and `again,` are immediate library words that emit `branch` and
  `0branch` CALLs with inline 8-byte target slots, not language
  built-ins; `exit,` compiles a `ret` for early return.
- Each forward branch follows emit, remember, patch: reserve a slot,
  leave its address (the *fixup*) on the data stack, and let the
  matching word store the target once it is known.
- Every control structure in the codebase's Forth source, the C
  compiler's included, is built from these combinators.

**Part I tally.**  Built so far: byte emission, Boolean logic,
subtraction, file I/O, character tests, comparisons, shuffles,
multi-byte writes, `constant`, **branches, loops and early
return**.  Still
missing: variables, buffers, string compare.

Next: Chapter 12 — `allot`, `create`, `variable`, `bytes-eq`.  The
library can now decide and loop, but it cannot *remember*: there is
no `variable`, no named buffer, and no way to ask whether two names
are the same, a question the C compiler asks on every identifier.
The last 69 lines of `010-lib.fth` answer all three.
