# seed-cc and seed-ar: the native compiler driver

`seed-cc` and `seed-ar` are C replacements for the host-Python driver
`tools/gcc-direct-cc.py` and archive adapter `tools/gcc-direct-ar.py`. They are
compiled by the project's own Forth C compiler, bootstrapped straight from
`./seed-forth`, and produce the same bytes as the Python tools: for every
command both accept, the seed receives the same Forth input stream, so
objects, archives, executables, `-E` output, messages and exit statuses are
identical. Like the Python tools they only parse arguments, snapshot and hash
inputs, and publish outputs; all preprocessing, compilation, object writing,
archiving and linking stays in the seed and the numbered Forth layers.

| File | Role |
|---|---|
| `tools/seed-cc.c` | the driver (port of `gcc-direct-cc.py`) |
| `tools/seed-ar.c` | the archiver (port of `gcc-direct-ar.py`, plus archive update) |
| `tools/seed-tool.h` | shared code: direct Linux syscalls, SHA-256, paths, running the seed |
| `tools/seed-cc-start.fth` | the bootstrap, run by the seed itself |
| `tools/seed-cc-boot/*.fth` | fixed Forth driver fragments the bootstrap feeds the seed |

## Bootstrap without Python

From the repository root, after `./build.sh`:

```sh
./seed-forth < tools/seed-cc-start.fth
```

This writes `build-out/seed-cc/seed-cc` and `build-out/seed-cc/seed-ar`, with
scratch objects in `build-out/seed-cc/boot/`, in about 30 seconds. The start
file defines a few Forth words on the seed's primitives (as
`tools/amd64-start.fth` does), lists `runtime/gcc-seed/` and the repository
root with `getdents64`, and for each step forks and execs `./seed-forth` on a
generated input file: the compiler layers (`010-lib.fth` and the sorted
`NNN-cc-*.fth`, except `120-cc-main.fth` and `140-cc-link.fth`), one fixed
fragment from `tools/seed-cc-boot/`, and one C source. In order it compiles
every `runtime/gcc-seed/*.c` except `math.c`, then `tools/seed-cc.c` and
`tools/seed-ar.c`; writes the seven Forth runtime objects; archives every
runtime object except `start.o` into `libseed.a`; and links each program as
`start.o`, the program object, then `libseed.a`. These are exactly the
operations, arena size, include order and member order `seed-cc` itself uses.
Exit status 0 is success; 1xx statuses name the failing operation.

The seed is the only program that runs. Under
`strace -f -e trace=execve` the bootstrap shows 52 `execve` calls, all of
`./seed-forth`: the initial launch, 45 runtime units, the two tools, the
runtime objects, the archive and two links. `tests/gcc/seed-cc-check.py`
repeats this audit (with `--seccomp-bpf`) on every run.

Recorded pins, for compiler and runtime inputs with seed-cc identity
`68650692039d279521c7cfdaff57849e4fc2ce2e463943b2f2952f0d8a6999c8`:

| Output | Bytes | SHA-256 |
|---|---|---|
| `seed-cc` | 156,040 | `c1d406bfe31dcd771df52d9a9134106eaf47074cf43a8b12373293f699990b23` |
| `seed-ar` | 94,528 | `6c1b81cfe59e5ba8379f917595c433e47e398b27d6b3c3624476546919ab8aff` |

The bytes follow the compiler layers and runtime sources, so any change
there gives new pins. The check therefore does not hard-code them; it
requires three builds to agree instead: the bootstrap's output, the Python
driver's build of the same sources, and `seed-cc` rebuilding itself and
`seed-ar` (and that rebuilt `seed-cc` building `seed-cc` once more). All 52
bootstrap runtime objects also equal the Python driver's cached objects.

## Use

`seed-cc` takes the same command line as `gcc-direct-cc.py`; see
[the driver contract](../gcc-direct/README.md). Like it, it passes each source
file and `-I` directory to the preprocessor as spelled, so `__FILE__` is GCC's
spelling, and `-Werror=implicit-function-declaration` makes a call to an
undeclared function error 228. For example:

```sh
build-out/seed-cc/seed-cc -c example.c -o example.o
build-out/seed-cc/seed-cc example.o -lm -o example
build-out/seed-cc/seed-ar rcs libexample.a example.o
```

The tools locate the repository two directories above their own executable,
through `/proc/self/exe`; set `SEED_CC_ROOT` to use a copy installed
elsewhere. They read the compiler layers, the seed and the runtime from that
root, verify `seed-forth` against `000-seed.hex0`, and run a private copy of
the seed, exactly as the Python tools do. Messages keep the Python tools'
prefixes (`seed-forth-cc:` and `gcc-direct-ar:`) and spelling, including
`[Errno N] text: 'path'` for operating-system errors, so build logs and tests
cannot tell the drivers apart.

The runtime-object cache is `build-out/seed-cc-cache/IDENTITY/`, separate from
the Python driver's `gcc-direct-cache/`. The identity hashes the same inputs as
the Python driver's, with `tools/seed-cc.c` and `tools/seed-tool.h` in place
of `gcc-direct-cc.py`; `--print-source-hash` prints it. A text manifest lists
the SHA-256 of each object. A cache entry is used only when the manifest
re-renders byte for byte and every object matches it; objects are copied to
private scratch and verified again. Otherwise the runtime is rebuilt in a
private `.build-*` directory that is renamed into place. A concurrent winner
or a damaged entry is never overwritten, so concurrent cold invocations are
safe.

## Differences from the Python tools

- `seed-ar` updates an existing archive, as GNU `ar r` does: an input whose
  basename equals a member's name replaces the first such member in place,
  other inputs are appended, and Forth rewrites the whole archive and its
  index. `r` without `c` is accepted and reports `creating ARCHIVE` for a new
  archive. Members carry no dates, so `u` always replaces. The Python adapter
  refuses all of these; for fresh archives the two produce the same bytes,
  and every update equals the Python adapter's fresh archive of the resulting
  member list.
- An existing output that is not a GNU archive is reported as such by
  `seed-ar`, where the Python adapter reports that the output exists.
- `seed-cc` also refuses to overwrite its own executable, `tools/seed-cc.c` or
  `tools/seed-tool.h`; the Python driver protects `gcc-direct-cc.py` instead.

## Evidence

```sh
python3 tests/gcc/seed-cc-check.py                 # bootstrap, audit, pins agree, equivalence
python3 tests/gcc/seed-cc-check.py --all-programs  # also every tests/gcc/*.c
python3 tests/gcc/seed-cc-cache-check.py           # cold-cache concurrency and corruption
```

Both run in an isolated source-copy fixture and are part of
`tests/gcc/check.sh`. The equivalence check runs each command once with the
Python tools and once with the native ones, in the same freshly created
directory, and compares exit status, stdout, stderr and the resulting tree:
names, modes and bytes. Its corpus covers the driver, archive and
library-search test programs (`-I`/`-D`/`-U` ordering, stdin, `-x`, `-E` to
stdout and files, multi-file links, `-L`/`-l` order and rescans, `-lm`
precedence and fallback, `-nostdlib`, archive-only `main`, duplicate
definitions), 44 error-path commands with their messages and statuses,
the seed-ar operations, `__FILE__` under five source and six `-I` spellings
(`-E` output and `assert()` objects), and
`-Werror=implicit-function-declaration` on and off, with undeclared calls in
the main file, in a header and after `#line`, and with only declared calls.
That default run is 13 cases and 206 commands. With `--all-programs` it adds
`-c`, `-E` and a link of each of the 205 `tests/gcc/*.c` files: 212 cases and
761 commands, all identical. The cache check starts eight `seed-cc` processes on an absent
cache, requires identical executables equal to the Python driver's, then
damages objects and the manifest and changes a runtime header, the driver
source and the seed.

Two original packages were also built once with each driver, in the same
directory: GNU sed 4.0.9 with its scratch Makefile (`make CC=... AR=...`,
with archive-ordering and missing-function workarounds) and GNU make 3.82 from
its explicit 27-unit list. All 47 outputs, including every object,
`libsed.a`, `sed` and `make`, were byte-identical.
