# Chapter 19 — Branches and Inline Cells

```text
Missing capability: how branch and 0branch jump without an instruction operand is unclear.
New pattern: read the inline 8-byte target off the return stack, push a corrected return address, ret to it.
Artifact after this chapter: branch_code and zbranch_code plus the consumed-slot property.
Proof link: the C compiler's jump fixups (Ch 30) reuse the shape, just in x86-64 rather than inline cells.
```

Ch 11 built `if,`, `then,`, `else,`, `begin,`, `while,` and
`repeat,` in Forth.  Each one emits a `CALL` plus an 8-byte inline
cell at HERE, but Part I never said what those `CALL`s land on.
They land on two primitives, 34 bytes of hex between them.
`branch_code` (`@ 0x42B`, lines 368–372) jumps unconditionally to
the address in the inline cell.  `zbranch_code` (`@ 0x431`, lines
374–385) jumps only when the flag on top of the data stack is zero,
and otherwise steps past the cell.  Every loop and conditional in
the Forth library and in the C compiler's Forth source runs through
them; only the seed's own REPL, written in raw hex, uses native
jumps instead.

Both reuse `lit_code`'s trick from Ch 18: pop the return address
(which points at the inline cell), read the cell, and push a
corrected return address before `ret`, so execution never lands on
the 8 raw bytes.  The difference is which address goes back.
`lit_code` always pushes `slot + 8`; the branches can push the
cell's *contents*, the target.

## 1. The compiled shape

A compiled `if,` site looks like this in memory:

```
addr+0:  E8 xx xx xx xx          ; CALL 0branch's xt   (5 bytes)
addr+5:  TT TT TT TT TT TT TT TT ; inline target cell  (8 bytes)
addr+13: ...                     ; next instruction (the "then" arm)
```

The `CALL` targets `0branch`'s xt, the `JMP` stub in its header
(Ch 17), which passes control on to `zbranch_code`.  The `CALL`
pushes the address `addr+5` (the byte after the CALL) as the return
address.  `zbranch_code` is now executing with
the address of the inline target cell sitting at `[rsp]`.

For an unconditional `branch,` (used in `else,` and `repeat,`) the
shape is the same except the `CALL` lands on `branch_code` instead.

## 2. `branch_code` in four instructions

The unconditional branch is the simpler of the two:

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
When `ret` runs, the new target is on top of the return stack and
the slot's address is gone.

Had the slot's address stayed on the stack, `ret` would have jumped
to the slot and executed its 8 raw bytes as code.  Because the
primitive consumes the slot, an `if,` combinator only has to emit a
CALL and an 8-byte slot, with no follow-up bookkeeping.

## 3. `zbranch_code` in eleven instructions

The conditional branch adds a data-stack pop and a test:

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

In assembly:

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

One encoding is worth decoding by hand.  `48 85 D2` is
`test rdx, rdx`: `48` is REX.W, `85` is the `TEST r/m64, r64`
opcode, and the ModR/M byte `D2` (`mod=11, reg=010, r/m=010`) names
rdx in both operand slots.

`zbranch_code` does two things `branch_code` doesn't.

**It pops a flag off the data stack** before consulting it.  This is
the `( flag -- )` part of its stack effect.

**It branches on the flag.**  If the flag is zero (Forth "false"),
read the slot and jump to the target; if the flag is non-zero
(anything truthy, including Forth's canonical `-1`), skip the slot
and continue.

That asymmetry, "branch if zero, fall through if non-zero," is what
makes the Forth idiom `flag if, ... then,` read naturally:
when the flag is true (non-zero), you *enter* the `if`-body;
`0branch` is what skips the body when the flag is *false*.

## 4. Why `push rax; ret` and not `jmp rax`?

`JMP r/m64` is a real x86 instruction (`FF E0` for `jmp rax`, two
bytes).  `push rax; ret` (`50 C3`) is also two bytes.  The choice
between them is stylistic, not size-driven.  Two things favour
`push/ret`:

- The instruction we're "returning from" is a `CALL`, so structuring
  the primitive as "pop the call's return address, fiddle with it,
  push a new one, ret" is a clean, symmetric handshake with the
  `CALL`.  The reader sees `pop ... ret` and understands that the
  primitive is replacing one return address with another.  With
  `jmp rax` the primitive would still start with `pop rax`, leaving
  an asymmetric pop-then-jump.
- Branch predictors prefer balanced call/ret stacks.  A `push/ret`
  pairs with the original `CALL` better than a `jmp` would for the
  CPU's return-address predictor.  The effect is invisible in a
  program this size but real on hardware.

## 5. The consumed-slot property

The pop/adjust/push is the same one `lit_code` does (Ch 18).  For
the branches it is what makes inline targets work at all.

When a Forth-level `if,` emits a 13-byte sequence at HERE (5 bytes
for the `CALL` to `0branch`'s xt + 8 bytes for the inline target),
there is no separate target table: the target sits next to the
CALL.  That keeps the compiler simple, but the primitive has to
*jump over* the target cell when it continues past it.

The obvious alternative is to leave the return address on the stack
and adjust it in place.  x86 can do that: `add qword [rsp],
8` is a real 5-byte instruction, and `r@` reads `[rsp+8]` directly.
The seed pops anyway because it is smaller.  Every `[rsp]` operand
costs a SIB byte, and both paths need the slot address in a
register to read the cell.  `pop rax` and `push rax` are one byte
each, so the fall-through path is `add rax, 8` (4 bytes) inside a
2-byte pop/push pair, and the taken path is `mov rax, [rax]` (3
bytes) inside the same pair.  Doing the taken path in place would
need `mov rax, [rsp]` (4) + `mov rax, [rax]` (3) + `mov [rsp], rax`
(4).

After the primitive's `ret`, the return stack looks like:

- For the "take the branch" case: the top is the *target address*;
  no trace of the slot.
- For the "fall through" case: the top is `slot_addr + 8`; again no
  trace of the slot.

Either way, the slot has been *consumed*, and no later code sees
it.  That is why `if,/then,` is a self-contained 13-byte emission.

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
  0branch-xt comma-call      \ emit CALL to 0branch's xt
  here                       \ remember slot address for back-patching
  [lit] 0 , ;                \ reserve an 8-byte cell as placeholder
immediate
```

So an `if,` invocation emits:

```
addr+0:  E8 xx xx xx xx     ; CALL 0branch's xt (stub → zbranch_code)
addr+5:  00 00 00 00 00 00 00 00 ; placeholder target
```

…and pushes `addr+5` onto the data stack as the "patch address."
When `then,` runs later, it patches that 8-byte placeholder with
the *current* HERE, the address of the next instruction
after the `if,` body.

This is Ch 11's emit-remember-patch pattern seen from the
primitive's side: the emitted slot is inline
machine data, the remembered address is a Forth stack value, and
the patch becomes the runtime branch target.

At runtime:

1. The compiled definition executes its body up to the `CALL` to
   `0branch`'s xt.
2. The flag is popped off the data stack.  In Forth, `flag if ...
   then` enters the body when the flag is true, and `then,` patches
   the placeholder slot with the *post-body* address, so the
   primitive's job is to *skip* the body when the flag is **false**
   and fall through when it is true:
   - Flag non-zero: `zbranch_code` skips past the slot → next
     instruction is the body → body runs.
   - Flag zero: `zbranch_code` reads the slot → jump to the
     post-body address → body is skipped.

Walk this end-to-end for `: pos? [lit] 0 > if, [lit] 89 emit
else, [lit] 78 emit then, ;` and you'll find that `else,` ends the
first arm with an unconditional `branch` over the second, whose slot
`then,` patches, exactly as Ch 11's combinators set up.

## Try it

```sh
./build.sh

# Define a word using if,/then, (which are immediate words from
# 010-lib.fth, so load it first):
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
# prints "YN": 5 is positive ('Y'), 0 is not ('N').
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

3. **★ Trace.** Suppose you added an `again_code` primitive (unconditional, no
   flag).  Isn't that just `branch_code`?  Confirm by reading both bodies
   and identifying any difference.

4. **★ Trace.** Why doesn't `branch_code` or `zbranch_code` need to know whether
   the destination is forward or backward?  (Hint: the slot holds
   an *absolute* address.)

5. **★★ Trace.** The inline-cell convention shares its mechanism with `lit_code`
   (Ch 18).  Could `lit_code` *be* `branch_code` if we always
   treated the inline cell as "push and jump past"?  Why does the
   seed have both?

## Takeaways

- `branch` and `0branch`, 34 bytes in total, run every control
  structure in the Forth code, while the C programs the compiler
  emits use native x86 jumps (Ch 30).
- Each branch target sits in an 8-byte cell right after the `CALL`,
  and the primitive consumes that cell by replacing its return
  address with either the target or the address just past the cell.
- Ch 11's combinators only emit a `CALL` plus an 8-byte slot and
  patch the slot later, and these two primitives are what make that
  emit-remember-patch contract run.

Next: Chapter 20 — The Number Parser and REPL.
