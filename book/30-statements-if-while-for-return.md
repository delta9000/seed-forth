# Chapter 30 — Statements: `if`, `while`, `for`, `return`

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read the statement parser and its dispatch table on the first
  token of each statement;
- read the codegen for `if`/`while`/`for` and recognise the same
  back-patching pattern from Ch 11's `if,/then,/else,`;
- read `return` and explain how it interacts with the function
  epilogue from Ch 26.

## Source coverage

`110-cc-decl.fth` middle third (lines ~900 through ~1800).  Confirm
boundaries when writing.

## Concepts introduced

- **Statement parser dispatch.**  `if` / `while` / `for` /
  `return` / `{` / `;` / expression-statement.
- **Compound statements (`{ ... }`).**  Push a scope, parse stmts
  until `}`, pop the scope.
- **Conditional jumps in codegen.**  `cc-emit-jz-rel32-fixup`
  emits `je rel32` with the rel32 reserved as a fixup; the
  matching `cc-emit-patch-jump fixup` writes the resolved offset.
- **Loop codegen.**  `while`: record start, evaluate condition,
  emit `jz end-fixup`, emit body, `jmp start`, patch end-fixup.
- **`return`.**  Evaluate (optional) expression into `rax`; emit
  the function epilogue (Ch 26).

## Concepts carried in

- Expression compilation from Chs 27–28 (used for conditions and
  return values).
- Codegen vocabulary from Chs 25–26 (especially conditional
  jumps).
- Scope discipline from Ch 24.
- Forward-fixup pattern from Ch 11 — but in the *output* segment,
  not the Forth dictionary.

## Concepts deferred

- `break` / `continue` (probably supported; confirm) — require a
  stack of "innermost loop's end-fixup."
- `switch` / `case` (probably not supported in M2-Planet's subset;
  confirm).
- `goto` (definitely not supported).

## Section plan

1. **Statement dispatch.**  `cc-parse-stmt` peeks the next token;
   on a keyword, calls the matching parser; on anything else,
   parses as expression-statement and emits a `pop rax` to discard
   the result.
2. **`if` and `if/else`.**  Same pattern as Ch 11's `if,/else,/
   then,` but compiling x86-64 `jz`/`jmp` instead of Forth
   `0branch`/`branch`.
3. **`while`.**  Trace: record `start = code-pos`; evaluate cond;
   `jz end-fixup`; parse body; emit `jmp start`; patch end-fixup
   to current `code-pos`.
4. **`for`.**  Three-part: init (a statement); cond (an
   expression); update (an expression).  Compiles to `init; start:
   cond; jz end; body; update; jmp start; end:`.
5. **`return`.**  If expression follows, evaluate into `rax`.  Emit
   `mov rsp, rbp ; pop rbp ; ret` (the standard epilogue from
   Ch 26).
6. **`break`/`continue`.**  Require a stack of "the innermost
   loop's start address and end-fixup" maintained by the parser.
   Confirm whether this compiler does this and how.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=110-cc-decl.fth
\   <middle third of 110-cc-decl.fth>
\   ```
\ Ch 31 emits the rest.
```

## Try it

```sh
./build.sh
echo 'int main() {
  int i = 0;
  int s = 0;
  while (i < 10) { s = s + i; i = i + 1; }
  return s;
}' | ./your-cc-runner.sh
echo $?    # 45
```

## Exercises

1. `for` is `init; while(cond) { body; update; }`.  Does this
   compiler implement it that way?  Or with separate codegen?

2. Add `do-while`.  How does it differ from `while`?  How many
   lines of code?

3. `break` jumps to the end of the innermost enclosing loop or
   switch.  How does the parser keep track?  (Hint: probably a
   separate stack of fixups, similar to the data stack used for
   control-flow.)

4. The codegen pattern in Ch 11 (`if,/then,`) and this chapter's
   `if` are structurally identical.  Tabulate the parallels:
   Forth's `0branch_code` vs x86's `jz`; the fixup-on-the-stack
   pattern; the patch-on-`then,`.

## Takeaways

- Statement codegen is a direct port of Ch 11's combinators to
  x86-64.  Same fixup pattern, same back-patching, different
  byte encoding for the jump.
- `return` is the only escape route to function exit; no
  `longjmp`, no exceptions.  This keeps codegen simple.
- The scope stack (Ch 24) is pushed/popped at every `{` / `}`.

Next: Chapter 31 — Functions: Parameters, Locals, Scope.
