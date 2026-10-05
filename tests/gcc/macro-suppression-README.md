# Unavailable macro tokens across rescans

This bounded direct-preprocessing change preserves suppression on copied tokens.
The unchanged GCC 4.0.4 `combine.c` includes the object macro
`#define gen_lowpart rtl_hooks.gen_lowpart`. After that identifier is seen while
the definition is busy, a later argument/replacement rescan must not expand the
copied member name again.

## Representation and limits

`040-cc-prep.fth` uses a direct-mode, per-process mapping of 5 MiB: one shadow
byte for each byte of the 2 MiB scratch area, then a 3 MiB final-source shadow.
The active source interval is restricted to its selected capacity. Native direct
preprocessing with the default 2 MiB source buffer leaves the remaining source
shadow inactive. Legacy mode neither allocates nor selects shadow storage.

An unavailable identifier is marked at its first byte. Forwarding copies preserve
that mark; new spelling clears the destination mark. Copies read the source flag
before clearing the destination, including same-address copies. Sink push/pop
recompute the selected shadow address, and the existing text bound is checked
before either text or metadata is written. Repeated preprocessing resets active
text/scratch cursors; unused shadow bytes need not be cleared because every new
text write clears its mark. The mapping is cached without growth or retry.
Error 43 covers mapping failure and an active source capacity beyond the shadow.
No control-byte annotation is inserted into the preprocessed C text.

## Deliberate support narrowing

Pasting rejects error 47 if **any byte of either entire raw operand** is marked
unavailable, including a marked identifier away from the pasted edge and an
unavailable operand paired with an empty operand. This is broader than an
edge-token test. Some such cases were previously accepted and matched GCC, so
this is a real narrowing of supported input. A full token/placemarker model is
outside this repair. Unmarked raw operands still support ordinary token pasting.

Three inherited silent mismatches remain and are retained in the independent
review evidence:

- `DEFER(A)()` with `DEFER(id) id EMPTY()`, `EMPTY()`, and `A() 12` emits `12`
  where GCC emits `A ()`; adding an outer identity rescan behaves differently
- `F(x) G(F(x))`, `G(x) #x`, `F(1)` stringifies inserted padding as `"F( 1 )"`
  rather than `"F(1)"`
- `1e+I(A)` is a single pp-number followed by `(A)`, but the inherited scanner
  expands `I` after the exponent sign

An incomplete invocation crossing macro-region boundaries can also reject44.
These results do not establish general C-preprocessor conformance.

## Focused proof

Run serially with a whole-process timeout and at most 1 GiB of address space:

```sh
python3 tests/gcc/macro-suppression-check.py
python3 tests/gcc/macro-suppression-shadow-check.py
python3 tests/gcc/workspace-preservation-check.py --baseline /path/to/frozen/baseline
```

The token oracle uses maximal munch for punctuators and pp-numbers and preserves
literal spelling; it does not erase whitespace before lexing or decode string
contents. Six negative controls distinguish `++` from `+ +`, `>>` from `> >`,
`>=` from `> =`, `##` from `# #`, `1e+2` from `1e + 2`, and `"ab"` from
`"a" "b"`. Forty supported cases compare with GCC, while four unsupported
paste cases verify error47 and existing/absent preprocessing destinations.

The shadow suite tests allocation size and layout, cached reuse, interval ends,
exact and one-past writes, default/native/direct selections, nested sink restore,
preprocess and scratch-lifetime reset, stale-mark clearing, overlapping copies,
and synthetic zero/negative Linux mmap failures. Four in-memory source mutation
controls prove that the fresh-clear, copied-mark, and exclusive-end assertions
actually fail. Existing and absent object/preprocessor destinations survive the
covered early failures; no incomplete object temporary is published.

The preservation helper compares four legacy executables, six native executables,
and an ordinary direct object and runtime-linked executable byte for byte against
an explicitly frozen baseline. It checks runtime-cache identities and artifact
hashes and executes the resulting ordinary programs. Host GCC is only a
preprocessing oracle; it does not supply object or runtime bytes on this path.

The independent review additionally retains 182 maximal-munch GCC comparisons,
eight default-byte comparisons and one same-process mode transition. Its scope
excludes broad gates and the complete original-source compilation.

## Original-source recovery

The separate frozen proof reuses an already completed, unchanged `combine.c`
compilation, rather than repeating it: the 711,720-byte ELF object has SHA256
`0dba592da660bafc644ed524fc441e31395c06f0d5e7f39f05b825fea95eccde`.
Its 144.76-second run used the explicitly historical `a5356f3b` configuration,
with the original-input and all 94 candidate-input hashes unchanged. This proves
that particular original object under that historical configuration; it does
not substitute for a current configure run, census, or full GCC build.

The generic, inherited workspace mapper also accepts the artificial return value
`0x8000000000000000` because its signed comparison has an extreme-value gap.
The same behavior is reproduced on the baseline. That value is not a real Linux
mmap errno return. Actual zero and representative negative errno results are
covered by the shadow tests. No generic mapper change is included here.
