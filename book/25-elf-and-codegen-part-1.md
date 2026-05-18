# Chapter 25 — ELF Emission and Codegen, Part 1: Instructions

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read `080-cc-elf.fth` and explain how the output ELF's header is
  laid out, what fields are back-patched, and why the data segment
  follows the code segment at a `0x1000` alignment;
- read the first half of `090-cc-emit.fth` — the per-instruction
  encoders (push/pop, load/store, arithmetic, compares) — and
  predict the bytes each emits.

## Source coverage

`080-cc-elf.fth` (68 lines) and `090-cc-emit.fth` lines 1 through
roughly the midpoint (~500 lines).

## Concepts introduced

- **Two-segment output ELF.**  R-X for code, R-W for data; both
  start at `0x10000` (or similar — confirm when writing).  The
  back-patching from Ch 21 sets segment sizes.
- **The codegen "current code position" cursor.**  We emit
  instructions into the code segment by advancing the cursor.  The
  cursor is the output equivalent of HERE.
- **One word per instruction encoder.**  `cc-emit-push-imm`,
  `cc-emit-pop-rax`, `cc-emit-add-rax-rbx`, etc.  Each writes the
  bytes of one (or a small group of) x86-64 instructions.

## Concepts carried in

- `cc-emit-byte`, `cc-emit-4le`, `cc-emit-8le`, `cc-out-patch-*`
  (Ch 21).
- x86-64 instruction encoding intuition (Chs 14–18).

## Concepts deferred

- Higher-level codegen (function prologue, locals, calls) — Ch 26.
- Expression-to-code translation — Ch 27.

## Section plan

1. **`080-cc-elf.fth`.**  Read the whole 68-line file.  Identify the
   header bytes, the program headers (two), the back-patch hooks
   for code-size and data-size.  Walk `cc-emit-elf-header` and
   `cc-finalize-elf`.
2. **`090-cc-emit.fth` opening.**  Read the section header and the
   shared register/encoding conventions (which registers are
   call-clobbered, which are reserved for the evaluation stack).
3. **Stack ops.**  Encoders for `push imm32`, `push rax`, `pop rax`,
   `pop rbx`.  Each is 1–10 bytes; trace each opcode in the Intel
   manual.
4. **Memory ops.**  Encoders for `mov rax, [rsp]`, `mov [rdi], rax`,
   `mov al, [rdi]`, etc.  Note how ModR/M encoding factors in.
5. **Arithmetic and logic.**  Encoders for `add rax, rbx`, `sub rax,
   rbx`, `imul`, `xor rax, rax`, etc.  These map roughly 1:1 onto C
   binary operators.
6. **Compares and conditional set.**  `cmp rax, rbx` followed by
   `sete al ; movzx eax, al` — the "make a 0/1 boolean from a
   comparison" idiom.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=080-cc-elf.fth
\   <body of 080-cc-elf.fth>
\   ```
\   ```forth file=090-cc-emit.fth
\   <first ~500 lines>
\   ```
\ Ch 26 will emit the remaining lines.
```

## Try it

```sh
./build.sh
tests/cc/stage-a-check.sh   # builds M2-Planet via cc-out and compares
                            # the .M1 output to the GCC-built reference
```

If `stage-a-check.sh` passes, the codegen is producing byte-correct
machine code at scale.

## Exercises

1. Read `cc-emit-elf-header`.  Why does it emit zeros for fields
   that get back-patched later?  What's the alternative?

2. The two-segment layout costs 56 bytes (one extra program
   header).  Could we live with one R|W|X segment like the seed?
   What would change?

3. Tabulate every instruction encoder by name and bytes-emitted.
   Roughly how many distinct x86-64 instructions does this codegen
   know?

4. Add an `imul rax, rbx, imm32` encoder.  Where would it be used?
   (Hint: scalar multiplication by a constant.)

## Takeaways

- The output ELF mirrors the seed's structure but with two
  segments and back-patched sizes.
- Each instruction has its own Forth-level encoder; this is the
  alternative to a generic "assemble these tokens" pass.
- The expression evaluator (Ch 27) sees this layer as a vocabulary
  of `cc-emit-*` words and never touches raw bytes.

Next: Chapter 26 — Codegen, Part 2: Calls and Locals.
