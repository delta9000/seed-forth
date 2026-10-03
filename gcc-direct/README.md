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
stdin. Preprocessing writes stdout unless `-o` names a file. The driver
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
of the current original C files under `runtime/gcc-seed/` and Forth-built
syscall, errno, and startup objects. User `-D`, `-U`, and `-I` options do not
affect that runtime build. Runtime objects are linked eagerly, so this driver
does not provide archive extraction or replacement-libc symbol semantics.
`-nostdlib` omits all runtime/startup objects; the caller must supply `_start`.
Inputs ending in `.o` must satisfy the Forth linker's object contract.

`-static`, `-O0`, and `-g0` describe the actual output and are accepted.
Optimization/debug flags including `-O2` and `-g`, other language standards,
assembly, shared libraries, archives, `-l`, `-L`, dependency files, forced
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
