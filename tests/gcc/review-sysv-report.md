# Independent scalar SysV review, 2026-10-03

These are new reconstruction checks, not recovered historical results.

Command: `python3 tests/gcc/review-sysv-check.py`

Observed result: PASS at host oracle `-O0` and `-O2` for both mapped ELF and
ET_REL object modes, followed by nine additional executable C fixtures and
twenty exact-code rejection cases. Final observed result: 2026-10-03 13:37 UTC.
`review-sysv-results.json` records the complete tested compiler input hashes.

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

## Fail-closed checks

- Duplicate typed/K&R parameters, duplicate or unknown K&R declarations,
  void after another parameter, and unsupported function parameters: 233
- Unspecified declaration versus non-promotion-compatible prototype: 237
- Typed arity still enforced after later unspecified declaration: 235

- 65 parameters or call arguments: 234
- Function-pointer calls with too few or too many arguments: 235
- Conflicting callback parameter signature, integer parameter width,
  signedness, variadic signature, or struct-pointer identity: 237
- Floating function-pointer parameter or floating local: 214
- Aggregate function-pointer parameter: 232

The script records SHA-256 hashes and rejects a compiler source change during
its run. The verified SysV input was
`121-cc-sysv.fth` SHA-256
`221deb7169f094096a3b4a877f7dd7de325ebccbb8a98a3ed09b4c0e59f9e656`.
The JSON hash manifest is printed by the command so later runs can identify
their exact inputs.

## Limits and pending checks

This review does not claim aggregate/SSE ABI support, variadic definitions,
a complete C implementation, a source-built libc, or a direct GCC build.
The independent oracle passes against the new ET_REL object adapter at
`-O0` and `-O2` on the recorded final source snapshot. It exercises the
object symbols and their call relocations through a host linker; it does not
verify the production Forth linker. Subsequent source edits need affected
checks rerun. Floating base declarations, including pointers to floating
types, currently reject before pointer declarators are parsed.


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
