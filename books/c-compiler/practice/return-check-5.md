# Return check: one spelling, different consumers

Use the pinned legacy profile unless a question explicitly changes it.
Fixtures are independent, with valid owned storage, enough stack/output/arena
space, and no unmentioned symbol or metadata changes. These are paper
predictions. Distinguish builder state from future generated execution, and
successful returns from fatal error paths.

## Questions

### CR5-01

A mutable local `r` occupies slot 4 and contains 2. Compare `r`, `(r)` and
`r+0` as separate expressions starting from that state. What value do their
emitted sequences predict, and which retains local destination identity?
What does calling materialize change for each? Can `(r)=3` and `(r+0)=3` use
the same assignment path merely because their left sides predict equal
values?

### CR5-02

Compare ordinary runtime parsing of `0 && (1 / 0)` with
`cc-pp-eval-text` evaluating that same already-expanded text as a preprocessing
constant. The runtime context is evaluated code, not static initialization or
sizeof. Does each parser consume the right operand? Does it append runtime
division instructions, immediately perform division, or neither? What is the
predicted selected result, and which state prevents a zero-divisor operation?

### CR5-03

Start with legacy local-slot count zero, enough symbol capacity and no static
storage prefix. Process `int *p, a[3];`. Give each symbol's type, array count,
slot identity, and reserved byte range relative to RBP. Does `p`'s star make
`a` an array of pointers? What happens to local-slot allocation when a later
symbol-scope pop hides these names?

### CR5-04

A standard nonnested call to `cc-pp-eval-text` begins with PP mode false,
skip zero, source length 100, source position 12, line 7, and a pending current
token whose other cells are valid. Selected source base is B. A separately
owned five-byte expression span at `B+500` contains `1 + 2`, with no newline.
What temporary source-relative limits are installed, what value is returned,
and what reader state is restored after successful completion? Does this
establish a general rollback contract if a trailing token causes error 129?

## Hints

- CR5-01: a stored place identity and a value with equal bits are different
  outputs; grouping deliberately avoids the public final-load entry
- CR5-02: source parsing, byte emission and execution of an arithmetic word
  are different events in the two paths
- CR5-03: the shared initial pointer depth is reused afresh for each declarator
- CR5-04: the reader retains its selected base; both temporary offsets use that
  same base, and length is saved separately from the eight-cell snapshot

## Worked answers

### CR5-01

All three simple expressions predict value 2. Bare `r` produces an already
loaded value with `lv-local` and slot 4. Grouping `(r)` preserves that result
because it uses the non-final-materializing inner grammar. Materialize does
not load either again or erase their local identity merely because of its
name.

The actual addition in `r+0` consumes the two values, emits their arithmetic,
and republishes a non-assignable `lv-value` with no local slot identity.
Materialize has no pending dereference to load there either, but that does not
make its metadata equal to the other cases.

`(r)=3` can recover slot 4 and store the RHS there, returning the new value as
a computed expression. `(r+0)=3` has no retained destination and reaches the
invalid-destination error 120. No successful store or later result is predicted
after that fatal path. Equal runtime bits do not reconstruct where a value
came from.

Changed case: replace `r` with a valid pending field expression `t.stars`.
Grouping preserves its pending target address. A value consumer materializes
that address into its field value; a store consumer instead needs the address
while parsing the RHS. This is a different representation from an already
loaded legacy local.

### CR5-02

Both consume and parse the right operand's source. The ordinary runtime parser
appends its division sequence while compiling the RHS; it is not dividing the
builder's numbers while doing so. Its generated conditional branch sees the
left zero and selects the false path, skipping the division instructions at
runtime. The predicted logical result is 0.

The preprocessing constant path computes a builder cell rather than emitting
those arithmetic instructions. Its logical evaluator saves the surrounding
suppression state and sets `cc-cx-skip` while parsing the dead right operand.
The division operator is not immediately evaluated, so the zero divisor does
not reach the active division operation. This path also returns 0, then restores
its successful-call reader contract.

The mechanisms have different owners: generated control flow in one case,
builder-time evaluation suppression in the other. Neither means “ignore the
right-hand text.” Invalid syntax or unsupported operands can still fail while
being parsed. This is also different from an inactive nested preprocessor
group whose condition is never sent to the evaluator.

Changed case: use `1 && (9 / 3)`. The runtime true-left path executes its RHS
and normalizes nonzero 3 to 1. The immediate evaluator actually computes 3 and
normalizes it to 1. The values coincide, but their phases and artifacts remain
different. This answer concerns the expression/provider result; an outer
preprocessor dispatcher may use its own nonzero/Forth-flag convention.

### CR5-03

`p` adds one star to the initial depth zero. Its type is int-pointer,
`2*65536+1=131073`, array count zero, and slot 0. It reserves the one cell
`[RBP−8,RBP)`; no initializer has supplied a pointer value.

For `a`, the declarator starts again at depth zero. The type records scalar
int as its element type, 131072; array count is 3. Its three slots are 1, 2, 3,
with base-slot identity 3. Thus its base is `RBP−32`, and its owned array span
is `[RBP−32,RBP−8)`. Elements at offsets 0, 8, 16 are in slots 3, 2, 1. There are
four claimed local slots in total. The pointer star did not carry across the
comma.

A symbol-scope pop restores visible symbol count. It does not reduce
`cc-fn-local-count`, erase the frame bytes or release individual slots. Later
local allocation in that function continues after the existing count. A name's
visibility and storage-accounting lifetime are separate facts.

Changed case: start at local-slot count 31. `p` claims slot 31 and raises count
to 32. The array's proposed additional three slots exceed the legacy 32-slot
limit and fail with 162 before the local-count update. Count remains 32.
However, the array symbol was already added with base slot 34 and length 3;
the parser publishes that row before requesting the slot-count increment.
Neither that row nor the earlier successful `p` claim/record is rolled back.
This inconsistent partial state is at the fatal boundary, not permission to
continue the failed compilation.

### CR5-04

The temporary position becomes 500 and temporary end limit 505:
`(B+500)−B` and `(B+500+5)−B`. The selected base itself does not move. The
reader starts at the owned expression bytes, not at the intervening prefix.
The helper clears pending, enables PP mode, clears evaluation suppression,
and invokes the constant parser.

With the stated valid expression, the parser returns builder-cell value 3 and
the final token check reaches EOF. The helper then clears PP mode, restores
source length 100, and copies back the eight saved lexer cells. Position is
again 12, line 7, pending is again true, and the old token kind/payload/keyword
cells are restored. The saved addresses still rely on their owners preserving
those bytes. The expression contains no newline, but even a temporary line
change belongs to the restored snapshot on successful completion.

Changed case: supply `1 2` instead. The extra number is not EOF after the first
complete expression, so the wrapper reaches error 129 before its success-path
restoration. The process exits through the current error contract; there is
no returned value or promised recovered reader state for a caller to use.
One global snapshot buffer and a success-path restore do not constitute a
reentrant or general transactional parser.

## Check the consumer, not only the number

If an answer is numerically right but its metadata is wrong, identify the
consumer that will fail next. If phases are mixed, label each step as parsing,
emitting bytes, evaluating a builder cell, or predicted generated execution.
Try a changed prompt again with the answer closed after intervening work.
These are opportunities to test reasoning, not evidence that unattempted
practice establishes retention or transfer.

[Back to the volume](../README.md)
