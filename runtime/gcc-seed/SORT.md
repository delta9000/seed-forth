# Source-built qsort

GCC 4.0.4's original `gcc/genmodes.c`, in `calc_wider_mode`, calls `qsort`
on an array of `struct mode_data *`, using `cmp_modes` to order the pointed-to
modes. The pinned libiberty source does not supply `qsort.c`. This concrete
consumer motivated the `qsort` declaration in `include/stdlib.h`. The
implementation in `qsort.c` is musl 1.1.24's `src/stdlib/qsort.c` (sha256
`a520c44672ba94435de6d0cbc926786f3ff5fdda8ef35a361108dec2ea6875f4`, MIT,
copyright 2011 Valentin Ochs; its notice is kept in the file). The direct
driver compiles it with the project's Forth C compiler, just as it compiles
the other runtime C sources. No host libc algorithm or object is used as a
production input.

## Why musl's algorithm

ISO C leaves the order of elements that compare equal unspecified, and GCC
4.0.4 sorts with comparators that tie. `simplify_plus_minus` in
`simplify-rtx.c`, for example, sorts the operands of an address by
`commutative_operand_precedence`, which ranks every register the same. The
order `qsort` leaves them in becomes the order cc1 writes them, as in
`-112(%rbp,%rdx)` versus `-112(%rdx,%rbp)`. Both are correct, but they are
different bytes.

The runtime first had an original heapsort, which exchanges two equal
elements where musl's smoothsort leaves them. GCC 4.0.4 compiled by a cc1 on
that runtime differed from GCC compiled by GCC on musl in seven executables,
all by such equivalent choices. Relinking that cc1 with this file, and
changing nothing else, made the two identical, so stage D of
[gcc-direct](../../gcc-direct/README.md) now requires stage 2 to equal stages
3 and 4.

## Algorithm and contract

Smoothsort is an adaptive heapsort over a sequence of Leonardo heaps, with
O(n log n) worst-case and close to O(n) comparisons on nearly sorted input.
It uses constant auxiliary space: an array of Leonardo numbers and a
256-byte buffer on the stack, through which `cycle` rotates elements of any
width with `memcpy` (from `memory.c`). There is no allocation, no global
state and no unbounded recursion, so a comparator may call qsort on another
array. Elements keep their complete byte representations and need no
alignment beyond what the caller's comparator requires. Only the sign of the
comparator result matters. A sorted run, including a run of equal keys, is
left in place; in general equal keys need not keep their input order.

One adaptation is marked in the source. musl takes `a_ctz_l` (count trailing
zeros, `bsf` on x86_64) from its internal `atomic.h`. A portable loop with
the same result for every nonzero argument replaces it. Smoothsort never
asks about zero (an instrumented host build that rejects zero sorted about
10 million keys, with heavy ties, without hitting it); the loop still
returns the word width for zero instead of looping forever.

As with the C interface, the caller supplies an array large enough for count
elements of the requested size and a consistent ordering function. Invalid
pointers, overflowing object extents, a comparator that changes the elements
being ordered, or inconsistent ordering are not supported. Zero and one
element return without calling the comparator, and so does a zero element
size.

`sort.c` remains original seed-forth code and now holds only `bsearch`.

## Verification and provenance

Run `python3 tests/gcc/sort-check.py`. It snapshots and hashes the compiler,
headers, `qsort.c`, `sort.c`, `memory.c` and test inputs before compiling, checks that the
snapshot remains unchanged, and retains all source and target artifacts in
the printed build directory. The source, client, syscall/start objects and
ELF executable are built through Forth only. Python copies inputs, invokes
commands and records hashes; it does not generate qsort object bytes.

The production client checks every permutation through eight elements,
zero/one counts, up to 4096 elements, sorted/reverse/equal/organ-pipe/
alternating/random/sawtooth patterns, duplicates, full-range comparator
results, byte records of sizes 1 through 33 and 257 at offsets 1 through 8,
unchanged surrounding bytes, complete element permutations, mode pointer
records, three nested callback levels, a comparison-count bound, runs of
2 through 64 equal keys staying in input order, and Linux guard pages at both
ends of the accessible region. Byte records are compared
with an independent selection-sort reference; integer and pointer cases
independently count identities instead of assuming stable equal-key order.

Run `python3 tests/gcc/sort-oracle-check.py BUILD_DIRECTORY` using the printed
production directory. This separate optional check namespaces and Forth-builds
the exact frozen qsort source, then links it to host GCC clients at -O0 and
-O2. Independent host libc qsort supplies expected byte order and mode-key
order; all record bytes and pointer identities are checked. For keys that tie
but carry distinct payloads, the Forth-compiled and host-compiled objects must
leave every element in the same place. The same source
also runs as a host-compiled implementation with undefined-behavior checking.
Host GCC, host linker, host headers and host libc are used only by this oracle,
never as evidence of production closure. Passing these tests establishes this
runtime interface, not completion of the original GCC generator bootstrap.
