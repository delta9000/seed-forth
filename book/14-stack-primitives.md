# Chapter 14 — Stack Primitives in Machine Code

```text
Missing capability: dup, drop, swap, over, @, !, and return-stack ops were black boxes.
New pattern: each primitive is two to six x86-64 instructions; rdi holds TOS, rbp is the data-stack pointer.
Artifact after this chapter: the stack and memory primitives' machine code, fully readable.
Proof link: the compiler's codegen reuses the same rdi/rbp convention; these bytes prime you for Ch 25.
```

`dup` appears 236 times in the library and the C compiler's Forth
source.  It duplicates the top of the stack, so it has to read the
top of the stack.  Look for that read in its body and you won't
find one: `dup_code` is two instructions and a `ret`, and neither
instruction loads anything from the stack.  The top of the Forth
stack is not in memory.  It is in a register.

Every body in the seed follows that convention.  `rdi` *is* the top
of stack (TOS), and `rbp` points at the cell just below it.  "TOS
is 42" means `rdi == 42`; "the cell below TOS is 100" means
`[rbp] == 100`.  Cells are 8 bytes and the stack grows down.  A
textbook stack machine keeps every value in memory; caching the top
in a register saves a load and a store in most primitives, at the
cost of *spilling* `rdi` to memory whenever a new value is pushed.

This chapter reads ten bodies: `dup_code` at `0x13B` through
`cstore_code` at `0x18E` (lines 97–152 of `000-seed.hex0`), plus
`r_at_code` at `0x732` (lines 666–675), which sits among the entries
at the end of the file.  `bye`, `emit` and `key` come just before
`dup` in the file, so their chunks appear at the end of this
chapter, but Ch 16 explains them.

## 1. The push and pop shapes

Nearly every primitive in this chapter is built from two shapes:
a push and a pop.  Learn them and the rest of the chapter is
pattern-matching.

**Push (we have a new TOS in `rax`; the old one is in `rdi`):**
```
48 83 ED 08     sub rbp, 8       ; make room for the spilled TOS
48 89 7D 00     mov [rbp], rdi   ; spill old TOS
48 89 C7        mov rdi, rax     ; new TOS = rax
```

**Pop (discard TOS, restore the under-TOS into `rdi`):**
```
48 8B 7D 00     mov rdi, [rbp]   ; rdi = old under-TOS
48 83 C5 08     add rbp, 8       ; release the slot
```

That is the whole data-stack convention.  `48` is the REX.W prefix
("operate on 64-bit operands"); the rest of the bytes encode the
operation and the addressing mode.  After a few primitives the
patterns become familiar.

## 2. `dup` in 9 bytes

```hex0 chunk=dup-code
;; ----- dup_code @ 0x13B -----
48 83 ED 08
48 89 7D 00
C3

```

That is *half* a push.  `rdi` already holds the value we want to
duplicate, so there is no new TOS to load.  We only spill it to a
fresh slot:

```
sub rbp, 8       ; make a new slot
mov [rbp], rdi   ; spill rdi into it; rdi still holds TOS
ret
```

After this, `rdi == old TOS` and `[rbp] == old TOS`: two copies of
the same value, one in the register cache and one in memory.

## 3. `drop` in 9 bytes

```hex0 chunk=drop-code
;; ----- drop_code @ 0x144 -----
48 8B 7D 00
48 83 C5 08
C3

```

A bare pop:

```
mov rdi, [rbp]   ; pull the under-TOS into the register cache
add rbp, 8       ; release the slot we just drained
ret
```

The old TOS is overwritten and gone; the new TOS is what used to be
the under-TOS.

## 4. `swap` in 12 bytes

```hex0 chunk=swap-code
;; ----- swap_code @ 0x14D -----
48 8B 45 00
48 89 7D 00
48 89 C7
C3

```

Trace it with `( a b -- b a )`, where `a` is at `[rbp]` and `b` is
in `rdi`:

```
48 8B 45 00      mov rax, [rbp]   ; rax = a
48 89 7D 00      mov [rbp], rdi   ; [rbp] = b
48 89 C7         mov rdi, rax     ; rdi = a
C3               ret
```

There is no `sub rbp` or `add rbp`: the stack doesn't grow or
shrink, only its contents rotate, with `rax` as scratch.

## 5. `>r`, `r>`, and `r@`: bridging the two stacks

The data stack is `rbp`-and-`rdi`.  The **return stack** is the
ordinary x86 call stack accessed by `push` / `pop` / `call` / `ret`,
with `rsp` as the pointer.  When a Forth-level word calls one of
these primitives via `CALL`, the return address sits at `[rsp]`,
the *top* of the return stack from x86's point of view.

To move a value between the two stacks, the primitives have to
shuffle that return address out of the way, do their work, and put
it back.

### `>r` ( n -- ; R: -- n )

```hex0 chunk=to-r-code
;; ----- to_r_code @ 0x159 -----
58
57
50
48 8B 7D 00
48 83 C5 08
C3

```

Three single-byte instructions, then a pop:

```
58               pop rax        ; rax = return address (our own)
57               push rdi       ; push TOS onto return stack
50               push rax       ; restore the return address on top
48 8B 7D 00      mov rdi, [rbp] ; pop from data stack
48 83 C5 08      add rbp, 8
C3               ret
```

Inside `>r`, the value sits one cell *below* `>r`'s own return
address.  Once `>r`'s `ret` pops that address, the value is on top
of the caller's return stack — directly above the caller's *own*
return address.  If the caller now hit its `ret`, the CPU would pop
the value and jump to it as if it were an address.  That is why
`>r` and `r>` must balance within one definition: `r>` (or `r@`,
which peeks) has to take the value back before the caller returns.

### `r>` ( -- n ; R: n -- )

```hex0 chunk=r-from-code
;; ----- r_from_code @ 0x165 -----
48 83 ED 08
48 89 7D 00
58
5F
50
C3

```

A push on the data stack, then the inverse return-stack dance:

```
48 83 ED 08      sub rbp, 8     ; make data-stack room
48 89 7D 00      mov [rbp], rdi ; spill old TOS
58               pop rax        ; pull our own return address
5F               pop rdi        ; pull the value we want into rdi (new TOS)
50               push rax       ; restore our return address
C3               ret
```

Net effect: the cell that `>r` parked on the return stack lands in
`rdi`, and the data-stack TOS shifts down.

### `r@` ( -- n ; R: n -- n )

`r@` peeks at the top of the return stack.  Its body lives near the
end of the file at `0x732`, and it avoids the pop/push dance
entirely by looking past the return address.

```hex0 chunk=r-at-code
;; ----- r_at_code @ 0x732 ( -- v ) peek caller's top-of-rstack -----
;; r@ is CALL'd, so [rsp+0] = our own ret addr; caller's saved value is at [rsp+8].
;; Existing precedent: to_r_code and r_from_code
;; both pop their own ret addr to manipulate rstack across the CALL boundary.
48 8B 44 24 08                            ; mov rax, [rsp+8]   ; skip our ret addr; rax = caller's TOR
48 83 ED 08                               ; sub rbp, 8         ; make data-stack room
48 89 7D 00                               ; mov [rbp], rdi     ; spill old TOS to rbp
48 89 C7                                  ; mov rdi, rax       ; new TOS = TOR
C3                                        ; ret

```

`mov rax, [rsp+8]` reads the cell *one slot past* the return
address.  The return stack is left untouched.  Once you know where
the cell lives, as `>r` and `r>` show, you can read it without
unstacking anything.

## 6. `@` and `!`: cell load and store

### `@` ( addr -- value )

```hex0 chunk=fetch-code
;; ----- fetch_code @ 0x171 -----
48 8B 3F
C3

```

Three bytes (plus `ret`):

```
48 8B 3F         mov rdi, [rdi]
C3               ret
```

TOS is an address; load 8 bytes from that address; store them back
into `rdi`.  No data-stack motion at all.  At four bytes this is the
seed's smallest primitive; `dup` and `drop` are more than twice its
size.

### `!` ( value addr -- )

```hex0 chunk=store-code
;; ----- store_code @ 0x175 -----
48 8B 45 00
48 89 07
48 83 C5 08
48 8B 7D 00
48 83 C5 08
C3

```

Decoded:

```
48 8B 45 00      mov rax, [rbp]   ; rax = value (under-TOS)
48 89 07         mov [rdi], rax   ; *addr = value   (TOS is the addr)
48 83 C5 08      add rbp, 8       ; pop value's slot
48 8B 7D 00      mov rdi, [rbp]   ; load new TOS (whatever was below)
48 83 C5 08      add rbp, 8       ; pop addr's slot
C3               ret
```

`!` consumes both arguments: the address (in `rdi`) and the value
(at `[rbp]`).  After the store, both stack slots are released and
`rdi` holds whatever sat below them.

## 7. `c@` and `c!`: byte load and store

### `c@` ( addr -- byte )

```hex0 chunk=cfetch-code
;; ----- cfetch_code @ 0x189 -----
48 0F B6 3F
C3

```

`MOVZX` (`0F B6`) loads a byte and zero-extends it to 64 bits.  The
high 56 bits of `rdi` get cleared; the low 8 bits hold the byte at
`[rdi]`.

### `c!` ( byte addr -- )

```hex0 chunk=cstore-code
;; ----- cstore_code @ 0x18E -----
48 8B 45 00
88 07
48 83 C5 08
48 8B 7D 00
48 83 C5 08
C3

```

Identical shape to `!`, except the store is one byte:

```
48 8B 45 00      mov rax, [rbp]    ; rax = byte (under-TOS)
88 07            mov [rdi], al     ; store just the low byte
48 83 C5 08      add rbp, 8        ; pop byte's slot
48 8B 7D 00      mov rdi, [rbp]    ; load new TOS
48 83 C5 08      add rbp, 8        ; pop addr's slot
C3               ret
```

The high 56 bits of the value cell are silently discarded.  If you
pass `0x12345678` and write it to `addr`, only `0x78` lands in
memory; the rest is lost.

## 8. The arithmetic of bytes saved

Ten stack primitives, 119 bytes of code in total: `dup` 9, `drop` 9,
`swap` 12, `>r` 12, `r>` 12, `@` 4, `!` 20, `c@` 5, `c!` 19, `r@` 17.
Everything else Part I used, `over`, `nip`, `rot`, `2dup` and
`2drop`, is Forth-level, compiled at load time from these.  The trade
is to keep the most-used shufflers in hex and derive the rest, which
then cost the seed nothing.  With a 2,040-byte
budget, every byte spent on one primitive is a byte unavailable to
another.

## Canonical source

This chapter defines the bodies for the stack-primitive chunks
referenced by the master root block in Ch 13.  The chunks for
`bye_code`, `emit_code`, and `key_code` are written here too, so
that the lines 65–96 region of the source has a body, but the
prose explaining them is in Ch 16.  They appear here without
commentary, under the same `;; -----` banners the source uses.

```hex0 chunk=bye-code
;; ----- bye_code @ 0x0D2 -----
B8 3C 00 00 00
BF 00 00 00 00
0F 05

```

```hex0 chunk=emit-code
;; ----- emit_code @ 0x0DE -----
48 C7 C0 00 20 41 00
40 88 38
B8 01 00 00 00
BF 01 00 00 00
48 BE 00 20 41 00 00 00 00 00
BA 01 00 00 00
0F 05
48 8B 7D 00
48 83 C5 08
C3

```

```hex0 chunk=key-code
;; ----- key_code @ 0x10C -----
48 83 ED 08
48 89 7D 00
B8 00 00 00 00
BF 00 00 00 00
48 C7 C6 00 20 41 00
BA 01 00 00 00
0F 05
48 85 C0
74 06
48 0F B6 3E
EB 03
48 31 FF
C3

```

(The nine stack-primitive chunks `<<dup-code>>` through
`<<cstore-code>>`, plus `<<r-at-code>>`, are defined inline in the
prose above.)

## Try it

```sh
./build.sh
echo "[lit] 65 [lit] 66 swap emit emit bye" | ./seed-forth
# prints "AB": after swap TOS is 65 ('A'), so it emits first, then 66 ('B')
echo "[lit] 67 dup emit emit bye"           | ./seed-forth
# prints "CC"
echo "[lit] 68 [lit] 69 drop emit bye"      | ./seed-forth
# prints "D"  (69='E' was on top, drop discarded it, then 68='D' emits)
echo "[lit] 65 >r [lit] 66 emit r> emit bye" | ./seed-forth
# prints "BA"
echo "[lit] 305419896 [lit] 4325376 c! [lit] 4325376 c@ emit bye" | ./seed-forth
# prints "x"
```

The last two are §5 and §7 happening on real hardware.  `>r`
parked the 65 on the x86 call stack, under the return address it
popped and pushed back, and `r>` fetched it after the 66 had gone
out.  (This works at the top level because the REPL is a loop that
never executes `ret`, so nothing pops the parked value by mistake.)
Then `c!` was handed 305419896, hex 12345678, and stored only its
low byte: `c@` read back hex 78, the letter `x`.

Before running the other primitives, predict the stack at each step
using the push and pop shapes from §1.

## Exercises

1. **★★ Extend.** `dup_code` is 9 bytes.  Write the equivalent of a primitive
   `2dup_code` (duplicate the top *two* cells, leaving 4 on the
   stack).  Count the bytes.  Compare to `: 2dup over over ;` which
   compiles to two `CALL` instructions of 5 bytes each plus the
   header overhead.  Which wins on size?

2. **★★ Trace.** `c!` writes only the low byte of TOS, then reloads `rdi` from
   `[rbp]`.  Trace what happens after `[lit] 305419896 [lit]
   4325376 c!` — that is, `0x12345678` stored to `0x420000`
   (`[lit]` reads decimal only).  What's in memory at `0x420000`?
   What's in `rdi`?  Check the first answer with
   `[lit] 4325376 c@ emit`.

3. **★★ Trace.** `>r` cannot simply do `push rdi` first: the return address is in
   the way.  Walk through the alternative encoding `push rdi ; ...`
   and explain what specifically breaks.

4. **★★★ Extend.** Modify a copy of `000-seed.hex0` to add a `nip` primitive
   (effect: `( a b -- b )`) directly in hex.  How many bytes?  Is
   it smaller than the Forth-level `: nip swap drop ;`?  (Count the
   header bytes too.)

5. **★★ Extend.** `r@` reads `[rsp+8]` to skip past the return address.  Sketch a
   hypothetical `r@2` that reads two cells deep (`[rsp+16]`).  When
   would you want that?  Why hasn't the seed paid for it?

## Takeaways

- With TOS cached in `rdi`, a push or pop costs 8 bytes (`sub` or
  `add rbp` plus the spill or reload), which is why `dup` and `drop`
  are 9 bytes with their `ret`.
- Almost every primitive ends in `C3` (`ret`), and calls between
  primitives use `CALL rel32`, so every callee address is fixed at
  hex-assembly time.
- `>r`, `r>` and `r@` move values between the data and return
  stacks by working around the x86 `CALL` return address that sits
  on top of the return stack.

**Running count: 329 of 2,040 bytes read (16%).**  Ch 13's 210 plus
this chapter's 119.  (`bye`, `emit` and `key` are listed here but
counted in Ch 16, where they are explained.)

Every body so far moves or copies cells; not one computes anything.
Part I built all of Boolean logic on `nand` and every signed
comparison on `/`.  Ch 15 opens both, and the one logic operation
the seed pays for turns out to be the one x86 lacks.

Next: Chapter 15 — Arithmetic, Logic, Comparison.
