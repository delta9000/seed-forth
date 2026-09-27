# Chapter 4 — The Return Stack: `over` and Subtract

```text
Missing capability: nowhere safe to stash a temporary across nested calls.
New pattern: a second rsp-based stack with >r, r>, r@; subtraction built from nand.
Artifact after this chapter: temporary storage with stack discipline, plus - derived from + and nand.
Proof link: Ch 7 builds every comparison on -; Ch 27's parser threads its operator byte through the return stack.
```

Two everyday operations are still impossible.  The seed can add but
not subtract: there is `+` and no `-`.  And it cannot copy the value
*under* the top of the stack, because `dup` only ever sees the top.
With `a b` on the stack, no sequence of `dup`, `drop`, and `swap`
ever produces `a b a`.

The next definitions in `010-lib.fth` (lines 34–45) close both
gaps without a new primitive.  `over` parks `b` somewhere else for a
moment, and the seed has exactly one somewhere else: the return
stack.  `-` borrows two's complement and Ch 3's `dup nand`.  Ch 1
previewed both words; this chapter gives the reasons behind them,
and the return-stack rules that every later chapter relies on.  The seed's `>r`/`r>` machine code is Ch 14, and how `:` and
`;` themselves use the return stack is Ch 18.

## 1. Why two stacks at all?

A virtual machine needs somewhere to remember "where to return when
this subroutine finishes."  The obvious choice is the same stack
that holds the subroutine's arguments and locals: push the return
address before the call, pop it on return.  That's what C does, and
what most procedural VMs do, and it works.

The cost is that user code can no longer treat "the stack" as a
free-form scratch area.  Every time you call a subroutine, a return
address slides under your data; every time you return, it slides
back out.  Reach below the top with `pick` or `swap`-of-`swap`-of-…
and you have to know how deep the current call chain is.  Forth
solves this by giving call/return its own stack, the **return
stack**, and leaving the **data stack** entirely to the user.  The
two grow independently, in separate regions of memory, with separate
primitives.

The split has a second benefit.  Because the return stack is right there and the primitives
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
to it.  Your value is almost certainly not a valid return address,
so the VM crashes.  Treat `>r … r>` like a bracket:
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
`b`, and `dup` would copy `b`, which is not what we want.  Parking `b`
exposes `a`, `dup` does its job, and `r>` reunites the original `b`
with its copy of `a` so a final `swap` can order them.  The return
stack is untouched at the end (`b` went on with `>r` and came off
with `r>`), so the discipline holds.

The call site doesn't care which way `over` is built: either way,
each use compiles to one 5-byte `CALL`.  The difference is paid
elsewhere.  The derived body is four `CALL`s and a `RET` (21 bytes)
in `010-lib.fth`, and at runtime every `over` executes four nested
calls where a primitive would run a few instructions.  A primitive
instead costs a slot in the dictionary and 20–30 bytes of machine
code in the seed, and the seed is on a 1,772-byte budget.  Some
extra cycles per `over` is the cheaper bill.

## 4. `-` from `+` and `nand`

Now the second gap: how do you subtract with only `+`?  Add the
negation.  Two's complement, the convention modern CPUs use for
signed integers, defines the negative of `b` as `~b + 1`, where `~b`
is the bitwise complement, and the same `ADD` works for signed and
unsigned values.  So subtraction needs only a way to flip bits.

Ch 3 already supplied one: `dup nand` is `~`.  So
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

Now trace `( 3 10 -- )`, the underflow case:

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
you care about sign.  Forth mostly doesn't: the operators are
agnostic, and the same `+` and `-` work for both interpretations.

## 5. Why subtraction isn't a primitive

This is Ch 3's trade again, with the same arithmetic as `over` in §3.  A primitive costs a dictionary header
(around 18 bytes for a short name) and a machine-code body (15–30
bytes for a one-instruction primitive), which is 30–50 bytes total.
A derived definition costs a header plus a sequence of calls to
primitives that are already paid for.

For `-`, the derived definition is six tokens: `dup`, `nand`,
`[lit]`, `1`, `+`, `+`.  Call sites cost nothing extra: each `-` is
one 5-byte `CALL`, exactly what a hypothetical `SUB` primitive would
compile to.  The price is runtime: every `-` executes five nested
calls (one of them to `lit` for the inline `1`) instead of one `sub`
instruction.

Division `/` and multiplication `*` go the other way.  They are the
seed's only "big" arithmetic primitives, because deriving them would
cost more than the bytes they take.  And `-` will not stay a
convenience: Ch 7 builds every comparison on it.

Two more one-liners follow `-`: `1+` and `1-`, which add and
subtract one.  They shrink a call site from 18 bytes (`[lit] 1 +`
is a 13-byte literal and a 5-byte CALL) to 5, but that is not why
they exist.
Stepping a pointer, a counter or a length by one is the commonest
arithmetic in the C compiler, and `1+` says it in one token.

## Canonical source

```forth file=010-lib.fth
\ over ( a b -- a b a )  copy second-from-top to top.
\ Standard Forth idiom, missing from our seed primitives.
: over  >r dup r> swap ;

\ - ( a b -- a-b )  subtract via 2's complement (we have + and nand).
\ Used by classifier helpers and the local rel32 CALL encoder below.
: -  dup nand [lit] 1 + + ;

\ 1+ ( n -- n+1 )   1- ( n -- n-1 )  Step by one: the commonest arithmetic
\ in the C compiler (pointers, counters, lengths), so it gets a name.
: 1+  [lit] 1 + ;
: 1-  [lit] 1 - ;

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
{ cat 010-lib.fth
  echo '[lit] 1 [lit] 2 over [lit] 48 + emit [lit] 48 + emit [lit] 48 + emit'
  echo '[lit] 10 [lit] 3 - [lit] 48 + emit'
} | ./seed-forth
```

The first test prints `121`: `over` turns `( 1 2 )` into `( 1 2 1 )`,
and `+ 48 emit` on each value prints its ASCII digit.  The second
test prints `7`: `10 - 3 == 7`, plus 48 gives ASCII `7`.  Both words
you just ran were impossible with the seed alone; each is one line
of Forth.

## Exercises

1. **★★★ Extend.** Derive `tuck ( a b -- b a b )` two ways: once via `swap over`,
   once inlining `over`'s primitives (`swap >r dup r> swap`).  Both
   leave the same stack, but they compile to different bytes: count
   the `CALL`s in each body, and the calls each one executes at
   runtime.  (You'll need a built seed-forth to inspect the bytes;
   gforth optimises.)

2. **★★ Trace.** Trace `0 [lit] 1 -` on paper.  What does the data stack hold?
   What is the bit pattern (in hex)?  Why does that bit pattern
   represent `-1` in two's complement?

3. **★ Trace.** Trace `-` on `( 0 0 -- )` and on `( 5 5 -- )`
   row by row, as in §4.  At which step does an addition carry out
   of bit 63, and why is it safe for `+` to drop that carry?

4. **★★ Extend.** Write `negate ( n -- -n )` using only `nand`, `[lit]`, and `+`.
   How many tokens?  Compare to `0 swap -`.

## Takeaways

- The return stack exists for call/return, and a word may borrow it
  with `>r`/`r>` as long as every push is matched by a pop within
  the same word.
- `over` is not a primitive; it parks `b` on the return stack so
  `dup` can reach `a`, in four tokens.
- Subtraction is `+` of the two's-complement negation `(b nand b) + 1`,
  which saves a primitive slot at the cost of five nested calls per
  use.

**Part I tally.**  Built so far: byte emission, Boolean logic,
**`over` and subtraction**.  Still missing: files and exit, `<`,
`if,`, `variable`.

Next: Chapter 5 — Talking to Linux: `syscall6` Wrappers.  Everything
so far happens inside the process, but a compiler has to read a file
and write one.  The seed's only door to the kernel is `syscall6`, a
primitive that takes seven arguments at once.
