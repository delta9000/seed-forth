# Integer input measured from original Flex

Flex2.5.11 misc.c uses exactly plain %d, %o and %x through sscanf; scanopt.c
uses atoi for a decimal column count. This stage implements those conversions
with ASCII whitespace, optional signs, hexadecimal prefixes, real variadic
destination pointers and assignment counts. The format walker also handles
ordinary literals, percent literals, whitespace and repeated supported fields.
Percent conversions skip leading input whitespace through the same path as
numeric conversions; ordinary literal characters still match the next input
byte exactly. scanf-percent-check.py covers this distinction, EOF, mismatch,
and assignment counts with independent host C90 O0/O2 comparisons.
It does not advertise width, suppression, length modifiers, other conversion
letters or floating input. `%c` and `fscanf` were added later for GCC's
driver; see [DRIVER-RUNTIME.md](DRIVER-RUNTIME.md#fscanf). Unsupported formats fail with EINVAL before
consuming that field's argument; prior completed assignments remain counted.

Empty input before the first assignment returns EOF; a nonmatching field
returns the number already assigned. An incomplete 0x prefix is a matching
failure and leaves its destination unchanged. The host libc accepts that
incomplete prefix as zero, so this explicit choice is checked only for the
production runtime. Valid complete fields match the independent host oracle.

Representable signed decimal and unsigned octal/hexadecimal fields have exact
32-bit results. Negative unsigned fields use unsigned modular negation. An
unrepresentable magnitude sets ERANGE and leaves that field unassigned; this is
an explicit extension where the C scanf contract otherwise leaves behavior
undefined. atoi similarly saturates to INT_MIN/MAX with ERANGE on overflow.
No-conversion atoi returns zero. Successful and ordinary nonmatching operations
preserve errno; the host resets errno on an empty scanf input, so that detail
is tested as a target contract and excluded from the shared oracle comparison.

integer-input-check.py calculates 203 scanf and 49 atoi expectations, checks
assignment/mismatch/EOF cases, eight spilled pointer arguments, unsupported
formats, overflow and a protected-page input boundary. Separate host C90 O0/O2
builds compare representable results. The production compiler, runtime and
linker remain Forth-built; host execution is only an independent oracle.
