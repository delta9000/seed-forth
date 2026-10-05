# Chapter 49 — Building GCC's compiler proper

## Goal and source coverage

We can now use the C compiler written in Forth to build GCC 4.0.4's `cc1`,
link it with Forth, and have that compiler pass its own applicable execution
torture tests at `-O0` and `-O2`. Chapter 48 supplied record transport and
shared argument planning. Here those interfaces join the objects, archives,
and runtime into a compiler that consumes substantially more C than its builder.

**Source coverage:** the tooling in
[`gcc-direct/configure.py`](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/gcc-direct/configure.py),
[`census.py`](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/gcc-direct/census.py),
[`lexers.py`](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/gcc-direct/lexers.py),
and [`torture.py`](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/gcc-direct/torture.py),
with the production driver `tools/gcc-direct-cc.py` and runtime search repair.
These are checked-in tools; this chapter adds no canonical Forth source.

**Concepts carried in:** separate compilation and scalar calls (Chs 35–36),
checked linking (Ch 37), source-built runtime and target headers (Chs 38–43),
lazy archives (Ch 44), and floating, bitfield, and record semantics (Chs 45–48).

**Concepts introduced:** a Makefile-selected compiler census, executable
source generators, relocation-masked function identification, declaration
lint at the integration boundary, and stage-specific execution evidence.

**Deferred:** our own assembler, linker, and libc for `cc1`'s output,
a GCC self-rebuild, and a bootstrap fixed point.

## 1. The driver is not the compiler proper

The command named `gcc` normally coordinates other programs: it chooses the
language compiler, arranges options, and invokes the assembler and linker.
`cc1` is the C compiler proper. It preprocesses and parses C, checks and lowers
the program, optimizes its intermediate forms, selects target instructions,
and writes assembly. Building the driver alone would leave that work undone.

For this pinned GCC, the original `gcc/Makefile.in` names `C_OBJS` for the C
front end and `BACKEND` for the shared compiler machinery. Its `cc1` rule
links both with `LIBS`. Trees, RTL, machine modes, instruction attributes,
and garbage-collection descriptions all have to agree inside that executable;
a mistake in one library call can fail far from the source that introduced it.

That makes this the hard core of the milestone. Forth must compile the
compiler's implementation correctly, including the programs that generate
parts of it. The resulting GCC can then compile language features absent
from the Forth compiler, such as variable-length arrays: the builder needs
the C used to implement GCC, not every C construct GCC accepts as input.

## 2. Freeze the builder, then let Make choose the work

`configure.py` first checks the source tree against the archive pinned in
`gcc64/SOURCES`. `snapshot` captures the seed, Forth layers, driver, runtime
C and headers, and records their hashes in `toolchain-inputs.json`. It
rereads the inputs before accepting the capture, so a concurrent edit cannot
quietly produce a mixed snapshot.

The original configure script receives that frozen driver as both `CC` and
`CC_FOR_BUILD`; `CPP` uses its preprocessing mode. Empty flags, no site file,
and no prefilled feature cache keep probes attached to actual behavior.
Guards for host compilers, `as`, `ld`, and related target tools log attempted
use and fail. `--forth-ar` supplies the genuine Forth archive adapter.
A successful configure exit remains provisional until its answers and
consumers have been audited.

The `--invoke` path preserves each compiler call under `probes/`: arguments,
working directory, copied direct inputs and configuration headers, stdout,
stderr, return code, and successful output bytes with hashes. Make inherits
this traced command, so tracing continues through the build. A failed unit
has its own diagnostic; one that never ran has a failed prerequisite to find.

`census.py` does not maintain a hand-written list of GCC source files.
Its `cc1_objects` asks the configured Makefile to expand:

```make
$(sort $(C_OBJS) main.o $(OBJS))
```

The milestone's configuration selected 220 objects. That is a measured
configuration result, not a constant in the census. Make retains its original
source dependencies, include paths, macros, and rules; the census clears the
unsupported hardcoded debug flags and supplies parser tools and library paths.

After building libiberty, the runner requests those objects with `make -k`.
Continuing after failures makes this a census rather than a stop-at-first-error
build. `compile_traces` associates each object with its last compile invocation;
`census/objects.txt`, `census.json`, and `census.md` retain the selection,
object hashes and sizes, diagnostics, and missing-prerequisite cases.
An object existing is compilation evidence; it is not execution evidence.

## 3. Generated C must have a builder too

GCC's source tree includes programs that write more compiler source.
The Makefile builds and executes `gengtype` to describe garbage-collected
objects, `genattrtab` to derive instruction attributes from machine descriptions,
and generators such as `genmodes` and `gengenrtl` for modes and RTL interfaces.
Their output becomes headers and C units consumed by later compilation rules.
With `CC_FOR_BUILD` pointing to Forth, these generators are Forth-built
executables linked against source-built support, not host-GCC shortcuts.

Parser generation adds another dependency. `census.py` supplies the paths to
Forth-built oyacc and flex as `BISON` and `FLEX`. The original Makefile's
`gengtype-yacc.y` and `gengtype-lex.l` rules use those tools; its C parser
rules also belong to the original build graph. Supplying a tool path and
proving regeneration are separate facts: retained make logs and generated
inputs show which rules actually ran.

`lexers.py` closes the tool dependency through oyacc, Heirloom lex, and flex.
It builds oyacc with `tests/gcc/oyacc-check.py --production-only`, uses oyacc
to generate Heirloom's parser, and compiles and links Heirloom lex with Forth.
Heirloom then generates a temporary flex scanner; the resulting `flex-tmp`
generates flex's own scanner, which replaces the temporary one in the final
build. Archive pins, exact preparation changes, generator commands, and
artifact hashes remain in the recipe reports.

Python, shell, sed, and patch still orchestrate source preparation. They do
not compile these C tools or contribute host-produced object code. The
[parser-generator provenance](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/gcc-direct/lexer-inputs/PROVENANCE.md)
records the source adaptations; the result is not a claim that preparation
has already been moved into the seed.

## 4. Link the whole compiler with the existing words

With `--link`, the census builds libcpp's archive and requests the original
Makefile's `cc1` target. Libcpp hardcodes its archiver command, so the runner
explicitly supplies the configured Forth adapter and fresh-archive flags.
`tools/gcc-direct-cc.py` sends ordinary objects to `lnk-add-object`, archives
to `lnk-add-archive`, chooses `_start` with `lnk-entry`, and finishes with
`lnk-link`. Startup and the bounded runtime are Forth-produced too.

Chapter 44's lazy extraction matters here. `libbackend.a`, `libcpp.a`,
libiberty, and the runtime contribute members demanded by unresolved strong
names; a selected member can create more demand. Every extracted object
occupies a linker slot just as an explicit input does. Counting only the
front-end objects or only the census list understates the complete link.

The previous 256-object policy bound failed with capacity error 251.
The [linker milestone record](https://github.com/delta9000/seed-forth/commit/85fa24f3564599a9c6b84e4b27c59d1702fd5ed4)
explains why the backend and supporting libraries exceeded it. The current
`lnk-object-cap` in `140-cc-link.fth` is 1,024. Increasing that table leaves
Chapter 37's object validation, symbol selection, checked relocations, BSS
placement, and atomic publication rules intact.

## 5. A successful link can still truncate a pointer

The first linked compiler crashed on every variable-length array.
GCC lowers a VLA's stack restore through a try/finally. In original
`tree-eh.c`, `find_goto_replacement` searches the goto queue and then reads
the selected record:

```c
ret = bsearch (&tmp, tf->goto_queue, tf->goto_queue_active,
              sizeof (struct goto_queue_node), goto_queue_cmp);
return (ret ? ret->repl_stmt : NULL);
```

The debugging step was to map fault addresses back to functions by comparing
object code with the linked image. Chapter 37's executable has no symbol
section table, but the input objects retain symbols and relocation records.
Mask the bytes covered by relocations, match the remaining function bytes
against executable text, and use the match position to recover an address
range. Relocated calls and addresses change during linking; ordinary
instruction bytes retain their identity. Ambiguous matches need further
checking against surrounding bytes and call sites.

This connects a machine fault to the queue lookup rather than merely naming
a failed torture input. The
[search repair account](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/runtime/gcc-seed/SEARCH-STRERROR.md)
records the decisive value: `0x00007ffff7fd47e0` became
`0xfffffffff7fd47e0`. The runtime headers had no `bsearch` declaration,
because the runtime had not implemented it. Libiberty supplied a definition
at link time, so there was no unresolved symbol.

Chapter 36's C90 implicit declaration supplied `extern int bsearch()` at
the call. The caller narrowed the result to a 32-bit `int` and sign-extended
it before using it as a pointer. The function returned the right address;
the caller destroyed it. A linker resolves names and relocations, not C
return-type compatibility across translation units.

The repair adds a real `bsearch` to `runtime/gcc-seed/sort.c` and its
pointer-returning prototype to `include/stdlib.h`. Its half-open binary
search compares the key first and returns an element address or null.
The same scan exposed `strerror` in `tree-dump.c`; it too needed a real
implementation and pointer-returning declaration. `tests/gcc/search-error-check.py`
compares Forth-built search and error behavior with independent host-libc
executions, including absent keys, unusual element sizes, and error strings.

`census.py` now calls `implicit_declarations`. When host GCC is available,
it reuses each trace's source, macros, and include paths for a GNU C90
syntax-only pass against the frozen runtime headers, with `-nostdinc` and
`-Wimplicit-function-declaration`. Any reported implicit declaration fails
the census and appears in `census/implicit-decls.json`. Without host GCC,
the report explicitly records that lint was skipped; an empty lint result
and an unavailable oracle are different evidence.

## 6. Let GCC's own programs test the result

`gcc-direct/torture.py` takes the built `cc1` and its configured build
directory. `headers` copies configured inputs into a private output tree
and uses the original `stmp-int-hdrs` rule to build GCC's private headers.
Fixincludes is disabled; the runner installs `gsyslimits.h` using the
Makefile's fallback. The supplied build remains read only.

The optimization options here belong to the newly built GCC, not the
Forth compiler that built it. For each `gcc.c-torture/execute/*.c` and
requested optimization level, `test_one` runs `cc1` to produce assembly, asks host GCC to assemble and
link it with host libc and libm, then executes the test. Diagnostics,
assembly, executables, source hashes, commands, and exit codes stay in the
output tree. `FAIL(cc1)`, `FAIL(link)`, and `FAIL(run)` identify the stage;
compiler and execution timeouts keep a broken case from hanging the run.

The adjacent `.x` scripts are part of the test contract. `evaluate_x`
checks their entire active text against `torture-x.json` before applying
its explicit target, additional-flag, skip, and expected-failure rules.
It is a pinned-script evaluator, not a general Tcl interpreter. Unknown
scripts fail even when their unknown statement would be in an inactive
branch; unexpected passes also fail rather than disappearing into XFAIL.
`tests/gcc/torture-check.py` exercises these policies and failure reporting.

The [recorded execution milestone](https://github.com/delta9000/seed-forth/commit/b368347da8c71b9c058ea2a71ef565ec20c432b0)
reports 1,692 PASS and four IRIX-only SKIP across `-O0` and `-O2`.
The pinned execute directory contains 848 C tests; the two IRIX-only cases
are skipped at each level. These are historical run results, not a fresh
full-suite run performed while writing this chapter. A repeat produces its
own `report.json`, `report.md`, and `results.txt`; inspect those alongside
the compiler identity and census, rather than inferring success from the
runner's existence.

## 7. Keep the next boundary visible

Host assembler, linker, libc, system headers, and libm provide the execution
oracle for GCC's output. Their objects never build `cc1` or its source
generators. Passing the tests establishes that the Forth-built compiler
emits working assembly in that environment; it does not establish an
independent executable path for that assembly.

Our Forth ELF linker consumes the Forth compiler's relocatable contract.
That does not make it an assembler for GCC's emitted text, or a linker for
every object another assembler might produce. Building those downstream
tools and a suitable target libc is a further integration step. Rebuilding
GCC with the resulting toolchain, then establishing a fixed point, is later
bootstrap work.

To repeat the expensive build, prepare the pinned inputs and Forth-built
parser tools, then run `gcc-direct/configure.py --forth-ar` into fresh
`WORK/gcc`, `WORK/libiberty`, and `WORK/libcpp` directories with their matching
`--component` options. Use one frozen compiler epoch; select `--alloca-frame`
for libiberty's documented caller-frame adapter. Run
`gcc-direct/census.py WORK --oyacc OYACC --flex FLEX --link -j 1`, then
`gcc-direct/torture.py WORK/gcc/build/gcc/cc1 WORK/gcc/build/gcc
--levels='-O0 -O2' -j 1 --out build-out/torture-repeat` through Python.
These commands require the archive and sustained build time, so they are
not a short Try-it block; constrain memory separately for your machine.

## Exercises

1. **★** Explain why libiberty's `bsearch` could satisfy the linker while
   its caller still destroyed the returned pointer.
2. **★★** Run `python3 tests/gcc/torture-check.py`, then change an inventory
   script in a scratch copy and explain why an inactive unknown hook must fail.
3. **★★** Trace `build/genattrtab` through the original Makefile and identify
   its compiler, link libraries, input description, and generated consumer.
4. **★★★** Design a function-address matcher using object symbols and
   relocation masks; specify how it rejects ambiguous byte matches.

## Takeaways

- The original Makefile selects cc1's units and builds its source generators through the frozen Forth toolchain.
- A linked compiler still needs declaration lint and execution tests because symbol resolution cannot check C return types.
- Passing GCC's applicable execution torture tests with host output tools proves a compiler milestone while leaving downstream closure and bootstrap for later.

Next: close the assembler, linker, and target-runtime boundary for the
assembly emitted by this Forth-built GCC.
