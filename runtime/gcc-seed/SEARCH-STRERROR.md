# Source-built bsearch and strerror

## Why they exist

The first linked Forth-built `cc1` crashed on every variable-length array.
GCC lowers a VLA's stack restore through a try/finally, and
`tree-eh.c:find_goto_replacement` looks up its goto queue with `bsearch`.
This runtime implemented neither `bsearch` nor `strerror`, and its headers
declare only implemented interfaces, so the call had no visible prototype.
libiberty supplied a `bsearch` object at link time, so linking succeeded.
Under C90, however, an undeclared function returns `int`: the 64-bit result
was truncated to 32 bits and sign-extended, and `cc1` dereferenced
`0xfffffffff7fd47e0` instead of `0x00007ffff7fd47e0`.

A scan of all 220 original cc1 translation units for implicit function
declarations against these headers found exactly two: `bsearch` in
`tree-eh.c` and `strerror` in `tree-dump.c`. Both return pointers. The cc1
census now repeats that scan (`census/implicit-decls.json`), so a new
undeclared pointer-returning call cannot hide behind a successful link.

## Contracts

`bsearch` (in `sort.c`, beside `qsort`) searches an ascending array of
`count` elements of `size` bytes. It keeps a half-open interval of indices
that may still match and computes the midpoint as `low + (high - low) / 2`,
so index arithmetic cannot overflow. The comparator receives the key first,
as ISO C specifies; only the sign of its result matters. It returns some
matching element, or a null pointer when none matches or `count` is zero.

`strerror` (in `strerror.c`, shared with the [process API](PROCESS-API.md),
which also needs it) returns the Linux wording for each error number that
`<errno.h>` declares (now every Linux value; see [ERRNO.md](ERRNO.md)), and
"Success" for zero; it preserves `errno`. Any other value
produces "Unknown error N" in a single static buffer that the next such call
overwrites, as ISO C permits. The returned text must not be modified.

## Verification

`tests/gcc/search-error-check.py` compiles `tests/gcc/search-error.c` with
the production Forth driver and runtime, and again with host GCC and host
libc as an oracle. The outputs must be identical: element sizes 1, 3, 8 and
24 bytes, array lengths 0 through 41, every present and absent key, extreme
comparator results, and every declared error number plus unknown values.
