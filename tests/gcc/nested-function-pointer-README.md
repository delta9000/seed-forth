# Nested function-pointer objects

Publication note: this candidate has no independent acceptance. Its original
131-step focused author run, preservation/native checks, and raw `except.c`
object replay passed; no broad suite or combined-tree behavioral check passed
by implication. See [publication status](../../PUBLICATION-STATUS.md).

The GCC `except.c` source contains `*(void (**)(rtx)) data`. The former
abstract declarator rejected this with error231 even though an equivalent
function-pointer typedef followed by `*` worked. Named multiple-star
function-pointer declarators had the same unnecessary restriction.

The System V declarator now stores all grouped stars in the existing
8-bit pointer depth beside the same recursive signature descriptor.
Depth1 is a callable function pointer. Greater depths point to pointer
objects: ordinary loads/stores and pointer arithmetic use eight-byte
cells, and each dereference removes exactly one level. The type checker
keeps return/parameter/aggregate identity; casting a `void *` to a pointer
to a function-pointer object remains an object-pointer conversion.
A direct call through depth 2 or greater is invalid and is rejected with error 230,
including the formerly accepted typedef spelling. A function designator
at depth0 and a function pointer at depth1 remain callable.

The test runs two translation units as strict C90 host oracles at O0/O2,
then both mixed-compiler link directions and a combined Forth-only ELF.
It exercises depths2/3, named and abstract forms, arrays, aggregate members,
loads and replacement stores, static address relocations, single evaluation,
typedef equivalence, callbacks returning callbacks and callbacks with callback
parameters, object-pointer results, double/float argument and result ABI,
eight INTEGER arguments including narrow unsigned conversion, qualifiers,
null pointers and `sizeof`. Depth 255 is accepted; depth 256 is rejected with error 231.
Adversarial tests check exact diagnostics and atomic output preservation
for both mapped ELF and relocatable object output, with existing/absent
output destinations. Older shape tests now reject attempted calls through
pointer objects rather than rejecting their valid declarations.

Run `python3 tests/gcc/nested-function-pointer-check.py` under the shared
resource-bounded isolated supervisor. Broader gates and original-unit
replays are independently controlled; passing this focused suite is not
an integration or full GCC-bootstrap claim.
