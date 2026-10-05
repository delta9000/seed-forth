# Fixed-array pointer semantics

The direct System V target retains array element type, descriptor, dimensions,
size, alignment and element qualification behind an explicit array type
node. Each node consumes 56 bytes from the existing checked compiler arena; it does not enlarge the arena
or the seed mapping. Ordinary pointer objects remain eight bytes. Function
signatures, object declarations and callback members preserve structural array
identity, including independently declared aliases and arrays of row pointers.

Supported shapes include fixed-size typedef arrays, their pointer levels,
nested aliases within the existing two-dimensional array bound, and named or
abstract grouped pointers such as `long (*p)[3]` and `sizeof(long (*)[3])`.
Dereference preserves the array lvalue for `sizeof` and address-of; value use
performs array decay. Arithmetic, subtraction, indexing and increments use the
complete pointee size. Static addresses retain actual ELF relocations. A bare multidimensional array
in a static initializer decays to a pointer to its complete row, including
when the outer dimension is incomplete; offsets and conditional arms retain
the same structural type and relocation identity. The
24-byte array-based `va_list` declaration is unchanged; a `va_list *` callback
can advance the original caller's list rather than a copy.

Invalid bounds, incompatible dimensions/elements/depth, unsupported shapes,
and invalid pointer operators fail before output publication. Existing files
at an output path survive rejection. An array of grouped pointers to arrays
(`long (*p[2])[3]`) and a grouped function returning a pointer to an array
(`long (*f(void))[3]`) remain explicitly unsupported. Grouped array pointers
with an array-typedef base, such as `row *(*p)[2]`, also remain unsupported;
a `typedef row *slots[2]` followed by `slots *p` retains that type. For these
bounded declarator forms, equivalent supported
pointer typedefs can describe these object/signature types. Grouped multiple-star
function-pointer declarators and abstract casts, such as `long (**slot)(long)`
and `long (**)(long)`, retain the same depth and signature as the equivalent
function-pointer typedef plus an ordinary pointer declarator. See
[nested function-pointer coverage](nested-function-pointer-README.md).
Function type typedef declarations themselves remain unsupported and now reject instead of
being mistaken for scalar typedefs.

Qualified arrays decay in every value context, as in C90 6.2.2.1: a
`const` or `volatile` array, or an array member reached through a qualified
record (binutils elflink.c's `&((const Elf32_External_Rel *) p)->r_offset`),
yields a pointer to qualified elements, and `&a` a pointer to a qualified
array. A row node records the qualifier (`cc-ad-qualified`), so qualified
array-pointer declarations, parameters, type names, arithmetic, comparisons,
conditionals and static addresses are accepted. Declared array pointers take
the base type's qualifiers: `const long (*p)[3]` points to qualified rows,
`long (*const p)[3]` does not. Implicitly discarding a row qualifier
(`long (*p)[3] = t` for `const long t[2][3]`, in an initializer, assignment,
argument or return) rejects with 238 before output publication; an explicit
cast or a qualified destination accepts. Element pointers follow the existing
scalar policy: a decay to `const T *` keeps only the expression's qualifier
provenance flag, so neither `T *q = a` nor a store through such a pointer is
diagnosed. A provenance flag that also covers top-level qualifiers can make a
row qualified conservatively, e.g. a matrix member reached through
`struct S *const s`. `restrict` placement is not checked. See
`tests/gcc/qualified-array-check.py`.

Implicit integer-to-array-pointer conversion accepts runtime zero literals
(including integer suffixes and parenthesized literals), and zero-valued static
constant expressions. More complex runtime integer constant expressions are
conservatively rejected rather than presumed null. Explicit pointer casts and
`void *` conversions follow the existing C-subset cast boundary.

Run `python3 tests/gcc/array-pointer-check.py --baseline-root PATH` and
`python3 tests/gcc/pointer-array-qualifiers-check.py`. The first checks actual
Forth execution, host GCC O0/O2 results, bounded rejections and optional ten-case
legacy/native ELF byte identity. The second exercises qualified array-pointer
shapes, the row-qualifier discard guard, publication guards and unqualified
controls. The gate also compiles separate caller/provider translation units and checks
function and array pointers passed through ellipsis or unprototyped calls,
including stack arguments and mixed SSE use. Both host/Forth directions execute
at O0/O2. Independent ABI checks remain in the integration review evidence.
These gates do not establish a complete GCC or libcpp build.
