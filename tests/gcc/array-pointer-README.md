# Fixed-array pointer semantics

The direct System V target retains array element type, descriptor, dimensions,
size and alignment behind an explicit array type node. Each node consumes 48
bytes from the existing checked compiler arena; it does not enlarge the arena
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

Qualification is a conservative boundary: newly constructed array-pointee
shapes involving `const`, `volatile` or `restrict` reject238. Provenance is
retained through typedefs, symbols, members, parameters, result signatures,
casts, pointer expressions and static address parsing so these qualifiers
cannot silently disappear. Existing ordinary qualified scalar/pointer/array
paths retain their previous behavior. This does not claim full C qualifier
semantics. Some otherwise valid qualified array-pointer programs are rejected.
A qualified array may decay as the direct operand of a runtime explicit cast
(`(const T *)table`), whose type name replaces the row shape; see
`tests/gcc/qualifier-order-check.py`.

Implicit integer-to-array-pointer conversion accepts runtime zero literals
(including integer suffixes and parenthesized literals), and zero-valued static
constant expressions. More complex runtime integer constant expressions are
conservatively rejected rather than presumed null. Explicit pointer casts and
`void *` conversions follow the existing C-subset cast boundary.

Run `python3 tests/gcc/array-pointer-check.py --baseline-root PATH` and
`python3 tests/gcc/pointer-array-qualifiers-check.py`. The first checks actual
Forth execution, host GCC O0/O2 results, bounded rejections and optional ten-case
legacy/native ELF byte identity. The second exercises qualifier provenance,
publication guards and unqualified controls. The gate also compiles separate caller/provider translation units and checks
function and array pointers passed through ellipsis or unprototyped calls,
including stack arguments and mixed SSE use. Both host/Forth directions execute
at O0/O2. Independent ABI checks remain in the integration review evidence.
These gates do not establish a complete GCC or libcpp build.
