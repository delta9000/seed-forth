# patches/amd64 — our changes for the amd64 route to TinyCC

`tests/pnut/sf-pnut-amd64-check.sh` climbs from seed-forth to tcc-0.9.27
with every program an x86-64 ELF:

```
seed-forth -> sf-pnut64 -> pnut-exe -> pnut-exe-for-tcc -> tcc-pnut
           -> tcc-boot0 -> tcc-boot1 -> tcc-boot2 = tcc-boot3
```

pnut's own TinyCC kit (`vendor/pnut/kit/`) targets i386 only.  These
patches are everything this route adds to it.  They are not sent upstream:
upstream sources are pinned by hash (see below) and the patches live here.
Every patch is a unified diff with a comment header that says what it
fixes and why.  The script applies them with GNU `patch -p1 -F0` (no fuzz)
to scratch copies.  Nothing under `vendor/` is ever modified.

| Directory | Applies to | Applied in |
|---|---|---|
| `pnut/` | a copy of `vendor/pnut/pnut.c` (as `pnut-for-tcc.c`) | stage 5, for `pnut-exe-for-tcc` only |
| `tcc/` | `tcc-0.9.27/` unpacked from pnut's tarball, after the kit's own 8 patches (`kit/tcc-patches/0.9.27`) | stage 4 |
| `libc/` | `libc64/`, a copy of `vendor/pnut/portable_libc` | stage 4; used by every stage from 5 on |

The files are applied in name order within each directory.

## pnut (1)

- `01-heap-size.diff`: `HEAP_SIZE` goes from 786,432 to 1,048,576 words.
  x86_64 tcc needs 790,991 words.  This is used only for the pnut that
  compiles tcc (`pnut-exe-for-tcc`).  SF, `sf-pnut64` and `pnut-exe` are
  built from `pnut.c` as shipped.

## tcc-0.9.27 (4)

- `01-local_enum.diff`, `02-vla_onstack.diff`: these work around pnut
  limitations (no block-scope `enum`, no VLAs).  Both apply only under
  `PNUT_CC`, so they change `tcc-pnut` alone.
- `03-static_no_plt.diff`, `04-static_fill_got.diff`: these fix **bugs in
  tcc-0.9.27 itself**.  On x86_64, a `-static` executable calls through a
  PLT that is never filled, and its GOT is never filled either.  The
  evidence is that a gcc-built tcc-0.9.27, from the same sources and flags
  and without these two patches, builds a static hello-world that crashes.
  That binary is byte-identical to the one the pnut-built tcc makes.  With
  only one of the two patches the result still crashes.  Both apply under
  `BOOTSTRAP`, which every tcc in the chain is built with.

## portable_libc (6)

- `01-crt1-x86_64.diff`: `_start` and the `syscall` wrappers for x86_64.
  The original has only i386 code.
- `02-stdarg-x86_64.diff`: under tcc on x86_64, tcc's own register-save-area
  `va_list`.  Its helpers come from `tcc-0.9.27/lib/va_list.c`, which is
  compiled unmodified into `libtcc1.a`.
- `03-assert-h.diff`: adds `<assert.h>`, which `x86_64-gen.c` includes.
- `04-abort.diff`: adds `abort()`, which `x86_64-gen.c` calls.
- `05-puts-newline.diff`: `puts` now appends the `'\n'`.
- `06-printf-length.diff`: adds `printf`'s `l`/`ll` length modifiers
  (`%ld %lld %lu %llu %lx %llx %lo …`) and makes `%u`/`%o`/`%x` unsigned.

`05` and `06` are not needed to reach tcc.  They fix libc behaviour for
the programs that `tcc-boot2` builds.  `tests/pnut/amd64/printf.c` tests
them, and `tests/pnut/amd64/printf.out` is the expected output.

## Upstream inputs and their pins

| Input | Source | Pin |
|---|---|---|
| pnut | `vendor/pnut` submodule | commit `abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d` |
| tcc-0.9.27 source | vendored in pnut as `kit/tcc-0.9.27.tar.gz`, added by pnut commit `920cb3f`.  This is the 2017-12-17 tcc 0.9.27 release tree.  Upstream distributes it as `tcc-0.9.27.tar.bz2` from download.savannah.gnu.org/releases/tinycc/; this tarball's relation to that file is not checked here. | sha256 `db0a0bf390c746621b2dc9b8ddf9ff4eeda0c7e3e65e292de5bd8be902eb230d` |
| `tcc-0.9.27/lib/va_list.c` | inside that tarball | sha256 `3204e28b30bc7cbd4ea9520377e69a6feef11e110081bd05d1136fdcbf50c6f1` |
| kit's 8 tcc patches, `kit/config.h`, `kit/libtcc1.c`, `kit/bintools/`, `portable_libc/` | vendor/pnut at the commit above | (covered by the commit) |

The script refuses to run on a different pnut commit.  It also checks the
tarball's hash before bintools unpacks it, and it checks `va_list.c` after
unpacking.  A mismatch is a hard FAIL, not a skip.

## Changing a patch

Edit the `.diff` so that it still applies with `-F0`.  Then run
`SF_PNUT64_REPIN=1 tests/pnut/sf-pnut-amd64-check.sh`, which prints every
stage's new sha256 instead of failing on it.  Copy the values into the pins
at the top of the script and into REPRODUCIBLE.md ("Past M2-Planet on amd64
alone").  After that, `./verify.sh` step 9 should still show the gcc-seeded
tcc reaching the same `tcc-boot2`.
