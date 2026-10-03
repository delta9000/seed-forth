# Independent computed-include review

Accepted within the documented bounded direct-preprocessor profile. Review
gate: `python3 tests/gcc/review-computed-include-check.py`. Machine-readable
evidence: `tests/gcc/review-computed-include-results.json`.

The final run passed against `040-cc-prep.fth` SHA-256
`4510f0499c350533a1d8c8059616f8a9b270c2b6ee863db5599a61fe1d3ccfb4`.
All production input bytes remained unchanged during that run. The results
record their individual hashes and the exact reviewer script hash.

## Evidence

- 30 fixture cases matched independent host `cc -E -P` tokens, covering nested
  relative lookup, ordered quote/angle search, absolute names, macro aliases,
  function substitutions, stringification, token pasting, source locations,
  skipped conditions, escaped filename bytes, missing final newlines, guarded
  self-inclusion, redefinition, and 400 successive computed includes.
- A further case included the complete original `config/i386/i386-modes.def`,
  verified SHA-256
  `0141dec67f7141c1f2bb4096ad18fb2a7628f4a7ea5258acd9dc736491c6330d`, matched
  every host-preprocessed token, and retained all five architecture-specific
  markers. Its bytes were unchanged afterward.
- 21 malformed, unknown, empty, cyclic, or missing operand cases failed with
  error 30 and preserved pre-existing binary output bytes. These include a
  missing nested header and a missing actual `EXTRA_MODES_FILE` lookup.
- Four valid GNU angle-token forms with internal whitespace were deliberately
  rejected with error 30, with no output created. This includes the separator
  blanks introduced by a function macro producing `<x>`.
- Eleven direct Forth assertions verified scratch top, original source
  address/length/position, file scanning mode, include depth/pool top, output
  sink depth/address, source-location expansion depth, and pending-newline
  restoration after nested and repeated computed includes.

## Findings resolved during review

The initial implementation's `cc-pp-line-slice` interpreted `/*` inside a
quoted function argument or trailing `//` comment as a block comment. It
could consume following source lines and reject otherwise valid computed
includes. The owner corrected the slicer to walk literals and line comments
before detecting block comments. Both minimal regressions now match host CPP
and are retained in the review gate.

The original book prose also still listed computed includes as unsupported.
The owner replaced that stale statement with the bounded implementation and
its computed-angle whitespace restriction.

## Explicit limits

The implementation follows the quoted computed-header spelling rule from
the [GNU computed-include documentation](https://gcc.gnu.org/onlinedocs/cpp/Computed-Includes.html):
backslash bytes and escaped quotes remain filename bytes. It does not claim
GNU's full whitespace-sensitive angle-token joining behavior. The gate proves
that unsupported angle cases fail explicitly instead of selecting a different
file or silently omitting the include.

The existing shared macro engine does not recognize a function invocation
when a comment separates its macro name from `(`. For example,
`ID/**/("only.h")` fails as a computed include, and `ID/**/(7)` remains
unexpanded in ordinary C text. This pre-existing macro-engine limitation is
recorded separately and is outside this bounded change.

Host CPP was used only as an independent token oracle. Production
preprocessing and state assertions ran through the Forth seed. This focused
review did not rerun the long historical native/TinyCC suites; their exact
artifact pins and the canonical book/source check belong to the owner's
batched publication gate.
