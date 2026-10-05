# Binutils runtime: file metadata, rewind, temporary names, wide and calendar helpers

Original binutils 2.30 `gas`, `ld`, `ar`, `nm`, `objdump`, `readelf` and
`objcopy` need these interfaces beyond the GCC driver set. The stage-B census
found two compile failures (undeclared `S_IWUSR` in `binutils/rename.c` and
`S_IRUSR` in `binutils/objcopy.c`, error 93), the unresolved `rewind` that
stopped `elfedit`, and, once the other links were given zlib by path, the
remaining unresolved symbols below. A host-GCC implicit-declaration scan of
every preprocessed binutils source confirmed the same list. Several of these
were also called without a declaration, so a pointer result (`ctime`,
`mktemp`) would have been truncated to `int`; the headers now declare them.

| Interface | Original consumer |
|-----------|-------------------|
| `S_IRUSR` ... `S_IXOTH`, `S_ISUID`, `S_ISGID`, `S_ISVTX` | `binutils/rename.c` `smart_rename`, `binutils/objcopy.c` `copy_unknown_object` |
| `lstat` | `binutils/rename.c`; libiberty `unlink-if-ordinary.c` |
| `chmod` | `bfd/opncls.c` `bfd_close`, `binutils/ar.c`, `rename.c`, `objcopy.c` |
| `umask` | `bfd/opncls.c` (executable permission bits) |
| `mkdir`, `mktemp` | `binutils/bucomm.c` `make_tempdir` (no `mkdtemp`); libiberty `choose-temp.c` |
| `chown` | `binutils/rename.c` |
| `rmdir` | `binutils/objcopy.c` (archive temporary directory) |
| `<utime.h>` `struct utimbuf`, `utime` | `binutils/rename.c` `set_times` |
| `rewind` | `binutils/elfedit.c`, `binutils/readelf.c`, `ld/ldmain.c` |
| `towlower` | `bfd/peXXigen.c` (resource-name comparison) |
| `mbstowcs` | `gas/read.c` (quoted symbol names) |
| `gmtime` | `binutils/readelf.c` (MIPS, VMS and liblist time stamps) |
| `ctime` | `binutils/bucomm.c` (`ar tv`), `bfd/peXXigen.c` |
| `strftime` | `gas/listing.c` listing time stamp |
| `atof` | `binutils/stabs.c` float constants; see [DECIMAL-INPUT.md](DECIMAL-INPUT.md) |
| `sscanf` `%lu`, `fscanf` `%4095s` | `bfd/archive.c` member sizes, `binutils/readelf.c` interpreter; see [INTEGER-INPUT.md](INTEGER-INPUT.md#binutils-conversions) |

## Single calls

`lstat` (Linux syscall 6), `chmod` (90), `chown` (92), `mkdir` (83), `rmdir`
(84) and `utime` (132) each make one AMD64 syscall through `__seed_syscall6`
in `metadata.c`; raw values in `[-4095, -1]` become errno and `-1`, and
nothing is retried. The kernel supplies every semantic: `lstat` reports a
final symbolic link itself, `chmod` and `chown` follow it, `(uid_t)-1` and
`(gid_t)-1` leave an ID unchanged, `mkdir` applies the process umask, and
`rmdir` fails on a nonempty directory. `umask` (95) cannot fail and returns
the previous mask; the kernel keeps only the 0777 bits. The permission
macros are the Linux octal values; `struct stat` is unchanged
([CONFIGURE.md](CONFIGURE.md)).

`<utime.h>` defines `struct utimbuf` as two `time_t` seconds, the kernel's
record, so `utime` passes it through; NULL sets both times to now. Fresh
binutils configure finds the header and the struct and defines
`HAVE_GOOD_UTIME_H`; without it `rename.c` passed `long[2]` to an undeclared
`utime`. No `utimes`, `futimens` or subsecond interface is supplied.

## rewind, mktemp, towlower, mbstowcs

`rewind(stream)` is `fseek(stream, 0, SEEK_SET)` followed by clearing the
error and end-of-file indicators, so a pushed-back byte is discarded as with
any seek. A failed seek keeps its errno; the indicators are still cleared.

`mktemp` shares `mkstemp`'s template check and getrandom-chosen letters and
digits. It returns the template with six trailing `X`s replaced by a name for
which `lstat` reports `ENOENT`, preserving errno. A template without six
trailing `X`s becomes `""` with `EINVAL`; any other `lstat` error, a getrandom
failure, or 128 existing candidates also yield `""` with that errno (EEXIST
for the last). The name is not reserved: binutils follows it with `mkdir`,
which fails if another process took the name first. Use `mkstemp` for files.

`towlower` maps only ASCII `A`-`Z`, as glibc's C locale does (checked for
every value below 0x3000 and for large and WEOF values). `mbstowcs` treats
each byte below 128 as one wide character, the same ASCII encoding as
`mbtowc` ([WIDE.md](WIDE.md)). With a NULL destination it counts and ignores
the size; otherwise it stores at most `count` characters, including the
terminating zero only when it fits, and returns the count before the zero. A
byte above 127 returns `(size_t)-1` with `EILSEQ`, as POSIX requires; glibc's
C locale leaves errno unchanged there, so the gate checks that errno only for
this runtime.

## gmtime, ctime, strftime

`calendar.c` now shares one proleptic Gregorian conversion between
`localtime` and `gmtime` ([CALENDAR.md](CALENDAR.md)). `gmtime` needs no
`TZ`; both return the same static record, as in glibc. `localtime` keeps its
explicit `TZ=UTC0` requirement, so `ctime`, which formats `localtime(timer)`
as `"Thu Jan  1 00:00:00 1970\n"` in a static buffer, returns NULL with
`EINVAL` for any other zone. Original `bucomm.c` handles that NULL; run
`ar tv` with `TZ=UTC0`. Years are printed with `%d`, so any representable
year fits the buffer.

`strftime` is a bounded C-locale subset: `%Y %m %d %e %H %M %S %j %y %F %T
%z %%`, enough for gas's `"%Y-%m-%dT%H:%M:%S.000%z"`. Fields are formatted
from the record without normalization. `%z` is always `+0000`, because only
UTC records exist. Any other conversion, or a field outside its C range,
returns 0 with `EINVAL` and an empty string; output that does not fit with
its terminating zero returns 0 with an empty string, as C allows. Names
(`%a`, `%b`, `%c`, `%p`, `%Z`) and week numbers are not supplied.

## Gate

`python3 tests/gcc/binutils-runtime-check.py`, registered in
`tests/gcc/check.sh`, builds `tests/gcc/binutils-runtime-check.c` with the
Forth driver and with host GCC/glibc at `-O0` and `-O2`, and runs each in a
fresh directory holding a file, a subdirectory and a symbolic link, with
`TZ=UTC0`. The outputs must be identical apart from two `runtime-only`
`mbstowcs` errno lines, which must show `EILSEQ`. It covers every permission
macro value; umask round trips and its effect on `mkdir`; `mkdir`/`rmdir`
success and `EEXIST`, `ENOENT`, `ENOTDIR`, `ENOTEMPTY`; `chmod` (including
set-user-ID through the link) and `chown` with unchanged and own IDs;
`lstat` versus `stat` on the link; `utime` with explicit, pre-epoch and
NULL times; `rewind` after EOF, after `ungetc` and after a write error;
`mktemp` names, the binutils `mkdir` pattern and `EINVAL` templates; the
binutils `sscanf`/`fscanf` conversions;
`towlower` and `mbstowcs` boundaries; and `gmtime`, `ctime` and `strftime`
for sixteen timestamps from year 1 to 9999 plus short buffers and gas's exact
listing format. The same script runs the [atof gate](DECIMAL-INPUT.md) and
lints the changed runtime sources with host GCC against the runtime headers.

## Consumer build

A fresh `gcc-direct/binutils.py` run (new configure, so `HAVE_GOOD_UTIME_H`
is found) compiles every gas, ld and binutils source, including `rename.c`,
`objcopy.c` and `nm.c` (the last needed a compiler fix, chapter 34), and
links `elfedit` and `sysinfo`. Every other tool link still stops at the
driver's missing `-L`/`-lz` support. Relinking the same commands with
`zlib/libz.a` named by path builds `as-new`, `ld-new`, `ar`, `nm-new`,
`objdump`, `readelf` and the other binutils programs with no unresolved
symbol. All six print their 2.30 version; `as-new` and `ld-new` assemble
and link a program that runs; `ar rcs`, `ar tv`, `nm -s` and `objdump -a`
read archives (the `%lu` gap above was found here); `readelf -l` prints a
host executable's interpreter; and `nm`, `objdump -d` and `readelf -h`
read a Forth-built object. `ctime` output requires `TZ=UTC0`.
