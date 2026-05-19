# Chapter 19 — Branches and Inline Cells

> **Status:** ✅ complete.  Defines chunks `<<branch-code>>` and
> `<<zbranch-code>>`; bodies match `000-seed.hex0` lines 368–386.

## Goal

By the end of this chapter the reader can:

- read `branch_code` and `zbranch_code` byte for byte;
- explain the "CALL with an inline 8-byte target" convention,
  including the **consumed-slot property** — the target cell does
  *not* remain on the return stack after the branch;
- map each primitive byte to the corresponding Forth-level word in
  `010-lib.fth` (`comma-call`, `if,`, `then,`) that we built in
  Ch 11.

## Source coverage

`000-seed.hex0` `branch_code @ 0x42B` (lines 368–372) and
`zbranch_code @ 0x431` (lines 374–385).  Roughly 30 bytes total.

## Concepts introduced

- **`branch_code` ( -- ).**  Unconditional jump; target is the
  inline 8-byte cell that follows the `CALL` site.
- **`zbranch_code` ( flag -- ).**  Conditional jump; if `flag == 0`
  jump to the inline target, else skip past the 8-byte slot.
- **The "consumed slot" property.**  Both branch primitives `pop`
  the return address (the slot address), do their work, and `push`
  the *new* return address — so when they `ret`, control resumes
  at the destination (or past the slot), and the slot is gone from
  the return stack.  This is what makes the Forth-level `if,/then,`
  combinator a single 13-byte sequence with no separate target
  table.

## Concepts carried in

- The "callee `pop`s its return address" trick from Ch 18's
  `lit_code`.
- The data-stack-and-`rdi` convention from Ch 14.
- The Forth-level combinators `if,/then,/else,/begin,/while,/repeat,`
  from Ch 11 — this chapter is the underlying machinery they emit.

## Concepts deferred

- Nothing new.  The C compiler's back-patching in Part III is the
  same idea applied at a higher level: emit a placeholder, remember
  the address, fill it in later.

---

Ch 11 ended with a complete suite of control-flow combinators —
`if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,` — all defined
in Forth, all emitting some combination of "CALL plus inline cell"
at HERE.  We deferred *what those CALLs land on* until Part II.

This is the chapter where we find out.  The two primitives below,
`branch_code` and `zbranch_code`, are 26 bytes of hex between them.
They implement every loop and conditional in this codebase — the
Forth library, the C compiler, even seed-forth's own REPL doesn't
use them only because the REPL is written in raw hex.

## 1. The compiled shape

A compiled `if,` site looks like this in memory:

```
addr+0:  E8 xx xx xx xx          ; CALL zbranch_code   (5 bytes)
addr+5:  TT TT TT TT TT TT TT TT ; inline target cell  (8 bytes)
addr+13: ...                     ; next instruction (the "then" arm)
```

The `CALL` instruction transfers control to `zbranch_code`, pushing
the address `addr+5` (the byte after the CALL) onto the return
stack as the return address.  `zbranch_code` is now executing with
the address of the inline target cell sitting at `[rsp]`.

For an unconditional `branch,` (used in `else,` and `repeat,`) the
shape is the same except the `CALL` lands on `branch_code` instead.

## 2. `branch_code` in four instructions

```hex0 chunk=branch-code
;; ----- branch_code @ 0x42B ( -- ) unconditional, target = inline cell -----
58                                        ; pop rax
48 8B 00                                  ; mov rax, [rax]
50
C3

```

```
58              pop rax        ; rax = address of inline target cell
48 8B 00        mov rax, [rax] ; rax = target address (8 bytes from the cell)
50              push rax       ; new return address = target
C3              ret            ; jump there
```

Four bytes of opcode (plus `ret`).  The trick is **the cell is
consumed**: we popped the slot's address, dereferenced it to get
the target, and pushed the *target* back.  When `ret` runs, the
return stack has only the new target on top — the slot's address is
gone.

If we had left the slot's address on the stack and just dereferenced
to jump, `ret` would have gone to the slot, executed the 8 raw
bytes as code (gibberish), and crashed.  The seed authors picked
this pop/dereference/push trick specifically so that one `if,`
combinator can read as "emit a CALL and an 8-byte slot" with no
follow-up bookkeeping.

## 3. `zbranch_code` in nine instructions

```hex0 chunk=zbranch-code
;; ----- zbranch_code @ 0x431 ( flag -- ) branch if flag==0 -----
48 89 FA                                  ; mov rdx, rdi    ; save flag
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
58                                        ; pop rax          ; ret addr (-> inline cell)
48 85 D2                                  ; test rdx, rdx
75 05                                     ; jnz .skip
48 8B 00                                  ; mov rax, [rax]
EB 04                                     ; jmp .push
48 83 C0 08                               ; add rax, 8       ; .skip
50                                        ; push rax         ; .push
C3

```

Wait — the comment says `test rdx, rdx`, but the bytes say `48 85
D2`.  Let me decode that: `48` = REX.W; `85` = TEST r/m64, r64
opcode; `D2` = ModR/M byte with `mod=11, reg=010, r/m=010` = `rdx,
rdx`.  So it *is* `test rdx, rdx`.  The comment matches the bytes;
my paraphrase above just listed the wrong register.

Pseudocode:

```
mov rdx, rdi      ; save the flag in rdx
mov rdi, [rbp]    ; pop the flag off the data stack
add rbp, 8        ; (data-stack pop completed)
pop rax           ; rax = address of inline slot
test rdx, rdx     ; flag == 0?
jnz .skip         ; flag != 0 → skip the slot
mov rax, [rax]    ; flag == 0 → rax = target (read the cell)
jmp .push
.skip:
add rax, 8        ; skip past the slot
.push:
push rax          ; new return address
ret
```

`zbranch_code` does two things `branch_code` doesn't.

**It pops a flag off the data stack** before consulting it.  This is
the `( flag -- )` part of its stack effect.

**It branches on the flag.**  If the flag is zero (Forth "false"),
read the slot and jump to the target; if the flag is non-zero
(anything truthy, including Forth's canonical `-1`), skip the slot
and continue.

That last asymmetry — "branch if zero, fall-through if non-zero" —
is what makes the Forth idiom `flag if, ... then,` read naturally:
when the flag is true (non-zero), you *enter* the `if`-body;
`0branch` is what skips the body when the flag is *false*.

## 4. Why `push rax; ret` and not `jmp rax`?

`JMP r/m64` is a real x86 instruction (`FF E0` for `jmp rax`, two
bytes).  Why does the seed use the longer `push rax; ret`
(`50 C3`, two bytes) instead?

Actually they're the same length — *two bytes*.  The choice between
them is stylistic, not size-driven.  The seed's authors picked
`push/ret` because:

- The instruction we're "returning from" is a `CALL`, so structuring
  the primitive as "pop the call's return address, fiddle with it,
  push a new one, ret" is a clean, symmetric handshake with the
  `CALL`.  The reader sees `pop ... ret` and understands that the
  primitive is replacing one return address with another.
- `jmp rax` would also work, but the prologue would have to first
  `pop rax` (to discard the saved return address that nobody is
  going to return to), creating an asymmetry: pop, jump.  Using
  `push/ret` keeps the metaphor consistent.
- Branch predictors prefer balanced call/ret stacks.  A `push/ret`
  pairs with the original `CALL` better than a `jmp` would for the
  CPU's return-address predictor.  This is a microoptimisation
  that's invisible in our 2,040 bytes but real on actual hardware.

## 5. The consumed-slot property

This deserves its own section because it is *the* clever idea in
the chapter.

When a Forth-level `if,` emits a 13-byte sequence at HERE (5 bytes
for `CALL zbranch_code` + 8 bytes for the inline target), it does
*not* leave a separate target table.  The target is right there,
next to the CALL.  This is good for code locality and for compiler
simplicity — but it means the primitive has to *jump over* the
target cell when continuing past it.

The naive approach is: don't pop the return address; just adjust it
in-place on the return stack.  But x86 doesn't let you write
through `rsp` arbitrarily without disturbing the call stack
invariants.  Pop / modify / push is the cleanest path.

After the primitive's `ret`, the return stack looks like:

- For the "take the branch" case: the top is the *target address*;
  no trace of the slot.
- For the "fall through" case: the top is `slot_addr + 8`; again no
  trace of the slot.

Either way, the slot has been *consumed*.  Higher-level code never
sees it after the branch resolves.  This is what makes `if,/then,`
a self-contained 13-byte emission with no separate target table.

## 6. Connecting to Chapter 11

Ch 11 defined the `comma-call` word as:

```forth
: comma-call  ( xt -- )    \ emit a 5-byte CALL rel32
  [lit] 232 c,
  here-addr @ + [lit] 5 + -
  ,4 ;
```

This builds the same 5-byte `CALL` instruction we just talked about.
At a Forth-level `if,` call site:

```forth
: if,  ( -- patch-addr )
  ['] 0branch  comma-call    \ emit CALL zbranch_code
  here-addr @                \ remember slot address for back-patching
  0 ,8 ;                     \ emit 8 zero bytes as placeholder
```

So an `if,` invocation emits:

```
addr+0:  E8 xx xx xx xx     ; CALL 0branch (= zbranch_code)
addr+5:  00 00 00 00 00 00 00 00 ; placeholder target
```

…and pushes `addr+5` onto the data stack as the "patch address."
When `then,` runs later, it patches that 8-byte placeholder with
the *current* HERE — i.e., the address of the next instruction
after the `if,` body.

At runtime:

1. The compiled definition executes its body up to the `CALL
   zbranch_code` instruction.
2. The flag is popped off the data stack.  If it's zero, we want
   to *skip* the `if,` body; if non-zero, we want to *enter* it.

Wait — that's backwards from Forth convention!  Let me re-read.
In Forth, `flag if ... then` *enters* the body when the flag is
true.  And `then,` patches the placeholder with the
*post-body* address.  So:

- Flag is true (non-zero): `zbranch_code` skips past the slot →
  next instruction is the body → body runs.
- Flag is false (zero): `zbranch_code` reads the slot → jump to
  the post-body address → body is skipped.

Yes, that matches.  The naming `zbranch` = "branch if zero" is
correct: zero flag → take the branch (skip the body).  Non-zero
flag → fall through (enter the body).

Walk this end-to-end for `: pos? [lit] 0 > if, [lit] 89 emit
else, [lit] 78 emit then, ;` and you'll find the runtime emits
exactly the four-block structure that Ch 11's `if,/else,/then,`
combinators set up.

## Try it

```sh
./build.sh

# Define a word using if,/then, (which are immediate words from
# 010-lib.fth — load it first so they're defined):
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  cat <<'EOF'
: pos?  [lit] 0 > if,
    [lit] 89 emit
  else,
    [lit] 78 emit
  then, ;
[lit] 5  pos?
[lit] 0  pos?
bye
EOF
} | grep -v '^[[:space:]]*$' | ./seed-forth
# prints "YN" — 5 is positive ('Y'), 0 is not ('N').
```

For the begin/while/repeat combinators, try a countdown:

```sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  cat <<'EOF'
: countdown  begin, dup [lit] 0 > while,
    dup [lit] 48 + emit
    [lit] 1 -
  repeat, drop ;
[lit] 5 countdown bye
EOF
} | grep -v '^[[:space:]]*$' | ./seed-forth
# prints "54321"
```

## Exercises

1. The `push rax; ret` indirect-jump trick is two bytes long.  So
   is `jmp rax`.  Replace one of the branches in a copy of
   `000-seed.hex0` with the `jmp rax` form and rebuild.  Does
   anything observable change?  Why might the seed still prefer
   the original form?

2. The conditional branch tests `rdx` directly with `TEST rdx, rdx`.
   Which x86 flag does this set?  Which `J*` instruction does the
   following byte (`75 05`) encode?  Trace: what would change if
   you replaced it with `74 05`?

3. Add an `again_code` primitive (unconditional, no flag).  Wait —
   isn't that just `branch_code`?  Confirm by reading both bodies
   and identifying any difference.

4. Why doesn't `branch_code` or `zbranch_code` need to know whether
   the destination is forward or backward?  (Hint: the slot holds
   an *absolute* address.)

5. The inline-cell convention shares its mechanism with `lit_code`
   (Ch 18).  Could `lit_code` *be* `branch_code` if we always
   treated the inline cell as "push and jump past"?  Why does the
   seed have both?

## Takeaways

- `branch` and `0branch` are 26 bytes total and implement every
  control structure in this codebase — every `if`, `else`, `while`,
  `for`, and `return` you'll meet from Ch 22 onward sits on top of
  one of these two primitives.
- The inline-slot convention puts branch targets next to the CALL
  site, which simplifies the compiler (no separate target table)
  but requires the primitive to *consume* the slot — pop the
  callee's return address, do the work, push the new one.
- Every Forth-level combinator in Ch 11 is a thin wrapper that
  emits `CALL <(z)branch_code> + 8-byte slot` and arranges for
  later code to patch the slot.

Next: Chapter 20 — The Number Parser and REPL.
