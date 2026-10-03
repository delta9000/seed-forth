# Independent archive/member-selection review

The final frozen archive implementation passes all **176 recorded checks**:
161 seed-Forth executions and 15 independent GNU `ld` comparisons. Additional
Python assertions inspect member/index bytes, compare `ar p` payloads, check
publication preservation, and compare ordinary-object executables byte for byte.
There are no outstanding defects from this review.

This result establishes the bounded archive contract described below. It is
not a claim that a complete direct GCC bootstrap or arbitrary ELF/archive
compatibility has been established.

## Reproduce and identify the snapshot

Run `python3 tests/gcc/review-archive-check.py` from the repository. The fixture
also accepts `SF_REVIEW_ROOT` for a frozen source tree. It reads every Forth
layer into memory before running and checks that those layers have not changed
when it finishes. No production compiler, linker, documentation, or Git state
was modified by this reviewer.

Final proof artifacts are in
`build-out/review-archive-0penq_27/`; the recorded results are copied into
`tests/gcc/review-archive-results.json`. That JSON is historical evidence copied
at checkpoint time. Normal fixture runs write only their fresh `build-out`
results and leave published evidence unchanged. The source/fixture/report
manifest is `tests/gcc/review-archive-manifest.json`.

After the final 176-check run, a one-line harness-only change removed the
unconditional source-tree results write. The executed fixture hash remains
recorded in the historical JSON (`c06da3d368c4d17c4ffb943d9b1cc4cdcf3879bd7ba9a048442a0668b4066b79`);
the post-change fixture hash is in the manifest. `py_compile` and an isolated
execution of the actual final results-write statement verified the change:
only the fresh build-output JSON was written, and a preexisting historical
JSON remained unchanged. No Forth, input, assertion, or oracle logic changed.

Reviewed SHA-256 values:

- `140-cc-link.fth`: `abacc3197fd03baf31d2d86b0c999ca3b63e04b806882078d7925ae55bfd4e84`
- `141-archive.fth`: `e6a544feae6a75286dab034f319da04ca5149131ebf930257fc503ca975aa674`
- `book/44-direct-gcc-archives.md`: `c1fcfb3b12a9316517f03a29f2436ce3339cd5b56ef989d59ab66121a0459dc0`
- `081-cc-object.fth`: `7c9f15eb3d0b9820ebd5282fc76269ef3a27cee8fde09b64e6397dddd4e25438`
- `seed-forth`: `697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e`

The canonical `file=141-archive.fth` block in Chapter 44 was independently
checked byte-identical to the reviewed source. The ordinary-object comparison
uses the pre-archive linker from immutable revision
`f6777bf6b657cbd10601f52d482891959da3a05f`, whose linker SHA-256 is
`9be639f99a6ffeef31baf456e3db765f83c9dd75c54054904c340febe81d84f8`.

## Production boundary and independent oracles

Every primary target object is produced by `081-cc-object.fth`, every primary
archive by `141-archive.fth`, and every target executable by the Forth linker,
all running on the existing seed. Python transports Forth, inspects bytes, and
creates deliberately changed input fixtures. It does not perform target symbol
selection, build target indexes, or supply a fallback linker.

GNU binutils 2.44 `ar` and `ld` are independent oracles. `ar t` checks names,
`ar p` confirms original object payload identity, and GNU `ld` independently
links the same Forth-produced fixtures. A separately named GNU-created archive
is used solely to test reader interoperability. The BSD extended-name positive
fixture changes one archive envelope around an unchanged Forth-produced object;
its GNU index still identifies the member header. This is format testing, not a
production path.

## Findings repaired before the final run

Two executable probes exposed writer/reader mismatches in checkpoint A
(`141` SHA-256 `4a7d029fd6c31948c2b5e14680b31f56cd74bf3eca43de8bc8590dfea552531a`):

1. Changing a nonlocal ELF symbol's `st_name` to zero allowed archive publication
   with an empty index name, which the archive reader then rejected. The writer
   now validates nonempty names for both defined and undefined nonlocal symbols.
   Regression cases verify error 250 and preservation of an existing output.
2. A legal ordinary basename such as `__.SYMDEFordinary.o` was accepted by the
   writer but rejected by an overbroad reader prefix check. The reader now
   rejects the exact reserved BSD names; the writer rejects those same names
   before publication. Ordinary prefix names now round-trip and link.

Static inspection also identified a binding/section conjunction that used
bitwise integer `and`, omitting weak text and global rodata/BSS definitions
from the index. The owner had independently repaired it before the first stable
run. The final fixture covers every global/weak definition in text, rodata,
data, BSS, and ABS, while excluding every corresponding local definition.
The owner also repaired odd-padding validation and writer-to-reader mapping
ownership before the first stable run; both have explicit final regressions.

## Verified behavior

- Deterministic archive bytes, GNU index contents, original payload identity,
  short/long-name boundary at 15/16 characters, multiple GNU long names, BSD
  extended names with NUL padding, and odd-sized payload emission
- Repeated writes of one writer collection produce identical bytes; adding a
  member after a write produces a valid expanded archive
- Lazy selection in member order, reverse dependencies requiring another pass,
  and successful execution of a real cross-member relocated function call
- Weak undefined references do not extract; later strong demand upgrades them;
  weak definitions can satisfy demand; locals do not enter the index
- A forced selection for another symbol obeys normal weak/strong precedence and
  reports duplicate strong definitions; unused duplicate or unresolved members
  remain unselected
- Archive-before-demand failure, explicit repeated archive success, and the
  absence of implicit cross-archive groups, compared with GNU `ld`
- An unselected member with invalid ELF is ignored after its archive envelope
  and index pass validation; selecting the same bad payload reports error 250
- Exactly 256 archive members are accepted by writer and reader; member 257
  reports capacity error 251 without replacing the prior output
- Truncated magic/headers/payloads/padding, bad header trailers, invalid and
  overflowing decimal sizes, impossible index counts, nonmember offsets,
  empty/unterminated index names, duplicate special tables, bad GNU name
  offsets/terminators, malformed BSD name extents, unsupported 64-bit index,
  and nonempty unindexed archives produce explicit bounded errors
- Existing outputs survive unresolved symbols, selected invalid ELF, writer
  validation failures, and induced partial writes (`RLIMIT_FSIZE`) in both
  archive and executable publication; no sibling temporary output remains
- Direct, hardlink, and symlink source/output aliases are rejected; an entirely
  unselected archive is still protected by the independent source inode ledger
- `mincore` confirms release of selected-member copies, writer source mappings,
  archive reader mappings, and writer mappings during a writer-to-reader
  transition; link initialization clears object state and the source ledger
- Loading the new archive layer does not change ordinary-object executable
  bytes, and the current linker produces exactly the same ordinary-object
  executable as the immutable pre-archive linker on the reviewed fixture

## Limits

The implementation explicitly supports regular GNU 32-bit indexes and the
existing ten-section ELF contract. BSD ranlib indexes, GNU 64-bit indexes,
thin archives, arbitrary native ELF layouts, COMMON, archive groups,
whole-archive mode, and incremental editing remain outside scope. The index is
trusted to name candidate symbols; selected ELF is still validated normally.
Unselected ELF is intentionally not validated. The suite is substantial but
is not exhaustive over the 256 MiB input space, race conditions, or all system
I/O failures. The host adapter and complete bootstrap integration have separate
owners and are not approved by this parser/member-selection report.
