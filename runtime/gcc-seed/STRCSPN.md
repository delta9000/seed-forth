# Byte-string rejection span

The original GCC 4.0.4 `libcpp/pch.c` macro-restoration loop calls
`ustrcspn(data->defns[i], "( \n")` to find a saved macro's name boundary.
Its `libcpp/internal.h` inline wrapper calls the standard `strcspn`.
The measured original-program link exposed this unresolved symbol; the
original libiberty sources do not supply a `strcspn.c` fallback.

The separate, original `strcspn.c` implements the byte-string operation, with
its `size_t strcspn(const char *, const char *)` declaration in `string.h`.
It returns the length of the maximal initial segment containing no byte from
`reject`. Both arguments are NUL-terminated strings. The terminator ends a
string and is not a reject-set member. Empty input returns zero; an empty
reject set returns the input length. Duplicate reject bytes and their order
have no effect. Comparisons use unsigned bytes, including values 128–255.

The implementation reads one byte at a time, stops at a matching byte or the
input terminator, and never scans the reject set past its first terminator.
It allocates no memory and uses constant auxiliary storage. Worst-case work
is the product of the input and reject lengths. It changes neither argument
nor errno. Null pointers or missing terminators are not valid input; this is
not a length-limited buffer API. The target remains the bounded,
single-threaded Linux AMD64 LP64 runtime. The existing `string.c`, seed,
Forth compiler and linker remain unchanged. The direct driver discovers the
new runtime source and builds it with the Forth compiler automatically.

Run `python3 tests/gcc/strcspn-check.py`. The focused gate constructs an
independent Python byte-set oracle and binary vectors, then checks a static
Forth-only production executable. Every pair of byte values is covered,
including NUL and high-bit bytes, with additional empty, duplicate, reordered,
long/repeated, randomized, early-stop, aliased-argument and original-consumer
delimiter cases.
Readable pages surrounded by inaccessible pages check both input and reject
strings at their first and last readable bytes in all four edge combinations.
Only valid, terminated strings are passed to any implementation.

Separate host GCC `-O0` and `-O2` runs check host libc, host-compiled runtime
source, and host callers of the Forth-built function object. Strict public
header compilation, exact `size_t` function pointers and return expressions,
and eight-byte unsigned width checks cover the LP64 interface. Under the
one-GiB process cap, the gate does not allocate strings longer than `2^32`;
it makes no claim to have dynamically observed such a span. Each result must
match the Python oracle exactly, with unchanged input bytes and errno.

The runner keeps vectors, expected output, objects, executables, command
results, hashes and a JSON report in a fresh `build-out/strcspn-*` directory.
Processes run serially with a one-GiB address-space limit. Host artifacts
never enter the Forth production executable. This is evidence for the narrow
runtime contract only, not successful linking or rebuilding of original GCC.
