# patches/gcc64 — our changes for the chain from tcc-0.9.27 to GCC 15.2

`gcc64/run-gcc64.sh` (see [`gcc64/README.md`](../../gcc64/README.md))
takes the amd64 `tcc-boot2` of `tests/pnut/sf-pnut-amd64-check.sh` on to
musl, binutils and four GCCs.  These are all the source changes it makes.
Nothing is sent upstream and nothing under `vendor/` is touched: every
patch is applied with GNU `patch -p1 -F0` (no fuzz) to a fresh copy of a
source whose sha256 is pinned in `gcc64/SOURCES`.  Files are applied in
name order within each directory.

Every file starts with a comment block that says what it changes, why the
chain needs it, and where it comes from.  Patches taken from
[live-bootstrap](https://github.com/fosslinux/live-bootstrap) (commit
`b1ceced7`) are byte-identical to live-bootstrap's file below a
three-line `# gcc64: from live-bootstrap ...` block that we prepend (GNU
`patch` skips leading text), so `tail -n +4 FILE | cmp - LB-FILE` checks
them.  Patches marked "ours" are new here.

| Directory | Applies to | Stage | From |
|---|---|---|---|
| `libc64/` | stage 0's `libc64` (portable_libc + `patches/amd64/libc`) | 1 | ours |
| `tcc/` | stage 0's patched `tcc-0.9.27` tree | 1 (every tcc after `tcc-boot2`) | 3 live-bootstrap, 2 ours |
| `tcc-simple/` | the same tree, by `gcc64/simple-patch.py` | 1 | live-bootstrap |
| `musl-1.1.24/` | musl for tcc | 2, 4 | 4 ours, 2 live-bootstrap |
| `musl-gcc/` | musl for gcc (plus `musl-1.1.24/06`) | 7 | ours |
| `gcc-4.0.4/` | the gcc-4.0.4 git export | 5, 6 | ours |
| `gcc-4.7.4/` | gcc-4.7.4 | 8 | live-bootstrap (all 12) |
| `gcc-10.5.0/` | gcc-10.5.0 | 10 | live-bootstrap (3 of its 5) |

binutils-2.30, flex-2.6.4, gmp, mpfr, mpc, binutils-2.41 and gcc-15.2.0 are
built unpatched.

## libc64 (1, ours)

- `01-bridge.diff`: stage 1 only.  portable_libc's `ldexp` aborts and its
  `strtod` knows four literals; tcc needs both for floating-point
  constants.  Adds an exact IEEE `ldexp`, a general `strtod` (a few ulp,
  not correctly rounded) and a 1 GiB heap (for `tcc -ar` over all of
  musl).  It is used only to build `tcc-p0`, so `musl-1` differs from
  `musl-2` and the fixed point is `musl-2 = musl-3`.

## tcc-0.9.27 (5 + 3 simple patches)

- `01-lb-ignore-static-inside-array.patch` (live-bootstrap
  `steps/tcc-0.9.27/patches/ignore-static-inside-array.patch`): musl's
  headers use `[static N]`.
- `02-lb-dont-skip-weak-symbols-ar.patch` (lb `dont-skip-weak-symbols-ar.patch`):
  `tcc -ar` must index musl's weak symbols.
- `03-lb-static-link.patch` (lb `static-link.patch`): static by default.
- `10-static-libc-after-libtcc1.diff` (ours): `libtcc1.a` (`va_list.c`)
  calls `abort()`; with a static libc, scan `libc.a` again after it.
- `11-no-unlink-dev.diff` (ours): tcc unlinks its output file first, so
  a configure test linking `-o /dev/null` replaced `/dev/null` with a
  regular file when run as root.  Never unlink under `/dev/`.
- `tcc-simple/{remove,addback}-fileopen`, `check-reloc-null`
  (`.before`/`.after` pairs, live-bootstrap
  `steps/tcc-0.9.27/simple-patches/`, byte-identical, applied exactly as
  live-bootstrap's `simple-patch` does): `tcc -ar` opens (and so
  truncates) the archive only after reading its input objects, and
  `fill_local_got_entries` returns early when there is no GOT
  relocation section instead of dereferencing NULL.  lb's fourth pair
  (`fiwix-paddr`) is for its Fiwix kernel and is not used.

## musl-1.1.24 (6)

For tcc on x86_64 (live-bootstrap's musl patches are for i386):

- `01-tcc-x86_64-syscall.diff` (ours): tcc ignores
  `register long r10 __asm__("r10")`, so 4-6 argument syscalls pass their
  arguments through memory under `__TINYC__`.
- `02-tcc-x86_64-va_list.diff` (ours): tcc has no `__builtin_va_list` on
  x86_64; use tcc's own SysV `va_list` and its `__va_start`/`__va_arg`
  (the x86_64 analogue of lb's i386 `va_list.patch`).
- `03-tcc-asm-mxcsr.diff` (ours): tcc's assembler lacks
  `stmxcsr`/`ldmxcsr`; they are hand-encoded as `.byte`.  Stage 4 checks
  that GNU as and tcc agree on the whole of `fenv.s`, instruction for
  instruction.
- `04-tcc-asm-no-plt.diff` (ours): tcc's assembler cannot parse `sym@PLT`;
  static only, so call the symbol directly.
- `05-lb-makefile.patch` (lb `steps/musl-1.1.24/patches/makefile.patch`):
  `tcc -ar` cannot create empty archives.
- `06-lb-madvise_preserve_errno.patch` (lb `madvise_preserve_errno.patch`):
  malloc must not clobber `errno`.  Also used for the gcc-built musl.

`run-gcc64.sh` also deletes `src/complex` (tcc has no `_Complex`, as in
live-bootstrap) and eight SSE `.s` files in `src/math/x86_64/` that tcc
cannot assemble, so their C versions are used.  Neither is done for the
gcc-built musl of stage 7, which is the pristine source plus `06` and:

- `musl-gcc/01-basename-c23.diff` (ours): musl-1.1.24's `char *basename();`
  means `basename(void)` in C23, gcc-15's default, and clashes with
  libiberty.  Later musl dropped the declaration.

## gcc-4.0.4 (1 + three edits)

- `01-collect2-unlink-if-ordinary.diff` (ours): on a failed link,
  collect2 unlinks its output without looking at it; musl's configure
  links `-o /dev/null`, so as root `/dev/null` became a regular file.
  Unlink only regular files and symlinks, as gcc-4.7 does.
- `gcc64/build-gcc4.sh` also makes live-bootstrap's three `sed` edits
  (`steps/gcc-4.0.4/pass1.sh`): `ix86_attribute_table[10]` (tcc),
  `siginfo_t` (musl), `yylex()` (newer bison); and for the tcc build
  only, `C_alloca` → `alloca` (ours; tcc provides `alloca`).

## gcc-4.7.4 (12, all live-bootstrap `steps/gcc-4.7.4/patches/`)

`0001`–`0008`: musl support (upstream gcc commits backported by
live-bootstrap).  `gcc-10-mlong-double`, `gcc-10-libgcc-builtin-macros`,
`gcc-10-fself-test`: what gcc-10's build needs from the gcc-4.7.4 that
builds it.  `remove_gperf_dependency`: no gperf.  `build-gcc47.sh` also
takes `config.sub` from binutils-2.41 (it knows `*-linux-musl`; lb
regenerates instead) and presets `gcc_cv_libc_provides_ssp=yes
gcc_cv_target_dl_iterate_phdr=yes`, which is what lb's regenerated
`gcc/configure` decides for musl.

## gcc-10.5.0 (3, live-bootstrap `steps/gcc-10.5.0/patches/`)

`includes` (libgcc gets the in-tree `cpuid.h`, which pre-5.0 gccs do not
install, and `-fno-pic`, since they reject PIC inline asm that touches
`%ebx`), `libgcc-xfmode` (backport of gcc `43ccb7e4`),
`no-isolate-erroneous-paths-dereference` (a flag gcc-4.7.4 lacks).  lb's
other two, `fix-autoreconf` and `new-gettext`, only matter when
regenerating the build system, which we do not do.

## Changing a patch

Keep it applying with `-F0`, rerun the chain from the stage that uses it
(`gcc64/run-gcc64.sh stageN ... stage12`; each stage rebuilds only its own
outputs), then run with `GCC64_REPIN=1` and copy `logs/hashes.txt` into
`gcc64/HASHES` if the change is deliberate.
