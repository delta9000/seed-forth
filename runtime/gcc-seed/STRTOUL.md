# Source-built unsigned conversion

Original oyacc 6.6 `reader.c` calls `strtoul` for octal/hexadecimal character
escapes and decimal token numbers. The implementation in `strtoul.c` is
original project source under the repository license and is compiled by the
Forth C compiler. Its declaration is in the bounded `stdlib.h` interface.

This is an LP64, fixed ASCII C-locale contract. Bases 2 through 36 are
accepted; base zero chooses decimal, leading-zero octal, or a hexadecimal
prefix when a hexadecimal digit follows it. Base 16 likewise accepts `0x`
only when followed by a hexadecimal digit. There is no binary-prefix
extension. Leading C whitespace and one optional sign are accepted.
The end pointer identifies the first unconsumed byte. With no conversion,
it points to the original input and errno is preserved. A null end-pointer
argument is permitted.

The result limit is `ULONG_MAX` (18446744073709551615). Overflow returns
that limit, sets `ERANGE`, and still consumes the complete valid digit
sequence. Negation is performed in unsigned arithmetic only after a
non-overflowing conversion. Invalid bases return zero, set `EINVAL`, and
leave the end pointer at the original input. Successful conversions preserve
errno. Inputs must identify readable, terminated C strings as for the normal
C library interface.

`python3 tests/gcc/strtoul-check.py` runs independently derived value/end/errno
cases over all 35 explicit bases, including both letter cases, LP64 boundaries,
negative values, continued scanning after overflow, octal/hexadecimal prefix
edges, all C whitespace, high bytes, invalid bases, and a null end pointer.
The test emits a fixture from these input cases; it never supplies production
conversion tables. The executable, parser, runtime, and linker are Forth-built.
A separately built host C90 version using host headers/libc at `-O0` and `-O2`
is an optional differential oracle. Its outputs are never bootstrap inputs.
Reports and input/output hashes are retained under a unique build directory.

## Signed conversion

`strtol`, beside `strtoul` in the same file, exists because binutils'
generated `sysinfo` parser (from `binutils/sysinfo.y`) converts numbers with
it. Both public functions use one static scanner, `seed_scan`, for base
validation, whitespace, sign, prefixes, digit accumulation, overflow tracking,
and the end pointer. The scanner selects a caller-supplied positive or negative
magnitude limit after reading the sign; the public functions handle range errors
and signed or unsigned result conversion. It shares every parsing rule above.
The signed magnitude limit is `LONG_MAX`,
or `LONG_MAX + 1` for a negative result, so `LONG_MIN` converts exactly;
overflow consumes the complete valid digit sequence and returns `LONG_MAX`
or `LONG_MIN` with `ERANGE`. `python3 tests/gcc/strtol-check.py` compares
value, end offset and errno with host libc over boundary, prefix, whitespace,
sign, base and overflow cases.
