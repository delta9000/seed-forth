# Independent scalar SysV review, 2026-10-03

These are new reconstruction checks, not recovered historical results.

Command: `python3 tests/gcc/review-sysv-check.py`

Observed result: PASS at host oracle `-O0` and `-O2` for both mapped ELF and
ET_REL object modes, followed by eleven additional executable C fixtures and
twenty exact-code rejection cases. Latest observed result: 2026-10-03 15:29 UTC.
`review-types-results.json` records the latest complete tested compiler input
hashes for this ABI replay and the metadata review below.
`review-sysv-results.json` retains the earlier 13:37 UTC snapshot.

The production side is the 1,772-byte seed Forth plus repository compiler
modules. `tests/gcc/sysv-compile.sh` produces the target ELF without a host
C compiler, preprocessor, assembler, linker, or runtime. The host-built
oracle maps that ELF and invokes its generated functions through the real
System V AMD64 ABI. Host C/assembly serve only as independent instrumentation
and semantic oracles; they are not bootstrap artifacts.

## Positive checks

- Host-to-seed calls with 0, 6, 7, 8, and 12 scalar arguments
- Seed-to-host callback with 8 arguments and preservation across two calls
- Recursive calls, nested calls, both expression operand orders, switch/goto
- Actual callback-entry RSP modulo 16 equal to 8
- Sentinel preservation of RBX, RBP, R12, R13, R14, and R15
- Signed/unsigned 8-, 16-, and 32-bit incoming arguments and 6,162 return-width
  comparisons per optimization level; 64-bit signed/unsigned arguments
- Variadic outgoing calls with AL equal to 0 and default integer promotions
- Typedef function-pointer return, compatible callback redeclaration,
  array-to-pointer parameter adjustment, compatible struct-pointer signature
- Exactly 64 parameters and arguments, checked using distinct weighted values
- K&R declarations with promoted narrow formals, implicit-int parameters,
  eight mixed-width arguments, and retained typed prototypes after `f()`
- Unused floating/aggregate callback declarations and floating locals,
  real floating sizes, aggregate padding, and unevaluated `sizeof(call)`
- Floating-base pointer address-taking, arithmetic, and `sizeof(*pointer)`

## Fail-closed checks

- Duplicate typed/K&R parameters, duplicate or unknown K&R declarations,
  void after another parameter, and unsupported function parameters: 233
- Unspecified declaration versus non-promotion-compatible prototype: 237
- Typed arity still enforced after later unspecified declaration: 235

- 65 parameters or call arguments: 234
- Function-pointer calls with too few or too many arguments: 235
- Conflicting callback parameter signature, integer parameter width,
  signedness, variadic signature, or struct-pointer identity: 237
- Actual calls through floating/aggregate function pointers or an actual
  floating-local value read: 232; declarations themselves are permitted
- Every rejected translation unit leaves its executable output absent

The script records SHA-256 hashes and rejects a compiler source change during
its run. The verified SysV input was
`121-cc-sysv.fth` SHA-256
`2fb916e207bc79d2a659f0fbec5f90f42a00946e7ea3c74bc977241713cdb999`.
The JSON hash manifest is printed by the command so later runs can identify
their exact inputs.

## Limits and pending checks

This review does not claim aggregate/SSE ABI support,
a complete C implementation, a source-built libc, or a direct GCC build.
The independent oracle passes against the new ET_REL object adapter at
`-O0` and `-O2` on the recorded final source snapshot. It exercises the
object symbols and their call relocations through a host linker; it does not
verify the production Forth linker. Subsequent source edits need affected
checks rerun. Floating and aggregate declaration metadata are preserved;
floating value operations and floating/aggregate ABI calls remain unsupported.

## Independent declaration metadata review

Command: `python3 tests/gcc/review-types-check.py`

Observed result: PASS on 2026-10-03 15:32 UTC, with 31 layout comparisons at
each host optimization level, 29 rejection cases, and 116 output-preservation
checks. Both scripts confirmed stable compiler inputs throughout their runs.

The new fixture is compiled to an object by Forth. Host GCC builds only the
independent layout/reference implementation and the test harness. At both
`-O0` and `-O2`, 31 comparisons cover `float`, `double`, and `long double`
sizes; mixed and nested record/union layout; array typedefs; pointer sizes,
arithmetic and static pointer initializers; callback declarations; and
unevaluated direct/indirect calls returning unsupported value classes.
The generated object has no relocation for the unevaluated functions.

Host code also writes actual floating values through Forth-provided local
and global addresses. These checks prove natural alignment, including
16-byte long-double and record alignment, non-overlapping local allocations,
array extents, and preserved neighboring integer locals. Floating and
aggregate function pointers are passed into and returned from Forth functions
without calling through their unsupported ABI signatures. Six global ELF
symbol sizes are checked independently with `readelf`.

The rejection matrix covers floating/aggregate ABI definitions and direct or
indirect calls, floating reads/writes through locals/globals/pointers/fields,
discarded floating reads, initialization, casts, increments and comparisons.
Each unsupported value operation rejects with 232. An explicitly typed
floating enum constant rejects with 240; `va_arg(list,double)` rejects with
247 and the `varargs:` diagnostic prefix. Every case runs through both the
ELF and object compiler, first with an absent output and then with an existing
sentinel artifact, proving no output publication or replacement on rejection.

One diagnostic distinction is intentional in this review: a floating cast in
an integer global initializer, `int n=(int)(double)1`, rejects with 232 in
the ELF driver's expression initializer and 240 in the object driver's typed
constant initializer. Both reject; the common typed-enum path checks 240 in
both modes. These tests establish declaration metadata and fail-closed value
boundaries, not floating arithmetic or an aggregate/SSE calling convention.


## Independent syscall-object review

Command: `python3 tests/gcc/review-sysv-syscall-check.py`

Observed result: PASS. The independent test parses the generated ELF section
headers, compares `.text` with the expected 26-byte register shuffle, and
prints an `objdump` disassembly. A host shared-library linker and Python
`ctypes` provide an independent calling-convention oracle. Calls checked
process ID, raw `-EBADF` and `-ENOSYS`, unchanged errno, and a real read-only
mapping of a memfd at file offset 8192. The nonzero file offset demonstrates
that the seventh C argument at `[rsp+8]` becomes Linux syscall argument 6 in
R9. All six callee-saved GPR sentinels are checked separately.

The Forth-built object is 880 bytes, SHA-256
`18f80c26c4437d3ad4864c84b6c38adef0bc9b97903500643f69dfc0e2299d54`.
Host-generated shared libraries and test executables are oracles only; they
are not inputs to the bootstrap or claims of a complete source-built libc.


## Bounded original GCC source review

Both paths in `bash tests/gcc/sysv-gcc-ffs-check.sh` were independently
replayed: 100,032 comparisons passed through the Forth object/startup/linker
path, and another 100,032 passed with the host ABI oracle.

`python3 tests/gcc/review-sysv-gcc-ffs-check.py` supplies a separately designed
Python oracle. It verifies the pinned original GCC 4.0.4 `libiberty/ffs.c`
input, compiles it to an object through Forth, verifies that the object has no
relocations, and executes its raw text directly through `ctypes`. The expected
answer comes from Python's low-bit expression `(value & -value).bit_length()`.
All 65,604 comparisons passed: every value from 0 through 65535, each single
bit, one-cleared-bit patterns, zero, all ones, and the signed boundary values.
No host compiler or linker participates in this separate check.

Original source SHA-256:
`514a4bfc11ca70e48d818c9dccfb13b3c7f502371b0b54d0b13c5dec7220ecec`.
Forth object SHA-256:
`19485f7f1610426d4f214da8bc72a9d5678008ba6646094e9ffd4a1f4ffb1782`.
This is one unchanged libiberty source unit, not a complete GCC compiler,
configuration, generator cohort, runtime, or self-rebuild.
