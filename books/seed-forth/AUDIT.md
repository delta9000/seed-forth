# Seed byte audit coverage

The [source audit ledger](source-audit.csv) partitions the pinned seed's
1,772 file bytes into 76 consecutive regions. Every byte belongs to exactly
one row. The ranges come from the annotated offsets in
[`000-seed.hex0`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0),
checked against the number of preceding decoded hex bytes. No gap or overlap
is hidden by the grouping.

This is a coverage ledger, not a correctness proof or a record of execution.
“Drafted” means the named manuscript explains that region. A source-matched
instruction listing and a manually derived trace still depend on the stated
ISA, loader and input assumptions. The new examples have not been executed.

## Ownership by teaching unit

| Unit | Region responsibility | Regions | File bytes | Manuscript state |
|---|---|---:|---:|---|
| [S11 Executable and entry](chapters/11-executable-and-entry.md) | Both ELF headers and the three startup sections | 5 | 186 | Drafted |
| [S12 Physical stacks and memory](chapters/12-physical-stacks-and-memory.md) | Ten stack and memory primitive bodies | 10 | 119 | Drafted |
| [S13 Arithmetic instruction bytes](chapters/13-arithmetic-in-instruction-bytes.md) | Five arithmetic and logic primitive bodies | 5 | 70 | Drafted |
| [S14 Physical I/O](chapters/14-physical-io-and-exit.md) | Four I/O/exit primitive bodies | 4 | 142 | Drafted |
| [S15 Dictionary and token input](chapters/15-dictionary-and-token-input.md) | All 32 dictionary headers, lookup/storage/token words and input/error helpers | 43 | 816 | Drafted |
| [S16 Colon compiler](chapters/16-native-colon-compiler.md) | Definition/literal bodies and the call-emission helper | 5 | 237 | Drafted |
| S17 Inline branch operands | Two branch primitive bodies | 2 | 34 | Planned |
| S18 Parser and interpreter loop | Decimal parser and REPL | 2 | 168 | Planned |
| Total | Exact file-byte partition | 76 | 1,772 | 1,570 bytes drafted; 202 planned |

Dictionary headers are assigned to S15 even when the corresponding primitive
body is taught earlier. This avoids pretending that recognizing a word's name
already audits its link field, flags or length. S19 will reconcile the complete
ledger and an integrated reader-built word after these audit chapters exist.

## Address conventions

- Start offsets are inclusive; end offsets are exclusive
- A row of size `n` beginning at file offset `f` owns offsets `f` through
  `f+n-1`
- In this edition, the mapped virtual address for a file byte is
  `0x400000 + file_offset`
- The ledger covers file bytes only. Zero-filled mapped memory, the runtime
  dictionary, data stack, token buffer and system variables are not extra
  bytes in the 1,772-byte file
- Source line ranges are supplementary locators; the immutable revision and
  byte range define the edition being discussed

## Static evidence

Source decoding yields SHA-256
`697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e`.
The inspected regions were also decoded with GNU objdump 2.44 in x86-64 Intel
syntax. This is static disassembly: the byte stream was read as data and was
not launched. A disassembler's output is another inspectable observation,
not independent evidence that the program behaves correctly for all inputs.

The [edition checker](../check.py) verifies the partition and its exact
source offsets alongside the other document contracts. The wider
[validation record](../VALIDATION.md) separates these checks from repository
CI, unexecuted teaching examples and the outstanding real-reader review.
