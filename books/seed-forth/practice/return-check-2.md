# Return check after the library foundations

These mixed tasks revisit [return-stack discipline](../chapters/04-return-stack-and-shuffles.md),
[comparisons and characters](../chapters/05-comparisons-and-characters.md),
and [memory updates and writers](../chapters/06-memory-updates-and-writers.md).
Use them after intervening work, with the relevant word contracts available
but the answers closed if that suits your goal. All states are paper models.

## R2-01 The helper changes the question

A colon word has return destination K and temporarily parks 3 using `>r`.
The logical data stack is now `[50]`, and the physical return stack, top
right, is `[..., K, 3]`. It calls a helper defined as `: peek r@ ;`.
Let H be the return destination from `peek` to its caller. What does `peek`
leave on the data stack? Why is balancing the original `>r` eventually not
enough to make this helper read the parked value?

## R2-02 Two opposite comparisons both claim true

Use the actual bounded library definitions, not an ideal comparison operator.
Let `a` have signed value `-2^63` and `b` have signed value zero. What do
`a b <` and `a b >` produce? Those expressions mean “start with the named
values in that order, then call the comparison”; they are not literal input
syntax. Explain why the results do not establish a consistent total ordering.
Then choose a pair that lies within the shared safe domain and compare it
both ways.

## R2-03 A field wider than its writer

In a fresh paper model, a valid payload cursor starts at 6000, with enough
nonoverlapping writable bytes. A caller gives `,4` the unsigned 64-bit value
4294967297. Which four bytes are emitted, and what is the new cursor?
Would reading those four bytes as an unsigned little-endian number recover
the caller's original value? State the contract needed to promise that
round trip, then name a writer from the chapter that preserves all 64 bits.

## R2-04 A count update is not byte emission

A valid, writable cell at 3000 initially contains 7. Other live state is
disjoint. Start with data stack `[99, 4, 3000]` and execute `-!`. Give the
final cell value and logical stack. Does this operation advance HERE?
Explain which contract decides the answer, rather than inferring a cursor
change merely because a store occurred.

## Hints

- R2-01: Write H onto the return stack for the helper call, then remember
  that `r@` skips exactly its own return address
- R2-02: `<` tests the signed interpretation of `a-b`; `>` swaps first and
  therefore tests `b-a`. Do both exact differences fit?
- R2-03: The input is `2^32 + 1`, so its low four bytes do not carry the
  high-order one
- R2-04: Follow `-!`'s explicit target address; it is not a `c,` or `,4` call

## Answers and changed checks

### R2-01 answer

Calling `peek` changes the physical return stack to `[..., K, 3, H]`.
Calling `r@` inside `peek` adds another return destination P, giving
`[..., K, 3, H, P]`. The primitive skips P and copies H. Its own return
removes P, and the helper's return removes H, leaving `[..., K, 3]`.
The data stack is `[50, H]`, not `[50, 3]`.

The original borrowing can still be balanced by a direct `r>` in the caller.
That discipline does not remove the helper's extra frame while its `r@` runs.
For a changed check, replace the helper call with a direct `r@` in the original
word. The primitive then skips its own return destination and copies 3.

### R2-02 answer

`a-b=-2^63` fits the signed range, so the `<` implementation sees a set top
bit and returns all ones. For `>`, `b-a=2^63` does not fit as a positive signed
64-bit integer. Its bit pattern is again the top-bit-only pattern, interpreted
as negative; the implementation also returns all ones.

Both cannot describe the intended mathematical ordering. The second call is
outside its exact-difference domain. The shared sufficient condition
`|a-b| < 2^63` excludes this pair and makes both directional differences fit.
For example, 30 and 50 produce true for `<` and false for `>`. Explain your own
changed pair and its differences rather than treating a small example as a
proof about every cell.

### R2-03 answer

`,4` emits `1 0 0 0` at addresses 6000 through 6003 and leaves HERE containing
6004. Decoding those four bytes gives 1. The writer's contract keeps only
the low 32 bits; exact recovery requires an input between zero and `2^32-1`,
inclusive. `,8` emits all eight bytes of a seed cell. On the original value
its bytes are `1 0 0 0 1 0 0 0` and the cursor advances by eight.

For a changed check, use `2^32-1`: all four emitted bytes are 255 and an
unsigned four-byte decode recovers the input. This boundary is a stronger
test of the contract than another tiny positive number.

### R2-04 answer

The new cell value is 3 and the final logical stack is `[99]`. The target
address and amount are consumed; the older item survives. The `-!` definition
uses `@`, arithmetic, and `!` at the provided address. It does not use `here`,
`here-addr`, or a cursor-advancing writer, so HERE is unchanged under the
stated non-aliasing precondition.

For a changed check, replace the initial cell value with 2 while retaining
amount 4. The stored cell is `2^64-2`, whose signed interpretation is -2.
The memory update uses the same modular subtraction as a stack calculation.

## Choose the next repair

A return-address mistake calls for two separate stack pictures. A comparison
mistake calls for the exact difference before truncation. A lost-byte mistake
calls for the writer's width and the input range. A wrong cursor prediction
calls for distinguishing an ordinary store from the writer that adds a
cursor update. Make a fresh, changed attempt after the relevant correction.
