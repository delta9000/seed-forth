# Direct Forth compiler driver

`tools/gcc-direct-cc.py` is the experimental C compiler command for the direct
seed-forth → GCC reconstruction. It is not GCC, TinyCC, or a wrapper around a
host compiler. It preprocesses and compiles C through the numbered Forth
compiler layers, emits their ELF64 relocatable format, and links through
`140-cc-link.fth`. The Python launcher only orchestrates those operations,
copies bytes, verifies hashes, and publishes outputs.

Build the seed first with `./build.sh`. Then, from any working directory:

```sh
/path/to/seed-forth/tools/gcc-direct-cc.py -c example.c -o example.o
/path/to/seed-forth/tools/gcc-direct-cc.py example.o -o example
/path/to/seed-forth/tools/gcc-direct-cc.py -E -Iinclude -DVALUE=7 example.c
/path/to/seed-forth/tools/gcc-direct-cc.py --version
```

The default executable is `a.out`; `-c file.c` produces `file.o` in the current
directory. Multiple sources and objects can be linked, or multiple sources
compiled with `-c` and no `-o`. For stdin use `-x c -`; `-E -` also accepts
stdin. Its presumed source filename is `<stdin>` and quoted includes start
from the current directory. Preprocessing writes stdout unless `-o` names a file. The driver
recognizes joined and separate `-o`, `-I`, `-D`, and `-U` arguments. `-x c`
and `-x none` select/reset the language for following inputs.

Command-line `-D` and `-U` directives are processed in order by the Forth
preprocessor after target predefined macros, separately from the source file.
Object and fixed-parameter function macros are supported. Source-relative
quoted includes are resolved by Forth; explicit `-I` directories precede the
bounded runtime headers. `-nostdinc` removes that final runtime include
directory. No host system headers or environment include directories are
implicitly added. Paths containing spaces are byte-encoded safely for Forth;
the bounded preprocessor still limits source/include path lengths.

Links are static Linux AMD64 LP64 executables. The default runtime consists
of the current original C files under `runtime/gcc-seed/` except `math.c`, and Forth-built
syscall, errno, and startup objects. User `-D`, `-U`, and `-I` options do not
affect that runtime build. Startup is linked first; all other runtime objects
form a deterministic Forth-built archive searched after user inputs. An
original source package may therefore supply an entire competing member,
such as `getopt`, without pulling the runtime's copy. Selection is at object
granularity: replacing one symbol while requiring another from the same
member still diagnoses duplicate definitions. Explicit `.a` inputs use the Forth
archive layer's lazy extraction at their command-line position, including
member rescans for newly selected dependencies. The default startup precedes
archive scanning so an archive may provide `main`. `-l`/`-L` library search is
not implemented; pass an explicit archive pathname. The exact `-lm` option is
a bounded exception: it creates and searches a genuine Forth-built math archive
at that input position. See [math linkage](../runtime/gcc-seed/MATH-LINKING.md).
`-nostdlib` omits all runtime/startup objects; the caller must supply `_start`.
Inputs ending in `.o` must satisfy the Forth linker's object contract.

`-static`, `-O0`, and `-g0` describe the actual output and are accepted.
Optimization/debug flags including `-O2` and `-g`, other language standards,
assembly, shared libraries, other `-l` spellings, `-L`, dependency files, forced
includes, and unknown flags fail explicitly. This matters to configure:
its `-g` probe should fail, and its non-GNU fallback can select empty CFLAGS.
Use `CFLAGS= LDFLAGS=` when explicitly testing a clean bootstrap configuration.
Do not force cached feature answers or advertise GNU compiler compatibility.
`--version` and `-v` identify seed-forth; `-dumpmachine` gives the target tuple.
No `__GNUC__` macro is invented. Compiler diagnostics currently use the
preprocessed source line number and numeric error code.

Each invocation captures the compiler, seed, runtime sources and headers,
checks that those files did not change during capture, and verifies the seed
bytes against `000-seed.hex0`. The seed is copied into private scratch space
and all Forth layers are loaded from the captured bytes. Runtime C/header
snapshots are also private. User headers are read by Forth at their requested
paths, so avoid editing them during an invocation.

The content-addressed cache in `build-out/gcc-direct-cache/` includes the
complete compiler/seed/driver/runtime source hashes in its key. Each cached
object is checked against its manifest before being copied into private
scratch. A stale or damaged entry triggers a source rebuild. Runtime creation
uses private staging directories and atomic directory publication, allowing
concurrent invocations. `--print-source-hash` prints the current cache identity.

Output files honor the invoking process's umask and are published atomically only after successful preprocessing,
compilation, or linking. Existing outputs survive failed operations. Outputs
aliasing a direct input or compiler/runtime source, including symlinks and
hardlinks, are rejected. Compile mode also rejects duplicate default output
names. Scratch paths are private to each invocation.

Run `python3 tests/gcc/driver-check.py` for targeted production checks and
`python3 tests/gcc/driver-cache-check.py` for cold-cache concurrency, corruption,
invalidation, and runtime isolation checks in an isolated source-copy fixture.
These are evidence for this driver contract, not proof that original GCC configure,
generators, a full compiler build, or a GCC fixed point have succeeded.

## Measured original configure runs

`python3 gcc-direct/configure.py --component gcc` runs the original pinned
GCC 4.0.4 `gcc/configure` in a new retained build directory. `libiberty`,
`libcpp`, and `top` select the corresponding original configure scripts.
Use `--forth-ar` when the frozen Forth archive layer is available to select
its genuine AR command and `AR s` index validation as RANLIB. Other host target
tools remain guarded. The archive adapter currently creates fresh indexed
archives; it explicitly rejects incremental replacement of an existing file.
The default source/archive paths are under `build-out/direct-gcc-inputs/`;
explicit paths can be passed with `--source` and `--archive`.

The recipe checks the archive against `gcc64/SOURCES` and compares every
source file and symlink against that archive. It rejects extra source files
(Git administrative metadata is excluded). It captures the Forth compiler,
seed, driver, and runtime sources before invoking any configure probe, so
concurrent development cannot change the compiler partway through a run.

The original scripts receive a C-only, native Linux AMD64 configuration,
explicit Forth CC/CPP commands, empty CFLAGS/CPPFLAGS/LDFLAGS/LIBS, no site
configuration, and no prefilled configure cache. Host compilers, assembler,
linker, archiver, and related target tools are guarded. Their attempted
invocations fail and are logged; the recipe does not supply success answers
or pretend that a target assembler exists.

The printed build path retains `configure.log`, the original `config.log`,
the exact invocation/environment, compiler/source manifests, and individual
compiler traces under `probes/`. Each trace preserves its arguments, working
directory, C/object inputs, current configuration headers, diagnostics,
preprocessor output, and successful file outputs. `probe-inventory.json`
collects their outcomes. A successful configure exit is explicitly provisional:
failed probes, suspicious positive answers, generated size/type macros, and
their consumers still require review.

For the first `gencheck` proof, the original GCC Makefile supplies the required
header and object rules: `gencheck.h` from the configured language-tree list,
`bconfig.h`, `tm.h`, and `build/gencheck.o` with the actual `CC_FOR_BUILD`,
`BUILD_CFLAGS`, and `BUILD_CPPFLAGS`. Its complete link rule additionally
requires `BUILD_LIBIBERTY`. A narrower link of this original generator against
the source-built bounded runtime may establish its direct symbol requirements;
it does not establish the full libiberty/archive or Makefile build closure.
Pass `--gencheck` with `--component gcc` to run this measured generator check
after configure: the unchanged Makefile builds the object, the Forth linker
creates `build/gencheck-direct`, and its output and error-usage behavior are
checked against the original source. `tree-check.h` is the actual generator
stdout. Its expected-output oracle is kept in Python memory; it does not
produce target code or replace generated data. `gencheck-report.json` records
the executable/object/output hashes and the narrowed link scope.

The Makefile template hardcodes `CFLAGS = -g` despite configure accepting an
empty CFLAGS. The recipe therefore passes `CFLAGS= LDFLAGS=` explicitly to
make, retaining the original compilation rule while selecting supported flags.

## Binutils stage-B build

Run the pinned binutils 2.30 configure and original gas/ld/binutils Makefiles
with the frozen Forth compiler and archive adapter in a new work directory:

```sh
python3 gcc-direct/binutils.py build-out/stage-b-codex \
  --oyacc /path/to/forth-built/oyacc --flex /path/to/forth-built/flex -j 6
```

For example, existing Forth-built tools may live at
`/home/ben/code/seed-forth-direct-gcc/build-out/oyacc-source-ycjjoae3/production/oyacc`
and `/home/ben/code/seed-forth-direct-gcc/build-out/tools-run1/lexer-build/flex/flex`;
these are examples, not defaults. Both arguments are required. Jobs default to
six and are limited to 1–6.

Configure's source view omits shipped generated parser/scanner C and headers,
so make regenerates them with the supplied oyacc and flex. The recipe restores
the recorded configure environment and passes empty `CFLAGS`, `LDFLAGS`,
`WARN_CFLAGS`, and `WARN_WRITE_STRINGS`: the Forth driver rejects unsupported
flags, including `-Wwrite-strings` incorrectly selected by bfd's GCC version
test. `make -k` continues across failures. `WORK/make.log` retains make output;
`WORK/stage-b/report.json` and `report.md` list the six requested executables
with SHA256 hashes, all failed compile/link traces, and diagnostic counts.
Configure conftests are excluded from this build census. Missing executables
cause a nonzero exit; a successful configure remains provisional.

## Original RTL generator checks

Given a retained successful component configure directory, run:

```sh
python3 tests/gcc/driver-gengenrtl-check.py build-out/direct-configure-...
python3 tests/gcc/driver-gengenrtl-oracle.py build-out/direct-configure-...
```

The first command compiles unchanged `gengenrtl.c` and `errors.c` with their
actual Makefile rules, then links them with the Forth driver and bounded runtime.
Both generator modes produce retained `genrtl.c` and `genrtl.h`. An independent
reader of original `rtl.def` selects its conditional alternatives using audited
`auto-host.h` facts and the real `GENERATOR_FILE` option. It checks the ordered
format definitions/declarations and RTL macro coverage. The initial naive
inventory included both `USE_MAPPED_LOCATION` branches; that inventory error
was corrected in the checker, and was not a compiler failure.

The input manifest covers every original header and definition file (a superset
of those consumed), concrete generator sources, generated headers, and the
complete frozen Forth compiler/runtime inputs. Coverage checks alone are not a
full byte oracle. The optional second command builds the same unchanged source
with host GCC in C90 mode and host libc, with the same configured branch facts,
and compares both complete outputs byte for byte. Host executables and output
stay under `host-oracle/`; none enters the production path. Neither narrowed
generator link claims completion of the Makefile's `BUILD_LIBIBERTY` dependency.

`python3 tests/gcc/driver-archive-check.py` checks Forth-only archive creation,
lazy driver extraction, archive ordering, dependency rescans, an archive-only
`main`, and rejection/atomic-publication cases. The compiler driver loads
`141-archive.fth` after the linker only when an archive is supplied; the
standalone archive source is never loaded as a C compiler extension.

## C_alloca target frame metric

The original libiberty `C_alloca` estimates caller depth using its own local
variable address. A nested argument expression changes the temporary stack
depth in this Forth compiler: `second(17, C_alloca(64))` followed by
`C_alloca(0)` in the same caller prematurely freed the second live allocation.
The unchanged original code both segfaulted with the real allocator and showed
that precise premature free in a separate observation harness.

`--alloca-frame` applies the hash-checked
`gcc-direct/patches/alloca-frame.patch` in a private source view after verifying
the original archive. It does not edit the upstream source tree or configure
answers. Under `__SEED_FORTH__` alone, `C_alloca` includes private `seed-frame.h`
and obtains its caller's stable saved RBP through `__seed_parent_frame()`.
The Forth-built leaf helper is a separate `frame.o` runtime object. This ABI
requires the calling C function and its parent to use the seed SysV RBP frame
chain; it is not a general frame API for arbitrary host-compiled functions.

The original allocation list, allocation sizes, deeper-frame reclamation,
`C_alloca(0)`, and non-seed fallback remain intact. To check the adapter with a
coherent compiler directory and a retained libiberty configure run:

```sh
python3 tests/gcc/driver-alloca-check.py COMPILER_ROOT LIBIBERTY_WORK
```

The production witness checks same-frame, nested-argument, callback, and
recursive lifetimes using the actual allocator and abort. A separate test
allocator observes all 13 allocations being reclaimed, rejects duplicate or
unknown frees, and poisons freed storage to expose premature reclamation.
That observer is never linked into production generators.

## Original machine-mode generator checks

Use GCC and libiberty configure directories built from the same verified
compiler snapshot, with `--forth-ar` on both and `--alloca-frame` on libiberty:

```sh
python3 tests/gcc/driver-genmodes-check.py GCC_WORK LIBIBERTY_WORK
python3 tests/gcc/driver-genmodes-oracle.py GCC_WORK LIBIBERTY_WORK
```

The production check uses the original libiberty Makefile rules to compile and
archive five selected members: alloca, hashtab, xmalloc, xstrdup, and xexit.
The sole source change is the documented target-guarded C_alloca adapter.
The original GCC Makefile then builds `genmodes` with that actual archive as
`BUILD_LIBIBERTY`. This is a selected-member bootstrap archive, not a complete
libiberty build. Earlier full-library measurement built 57 of 75 objects; the
remaining failures are retained separately.

Before executing the generator, the checker preserves Forth preprocessing and
verifies target definitions from the computed `EXTRA_MODES_FILE` include:
`config/i386/i386-modes.def`, its six extra condition-code modes, extended/quad
formats, and long-double adjustments. It hashes every original header/definition
file, original source/recipe, generated header, compiler input, object, archive,
executable, and output. The historical object produced while computed includes
were skipped is quarantined as `genmodes.incomplete-include.o` and is not reused.

Successful execution and marker coverage remain provisional. The independent
host GCC/libc oracle builds unchanged original generator/library C using the
same configured facts, with native original C_alloca behavior. Its three complete
outputs must equal Forth production byte for byte. All oracle artifacts stay in
`genmodes-host-oracle/` and never feed production. The first complete-target run
exposed a real line-splicing defect: physical backslash-newline inside string
literals became extra output newlines. That differential failure is retained;
it does not count as accepted generator output.

After the literal repair, complete original genmodes output matches the independent
host oracle: `insn-modes.h` is 3522 bytes, `min-insn-modes.c` is 4589 bytes, and
`insn-modes.c` is 16715 bytes. The full-current-core integration replay includes
bitfields and final declarator guards; its object and output bytes equal the
previous narrower compiler composition. `genmodes-proof.json` records the exact
sources, configuration lineage and outputs. The final proof reruns both original
configure scripts on the full current source, including the object-section capacity
repair, and preserves their direct probe traces. This proves the bounded original
generator/selected-library milestone, not full GCC or full libiberty.

A fresh build can reuse an existing configuration without claiming that the new
compiler produced its answers:

```sh
python3 gcc-direct/replay.py ORIGINAL_GCC_WORK ORIGINAL_LIBIBERTY_WORK
python3 tests/gcc/driver-genmodes-check.py PRINTED_GCC_WORK PRINTED_LIBIBERTY_WORK
python3 tests/gcc/driver-genmodes-oracle.py PRINTED_GCC_WORK PRINTED_LIBIBERTY_WORK
```

The helper snapshots the current compiler and copies configured build inputs
into new directories, excluding existing objects, archives and generator
executables. It preserves the original configure command and probe inventory,
records the old configuration compiler and exact header hashes, and supplies
explicit Make command-line overrides for the new Forth tools. Configure is not
rerun, so the source set used to answer its probes remains separately identified.

## cc1 execute torture runner

`gcc-direct/torture.py` replaces `build-out/torture.sh` and the header/torture
steps of `build-out/full-run.sh`. Configure and census remain prerequisites:

```sh
python3 gcc-direct/torture.py CC1 GCC_BUILD_DIR \
  --source build-out/direct-gcc-inputs/gcc-source \
  --levels='-O0 -O2' -j6 --out build-out/torture-run1
```

Supply a Forth-built `cc1` and its configured `build/gcc` directory. Source,
levels and jobs shown are defaults; each repeat needs a fresh output directory
under this worktree's `build-out/`. `--extra` (or `EXTRA`) adds cc1 flags.
This native runner supports `x86_64-pc-linux-gnu`. Host **gcc is ONLY an oracle**:
it assembles/links cc1's assembly with `-no-pie -lm`; the host then executes it.
Oracle binaries never enter the Forth build route. The runner retains
`-quiet -w -fno-builtin-abort`, a 4,000,000 KiB cc1 address-space limit,
120-second compiler and 20-second execution timeouts, and per-test assembly,
executable, diagnostics and output. Parallelism cannot exceed six jobs.

The supplied build stays read only. Configured files are copied into
`OUT/header-build`; make uses the environment recorded in
`BUILD/../../configure-command.json` (`--configure-record` overrides this).
It runs `make CFLAGS= LDFLAGS= STMP_FIXINC= stmp-int-hdrs` with at most `-j6`,
overrides `srcdir`/`VPATH` to the supplied source, and freezes
`Makefile`/`config.status` against reconfiguration. Empty flags avoid the
Makefile's hardcoded unsupported `-g`. Private headers and `xlimits.h` are
rebuilt. Disabling fixincludes also bypasses its `syslimits.h` installation,
so the runner copies `gcc/gsyslimits.h` to `include/syslimits.h` and makes it
readable, exactly the Makefile's `stmp-fixinc` fallback when no fixed system
`limits.h` exists. Its `#include_next <limits.h>` lets generated `limits.h`
reach the host system limits. Private headers precede the native
`/usr/include/x86_64-linux-gnu` headers, as in the scratch full-run script.

The tiny evaluator validates every `.x` against the **25 exact active scripts**
in `torture-x.json`, ignoring only blank lines and full-line comments; it does
not interpret Tcl. Changed/unknown scripts, including orphan `.x` files, fail
visibly. Its explicit patterns, implemented in `evaluate_x`, are:

- `return 0/1`, positive/negated/OR `istarget` globs and expr-return skips.
- Direct/target-conditional `set additional_flags`, including the i386
  board/multilib choice, C99, instrumentation and stack-boundary flags.
- Before-compile string-match/`continue` for `-fomit-frame-pointer`.
- `torture_execute_xfail` and compile/execute conditional XFAIL tuples
  (reason, target globs, include/exclude option groups, nested AND groups).
- `set options` overwritten by `c-torture-execute`; commented-out hooks;
  and the caught malformed target quote in `931004-12.x`, reported explicitly.

No compile-only markers occur in this pinned execute suite; a new one fails
as unrecognised. Reports classify `PASS`, `FAIL(cc1|link|run)`, `SKIP(reason)`
and `XFAIL`. Active exceptions apply only to their failure stage; unexpected
passes are `FAIL` with an `XPASS` reason. Setup/unknown-script errors and
unexpected failures exit nonzero. `report.json` retains hashes, commands,
exit codes, policies and `.x` inventory; `report.md` lists every result;
`results.txt` provides a compact scratch-runner-style listing. Check exception
semantics and error reporting with `python3 tests/gcc/torture-check.py`.

## Recorded parser-generator recipe

`lexers.py` builds oyacc 6.6, Heirloom devtools lex 070527 and its ordinary
five-member `libl.a`, then flex 2.5.11, sequentially with the Forth compiler,
linker and archiver. It reuses `tests/gcc/oyacc-check.py --production-only`
for oyacc's original configure probes and production build. Host compilers
never produce these tools. Python, shell, sed and patch remain orchestration
and source transformation dependencies. Processes are limited to 4 GiB.

Archive names, fetch URLs and SHA-256 pins are in
[lexer-inputs/sources.json](lexer-inputs/sources.json). Fetch/cache the three
archives in gitignored `build-out/lexer-inputs/archives/` (or an external
read-only cache). Copy `lexer-inputs/recipe-reference/` to that inputs
folder's `recipe-reference/`. Archives and extracted originals never belong
in git. An existing evidence directory with that layout can be used directly;
the recipe never writes to it. Flex 2.6.4 is not needed for this chain.

```sh
python3 gcc-direct/lexers.py build-out/lexer-inputs build-out/lexers-run
python3 tests/gcc/lexers-check.py --inputs build-out/lexer-inputs
# The gate also accepts GCC_LEXER_INPUTS=/path/to/offline/inputs.
```

The work directory must be new. Sources are verified and extracted there;
`report.json` records compiler identity, tool paths, SHA-256 of every produced
tool/archive and generated C input, header probes and generator commands.
`sources/source-preparation.json` records original file hashes, exact patch
commands/output and the independent skeleton check; `oyacc/report.json`
records the oyacc production details. `lexers-check.py` skips with status 77
when archives are absent and otherwise checks the known-good Heirloom parser,
ordinary `libl.a`, and flex parser/scanner hashes supplied for this recipe.
Tool binary hashes are recorded without pinning compiler output.

The exact live-bootstrap adaptations, patch provenance and licenses are in
[lexer-inputs/PROVENANCE.md](lexer-inputs/PROVENANCE.md). In particular,
`scan.lex.l` stays unchanged; a separate `scan-ascii.l` transliterates one
U+0160 letter in its copyright comment to S because Heirloom's C-locale wide
I/O rejects UTF-8. Both hashes and the rationale are recorded. The temporary
restricted scanner is replaced by flex's own generated scanner. This recipe
establishes the generator chain, not wide/EUC lex support or a GCC bootstrap.
