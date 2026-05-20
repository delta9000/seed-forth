# Chapter 4 — The Return Stack: `over` and Subtract

Two definitions in `010-lib.fth` (lines 31–38), `over` and `-`,
introduce the seed's *second* stack and show how two's complement
turns subtraction into addition plus `nand`.  `over` borrows a
return-stack slot as a scratch parking space for `dup`-of-the-second;
`-` doesn't touch the return stack but earns its place alongside
`over` by making the same trade, paying a few extra tokens at the
call site so the seed can keep one fewer primitive.  Open
`010-lib.fth` to those eight lines and read along; the chapter
spends most of its time on the return-stack sidebar (`>r`, `r>`,
`r@` and the matched-pair rule) because every later trick in the
book reaches for it.

By the end of the chapter you'll be able to explain why Forth uses
two stacks and what each is for, read and write `>r` / `r>` / `r@`
idioms, derive subtraction from `+` and `nand` (and predict its
bit-by-bit behaviour for negative inputs), and know exactly what
`over` does mechanically rather than only symbolically.  The seed's
`>r` / `r>` machine code is Part II, Ch 14; the full call/return
story (how `:` and `;` themselves use the return stack) is Ch 18;
and multi-step return-stack juggling, preserving a value across a
long expression, is Ch 8's `rot` and later compiler-internal uses.

---

Ch 1 introduced one stack — the data stack — and a handful of
primitives that push, pop, and shuffle values on it.  This chapter
introduces the *other* stack the seed maintains, the one most users
never directly touch, and shows two definitions that lean on it.
`over` borrows it as a temporary parking space; `-` doesn't touch it
at all but earns a place alongside `over` because it makes the same
trade — fewer primitives, slightly more work at the call site.

## 1. Why two stacks at all?

A virtual machine needs somewhere to remember "where to return when
this subroutine finishes."  The obvious choice is the same stack
that holds the subroutine's arguments and locals: push the return
address before the call, pop it on return.  That's what C does, that
it's what most procedural VMs do, and it works.

The cost is that user code can no longer treat "the stack" as a
free-form scratch area.  Every time you call a subroutine, a return
address slides under your data; every time you return, it slides
back out.  Reach below the top with `pick` or `swap`-of-`swap`-of-…
and you have to know how deep the current call chain is.  Forth
solves this by giving call/return its own stack — the **return
stack** — and leaving the **data stack** entirely to the user.  The
two grow independently, in separate regions of memory, with separate
primitives.

The split has a second benefit, which is the one we use in this
chapter.  Because the return stack is right there and the primitives
to access it are cheap, a colon definition can *borrow* a slot or
two for temporary storage.  As long as every push (`>r`) is matched
by a pop (`r>`) before the colon definition ends, the call/return
discipline is undisturbed and the borrowed slot looks invisible from
outside.  That's exactly what `over` does.

## 2. `>r` / `r>` / `r@` as a sidebar

The seed gives you three primitives for talking to the return stack:

```
>r  ( n -- ; R: -- n )    \ move from data stack to return stack
r>  ( -- n; R: n -- )     \ move from return stack to data stack
r@  ( -- n; R: n -- n )   \ copy the top of the return stack
```

The `R:` part of the stack-effect comment describes the **return
stack**'s before/after state, in the same `before -- after`
convention you already know.  `>r` pops one value off the data
stack and pushes it onto the return stack.  `r>` does the reverse.
`r@` is the non-destructive read: it leaves the return stack alone
and pushes a copy of its top to the data stack.

There is one rule that turns this from a footgun into a tool: **every
`>r` must be matched by a balancing `r>` within the same colon
definition.**  If you push to the return stack and never pop, the
next `;` will pop your value as if it were a return address and jump
to it — which, since your value is almost certainly not a valid
return address, will crash the VM.  Treat `>r … r>` like a bracket:
they nest, and they balance.

## 3. `over` via the return stack

`over ( a b -- a b a )` copies the second-from-top of the data stack
to the top.  Useful enough that it shows up dozens of times in the
later definitions in `010-lib.fth`.  The seed's authors did not make
it a primitive; they built it from four others:

```forth
: over  >r dup r> swap ;
```

Trace it on `( a b -- )`:

| token  | data stack | return stack | reasoning                          |
|--------|------------|--------------|------------------------------------|
| (in)   | `a b`      |              | initial state                      |
| `>r`   | `a`        | `b`          | park `b` on the return stack       |
| `dup`  | `a a`      | `b`          | now `dup` sees `a` on top          |
| `r>`   | `a a b`    |              | bring `b` back                     |
| `swap` | `a b a`    |              | put the new copy where it belongs  |

The trick is in the first move.  Without `>r`, the value on top is
`b`, and `dup` would copy `b` — not what we want.  Parking `b`
exposes `a`, `dup` does its job, and `r>` reunites the original `b`
with its copy of `a` so a final `swap` can order them.  The return
stack is untouched at the end (`b` went on with `>r` and came off
with `r>`), so the discipline holds.

If `over` were a primitive, it would cost zero extra tokens at the
call site.  As a derived word, every `over` is four tokens plus a
call.  But every primitive costs a slot in the dictionary and 20–30
bytes of machine code, and the seed is on a 2,040-byte budget.  Four
tokens per `over` is the cheaper bill.

## 4. `-` from `+` and `nand`

The seed also doesn't have subtraction as a primitive.  This is
defensible because two's complement makes subtraction a thin glaze
on top of addition.  Two's complement is the convention modern CPUs
use to represent signed integers: the negative of a value `b` is
defined as `~b + 1`, where `~b` is the bitwise complement.  The
neat property is that the same `ADD` instruction works for signed
and unsigned arithmetic — once you've produced the two's-complement
negation, you just add.

```
   (V) (V)
   ( o.o )   "subtraction made from add and bitwise-NAND.
   /\/\/\     a primitive slot saved by walking sideways."
```

From Ch 3 we already know that `dup nand` is the same as `~`.  So
to negate `b`, compute `b nand b` (which gives `~b`), then add 1.
To subtract `b` from `a`, add the negated `b` to `a`.  In Forth:

```forth
: -  dup nand [lit] 1 + + ;
```

Trace it on `( 10 3 -- )`:

| token       | stack          | reasoning                       |
|-------------|----------------|---------------------------------|
| (in)        | `10 3`         |                                 |
| `dup`       | `10 3 3`       | copy the subtrahend             |
| `nand`      | `10 ~3`        | `b nand b == ~b`                |
| `[lit] 1`   | `10 ~3 1`      | push the constant 1             |
| `+`         | `10 (~3+1)`    | `~3+1` is the two's-complement -3 |
| `+`         | `10 + (-3)`    | which is `7`                    |

End state: `7`.  ✓

Now trace `( 3 10 -- )` — the underflow case:

| token       | stack          |
|-------------|----------------|
| (in)        | `3 10`         |
| `dup`       | `3 10 10`      |
| `nand`      | `3 ~10`        |
| `[lit] 1`   | `3 ~10 1`      |
| `+`         | `3 -10`        |
| `+`         | `-7`           |

End state: `-7`.  In an unsigned reading of the bytes that's `2^64 -
7`, which is `0xFFFFFFFFFFFFFFF9`.  In a signed reading it's `-7`.
The bit pattern is identical; how you read it depends on whether
you care about sign.  Forth doesn't, mostly — the operators are
agnostic, and the same `+` and `-` work for both interpretations.

## 5. Why subtraction isn't a primitive

The trade is the same one Ch 3 spelled out for `nand`.  A primitive
costs a dictionary header (around 18 bytes for a short name) and a
machine-code body (15–30 bytes for a one-instruction primitive),
which is 30–50 bytes total.  A derived definition costs only the
dictionary header plus the compiled token sequence — and the tokens
are mostly already-paid-for calls to other primitives.

For `-`, the derived definition is five tokens: `dup`, `nand`,
`[lit]`, `1`, `+`, `+`.  Each call site pays a few extra bytes
relative to a hypothetical `SUB` primitive.  But there are only a
few dozen subtractions in the whole seed.  Saving the primitive
slot saves more bytes than the extra call-site overhead costs.

The book will keep meeting this pattern.  Comparisons (Ch 7) are
derived from `-` and a sign trick.  Division (Ch 7) is the only
"big" arithmetic primitive in the seed, because it would be too
expensive to derive.  Each choice asks the same question: would a
primitive save more bytes than the call-site overhead it eliminates?
If yes, primitivise; if no, derive.

## Canonical source

```forth file=010-lib.fth
\ over ( a b -- a b a )  copy second-from-top to top.
\ Standard Forth idiom, missing from our seed primitives.
: over  >r dup r> swap ;

\ - ( a b -- a-b )  subtract via 2's complement (we have + and nand).
\ Used by classifier helpers and the local rel32 CALL encoder below.
: -  dup nand [lit] 1 + + ;

```

## Try it

### The fast path: gforth

The seed's `over` and `-` already exist in standard Forth, but you
can define them under different names and verify they behave
identically.  In the playground:

```sh
gforth book/playground.fth
```

```forth
: my-over  >r dup r> swap ;
: my-sub   dup nand [lit] 1 + + ;

1 2 my-over .s    \ <3> 1 2 1
10 3 my-sub .     \ 7
3 10 my-sub .     \ -7    (gforth prints signed)
```

The `.s` form shows the entire data stack without consuming it.
The bracketed count `<3>` is gforth's depth indicator.

### The full path: build the seed

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo '[lit] 1 [lit] 2 over [lit] 48 + emit [lit] 48 + emit [lit] 48 + emit'
  echo '[lit] 10 [lit] 3 - [lit] 48 + emit'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

The first test prints `121`: `over` turns `( 1 2 )` into `( 1 2 1 )`,
and `+ 48 emit` on each value prints its ASCII digit.  The second
test prints `7`: `10 - 3 == 7`, plus 48 gives ASCII `7`.

## Exercises

1. **★★★** Derive `tuck ( a b -- b a b )` two ways: once via `swap over`,
   once via `>r dup r> swap`-style primitives.  Show that both
   produce identical bytes when compiled (you'll need a built
   seed-forth for the byte comparison; gforth optimises).

2. **★★** Trace `0 [lit] 1 -` on paper.  What does the data stack hold?
   What is the bit pattern (in hex)?  Why does that bit pattern
   represent `-1` in two's complement?

3. **★** Why does `-` have an extra `+` at the end (two `+`s total)?
   Walk the stack again and identify what each `+` consumes.

4. **★★** Write `negate ( n -- -n )` using only `nand`, `[lit]`, and `+`.
   How many tokens?  Compare to `0 swap -`.

## Takeaways

- The return stack is a second LIFO that exists primarily for
  call/return.  User code may borrow it via `>r`/`r>` provided
  every push is matched by a pop *within the same word*.
- `over` is not a primitive in this seed; it is built from four
  other primitives in five tokens.
- Subtraction is not a primitive either; it is built from `+` and
  `nand` in five tokens.  Both choices reflect the seed authors'
  preference for fewer primitive slots at the cost of slightly
  longer derived definitions.

Next: Chapter 5 — Talking to Linux: `syscall6` Wrappers.
