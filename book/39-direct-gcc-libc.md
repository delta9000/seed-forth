# 39. A bounded C runtime from source

## Goal

Build real memory, string, and allocation functions from C source using the
Forth compiler, then execute them in an image linked by Forth. The result is
a small Linux AMD64 runtime for the direct GCC reconstruction route. It is
not a complete libc, and passing its tests does not yet mean GCC is rebuilt.

**Source coverage:** the original project C implementations and public
headers in [`runtime/gcc-seed`](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/runtime/gcc-seed/README.md). These nested C
files are ordinary checked-in source, not root-level Forth tangler outputs.
This chapter explains their contracts without duplicating canonical source.

**Concepts carried in:** relocatable objects from chapter 35, the System V
integer/pointer calling convention from chapter 36, the linker from chapter
37, and the Linux syscall and errno boundaries from chapter 38.

**Concepts introduced:** an explicit LP64 header surface, allocation metadata
owned by each mapping, preserved state on failure, and separate production
reconstruction and independent host-oracle evidence.

**Deferred:** stdio, process environments, locale, floating conversion, time,
signals, threads, shared libraries, and the remaining original GCC consumers.

## 1. Declare the machine we actually build

The target has eight-bit bytes, signed plain `char`, two-byte `short`,
four-byte `int`, and eight-byte `long` and pointers. `size_t` is an unsigned
long; `ptrdiff_t` is a signed long. The small `stddef.h` and `limits.h`
headers state those choices instead of borrowing the build machine's
headers. The production test checks the storage widths and signedness.

`string.h` declares the implemented byte and string operations. `stdlib.h`
declares allocation, and `errno.h` exposes the errno location through a
macro. An unimplemented interface is absent. Adding declarations for
nonexistent functions would merely delay a missing-runtime error until
linking; a successful stub would be worse because it would hide the gap.

The implementations are original seed-forth source under the repository
[MIT license](https://github.com/delta9000/seed-forth/blob/bootstrap/forth-direct-gcc/LICENSE). They do not import or adapt an upstream libc.
Their small byte loops make the memory boundaries visible and avoid an
unearned dependency on optimized assembler, word-at-a-time overreads, or
compiler-generated support routines.

## 2. Give every allocation its own bookkeeping

The allocator asks Linux `mmap` for one mapping per allocation. The raw
syscall bridge from chapter 38 carries all six kernel arguments, including
the mapping flags, file descriptor, and offset. Anonymous private mappings
need no process-wide allocator list, bump pointer, or free-list state.

Two `size_t` fields precede the returned pointer: the mapping extent and the
requested payload size. Together they occupy sixteen bytes on this target.
Linux returns a page-aligned mapping, so the pointer after the header is
still sixteen-byte aligned. The extent retains the original length needed
by `munmap`; the requested size tells `realloc` how much live payload to copy.

Before adding metadata, `malloc` rejects requests larger than `LONG_MAX`
minus the header. This protects the addition and bounds pointer differences.
A zero request uses a minimal nonzero payload but still owns a real mapping.
`free(NULL)` does nothing; ordinary `free` reads the header and unmaps it.
The raw syscall bridge leaves errno alone, so freeing preserves errno.

The kernel rounds mapping lengths to pages. A separate mapping for every
small object is expensive, but it gives us a clear first allocator with real
deallocation. Optimization can follow measured need without changing the
public interface or hiding allocation failures.

## 3. Failure is part of the interface

`calloc` checks multiplication before allocating. It compares the element
size with the largest `size_t` divided by the nonzero count; a failing check
sets `ENOMEM`. A successful allocation is explicitly cleared through
`memset`, so the zeroing contract is visible in the C source.

`realloc(NULL, n)` delegates to `malloc`. For a nonnull pointer and zero
size, this runtime chooses to free the object and return `NULL`. Shrinking
can keep the existing mapping. Growing first allocates a replacement, then
copies the old requested payload, then releases the old object.

The order matters. If replacement allocation fails, the old object and its
contents still belong to the caller. Tests check this both when the size
guard rejects the request and when an enormous otherwise valid request
reaches `mmap` and the kernel rejects it. Size overflow and kernel failure
are distinct paths with the same required preservation behavior.

The errno storage is a single four-byte BSS object emitted by Forth. Its
address is returned by `__errno_location`, and the C macro dereferences
that pointer. This is explicitly a single-threaded bootstrap contract.
It must not be described as thread-local storage or a full libc ABI.

## 4. Copy bytes without changing their meaning

`memcpy` copies forward and requires non-overlapping objects. `memmove`
chooses a safe direction from the integer ordering of the addresses, an
explicit AMD64 assumption. Every counted function stops at its count;
string functions stop at the first terminating zero where their interface
requires it. Zero-count operations do not dereference their arguments.

Comparisons use unsigned bytes, so a byte with its high bit set sorts above
an ordinary low byte even though plain `char` is signed. `strncpy` pads a
short source with zero bytes and does not append a terminator when the count
is exhausted. `strncat` always terminates the destination. `strchr` and
`strrchr` can find the terminating zero itself.

The initial string surface includes duplication, search, comparison,
copying, and concatenation. `strdup` composes `strlen`, `malloc`, and
`memcpy`; allocation failure propagates as `NULL`. These are real functions
for original GCC and libiberty consumers, not successful placeholder bodies.

## 5. Keep two kinds of proof separate

The production check compiles `memory.c`, `string.c`, `alloc.c`, and its C
test translation unit using `sysv-object-compile.sh`. That script runs the
Forth compiler and preprocessor. Forth also emits the syscall bridge, errno
object, and entry stub. The Forth linker joins the seven objects and Linux
executes the resulting static image. No host C compiler, assembler, linker,
or libc contributes an object to this executable.

The test covers memory lengths and both overlap directions, high-byte
comparisons, string termination and padding, alignment, allocator overflow,
kernel allocation failure, errno preservation, and resizing. A `mincore`
probe after `free` checks that the mapping is actually gone. It also maps
two pages and protects the second page from access. Strings and buffers end
at the first page boundary, so reading beyond the allowed end faults instead
of silently succeeding inside a larger test buffer.

An optional differential oracle builds separately named copies of the C
functions with Forth. A host-compiled test harness calls both those copies
and the host libc across many lengths, offsets, byte values, and strings.
The harness runs at two optimization levels. This checks interoperability
and behavior against an independent implementation; its host linker and
libc are test tools, and its executable is not production bootstrap output.

## Try it

Run the production reconstruction from the repository root:

```sh
python3 tests/gcc/runtime-check.py
```

The check reports a pass, retained artifact directory, and SHA-256 values.
Run the optional host oracle separately when host GCC is available:

```sh
python3 tests/gcc/runtime-oracle-check.py
```

Both checks passed on 2026-10-03. The latter prints an explicit oracle-only
label. A missing host GCC skips that optional check; it is not a prerequisite
for producing or executing the runtime reconstruction.

## Exercises

- **★** Explain why the mapping extent and requested size are separate fields
- **★★** Extend the production guard-page test to a longer string search
- **★★** Show why multiplying the `calloc` arguments before checking cannot work
- **★★★** Design a page-sharing allocator that preserves these failure contracts

## Takeaways

- The runtime's public headers describe its real target and implemented surface
- Per-allocation mappings give us actual allocation and release with explicit failure semantics
- Production reconstruction and independent host-libc comparison prove different claims

Next, use original GCC generator and libiberty translation units to determine
the next missing compiler or runtime contract.
