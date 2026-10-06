# Return check

Use these after some intervening material or in a later session. The purpose
is to choose a relevant contract without a chapter title choosing it for you.
You may keep the word reference available; try the answer without a worked
solution open. All traces are paper exercises, not live memory operations.

Record what you predicted and why. If useful, also note how sure you felt,
then compare that confidence with the first state that differs from the
answer. There is no score threshold or required waiting interval.

## R-01 A value changes roles

On the 64-bit seed, begin with `[300]` and run `dup [lit] 256 /` on paper.
What stack remains? If you now apply `c!`, does the sequence safely write
the two-byte representation of 300 somewhere? Identify the missing contract
rather than inventing a final memory state.

## R-02 A cursor is not a payload

In a fresh hypothetical model, HERE's cell at 4000 contains 8000. The payload
at 8000 starts with bytes `7 9 0 0 0 0 0 0`. All stated cells and payload
locations are writable and disjoint from live program state. Starting with
`[511]`, a correct `c,` runs. Give the payload row and the cursor afterward.
Then explain what would go wrong if the last store used the old cursor 8000
as its address instead of the HERE cell's address 4000.

## R-03 A plausible arithmetic claim

Someone says: “Complementing a number changes its sign.” Give a counterexample
using 5, then name the missing operation. Does adding that operation make
signed negation behave like unbounded arithmetic for every 64-bit pattern?
Use the top-bit-only pattern to explain your boundary.

## R-04 Compose without changing an older value

`twice-plus-one` and `-` have been defined as in the chapters. Start with
`[99, 7]` and execute `twice-plus-one [lit] 4 -`. Trace the final subtraction
at the contract level and state the final stack. Give a new input that tests
wraparound rather than only small positive arithmetic.

## Hints

- R-01: Track the roles that `c!` assigns to its two inputs; having two
  values is not sufficient evidence of a valid destination
- R-02: Separate the address of the cursor cell from its stored value;
  remember both store widths
- R-03: Compare `U-5` with `M-5`, where `U=M-1`
- R-04: Treat the older 99 as a preserved prefix, then replace only the top
  two operands at subtraction

## Answers and recovery routes

### R-01 answer

`[300] -> [300,300] -> [300,300,256] -> [300,1]`.
`c!` would use 1 as the destination address and the low byte of 300, which is
44, as its value. No valid writable address was supplied. Stop at the missing
memory precondition; do not predict a successful write or a particular fault.
For the legitimate two-byte writer, revisit
[S2-05](02-solutions.md#s2-05--build-a-two-byte-writer), which uses a stated
cursor and preserves the original value until both bytes have been emitted.

### R-02 answer

The new payload row is `255 9 0 0 0 0 0 0`, because 511's low byte is 255.
HERE's cell at 4000 now contains 8001. A final `!` addressed to 8000 would
write the eight-byte representation of 8001 over the payload instead, and
leave the cursor cell unchanged at 8000. The stores' addresses, not just their
values, decide what state changes. Revisit
[the complete cursor trace](../chapters/02-addresses-and-bytes.md#build-the-byte-writer)
if those two locations merged in your answer.

### R-03 answer

Complement of 5 is `U-5=M-6`, whose signed interpretation is -6. Adding one
produces `M-5`, or signed -5. But the top-bit-only pattern, unsigned `2^63`,
is signed `-2^63`; complement-and-increment returns that same pattern. Its
positive mathematical counterpart is not a signed 64-bit value. The modular
rule works while unbounded signed negation does not describe every result.
Revisit [the inverse argument](../chapters/03-bits-and-subtraction.md#subtraction-is-addition-with-a-modular-inverse).

### R-04 answer

`[99,7] -> [99,15] -> [99,15,4] -> [99,11]`.
The lower 99 is preserved. One changed input is `n=U`: doubling and adding
one returns `U` modulo `M`, then subtracting four returns `M-5`. Another useful
case is `n=0`: the word returns one, then subtracting four returns `M-3`.
Give your chosen case and the modulus reasoning, rather than assuming there
is one unique test input.

## What to do with the result

If you lost an operand, return to the first differing stack transition. If
you got arithmetic right but wrote to the wrong location, redraw the value
and address columns. If a width change caused the error, label the modulus
before tracing again. Then choose a changed example and make a fresh attempt.

A successful supported attempt is useful progress. A later independent
attempt asks a different question about retention. Neither result proves
that you can already recognize the mechanism in an unfamiliar compiler; the
later volume must teach that bridge and offer its own checks.
