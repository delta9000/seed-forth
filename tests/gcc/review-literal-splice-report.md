# Independent literal-continuation review

Accepted within the bounded LF literal and raw-stringification scope against
`040-cc-prep.fth` SHA-256
`5708cccd9f44de31878d31b80b48247f573a7559f996aa06073c42f4444e6426`.
The review gate is `python3 tests/gcc/review-literal-splice-check.py`;
machine-readable evidence is `tests/gcc/review-literal-splice-results.json`.

The tracked evidence preserves the accepted historical run and its original
reviewer-script hash. By default, subsequent gate runs write only their own
`build-out/review-literal-splice-*/report.json`; `--report` explicitly selects
an additional output. `--baseline` can supply the preceding frozen layer when
running from an isolated source checkout. If the default historical baseline
is absent, the gate explicitly skips historical comparisons and still runs all
48 semantic cases and executable checks. An explicitly selected missing
baseline fails instead of skipping.

The gate snapshots production source bytes and compares the final candidate
with the preceding frozen computed-include checkpoint's `040-cc-prep.fth`
(`4510f0499c350533a1d8c8059616f8a9b270c2b6ee863db5599a61fe1d3ccfb4`).
All target preprocessing and target executable generation run through the
seed/Forth chain. Host `cc -E -P` tokens and a separately compiled executable
are independent oracles; none of their products feed the Forth chain.

## Evidence

- All 48 in-scope fixtures match host preprocessing tokens, covering strings,
  characters, empty/adjacent literals, backslash runs of lengths 1–6, quotes
  escaped across a continuation, hex/octal escape sequences, repeated
  continuations, object/function definitions, nested/repeated/unused arguments,
  stringification with comments and edge whitespace, empty token-paste operands,
  wide-prefix pasting, skipped conditions, character conditions, and EOF.
- Nested includes, a function-computed header, and a stringified computed
  header match host tokens and physical `__LINE__`/`__FILE__` provenance.
- Independently generated Forth and host executables both validate string and
  character values, including an even-backslash continuation becoming a
  backspace escape, then exit zero and print exactly `ab` plus one newline.
- Historical default and native modes preserve preprocessing bytes for an
  ordinary fixture. Their ordinary executable fixtures are also byte-identical
  before/after and exit zero. Continued-literal preprocessing deliberately
  changes in both modes and now matches the host oracle.
- The report records all captured production hashes, exact fixture hashes,
  reviewer script hash, diagnostics, before/after output, and retained work
  paths. Production source bytes were unchanged during the accepted run.

## Defects found and resolved

The initial repair handled a continuation only when the literal walker first
visited its backslash. With two adjacent backslashes before a physical LF,
the escape walker consumed both and retained the LF inside the literal. The
owner changed the walker to remove continuation pairs before interpreting
each logical token byte, including between an escape backslash and its next
logical byte. Parity runs and escaped-quote cases verify that correction.

The initial stringifier trimmed argument whitespace before deleting
continuations. A trailing continuation consequently lost its LF first and
left a stray backslash in the result. For example, `S(a` followed by a
backslash/LF and `)` should stringify to `"a"`. Removing that preliminary
trim lets the existing whitespace state machine handle edges after the
continuations are removed. Trailing, splice-only, comment-adjacent, and nested
cases verify the correction.

## Explicit limits

This is not complete translation-phase-2 support. The audit separately records
three pre-existing mismatches: identifier splicing outside a literal, a
continuation in a direct header-name operand, and CRLF literal continuations.
They remain outside this LF-focused increment. The computed-header tests pass
through the repaired literal/stringification machinery; the direct header
parser is a different path.

The historical checks above are focused controls, not a rerun of the complete
native, TinyCC, or bootstrap suites. The owner's aggregate/source-book gates
and unchanged original GCC generator checks remain separate evidence. This
review establishes no full ISO C or complete GCC-bootstrap claim.
