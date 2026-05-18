# Chapter 21 — Arena and I/O Buffers

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- explain the bump allocator in `020-cc-arena.fth` and predict its
  exhaustion behaviour;
- read the source-buffer reader in `030-cc-io.fth` (`cc-load-stdin`,
  `cc-peek-char`, `cc-next-char`) and trace a single character's
  journey from stdin to the lexer;
- read the output-buffer writer (`cc-emit-byte`, `cc-emit-4le`,
  `cc-emit-8le`, `cc-out-patch-*`) and explain why we accumulate the
  whole ELF in memory before writing.

## Source coverage

`020-cc-arena.fth` (41 lines) — entire file.
`030-cc-io.fth` (151 lines) — entire file.

## Concepts introduced

- **Bump-allocator arena** with 8-byte alignment, OOM via `die 7`.
  Used for struct descriptors, label fixup overflow, string overflow.
- **1 MiB source buffer** at `0x414000+`.  The compiler reads all of
  stdin into memory before lexing.
- **`peek`/`next` reader interface** with line-number tracking for
  error messages.
- **1 MiB output buffer + back-patching.**  We emit ELF bytes
  in-order, but headers (e.g. `e_shoff`, segment sizes) aren't known
  until we've laid out the whole file — hence `patch-4le` /
  `patch-8le`.

## Concepts carried in

- `create`, `allot`, `variable` (Ch 12).
- `c@`, `c!`, `here-addr`, `+!` (Chs 2, 9, 14).
- `open`, `read`, `write`, `close`, `die` (Ch 5).

## Concepts deferred

- The ELF-header bytes that `cc-emit-4le` / `8le` actually write —
  Ch 25.
- How the lexer consumes `cc-next-char` — Ch 23.

## Section plan

1. **`020-cc-arena.fth`: a 41-line allocator.**  Walk `cc-alloc`:
   round up to 8, bump, OOM check, return old top.  Show the
   one-shot OOM path with `die 7`.
2. **`030-cc-io.fth`, part A: the source reader.**  4096-byte
   `read` loops until EOF; `cc-peek-char` returns the current byte
   or 0 at EOF; `cc-next-char` advances and tracks newlines.
3. **`030-cc-io.fth`, part B: the output writer.**  `cc-emit-byte`
   is `c, ` for the output buffer; `cc-emit-4le` and `cc-emit-8le`
   mirror `010-lib.fth`'s `,4`/`,8` but for the output buffer.
4. **`030-cc-io.fth`, part C: back-patching.**  `cc-out-patch-4le`
   and `cc-out-patch-8le` write at an absolute byte offset rather
   than at the current cursor.  Used for ELF section sizes that we
   compute only after seeing all the code.
5. **`cc-write-output`.**  Open `O_WRONLY|O_CREAT|O_TRUNC` with mode
   `0755`; write the whole buffer; close.  Errors die with status 1.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=020-cc-arena.fth
\   <body of 020-cc-arena.fth>
\   ```
\   ```forth file=030-cc-io.fth
\   <body of 030-cc-io.fth>
\   ```
```

## Try it

```sh
./build.sh
./test.sh    # exercises cc-arena and cc-io via test-020-cc-arena.fth
             # and test-030-cc-io.fth.
```

Read `test-020-cc-arena.fth` and `test-030-cc-io.fth` — the
assertions show exactly what each entry point is supposed to do.

## Exercises

1. The arena is 32 KiB.  Could you reduce it to 16 KiB without
   breaking M2-Planet compilation?  How would you measure?

2. The source buffer is 1 MiB.  What's the actual peak source size
   for M2-Planet?  Could you tighten this and save 800 KiB of
   virtual address space?

3. `cc-out-patch-4le` writes 4 bytes one at a time.  Could you write
   a faster `patch-cell-le` using `!` and some shuffling?  Would it
   be worth the bytes-of-code?

4. Add `cc-emit-string ( c-addr u -- )` that emits `u` bytes from
   `c-addr` to the output buffer.  Use it to emit a hardcoded "Hi\n"
   greeting and confirm.

## Takeaways

- The C compiler's memory model is two big in-memory buffers plus a
  small overflow arena.  No `malloc`, no `mmap` — just the 16 MiB
  segment from the ELF program header (Ch 13).
- Reading and writing are batched: stdin in one chunked loop, output
  in one `write` after the whole ELF is laid out.
- Back-patching is how the compiler handles forward references
  inside the ELF it's emitting (the same trick `if,` uses for
  Forth-level control flow, Ch 11).

Next: Chapter 22 — The Preprocessor.
