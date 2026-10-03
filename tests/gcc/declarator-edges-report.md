# Grouped declarators and omitted for steps

The measured GCC 4.0.4 libiberty failures are repaired in the shared C parser,
without changing the source translation units or their preprocessed text.

- `extern int (*__errno_location());` retains a function signature returning
  `int *`; a grouped pointer declaration does not automatically mean a
  function pointer.
- `void (*fns[32])(void);` retains its array length and each element's function
  signature, so record layout, indexing, assignment and indirect calls use the
  existing typed pointer representation.
- The apparent prefix-decrement failures in `spaces.c` and `dyn-string.c` were
  caused by whitespace in an omitted `for` step. Replaying that source range
  attempted to parse EOF as an expression. The deferred-step parser now skips
  whitespace and comments before deciding whether an expression exists.
  Prefix decrement already worked and did not need a lowering change.

`112-cc-stmt.fth` and `115-cc-native.fth` are the only compiler layers changed.
The existing function-pointer cast hook and argument/return ABI checks remain
in place. Pointer-to-array forms, extra function-pointer indirection and
unrepresented nested declarator suffixes reject. Function fields and arrays
of functions also reject; callback-pointer arrays remain valid. Grouped ordinary pointers
are represented, but casting a function to `char **` still rejects with 230.
Aggregate and floating callback argument ABI support is not added.

## Verification

`bash tests/gcc/sysv-declarator-edges-check.sh` exercises grouped pointer
returns/objects, callback arrays, typed calls, indirect-call lvalue
single evaluation, pointer decrement, whitespace/comment-only steps, nested
loops and genuine nonempty decrement steps. It runs a Forth-only mapped ELF,
a Forth-compiled and Forth-linked executable, a host-linked Forth object,
and separate strict C90 `-O0`/`-O2` reference executables. Sixteen rejected
forms preserve an existing output artifact.

Existing `sysv-function-pointer-casts-check.sh`, `sysv-knr-check.sh` and
`sysv-abstract-callback-check.sh` pass, including their rejection cases.

`tests/gcc/declarator-edges-proof.py` compiled unchanged original `spaces.c`,
`dyn-string.c`, `fnmatch.c`, `getcwd.c` and `xatexit.c` with the retained
libiberty configure output. Source, object and compiler identity hashes are
recorded in `declarator-edges-results.json`. This proves compilation of these
five units, not completion of the entire configured libiberty archive.

The same proof compared executable bytes before/after these two layer changes:
two default-target fixtures and five native-target fixtures are byte-identical
and retain their expected exits. The baseline compiler layers were captured
before edits at `build-out/declarator-edges-work/baseline`; their hashes are
recorded in the results. Strict literate-source verification passes.

Independent review and original-consumer execution are recorded separately
in the `review-declarator-*` reports.
