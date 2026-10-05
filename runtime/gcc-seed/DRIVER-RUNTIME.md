# GCC driver runtime: paths, descriptors, environment and stream input

Original GCC 4.0.4 `make xgcc cpp collect2` needs a few more interfaces. The
driver discovery pass found exactly these gaps and no compiler gap:

| Interface | Original consumer |
|-----------|-------------------|
| `<sys/param.h>` `MAXPATHLEN` | `gcc/tlink.c`: `static char initial_cwd[MAXPATHLEN + 1]` |
| `dup` | libiberty `pex-unix.c` (xgcc, cpp); `gcc/collect2.c` saves stdout/stderr |
| `chdir` | `gcc/tlink.c` recompiles a template in its recorded directory |
| `rename` | `gcc/tlink.c` replaces a `.rpo` file |
| `fscanf` | `gcc/tlink.c` reads `.rpo` records with `"%c "` |
| `putenv` | `gcc/gcc.c`, `gcc/collect2.c`, `gcc/tlink.c` |

`link` is the libiberty `rename.c` fallback; with a runtime `rename`,
configure finds `HAVE_RENAME` and libiberty no longer builds that object.
The runtime still supplies `link` as a single call because `unistd.h` makes
it visible, but no driver object now references it.

## sys/param.h

The header defines only `MAXPATHLEN`, 4096: the Linux kernel's path buffer,
including the terminating NUL, the same bound `execvp` and `getcwd` use.
Configure now answers `HAVE_SYS_PARAM_H`, so `gcc/system.h` and libiberty's
`getpwd.c`, `getpagesize.c`, `getruntime.c` and others include it. Those
files test `EXEC_PAGESIZE`, `NBPG`, `HZ` and `MAXPATHLEN` with `#ifdef` and
keep their fallbacks for the others; `getpwd.c` sizes its buffer from
`MAXPATHLEN`. No `MIN`, `MAX`, `NBBY` or `HZ` consumer is on this path.

## Single calls

`dup` (syscall 32), `chdir` (80), `link` (86) and `rename` (82) each make one
AMD64 syscall through `__seed_syscall6`. Raw values in `[-4095, -1]` become
errno and `-1`; nothing is retried. The kernel supplies every semantic:
`dup` returns the lowest free descriptor sharing the open file description
with close-on-exec clear, `rename` atomically replaces an existing file, and
directory, cross-device and permission rules are the kernel's. `dup2` is the
existing process-API call ([PROCESS-API.md](PROCESS-API.md)); with
`HAVE_DUP2` collect2 uses it rather than its private `dup` loop.

## putenv and environ ownership

`environ` initially points at the vector the kernel placed on the startup
stack ([ENVIRONMENT.md](ENVIRONMENT.md)). `putenv(string)`:

- with `NAME=value`, stores the pointer `string` itself, not a copy, in
  place of the first `NAME=` entry (the one `getenv` returns) or at the end.
  The caller keeps ownership: the string must stay alive and unchanged while
  it is in the environment, and editing it changes the environment. GCC's
  callers pass `xstrdup`, `concat` or obstack strings that they never free.
- with `NAME` and no `=`, removes every `NAME=` entry, as glibc does.
- rejects a null, empty or `=`-leading string with `EINVAL`, and returns
  `ENOMEM` (environment unchanged) when the vector cannot grow.

The first `putenv` copies the current vector's pointers into a runtime-owned
`malloc` vector and points `environ` at it; later calls grow it with
`realloc`. A vector the runtime did not build (the startup one, or one the
program assigned to `environ`) is never written or freed. If the program
assigns a different vector, the next `putenv` copies that one. The runtime
never frees a vector it built earlier, so a program may save and restore
`environ` across `putenv` calls; glibc instead reallocates its previous
vector, so that pattern is not portable and is not compared. A program must
not edit slots of the owned vector directly. `getenv`, `execv`, `execvp` and
pex-unix's child all read `environ` at call time, so a forked child and an
exec'd program see every change.

libiberty's own `putenv.c` uses `setenv`, which the runtime does not supply.
No driver source calls `setenv` or `unsetenv`.

## The alloca reference

libiberty `putenv.c` (and `regex.c`) do not include `libiberty.h`, whose
`alloca(x)` macro becomes `C_alloca(x)` for non-GCC compilers. They carry
their own block: `<alloca.h>` when `HAVE_ALLOCA_H`, `__builtin_alloca` under
`__GNUC__`, else `extern char *alloca ();`. The Forth compiler is neither, and
no `alloca.h` exists, so `putenv.o` referenced a plain `alloca` symbol that
nothing defines. An `alloca.h` mapping to `C_alloca` would make a runtime
header depend on a libiberty symbol, and a real stack `alloca` is not
supported by this compiler. Instead, with a runtime `putenv` configure
answers `HAVE_PUTENV`, drops `putenv.o` from `LIBOBJS`, and the reference
disappears. `regex.o` keeps its reference but no driver program selects it.

## fscanf

`scan.c` runs `sscanf` and `fscanf` through one scanner with one byte of
lookahead. `fscanf` reads with `fgetc` and returns the byte that ended the
scan with the stream's single `ungetc` slot, so the next read sees it. Both
accept the documented integer conversions ([INTEGER-INPUT.md](INTEGER-INPUT.md))
plus `%c` without a width: one byte, whitespace included, no skipping. A
format space skips any input whitespace. EOF or a read error before the
first assignment returns `EOF`. For streams an incomplete `0x` prefix
consumes both bytes before the matching failure.

## Gate

`python3 tests/gcc/driver-runtime-check.py`, registered in
`tests/gcc/check.sh`, runs the Forth-built `tests/gcc/driver-runtime-check.c`
and host GCC/glibc builds at `-O0`/`-O2` in fresh directories with the same
two-variable environment; the 75 output lines must be identical. It covers
`MAXPATHLEN`, lowest-free `dup`, shared offsets and close-on-exec,
`EBADF`; `chdir` with relative names, `ENOENT`, `ENOTDIR` and the empty
path; `link` counts, `EEXIST`, `ENOENT`, `EPERM` on directories; `rename`
replace, self-rename, `EISDIR`, `ENOTDIR` and directories; `putenv` insert,
in-place edit, replace (including a startup variable), removal, growth past
40 entries, a program-assigned vector left untouched, and children started
with `fork`/`execv` that see exactly the changed environment; tlink's
`fscanf("%c ")` loop with `fgets`, numeric and `%c` mixes, mismatch
pushback, `%%` and `EOF`. Host GCC also lints the runtime sources and the
test against the runtime headers alone.
