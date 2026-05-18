# Chapter 28 — Expressions, Part 2: Assignment, Postfix, Struct Access

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read assignment compilation (`=`, `+=`, `-=`, etc.) and understand
  the lvalue/rvalue distinction this compiler enforces;
- read `++` / `--` (pre and post) and predict the bytes for each;
- read `.` and `->` (struct member access) including the chained
  case `head->next->prev`;
- read function-call argument evaluation and argument-register
  loading.

## Source coverage

`100-cc-expr.fth` second half (~700 lines through end at line 1447).

## Concepts introduced

- **Lvalue vs rvalue.**  An lvalue knows its *address*; an rvalue
  knows only its *value*.  Assignment requires the LHS to be an
  lvalue (identifier, deref, struct field).
- **Compound assignment.**  `x += 1` compiles as "evaluate
  `address-of(x)` once, dereference for old value, add, store
  back."  One fewer evaluation of `x` than `x = x + 1`.
- **Pre- vs post-increment.**  `++x` returns the new value; `x++`
  returns the old.  Codegen differs in *when* the increment
  happens.
- **Struct field access.**  `s.field` computes
  `address-of(s) + offset(field)`; `p->field` is `(*p).field`.
  Chained `a->b->c` resolves left-to-right.
- **Function calls.**  Evaluate args (left-to-right) onto the
  evaluation stack; pop into call registers; emit `call NAME`;
  push `rax` for the result.

## Concepts carried in

- All of Ch 27 (precedence climbing, primary expressions).
- The struct descriptor accessors from Ch 24.
- The codegen vocabulary from Chs 25–26.
- The symbol table for function-name resolution (Ch 24).

## Concepts deferred

- Declaration of functions and parameters — Ch 31.

## Section plan

1. **Lvalue tracking.**  A compiled expression carries with it not
   just a type but a flag: "do I currently hold the address or the
   value?"  When you need a value (for arithmetic), emit a load if
   it's an address.
2. **Assignment.**  Parse `=`; evaluate LHS as lvalue (must be
   addressable); evaluate RHS as value; emit `store`.
3. **Compound assignment.**  `+=` and friends: same as assignment
   but the RHS computes `old-value + delta` using `cc-emit-dup-
   addr` so the LHS address is only evaluated once.
4. **`++` and `--`.**  Pre: increment then load.  Post: load then
   increment.  Both cases emit `inc qword [addr]` (or `add qword
   [addr], 1`).
5. **`.` and `->`.**  Struct descriptor lookup; field offset; emit
   address arithmetic.  For chained `a->b->c`, each `->` repeats
   the pattern using the field's pointee descriptor (the 5th cell
   of the field record from Ch 24).
6. **Function-call argument evaluation.**  Walk left-to-right.
   Push each evaluated arg onto the eval stack.  After all args,
   pop into `rdi`/`rsi`/`rdx`/`rcx`/`r8`/`r9` (System V) in
   reverse order; remaining args stay on the stack.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=100-cc-expr.fth
\   <second half of 100-cc-expr.fth>
\   ```
```

## Try it

```sh
./build.sh
echo 'int main() { int x = 0; x++; return x; }' | ./your-cc-runner.sh
echo $?    # 1

echo 'struct P { int x; int y; };
int main() { struct P p; p.x = 3; p.y = 4; return p.x + p.y; }' \
  | ./your-cc-runner.sh
echo $?    # 7
```

## Exercises

1. Pre-increment is one fewer byte than post-increment in some
   compilers.  Is it here?  Read both code paths and compare.

2. Chained `a->b->c` requires two struct descriptors at parse time.
   Trace how the compiler walks them.  What error message does it
   produce if `b` isn't actually a pointer-to-struct?

3. The compiler evaluates call args left-to-right.  C only
   guarantees one order in C11+ (`f(g(), h())` is unspecified).
   Find the loop; would right-to-left be cheaper here?

4. Add the `?:` ternary operator.  Where does it slot into the
   precedence?  How does its codegen reuse `if`/`else`/`then`
   machinery from Ch 30?

## Takeaways

- The lvalue/rvalue distinction is what makes assignment work.
  Every expression node implicitly carries this flag.
- Compound assignment and `++`/`--` are mechanical optimisations
  over "decompose to plain assignment" — they emit one fewer
  address evaluation.
- Struct access is descriptor-driven; the type system reaches
  into expression compilation here and in Ch 27's pointer
  arithmetic.

Next: Chapter 29 — Declarations: Types and Globals.
