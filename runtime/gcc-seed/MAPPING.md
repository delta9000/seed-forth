# Public private mappings on Linux AMD64

The complete original GCC 4.0.4 `gcc/config/host-linux.c` includes
`sys/mman.h` unconditionally. Its PCH hooks need `mmap`, `munmap`, `PROT_NONE`,
`PROT_READ`, `PROT_WRITE`, `MAP_PRIVATE`, both anonymous spellings, and
`MAP_FAILED`. Its fallback read loop also needs `SSIZE_MAX`. These are real
public interfaces, declared before use; no configuration answers or original
GCC sources are changed to hide an absent header.

The original consumer is pinned at GCC commit
`944765863eec87a9f37e297994fd2af960397138`, with `host-linux.c` SHA-256
`ca31293e9e9ebbdcb103008387dfc95e719f5f0abd25203901606d0ef6b7f4db`.
The existing GCC configuration belongs to its separately recorded compiler
and runtime epoch. A later successful source compile does not retroactively
change the configuration identity or claim fresh configure results.

## The bounded surface

`mapping.c` is original project source under the repository MIT license.
The implementation accepts exactly `MAP_PRIVATE` or
`MAP_PRIVATE | MAP_ANONYMOUS`, with the latter also spelled `MAP_ANON`.
Protections are exactly the four combinations of the read/write bits,
including `PROT_NONE`. Every other flag or protection bit fails with `EINVAL`
before any syscall. No shared, fixed, executable, huge-page, locked, populated,
stack, or advice interface is exposed. In particular, a requested address is
only a hint and cannot replace an existing mapping.

`off_t` is signed 64-bit `long`; negative or non-page-aligned offsets fail
with `EINVAL`. The ordinary AMD64 Linux page size is 4096 bytes. Anonymous
calls conventionally use descriptor -1 and offset zero; accepted descriptors
and aligned nonnegative offsets are passed unchanged, with anonymous
interpretation left to Linux. `size_t` is unsigned 64-bit `long`; the wrapper
forwards every length bit, including zero and very large values. Linux
validates the requested length, rounds mappings and unmaps to page boundaries,
and reports overflow or insufficient address space. The wrapper does not
add a silent maximum, truncation, copying fallback, or retry.

File mappings use real kernel private copy-on-write pages. Closing the file
descriptor does not remove the mapping. The caller owns the returned mapping
and must eventually unmap it. `munmap` can remove a page-aligned subrange;
its length need not be page-aligned. Invalid alignment or zero length is a
kernel error. The caller must never unmap unrelated storage, including an
allocator payload: allocation metadata and lifetime remain `alloc.c`'s
responsibility. The allocator's raw syscalls and ownership are unchanged.
See the upstream [Linux mmap/munmap contract](https://man7.org/linux/man-pages/man2/mmap.2.html).

## Preserve the raw boundary

The wrappers use the existing seven-argument raw bridge once: AMD64 syscall
9 for `mmap`, 11 for `munmap`. Linux raw values -4095 through -1 become errno
and the public failure sentinel. All other mapping result bits become the
returned pointer unchanged. A negative signed pointer representation outside
the kernel-error interval is not by itself a failure. Success preserves errno.
`munmap` returns the kernel status, normally zero; it does not retry errors.

The signed/unsigned and pointer casts are the documented Linux AMD64 LP64
bit-preserving ABI conversions, not a portable C implementation. The target
header defines `SSIZE_MAX` as `LONG_MAX`, consistently with the existing
`ssize_t` typedef. It does not imply an additional I/O API. The test compiles
the actual source against its public header with strict independent host
warnings and verifies constants against installed Linux UAPI headers
`linux/mman.h` and `asm/unistd.h`, whose backing header hashes are reported.

## Focused production and oracle proof

Run `python3 tests/gcc/mapping-check.py`. Production C, syscall and errno
objects, startup, and final ELF come from the unchanged Forth seed and Forth
compiler/linker. Host compilation is used only for separately labelled
oracles, including libc, independently compiled wrapper source, host callers
of Forth objects, and Forth callers of host objects at both O0 and O2.

The serial gate caps virtual address space at 1 GiB and disables core dumps
for intentionally faulting children. It checks anonymous zero-fill, file
private writes, descriptor lifetime and errors, protection faults, seven
length boundaries, partial unmap holes, and non-destructive address hints.
A sparse file has marked bytes above 4 GiB, but tests map only small windows
and never read or hash the sparse file wholesale. Fault doubles cover every
kernel errno, success pointer bit patterns, both sides of the error interval,
full-width arguments, and every unsupported flag/protection bit.

To additionally compile the complete untouched consumer, supply
`--gcc-source PATH --gcc-config PATH`, where the latter is the original
configured `build/gcc` directory. Source and configuration header hashes are
checked before and after compilation, and its command, object size and hash
are retained. This is a compile proof only: fresh genuine mmap configuration
probes, linked original PCH execution, complete cc1, and a GCC self-rebuild
remain separate work. The focused gate is registered in `tests/gcc/check.sh`.
