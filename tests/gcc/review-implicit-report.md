# Independent C90 implicit-function review

Status: **PASS**, 2026-10-03. No unresolved compiler defect found in the
reviewed scope. Exact compiler, seed, harness and fixture hashes are in
`review-implicit-results.json`; the publisher package is listed in
`review-implicit-manifest.json`.

Run from the repository root:

```sh
python3 tests/gcc/review-implicit-check.py --json tests/gcc/review-implicit-results.json
```

## Result and coverage

- Six defined C90 positive cases; 14 successful System V executions from
  Forth-built mapped ELF and Forth-linked ET_REL objects, plus one successful
  native-dialect regression executable
- Twelve separately built GCC `-std=gnu89 -fno-builtin` executables, covering
  the six positives at both `-O0` and `-O2`, agree with the target results
- Nineteen negative source cases tested in both mapped/object modes, with
  absent and preexisting output paths: 76 compile-failure publication checks
- Four additional publication checks for an unresolved implicit external:
  mapped compilation rejects with 206; the Forth linker rejects with 253;
  neither creates a missing output nor changes an existing output
- Two native isolation checks: undeclared calls retain error 93, while an
  explicit forward declaration compiles and executes successfully

The multi-function fixture uses repeated implicit calls across function and
nested-block scope exits. Reused symbol IDs encounter unrelated parameters,
locals and ordinary-name shadows before later definitions. It also takes a
function address after a declaration-producing call, and uses that pointer
after the definition has patched its address. Tests cover eight integer
arguments, negative `int` return values, default-promoted `unsigned char`
arguments, a compatible K&R definition, and a struct tag sharing an implicit
function's name.

The separate caller ET_REL contains exactly one global undefined `STT_FUNC`
entry for each of its five implicit external names. Forth links the caller
and provider successfully in both object orders. The combined TU also
compiles and links successfully, exercising later-definition fixups in both
output forms. Later compatible `long` and `void` prototypes, existing static
linkage, an expired local shadow, and an unevaluated undeclared call are
separate positive cases.

Negative cases retain errors for unknown values, addresses, function-pointer
assignments and parenthesized unknown identifiers; implicit declarations do
not leak ordinary-name visibility beyond their blocks/functions. Local,
typedef and enumerator shadows cannot be called as implicit functions.
Persistent metadata rejects incompatible return types, prototype parameter
types and variadic declarations even after intervening scopes have reused
symbol IDs. Later object declarations and static linkage conflict with an
implicit external declaration. A later visible prototype enforces argument
count.

## Regression sensitivity

Three controls change only in-memory Forth bindings, leaving source files
untouched:

1. Restoring the old unknown-identifier behavior makes the positive fixture
   reject with error 93, reproducing the original missing capability
2. Restoring scope-limited call-fixup cells produces an executable that
   returns 1 instead of the required 0
3. Restoring scope-limited address-fixup cells produces an executable that
   fails with SIGSEGV instead of returning 0

Thus the fixture detects persistent-scope failures in addition to detecting
whether an undeclared call is accepted. The fault-injected executables run
only in bounded subprocesses; their failures are expected test controls.

## Review findings and limits

The first probes confirmed two issues already being completed by the owner:
an implicit external followed by `static` was accepted, and a later object
declaration reached mapped unresolved error 206 instead of declaration
conflict 237. The final source rejects both with 237 in both modes. The old
namespace test that treated a tag as preventing an implicit ordinary-function
declaration was also corrected by the owner.

Every target object, entry object and executable is produced by Forth. GCC
builds independent oracle programs only; no host compiler, assembler or linker
produces any input to the target route. Positive cases avoid mismatched
default-promoted argument types and return types. This is a bounded scalar
C90 implicit-call review, not proof of complete C90 support or a GCC bootstrap.
Explicit block-scope function prototypes remain outside the implemented
subset. The parent owns broader historical/native regression coverage.

The successful run hashes its complete loaded compiler input before execution
and verifies those bytes are unchanged afterward. Its four core modified
compiler hashes match the owner's
`sysv-implicit-calls-checkpoint-20261003T1613` manifest. No compiler or canonical
book file was edited by this review, and no Git mutation was performed.
