# Two-dimensional record fields

The direct System V target retains the second fixed array bound in a new
field-record cell at offset 64. Its record size is 72 bytes; bitfield width
and shift remain at 48/56. The old default/native record layouts, original
1,772-byte seed and native rejection of multidimensional fields are unchanged.
Anonymous aggregate promotion copies the whole target-selected field record.

A field such as `struct cell records[2][3]` retains its element identity and
both bounds. Layout uses the naturally padded element size times both bounds.
Member expressions retain complete matrix and row sizes until decay; indexing
scales by the row and element sizes respectively. `&s.records` and
`&s.records[1]` construct structurally checked array-pointer types. Static
addresses retain their ELF symbol and addend. The ordinary recursive initializer
now visits both dimensions, including braced and brace-elided rows, zero-filled
omissions, character-string rows and nested aggregate elements.

Each positive product and the enclosing record's final padded size are bounded
by the existing direct target's 1 GiB object limit. Oversized dimensions,
products, combined fields, trailing bitfields and tail padding reject before
output publication.
This is a compile-time representation bound, not a promise to allocate or
initialize a 1 GiB object. Tests of the limit use declarations only; processes
run serially with a 1 GiB address-space ceiling. Fixed matrix fields with an
incomplete outer bound, a third dimension, zero or negative bounds, excess
initializers, or incompatible array-pointer destinations reject explicitly.
The existing independent boundaries for designators, general declarators,
floating-value operations and aggregate varargs remain unchanged. Anonymous
aggregate promotion retains matrix metadata, but nested initializer braces
around the flattened anonymous aggregate remain unsupported. Static member
arrays require explicit addresses such as `&global.matrix[0]`; implicit static
member-array decay remains outside the constant-expression parser. Both are
inherited boundaries, separately checked against one-dimensional baseline
analogues during independent review.

Qualification provenance survives direct matrix indexing and member traversal.
Taking the address of, or decaying, a qualified array into a newly constructed
array-pointee type remains error 238, consistently with the existing
[array-pointer profile](array-pointer-README.md). Valid direct reads and
`sizeof` work without dropping that provenance. Invalid member bases and scalar
extra subscripts also reject. Full C qualifier enforcement
is not claimed: the existing scalar/pointer/array qualifier behavior is outside
this change. Arrays and rows remain non-assignable and non-incrementable;
scalar and record elements keep ordinary lvalue behavior. General pointer
constraint checking is not complete: independent review confirmed that unary
plus on pointers and ordinary arrays is already accepted by the frozen
baseline. This change does not claim to close that inherited constraint gap.

Run:

```
python3 tests/gcc/multidimensional-record-check.py
```

The production path uses the Forth compiler, object writer, runtime and linker.
Independent host O0/O2 builds and both mixed caller/provider directions compare
layout, offsets, padding, element values, string rows, static relocations,
nested/anonymous structs, unions, copy independence, and 6/16/168-byte by-value
records. Negative tests require exact diagnostics and preserve an existing
output file. Optional `--baseline-root PATH` compares ten legacy/native
executables byte-for-byte and verifies the original seed hash.

For the measured GCC declaration, add `--source-root ORIGINAL_GCC_TREE` and
`--generated-dir ORIGINAL_GENERATED_GCC_DIR`. The test preserves exact original
`optabs.h` declaration bytes, includes retained `insn-modes.h` and
`insn-codes.h`, and supplies explicitly identified `GTY`, `rtx` and `rtx_code`
shims for names outside the declaration. It executes every handler cell through
Forth and independent host builds and records all input hashes. This is a
bounded source-declaration proof, not compilation of the full header or GCC
translation unit, a linked GCC compiler, or a bootstrap.

Higher fixed dimensions are now represented by recursive array element types;
see [ranked arrays](ranked-arrays-README.md) for their checked size, rank,
initializer, address, qualification and aggregate-ABI rules and new coverage.
