# Modern plumbing recipe drafts

These are fixed-configuration, static recipes for the pinned upstream
archives in `build-out/modern-inputs/`. No package configure script runs.
The compiler, archiver and ranlib default to the exact paths supplied for the
project's native GCC 4.0.4 / musl 1.1.24 toolchain. Host make, tar and cp drove
recipe development; this is not an audited seed-only bootstrap stage.

| Package | Result | Clean build time |
| --- | --- | --- |
| [make 4.4.1](make-4.4.1/NOTES.md) | Builds; version and parallel small makefile checks pass | 8.829 s, 2 jobs |
| [bash 5.2.37](bash-5.2.37/NOTES.md) | Builds; version and script checks pass | 32.407 s, 2 jobs |
| [coreutils 9.5](coreutils-9.5/NOTES.md) | Eight requested programs build and pass smoke checks; remaining programs not supplied | 15.893 s, 4 jobs |

Times are elapsed compile/generate/archive/link time, excluding unpacking,
configuration discovery and smoke tests. They are observations on this
checkout, not performance guarantees. All three results come from fresh
extractions, not incremental links. Detailed evidence is retained under
`build-out/modern-work/` (`clean-results.json`, `*-clean.log`, `*-check.log`,
`header-probes.json`, `source-audit.json`).

## Rebuild

From the repository root, verify the inputs, unpack into a **fresh** work
area, then invoke each recipe in its package source directory:

```sh
(cd build-out/modern-inputs && sha256sum -c SHA256SUMS)
mkdir -p build-out/modern-work
tar -xf build-out/modern-inputs/make-4.4.1.tar.gz -C build-out/modern-work
tar -xf build-out/modern-inputs/bash-5.2.37.tar.gz -C build-out/modern-work
tar -xf build-out/modern-inputs/coreutils-9.5.tar.gz -C build-out/modern-work
make -C build-out/modern-work/make-4.4.1 -j4 -f ../../../plumbing-modern/make-4.4.1/Makefile
make -C build-out/modern-work/bash-5.2.37 -j4 -f ../../../plumbing-modern/bash-5.2.37/Makefile
make -C build-out/modern-work/coreutils-9.5 -j4 -f ../../../plumbing-modern/coreutils-9.5/Makefile
plumbing-modern/check.sh
```

Run those builds sequentially to keep the total at four jobs. `check.sh make`,
`check.sh bash` and `check.sh coreutils` select individual smoke checks.
There is no install target: outputs are `make`, `bash`, and `src/PROGRAM`
in the respective work trees. Do not overlay an old configure build; these
recipes have deliberately simple object dependencies and no compiler-generated
dependency files. Delete only the corresponding scratch package directory
before testing a fresh rebuild or changing compiler options.

## What the recipes need

Make uses a fixed config.h, bundled fnmatch/glob headers and objects,
high resolution Linux timestamps, and the POSIX jobserver. NLS, Guile,
dynamic loading and posix_spawn are disabled. Its 34 object commands and
static link use no shell operators.

Bash uses fixed config/pathnames/version/pipesize headers, libc malloc,
POSIX signals/job control and multibyte support. Readline/history,
programmable completion, NLS and loadable builtins are disabled. The shipped
parser is used. The same compiler builds mkbuiltins, mksyntax and mksignames;
their outputs are generated during the build. A small helper Makefile runs
mkbuiltins in the builtins directory, avoiding collisions with shell sources.
Library archives are repeated at the end of the link to resolve their cycles.
All recipe lines can run directly without a shell.

Coreutils needs the configured gnulib lib/*.h wrappers, portable static
assertion/checked-arithmetic headers, SELinux stubs, configmake.h, and glibc
scratch-buffer/dynarray headers transformed according to gnulib.mk. It uses
GCC's supported GNU99 mode for loop declarations, native libc allocation and
most POSIX APIs, bundled GNU getopt, and no optional ACL/xattr/NLS/security
libraries. The selected object/feature matrix builds the eight requested programs.
It is not a complete configure-result equivalence claim. See its NOTES.md and header-answers.json.

## Validation and limits

All three archive SHA-256 checks passed, matching SHA256SUMS and the ladder
pins. A byte comparison against tarball C and header members found no changes
to shipped upstream sources. Configured headers and normal generator outputs
are the only source-tree additions. No patches were applied.

The make smoke test checks two parallel prerequisites and variable expansion.
The bash smoke test checks variables, indexed arrays, arithmetic, a function,
command substitution and case matching. ELF program-header inspection confirms
all ten executables have no dynamic interpreter or dynamic segment. This is smoke
coverage, not the upstream regression suites.

Coreutils smoke coverage checks mkdir/cp/cat round trips,
sort order, wc line count, ls output, printf output and date at Unix epoch.
This recipe targets those eight programs; other coreutils programs, tests,
documentation and installation are not yet supplied. Neither successful
smoke tests nor declaration probes imply all gnulib semantic tests pass.

During discovery, absent headers defined to 0 triggered `#ifdef` paths;
missing Bash build definitions/types and archive ordering blocked its build;
incomplete gnulib type/limit answers and missing replacement objects blocked
coreutils. These failures were resolved with configuration, generated headers
and object/link rules. No compatibility source patches were required.

The remaining partial result is package coverage: coreutils is an
eight-program recipe, not a full coreutils installation recipe. The GNU
configure behavior-test matrix, optional services and upstream tests have
not been reproduced. ladder/stage10.sh and ladder/PACKAGES are unchanged.
