# Chapter 31 — Functions: Parameters, Locals, Scope

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read the function-definition parser (signature, parameter list,
  body);
- explain how parameters are spilled from System V registers into
  the frame and addressed alongside locals;
- read local-declaration handling inside a function body;
- describe the end-to-end build of a single function: parse
  signature → emit prologue → parse body → back-patch frame size →
  emit epilogue.

## Source coverage

`110-cc-decl.fth` last third (lines ~1800 through end at 2750).
Confirm boundary when writing.

## Concepts introduced

- **Function signatures.**  `T NAME (T1 p1, T2 p2, ...) { ... }`.
  Parse type and name; commit a symbol entry; parse parameter list
  into the new scope; parse body.
- **Parameter spilling.**  Per System V (Ch 26), first six args
  arrive in registers.  The prologue spills them to `[rbp - 8*n]`
  slots so they're addressable like locals.
- **Local declarations.**  Inside a body, `T name;` adds a symbol
  in the current scope and bumps the frame size by `sizeof(T)`.
- **Frame-size back-patching.**  The `sub rsp, FRAMESIZE`
  instruction in the prologue uses a 4-byte placeholder; after the
  full body is parsed, the placeholder is patched with the final
  frame size.
- **Symbol resolution at call sites.**  When a function name is
  referenced (in Ch 28's call-site codegen), the symbol table
  yields either the address (if already defined) or a fixup
  request (if forward).

## Concepts carried in

- Symbol table and scope from Ch 24.
- Prologue/epilogue from Ch 26.
- Statement parsing from Ch 30.
- Expression parsing from Chs 27–28.

## Concepts deferred

- Final symbol resolution (forward refs) — Ch 32's `cc-finalize-
  globals`.

## Section plan

1. **Function definition: shape.**  After a type-spec + name, if the
   next token is `(`, it's a function definition (not a global
   variable).  Parse the param list; open a scope; parse the body
   `{ ... }`.
2. **Parameter list parsing.**  For each param: read type-spec, read
   name, add to scope at frame slot `-8*(idx+1)`.  Track total
   param count (so we know how many register spills to emit).
3. **Prologue emission.**  `push rbp ; mov rbp, rsp ; sub rsp,
   PLACEHOLDER`.  Then `mov [rbp-8], rdi ; mov [rbp-16], rsi ; ...`
   for as many params as there are (up to 6).  Args 7+ already
   sit at positive `rbp` offsets per System V.
4. **Body parsing.**  Loop calling `cc-parse-stmt` (Ch 30) until
   `}`.  Local declarations grow the frame size.
5. **Back-patch.**  Replace `PLACEHOLDER` in the prologue with the
   final frame size (rounded up to 16 for stack alignment if the
   ABI requires it; confirm when writing).
6. **Epilogue.**  Emitted by `return` (Ch 30) and also implicitly
   at `}` for functions falling off the end.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=110-cc-decl.fth
\   <last third of 110-cc-decl.fth>
\   ```
```

## Try it

```sh
./build.sh
echo 'int add(int x, int y) { return x + y; }
int main() { return add(3, 4); }' | ./your-cc-runner.sh
echo $?    # 7
```

## Exercises

1. The frame is back-patched.  Why not parse the body once to
   compute the frame, then again to emit code?  Pros and cons.

2. Functions with more than 6 params receive args 7+ on the stack.
   Compile a 9-arg function and inspect the prologue: where do
   args 7, 8, 9 live?

3. C requires 16-byte stack alignment at `call` sites in the System
   V ABI.  Does this compiler honour it?  How would you check?

4. Recursive functions need the symbol available before the body
   parses.  Confirm the symbol is added at function-name parse,
   not at body close.

## Takeaways

- A function definition is a parameter list followed by a body of
  statements.  Both reuse vocabulary you've already met.
- Parameter spilling makes args look exactly like locals; the rest
  of the compiler doesn't need to know the difference.
- The frame size is the one number that requires back-patching;
  everything else is known at emit time.

Next: Chapter 32 — End to End: Main and the Bootstrap Chain.
