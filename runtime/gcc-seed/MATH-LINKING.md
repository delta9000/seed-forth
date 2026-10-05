# Explicit bootstrap math archive

The direct driver accepts the exact `-lm` spelling in link mode. At that input
position it compiles the snapshotted `math.c` with Forth, writes `math.o`, and
uses the Forth archive writer to create a real `libm.a`. Archive selection is
ordered and lazy: place `-lm` after the objects that need `exp` or `log`.
Repeated `-lm` reuses the private archive but rescans it at each input position.
No host library, archive writer, object file or search path supplies production
code. General `-lNAME`, separated `-l m`, and `-L` options remain unsupported.
Compile-only and preprocess-only invocations reject `-lm` explicitly.

`math.c` remains part of the compiler snapshot and its content-derived identity,
but it is excluded from the implicit runtime object's cache and libc archive.
Omitting `-lm` therefore leaves exp/log references unresolved. Explicit `-lm`
also applies under `-nostdlib`; it does not implicitly add startup, errno or
syscall support. The caller must supply any such dependencies as explicit
objects. The generated math archive exists only in the private per-invocation
workspace; output publication retains the driver's atomic replacement checks.

Run `python3 tests/gcc/math-check.py` for Forth numerical production, then the
separate oracle command it prints. Run `python3 tests/gcc/math-link-check.py`
for archive membership, ordering, negative-option, missing-source, nostdlib
and existing-output preservation checks. Host `ar` in that fixture only inspects
Forth-produced archive bytes. MATH.md retains the numerical contract, observed
near-integer disagreements and the original GCC optional-split reachability
boundary. This bounded exp/log archive is not a complete or correctly rounded
libm.
