# 1. Values and words

How can a program compute twice a number, then add one, without naming a variable? In seed Forth, it leaves the number on a **data stack** and runs a sequence of small operations called **words**. The stack carries the intermediate results between them.

By the end of this chapter, you should be able to predict those intermediate results, define a reusable word, and notice when a program asks for an operation its starting stack cannot support. These skills will let you read the language that builds the next layers of the system.

This chapter assumes ordinary arithmetic. We will follow each program one step at a time. It does not assume Forth or machine code. It describes `delta9000/seed-forth` at revision `bbcc1732152af2d884737272eed870d2410ffe8e`, the source snapshot used by this edition's `direct-gcc-overlay` profile. Here we use only the seed's existing primitives; no GCC knowledge or library loading is needed.

**Evidence boundary:** every stack trace below is a manual derivation from the inspected source. The snippets have not been executed for this chapter. Stack pictures are reasoning aids, not terminal output; setup and execution are deferred.

## Choose your starting point

Our notation puts the stack's **top at the right**. Thus `[9, 7]` has `7` on top, and `[]` is empty. A word's effect `( a b -- c )` means that it consumes the top two values, with `b` on top, and replaces them with `c`.

If this notation is familiar, try these two questions before reading on:

1. Starting with `[7]`, what does `dup + [lit] 1 +` leave?
2. Starting with `[15, 7]`, how do `/` and `swap /` differ?

Explain the intermediate states, not only the answers. Compare with the [entry-check reasoning](../practice/01-solutions.md#entry-check). If both explanations hold up, skip to [Defining the calculation](#defining-the-calculation), then try the exercises. If the notation is new, the next sections supply the missing steps. There is no setup task to solve before you can begin.

## A stack holds values in an order

Think of the data stack as an ordered sequence of values. **Pushing** adds a value at the top; **popping** removes the top value. This is a model of the information available to a program, not a drawing of its physical memory layout.

For example, pushing `7` and then `3` gives:

```text
start          []
push 7         [7]
push 3         [7, 3]
pop            [7]       removed value: 3
```

The last value added is the first available to remove. A word that needs two values uses the top two, rather than searching the stack for suitable numbers. Older values can remain underneath while a calculation works above them.

Each value occupies a **cell**. In this seed, a cell is 64 bits, or eight bytes; a byte is eight bits. As an unsigned integer, one cell can represent values from `0` through `18446744073709551615`, which is one less than 2 raised to the power 64. “Unsigned” means that all those bit patterns are being interpreted as nonnegative integers.

The number `7` still occupies one whole cell. Small values do not make narrower stack entries. Conversely, `300` fits in a cell even though it exceeds a single byte's unsigned range, `0` through `255`.

For now, distinguish the unit from the value: **eight bytes per cell; one number per stack entry**. Where bytes live, and how to read or write them using addresses, is the next chapter's subject. The seed's actual stack representation follows its [register convention and eight-byte stack operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L53-L105); you do not need to decode those instructions yet.

## Words describe changes to the stack

A **word** is a named operation the system knows how to perform. Its name may look like an English word, such as `dup`, or an arithmetic symbol, such as `+`. A **primitive** is a word already implemented in the seed. We will combine primitives to define new words.

These are the six operations needed here:

| Word | Stack effect | Meaning |
|---|---|---|
| `dup` | `( a -- a a )` | Copy the top value |
| `drop` | `( a -- )` | Discard the top value |
| `swap` | `( a b -- b a )` | Exchange the top two values |
| `+` | `( a b -- sum )` | Replace two values with their sum |
| `*` | `( a b -- product )` | Replace two values with their product |
| `/` | `( a b -- quotient )` | Divide unsigned `a` by nonzero unsigned `b`, keeping the integer quotient |

The letters are labels for values, not variable names in the input. The `--` separates the before and after pictures. An empty side means no values on that side of the effect. These effects describe the portion a word uses; they do not say that the entire stack must contain exactly that many entries.

For example, `dup` changes `[9, 7]` to `[9, 7, 7]`. Then `+` changes it to `[9, 14]`: the two sevens are consumed, their sum replaces them, and `9` stays underneath. A following `drop` would remove `14`, leaving `[9]`.

Stack effects are a contract to check while reading. They are not automatic checks performed by the seed. In particular, `dup` needs at least one input and `+` needs at least two.

The implementations are short enough to locate directly: [`dup_code`, `drop_code`, and `swap_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L76-L105), [`plus_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L191-L199), and [`divide_code` and `star_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L224-L249).

## Getting a number onto the stack

In this seed, write `[lit] 7` to push the number seven. `[lit]` is one word, brackets included. It reads the next token as unsigned decimal digits. A **token** is a piece of input text separated from its neighbors by whitespace; here, `[lit]` and `7` are two tokens, with the first telling the system how to handle the second.

Do not omit `[lit]`. The ordinary input loop looks up names; it has no fallback that interprets an unknown name as a number. A bare `7` does not push seven. The source makes this division of work explicit in [`bracket_lit_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L577-L600) and the [`repl` input loop](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L664-L689).

Use digits without a sign or a base prefix: `[lit] 15` is valid; `[lit] -1` and `[lit] 0xF` are not. This restriction comes from [`parse_decimal_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L633-L662). Our examples use decimal values within the cell's range.

These study inputs execute their operations from left to right:

```forth
[lit] 7 dup + [lit] 1 +
```

Read this as “push seven; copy it; add the two copies; push one; add again.” There is no rule that searches ahead for multiplication before addition. Each operation uses the stack available when that operation is reached. `[lit]` consumes its following number token as part of its own work.

Here is the complete manual trace:

| Step | Operation | Stack afterward | Why |
|---|---|---|---|
| 0 | Start | `[]` | No input values yet |
| 1 | `[lit] 7` | `[7]` | Supply the input |
| 2 | `dup` | `[7, 7]` | Addition needs two copies |
| 3 | `+` | `[14]` | Consume both sevens; leave their sum |
| 4 | `[lit] 1` | `[14, 1]` | Supply the amount to add |
| 5 | `+` | `[15]` | Consume fourteen and one |

Notice that the first addition does not preserve either input separately. If we had omitted `dup`, it would not have two inputs. That missing copy is a missing precondition, not a different arithmetic formula.

Nothing here prints `15`. The number is a value on the data stack. A table showing that value is not evidence of screen output, and we have not introduced a number-printing word.

## Defining the calculation

Give the sequence a name so another part of a program can use it:

```forth
: twice-plus-one dup + [lit] 1 + ;
```

This is a **colon definition**. The `:` starts a definition, the next token supplies its name, and `;` ends it. Keep whitespace between these tokens. The words between the name and semicolon describe the work to do when the new word is later executed.

Defining `twice-plus-one` does not run `dup` on the current data stack. It prepares the new word. In this definition, `[lit] 1` arranges for a one to be pushed when the new word runs; it does not leave an extra one on the stack merely because we have read the definition.

After the definition, this input requests the calculation:

```forth
[lit] 7 twice-plus-one
```

Its predicted final stack, starting empty, is `[15]`. Executing the new word has the same stack effect as executing the body we just traced. Its contract is `( n -- result )`, where `result` is twice `n` plus one, subject to the cell-width rule below. The name is our example, not a built-in primitive.

A useful way to check the contract is to trace symbols instead of one input:

```text
start          [n]
dup            [n, n]
+              [2n]
[lit] 1        [2n, 1]
+              [2n+1]
```

Here `2n` and `2n+1` are mathematical labels in a paper trace, not seed input. One value enters and one leaves. Deeper values survive: starting with `[99, 7]` would leave `[99, 15]`.

This is the definition contract we need now. The machine mechanism that builds and calls a definition comes later. The relevant source boundaries are [`colon_code` and `semicolon_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L515-L549). The library uses the same composition pattern in its small [`1+` definition](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L42-L45); we have written those operations explicitly rather than assuming that library word is loaded.

## Division reveals the order

Addition and multiplication can hide a reversed pair of inputs: seven plus fifteen equals fifteen plus seven. Division exposes the difference.

For `( a b -- quotient )`, the lower value `a` is the dividend and the top value `b` is the divisor. From `[15, 7]`, `/` computes fifteen divided by seven and leaves `[2]`. The fractional part is discarded; no remainder is left on the data stack.

Now insert `swap`:

```text
start          [15, 7]
swap           [7, 15]
/              [0]
```

Seven divided by fifteen has integer quotient zero. This is why “take the top two and divide” is an incomplete description: you must say which value divides which.

The same stack contracts hold for large cells, but their arithmetic is not unbounded. `+` and `*` retain only the low 64 bits of their result. Equivalently, an unsigned result wraps around at 2 raised to the power 64. Thus adding one to `18446744073709551615` leaves zero. Multiplication retains one cell, not an arbitrarily large product.

The source uses a multiply instruction named `imul`; retaining only its low half gives the same 64-bit result for signed and unsigned interpretations of the inputs. Division is different: the seed explicitly uses unsigned division. Do not import signed-division behavior from another Forth implementation. These properties follow from the [arithmetic implementations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L191-L249).

## Where a trace must stop

From `[7]`, the word `+` lacks one operand. This is **stack underflow**: the program requests more input values than are available. The seed's primitive routines do not check the logical stack depth. Do not predict a friendly error message, an unchanged stack, or a meaningful answer. Stop the paper trace at the violated precondition; invalid stack use may read unrelated memory or fault.

Division has another precondition: its divisor must not be zero. The inspected `divide_code` executes a processor division that traps on a zero divisor; the source identifies the Linux signal as `SIGFPE`. It does not provide a recoverable Forth result. We will not run either kind of failure here.

These boundaries make stack effects practical. Before asking “what is the result?”, ask “are the required values present, in the required order, and in the operation's domain?”

## Practice

Work on paper or in a text file. All stacks below are logical stacks with top at the right. The [separate practice companion](../practice/01-solutions.md) contains graduated hints and reasoned solutions; open it whenever it would help.

### S1-01 — Predict two sequences

Starting empty each time, trace both inputs. Explain the first step at which their computations differ.

```forth
[lit] 3 [lit] 4 + [lit] 5 *
[lit] 3 [lit] 4 [lit] 5 * +
```

### S1-02 — Complete a contract check

`twice-plus-one` is already defined. Starting with `[99, 7]`, its first body operation, `dup`, leaves `[99, 7, 7]`. Fill in the states after the remaining operations: `+`, `[lit] 1`, and `+`. Why does `99` survive? Would reading the definition itself have performed this calculation?

### S1-03 — Repair the order

The stack is `[4, 21]`. You want the integer quotient of twenty-one divided by four. A proposed program is `/`. Explain its actual result, then repair it using one additional word. Check the repair on `[5, 23]` without copying the first numerical answer.

### S1-04 — Build a new word

Define `square-plus-one` with contract `( n -- result )`, where `result` is `n` multiplied by itself, then increased by one with cell-width arithmetic. Use only `dup`, `*`, `+`, and `[lit]` in the body. Trace it from `[6]`, then from `[99, 8]`. The lower `99` must survive.

### S1-05 — Find the boundary

Each line starts with an empty stack, and no word named `7` has been defined. Decide whether it yields a meaningful arithmetic result, encounters a missing operand, encounters a zero divisor, or first contains a token that fails to supply its intended number. Locate the decisive step; do not invent a post-failure stack.

```forth
[lit] 5 +
[lit] 5 [lit] 0 /
[lit] 18446744073709551615 [lit] 1 +
7 dup +
```

## Check, pause, and continue

If a trace went wrong, compare the **first differing state** with the solution. Missing values suggest checking each word's input count; reversed quotients suggest labeling dividend and divisor before `/`. If the complete traces are reliable, try S1-04 without looking back at `twice-plus-one`. A correct answer with help is useful practice; a fresh attempt tells you more about what you can do independently.

You can pause here. Save your last agreed stack, the next word, and any uncertain precondition. To resume without reconstructing everything, start at `[7, 7]` immediately before the first `+` in `twice-plus-one`: predict that step and the two remaining operations. Then return to your first unfinished exercise.

You now have a way to follow values through a sequence, a way to package that sequence as a word, and a check for when the sequence stops making sense. Next we give cells locations: [Addresses and bytes](02-addresses-and-bytes.md).
