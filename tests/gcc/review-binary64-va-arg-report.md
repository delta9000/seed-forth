# Independent review: binary64 va_arg and abs

## Verdict

No blocking defect found in the frozen binary64 retrieval and small `abs`
increment. Reviewed the exact frozen file manifests and artifact hashes from
`binary64-va-arg-private/checkpoints`. Work and generated artifacts remained
in the isolated `binary64-va-arg-review` tree. No shared core, book, Git, or
publication writes were performed. This is a focused review; the parent owns
the full aggregate validation.

## ABI and implementation

`126-cc-varargs.fth` keeps the existing per-invocation 176-byte save area and
adds only binary64 retrieval. The emitted sequence loads the 32-bit `fp_offset`,
compares it unsigned against the full immediate 176, reads the low eight bytes
of `reg_save_area + fp_offset`, and advances that cursor by 16. On exhaustion
it takes eight bytes from the shared overflow cursor and advances it by eight.
It does not modify `gp_offset`. Existing GP retrieval leaves `fp_offset`
unchanged. Eight-byte alignment is sufficient for the supported INTEGER and
binary64 stack arguments; this does not implement long-double alignment or
classification. `121-cc-sysv.fth` is unchanged by the increment.

Independent host callers at O0/O2 verify:

- Indirect record-pointer aliases and one evaluation of side-effecting list expressions
- `va_list` arrays stored in struct members and independent copied cursors
- Qualified double, record-pointer descriptor preservation, and double-pointer GP retrieval
- Fourteen interleaved INTEGER/double arguments, with both banks and overflow in use
- Eight named GP arguments and a host-created list with eight named FP arguments
- A valid host list after the host consumes a 16-byte long-double argument
- Cursor values, stack alignment, and exact double payloads throughout

The owner suite independently reran at O0/O2, covering twelve-double overflow,
seven named GP parameters, restart/copy/end, nested callbacks, host-created
lists, special binary64 payloads, and XMM0 returns. Existing GP production and
opaque floating-list forwarding checks also passed.

## Types and output preservation

The independent suite checks fourteen rejected forms: typedef and qualified
float, typedef long double, char/short, void, array and aggregate results,
wrong record and integer lists, named FP parameters, fixed and variadic FP
calls, and pointer-to-va-list-array parameters. Each emitted one expected
diagnostic, no stdout, and preserved an existing output artifact byte for byte.

A standard `va_list *` parameter is rejected with diagnostic 238 by this
bounded declarator implementation. Replacing only layer 126 with its frozen
pre-increment source reproduces the same diagnostic and output preservation.
This is a pre-existing boundary, not a regression introduced by binary64
retrieval. The positive indirect-list test uses a pointer to the actual
record pointer, as supported by this compiler.

## Runtime abs and original vasprintf

`abs` is a real source-built function with a real `stdlib.h` prototype. Its
ternary implementation and function-pointer fixture passed zero, both signs,
byte/short boundaries, INT_MAX and -INT_MAX in a Forth-only executable and
host O0/O2 callers. INT_MIN remains outside the representable-result domain;
no wrapping or saturating semantics are claimed.

The original GCC 4.0.4 `libiberty/vasprintf.c` remained byte-identical at SHA256
`3e749239083867d756ddb17eefec27905c75b818de968683a8f64412504c98e4`.
The original source, config, ansidecl.h and libiberty.h were hashed before and
after the check. Its unchanged double-sizing branch now compiles. The actual
Forth-only executable passed integer/string formats, flags, width/precision,
star arguments, copied lists, and GP overflow. Four additional comparisons
passed: Forth object with host callers and original host compilation, each
at O0/O2.

The isolated review began without a runtime cache. The direct driver built
runtime C members, startup/syscall objects, and final target bytes using the
Forth compiler/linker. Its source identity matches the owner proof:
`74056637ca3a625a031c2a96c2031b6aa23e47fe7199fd1ba7e750d968e6cc31`.
The production ELF contains only two LOAD program headers, with no dynamic
interpreter. Driver inspection confirms only the seed executable is invoked
for preprocessing, compilation, object writing, and linking; host GCC and
libc are isolated to the comparison executables.

The runtime prerequisites are the existing ctype/assert and strtoul changes,
plus this abs function. This result does not show full floating formatting:
seed stdio explicitly rejects floating conversion characters with EINVAL.
Floating caller arguments, Forth FP named parameters, float and long-double
retrieval, aggregate arguments, and a complete GCC bootstrap remain outside
this increment.

## Validation

Passed in the isolated review tree:

- `python3 tests/gcc/review-binary64-va-arg-check.py --baseline-varargs <frozen pre-increment 126>`
- `python3 tests/gcc/varargs-binary64-check.py`
- `python3 tests/gcc/varargs-vasprintf-check.py --source-root <original GCC> --config-dir <configured libiberty>`
- `bash tests/gcc/abs-check.sh`
- `python3 tests/gcc/varargs-check.py`
- `bash tests/gcc/varargs-interop-check.sh`
- `tools/tangle.sh verify --strict`

The full aggregate was intentionally left to the parent. The known unrelated
sort harness workdir and function-pointer-to-long diagnostic 230 issues were
not changed, weakened, or attributed to this increment.
