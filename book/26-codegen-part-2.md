# Chapter 26 — Codegen, Part 2: Calls, Locals, Stack Discipline

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read the function-prologue and function-epilogue emitters and
  predict the bytes for a function of given local-variable count;
- read the System V AMD64 calling-convention setup (first six
  args in `rdi/rsi/rdx/rcx/r8/r9`, rest on the stack) as emitted
  by this compiler;
- explain how local variables are addressed (`rbp` + negative
  offset) and how the compiler tracks the current frame size.

## Source coverage

`090-cc-emit.fth` lines ~500 through 1027 (second half).

## Concepts introduced

- **Function prologue / epilogue.**  `push rbp ; mov rbp, rsp ; sub
  rsp, frame-size` on entry; `mov rsp, rbp ; pop rbp ; ret` on exit.
  Standard System V AMD64 frame.
- **Local-variable allocation.**  Each declared local gets the next
  `rbp - N` slot; the compiler maintains a "current frame size"
  counter that grows on declaration.
- **Argument passing.**  First six integer/pointer args in
  `rdi/rsi/rdx/rcx/r8/r9`.  Remaining args go on the stack right-
  to-left.  The callee's prologue spills args to its frame.
- **Function call sites.**  Evaluate args left-to-right onto the
  evaluation stack, then move them into the call registers (or
  push), then `call`, then handle the return value in `rax`.

## Concepts carried in

- All of Ch 25's per-instruction encoders.
- The symbol table from Ch 24 (where local addresses live).

## Concepts deferred

- Statement-level codegen (if/while/for/return) — Ch 30.
- Function definition parsing — Ch 31.

## Section plan

1. **Frame conventions, recap.**  `rbp` is the frame pointer;
   `rsp` the stack pointer.  Locals at negative offsets; args at
   positive offsets (for args 7+).
2. **`cc-emit-prologue`.**  Read the bytes.  Note the
   `sub rsp, FRAMESIZE` placeholder gets back-patched once the
   function body is fully parsed.
3. **`cc-emit-epilogue`.**  Mirror prologue; called by `return`
   statement compilation.
4. **Local-variable lookup.**  `cc-emit-load-local n` emits `mov
   rax, [rbp - 8*n]`; `cc-emit-store-local n` emits `mov [rbp -
   8*n], rax`.
5. **Call sites.**  `cc-emit-call-prep` evaluates args in order;
   `cc-emit-call-load-arg n` moves an arg from the evaluation
   stack into the right call register; `cc-emit-call NAME` emits
   `call rel32` to the resolved address.
6. **Return value plumbing.**  `rax` holds the result.  The caller
   pushes it onto the evaluation stack for chained use.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=090-cc-emit.fth
\   <second ~500 lines, picking up where Ch 25 left off>
\   ```
```

## Try it

```sh
./build.sh
echo 'int main() { return 42; }' | ./seed-forth-cc-runner   # or
                                                            # tests/cc/stage-a-check.sh
echo $?    # 42
```

(Adapt the runner invocation when writing.)

## Exercises

1. The frame size is back-patched after parsing the body.  Why not
   compute it during a pre-pass?

2. System V says first 6 args in registers, rest on the stack.  How
   does this compiler handle a 9-arg function call?

3. The evaluation stack uses `push rax` / `pop rbx` for binary
   operators (slow but simple).  A register allocator would be
   faster.  What's the size-vs-speed argument for not having one?

4. Tail-call optimisation could replace `call ; ret` with `jmp`.
   Find the `return f(...)` codegen and consider whether the
   compiler does this; if not, what would adding it cost?

## Takeaways

- Function prologue/epilogue and per-local addressing are the
  scaffolding that lets the expression evaluator (Ch 27) ignore
  frames entirely.
- The compiler uses an evaluation stack (the x86 hardware stack)
  for intermediate results.  This is simple and slow; a register
  allocator would be much harder.
- System V AMD64 calling conventions are followed verbatim, so the
  output can interoperate with libc — though this compiler never
  uses libc.

Next: Chapter 27 — Expressions, Part 1: Precedence Climbing.
