# Validation record

This is a manuscript milestone, checked on 2026-10-06. It contains an entry
chapter, three teaching chapters, fifteen exercises with separate feedback,
and a four-question mixed return check. It is not a completed book or a
reproduced compiler build.

## Checks performed

The included checker is intentionally small and inspectable:

```sh
python3 books/check.py
```

It uses Python's standard library. It checks the two relevant source blob
identities, the static seed-byte count, selected excerpt tokens, all local
Markdown links and anchors, paired exercise IDs, complete original-chapter
inventory, and a bounded set of mathematical assertions for worked results.
All 14 Markdown files and 86 links passed at the first complete-unit check,
alongside the 71-row inventory, 15 exercise pairs, two source blobs, five
excerpt comparisons and mathematical assertions. The exact source byte
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
unchanged. Remote tree comparison is the evidence for that boundary; the
existing compiler and literate-source suites were not rerun in this pass.

The entry chapter and three teaching chapters were converted from GitHub-
flavored Markdown to HTML with Pandoc 3.1.11.1 to check parseability. A local
headless Chromium layout check could not complete because the environment
refused its process-singleton socket. No browser screenshot inspection is
claimed; GitHub and published-book layout still need visual review.

## Still unverified

- The seed examples have not been executed for this edition
- No compiler, bootstrap, GCC stage or Linux boot was run for this manuscript
- Existing reported build comparisons remain attributed to their pinned
  source documentation, not newly reproduced observations
- No representative new reader has attempted the unit; learnability remains
  a reasoned design judgment awaiting reader feedback
- Screen-reader behavior, mobile presentation, PDF/EPUB export and a complete
  published-book rendering have not been validated
- Planned later chapters and volumes do not yet supply their promised entry
  artifacts, implementation walkthroughs or acceptance checks

## Next coherent unit

The next manuscript work is S04–S05 in [the coverage map](COVERAGE.md):
return-stack discipline and reusable shuffles, then comparisons and character
classes with explicit signed/unsigned boundaries. It should preserve the same
contracts, recurring state notation, source pins and separate feedback.
Execution checks need a named, authorized seed profile before their status
can change from derived to observed.
