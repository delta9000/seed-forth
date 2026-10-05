# Target floating format metadata

The original Autoconf ANSI-header probe includes float.h. This header describes
the compiler's chosen AMD64 layouts: four-byte binary32, eight-byte binary64,
and sixteen-byte storage containing x87 extended80 with six padding bytes.
The representation contract follows the AMD64 ABI figure3.1 and section3.1.2:
https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf

The C90 precision/exponent/limit macros describe those formats. FLT_ROUNDS is
-1 (indeterminable); the bounded runtime supplies no floating-environment
query/control API. This value follows the language definition, not a guessed
current rounding mode: https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf
section5.2.4.2.2. No C99/C11 metadata extension is promised in this stage.

The header does not enable float or long-double expression support. All six
typed FLT/LDBL limit expressions still fail the production compiler's value
gate when used. The three supported binary64 constants execute and have exact
independently expected bits. float-header-check.py also verifies all integer
format fields and actual struct size/alignment, then checks all nine numeric
limit macros with separately host-built target-header and host-header units
at O0/O2. Passing this header probe records only the measured check; it does
not assert complete ISO compiler/library conformance.
