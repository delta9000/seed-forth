# Direct Forth-to-TinyCC

The opt-in compiler extension targets the repository's pinned, patched
TinyCC 0.9.27 AMD64 bootstrap configuration. The legacy M2/pnut route
remains an independent control. The direct seed now rebuilds TinyCC to
the same boot2/boot3 executable and object fixed points.

## Run the default raw-input route

From the repository root, with the pinned submodules available:

```sh
./build.sh
python3 tools/tcc_inputs.py
./seed-forth < tools/tcc-ladder-start.fth
```

For the actual host entry with inventory and helper checks:

```sh
tests/tcc/kernel-route-check.sh
```

This gate resets known generated route outputs, runs the raw-input recipe,
checks source inventories before/after, and exercises both bootstrap and
later ladder helpers. It is `check-all.sh`'s `06c-direct-tcc` step.
QEMU guest execution is a separate test.

Host setup verifies/copies 50 pinned raw archive/libc/tool inputs plus
local source and fixtures. It does not expand a `build-out` source tree.
The original seed builds the runner. Forth then compiles raw portable libc
with the patch/archive helpers; those generated programs unpack the
original TinyCC archive and apply all exact checked replacements. The
recipe verifies 440 prepared-file pins, including the 439 source files
and their manifest, before compiling TinyCC directly and continuing
through the fixed point. `tools/tcc.recipe` has 49 explicit generated
program runs plus exact-patch applications.

The Forth-built bootstrap helpers are:

- `simple-patch`, 27,456 bytes, SHA-256
  `95782bd922815b1ba9df707a22feebe88e8b723010a4d960348934d00d151fc7`
- `bintools`, 75,024 bytes, SHA-256
  `d330f693121629b503cc9e6c8c9af1e384df320f80188986070dfa8e5475f5b4`

The direct seed ELF remains 870,752 bytes, SHA-256
`7411c326d30ff5a0ebadfe36d6218b6e46d2e8357f76d3a003e74ed9aee2fc3a`.
Historical output paths under `build-out/pnut-amd64` are retained for
path-sensitive pins; they do not identify a pnut compilation stage.

## Source and execution boundaries

Every C preprocessing, parsing, instruction-generation, initializer and
ELF-output step is performed by the Forth compiler. No host C compiler,
preprocessor, assembler, linker, libc, object file, prebuilt TinyCC or
pnut compiler executable participates. After launch, seed-derived helpers
also perform extraction and exact patching. Source acquisition, initial
seed construction, launch setup and image packaging remain prerequisites.

Removing the pnut executable does not remove the vendored pnut kit. The
direct route still consumes its TinyCC archive, helper/patch sources, and
portable libc, retaining their copyright/license notices. `PNUT_CC` and
related macros name the source compatibility profile; they do not run pnut.

`prep-stage-sources.py NEW_DIRECTORY` is retained as a separate host-side
source-preparation oracle for focused tests. It verifies pins, extracts
and patches source, and records the resulting bytes. It never compiles or
preprocesses C. `--compare CONTROL_KIT` compares prepared source against
the existing control without consuming its binaries. This helper is not
a dependency of the default raw-input route.

## Compile a prepared input independently

The smaller launcher expects `build-out/tcc-sources` and writes
`build-out/tcc-seed`. If the raw route has already prepared that tree:

```sh
./seed-forth < tools/tcc-start.fth
./build-out/tcc-seed -v
```

For a separate preparation-oracle run, use a new directory with
`prep-stage-sources.py`. The general driver takes `SOURCE OUTPUT` followed
by optional include directories:

```sh
tests/tcc/compile-native.sh tests/tcc/native-stack-call.c build-out/native-stack-call
./build-out/native-stack-call
SF_NATIVE_FLOATBITS=1 tests/tcc/compile-native.sh \
    build-out/tcc-sources/direct-input.c build-out/tcc-seed \
    build-out/tcc-sources/libc64/include
```

## Native profile

- Object storage is LP64: char 1, short 2, int 4, long and pointers 8 bytes
- Calls within the generated image use a private all-stack ABI. Parameters
  are eight-byte slots, permitting portable-libc's stack-based varargs.
  The generated TinyCC implements its own AMD64 SysV target ABI
- Aggregates use aligned fields, anonymous-member promotion, arrays,
  assignment/copy, and bounded brace/string initializers. Static constant
  initializers are lowered to startup routines using the same relocation
  machinery as expressions. They cannot perform evaluated calls, loads,
  assignments, or increments
- `SF_NATIVE_FLOATBITS=1` selects the restricted initial TinyCC profile:
  float/double/long-double storage is eight-byte integer bit transport,
  not general IEEE floating arithmetic. Three unsupported seed operations
  fail visibly rather than continuing: localtime, ldexp and longjmp. See
  [native-runtime.md](native-runtime.md)

Known bounds include no designated initializers, no nested array fields,
no general pointer-to-array declarators, and no aggregate-by-value call
ABI. Aggregate-by-value parameters, returns and arguments fail with 212;
floating types in normal mode fail with 214, including skipped signature
tokens. These forms are not required by the measured seed translation unit.
Native diagnostics and regression cases make unsupported forms explicit.

## Focused checks

`tests/tcc/native-check.sh` runs the native regression gate and is included
in `check-all.sh` as `02c-native`. Individual checks include:

- `tests/tcc/prep-check.sh --target STAGED_DIRECTORY`
- `tests/cc/lp64-encoders-check.py`
- `tests/cc/run-native-expression-checks.sh`
- `tests/tcc/profile-bounds-check.sh` (nine unsupported forms reject;
  explicit seed-only float bit transport still works)
- `tests/tcc/initializers-check.sh`
- `tests/tcc/native-runtime-check.sh`
- `tests/tcc/native-runtime-libc-check.sh STAGED_DIRECTORY/libc64`

The TinyCC header/layout probe is `native-tcc-layout.c`. All existing
legacy compiler gates, the M2 byte-identity check, and the pnut route stay
independent controls. Optional GCC comparisons are verification oracles
only; their outputs are never compiler inputs in the direct chain.

## Independent prepared-source fixed-point check

```sh
tests/tcc/sf-tcc-check.sh
```

This separate verification workflow uses the host preparation oracle to
stage fresh verified sources, compiles the seed
through Forth, runs `downstream-check.py`, checks the seed and final
executable/object pins, and executes the rebuilt compiler's floating,
bitfield, VLA and local-enum acceptance programs. An optional `BUILDROOT`
selects a fresh output directory. The host Python/shell harness controls
staging and execution; it does not preprocess or compile C.

## Prepared-source isolation and audit

This earlier proof starts after extraction and patching; it does not
prove raw archive preparation in the isolated root. Capture and review
the explicit 460-input hash manifest, then run the gate:

```sh
python3 tests/tcc/source-closure-check.py --sources build-out/tcc-sources \
    --write-manifest build-out/tcc-closure-inputs.json
# Review build-out/tcc-closure-inputs.json before the next command.
python3 tests/tcc/source-closure-check.py --sources build-out/tcc-sources \
    --manifest build-out/tcc-closure-inputs.json --dest build-out/tcc-isolated \
    --pin 7411c326d30ff5a0ebadfe36d6218b6e46d2e8357f76d3a003e74ed9aee2fc3a
python3 tests/tcc/source-closure-check-test.py
```

The destination must be new. The manifest includes the original pinned
seed, Forth compiler/launcher source, and verified prepared C/header
sources. The fresh root has no `/bin` or `/usr`, no prebuilt TinyCC, no
pnut executable or compiler source, no object/archive inputs, and no host
preprocessor. The launcher must build the output from the original seed;
copying the previously built candidate is not a closure test.

The strong gate requires an actual `strace` exec-syscall audit, as well as
source verification, static-ELF checks, and the product pin. Missing audit
or isolation support is **SKIP (77)**, never PASS. In the development
sandbox, `PTRACE_TRACEME` was denied, so that audited gate is SKIP.
A separate `unshare`/`chroot` execution of the same fresh source-only root
succeeded: only the original seed was executable before compilation, all
460 input hashes remained unchanged, and the product matched the pinned
seed hash. That establishes the isolated build result without claiming
the unavailable syscall trace. The verifier's 17 focused tests pass.

## Rebuilt TinyCC evidence

The direct seed builds boot0 through boot3 and their runtimes. The
independent prepared-source validation executes forty downstream
compiler/runtime programs (separate from the raw recipe's 49 explicit
runs) and reaches:

- `tcc-boot2` = `tcc-boot3`, 305,496 bytes, SHA-256
  `514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1`
- `tcc-boot2.o` = `tcc-boot3.o`, SHA-256
  `b3730a49338b042d9a3dd3cde1aa4472841296e36f4b09e6e894f405f2648b61`
- Existing boot2 `crt1.o`, `libc.a`, and `libtcc1.a` pins unchanged
- All 136 portable-libc checks passing
- Genuine float, double, and long-double arithmetic, bitfields,
  variable-length arrays, and local-enum acceptance programs passing
  under the rebuilt boot2 and boot3 compilers

The full rebuilt compiler is byte-identical to the existing pnut control's
boot2. These tests do not turn the initial Forth compiler's restricted
float transport into general floating support. The implementation and
canonical source are explained in [Chapter 34](../../book/34-direct-tinycc.md);
full output pins are in [REPRODUCIBLE.md](../../REPRODUCIBLE.md).

## Guest validation scope

Both the raw-input host route and the fresh raw-input K0 → K1 QEMU smoke
passed. K0 built the helpers/TinyCC from raw inputs and used its generated
TinyCC to compile K1; after handoff, K1 rebuilt the seed via hex0 and
repeated the raw-helper/TinyCC/fixed-point/runtime sequence. The clean
wrapper exited 0, guest init reported 0/PASS, and QEMU returned its
expected debug-exit status 1. This used 3 GiB TCG without KVM and took
about eleven minutes. Logs: `build-out/k1-raw-seed-smoke.log` and
`build-out/k1-raw-smoke/serial.log`.

Host source inventories alone would not prove guest execution. The full
GNU/Linux continuation remains incomplete after an interrupted attempt; neither the
TinyCC fixed point nor the K0/K1 handoff implies that larger result.
Current boundary details are in
[HOST-TOOLS.md](../../HOST-TOOLS.md); guest commands are in
[k1/README.md](../../k1/README.md).
