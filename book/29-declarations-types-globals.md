# Chapter 29 — Declarations: Types and Globals

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read the type-specifier parser that handles `int`, `char`, `void`,
  `struct NAME { ... }`, `T *`;
- read global-variable declaration handling (data-segment layout,
  initializers, externs);
- read struct declaration handling (descriptor construction, field
  accumulation, alignment).

## Source coverage

`110-cc-decl.fth` lines 1 through roughly line 900 (first third of
the file).  Confirm boundary when writing.

## Concepts introduced

- **Type-specifier parser.**  Reads `int`/`char`/`void`/`struct` and
  pointer stars; constructs the type word from Ch 24.
- **Struct definition.**  `struct NAME { field-decl* }` builds a
  struct descriptor; field offsets accumulate respecting alignment.
- **Global declarations.**  `T name;`, `T name = init;`, `T name[N];`.
  Globals go into the data segment of the output ELF; their address
  in the data segment becomes the symbol's val.
- **Forward declarations and externs.**  Names declared without
  bodies get marked as needing resolution; the linker pass (or the
  end-of-file fixup) resolves them.

## Concepts carried in

- The type encoding from Ch 24.
- Struct descriptors from Ch 24.
- The symbol table from Ch 24.
- ELF data-segment emission from Ch 25.

## Concepts deferred

- Statements (`if`, `while`, etc.) — Ch 30.
- Function definitions and parameters — Ch 31.

## Section plan

1. **The top-level parser.**  `cc-parse-program` reads declarations
   until EOF.  Each one is either a type-specifier followed by a
   name and either `;` (declaration) or `(` (function definition,
   Ch 31) or `{` (struct body).
2. **Type-specifier parsing.**  Read `int`/`char`/`void`/`struct
   NAME`; then any number of `*`s to accumulate pointer depth.
3. **Struct definition.**  `struct NAME { ... };` allocates a
   descriptor; loops over field declarations; computes each
   field's offset (no padding for char, 8-byte alignment for
   pointers, etc.); records the descriptor on the named struct.
4. **Global variable declarations.**  Allot space in the output's
   data segment; record the symbol with its address; if an
   initializer is given, emit the initializer bytes.
5. **Forward decls / externs.**  A name declared without body or
   initializer gets a symbol with `kind = extern`; references
   accumulate fixup notes; end-of-file pass resolves them.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=110-cc-decl.fth
\   <first third of 110-cc-decl.fth>
\   ```
\ Chs 30 and 31 emit the rest.
```

## Try it

```sh
./build.sh
echo 'int g = 42;
int main() { return g; }' | ./your-cc-runner.sh
echo $?    # 42

echo 'struct P { int x; };
struct P gp;
int main() { gp.x = 7; return gp.x; }' | ./your-cc-runner.sh
echo $?    # 7
```

## Exercises

1. The compiler probably aligns structs to 8-byte boundaries.  Read
   the field-offset accumulation and confirm.  Then construct a
   struct with `char a; int b;` and observe its size.

2. Add `enum` support.  How would you store the enum tag and
   constants?  Compare to how struct tags are stored.

3. Function pointers (`int (*fp)(int);`) — does this compiler
   support them?  Confirm by trying a test case.  If not, sketch
   what the parser change would look like.

4. The data segment grows monotonically.  What's the largest
   data-segment size you've seen for M2-Planet?  Could you measure
   by reading the `e_phdr` of `/tmp/cc-out` after compiling
   M2-Planet?

## Takeaways

- Type-spec parsing is small (~100 lines) because the type system
  is small (Ch 24).
- Struct definitions build descriptors at parse time; struct
  *use* (Ch 28) consults those descriptors.
- Global declarations are just data-segment emissions plus a
  symbol entry — no relocation machinery, because the output is a
  static-linked executable.

Next: Chapter 30 — Statements: if, while, for, return.
