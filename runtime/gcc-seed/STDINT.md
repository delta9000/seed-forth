# Exact-width integer types

Original binutils 2.30 `libiberty/obstack.c` includes `<stdint.h>`
unconditionally, and bfd uses its types. `include/stdint.h` supplies the C99
header for Linux AMD64 LP64 without `long long`: every 64-bit type is `long`
or `unsigned long`, which is the same type glibc uses on this target.

## Types

- `int8_t`…`int64_t` are `signed char`, `short`, `int`, `long`; the unsigned
  forms use the matching unsigned types. The least-width types are the same.
- `int_fast8_t` is `signed char`; `int_fast16_t`, `int_fast32_t` and
  `int_fast64_t` are `long` (unsigned forms likewise), matching glibc x86-64.
  This matters for ABI and for format strings, not only for width.
- `intptr_t`, `intmax_t` are `long`; `uintptr_t`, `uintmax_t` are
  `unsigned long`.

## Macros

All `*_MIN`, `*_MAX`, `INTPTR_*`, `UINTPTR_MAX`, `INTMAX_*`, `UINTMAX_MAX`,
`PTRDIFF_MIN`/`PTRDIFF_MAX`, `SIZE_MAX`, `SIG_ATOMIC_*` (`int`), `WCHAR_*`
(`int`), and `WINT_*` (`unsigned int`) limits are defined with the type and
value of the promoted corresponding type, and all are usable in `#if`.
`INTn_C`, `UINTn_C`, `INTMAX_C`, and `UINTMAX_C` append nothing, `U`, `L`, or
`UL` to the literal, as glibc does.

`inttypes.h` now includes `stdint.h` (it previously declared only
`intptr_t`/`uintptr_t`, identically). Its `PRI*`/`SCN*` format macros and
`imaxabs`/`strtoimax` family are not supplied.

## Focused gate

Run `python3 tests/gcc/stdint-check.py`; it is registered in
`tests/gcc/check.sh`. The Forth-built program prints the size, signedness,
value and bit pattern of every type and macro above, and evaluates the limits
in `#if`. Its output must equal, byte for byte, the same program built by
host GCC at `-O0` and `-O2` with host glibc headers. Host GCC also compiles
the program against the runtime headers alone, where pointer initializers
such as `int_fast16_t *p = (long *)0` fail under `-Werror` unless each typedef
is exactly the expected C type. When the pinned binutils source is present,
the gate also compiles unchanged `libiberty/obstack.c`; this makes no link claim.
