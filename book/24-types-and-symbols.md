# Chapter 24 — Types and Symbols

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read the C-type encoding (`ty-void`, `ty-char`, `ty-int`,
  `ty-struct`, `ty-func`) packed into one word: base in bits
  16–31, ptr-depth in bits 0–7;
- read the struct descriptor layout (total-size, field-count, then
  N 40-byte field records) and use `cc-sd-*` accessors;
- read the symbol-table parallel arrays and explain the scope
  stack push/pop discipline.

## Source coverage

`060-cc-types.fth` (88 lines) and `070-cc-sym.fth` (154 lines).

## Concepts introduced

- **Compact type encoding.**  Every C type fits in one 64-bit word:
  base kind + pointer depth + reserved flags.  Struct types carry
  an out-of-band descriptor pointer in the symbol's val slot.
- **Struct descriptors.**  Fixed-size header (16 bytes) + up to 16
  field records (40 bytes each).  Field records hold name, type,
  byte offset, and (for struct-pointer fields) a pointee
  descriptor for chained `->` resolution.
- **Symbol-table parallel arrays.**  `cc-sym-name`, `cc-sym-len`,
  `cc-sym-kind`, `cc-sym-type`, `cc-sym-val`, etc.  Indexed by an
  integer "symbol id."
- **Scope stack.**  `cc-scope-push` / `cc-scope-pop` mark and restore
  the symbol-table count to give lexical scopes.

## Concepts carried in

- `create`/`allot` (Ch 12), `bytes-eq` (Ch 12), `cc-alloc` (Ch 21).

## Concepts deferred

- Where types are *consumed* — Ch 27 (expressions) for
  type-checking; Chs 25–26 (codegen) for size-based instruction
  selection.

## Section plan

1. **The type word.**  Read `ty-make`, `ty-base`, `ty-ptr`, `ty-size`.
   Trace `ty-make ty-int 2` → 0x00020002 → 8 bytes (a pointer).
2. **Struct descriptor.**  Walk the layout:
   ```
   offset  0:  total-size
   offset  8:  field-count
   offset 16 + i*40:  field i (name-addr, name-len, type, offset, pointee)
   ```
   Read the accessors (`cc-sd-total-size`, `cc-sd-field-rec`,
   `cc-sf-offset`, …).
3. **Field-offset queries.**  `cc-sd-field-by-name` walks fields,
   matches with `bytes-eq`, returns the field record.
4. **The symbol table.**  Read the storage arrays in `070-cc-sym.fth`.
   `cc-sym-add` appends; `cc-sym-find` reverse-scans the table so
   the innermost scope wins.
5. **Scope discipline.**  Functions push a scope on entry, pop on
   return.  Local declarations append; the pop truncates the table
   back to its pre-function size.  Globals never leave.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=060-cc-types.fth
\   <body of 060-cc-types.fth>
\   ```
\   ```forth file=070-cc-sym.fth
\   <body of 070-cc-sym.fth>
\   ```
```

## Try it

```sh
./build.sh
./test.sh   # exercises types via test-060-cc-types.fth
            # and symbols via test-070-cc-sym.fth
```

## Exercises

1. Add `ty-short` (16-bit integer).  How many places change?
   What new size does `ty-size` need to return?

2. Struct fields max out at 16 per struct.  Find the largest struct
   in M2-Planet's source.  Does it fit?

3. The symbol table is a linear-scan parallel-array.  What's the
   worst-case lookup time for a 1000-symbol table?  Would a
   hash-based table fit in this codebase's size budget?

4. Add `ty-array` as a base kind distinct from `ty-ptr`.  Where
   would it differ in behaviour from a plain pointer?

## Takeaways

- The whole C type system fits in one word per type, plus an
  out-of-band descriptor for structs.  This is what makes the
  symbol table cheap (parallel arrays of fixed-size cells).
- Lexical scope is "remember the count; truncate to it on pop."
  No tree, no nesting record — just a stack of integers.
- The struct descriptor is the only place the compiler tracks
  per-field metadata; everything else (variables, functions)
  flows through the symbol table.

Next: Chapter 25 — ELF Emission and Codegen, Part 1.
