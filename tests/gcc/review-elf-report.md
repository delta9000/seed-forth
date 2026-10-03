# Independent review of the bounded ELF writer and linker

Reviewed on 2026-10-03 against the reconstructed source at base commit
`1a18de7e2551051a94b54f09104290723ee4fe8b`, with the local linker hardening
captured before testing. This is a review of the ten-section object contract,
not a claim of general host-object, GCC, or complete ELF conformance.

## Verdict

The Forth linker passed the existing gates and independent boundary,
corruption, ownership, repeated-session, and output-publication tests. No
incorrect linked result or linker memory-safety defect was demonstrated in
this bounded review. The object writer passed its existing representation and
capacity gate. One reproducible output-preservation gap remains in the writer:
a diagnosed partial write destroys a prior destination file. Atomic replacement
is currently a property of `lnk-link`, not `cc-obj-write`.

Input SHA256 values:

- `081-cc-object.fth`: `d687029d099e16af38479ed0f91e7c8f64c96a5999a80813fdc6086ee23c0b9f`
- `140-cc-link.fth`: `9be639f99a6ffeef31baf456e3db765f83c9dd75c54054904c340febe81d84f8`

All test commands used a private copy under
`build-out/review-elf-snapshot`, with its complete input hash manifest in
`source-inputs.json`. Concurrent parser, ABI, and runtime development did not
change the code under review. Both core hashes still matched at the end of the
review.

## Confirmed finding: writer failure replaces old output with partial bytes

`081-cc-object.fth:359` opens the destination with flags 577
(`O_WRONLY | O_CREAT | O_TRUNC`). Validation finishes before this open, but a
subsequent failed write closes the descriptor and reports error 248 without
restoring the destination.

The minimal committed reproduction is:

```sh
python3 tests/gcc/review-elf-writer-atomicity.py
```

It creates a private existing output, imposes a 128-byte `RLIMIT_FSIZE`, ignores
`SIGXFSZ` so the kernel reports `EFBIG`, and asks the Forth writer to write an
empty object. The writer diagnoses error 248, but the destination contains 128
partial ELF bytes instead of its original contents. The reproduction exits 1
until output preservation is implemented. No system files or shared outputs
are used by this fault injection.

Recommended disposition: write to an exclusive sibling temporary and rename
only after successful close, cleaning up on failure, as the linker already
does. If the intended writer API explicitly excludes atomic replacement, keep
that limitation visible and do not describe all toolchain outputs as atomic.

## Passing verification

Existing gates, run unchanged against the snapshot:

```sh
python3 tests/gcc/object-writer-check.py
python3 tests/gcc/linker-check.py
python3 tests/gcc/linker-c-check.py
```

Results:

- Object writer: cross-object host-link oracle exits 42; metadata, repeated
  builds, reset, exact capacities, and 41 reported rejection cases pass
- Linker: all 75 seed invocations pass
- C linker boundary: separately compiled C objects execute with status 42 in
  both object orders

New independent gate:

```sh
python3 tests/gcc/review-elf-check.py
```

To select the frozen inputs rather than the current checkout:

```sh
SF_REVIEW_ROOT="$PWD/build-out/review-elf-snapshot" python3 tests/gcc/review-elf-check.py
```

It passes 42 seed invocations, including a 40-session reset stress case with
two links and two releases per session. Its fixture is separately written in
Forth and checks:

- A PC-relative read of zero-filled BSS, cross-object data-pointer relocation,
  independently aligned text/rodata/BSS, and colliding local absolute names
- Exact `PC32`/`PLT32` signed limits and immediate out-of-range neighbors
- Full-width `R_X86_64_64` values and modulo-2^64 addition
- The linker's maximum 1 MiB section alignment and capacity rejection before
  attempting an oversized BSS image
- Additional malformed header, null section/symbol, string-table,
  symbol-extent/visibility, local-prefix, and relocation-target records
- Rejection of unsupported COMMON, TLS symbol types, extended section indexes,
  and extra sections
- RX/RW segment flags, page congruence, BSS memory/file extent separation, and
  absence of BSS bytes from the output file
- Data-stack balance through a preserved sentinel
- Actual mapping release: Linux `mincore` reports `ENOMEM` separately for
  every previously owned input, global-table, and image page after release
- Failed output rename, missing output parent, input hardlink/symlink aliases,
  and an actual `EFBIG` short write; prior linked output survives and temporary
  files are removed

`readelf -aW` independently inspects both new objects and the linked image
without warnings. GNU `ld` independently links the new Forth-produced objects
as a test oracle, and that executable also exits 42. Neither host tool supplies
an object or executable in the successful Forth production path.

The latest passing evidence is in
`build-out/review-elf-snapshot/build-out/review-elf-b4n738au/`, including
`results.json`, source hashes, and `readelf` reports. Existing gate artifacts
are in the same snapshot's `build-out/object-writer-gp2szbnk/`,
`build-out/linker-ur26l0b7/`, and `build-out/linker-c-93m9zcf7/` directories.

## Boundaries and noncanonical metadata

The reader validates fixed section roles by index, type, flags, links, entry
sizes, and bounded spans. It is not a strict validator of every layout or symbol
combination that the writer forbids. Separate exploratory mutations showed
that it accepts:

- A section-name index that gives the text role the name `.rodata`
- A nonzero payload range pointing into ELF header bytes
- A text file offset not congruent to its declared alignment
- A named global `STT_SECTION`, or a global `STT_FILE` attached to `.text`
- An arbitrary `SHT_NOBITS` file offset, whose bytes are never read

These examples remain within checked mapped ranges; they did not demonstrate
an out-of-bounds access. GNU `ld` also accepted these probes. They are recorded
as contract precision/hardening opportunities, not proof of a wrong relocation
result or general ELF acceptance. A strict requirement to reject every input
that 081 could not emit would require additional validation and should be
stated separately from safe support of the fixed indexed roles.

This review does not establish archives, COMMON allocation, TLS, GOT/PLT
construction, COMDAT, dynamic linking, arbitrary host section layouts, shared
library visibility semantics, crash durability, or full GCC bootstrap support.
The source explicitly defers these features; rejection of unsupported layouts
is preferable to presenting this gate as their implementation.
