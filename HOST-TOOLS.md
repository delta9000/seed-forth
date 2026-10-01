# Seed-only amd64 executable closure

The default amd64 route now reaches the same TinyCC 0.9.27 fixed point
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
