# Chapter 3 — Logic from One Primitive

```text
Missing capability: only nand exists; and, or, not, xor don't.
New pattern: De Morgan's law as code — derive every Boolean operator from nand alone.
Artifact after this chapter: a complete Boolean toolkit on top of one primitive.
Proof link: Ch 6's classifiers and the lexer's compound tests (Ch 23) run on this toolkit, never re-derived.
```

If you could keep exactly one bitwise primitive, which would you
keep?

The seed has to answer that question because it lives inside a
strict size budget: 2,040 bytes for the entire binary, where every
primitive costs a dictionary slot and a few dozen bytes of machine
code.  Cutting logic down to a single primitive is one of the moves
that lets it fit.

The answer is **`nand`** (or its dual, `nor`).
`and` alone won't do it, nor will `or`, nor both together.  None of
them can produce a negation, and without negation there's no way to
flip a bit.

Pick `nand` and you can build everything the rest of `010-lib.fth`
needs.  The library's boolean section (lines 23–30) defines just
`and` and `or`; this chapter derives those two and then `not` and
`xor` as a sidebar.  The machine code of `nand_code` itself is
Ch 15.

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

§5 tallies what that trade buys, and where else the seed makes it.

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

## 3. `or` in six words

OR is harder because the obvious approach, "NOT (NOT a AND NOT b)"
by De Morgan, needs to negate each input separately, then combine,
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
it.  Every Forth definition reads partly as logic and partly as a
stack-shuffle plan.

## 4. Sidebar: `xor` and `not`

`010-lib.fth` doesn't define `xor` or `not` because nothing in the
codebase needs them.  But they're worth deriving once so you know
the seed isn't *missing* anything; it just isn't paying for what
no caller uses.

**`not` in two words:**

```forth
: not  dup nand ;
```

That's the `dup nand` trick we kept seeing, named.  Stack effect
`( a -- ~a )`.

How does `not` differ from `0=`?  `0=` is a seed primitive that
returns `-1` if the input is exactly `0`, else `0`.  It produces
*Forth* booleans (canonical `-1`/`0`).  `not` flips every bit; on
input `0` it returns `-1`, on input `-1` it returns `0`, but on
input `5` it returns `0xFFFFFFFFFFFFFFFA`, which is not a Forth boolean.
For arithmetic, use `not`; for predicate-chaining, use `0=`.

**`xor` by reusing `or` and `and` (cheating):**

```forth
: xor  ( a b -- a^b )  2dup nand >r or r> and ;
```

That uses `2dup` (previewed in Ch 1, defined in Ch 8), `nand`,
`or`, and `and`.  It's `(a or b) and (a nand b)`: the
two inputs differ when at least one is set *and* not both are set.

**`xor` from pure nand:**

```forth
: xor-pure  ( a b -- a^b )
  2dup nand                ( a b nab )
  dup >r nand              ( a b-nab )      \ nab parked on R
  swap r> nand             ( b-nab a-nab )
  nand ;                   ( a^b )
```

(`>r` moves the top of the data stack onto the return stack and
`r>` moves it back; both are seed primitives, and Ch 4 introduces
them formally.)

Four NANDs and some shuffling: nine tokens.  This is the form a
textbook would show for "XOR using only NAND gates."  It's longer than the
`or`/`and` version because it refuses to reuse intermediate logic
words: the point is proving NAND alone is enough, not optimising.

## 5. What this buys

Look at what's now buildable from one primitive:

| Word | Tokens | Built from |
|------|--------|-----------|
| `not` | 2  | `dup nand` |
| `and` | 3  | `nand dup nand` |
| `or`  | 6  | `dup nand swap dup nand nand` |
| `xor` | 6 / 9 | `or`/`and` form / pure-`nand` form, as above |

Compare against the alternative seed where `and`, `or`, `not` are
each primitives.  Each saved primitive is:

- one dictionary entry (link cell + flags byte + name length +
  name bytes + body), at minimum 10 + name-length bytes;
- a few dozen bytes of machine code for the body itself;
- a slot in the assembly-time chain that maintains `LATEST`.

Multiply by three saved primitives (`and`, `or`, `not`) and
you've saved roughly 100 bytes of seed binary plus three CALL
targets, in exchange for adding eight extra tokens to a handful of
Forth-level definitions that get called sparingly.

The seed's rule is to **pick the primitives that buy the most
expressive power per byte**.  `nand` is one.  Ch 4's two's-complement
subtract saves another slot for `-`.  Ch 7's unsigned `/` covers both
arithmetic *and* sign-bit extraction, so every comparison operator is
derived rather than primitive.  Applied throughout, this rule is what
makes 2,040 bytes enough.

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
there too, but the seed's REPL doesn't strip `\` comments, so the
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

We name it `mand` rather than `and` because `010-lib.fth`, loaded
earlier in the same input, already defined `and`, and re-defining a word would just create a shadow (which would still
work, but is noisier to read).

## Exercises

1. **★ Trace.** Take the chapter's `and` (`nand dup nand`) and trace it
   by hand on the inputs `(-1, 0)` — step through `nand`, `dup`,
   `nand` and confirm it yields `0` (false).  Repeat on `(-1, -1)`
   and confirm `-1` (true).

2. **★★ Extend.** Define `xor ( a b -- a^b )` in terms of `nand` alone, with no
   intermediate `and`/`or`.  Confirm with the four-row truth table.
   Compare your token count to the `(a or b) and (a nand b)` form.

3. **★ Extend.** Define `not ( a -- ~a )` in terms of `nand` alone.  How does
   `not` differ from `0=`?  Construct an input where `not` and
   `0=` disagree.

4. **★★★ Trace.** Prove on paper that `nor` is also functionally complete.  Then
   redefine `and` and `or` using only `nor`.  How many tokens
   longer do they become?  (Asymmetric: NOR-based `or` is short,
   `nor dup nor`, while NOR-based `and` is long — figure out why.)

5. **★★★ Trace.** The seed could have spent a primitive slot on `not` and reduced
   `and` to one fewer token.  Estimate the byte cost of that primitive
   slot (10 bytes header + ~12 bytes body) and compare to the byte
   savings (one less token, in maybe a dozen call sites in
   `010-lib.fth`).  Was the seed authors' choice optimal?

## Takeaways

- `nand` is functionally complete, so every boolean function can be
  built from it.
- `and = nand dup nand` and `or = dup nand swap dup nand nand` are
  direct transcriptions of double negation and De Morgan's law.
- Deriving operators instead of making them primitives saves seed
  bytes, and Ch 7 applies the same trade to comparisons.

Next: Chapter 4 — The Return Stack: `over` and Subtract.
