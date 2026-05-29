# Chapter 8 — Stack Shufflers

```text
Missing capability: the seed has dup, drop, swap but not nip, rot, 2dup, 2drop.
New pattern: a small library of stack-effect transforms, each defined in one line over the seed.
Artifact after this chapter: the everyday stack-shuffling vocabulary.
Proof link: codegen passes use these to keep argument order straight without an exit primitive.
```

Four short shuffles in `010-lib.fth` (lines 123–137), `nip`, `rot`,
`2dup`, and `2drop`, round out the classical Forth shuffle
vocabulary on top of the five primitives Ch 1 introduced and the
derived `over` Ch 4 added.
None of them invents a new idea (`nip` is `swap drop`; `rot`
generalises Ch 4's return-stack trick one slot deeper; `2dup` is
`over over`; `2drop` is `drop drop`), but having them named by
reflex is what makes Forth feel like dancing on the stack instead
of fighting it.  Open `010-lib.fth` to those 16 lines and read
along; the prose argues each derivation and quietly justifies why
the seed names some of these and inlines others.

By the end of the chapter you'll be able to read and write all the
classical Forth shuffle words by name, derive arbitrary shuffles
using only the seed's five stack-manipulation primitives (`dup`,
`drop`, `swap`, `>r`, `r>`), and explain why deep-stack operators
like `pick` and `roll` aren't worth defining in this seed (and
what their cost would be).  `pick` and `roll` themselves get only
brief discussion; the C compiler's heavy use of `>r r@ r>` for
register-spill-like patterns is Part III, Ch 26.

---

Ch 1 introduced five stack primitives and Ch 4 derived a sixth
shuffle, `over`, from them.  Six shuffles are not quite enough
vocabulary to write ergonomic Forth, so this chapter adds four more
that fill out the standard shuffle library — each just two or four
primitives glued together.

## 1. `nip` — the simplest derivative

```forth
: nip   swap drop ;
```

`nip ( a b -- b )` discards the second-from-top of the stack and
keeps the top.  Read literally: swap the two values, then drop the
one that's now on top.  After `swap`, `( a b )` becomes `( b a )`;
after `drop`, just `( b )`.  Two tokens, no surprises.

This is what you'd write if you forgot `nip` existed.  The named
form is shorter, slightly faster (one CALL instead of two), and
self-documenting — anyone reading `nip` knows immediately what it
does.  Unnamed `swap drop` is fine in a one-off, but the lexer in
Part III uses `nip` dozens of times in its dispatch logic and the
name carries its weight.

## 2. `rot` — the return-stack trick, generalised

```forth
: rot   >r swap r> swap ;
```

`rot ( a b c -- b c a )` rotates the *third-from-top* up to the top.
This is the same trick Ch 4 used for `over`, applied one level
deeper.

Trace it on input `( a b c -- )`:

| token  | data stack | return stack |
|--------|------------|--------------|
| (in)   | `a b c`    |              |
| `>r`   | `a b`      | `c`          |
| `swap` | `b a`      | `c`          |
| `r>`   | `b a c`    |              |
| `swap` | `b c a`    |              |

The pattern: park the top value out of the way, shuffle the bottom
two, restore the parked value, and finish with one more swap to put
things in the desired order.  Whenever you need the third-from-top
and don't want to think too hard, this is the move.

Why isn't `rot` a primitive?  Same calculation as Ch 4: a four-token
derived definition costs about 24 bytes (header + four CALL sites)
versus 30–40 bytes for a primitive's machine body.  And `rot` is
common-enough-to-name but rare-enough-to-derive: the seed uses it
fewer than ten times.

## 3. `2dup` from `over over`

```forth
: 2dup  over over ;
```

`2dup ( a b -- a b a b )` duplicates the top *pair* of cells.  The
implementation is just `over` twice.

Trace it:

| token  | stack                |
|--------|----------------------|
| (in)   | `a b`                |
| `over` | `a b a`              |
| `over` | `a b a b`            |

After the first `over`, the stack is `a b a` — the original `a` has
been copied to the top.  Now apply `over` again: it copies the
*new* second-from-top (which is `b`, not the original `a`) to the
top.  Result: `a b a b`.

Why this works without thinking about pair-ness: `over` doesn't know
or care that `a` and `b` are "a pair."  Each invocation just copies
the second-from-top to the top.  Two invocations happen to produce
the same result as a hypothetical primitive that duplicated two
cells.  Free pair-dup from a pair of single-copies.

The trick does not extend for free, though: three `over`s do *not*
give you `3dup` — copying a triple needs more than three single-copies.
That asymmetry informs why the seed stops at `2dup`: `2dup` is cheap
and used; deeper pair-shuffles are uncommon enough to inline at call
sites when needed.

## 4. `2drop` is just `drop drop`

```forth
: 2drop drop drop ;
```

`2drop ( a b -- )` discards the top pair.  Two `drop`s.  There is
nothing more to say.

Two tokens makes this almost not worth naming, but the C compiler
in Part III uses it everywhere it discards a parameter pair (mostly
on error paths after a partial parse).  Reading `2drop` is more
obvious than reading `drop drop` and counting; the name signals "I
am dropping a logical pair, not coincidentally two adjacent items."

## 5. What's missing and why

Standard Forth also defines `pick ( ... n -- ... x_n )` and
`roll ( ... n -- ... )`.  These let you reach an arbitrary depth into
the stack indexed by `n`.  Neither is in this seed.

The reason is mechanical.  `pick` and `roll` need to read the stack
at a *runtime-computed* offset.  The seed's stack pointer is
`rbp`-relative and accessed only via the primitives `dup`, `drop`,
`swap`, `>r`, `r>` — none of which take a depth parameter.
Implementing `pick(n)` from those primitives requires generating an
unrolled chain proportional to `n`: e.g. `pick(3)` could be expressed
as `>r >r >r dup r> swap r> swap r> swap` or similar.  But you'd
need a different definition for every `n`, or a runtime loop, and
neither approach fits in the byte budget.

The deeper reason is that the seed's intended use — bootstrapping a
C compiler — doesn't need `pick` or `roll`.  The C compiler keeps
its data-stack depth shallow at every dispatch point (typically
three or four cells) and uses the return stack as scratch when it
needs more breathing room.  Code that wants deep-stack access in
this style of Forth is generally a sign of a missing abstraction —
the standard advice is "use a variable or a local instead."  The C
compiler follows that advice; the seed does not include `pick` or
`roll`; and the byte budget stays in shape.

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
`.`s gives `1 3 2` — top first.

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

## Exercises

1. **★★ Extend.** Define `tuck ( a b -- b a b )` two ways: as `swap over` and using
   `>r dup r> swap`.  Which compiles to fewer bytes?

2. **★★ Extend.** Define `-rot ( a b c -- c a b )` (the inverse of `rot`) using
   *only* the seed's primitives plus already-defined helpers.

3. **★★ Extend.** Define `2swap ( a b c d -- c d a b )`.  Hint: `rot >r rot r>`
   is one route.

4. **★★★ Trace.** Why is `pick` ( ... n -- ... x_n ) hard to define here?  Trace
   what it would have to do for `n=3` using only `dup`, `swap`,
   `drop`, `>r`, `r>`.  Show that the token count grows linearly
   with `n`, not constant-time.

## Takeaways

- Every shuffle is either a primitive or a short composition of
  primitives.  The shuffle vocabulary is finite — about a dozen
  classical names, all derivable.
- The return stack is used as a temporary parking spot for values
  that need to skip past `dup` / `over` operations.  The discipline
  is: `>r` and `r>` come in pairs *within the same word*.
- Deeper-than-third-of-stack access is not provided by this seed.
  Code that wants it must restructure or use the return stack
  explicitly.

Next: Chapter 9 — Memory Updates and Cell Writers.
