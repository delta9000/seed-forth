# Ranked fixed arrays

The original GCC 4.0.4 `tree-ssa-loop-ivopts.c` at source commit
`944765863eec87a9f37e297994fd2af960397138` declares the function-local static
`unsigned costs[2][2][2][2]` at line 2706. Frozen compiler a535 failed with
error 205 at preprocessed line 58477 because only two suffixes were consumed.
The source and its generated configuration are not adapted by this repair.

Direct System V mode now represents further fixed dimensions using recursive
`ty-array` element descriptors. Outer array metadata remains compatible with
one/two-dimensional symbols and fields. Pointer-to-array descriptors are
canonical single-dimension nodes, so a rank-three array row, a grouped pointer
and an array typedef compare by the same shape. Layout, alignment, indexing,
`sizeof`, decay, pointer arithmetic, static relocation addends and initializer
traversal retain the full element type and each dimension. No dimension product
is substituted for the actual type. Native/legacy suffix parsing stays at its
previous two-dimensional boundary.

Every descriptor checks its positive extent and product before allocation or
output publication. The existing 1 GiB complete-object limit remains in force.
The direct profile bounds both written suffix depth and total composed array
rank at 64; rank 65 rejects with 238, including composition through typedefs.
A pointer constructor starts a separate object type; pointer depth is not an
array dimension. These are compile-time bounds, not guarantees that a program
can allocate the maximum-size object at runtime. Tests use declaration-only
maximum-size records and serial subprocesses limited to 1 GiB address space.

Qualified inline arrays support direct indexing and `sizeof` without dropping
qualification. As in the existing array-pointer profile, constructing a new
qualified pointer-to-array remains unsupported and rejects with 238. Existing
unsupported general declarators, VLA bounds, designated initializers and
qualified-pointer rules are not relaxed. Unknown outer extents of ranked arrays
require a braced initializer for each outer element, matching the older matrix
inference boundary; unbraced inferred rows reject with 222. Newly ranked arrays
inside a grouped declarator reject with 238 before a pointer/function suffix
can overwrite the element shape. Ordinary pointer-element arrays, grouped
pointers to ranked arrays, and function-pointer typedef arrays remain supported.
Higher-rank record fields descend to
the real element in aggregate ABI classification, including explicit rejection
of floating-member by-value records. Integer/pointer records retain their
System V INTEGER/MEMORY transport and independent value-copy behavior.

Run `python3 tests/gcc/ranked-arrays-check.py`. The suite compares host O0/O2
programs, both mixed caller/provider directions and a fully Forth-built link.
It covers static/global/automatic/record storage, rank-three/four layouts,
all cell accesses, nested and brace-elided initialization, strings, static
addresses, one-past pointers, pointer compatibility, inferred outer bounds,
qualifiers, and rank/size boundaries. Negative cases require exact diagnostics
and preservation of a prior output. The existing array-pointer, matrix-record,
qualifier and static-address gates remain separate regressions.

The full unchanged GCC translation unit compiles on the repaired compiler
using the retained a535 generated headers. This is compilation evidence only:
a linked/executed GCC compiler and bootstrap are separate uncompleted gates.
