# Chapter 19 — Branches and Inline Cells

```text
Missing capability: how branch and 0branch jump without an instruction operand is unclear.
New pattern: read the inline 8-byte target off the return stack, push a corrected return address, ret to it.
Artifact after this chapter: branch_code and zbranch_code plus the consumed-slot property.
Proof link: the C compiler's jump fixups (Ch 30) reuse the shape, just in x86-64 rather than inline cells.
```

Two primitives, 34 bytes of hex between them, implement
every loop and conditional in the codebase: `branch_code`
(`@ 0x42B`, lines 368–372) is an unconditional jump to an inline
8-byte target, and `zbranch_code` (`@ 0x431`, lines 374–385) is its
conditional counterpart, jumping when the top-of-stack flag is zero
and otherwise stepping past the slot.  Both share `lit_code`'s
trick of reading their inline operand off the return stack, but
with one crucial twist: they *consume* that slot, pushing a fresh
return address before `ret`, so the 8-byte cell does not remain on
the return stack after the branch.

By the end of the chapter you'll be able to read both bodies byte
for byte, explain the consumed-slot property and why it makes
`if,/then,` a single 13-byte sequence with no separate target
table, and map each primitive's bytes back to the Forth-level
combinators (`comma-call`, `if,`, `then,`, `else,`, `begin,`,
`while,`, `repeat,`) that Ch 11 built on top of them.  Nothing new
is deferred here; the C compiler's back-patching in Part III is the
same idea applied at a higher level (emit a placeholder, remember
the address, fill it in later).

---

Ch 11 ended with a complete suite of control-flow combinators —
`if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,` — all defined
in Forth, all emitting some combination of "CALL plus inline cell"
at HERE.  We deferred *what those CALLs land on* until Part II.

This is the chapter where we find out.  The two primitives below,
`branch_code` and `zbranch_code`, are 34 bytes of hex between them.
They implement every loop and conditional in this codebase — the
Forth library and the C compiler both lean on them.  Only the seed's
own REPL avoids them, and only because the REPL is written in raw hex.

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

Six bytes total: five bytes of opcode plus a one-byte `ret`.  The
trick is **the cell is consumed**: we popped the slot's address,
dereferenced it to get the target, and pushed the *target* back.
When `ret` runs, the return stack has only the new target on top —
the slot's address is gone.

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

The encoding `48 85 D2` decodes as `test rdx, rdx`: `48` is REX.W,
`85` is the `TEST r/m64, r64` opcode, and the ModR/M byte `D2`
(`mod=11, reg=010, r/m=010`) names rdx in both operand slots.

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
bytes).  `push rax; ret` (`50 C3`) is also two bytes.  The choice
between them is stylistic, not size-driven.  The seed's authors
picked `push/ret` because:

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

```
   (V) (V)
   ( o.o )   "the primitive eats the inline cell on its way out.
   /\/\/\     no separate jump table.  the return stack does
            data-table duty.  again."
```

## 6. Connecting to Chapter 11

Ch 11 defined the `comma-call` word as:

```forth
: comma-call  ( xt -- )    \ emit a 5-byte CALL rel32
  [lit] 232 c,             \ 0xE8 CALL opcode
  here [lit] 4 + - ,4 ;    \ rel32 = target - (HERE+4)
```

This builds the same 5-byte `CALL` instruction we just talked about.
At a Forth-level `if,` call site:

```forth
: if,  ( -- patch-addr )
  0branch-xt comma-call      \ emit CALL 0branch (= zbranch_code)
  here                       \ remember slot address for back-patching
  [lit] 0 , ;                \ reserve an 8-byte cell as placeholder
immediate
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

This is the same emit, remember, patch pattern from Ch 11, now
explained from the primitive's side: the emitted slot is inline
machine data, the remembered address is a Forth stack value, and
the patch becomes the runtime branch target.

At runtime:

1. The compiled definition executes its body up to the `CALL
   zbranch_code` instruction.
2. The flag is popped off the data stack.  In Forth, `flag if ...
   then` enters the body when the flag is true, and `then,` patches
   the placeholder slot with the *post-body* address — so the
   primitive's job is to *skip* the body when the flag is **false**
   and fall through when it is true:
   - Flag non-zero: `zbranch_code` skips past the slot → next
     instruction is the body → body runs.
   - Flag zero: `zbranch_code` reads the slot → jump to the
     post-body address → body is skipped.

The naming `zbranch` = "branch if zero" matches: zero flag → take
the branch (skip the body); non-zero flag → fall through (enter the
body).

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

1. **★★★ Modify.** The `push rax; ret` indirect-jump trick is two bytes long.  So
   is `jmp rax`.  Replace one of the branches in a copy of
   `000-seed.hex0` with the `jmp rax` form and rebuild.  Does
   anything observable change?  Why might the seed still prefer
   the original form?

2. **★★ Trace.** The conditional branch tests `rdx` directly with `TEST rdx, rdx`.
   Which x86 flag does this set?  Which `J*` instruction does the
   following byte (`75 05`) encode?  Trace: what would change if
   you replaced it with `74 05`?

3. **★ Trace.** Add an `again_code` primitive (unconditional, no flag).  Wait —
   isn't that just `branch_code`?  Confirm by reading both bodies
   and identifying any difference.

4. **★ Trace.** Why doesn't `branch_code` or `zbranch_code` need to know whether
   the destination is forward or backward?  (Hint: the slot holds
   an *absolute* address.)

5. **★★ Trace.** The inline-cell convention shares its mechanism with `lit_code`
   (Ch 18).  Could `lit_code` *be* `branch_code` if we always
   treated the inline cell as "push and jump past"?  Why does the
   seed have both?

## Takeaways

- `branch` and `0branch` are 34 bytes total and implement every
  control structure in this codebase — every `if`, `else`, `while`,
  `for`, and `return` you'll meet from Ch 30 onward sits on top of
  one of these two primitives.
- The inline-slot convention puts branch targets next to the CALL
  site, which simplifies the compiler (no separate target table)
  but requires the primitive to *consume* the slot — pop the
  callee's return address, do the work, push the new one.
- Every Forth-level combinator in Ch 11 is a thin wrapper that
  emits `CALL <(z)branch_code> + 8-byte slot` and arranges for
  later code to patch the slot.  The primitive makes the
  emit/remember/patch contract executable.

Next: Chapter 20 — The Number Parser and REPL.
