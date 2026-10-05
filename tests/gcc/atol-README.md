# Measured GCC4 `read-rtl` prerequisite: `atol`

The original GCC4 `gcc/read-rtl.c:1327` calls `atol(tmp_char)` when reading
the `w` RTL field on a host where `HOST_BITS_PER_WIDE_INT` equals
`HOST_BITS_PER_LONG`, after the integer-width branch has been excluded.
The direct target is Linux AMD64 LP64: `int` is 32 bits and `long` is 64 bits.
Using `atoi`, or an implicit C90 `int` declaration, would truncate valid wide
constants. The runtime therefore supplies the C90 declaration
`long atol(const char *text)` and a source implementation of that interface.
No upstream GCC source is altered for this prerequisite.

## Contract and arithmetic

The implementation recognizes the runtime's fixed ASCII C locale: six ASCII
whitespace characters, an optional single sign, and consecutive decimal digits.
It returns zero when there are no digits and stops at the first nondigit or NUL.
Successful and no-conversion calls preserve `errno`. High-bit bytes are passed
to `isspace` as `unsigned char` and are not whitespace in this locale.

`unsigned long` accumulation uses a sign-dependent bound of `LONG_MAX` or
`LONG_MAX + 1UL`. Before each multiply-and-add, quotient/remainder checks prove
that the new magnitude fits the bound. The exact negative bound returns
`LONG_MIN` directly, so neither signed multiplication overflow, an out-of-range
unsigned-to-signed conversion, nor negation of `LONG_MIN` is needed.

ISO C leaves `atol` overflow undefined. This implementation deliberately uses
the same extension as the existing bounded `atoi`: saturation to `LONG_MIN` or
`LONG_MAX` with `errno = ERANGE`. The overflow flag remains set while consuming
remaining digits. Host libc overflow is never an oracle for this extension.
Null pointers and strings without an accessible terminating boundary remain
outside the interface contract.

## Reproduction

Run from the repository root:

```
python3 tests/gcc/atol-check.py
```

The script requires Python 3, the seed executable matching `000-seed.hex0`, and
host GCC for independent test oracles. It retains a JSON report, exact commands,
generated headers, expected results, observed results, objects, and executables
under a fresh `build-out/atol-check-*` directory. Only test artifacts use GCC or
host libc. Production preprocessing, compilation, runtime-object construction,
archive selection, and linking are performed by Forth. The production ELF check
rejects `PT_INTERP` and `PT_DYNAMIC` segments.

The deterministic suite has 954 inputs: 936 defined inputs and 18 overflow
extension inputs. Coverage includes exact signed endpoints and adjacent values,
decimal cutoffs, values wider than 32 bits and 53-bit floating precision, 180
seeded random 64-bit values, leading zeros, every ASCII whitespace character,
all nonzero ASCII controls, every high byte, signs without digits, trailing
text, embedded NULs, decimal-only prefix behavior, and 4095-byte strings.
Every input runs with both zero and `EDOM` preset in `errno`, on ordinary
storage and at both edges of a writable page surrounded by `PROT_NONE` pages.
At the right edge the terminating NUL is the final readable byte.

Expected numeric results come from independent Python integer arithmetic.
Host libc `atol` runs only the 936 defined inputs at GCC `-O0` and `-O2`.
The implementation is also compiled as a separately named C90 function by
host GCC at both optimization levels and compared on every input. A separately
named Forth-compiled implementation object is linked with each host-built
fixture to verify its calling convention. Those test-only renamed objects do
not replace any production symbol or runtime file. All host compilations use
`-pedantic -Wall -Wextra -Werror -fno-builtin`; long test strings use byte-array
initializers rather than suppressing the C90 string-length diagnostic.

## Candidate and limits

The production change consists of `runtime/gcc-seed/atol.c` and the single
prototype in `runtime/gcc-seed/include/stdlib.h`. The accepted compiler/runtime
base identity is
`c805ff20443e5bbf607979c3156c1328005053d09a78fcf4db3f4c8faf898cae`.
Adding those two changes yields
`00f98d45ec2f3c8595b91a98e108b89e6397e1351a4e04d791d06c1bd2eb0450`.
All existing compiler files and other runtime files match the accepted base.

The focused suite passed on this exact candidate. The original `read-rtl.c`
translation unit already compiles in the GCC4 consumer work. Full generator
link/execution against the original i386 machine description is a separate
integration check, initially blocked on the independently reviewed RTL
constant-expression prerequisite. These focused tests do not claim a full
GCC bootstrap or independent review acceptance.
