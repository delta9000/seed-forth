# Chapter 1 practice: hints and solutions

Return to [Values and words](../chapters/01-values-and-words.md).

All states here are manually derived from the chapter's source-backed contracts, not captured from an execution. Stack top is at the right. Square brackets show logical state; they are not input syntax. Each exercise includes hints followed by its solution so you can choose the amount of help you need.

## Entry check

Starting with `[7]`:

```text
dup            [7, 7]
+              [14]
[lit] 1        [14, 1]
+              [15]
```

The copy supplies the second input to the first addition. Both additions replace two inputs with one output.

Starting with `[15, 7]`, `/` uses fifteen as dividend and seven as divisor, leaving `[2]`. In the alternative sequence, `swap` first makes `[7, 15]`, so `/` leaves `[0]`. Integer division keeps neither a fractional part nor a remainder on the data stack.

If the final numbers were correct but the intermediate order was uncertain, read the division section before skipping ahead. If `[lit]` was unfamiliar, read “Getting a number onto the stack”; the seed's input syntax matters even if you already know another Forth.

## S1-01 — Predict two sequences

### Hints

1. Keep an explicit stack after every operation. Treat `[lit]` and the decimal token it consumes as one trace step.
2. The first sequence reaches `+` with `[3, 4]`. The second postpones that addition.
3. In the second sequence, `*` consumes four and five. Three is still underneath.

### Solution

First sequence:

```text
start          []
[lit] 3        [3]
[lit] 4        [3, 4]
+              [7]
[lit] 5        [7, 5]
*              [35]
```

Second sequence:

```text
start          []
[lit] 3        [3]
[lit] 4        [3, 4]
[lit] 5        [3, 4, 5]
*              [3, 20]
+              [23]
```

After the first two pushes, both states are `[3, 4]`. Their next operations differ: the first adds; the second pushes five. The first therefore computes `(3 + 4) * 5`, and the second computes `3 + (4 * 5)`.

If you obtained `23` for both, you may have applied an expression-language precedence rule to the first sequence. The seed follows the operation order written in the input. If you obtained `[3, 35]` for the first, check that addition consumes its two inputs instead of keeping either one separately.

**Changed-case reattempt:** replace the final `*` of the first sequence with `+`, leaving all other tokens unchanged. Predict every state from the change onward before checking: `[7, 5]` becomes `[12]`. This tests which operation combines the intermediate result, rather than recall of the original total.

## S1-02 — Complete a contract check

### Hints

1. Only the top two cells participate in an addition.
2. After the first `+`, the two sevens have been replaced by one fourteen. The ninety-nine remains below it.
3. Distinguish preparing the word's behavior from later executing that behavior with an input.

### Solution

```text
start          [99, 7]
dup            [99, 7, 7]
+              [99, 14]
[lit] 1        [99, 14, 1]
+              [99, 15]
```

The deepest value survives because no operation reaches it. The body begins with one value above `99`, makes the copies and literals it needs, and ends with one result above `99`. At each addition, two inputs are available above that older value.

Reading `: twice-plus-one dup + [lit] 1 + ;` prepares the definition. It does not apply this sequence to seven. Executing `twice-plus-one` later performs the body. Within this definition, `[lit] 1` prepares a literal for that later execution.

An answer that ends `[99, 7, 15]` preserves the original seven unnecessarily: `dup` initially makes two copies, but the first `+` consumes both. A correct solution must preserve the older ninety-nine while consuming the input seven as part of the computation.

**Changed-case reattempt:** begin with `[99, 0]`. The body gives `[99, 0, 0]`, then `[99, 0]`, `[99, 0, 1]`, and `[99, 1]`. Zero is a valid input here; no division takes place.

## S1-03 — Repair the order

### Hints

1. Write `/`'s inputs as `[a, b]`, with `b` the divisor.
2. In `[4, 21]`, four is currently the dividend. Which taught word exchanges exactly these two cells?
3. After that exchange, the stack should be `[21, 4]` immediately before `/`.

### Solution

The proposed `/` computes four divided by twenty-one, leaving `[0]`. It is a valid operation, but it answers the wrong question.

The repair is:

```forth
swap /
```

Manual check:

```text
start          [4, 21]
swap           [21, 4]
/              [5]
```

Twenty-one divided by four has integer quotient five. The remainder one is not part of the returned stack.

For the required changed case:

```text
start          [5, 23]
swap           [23, 5]
/              [4]
```

The repair preserves its purpose while the numerical answer changes. If you predicted five again, check whether you reused the prior result rather than the rule. If you predicted `[4, 3]`, you kept a remainder that this word does not return.

An explanation is complete when it identifies the original operand order, the corrected order, and the quotient-only result. Merely saying “division runs backwards” does not specify a dependable contract.

## S1-04 — Build a new word

### Hints

1. Multiplication needs two inputs even when both inputs should have the same value.
2. First arrange `( n -- n n )`, then consume that pair with `*`.
3. After multiplication, the stack contains the square. The remaining work is to push one and add.

### Solution

One definition is:

```forth
: square-plus-one dup * [lit] 1 + ;
```

Its first test:

```text
start          [6]
dup            [6, 6]
*              [36]
[lit] 1        [36, 1]
+              [37]
```

Its changed-input and deeper-stack test:

```text
start          [99, 8]
dup            [99, 8, 8]
*              [99, 64]
[lit] 1        [99, 64, 1]
+              [99, 65]
```

The conceptual effect is one input replaced by one output, with older values preserved. For larger values, both multiplication and addition retain only one 64-bit cell; the definition does not promise an unbounded mathematical square.

Accept an alternative definition if it uses only the allowed body words, works for every cell input under those width rules, and preserves any deeper stack values. Matching the two small examples alone is not enough to establish that full contract; a symbolic trace explains why it holds.

Two plausible errors are omitting `dup`, leaving `*` short of an operand, and writing `dup [lit] 1 + *`, which computes `n * (n + 1)` instead. With six, the latter leaves forty-two, not thirty-seven. Locate the first different state rather than treating the final number as the whole diagnosis.

If you needed the final hint, close this solution and later reconstruct the definition from its contract. That new attempt is a better check of independent construction than copying the line you have just read.

## S1-05 — Find the boundary

### Hints

1. For each line, ask whether a token supplies a value before counting arithmetic operands.
2. Having two operands does not make division by zero valid. Conversely, a result larger than a cell does not imply that this seed will report an overflow error.
3. The decimal value in the third line is the largest unsigned cell. The fourth line lacks the word that explicitly reads a number.

### Solution

**First line: `[lit] 5 +`.** The literal leaves `[5]`. `+` requires two inputs and finds only one in the logical stack. Stop at `+`: this is underflow. The seed has no depth guard here, so there is no justified friendly error or final stack to write down.

**Second line: `[lit] 5 [lit] 0 /`.** The literals leave `[5, 0]`. Two operands exist, but the top one is the divisor. A zero divisor violates `/`'s domain and triggers the processor's division trap rather than yielding a Forth quotient.

**Third line: `[lit] 18446744073709551615 [lit] 1 +`.** Both literals are within the unsigned 64-bit range. They give `[18446744073709551615, 1]`. Their mathematical sum is 2 raised to the power 64; retaining the low 64 bits leaves `[0]`. This is a meaningful result under the seed's wraparound contract. It is not an observed overflow diagnostic.

**Fourth line: `7 dup +`.** The earliest problem is the initial bare token `7`. With no word of that name defined, name lookup fails; it does not supply a numeric operand. The seed's input loop reports an unknown token and continues. The subsequent `dup` therefore lacks its required logical input. Do not derive `[14]` or invent a recoverable post-underflow state. The intended arithmetic input is `[lit] 7 dup +`.

The third and fourth cases distinguish two different layers: arithmetic on a value already supplied versus text that never supplied the intended value. Changing the arithmetic cannot repair the missing `[lit]`.

**Changed-case reattempt:** classify `[lit] 0 [lit] 5 /`. Its stack before division is `[0, 5]`, so the divisor is nonzero and the result is `[0]`. Zero is allowed as a dividend. Also check `[lit] 18446744073709551615 [lit] 0 +`: it preserves the largest unsigned cell, because that sum does not cross the wrap boundary.

## Ready to continue?

You have evidence of the chapter's target capability when you can trace a new short sequence, explain a definition's inputs and outputs, and stop at a violated precondition without inventing a result. If one part remains uncertain, return to its first differing state and use the corresponding changed-case attempt. You do not need to memorize source line numbers or repeat every solved exercise.

Next: [Addresses and bytes](../chapters/02-addresses-and-bytes.md).
