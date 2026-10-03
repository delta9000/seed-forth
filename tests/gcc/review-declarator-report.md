# Independent grouped-declarator and omitted-for-step review

Accepted the measured parser repair after the invalid-function-declarator follow-on. Reviewed source hashes:

- `112-cc-stmt.fth`: `5942ce90a33d95e00462756d09fb634f80824a9f56a7fae5ad871f2198bb52a4`
- `115-cc-native.fth`: `19b7cc5cfe7d2b256038f41f95468ef9136a2a58a90f2a6152caccdf85ce0fea`

No compiler or book edits were made by this reviewer. Target preprocessing, compilation, object emission, runtime generation, and final production linking run through the Forth seed. Host GCC was used only for independent C90 O0/O2 behavior and interoperability oracles; objdump was used only for inspection.

## Grammar, metadata, and control flow

`review-declarator-check.py` passed five executions of the independent strict C90 `review-declarator-fixture.c`: host source O0 and O2, Forth mapped ELF, Forth-only linked ELF, and a host-linked Forth object.

The fixture checks grouped object pointers, grouped function-return pointers, an unspecified declaration followed by a compatible prototype, and pointer-to-pointer returns. Callback arrays occur as local arrays, record fields, typedef-based fields, global initialized arrays, and nested aggregate initializers. Calls exercise unsigned-char arguments, signed-char results, record-pointer results immediately dereferenced for field access, and function-pointer results called immediately. Side-effecting array indices are checked for exactly one evaluation. Object disassembly independently verifies fourteen caller-side unsigned-char conversions, avoiding reliance on a callee also narrowing its input.

Loop checks cover whitespace/comment-only omitted steps, nested loops, continue, break, goto, real prefix increment/decrement steps, exact step/body counts, pointer decrement in the original spaces shape, and the original dyn-string prefix-decrement condition. The typed truth hook is exercised by negative zero and nonzero binary64 conditions.

Twenty-six invalid, incompatible, or deliberately unsupported inputs reject without publishing absent output or replacing existing output. Both object-driver and mapped-ELF paths were tested, for 104 publication checks. These include callback-array signature, return-type and bound conflicts; grouped return/argument conflicts; indirect and nested-returned-callback arity errors; aggregate/long-double callback ABI exclusions; pointer-to-array forms; zero/negative bounds; extra function-pointer depth; and malformed brackets/groups. In the mapped path, the three extern-array conflict fixtures reject earlier with error207 because external data are unresolved there; the object path reaches and confirms error237 compatibility checks.

## Defect found and corrected

Review confirmed that `struct X {int (*f(void));};` was accepted as a field although it declares a function. Plain function fields had the same pre-existing omission. The owner also confirmed ungrouped arrays of functions were accepted. The successor parser rejects plain/grouped function fields and plain arrays of functions with error238; all three have absent/existing-output regression cases. Valid callback arrays, including initialized arrays, still pass.

## Original configured source execution

`review-declarator-consumer-check.py` compiles unchanged originals from `build-out/direct-gcc-inputs/gcc-source/libiberty` using the actual retained `build-out/direct-configure-ul9t208b/build/libiberty/config.h` and the original include directory. It compiles `spaces.c`, `dyn-string.c`, `xatexit.c`, `xexit.c`, and `xmalloc.c`, then links and executes `review-declarator-consumer.c` through the Forth driver.

The consumer checks 279 increasing/decreasing spaces lengths, dynamic-string insertion/copy/substrings/clearing/growth/release, and 70 registered callbacks crossing three xatexit tables. Original xexit drives the callbacks, whose identity, reverse order, and exact count are checked. The same behavior passes host-source C90 O0/O2 and host-linked target-object O0/O2. The host interoperability fixture adapts only the target `__seed_stderr` name to host stderr; allocation failure is not exercised. The Forth-only run uses the actual target runtime and no test allocator or error-path stub.

Original source, original header, configuration, compiler/runtime inputs, objects, executables, and review fixture hashes are recorded in `review-declarator-consumer-results.json`. Compiler and source closure immutability are checked across the run.

## Legacy output invariance

`review-declarator-identity.py` isolates the two parser changes against the owner's saved pre-edit layers while loading all other current layers unchanged. The independent pre-existing-syntax nested-loop fixture runs successfully in default and native modes, and before/after executable bytes are identical in both. This is focused invariance evidence, not a rerun of the historical bootstrap chain.

## Reproduction and limits

Run these from the repository root:

```sh
python3 tests/gcc/review-declarator-check.py
python3 tests/gcc/review-declarator-consumer-check.py
python3 tests/gcc/review-declarator-identity.py
```

The consumer and identity scripts intentionally refer to the retained original configuration and before-edit layer snapshot recorded in their reports. General pointer-to-array and arbitrary recursive declarator support remain outside this bounded repair. Floating call arguments remain an explicitly documented unsupported ABI case; the positive narrow-argument tests therefore use integral conversions. No claim is made that all GCC source or a complete GCC bootstrap now passes.
