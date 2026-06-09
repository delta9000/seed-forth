# Chapter 14 — Stack Primitives in Machine Code

```text
Missing capability: dup, drop, swap, over, @, !, and return-stack ops were black boxes.
New pattern: each primitive is two to seven bytes of x86-64; rdi holds TOS, rbp is the data-stack pointer.
Artifact after this chapter: the stack and memory primitives' machine code, fully readable.
Proof link: the compiler's codegen reuses the same rdi/rbp convention; these bytes prime you for Ch 25.
```

Ten primitive bodies in `000-seed.hex0` carry the data-stack and
memory operations Part I leaned on without explanation: `dup_code` at
`0x13B` through `cstore_code` at `0x18E` (lines 97–152), plus
`r_at_code` at `0x732` (lines 666–675).  They share one convention,
introduced at the entry point in Ch 13 and now visible in every body:
`rbp` is the data-stack pointer (cells are 8 bytes, stack grows
down), and `rdi` is a register cache for TOS, so `sub rbp,8` opens a
new top slot and `mov [rbp], rdi` spills the old TOS before a fresh
value is loaded.  Open `000-seed.hex0` to lines 97–152 (and jump to
666–675 for `r@`) and read along.

By the end you'll be able to read the x86-64 encoding of `dup`,
`drop`, `swap`, `>r`, `r>`, `@`, `!`, `c@`, `c!`, and `r@` byte for
byte, explain the "TOS in `rdi`, data stack in `rbp`" convention and
trace what each primitive does to both registers, and predict the
exact memory image left behind by any sequence of these primitives.
Arithmetic and logic primitives wait for Ch 15; the I/O primitives
that thread `rsi` through `write(2)` and `read(2)` are Ch 16
(`bye_code`, `emit_code`, and `key_code` are emitted as source-contiguous
chunks here, but the prose lives in Ch 16).

---

The data stack is two registers and a 17-page region.  `rbp` points
at the cell just below the top of the stack; `rdi` *is* the top.
When we say "TOS is 42," we mean `rdi == 42`; when we say "the cell
below TOS is 100," we mean `[rbp] == 100`.

This is unusual.  A textbook stack machine keeps every value in
memory and dereferences a pointer to manipulate the top.  The seed
caches the top in a register, which avoids one load and one store
per primitive — at the cost of needing to *spill* `rdi` to memory
every time we want to push a new value.

The rule is consistent: every primitive in this chapter and the
next leaves `rdi` holding the new TOS, and uses `rbp` to read or
write deeper slots.  Reads from `[rbp]` get the cell *below* the
current TOS; writes to `[rbp]` overwrite that cell.

## 1. The push and pop shapes

There are exactly two ways to grow the data stack and exactly two
ways to shrink it.  Read these four sequences once and the rest of
the chapter becomes pattern-matching.

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

That is the whole calling convention.  `48` is the REX.W prefix
("operate on 64-bit operands"); the rest of the bytes encode the
operation and the addressing mode.  You won't memorise them on the
first read, but after eight primitives the patterns will pop out.

## 2. `dup` in 9 bytes

```hex0 chunk=dup-code
;; ----- dup_code @ 0x13B -----
48 83 ED 08
48 89 7D 00
C3

```

That is *half* a push.  We don't need to load a new TOS into `rdi`
— `rdi` already holds the value we want to duplicate.  All we have
to do is spill it to a fresh slot:

```
sub rbp, 8       ; make a new slot
mov [rbp], rdi   ; spill rdi into it; rdi still holds TOS
ret
```

After this, `rdi == old TOS` and `[rbp] == old TOS` — two copies of
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

No `sub rbp` or `add rbp` — the stack doesn't grow or shrink, only
its contents rotate.  `rax` is the scratch register for the swap.
Any caller-saved register would do; `rax` is the conventional choice.

## 5. `>r`, `r>`, and `r@`: bridging the two stacks

The data stack is `rbp`-and-`rdi`.  The **return stack** is the
ordinary x86 call stack accessed by `push` / `pop` / `call` / `ret`,
with `rsp` as the pointer.  When a Forth-level word calls one of
these primitives via `CALL`, the return address is sitting at
`[rsp]` — the *top* of the return stack from x86's perspective.

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

After this, the value that was on top of the data stack is now sitting
one cell *below* the return address on the return stack.  When the
caller continues, the next x86 `ret`/`pop` it does will skip past our
return address, but a Forth `r>` or `r@` knows to look one cell deeper.

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

`r@` (in Forth tradition: "peek" the top of the return stack) was
added later in the seed's history and lives at a different offset
(`0x732`).  Its trick is even tighter: don't pop the return address,
just look past it.

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
address.  No `pop`/`push` needed — we leave the return stack
untouched, just borrow a value off the top.  This is the kind of
move that becomes obvious once you've seen `>r`/`r>`: if you know
where the cell lives, you can read it without unstacking.

## 6. `@` and `!` — cell load and store

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
into `rdi`.  No data-stack motion at all.  This is the seed's
smallest primitive — at four bytes total, `dup` and `drop` are more
than twice its size.

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

```
48 8B 45 00      mov rax, [rbp]   ; rax = value (under-TOS)
48 89 07         mov [rdi], rax   ; *addr = value   (TOS is the addr)
48 83 C5 08      add rbp, 8       ; pop value's slot
48 8B 7D 00      mov rdi, [rbp]   ; load new TOS (whatever was below)
48 83 C5 08      add rbp, 8       ; pop addr's slot
C3               ret
```

`!` consumes both arguments — the address (in `rdi`) and the value
(at `[rbp]`).  After the store, both stack slots are released and
`rdi` holds whatever sat below them.

## 7. `c@` and `c!` — byte load and store

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
Compare that to the Forth-level definitions in `010-lib.fth` of
`over`, `nip`, `rot`, etc., which average around 5–10 tokens each and
compile (at runtime, via `:`) to roughly the same total byte count
once the `CALL` instructions are emitted.

The trade is: keep the *most-used* stack-shuffling primitives in
hex so they're called once per use, and *derive* the less-used ones
in Forth so they pay a token-count cost only when they appear.  By
the end of Part I we already saw the derived side — `over`, `nip`,
`rot`, `2dup`, `2drop` are all Forth-level.  Now you see why the
primitives have to be 9 bytes apiece: the seed budget is 2,040
bytes, and every primitive paid is a primitive not budgeted for
something else.

## Canonical source

This chapter defines the bodies for the stack-primitive chunks
referenced by the master root block in Ch 13.  The chunks for
`bye_code`, `emit_code`, and `key_code` are written here too, so
that the lines 65–96 region of the source has a body — but the
*prose* explaining them belongs to Ch 16, so we ship the chunks
without commentary and tag them with the same `;; -----` banners
that the original file used.

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

(The eight stack-primitive chunks `<<dup-code>>` through
`<<cstore-code>>`, plus `<<r-at-code>>`, are defined inline in the
prose above.)

## Try it

```sh
./build.sh
echo "[lit] 65 [lit] 66 swap emit emit bye" | ./seed-forth
# prints "AB" — after swap TOS is 65 ('A'), so it emits first, then 66 ('B')
echo "[lit] 67 dup emit emit bye"           | ./seed-forth
# prints "CC"
echo "[lit] 68 [lit] 69 drop emit bye"      | ./seed-forth
# prints "D"  (69='E' was on top, drop discarded it, then 68='D' emits)
```

For each of `>r`, `r>`, `@`, `!`, `c@`, `c!`, write a one-line shell
test before running it.  Predict the byte sequence on the stack at
each step from the table in §1.

## Exercises

1. **★★ Extend.** `dup_code` is 9 bytes.  Write the equivalent of a primitive
   `2dup_code` (duplicate the top *two* cells, leaving 4 on the
   stack).  Count the bytes.  Compare to `: 2dup over over ;` which
   compiles to two `CALL` instructions of 5 bytes each plus the
   header overhead — which wins on size?

2. **★★ Trace.** `c!` writes only the low byte of TOS, then reloads `rdi` from
   `[rbp]`.  Trace what happens after `[lit] 0x12345678 [lit]
   0x420000 c!`.  What's in memory at `0x420000`?  What's in `rdi`?

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

- The data-stack-in-register-cache convention costs ~9 bytes per
  push/pop primitive — half a cache line for the smallest.
- Every primitive ends in `C3` (`ret`).  Inter-primitive calls go
  through `CALL rel32`, so callee addresses must be known at
  hex-assembly time.
- `>r`, `r>`, and `r@` bridge the data and return stacks by
  threading values around the x86 `CALL` return address; `r@` is
  the simplest semantically (a peek that leaves both stacks
  otherwise unchanged), even though it isn't the smallest in bytes.

Next: Chapter 15 — Arithmetic, Logic, Comparison.
