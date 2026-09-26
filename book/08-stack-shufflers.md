# Chapter 8 — Stack Shufflers

```text
Missing capability: the seed has dup, drop, swap but not nip, rot, 2dup, 2drop.
New pattern: a small library of stack-effect transforms, each defined in one line over the seed.
Artifact after this chapter: the everyday stack-shuffling vocabulary.
Proof link: the lexer (Ch 23) and the parsers (Chs 27-31) shuffle operands with these between emits.
```

With `dup`, `drop`, `swap`, `>r`, `r>`, and Ch 4's `over`, you can
already write any shuffle.  What you can't yet do is write one
without counting.  `swap drop` and `drop drop` are easy to misread
in the middle of a parser, and a missed `swap` is a bug that only
shows up three words later.

`010-lib.fth` (lines 123–137) names four more: `nip`, `rot`, `2dup`,
and `2drop`.  Ch 1 previewed all four, and nothing new happens
inside them.  The interesting question is the one standard Forth
answers differently: why this seed has no `pick`, and why the C
compiler never misses it.

## 1. The four shuffles

```forth
: nip   swap drop ;        \ ( a b -- b )        drop second-from-top
: rot   >r swap r> swap ;  \ ( a b c -- b c a )  third-from-top to top
: 2dup  over over ;        \ ( a b -- a b a b )  duplicate the top pair
: 2drop drop drop ;        \ ( a b -- )          drop the top pair
```

`nip` and `2drop` are too short to need a trace.  `rot` is Ch 4's
park-on-the-return-stack trick one slot deeper: `>r` parks the top
value, `swap` reorders the bottom two, `r>` brings the parked value
back, and a final `swap` lands the result `( a b c -- b c a )`.

`2dup` is the one worth a second look, because it shows why the seed
stops here.  `over` doesn't know or care that `a` and `b` are "a
pair": each call just copies the second-from-top, so two calls happen
to duplicate the pair.  You get `2dup` free from a pair of
single-copies.  But the trick does *not* extend: three `over`s do
**not** give you `3dup` (copying a triple needs more than three
single-copies).  That asymmetry is why `2dup` earns a name and deeper
pair-shuffles are left to be inlined at the rare call site that wants
them.

Why name a two-token word at all?  Size (one CALL at each call site
instead of two) and self-documentation.  Part III's lexer reaches for `nip` four times,
and the compiler uses `2drop` where it discards a half-parsed
pair.  `2drop` says "I am dropping a logical pair"; `drop drop`
makes you stop and count.

## 2. What's missing and why

Standard Forth also defines `pick ( ... n -- ... x_n )` and
`roll ( ... n -- ... )`.  These let you reach an arbitrary depth into
the stack indexed by `n`.  Neither is in this seed.

The reason is mechanical.  `pick` and `roll` need to read the stack
at a *runtime-computed* offset.  The seed's stack pointer is
`rbp`-relative and accessed only via the primitives `dup`, `drop`,
`swap`, `>r`, `r>`, none of which take a depth parameter.
Implementing `pick(n)` from those primitives requires generating an
unrolled chain proportional to `n`: e.g. `pick(3)` could be expressed
as `>r >r >r dup r> swap r> swap r> swap` or similar.  But you'd
need a different definition for every `n`, or a runtime loop, and
neither approach fits in the byte budget.

The deeper reason is that bootstrapping a C compiler doesn't need
`pick` or `roll`.  The C compiler keeps its data stack three or four
cells deep at every dispatch point and uses the return stack as
scratch when it needs more.  Deep-stack access in Forth usually
signals a missing abstraction, and the standard advice, "use a
variable instead," is what the compiler follows.

If you ported a Forth program that *did* need `pick`, the cheapest
fix in this seed would be to define `variable`-backed slot
storage (Ch 12) and read/write through it, which is more verbose
than `pick` but doesn't grow the primitive set.

## Canonical source

```forth file=010-lib.fth
\ ===== Stack shuffles =====
\ Standard Forth stack-manipulation words built on the seed primitives
\ swap, dup, drop, >r, r>, plus over (defined above).

\ nip ( a b -- b )  drop second-from-top.
: nip   swap drop ;

\ rot ( a b c -- b c a )  rotate third-from-top to top.
: rot   >r swap r> swap ;

\ 2dup ( a b -- a b a b )  duplicate the top pair.
: 2dup  over over ;

\ 2drop ( a b -- )  drop the top pair.
: 2drop drop drop ;

```

## Try it

### The fast path: gforth

All four shuffles are built-in to gforth; the playground definitions
will shadow them.  Save as `/tmp/ch8.fth` and run with `gforth
book/playground.fth /tmp/ch8.fth`:

```forth
: nip   swap drop ;
: rot   >r swap r> swap ;
: 2dup  over over ;
: 2drop drop drop ;

1 2 nip       . cr        \ 2
1 2 3 rot     . . . cr    \ 1 3 2     (printed top-down)
1 2 2dup      . . . . cr  \ 2 1 2 1   (printed top-down)
1 2 3 4 2drop . . cr      \ 2 1
bye
```

Reading the `rot` line: `1 2 3 rot` leaves `2 3 1` on the stack (the
old third-from-top is now on top).  Printing top-down with three
`.`s gives `1 3 2`, top first.

### The full path: build the seed

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo '[lit] 65 [lit] 66 nip emit'
  echo '[lit] 65 [lit] 66 [lit] 67 rot emit emit emit'
  echo '[lit] 88 [lit] 89 2dup emit emit emit emit'
  echo '[lit] 65 [lit] 66 [lit] 67 [lit] 68 2drop emit emit'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

Expected output: `BACBYXYXBA`.  Trace each line:

- `65 66 nip emit` → `nip` drops 65, leaving 66; `emit` prints `B`.
- `65 66 67 rot emit emit emit` → `rot` gives stack `66 67 65`;
  three `emit`s print `A C B` (top-first).
- `88 89 2dup emit emit emit emit` → stack `88 89 88 89`; four
  `emit`s print `Y X Y X`.
- `65 66 67 68 2drop emit emit` → `2drop` leaves `65 66`; two
  `emit`s print `B A`.

Ten letters, and each one landed where the stack-effect comment
said it would.

## Exercises

1. **★ Trace.** `rot` reaches the third-from-top cell but no deeper.
   Predict the final stack for `1 2 3 4 rot`, written bottom-to-top,
   then check with `1 2 3 4 rot .s` in the playground.  Which value
   ended up on top, and where did it start?

2. **★★ Extend.** Define `tuck ( a b -- b a b )` two ways: as `swap over` and using
   `>r dup r> swap`.  Which compiles to fewer bytes?

3. **★★ Extend.** Define `-rot ( a b c -- c a b )` (the inverse of `rot`) using
   *only* the seed's primitives plus already-defined helpers.

4. **★★ Extend.** Define `2swap ( a b c d -- c d a b )`.  Hint: `rot >r rot r>`
   is one route.

5. **★★★ Trace.** Why is `pick` ( ... n -- ... x_n ) hard to define here?  Trace
   what it would have to do for `n=3` using only `dup`, `swap`,
   `drop`, `>r`, `r>`.  Show that the token count grows linearly
   with `n`, not constant-time.

## Takeaways

- `nip`, `rot`, `2dup`, and `2drop` are short compositions of the
  seed's primitives and `over`, named so call sites read clearly.
- `rot` reuses Ch 4's return-stack parking trick one slot deeper,
  with `>r` and `r>` paired inside the word.
- The seed provides no access deeper than the third cell (no `pick`
  or `roll`), so code that needs it keeps the stack shallow or uses
  variables.

**Part I tally.**  Built so far: byte emission, Boolean logic,
subtraction, file I/O, character tests, comparisons, **named
shuffles**.  Still missing: multi-byte writes, `constant`, `if,`,
`variable`.

Next: Chapter 9 — Memory Updates and Cell Writers.  `c,` writes one
byte, but every x86 `CALL` the library will assemble carries a
4-byte offset, and the seed has no shift instruction to split a
number into bytes.
