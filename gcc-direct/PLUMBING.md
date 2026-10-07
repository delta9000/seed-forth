# Build plumbing from the seed: status

Stages A to D build GCC 4.0.4 with no host compiler, assembler, linker, C
library or parser generator. The host still supplies the *plumbing*: the
shell that runs `configure`, GNU make, and the sed, awk, grep and coreutils
programs that configure scripts and Makefile recipes call. This work replaces
them with the same upstream tools compiled by the Forth C compiler against
`runtime/gcc-seed`.

The tool set and versions are live-bootstrap's, chosen because they are known
to build with a small C library and TinyCC. The sources are pinned by sha256
and fetched into the gitignored `build-out/plumbing-inputs/`:

| Package | sha256 |
|---|---|
| make-3.82.tar.bz2 | `e2c1a73f179c40c71e2fe8abf8a8a0688b8499538512984da4a76958d0402966` |
| bash-2.05b.tar.gz | `ba03d412998cc54bd0b0f2d6c32100967d3137098affdc2d32e6e7c11b163fe4` |
| sed-4.0.9.tar.gz | `c365874794187f8444e5d22998cd5888ffa47f36def4b77517a808dec27c0600` |
| coreutils-5.0.tar.bz2 | `c25b36b8af6e0ad2a875daf4d6196bd0df28a62be7dd252e5f99a4d5d7288d95` |
| grep-2.4.tar.gz | `a32032bab36208509466654df12f507600dfe0313feebbcd218c32a70bf72a16` |
| gawk-3.0.4.tar.gz | `5cc35def1ff4375a8b9a98c2ff79e95e80987d24f0d42fdbb7b7039b3ddb3fb0` |
| tar-1.12.tar.gz | `c6c37e888b136ccefab903c51149f4b7bd659d69d4aea21245f61053a57aa60a` |
| gzip-1.2.4.tar.gz | `1ca41818a23c9c59ef1d5e1d00c0d5eaa2285d931c0fb059637d7c0cc02ad967` |
| patch-2.5.9.tar.gz | `ecb5c6469d732bcf01d6ec1afe9e64f1668caba5bfdb103c28d7f537ba3cdb8a` |
| diffutils-2.7.tar.gz | `d5f2489c4056a31528e3ada4adacc23d498532b0af1a980f2f76158162b139d6` |

## Method

Make is built first, from an explicit file list with no configure run, as
live-bootstrap does. Every later tool is built by that make. Make 3.82 runs a
recipe line without a shell only when the line has no shell metacharacters,
so all configure answers go into each package's `config.h` (with
`-DHAVE_CONFIG_H`) instead of quoted `-D` options. Tracing `execve` confirms
that no shell runs. Objects are linked before archives, because the Forth
linker scans archives in command-line order.

## Discovery results (scratch builds, not yet recipes)

Each tool was built in a scratch tree, with marked workarounds for the gaps
below, and compared against the same upstream version built by host GCC. That
host build is an output oracle only.

| Tool | Result |
|---|---|
| make 3.82 | Builds and runs; matches host make on variables, functions, pattern rules, `-j` and errors |
| sed 4.0.9 | Matches host sed on 15 scripts (groups, ERE, hold space, branches, `y`, ranges, `N`/`D`) |
| grep 2.4 | No source changes; passes its 8 test scripts; 49/49 cases match the 2.4 oracle |
| gawk 3.0.4 | Passes its suite except for the strftime/TZ gap; 63/64 cases match the oracle; generates GCC's `options.c`, `options.h` and `optionlist` byte-identically. Rebuilt with no stand-ins at all (no formatter, math or POSIX stubs; honest `HAVE_STRTOD`/`HAVE_FMOD`): `bigtest` passes, including `strftime` (only the documented `/dev/fd` test differs), and 64/64 cases match the oracle |
| coreutils 5.0 | 70 programs; 363/376 cases match the oracle, and every difference is explained (floating `printf`, obsolete-option configuration). With the runtime's printf, strtod, libm, time zones and buffering, before the POSIX surface was merged (gnulib `mktime` and the `setvbuf`/`strtod`/`localtime` stubs removed, `paste`'s `FILE` hack dropped): 370/376, the 6 left being the obsolete-option configuration that the POSIX work resolves (not yet re-measured together); 20 `seq`/`printf` floating cases equal the glibc build; `cut`, `uniq` and `od` on 2 MB run 17-28x, 14x and 2.6x faster |
| gzip 1.2.4 | Output byte-identical to the oracle; decompresses every input tarball to host gzip's sha256 |
| tar 1.12 | Extracts every input tarball to host tar's tree; archives it creates are byte-identical to the oracle |
| patch 2.5.9 | 20 cases identical to the oracle |
| diffutils 2.7 | `diff`, `cmp`, `diff3`, `sdiff`: 50 cases identical to the oracle |
| bash 2.05b | Not yet attempted past `mkbuiltins`; its first blocker (function typedefs) is now fixed |

## Gaps found

### Compiler

- Block-scope function declarations (`extern char *getenv ();` inside a
  function): **fixed**.
- `main(argc, argv, envp)` received no environment pointer: **fixed** in the
  runtime-aware `_start`.
- Typedefs of function types (`typedef int Function ();`): **fixed**.
- Floating-point initialisers for objects with static storage, including
  integer constants assigned to them: **fixed** (exact binary32/binary64).
- Struct arguments passed by value to unprototyped or variadic functions,
  and `va_arg` of a struct: **fixed** for INTEGER, MEMORY and X87 records;
  records with `float` or `double` members remain error 232 in every form.
- `_Bool` and `<stdbool.h>`: **fixed**.
- Left shift of a negative value in a constant expression, as in
  `TYPE_MINIMUM (time_t)`: **fixed** (folded as two's complement, as GCC does).
- `__FILE__` is now the spelling given on the command line, as with GCC:
  **fixed**, so objects that use `assert` no longer depend on the build
  directory.
- Calls to undeclared functions are accepted silently, which C89 allows. On
  LP64 this truncated pointer and `double` results (`popen`, `floor`,
  `strtod`, `alloca`) and caused the hardest bugs. The driver now accepts
  `-Werror=implicit-function-declaration`, which makes such a call error 228
  naming the function, file and line; plumbing builds should pass it.

### Runtime (`runtime/gcc-seed`)

- `printf` and related functions lacked `%e`, `%f`, `%g`, `%E` and `%G`:
  **fixed**, exact and byte-identical to glibc
  ([PRINTF-FLOAT.md](../runtime/gcc-seed/PRINTF-FLOAT.md)).
- `math.h` declared only `exp` and `log`: **fixed**, a binary64 libm
  ([MATH.md](../runtime/gcc-seed/MATH.md)). Previously missing were `floor`, `ceil`,
  `modf`, `fmod`, `pow`, `sqrt`, `sin`, `cos` and `atan2`. (`strtod`,
  `strtof` and `strtold` are **fixed**:
  [DECIMAL-INPUT.md](../runtime/gcc-seed/DECIMAL-INPUT.md).)
- `localtime` failed unless `TZ` was exactly `UTC0`, and `strftime` lacked
  `%a`, `%b`, `%c` and `%Z`: **fixed** (POSIX `TZ` rules, full C99/POSIX
  `strftime`; [CALENDAR.md](../runtime/gcc-seed/CALENDAR.md)).
- `setbuf` with a non-NULL buffer exited with status 127: **fixed** with
  real buffering (`setvbuf`, `setbuffer`, `setlinebuf`).
- The POSIX surface: **added** to the runtime, each topic with a contract
  and a gate against host glibc (see
  [runtime/gcc-seed/README.md](../runtime/gcc-seed/README.md#posix-surface-for-the-plumbing-tools)).
  This covers the missing headers (`pwd.h`, `grp.h`, `sys/file.h`,
  `sys/utsname.h`, `sys/ioctl.h`, `sys/resource.h`, `termios.h`, `termio.h`,
  `ar.h`, `strings.h`, `memory.h`, `sys/mtio.h`, `sys/sysmacros.h`,
  `sys/times.h`; `alloca.h` only declares a program-supplied C `alloca`),
  every Linux errno and signal number, `PATH_MAX`/`NAME_MAX` and the other
  limits, `_PC_*`/`_SC_*` with `sysconf`/`pathconf`, `DT_*`, `struct
  timespec` with `st_mtim`, `struct lconv`, `mbstate_t`, and the missing
  process, identity, file, system-information, string, environment and
  terminal functions. Returning from `main` now runs `exit`, so `atexit`
  handlers run.
- Rebuilt against this runtime with every POSIX stand-in removed, tar,
  gzip, patch and diffutils reproduce their discovery results (patch and
  diffutils transcripts identical to host-built 2.5.9 and 2.7; tar and gzip
  results identical to the discovery runs), grep 2.4 and gawk 3.0.4 give
  the same 49/49 and 63/64,
  make 3.82 builds without its `pwd.h`/`ar.h`/`getpwnam` stand-ins, and
  coreutils 5.0 (now with `stty`) passes 369 of 376 cases; all 7 remaining
  differences were floating-point `printf`/`seq`, which exact printf now
  fixes (see the table above). The obsolete-option
  differences disappeared because `_POSIX2_VERSION` now matches glibc.
- `sscanf` `%n` (coreutils `stty` crashed restoring a saved `-g` setting):
  **fixed** ([INTEGER-INPUT.md](../runtime/gcc-seed/INTEGER-INPUT.md#consumed-byte-count-n)).
  `FILE` is now a complete type, so coreutils' `paste.c` needs no
  workaround for its `static FILE` objects.
- Stdio was unbuffered, so tools that read or write one character at a time
  ran 10 to 40 times slower than with glibc: **fixed**
  ([STDIO-BUFFERING.md](../runtime/gcc-seed/STDIO-BUFFERING.md)).

## Next steps

1. Land the remaining compiler fixes, then the runtime additions above, each
   with tests and book updates.
2. Turn the scratch builds into pinned recipes with no workaround patches.
   **Done** for make (stage 1) and for sed, gzip, patch, diffutils, grep,
   gawk, tar and 80 coreutils programs (stage 2): see
   [plumbing/README.md](../plumbing/README.md). All build from pristine
   sources except one reviewed coreutils patch (an upstream `realloc` bug
   in `canonicalize.c`), and no shell runs.
   The runtime's `fopen` now accepts glibc's mode `"rt"`, so `sed -f` works.
3. Build bash, then rerun GCC 4.0.4's, binutils' and musl's configure and make
   with a `PATH` that contains only these tools.
   The compiler and archiver on that `PATH` can be the native
   [seed-cc and seed-ar](../tools/SEED-CC.md), which the seed builds itself and
   which build sed 4.0.9 and make 3.82 byte-identically to the Python driver.
