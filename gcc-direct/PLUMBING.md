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
| gawk 3.0.4 | Passes its suite except for the strftime/TZ gap; 63/64 cases match the oracle; generates GCC's `options.c`, `options.h` and `optionlist` byte-identically |
| coreutils 5.0 | 70 programs; 363/376 cases match the oracle, and every difference is explained (floating `printf`, obsolete-option configuration) |
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
  integer constants assigned to them: in progress.
- Struct arguments passed by value to unprototyped or variadic functions
  (error 232).
- `_Bool` and `<stdbool.h>`.
- Left shift of a negative value in a constant expression (error 242), as in
  `TYPE_MINIMUM (time_t)`.
- `__FILE__` expands to the absolute path rather than the spelling given on
  the command line, so objects that use `assert` depend on the build
  directory.
- Calls to undeclared functions are accepted silently, which C89 allows. On
  LP64 this truncated pointer and `double` results (`popen`, `floor`,
  `strtod`, `alloca`) and caused the hardest bugs. Plumbing builds should use
  the census implicit-declaration lint.

### Runtime (`runtime/gcc-seed`)

- `printf` and related functions lack `%e`, `%f`, `%g`, `%E` and `%G`. gawk
  prints every non-integer this way and `seq` relies on it. A scratch exact
  formatter (base-10^9 bignum digits, round half to even, 600/601 cases equal
  to glibc) is a starting point.
- `math.h` declares only `exp` and `log`. Also missing are `floor`, `ceil`,
  `modf`, `fmod`, `pow`, `sqrt`, `sin`, `cos`, `atan2` and `strtod`.
- `localtime` fails unless `TZ` is exactly `UTC0`. Upstream code that does not
  check for NULL then crashes (`tar -tv`, `gzip -l`, `ls -l`, `date`).
  `strftime` lacks `%a`, `%b`, `%c` and `%Z`.
- `setbuf` with a non-NULL buffer exits with status 127.
- Missing headers: `pwd.h`, `grp.h`, `sys/file.h`, `sys/utsname.h`,
  `sys/ioctl.h`, `sys/resource.h`, `termios.h`, `ar.h`, `alloca.h`,
  `strings.h`, `memory.h`.
- Missing constants:
  - errno values: `EXDEV`, `ENXIO`, `EBUSY`, `ETXTBSY`, `EFBIG`, `EROFS`,
    `EMLINK`, `ENOTSUP`.
  - Signal numbers: `SIGPIPE`, `SIGQUIT`, `SIGCHLD`, `SIGALRM`, `SIGTSTP`.
  - Others: `PATH_MAX`, `NAME_MAX`, `_IO?BF`, `_PC_*`, `_SC_*`, `DT_*`.
- Missing types and fields: `struct timespec`, `struct lconv`, `mbstate_t`,
  and an `st_mtim` field in `struct stat`.
- Missing functions, about 60 in all. They fall into these groups:
  - Process control: `popen`, `pclose`, `system`, `execl` and `execlp`.
  - Identity: the `get*id`/`set*id` calls, `getpwnam`/`getpwuid`/`getpwent`,
    the group equivalents, and `getlogin`.
  - File calls: `symlink`, `readlink`, `fchdir`, `fchmod`, `fchown`,
    `lchown`, `ftruncate`, `fsync`, `mknod`, `mkfifo`, `creat` and `dirfd`.
  - System information: `uname`, `gethostname`, `sysconf`, `pathconf`.
  - Strings and numbers: `getline`, `index`/`rindex`, `strcasecmp`,
    `strtoll`.
  - Environment and exit: `setenv`, `atexit`.
  - Time and locale: `tzset`, `localtime_r`, `localeconv`.
  - Others: `tcgetattr`/`tcsetattr`, `flock`, `realpath`.
- Stdio is unbuffered, so tools that read or write one character at a time
  run 10 to 40 times slower than with glibc. Output is correct.

## Next steps

1. Land the remaining compiler fixes, then the runtime additions above, each
   with tests and book updates.
2. Turn the scratch builds into pinned recipes with no workaround patches.
3. Build bash, then rerun GCC 4.0.4's, binutils' and musl's configure and make
   with a `PATH` that contains only these tools.
