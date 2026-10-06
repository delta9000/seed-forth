# Validation record

This manuscript checkpoint, checked on 2026-10-06, contains an entry
guide, a motivation chapter, nineteen teaching chapters, ninety-five exercises
with separate feedback, six four-question mixed return checks and a compact
reference. The first volume's paper route is complete as a draft. It is not
a validated execution guide or a completed multi-volume rewrite.

## Checks performed

The included checker is intentionally small and inspectable:

```sh
python3 books/check.py
```

It uses Python's standard library. It checks the two relevant source blob
identities, the static seed-byte count, selected excerpt tokens, all local
Markdown links and anchors, paired exercise IDs, complete original-chapter
inventory, and a bounded set of mathematical assertions for worked results.
The current document pass checks all local inline and reference-style links,
the 71-row source inventory, the prerequisite graph of all 77 teaching units
for cycles, ninety-five exercise pairs, two source blobs, all 63 library
colon-definition excerpts and bounded mathematical assertions. It also
checks all thirty-two primitive-reference names/body offsets and five complete
predicted capstone-entry byte strings. The earlier units passed their smaller document passes. The exact source byte
sequence contains 1,772 bytes and has SHA-256
`697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e`.
That digest was calculated from source text; no executable was launched.

It does not execute source snippets. Run it in a checkout whose root files
match [the edition pin](EDITION.md); `--source-root PATH` allows a separately
materialized snapshot.

An independent document review compared the manuscript and solutions with
`000-seed.hex0` and `010-lib.fth`, concentrating on operand order, memory
widths, address/value roles, prerequisites and the scope of evidence. Findings
were corrected before the final checkpoint. The source excerpts use plain
fences and do not add a second literate-source authority.

The canonical `book/` tree, root source, build scripts and `book.toml` are
unchanged. Remote tree comparison is the evidence for that boundary.

The repository's automatic push-triggered [Check run for the first milestone](https://github.com/delta9000/seed-forth/actions/runs/37416564070)
completed successfully at commit
`819de4d346c38623d8db741323bc92293273690a`. Both `check-all + verify` and
`mdbook build + links` passed. Those existing jobs exercise the canonical
repository and original literate book; they do not execute this new edition's
examples or render the separate `books/` tree. The six-chapter checkpoint also passed [its own Check run](https://github.com/delta9000/seed-forth/actions/runs/37417624921)
at commit `d63b29b3f7f563bafb0de6056309e70cc0964e41`. The ten-chapter
checkpoint passed [its separate Check run](https://github.com/delta9000/seed-forth/actions/runs/37419018142)
at `bff03516d3b7202bb2ecbb0457192ec61cb9d9eb`. The thirteen-chapter
checkpoint also passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37420513780)
at `705e3f73a5f74c636b0f016d1e8f840acf6d747a`. The sixteen-chapter
checkpoint passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37422538095)
at `030bb0c8e5c8805f889bc00c3f8bb165e3631bbf`. Later checkpoints have
their own CI identity and must not inherit those results as a fresh run.

The entry guide, motivation chapter, nineteen teaching chapters, reference,
solutions and mixed checks were converted from GitHub-flavored Markdown to
HTML with Pandoc 3.1.11.1 to check parseability. A local
headless Chromium layout check could not complete because the environment
refused its process-singleton socket. No browser screenshot inspection is
claimed; GitHub and published-book layout still need visual review.

The [byte audit ledger](seed-forth/AUDIT.md) partitions all 1,772 bytes into
76 source-checked regions. The audit manuscripts cover all 1,772 bytes:
S11 covers 186, S12 119, S13 70, S14 142, S15 816, S16 237, S17 34 and
S18 168. The displayed records include all 32 reconstructed dictionary
headers and all 338 decoded startup/body/helper instructions, along with the
ELF fields. The checker compares every displayed
byte to the pinned image and verifies exact, nonoverlapping coverage. GNU
readelf/objdump 2.44 independently supplied static decoding observations;
neither tool executed the seed. A complete region ledger does not establish
that the prose or program is correct on every input.

## Still unverified

- The seed examples have not been executed for this edition
- No manual compiler, bootstrap, GCC-stage or Linux-boot reproduction was
  performed for the new chapters; the automatic canonical CI run above has
  its own narrower record
- Existing reported build comparisons remain attributed to their pinned
  source documentation, not newly reproduced observations
- No representative new reader has attempted the unit; learnability remains
  a reasoned design judgment awaiting reader feedback
- Screen-reader behavior, mobile presentation, PDF/EPUB export and a complete
  published-book rendering have not been validated
- Planned later chapters and volumes do not yet supply their promised entry
  artifacts, implementation walkthroughs or acceptance checks

## Next coherent unit

The next manuscript work establishes the C-compiler volume's entry profile
and recurring program before opening preprocessing, tokens and parser state.
The [coverage map](COVERAGE.md) distinguishes that planned material from
the first volume's drafted mechanisms and its remaining verification work.
Execution checks need a named, authorized seed profile before their status
can change from derived to observed.
