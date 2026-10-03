# Source-built qsort

GCC 4.0.4's original `gcc/genmodes.c`, in `calc_wider_mode`, calls `qsort`
on an array of `struct mode_data *`, using `cmp_modes` to order the pointed-to
modes. The pinned libiberty source does not supply `qsort.c`. This concrete
consumer motivates the one new declaration in `include/stdlib.h` and the
original MIT implementation in `sort.c`. No host libc algorithm or object is
used as a production input. The direct driver compiles this runtime source
with the project's Forth C compiler, just as it compiles the other runtime C
sources.

## Algorithm and contract

The sort constructs a maximum heap from its last parent back to its root.
It then exchanges the root with the last unsorted element and restores the
remaining heap. Each sift chooses the larger child, stops when the parent
is at least that child, or exchanges them and descends. The sorted suffix
therefore grows from right to left. Heap construction is linear; the complete
sort uses O(n log n) comparisons and O(size * n log n) byte operations, with
constant auxiliary space. There is no allocation, runtime global state, or
algorithm recursion. A comparator may call qsort on another array, including
recursively through another comparator.

Every exchange uses unsigned-character lvalues. The implementation preserves
entire element representations, supports odd sizes and byte-aligned records,
and imposes no alignment beyond that required by the caller's comparator.
Callbacks receive actual element addresses and use the System V callback ABI.
Only the sign of the comparator result matters, including INT_MIN/INT_MAX.
Equal keys need not retain their input order: this is not a stable sort.

As with the C interface, the caller supplies an array large enough for count
elements of the requested size and a consistent ordering function. Invalid
pointers, overflowing/infeasible object extents, a comparator that changes
the elements being ordered, or inconsistent ordering are not supported
contracts. Zero and one element return without accessing elements or calling
the comparator. A zero element size also returns as an implementation choice;
tests do not promote questionable zero-size or null-pointer calls into ISO C
requirements. Valid one-past pointers with zero count are tested. Testing
root < count / 2 before forming its child prevents heap-index overflow;
element-offset multiplication fits for a valid supplied array.

## Verification and provenance

Run `python3 tests/gcc/sort-check.py`. It snapshots and hashes the compiler,
headers, qsort source and test inputs before compiling, checks that the
snapshot remains unchanged, and retains all source and target artifacts in
the printed build directory. The source, client, syscall/start objects and
ELF executable are built through Forth only. Python copies inputs, invokes
commands and records hashes; it does not generate qsort object bytes.

The production client checks every permutation through eight elements,
zero/one counts, up to 4096 elements, sorted/reverse/equal/organ-pipe/
alternating/random/sawtooth patterns, duplicates, full-range comparator
results, byte records of sizes 1 through 33 and 257 at offsets 1 through 8,
unchanged surrounding bytes, complete element permutations, mode pointer
records, three nested callback levels, a comparison-count bound, and Linux
guard pages at both ends of the accessible region. Byte records are compared
with an independent selection-sort reference; integer and pointer cases
independently count identities instead of assuming stable equal-key order.

Run `python3 tests/gcc/sort-oracle-check.py BUILD_DIRECTORY` using the printed
production directory. This separate optional check namespaces and Forth-builds
the exact frozen qsort source, then links it to host GCC clients at -O0 and
-O2. Independent host libc qsort supplies expected byte order and mode-key
order; all record bytes and pointer identities are checked. The same source
also runs as a host-compiled implementation with undefined-behavior checking.
Host GCC, host linker, host headers and host libc are used only by this oracle,
never as evidence of production closure. Passing these tests establishes this
runtime interface, not completion of the original GCC generator bootstrap.
