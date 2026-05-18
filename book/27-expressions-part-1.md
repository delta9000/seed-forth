# Chapter 27 — Expressions, Part 1: Precedence Climbing

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- explain precedence climbing as an alternative to recursive-descent
  with one routine per precedence level;
- read `100-cc-expr.fth`'s precedence table and binary-operator
  dispatch;
- trace a single expression like `a + b * c - d` from token stream
  to emitted x86-64 bytes.

## Source coverage

`100-cc-expr.fth` lines 1 through roughly the midpoint (~700
lines).  Covers primary expressions, unary operators, and binary
operators (precedence climbing).

## Concepts introduced

- **Precedence climbing.**  A single loop reads operators in
  decreasing-precedence order, calling itself recursively for the
  right operand.  Half the code of one-function-per-level
  recursive descent.
- **Operator precedence table.**  Each binary operator has a
  precedence integer (e.g. `*` and `/` at level 13, `+` and `-`
  at 12, `<` at 10, etc.).
- **Unary operators.**  `-x`, `+x`, `!x`, `~x`, `*p` (deref),
  `&v` (address-of), `(type)e` (cast).
- **Primary expressions.**  Identifiers, literals, parenthesised
  expressions, function calls.
- **Codegen pattern.**  Each operator's case emits the operand
  evaluation onto the evaluation stack, then the op itself
  (`pop rbx ; pop rax ; <op> rax, rbx ; push rax`).

## Concepts carried in

- The lexer interface from Ch 23 (token kinds, `cc-lex-next`).
- The codegen vocabulary from Chs 25–26.
- The type system from Ch 24 (for type-checked operators like
  pointer arithmetic).

## Concepts deferred

- Assignment, postfix, `.` / `->`, function calls — Ch 28.
- Statement-level control flow — Ch 30.

## Section plan

1. **Why precedence climbing.**  Show what a one-function-per-level
   parser looks like for a 14-level grammar (long).  Then show
   precedence climbing (short).
2. **The precedence table.**  Read the constants `PREC_*` or the
   table-of-records.  Tabulate each operator's precedence and
   associativity.
3. **`cc-parse-expr` entry point.**  Walk the recursive function.
   Note where it bottoms out (primary expr) and where it loops
   (binary operator at sufficient precedence).
4. **Primary expressions.**  Identifier (lookup + load), literal
   (push immediate), `(expr)` (recurse), function call (deferred
   to Ch 28).
5. **Unary operators.**  Each one's emission pattern: evaluate the
   operand, then emit a single instruction (`neg`, `not`,
   `setz` + zero-extend, `mov rax, [rax]` for deref).
6. **Binary operators.**  The dispatch table.  Each row maps an
   operator token to a precedence and a codegen routine.
7. **A worked example.**  Compile `a + b * c - d`.  Show the
   precedence-climbing recursion tree, the order in which
   sub-expressions are evaluated, and the x86 bytes emitted.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=100-cc-expr.fth
\   <first ~700 lines>
\   ```
\ Ch 28 emits the rest.
```

## Try it

```sh
./build.sh
echo 'int main() { return 3 + 4 * 5 - 7; }' \
  | ./your-cc-runner.sh
echo $?    # 16
```

## Exercises

1. Does this compiler handle right-associative operators (assign,
   conditional)?  Find the place in the precedence loop where
   associativity changes the recursion depth.

2. Add the `%` (remainder) operator.  Where does it slot into the
   precedence table?  What x86 instruction does it emit?

3. Trace `a + b * (c - d)` on paper.  Show the recursion depth at
   each token.

4. Pointer arithmetic (`p + 1`) scales by `sizeof(*p)`.  Find where
   this scaling happens in the codegen.  Why doesn't `1 + p` get
   the same treatment (or does it)?

## Takeaways

- Precedence climbing is the right tool for any parser with more
  than ~5 precedence levels.  ~150 lines does what one-function-
  per-level recursive descent would do in ~1000.
- The codegen pattern for binary operators is universal: evaluate
  both operands onto the evaluation stack, pop into `rax`/`rbx`,
  emit one or two instructions, push result.
- Pointer arithmetic is the one place the type system reaches into
  expression compilation.

Next: Chapter 28 — Expressions, Part 2: Assignment, Postfix, Struct
Access.
