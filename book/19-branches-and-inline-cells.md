# Chapter 19 — Branches and Inline Cells

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read `branch_code` and `zbranch_code` byte for byte;
- explain the "CALL with an inline 8-byte target" convention,
  including the "consumed slot" property — the target cell does
  *not* remain on the return stack;
- map each primitive byte to the corresponding line in
  `010-lib.fth`'s `comma-call`, `if,`, and `then,` (Ch 11).

## Source coverage

`000-seed.hex0` `branch_code @ 0x42B`, `zbranch_code @ 0x431`.
About 30 bytes total.

## Concepts introduced

- **`branch_code` ( -- ).**  `pop rax ; mov rax, [rax] ; push rax ;
  ret`.  Four x86 instructions; the return address (= address of the
  inline slot) becomes the destination.
- **`zbranch_code` ( flag -- ).**  Same as `branch_code` except it
  first tests TOS and either reads the slot (flag=0) or adds 8 to
  `rax` (flag!=0).  Push and return either way.
- **The "consumed slot" property.**  Because we `pop`/`push` the
  return address rather than reading the slot through it and
  leaving the slot on the return stack, control flow returns to the
  *destination*, not to "just after the slot."  This is what makes
  `if,/then,` work as a single 13-byte sequence.

## Concepts carried in

- The "callee pops return address" convention shared with
  `lit_code` (Ch 18).
- Stack-and-rdi convention from Ch 14.

## Concepts deferred

- The Forth-level `if,/then,/else,/begin,/while,/repeat,` that emit
  CALLs to these primitives — already covered in Ch 11; this
  chapter is the underlying machinery.

## Section plan

1. **The convention in one diagram.**  A compiled `if,` site is:
   `E8 xx xx xx xx <8 bytes>`.  The `CALL` lands in
   `(z)branch_code`; the 8 bytes are the destination address.
2. **`branch_code` bytewise.**  Unconditional.  `pop rax` gets the
   address of the slot; `mov rax, [rax]` dereferences to the
   destination; `push rax` makes the destination the new return
   address; `ret` "returns" there.
3. **`zbranch_code` bytewise.**  Conditional.  Same pattern, but
   between the `pop` and the dereference, test `rdi` and either
   keep `rax` pointing at the slot (then dereference) or add `8`
   to `rax` (skip the slot).  Then pop TOS via `mov rdi, [rbp]; add
   rbp, 8`.
4. **Why "consumed slot" matters.**  If we naively `ret`ed without
   `push`ing, we'd return to the address-of-the-slot — i.e.
   execute the 8 raw bytes as code, which is gibberish.  The
   `push rax; ret` trick is the cleanest way to do an indirect jump
   on x86 without `jmp r/m`.
5. **Cross-reference Ch 11.**  Each Forth-level combinator
   (`if,/then,/else,/begin,/while,/repeat,`) emits exactly this
   13-byte sequence with a different patching strategy.  Walk one
   `: foo flag if, [lit] 1 then, ;` end-to-end: what bytes does the
   Forth compiler emit, and what does the seed runtime do with them?

## Canonical chunks

- `<<branch-code>>` — ~6 bytes at `0x42B`.
- `<<zbranch-code>>` — ~20 bytes at `0x431`.

## Try it

```sh
./build.sh
# Define a word that uses if,/then, (immediate words from 010-lib.fth)
cat 010-lib.fth - <<'EOF' | ./seed-forth
: pos? [lit] 0 > if,
    [lit] 89 emit  \ 'Y'
  else,
    [lit] 78 emit  \ 'N'
  then, ;
[lit] 5  pos?
[lit] -3 pos?
bye
EOF
# prints "YN"
```

## Exercises

1. The `push rax; ret` indirect-jump trick is one byte longer than
   `jmp rax` would be.  Why not use `jmp rax`?  (Hint: think about
   x86 instruction encoding; `JMP r/m64` exists.)

2. The conditional branch tests `rdi` directly.  What flag does
   x86 produce after `test rdi, rdi`?  Which `J*` instruction
   would you use?

3. Add an `again_code` primitive (unconditional, no flag).  Wait,
   isn't that just `branch_code`?  Confirm by reading both.

4. Why doesn't `(z)branch_code` need to know whether the destination
   is forward or backward?  (Hint: the slot holds an *absolute*
   address.)

## Takeaways

- `branch` and `0branch` are 26 bytes between them and implement
  every control structure in this codebase.
- The inline-slot convention pushes branch targets next to the
  CALL site, which makes the compiler simpler (no separate
  target-table) but the primitive's body trickier (it must reach
  back through the return stack).
- Every immediate combinator in Ch 11 is a thin Forth wrapper
  around emitting `CALL <(z)branch_code>` + an 8-byte slot.

Next: Chapter 20 — The Number Parser and REPL.
