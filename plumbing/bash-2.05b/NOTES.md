# bash 2.05b recipe (work in progress)

Builds bash 2.05b with seed-cc and the stage-1 GNU make, with no shell.
`Makefile`, `builtins.mk` and `common.mk` come from live-bootstrap's
`steps/bash-2.05b/mk/` (GPL-3.0-or-later; their SPDX headers are kept). They
are adapted here:

- All configure answers live in `config.h`, so no recipe line needs a shell.
  live-bootstrap's mes-libc answers are replaced by honest ones for
  runtime/gcc-seed: `HAVE_SYS_WAIT_H`, `HAVE_VPRINTF`, `PROTOTYPES`, and
  `USE_VARARGS`; the libc functions bash would otherwise replace; and
  `BUILDVERSION` as a number. The mes `endpwent(x)=0` workaround is gone.
- The `complete` builtin is dropped: it needs readline's programmable
  completion, which is not built.
- `lib/sh/strftime.c`, `strtoimax.c` and `strtoumax.c` are not built, because
  the runtime provides those functions.
- `lib/malloc/alloca.c` supplies alloca, since the compiler has no builtin.
- Objects come before archives in the link, and the archives are repeated,
  because they depend on each other and the linker scans each archive once.
- live-bootstrap's `missing-defines.patch` (an `#ifdef` guard in
  `execute_cmd.c`) is applied.

Verified (2026-10-06): the resulting bash runs sed 4.0.9's autoconf configure
and produces a `config.h` byte-identical to the one host bash produces.

Open before this becomes a pristine-source stage:

1. The `y.tab.c` rule runs `$(YACC)`, which must be the Forth-built oyacc
   produced inside the chain (today it comes from the Python lexer recipe).
2. `lib/sh/snprintf.c` applies `++` to a `double` three times. The compiler
   rejects that (error 232) and must be fixed; until then the scratch build
   rewrites those lines as `i = i + 1`.
