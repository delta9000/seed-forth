# Macro parameter continuation repair

## Measured original-source failure

The fresh original GCC 4.0.4 cc1 census used compiler epoch
`a5356f3b73523539aeb0a6581d1df054493d7690986d7b0c47aa973ee44e5fb0` and
its independently labeled configured/generated inputs. Its unchanged
`gcc/c-common.c` (upstream `944765863eec87a9f37e297994fd2af960397138`, SHA-256
`0ac139bcacc0eca1713d610023a1739f589f4699d755d62b24e5d4e5dada092b`) failed
with error 47 at flattened line 49786. The original `DEF_BUILTIN` definition
at physical line 3237 has eleven parameters, with a backslash-newline after
`FALLBACK_P,` and before `NONANSI_P`. The old parameter reader skipped spaces
and tabs, then required `)`, so it stopped at that backslash.

A diagnostic-only in-memory probe of the old source preserved the same
failure. It printed the final output ending in `c_init_attributes ();` and
the exact raw cursor beginning `\\` + LF + `NONANSI_P, ATTRS, IMPLICIT, COND)`.
The original source, configured headers, and running census were not changed.

## Bounded grammar and ownership

Only the source-location-enabled SysV target selects the new parser. Native
TinyCC and default legacy modes still select their existing parser. LF and
CRLF continuations are deleted before recognizing parameter names, commas,
and the closing parenthesis. Repeated joins and joins within identifiers are
allowed: `ar\\` + LF + `g` is the one name `arg`, never two names or whitespace.
A join between an intact macro name and `(` preserves function-like adjacency;
intervening spaces still make it object-like. Leading body continuations after
`)` are removed using the same physical accounting.

The parameter list is empty or contains 1–16 distinct ASCII identifiers,
separated by commas, spaces and tabs. A single existing 64 KiB temporary sink
stores the names' combined logical bytes. Name text remains valid during
replacement-body encoding and is released afterwards; definitions cannot
accumulate scratch storage. Physical source bytes and include paths are never
rewritten. Each consumed continuation contributes exactly one owed newline,
which is emitted after the directive. Physical/presumed `__LINE__`/`__FILE__`
values retain their meaning, and the continuation itself adds no diagnostic
line drift. The inherited parameter-index-10 marker caveat below is separate.
An error *inside* a definition keeps the existing flattened definition-start
line, before its owed newlines have been emitted.

- Error 47: malformed lists, duplicate names, missing names, trailing commas,
  unsupported parameter-list tokens, or a join splitting the macro's own name
- Error 48: a seventeenth parameter
- Error 37: combined logical parameter-name text exceeds 65,536 bytes
- Existing source, macro-pool and scratch-stack limits remain unchanged

The old SysV parser silently accepted leading/repeated/trailing commas and
duplicate names. Rejecting those definitions is an intentional standards-correct
repair, including definitions without continuations. The tests retain exact
old/new controls. This is not a general translation-phase-two implementation:
comments within parameter lists, variadics, form feed/vertical tab separators,
and split macro names remain unsupported. Split parameter references in the
replacement body remain a measured preexisting tokenization boundary; this
repair does not claim or silently generalize support for them. GCC's extension
accepting whitespace between backslash and newline is also deliberately rejected.

## Reproduction and evidence

Run the focused proof serially with a one-GiB address-space limit:

```
python3 tests/gcc/macro-parameter-splices-check.py \
  --baseline-root /path/to/frozen-a535 \
  --gcc-source /path/to/pinned/gcc-source
```

Without these optional paths, local grammar/execution checks still run and the
original-source and exact historical comparisons are explicitly skipped. The
script retains every input, CPP token comparison, diagnostic and source hash in
`build-out/parameter-splices-*/report.json`. Host `cc -E -P` is an independent
token oracle; host `-O0` and `-O2` executables are behavioral oracles only. Target
preprocessing, compilation, runtime objects and linking use the seed/Forth
compiler. The original full `DEF_BUILTIN` body and original `builtins.def` cohort
are copied byte-for-byte into test fixtures, never edited or used as replacement
inputs for the census. The exact `df.c:3806` `HS` definition together with both
original invocation arms is an additional pinned token witness of the same
parameter-list continuation shape; no second full-unit census is run.

A controlled full `c-common.c` replay uses the repaired compiler with the exact
old configured/generated input hashes. It is explicitly a mixed compiler/config
replay, not a new configure result or a same-epoch cohort pass. Its terminal
result and any later blocker belong in the retained replay report. Focused
success is not a complete GCC build, link, self-rebuild, or final integrated gate.

## Measured candidate result

Compiler `d459389c0c0cfe9d531bfd99dfb0d1448f5836d09a8d514a6a0494f76c5311ee`
passes the original parameter-definition failure in a complete unchanged
`c-common.c` compile replay. Against the retained a535 configured headers it
then fails with error 245 at flattened line 50055, publishing no object. All
recorded census/compiler/configuration input hashes remain unchanged. This
later failure is a separate boundary; the replay is not a successful object
compile or a same-epoch configure/build proof.

A diagnostic-only in-memory probe identifies this check as the request for
stable object record 5,121 with a 5,120-record table, while processing original
`builtins.def:239` (`BUILT_IN_HUGE_VAL`). Parsing the retained complete
Forth-preprocessed stream with a separately raised diagnostic bound reaches
EOF with exactly 9,866 stable records, then encounters another object-writer
capacity error. These measurement-only bounds are absent from the reviewed
macro repair; neither a larger production workspace nor a successful object
emission is claimed here.

## Independent-review diagnostic caveat

A preexisting body-encoding defect is unchanged by this repair: parameter index
10 is stored as marker byte LF and increments the preprocessing diagnostic line
counter. A later `#error` can consequently report one line too high, even for
a definition with no continuations; both a535 and d459 exhibit it. Referencing
that parameter in a continued 16-name definition similarly gives physical line
17 as flattened diagnostic line 18. The physical/presumed `__LINE__` and
`__FILE__` values remain correct. Claims above concern continuation ownership,
not a blanket guarantee of accurate diagnostics for every existing marker form.
Independent evidence retains exact before/after inputs and stderr. This is a
separate follow-on defect and is not silently repaired in the macro-list patch.
