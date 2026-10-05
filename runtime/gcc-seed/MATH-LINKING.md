# Explicit bootstrap math archive

The direct driver accepts `-lm` and `-l m` in link mode. It first searches
all explicit `-L DIR` / `-LDIR` directories in their supplied order for `libm.a`.
A found static archive takes precedence over the builtin math implementation.
If none is found, at that input position it compiles the snapshotted `math.c`
with Forth, writes `math.o`, and uses the Forth archive writer to create a real `libm.a`. Archive selection is
ordered and lazy: place `-lm` after the objects that need `exp` or `log`.
Repeated `-lm` reuses the private archive but rescans it at each input position.
Rescans are confined to the current archive; later inputs do not cause earlier
archives to be revisited. General `-lNAME` / `-l NAME` searches only explicit
`-L` directories for static `libNAME.a` files, with no host system or environment
search paths. Compile-only and preprocess-only invocations accept and ignore
`-L` and `-l`, including `-lm`, without lookup or building math.

`math.c` remains part of the compiler snapshot and its content-derived identity,
but it is excluded from the implicit runtime object's cache and libc archive.
Omitting `-lm` therefore leaves exp/log references unresolved. Explicit `-lm`
also applies under `-nostdlib`; it does not implicitly add startup, errno or
syscall support. The caller must supply any such dependencies as explicit
objects. The generated math archive exists only in the private per-invocation
workspace; output publication retains the driver's atomic replacement checks.

Run `python3 tests/gcc/math-check.py` for Forth numerical production, then the
separate oracle command it prints. Run `python3 tests/gcc/math-link-check.py`
for archive membership, ordering, missing-library, missing-source, nostdlib
and existing-output preservation checks. Host `ar` in that fixture only inspects
Forth-produced archive bytes. MATH.md retains the numerical contract, observed
near-integer disagreements and the original GCC optional-split reachability
boundary. This bounded exp/log archive is not a complete or correctly rounded
libm.
