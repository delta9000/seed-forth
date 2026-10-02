# Direct TinyCC and historical control boundaries

## Current direct route: raw inputs through the fixed point

The Forth compiler compiles TinyCC 0.9.27 directly. No pnut compiler
executable runs to prepare its inputs or anywhere in this route:

```sh
./build.sh
python3 tools/tcc_inputs.py
./seed-forth < tools/tcc-ladder-start.fth
```

Source acquisition, initial seed construction, Linux/CPU/filesystem
support, launch descriptors, and host image construction remain outside
the executable boundary. `tools/tcc_inputs.py` verifies 50 pinned raw
archive/libc/tool inputs; image writers copy those original bytes plus
local source and fixtures. They do not extract TinyCC, apply its patches,
or include an expanded `build-out/tcc-sources` tree in initial images.

After the seed starts, the runner and helpers built from source perform
file operations, extraction and exact patching. Forth performs every C
include, macro expansion, conditional, declaration, expression, instruction
and relocation. No host C compiler, preprocessor, assembler, linker,
object file, pnut compiler or prebuilt TinyCC enters the chain.

The direct chain is:

1. The original seed compiles the narrow recipe runner from Forth/C source
2. The runner stages pinned raw inputs. Forth compiles raw portable libc
   together with `tools/simple-patch.c`, then the archive helper's source
3. Those generated helpers decompress the original TinyCC archive, extract
   its 400 regular source files, apply the exact kit/amd64/libc patches,
   and verify all 440 prepared-file pins
4. The extended Forth compiler preprocesses and compiles the resulting
   TinyCC and portable libc, writing the pinned `tcc-seed`
5. That TinyCC builds its runtime and successive TinyCC generations,
   enforcing the original generation pins and executable/object fixed points
6. Rebuilt TinyCC builds the archive and exact-patch helpers for the later
   kernel ladder; the archive helper includes the documented LP64 CRC fix

`tools/tcc.recipe` lists 49 explicit generated-program runs plus exact-patch
applications. Its bootstrap helpers are `simple-patch` (27,456 bytes,
SHA-256 `95782bd922815b1ba9df707a22feebe88e8b723010a4d960348934d00d151fc7`)
and `bintools` (75,024 bytes,
`d330f693121629b503cc9e6c8c9af1e384df320f80188986070dfa8e5475f5b4`).
The 440 prepared-file pins cover the 439 source files plus their manifest.

The source material still includes the TinyCC kit, archive-tool sources
and portable libc pinned through `vendor/pnut`. Historical `PNUT_CC`
macros select the compatibility profile; they do not run or embed the
pnut compiler. Their provenance and licenses remain intact. The old
pnut scripts are separate controls and GCC-oracle tests.

For path-sensitive later artifact pins, the direct ladder still writes
`build-out/pnut-amd64`. That historical directory name is not a compiler
step. Default recipes and K0/K1 launchers use `tools/tcc-ladder-start.fth`
and `tools/tcc.recipe`.

## Verification and limits

The raw-input host route passes end to end: generated helpers reproduce
all prepared-source pins, Forth produces the unchanged TinyCC seed, and
the full TinyCC generation/runtime pins, executable/object fixed points,
and runtime tests pass. Rebuilt compilers also pass genuine float, double,
long-double, bitfield, VLA and local-enum probes. The initial Forth profile
still has restricted floating bit transport and three fail-closed runtime
operations; see [Chapter 34](book/34-direct-tinycc.md) and the
[native runtime](tests/tcc/native-runtime.md).

```sh
tests/tcc/kernel-route-check.sh   # actual raw-input host entry + helper checks
tests/tcc/native-check.sh         # focused Forth compiler regressions
tests/tcc/sf-tcc-check.sh         # independent prepared-source verification
```

`prep-stage-sources.py` remains an independent host-side preparation
oracle for focused tests and the last command. It extracts and patches
source in that separate verification workflow; it does not supply the
default raw-input route. Its outputs are never host-preprocessed C.

The earlier **prepared-source** isolation test has a narrower starting
point. A fresh user-namespace/chroot with only the original seed executable
and 460 reviewed inputs, no `/bin` or `/usr`, reproduced the 870,752-byte
direct seed. All input hashes remained unchanged and only the seed and
generated TinyCC were executable afterward. This checks compilation from
prepared source, not raw archive extraction inside that isolated root.
Its stronger syscall-audited gate reports SKIP (77) here because
`PTRACE_TRACEME` is denied; no audited PASS is claimed.

```sh
python3 tests/tcc/source-closure-check.py --help
```

The fresh **raw-input K0 → K1 guest smoke test passed** under QEMU TCG
with 3 GiB and no KVM, in about eleven minutes. K0 built the Forth helpers,
unpacked/patched the original inputs, reached the TinyCC fixed point, and
used that generated TinyCC to compile K1. After handoff, K1 imported its
raw-input disk, rebuilt the seed via `hex0-seed`, and independently repeated
the raw-helper/TinyCC/fixed-point/runtime sequence. The wrapper exited 0;
the serial log reports `K1: PASS` and init status 0 (QEMU's expected debug
exit status is 1). Logs are `build-out/k1-raw-seed-smoke.log` and
`build-out/k1-raw-smoke/serial.log`.

Host inventories alone would not prove guest execution; this run supplies
that separate result. The longer GNU/Linux attempt did not complete and
is not implied by the TinyCC fixed point or K0/K1 handoff.

The remaining sections describe the separately retained pnut control.
Its raw-archive preparation boundary is now also preserved by the direct
route, using Forth-built helpers in place of pnut-built helpers.

## Historical pnut control boundary

The retained pnut control reaches the same TinyCC0.9.27 fixed point
without executing host build tools after the initial seed launch:

```sh
./seed-forth < tools/amd64-start.fth
```

Run from the repository root, with the pinned source checkout already
available. `tests/pnut/sf-pnut-amd64-check.sh` is a convenience launcher: it
can build the initial seed, select `BUILDROOT`, arrange a private `/tmp`,
and optionally run a GCC oracle afterward. None of those host-side launch
or verification steps is required by the command above. The optional GCC15
continuation has a distinct, larger trust boundary; see `gcc64/README.md`.

## What is outside the boundary

- The Linux amd64 kernel, CPU, filesystem, permissions, initial process
  launch, working directory, and input descriptor setup
- Obtaining this repository and pnut's pinned source files, and converting
  `000-seed.hex0` to the existing 1,772-byte `seed-forth` ELF (for example
  with the independently pinned 229-byte stage0 `hex0-seed`)
- Host verification tools, including Python/GCC test harnesses, the isolated
  root's preparation, and the separate GCC reference build

This does not remove Linux or prove that the kernel, seed, or source text
is honest. It removes the need to execute additional pre-existing build
binaries after launching the seed. Every executable on this route is a
static amd64 ELF; no host dynamic loader or shared libc is used.

## Construction order, without a cycle

1. `tools/amd64-start.fth` runs directly in the seed. A small set of primitive
   Forth helpers assembles the compiler modules and `amd64-runner.c`, invokes
   the seed to compile them, checks its status, copies the output across the
   possible `/tmp` filesystem boundary, and executes the resulting runner
2. The SF-built runner reads `tools/amd64.recipe`. Its narrow language has
   explicit arguments, quoting and named variables, file operations, hashes,
   comparisons and checked process execution. It has no shell, PATH lookup,
   command substitutions, glob expansion, or general Bash compatibility
3. The runner checks the 56 files listed in `tools/amd64-inputs.sha256` and
   stages only those files: the pnut sources the route reads (its native
   x86_64 backend, kit's bintools, libtcc1 and tcc tarball, and the
   portable libc). The manifest is generated offline from pnut
   `abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d`; Git metadata and untracked
   files never become compiler inputs
4. The runner assembles the stage-1 Forth/C input, then the seed builds
   `sf-pnut64`. That compiler builds the include flattener before bintools
   exists. The flattener reproduces the pinned script's 68,580-byte output
5. Stage-3 pnut builds unchanged bintools plus the checked `simple-patch`
   helper. Bintools decompresses/extracts the vendored TinyCC source archive
6. The runner applies exact patch manifests, checking pre/post SHA-256 and
   promoting validated same-directory candidates with the Linux rename
   syscall. It carries on through every compiler/library pin, executable
   and object fixed points, runtime tests, and the TinyCC→pnut round-trip

A runner-only Forth extension, `tools/amd64-syscalls.fth`, resolves the
runner's explicit `syscall3` declaration. It maps C's four arguments
`(number, a, b, c)` to the Linux syscall ABI, clears the fourth kernel
argument, and returns the raw result. The launcher inserts this extension
only when compiling the runner. Existing compiler sources, symbol slots,
literate chapters and all other routes remain unchanged.

## Operations and limits

The runner supplies checked byte copy/concatenation, directory staging,
mkdir/chmod/unlink/rename, SHA-256, byte comparison, fork/exec/wait, and
explicit stdin/stdout/stderr redirection. Directory copies reject symlinks
and special files. The normal work tree is a private, non-concurrent build
directory. Cleanup accepts only normalized, symlink-free paths inside this
checkout's `build-out/`; an external `BUILDROOT` must be new. No general
shell interpretation occurs, and every child exit status is checked.

The loader's default work tree is `build-out/pnut-amd64`. Descriptor 9 can
supply one build-directory line; descriptor 8 can supply `1` for deliberate
artifact repinning. The Bash launcher exposes these as `BUILDROOT` and
`SF_PNUT64_REPIN=1`. Repinning leaves source and patch hashes strict, prints
artifact hashes, and exits nonzero for review before accepting new pins.
Do not run concurrent builds in one checkout: the compiler's fixed
`/tmp/cc-out` and the launcher's `build-out/amd64-runner` are shared names.
The wrapper uses a private `/tmp` when namespaces are available.

The include flattener intentionally supports only the pinned kit's include
syntax. It bounds input/output, recursion and line sizes, rejects cycles
and unsupported names, and emits nothing on input errors. Its system-header
suppression preserves the original script's relevant grep semantics;
this is not a general C preprocessor.

`simple-patch` is binary-safe exact replacement/copy, not GNU patch. It
requires a unique, nonempty before-pattern and a new output path, handles
short I/O and close errors, and bounds each input/output to 16 MiB. The
runner validates each candidate before renaming it. Failure leaves the
original unchanged; a stale candidate blocks retry until a clean rebuild.
A manifest is not a transaction: earlier successful entries remain if a
later entry fails. There is no fuzz, fsync/crash guarantee, metadata
preservation, or support for concurrent writers.

## Verification

```sh
./check-all.sh
tests/pnut/host-tools-check.sh
SF_PNUT64_GCC_ORACLE=1 tests/pnut/sf-pnut-amd64-check.sh
./verify.sh
```

`amd64-isolated-check.sh`, called by `host-tools-check.sh`, creates a fresh
root with source text, archive inputs and exactly one executable:
`seed-forth`. It has no `/bin` or `/usr`. In a user/mount namespace it
chroots and directly launches the seed. The complete route passes there;
the runner records 79 child executions in `executables.log`. The loader's
prior executions are the seed compiler and the newly built runner. The
filesystem's absence of host binaries enforces the closure; the log is an
inventory, not a security monitor. Namespace unavailability is reported
as a skip, never as a demonstrated isolated pass.

Focused tests compare SHA-256 against independent vectors and Python,
exercise file/argument/process failure paths, guard patch and cleanup
behavior, compare include output with the original script, and verify
exact fixtures against the original diffs. Host-only injected-I/O tests
cover failures difficult to force through normal files. CI runs these
checks in addition to the existing reproducibility and book checks.

The final TinyCC pin remains:

`514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1`

The independently checked flattener binary is
`e08be4cd5fd6e8c6ddc7fa034c8f1722844262b7b5cfc2149052672a0700d651`;
its flattened source is
`d7dbb22dfb0ab6b689c33a55b23b2f9baabd7eb3df653627fd5b3c89276e4102`.
The stage-3 patch helper is
`bc73ae05e3d0b31254347465d25a1417b9f3900085831615bce8599e7068bc9f`.
