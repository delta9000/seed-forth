# Source-built allocation and byte operations

A realloc call can fail after receiving a perfectly valid old pointer. Which
bytes and ownership must survive that failure?

Follow one allocation from request through reuse, then ask how the same runtime
copies, searches, maps and terminates. These source-built services will run
inside the generators and the first GCC compiler.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G06 supplies raw kernel results and public errno translation. size_t counts
bytes and is unsigned eight-byte LP64 storage. A requested payload is separate
from allocator metadata, mapping extent and page rounding. For the paper states,
assume valid live allocations, readable/writable spans and nonoverflowing object
extents.

## Keep a header outside the requested object

Each allocation has a two-word header: extent and requested size. Returning
header+1 leaves a sixteen-byte-aligned payload after the sixteen-byte header.
The requested size records how many user bytes may be copied later; the extent
identifies the owned allocation storage. Neither includes a claim that every
page-rounded byte is part of the C object.

For request 17, the small allocator chooses capacity 32 and stride 48 including
the header. A 65,536-byte slab is divided into whole strides; leftover bytes do
not become another slot. Freed small blocks are chained through their payload
and reused, so the old payload contents are not promised to persist after free.

There are eight classes from capacity 16 through 2048. A zero request obtains a
nonzero backing slot while retaining requested size zero. Large allocations map
payload plus header and return that mapping to Linux on free. Small slabs stay
until process exit: repeated free is reuse, not slab reclamation.

Sources: [headers, slabs and
mappings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L8-L103).

## Let failure leave the old owner alive

Supply an allocation requested at 17 bytes with a recognizable prefix. Shrinking
to 12 updates requested size and returns the same pointer. Its backing extent
need not shrink. Growing to 40 allocates a replacement first; if allocation
fails, realloc returns NULL and the old allocation remains live with its old
bytes and size.

Only after replacement succeeds does it copy the old requested byte count and
free the old block. Assigning realloc’s result directly over the only old
pointer would lose access on failure; the runtime cannot repair that caller
mistake. A NULL pointer delegates to malloc; zero new size frees a non-NULL old
pointer and returns NULL.

calloc checks size > SIZE_MAX/count before multiplication when count is nonzero.
Checking only the wrapped product would accept an oversized request. It then
allocates and explicitly clears the requested total, including recycled small
storage. A fresh mapping’s zero-fill property alone cannot implement calloc over
reused slots.

Sources: [calloc and realloc failure
preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L105-L148).

## Copy in the direction that preserves unread bytes

memcpy copies forward and requires the ordinary nonoverlap contract. memmove
chooses a direction using the documented Linux AMD64 integer-address ordering.
For supplied bytes ABCDE and a four-byte move from offset zero to offset one, it
copies backward: E is replaced by D, then the preceding positions receive C, B
and A. The result is AABCD.

A forward overlapping copy would read its own writes and can turn the region
into AAAAA. That is not a property of the desired move; it is the consequence of
choosing a direction that destroys later inputs. Counts are byte counts,
including zero. memset stores the low unsigned byte, not a full int per element.

memcmp and memchr use unsigned bytes. Comparing 0xFF with 0x01 therefore gives
positive ordering rather than interpreting 0xFF as a signed −1. Returned search
pointers refer into the original region; a matching index is not an allocated
copy.

Sources: [byte
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/memory.c#L4-L63).

## Read terminators without confusing them with bounds

strlen counts bytes before the zero terminator. strcpy includes that terminator;
strncpy instead fills exactly its count, padding after a short source and
omitting a terminator when the source fills the count. strncat has another
contract: it limits appended source bytes and writes a terminator afterward, so
its count does not describe total destination capacity.

strchr can return the terminator when searching for zero; strrchr retains the
last matching pointer. strstr returns the original haystack for an empty needle.
strdup allocates length+1 and copies the terminator only after allocation
succeeds. These return/lifetime contracts are used by actual compiler sources,
not merely names to resolve.

Additional span and accepted-byte searches live in separate source members.
Keeping their declarations in target headers prevents C90’s implicit-int
fallback from corrupting a returned pointer. A link can find a string function
while a caller still used the wrong return interface.

Sources: [string bounds, searches and
duplication](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/string.c#L5-L132).

## Map memory through the public contract

The allocator uses private anonymous mmap requests. The public mapping API
admits private file and anonymous mappings, read/write protection and aligned
nonnegative offsets. Unsupported flags, including MAP_FIXED, reject before a
syscall; a hint cannot replace unrelated mappings. Pointer and off_t widths
remain full LP64 widths, so offsets above 4 GiB are not shortened to int.

mmap translates the complete negative errno band to MAP_FAILED and sets errno.
munmap returns its public int status. Their lengths concern mapped extents, not
allocator requested sizes. Calling munmap on an arbitrary malloc payload would
skip the header and bypass the allocator’s ownership rule.

Other source members expose process, descriptor and path operations used by the
workload. exit now has a 64-slot handler table and a flush hook; abort has its explicit
signal fallback. Do not call this a full libc merely because a concrete
generator’s references are satisfied.

Sources: [public mapping
contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/mapping.c#L6-L38),
[termination
policies](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/process.c#L7-L94),
[process API
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/process-api.c#L1-L40).

## Separate a requested object from its allocation block

Ask for seventeen bytes. In the selected small allocation scheme, choose the
thirty-two-byte payload class. Add the sixteen-byte per-block overhead and
obtain a forty-eight-byte stride. These numbers name three extents: seventeen
bytes the caller requested, thirty-two payload bytes the class provides, and
forty-eight bytes used to move between managed blocks.

The pointer returned to the caller identifies the payload. Moving backward to
inspect its header is allocator work under its own contract; it is not part of a
general C object's permitted indexing. Similarly, writing forty-eight bytes
through the returned pointer would confuse the block stride with the caller's
writable object. The allocator's bookkeeping and the program's object have
adjacent bytes but different owners.

Small blocks come from mapped slabs. Returning one block to a free list makes it
available for a later request; it does not necessarily release the slab mapping.
Consequently, the process's mapped extent can remain large after the caller has
freed every currently used small object. That observation would not by itself
establish that the free operation ignored the object. Follow list ownership and
mapping ownership separately.

For a larger request, mapping-backed allocation carries a different release
path. The allocation policy is selected from the request; it is not an arbitrary
promise that every returned pointer belongs to one interchangeable class. An
invalid or already freed pointer remains outside the caller's contract. This
bounded allocator is a source-built runtime service, not a general proof against
corrupt metadata.

Sources: [headers, slabs and
mappings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L8-L103).

## Make failure leave the old owner intact

Supply an old eight-byte allocation containing eight meaningful bytes, then ask
realloc for a larger extent. If replacement allocation succeeds, copy the
preserved prefix, release the old storage and return the new pointer. At that
point ownership transfers: future accesses use the new pointer.

If replacement allocation fails, the old allocation remains valid. A caller that
assigns the result directly over its only old pointer can lose its way to that
surviving object. The failure-preservation mechanism and the caller's assignment
discipline are separate. On paper, keep two pointer cells until success decides
which owns the live object.

calloc first has to establish that count times element size fits its admitted
extent. An overflowed product that becomes a small positive value is not a small
legitimate request for the original number of elements. Checking before
multiplication preserves the relationship between requested object count and
allocated bytes. Only after a valid allocation can zeroing establish the initial
byte contents.

These cases suggest distinct future checks: preserved bytes on successful
growth, old-pointer validity on failed growth, overflow rejection and zero
initialization. None is established just by observing a nonzero returned address
from malloc. The paper example supplies the old contents and branches; it does
not claim an allocation failure was induced here.

Sources: [headers, slabs and
mappings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L8-L103).

## Let overlap decide the copying direction

Place A B C D E in five adjacent bytes and move four bytes one position to the
right. The destination overlaps the source at a higher address. Copying from the
end produces A A B C D. Copying from the beginning would repeatedly read bytes
already overwritten by earlier stores, losing the original B, C and D.

Move four bytes from positions one through four down to positions zero through
three instead. Forward copying produces B C D E E. Here the destination is
lower, so reading ahead before overwriting is safe. The two results are supplied
memmove states. A memcpy call has its own no-overlap contract; a particular loop
that happens to work for one overlap direction would not expand that contract.

String functions add a terminator rule to byte traversal. A count limiting a
destination or comparison is not automatically the length of a valid terminated
source. Keep the operation's stated source span and destination capacity
separate. Mapping and process wrappers then return us to G06's raw-error
conversion: obtaining or releasing storage is an operating-system boundary,
while copying bytes inside a valid span is a runtime algorithm.

Sources: [calloc and realloc failure
preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L105-L148),
[byte
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/memory.c#L4-L63),
[string bounds, searches and
duplication](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/string.c#L5-L132).

## Use a byte ledger to keep object ownership visible

Supply a seventeen-byte allocation and fill its requested extent with a visible
pattern. Record the requested seventeen bytes, class capacity thirty-two and
block stride forty-eight. A successful growth must preserve the admitted old
prefix. A failed growth must preserve the old allocation. These predictions
concern different branches even though both begin from the same pointer.

After freeing the small object, cross out caller ownership but keep the slab in
the allocator's mapped ledger. A later request can reuse that block. Its
numerical address can match the earlier pointer while its allocation lifetime is
different. Address equality therefore does not revive the old object or make an
old stale access valid.

For a mapped large object, retain the mapping extent that the allocator uses for
release. The requested byte count and release extent can differ because mapping
granularity and allocator metadata have their own rules. A caller should still
use the public allocation contract rather than guessing unmap arguments from its
request.

| Operation | Input fact to retain | Fact to check afterward |
|---|---|---|
| calloc | Count and element size before multiplication | Valid total and zeroed admitted extent |
| realloc success | Old requested extent and new request | Preserved prefix and transferred ownership |
| realloc failure | Old pointer and contents | Old ownership remains valid |
| memmove | Both spans and their overlap direction | Original source bytes at destination |
| strncpy | Source termination and count | Exactly the bounded-copy contract |

For strncpy with four source characters and count four, no extra terminator is
promised. That is not an allocation failure; it is the string operation's
specified result. If the caller needs a terminated destination, it must supply a
suitable capacity and operation. “Fits four characters” and “fits the terminated
string” ask different extent questions.

The mapping wrapper rejects MAP_FIXED before entering the kernel because
replacing an unrelated mapping would change its bounded ownership promise. This
guard is different from allocator reuse of a block it already owns. Treat both
through the actual owning layer rather than calling every repeated address a
safe reuse.

A later runtime record should include contents and lifetime transitions, not
just nonnull pointer results. Surrounding guard patterns can expose copying
beyond the requested extent; a saved old pointer can expose failure-preservation
behavior. The chapter has supplied these observation questions without
allocating, inducing failures or accessing mapped test pages.

Sources: [headers, slabs and
mappings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L8-L103),
[calloc and realloc failure
preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L105-L148),
[byte
operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/memory.c#L4-L63),
[public mapping
contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/mapping.c#L6-L38),
[termination
policies](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/process.c#L7-L94),
[process API
source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/process-api.c#L1-L40).

## Separate source closure from interface closure

The driver compiles selected runtime C sources into ordinary relocatable
objects. Their symbols make helpers available to source generators and other
tool products. Closing the selected unresolved set is a practical milestone: the
linker can choose implementations for the names the program needs.

The implementation contracts remain richer than those names. A memcpy provider
requires valid nonoverlapping spans. A string routine may require a terminated
source. A realloc provider must preserve the old allocation on failure. An mmap
wrapper rejects a fixed replacement policy. The name list alone cannot encode
all these preconditions or results.

Supply a generator that references malloc and memcpy but never requests
overlapping movement, never calls realloc and never overflows a calloc product.
Its successful run could establish useful behavior for its actual requests. It
would leave the other branches untouched. A broader runtime check needs distinct
inputs chosen to expose those branches, rather than describing the same
generator run more confidently.

A source-built runtime also runs under Linux. Mapping, descriptor and process
interfaces call the raw bridge from G06. Python can copy inputs or launch a
generator without generating its C object bytes; the operating system can
service a mapping without becoming the C compiler. Preserve these supporting
roles in the graph instead of trying to reduce every dependency to a compiled
library.

The small allocator's free lists and slab policy are particularly useful for
reasoning about resource ownership. Caller ownership can end while allocator
ownership continues. A later reused address names a new allocation lifetime. If
a future trace reports the same pointer twice, compare lifetime events before
deciding whether an allocation was duplicated.

For a later closure account, retain selected runtime source files, object
digests, extracted members and the actual generator workload. For an interface
account, retain the operation-specific input spans, sizes, contents and failure
events. They can support one another while remaining different evidence. This
book supplies the source mechanisms and paper cases; it has not run a new
allocator or generator workload.

Sources: [headers, slabs and mappings](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L8-L103), [calloc and realloc failure preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/alloc.c#L105-L148), [string bounds, searches and duplication](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/string.c#L5-L132), [public mapping contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/mapping.c#L6-L38), [termination policies](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/process.c#L7-L94), [process API source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/process-api.c#L1-L40).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](06-raw-syscalls-startup-and-runtime-control.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/07-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G7-01 — Choose a class

Give capacity and stride for request 17. Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G7-02 — Keep failure ownership

Growing the supplied 17-byte block fails. What remains live? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G7-03 — Check multiplication first

Why does calloc compare before multiplying? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G7-04 — Move overlap

Derive the supplied ABCDE move. Explain which supplied rule determines your
answer. Keep any prediction separate from a claim that the corresponding program
or build was run.

### G7-05 — Separate string contracts

Does strncpy(dst,"ABCD",4) promise a trailing zero? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G7-06 — Reject a mapping flag

Why reject MAP_FIXED before calling Linux? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G7-07 — Bound runtime closure

All generator references resolve. Does this establish every libc service?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now state allocation/byte-operation interfaces before the actual
workload needs them. Use the state transitions above to justify that
explanation, rather than treating a source filename or a successful later
milestone as a substitute for the mechanism.

Continue to [G08: Target headers and honest feature
probes](08-target-headers-and-honest-feature-probes.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
