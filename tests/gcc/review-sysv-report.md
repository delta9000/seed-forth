# Independent scalar SysV review, 2026-10-03

These are new reconstruction checks, not recovered historical results.

Command: `python3 tests/gcc/review-sysv-check.py`

Observed result: PASS at host oracle `-O0` and `-O2`, followed by five
additional executable C fixtures and twelve exact-code rejection cases.

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

## Fail-closed checks

- 65 parameters or call arguments: 234
- Function-pointer calls with too few or too many arguments: 235
- Conflicting callback parameter signature, integer parameter width,
  signedness, variadic signature, or struct-pointer identity: 237
- Floating function-pointer parameter or floating local: 214
- Aggregate function-pointer parameter: 232

The script records SHA-256 hashes and rejects a compiler source change during
its run. The verified SysV input was
`121-cc-sysv.fth` SHA-256
`1e06d0f44a13c0cfeec9239f757049d82ddb03dffc224400b0addd251695d9b0`.
The JSON hash manifest is printed by the command so later runs can identify
their exact inputs.

## Limits and pending checks

This review does not claim aggregate/SSE ABI support, variadic definitions,
a complete C implementation, a source-built libc, or a direct GCC build.
The new object adapter and linker were not used by this initial mapped-ELF
oracle. Independent production syscall-object disassembly/execution is still
pending at this checkpoint. Subsequent source edits need affected checks rerun.
