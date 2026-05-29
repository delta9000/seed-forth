# Chapter 3 — Logic from One Primitive

```text
Missing capability: only nand exists; and, or, not, xor don't.
New pattern: De Morgan's law as code — derive every Boolean operator from nand alone.
Artifact after this chapter: a complete Boolean toolkit on top of one primitive.
Proof link: the C compiler's lvalues and control-flow use these without ever re-deriving them.
```

The seed keeps exactly one bitwise primitive, `nand`, and builds
every other boolean operator on top of it in Forth.  This chapter
defines `and` and `or` (lines 22–30 of `010-lib.fth`, the section
header plus two short colon definitions) and uses them to motivate
why a single primitive is enough.  Open `010-lib.fth` to that
nine-line block; the rest of the chapter is the argument for the
trade and a walk through the two derivations.  The bigger payoff,
`not` and `xor`, falls out as exercises once you see how `nand
dup nand` and De Morgan's law fit together.

By the end of the chapter you'll be able to explain why `nand`
alone is functionally complete (every two-valued boolean function
expressible from it), derive `and`, `or`, `not`, and `xor` from
`nand`, and read a chained-nand expression and predict its truth
table.  The hex bytes of the `nand_code` primitive in
`000-seed.hex0` are Part II, Ch 15; the deeper "why not `and` plus
`invert` separately" question is touched on here and fully covered
when we read the seed in Part II.

---

If you could keep exactly one bitwise primitive in your CPU, which
would you keep?

The answer matters because the seed-forth project lives inside a
strict size budget — 2,040 bytes for the entire seed binary, of
which every primitive consumes both a slot in the dictionary and a
few dozen bytes of machine code.  Cutting "logic" down to a single
primitive is one of the moves that lets the whole project fit.

There's only one right answer: **`nand`** (or its dual, `nor`).  And
alone won't do it.  Or alone won't do it.  Even `and` plus `or`
together won't do it.  None of those can produce a negation, and
without negation you're stuck — there's no way to flip a bit.

Pick `nand` and you can build everything: `not`, `and`, `or`, `xor`,
all the predicates, all the boolean glue the rest of `010-lib.fth`
will need.  In this chapter we build `and` and `or`.  The rest fall
out as exercises.

## 1. Why "logic from nand" matters

The property that makes `nand` valuable has a name: **functional
completeness.**  A boolean function is functionally complete if you
can express every other boolean function using only that one
function and your input variables (duplicated and reused as needed).
`nand` and `nor` are the two two-input functions with this property.
`and`, `or`, `xor` are not.

The intuition is this: every boolean function you can write down has
some inputs where it produces 0 and some where it produces 1.  You
can always express the function as "for each input combination where
the output is 1, AND the inputs together (negating the 0-inputs);
then OR all those terms."  That's the disjunctive normal form.  It
needs three things: AND, OR, NOT.  Once you have NOT and one of
{AND, OR}, you can derive the other via De Morgan's law.  And NAND
gives you NOT (just feed it the same value twice) and AND (NAND
followed by NOT, which is itself NAND-of-itself).

So the seed authors made a trade:

- **Cost:** the Forth-level definitions of `and`, `or`, etc. are 1–5
  tokens longer than they would be if those were primitives.
- **Benefit:** one primitive slot saved per boolean function not
  primitivised, plus the dictionary header (10 + name-length bytes)
  not paid for.

You'll see the same trade made again in Ch 4 (`-` derived from `+`
and `nand`) and Ch 7 (every comparison operator derived from `-` and
unsigned `/`).  Each time, the seed pays a little more at use-site
to save a primitive slot.

## 2. `and` in three words

Here's the definition:

```forth
: and  nand dup nand ;
```

Trace it with input `( a b -- a&b )`.  The colon definition runs
left to right:

| token  | stack after        | reasoning                       |
|--------|--------------------|---------------------------------|
| (in)   | `a b`              | initial state                   |
| `nand` | `~(a & b)`         | the seed primitive does its job |
| `dup`  | `~(a&b) ~(a&b)`    | duplicate the negated AND       |
| `nand` | `~(~(a&b) & ~(a&b))` | NAND of a thing with itself   |

That last line simplifies.  Anything ANDed with itself is itself, so
`x & x == x`.  And NAND-of-a-thing-with-itself is NOT of that thing.
So:

```
~(~(a&b) & ~(a&b)) == ~(~(a&b)) == a & b
```

Two negations cancel.  The chain ends with `a & b` on the stack.  ✓

The pattern `dup nand` is going to recur.  Read it as "NOT this
value."  We just used it to undo the negation that the initial
`nand` introduced.

## 3. `or` in five words

OR is harder because the obvious approach — "NOT (NOT a AND NOT b)
by De Morgan" — needs to negate each input separately, then combine,
then negate again.  Three NOTs plus an AND, where every NOT becomes
a `dup nand`.  Mechanically:

```forth
: or   dup nand swap dup nand nand ;
```

Trace with input `( a b -- a|b )`:

| token  | stack after          | reasoning                       |
|--------|----------------------|---------------------------------|
| (in)   | `a b`                | initial state                   |
| `dup`  | `a b b`              | copy `b`                        |
| `nand` | `a ~b`               | `b nand b == ~b`                |
| `swap` | `~b a`               | bring `a` to top                |
| `dup`  | `~b a a`             | copy `a`                        |
| `nand` | `~b ~a`              | `a nand a == ~a`                |
| `nand` | `~(~b & ~a)`         | NAND of the two negated inputs  |

The last line is exactly De Morgan: `~(~a & ~b) == a | b`.  ✓

Sanity-check on the four corners (using Forth's `-1` for true and
`0` for false):

```
-1 -1 or  →  -1   (true  | true  == true)
-1  0 or  →  -1   (true  | false == true)
 0 -1 or  →  -1   (false | true  == true)
 0  0 or  →   0   (false | false == false)
```

You can confirm this in the playground (see "Try it" below).

The `swap` is the price of using a stack: with named arguments
you'd write `~(~a & ~b)` and call it a day.  With a stack, you have
to choreograph which value is on top when, and `swap` is how you do
it.  Get used to that — every Forth function reads partly as logic
and partly as a stack-shuffle plan.

## 4. Sidebar: `xor` and `not`

`010-lib.fth` doesn't define `xor` or `not` because nothing in the
codebase needs them.  But they're worth deriving once so you know
the seed isn't *missing* anything — it just isn't paying for what
no caller uses.

**`not` in three words:**

```forth
: not  dup nand ;
```

That's the `dup nand` trick we kept seeing, named.  Stack effect
`( a -- ~a )`.

How does `not` differ from `0=`?  `0=` is a seed primitive that
returns `-1` if the input is exactly `0`, else `0`.  It produces
*Forth* booleans (canonical `-1`/`0`).  `not` flips every bit; on
input `0` it returns `-1`, on input `-1` it returns `0`, but on
input `5` it returns `0xFFFFFFFFFFFFFFFA` — not a Forth boolean.
For arithmetic, use `not`; for predicate-chaining, use `0=`.

**`xor` by reusing `or` and `and` (cheating):**

```forth
: xor  ( a b -- a^b )  2dup nand >r or r> and ;
```

That uses `2dup`, `nand`, `or`, `and` — three of which we already
have or are about to define.  It's `(a or b) and (a nand b)`: the
two inputs differ when at least one is set *and* not both are set.

**`xor` from pure nand:**

```forth
: xor-pure  ( a b -- a^b )
  2dup nand                ( a b nab )
  >r over r@ nand          ( a b a-nab )
  swap r> nand             ( a a-nab b-nab )
  nand ;                   ( ... )
```

(`r@` peeks the top of the return stack without removing it; the
seed provides it as one more primitive alongside `>r` and `r>`.
This is a preview — Ch 4 introduces the return-stack family
formally.)

Four NANDs and some shuffling.  This is the form a textbook would
show for "XOR using only NAND gates."  It's longer than the
`or`/`and` version because we refuse to reuse intermediate logic
words — we're proving NAND alone is enough, not optimising.

```
       __
   __( o)>   "four NANDs for one XOR.  worth it for the punchline."
   \___/
```

## 5. What this buys

Look at what's now buildable from one primitive:

| Word | Tokens | Built from |
|------|--------|-----------|
| `not` | 2  | `dup nand` |
| `and` | 3  | `nand dup nand` |
| `or`  | 5  | `dup nand swap dup nand nand` |
| `xor` | 8  | as above |

Compare against the alternative seed where `and`, `or`, `not` are
each primitives.  Each saved primitive is:

- one dictionary entry (link cell + flags byte + name length +
  name bytes + body) — at minimum 10 + name-length bytes;
- a few dozen bytes of machine code for the body itself;
- a slot in the assembly-time chain that maintains `LATEST`.

Multiply by three saved primitives — `and`, `or`, `not` — and
you've saved roughly 100 bytes of seed binary plus three CALL
targets, in exchange for adding nine extra tokens to a handful of
Forth-level definitions that get called sparingly.

This is the seed's central design move: **pick the primitives that
buy you the most expressive power per byte**.  `nand` is one such
primitive.  Ch 4's two's complement subtract turns `-` into another
saved slot.  Ch 7's unsigned `/` lets one division primitive cover
both arithmetic *and* sign-bit extraction, which lets every
comparison operator be derived rather than primitive.  By the end
of Part I you'll see this principle has been applied everywhere; it
is what makes 2,040 bytes enough.

## Canonical source

```forth file=010-lib.fth
\ ----- bool / bitwise helpers built on nand -----
\ All derived because nand is the only logical primitive in the seed.

\ and ( a b -- a&b ) = ~~(a&b) = nand of nand-of-itself
: and  nand dup nand ;

\ or  ( a b -- a|b ) via De Morgan: ~(~a & ~b)
: or   dup nand swap dup nand nand ;

```

## Try it

In gforth via the playground (which provides `nand` as `and invert`,
matching the seed's semantics):

```forth
\ Load the shim:
include book/playground.fth

\ Paste our definitions to shadow gforth's built-in and/or:
: and  nand dup nand ;
: or   dup nand swap dup nand nand ;

\ Truth-table check using -1 (all bits set) and 0 (all bits clear):
-1 -1 and .   \ -1
-1  0 and .   \ 0
 0 -1 and .   \ 0
 0  0 and .   \ 0
-1 -1 or  .   \ -1
-1  0 or  .   \ -1
 0 -1 or  .   \ -1
 0  0 or  .   \ 0
```

If you've built the seed (`./build.sh`), the same definitions work
there too — but the seed's REPL doesn't strip `\` comments, so the
library has to be passed through `sed` first (the same trick
`test.sh` uses).  Also, the seed's number parser is decimal and
unsigned-only, and the seed has no `.` for printing, so we use
`emit` instead and pick inputs that produce a printable byte:

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo ': mand  nand dup nand ;'
  echo '[lit] 12 [lit] 10 mand [lit] 48 + emit bye'
} | grep -v '^[[:space:]]*$' | ./seed-forth
# prints: 8     (12 AND 10 == 8, plus 48 is ASCII '8')
```

We name it `mand` rather than `and` in the seed REPL because the
seed already defined `and` when it loaded `010-lib.fth` at startup,
and re-defining a word would just create a shadow (which would still
work, but is noisier to read).

## Exercises

1. **★★ Extend.** Define `xor ( a b -- a^b )` in terms of `nand` alone — no
   intermediate `and`/`or`.  Confirm with the four-row truth table.
   Compare your token count to the `(a or b) and (a nand b)` form.

2. **★★★ Extend.** Define `not ( a -- ~a )` in terms of `nand` alone.  How does
   `not` differ from `0=`?  Construct an input where `not` and
   `0=` disagree.

3. **★★★ Trace.** Prove on paper that `nor` is also functionally complete.  Then
   redefine `and` and `or` using only `nor`.  How many tokens
   longer do they become?  (Asymmetric: NOR-based `and` is short,
   NOR-based `or` is long — figure out why.)

4. **★★★ Trace.** The seed could have spent a primitive slot on `not` and reduced
   `and` to one fewer token.  Estimate the byte cost of that primitive
   slot (10 bytes header + ~12 bytes body) and compare to the byte
   savings (one less token, in maybe a dozen call sites in
   `010-lib.fth`).  Was the seed authors' choice optimal?

## Takeaways

- `nand` is functionally complete: every boolean function is
  expressible.
- `and = nand dup nand` and `or = dup nand swap dup nand nand` are
  not clever — they are direct transcriptions of "double negation"
  and "De Morgan's law."
- Picking the right primitive saves bytes in the seed.  We will see
  the same logic applied again in Ch 7 (comparisons from one
  arithmetic primitive: subtract).

Next: Chapter 4 — The Return Stack: `over` and Subtract.
