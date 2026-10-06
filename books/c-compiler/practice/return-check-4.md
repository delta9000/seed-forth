# Return check: bytes, patches, and runtime results

Use the bounded instruction and legacy-runtime contracts from C09–C11. Each
case is an independent paper layout, with valid owned code/data spans and
sufficient capacity. The stated syscall results are supplied premises, not
observed runs. Keep builder addresses, file offsets, generated registers and
returned units in separate columns.

## Questions

### CR4-01

In the illustrative star-call layout, `putchar` begins at file offset 146 and
the caller's CALL starts at 1024. RDI holds 42 before CALL; RSP is S. Derive the
CALL displacement and bytes. The shim's one-byte write returns 1. What are
RAX and RDI after the shim's RET, and what does the following emitted
RAX-to-RDI result move change? Does the returned 1 mean the character byte 1 was
requested?

### CR4-02

A separate valid layout has a CALL displacement field at file offset 1201 and
a MOVABS address field at 1222. The function target becomes known at file
offset 1408, with load base 0x400000. Derive both fields and their widths. If
both patches were recorded in sixteen-byte builder nodes, does that make
the field widths or formulas identical? Which operation clears a function's
owning head cells, and does clearing them free the nodes?

### CR4-03

Use separate legacy calls `fread(B,2,4,7)` and `fwrite(B,2,4,7)`, with a writable eight-byte read buffer and a readable eight-byte write
buffer, and a supplied positive transfer of five bytes in each case.
What does each return? For the read, which prefix contains transferred bytes,
and how many complete two-byte elements does it contain? Does either shim
retry the remaining three requested bytes?

### CR4-04

Use a separately established LP64 integer profile with bootstrap floatbits
off, a valid frame, slot 16 and plain signed char storage. Generated RDI holds
511. A typed local byte-store writes that value's low byte. What address and
byte are affected, and what does the store alone leave in RDI? What would the
signed-char result-conversion helper subsequently produce? Explain why the
one-byte C object does not change the slot coordinate to `RBP−17`.

## Hints

- CR4-01: a CALL's four-byte field is relative to its next instruction; the
  shim returns through RAX, not its restored scratch register
- CR4-02: the node stores a location where a patch belongs, not the patch's
  eventual bytes or meaning
- CR4-03: compute requested bytes first, then apply each actual return rule
- CR4-04: effective address, memory width and register conversion are three
  distinct operations

## Worked answers

### CR4-01

CALL ends at 1029. The displacement is `146−1029=−883`, represented by the
four little-endian bytes `8D FC FF FF`. The complete instruction is
`E8 8D FC FF FF`. Its saved return address is `0x400000+1029`, or 0x400405.
This illustrative caller is beyond the known eager block ending at 522; it is
still a manually chosen callsite, not a claim about an actual parser dump.

The shim temporarily pushes 42 to obtain a one-byte source buffer, writes its
low byte to fd 1, then pops 42 back into RDI. RET consumes the caller's saved
return address. Afterward RSP is S, RDI is 42 and RAX is the supplied raw result 1.
The caller's result move copies RAX into RDI, making RDI 1. The requested byte
was 42 (`*`); one is a count/result from that write, not a replacement character.

Changed case: supply raw result −9 instead, with the same return path. After
RET, RDI is still 42 and RAX is −9; the result move puts −9 in RDI. This does not
establish that a star was delivered. The generic write wrapper would normalize
a negative result to −1, while this putchar shim preserves it.

### CR4-02

The CALL field is four bytes. Its next-instruction coordinate is
`1201+4=1205`, so its displacement is `1408−1205=203`, bytes `CB 00 00 00`.
The MOVABS field is eight bytes and receives the absolute target
`0x400000+1408=0x400580`, bytes `80 05 40 00 00 00 00 00`.

Both builder nodes may use the same two-cell layout, but that layout describes
metadata: output field offset and next-node pointer. It does not select the
patch operation. The relative and absolute walkers interpret their respective
lists differently.

After walking each prototype list, the function-definition consumer
explicitly stores zero into that list's owning head cell before continuing. The walkers themselves
do not clear those heads. Clearing disconnects reachable metadata; it does
not erase node contents, free individual arena records or rewind allocation.

Changed case: move the supplied target to file offset 1024. The relative value
becomes `1024−1205=−181`, bytes `4B FF FF FF`; the absolute value becomes
0x400400, bytes `00 04 40 00 00 00 00 00`. The two field locations and widths
are unchanged. No other layout in this return check is being modified.

### CR4-03

Both calls request `2*4=8` bytes. The read's positive result is divided by its
saved size: `5/2` yields **two complete elements**. The valid transferred
prefix is `[B,B+5)`: two complete elements and one byte of the next element.
Returning two does not mean only four bytes were written into B.

The write shim returns **five bytes**, without dividing by size. Interpreting
that as five elements would falsely claim ten transferred bytes from an
eight-byte request. Neither body retries the missing three bytes. A later
caller would need its own policy and correct units to decide what to do next;
no such policy is invented by these names.

Changed case: set size 1 and count 8, retain the valid eight-byte extent, and
again supply progress 5. The read returns five elements and the write five
bytes. Their numbers now coincide, but their return conventions did not
become the same operation.

### CR4-04

The slot coordinate is `RBP−8*(16+1)=RBP−136`. The low byte of 511 is FF, so
that byte is stored there. The store alone leaves the full RDI value 511.
Its address uses the four-byte displacement form because −136 is outside the
signed one-byte range. Narrowing the amount written does not narrow the
address displacement or change how a slot number is interpreted.

The later signed-char conversion keeps FF and sign-extends it, yielding the
64-bit representation of −1. This is the inspected helper's register effect,
not a claim that the store itself converted the assignment result or that all
C conversion rules have been established.

Changed case: with unsigned char under the same valid LP64 profile, the store
still writes FF at the same address. The result conversion zero-extends it,
producing 255. Choosing a signed or unsigned consumer changes interpretation
without changing those stored eight bits.

## Use the result

For a wrong answer, first label the disputed quantity: address, offset,
displacement, byte count, element count, stored byte, or register value. Then
repeat the smallest transition that owns it. If the number is right but its
claim is too broad, identify the unobserved call or unsupported profile.
These cases assess paper reasoning opportunities, not actual execution,
conformance or demonstrated learning transfer.

[Back to the volume](../README.md)
