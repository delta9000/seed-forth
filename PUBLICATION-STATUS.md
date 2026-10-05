# Direct GCC branch publication status

**This tree includes two unreviewed candidates.** They were published by request
without independent acceptance. No behavioral validation of the combined tree
has been performed. Mechanical source/book checks are recorded separately below.

## Accepted prerequisite snapshot

The immediately preceding prerequisite snapshot has compiler/runtime identity
`12c19135a6fb7d91825762009da56a887f34859fc78b107e68ae7c88758b6100`
(100 inputs). It retains accepted conditional-expression, runtime, and named K&R
record-definition changes. Its recorded qualification includes 16 top-level
aggregate stages, 118 registered component commands, nine historical/original
supplements and two separately scoped regex checks. Historical nested omissions
remain in those records. Separate c70/12c replays covered 11 book blocks with
14 assertions, 75 macro cases and a ranked-callback executable per identity;
26 supervised wrappers passed. Those results do not validate this later tree.

## Original capacity candidate

- Candidate identity: `7f544e6d642c077cf5f902b1d32504834effdf82ccb6db7e1b4fbf918e74814b`
- Baseline identity: `07ff4f3862cfaa1dcd452eb59f58ec687d564076ad06a8436ddc41cd79237afd`
- Original patch SHA-256: `1349768e38d25caf24c60df824b24675837fabb1eebc6e9867c2defd087910ea`
- Direct-only policy: 10,752 records, 8,192 non-null symbols, 77,824 symbol-string
  bytes, and 21 MiB arena; default/native limits are unchanged
- Recorded author checks: 55 object-capacity cases, 23 arena cases, native/legacy
  preservation, and a separate 16-stage top-level aggregate pass
- Raw original `insn-output.c`, `insn-emit.c` and `i386.c` object runs passed
  under the same candidate identity using historical a535 configuration,
  with structural ELF checks, 600-second/1-GiB per-unit limits and clean shutdown
- Result object SHA-256 values, in that order:
  `ac637ee13860497735823311ba91208367a39909fdd731fa145cfbbc91de878e`,
  `6177861f46998546434357a04422900a33bd5b8a1d3f8844acc4d049903fb2e2`,
  `52571989df6db4cb750596c1fb2fbf548b44641ac3dc22e8f7ffae1dd7bdb26c`
- No independent acceptance or complete component-suite result is claimed

The early measurement narrative in `tests/gcc/remaining-cc1-capacity-README.md`
is retained; the finished author results above supersede its pending-run text.

## Original nested function-pointer candidate

- Candidate identity: `e9d85efea77fcc9138f51799fea22b5e18bfe4a2cb78cabcb685b6cbac05ab8c`
- Baseline identity: `5e4dfdd13538f732dc91052672027153e63463c99a633d1a9164fb6f0c8fcbe5`
- Original patch SHA-256: `cd65b6244f42f13b43582371b681552baae37e16b6a43e00e4b3e85d02b1fd9c`
- Production changes preserve grouped function-pointer depth and reject calls
  through pointer objects; the original author fixtures and runner are included
- Recorded author checks: 131 focused steps, including 25 rejection cases
  across existing/absent object and mapped-output modes, preservation scripts,
  native-byte checks, host O0/O2 comparisons, mixed-link directions and a
  Forth-only executable
- Raw original `except.c` object compilation passed using historical a535
  configuration. This is an object result, not GCC execution
- Independent acceptance is absent; no broad suite was run for this candidate

## Combined publication tree

Compiler/runtime input identity: `4c36494169f28d20410bfc5e4464dcb32b437704ebbd1865c49f85d7c6c8740d` (100 inputs).
Fingerprints use SHA-256 of the sorted JSON mapping from relative input path to
its SHA-256, with Python's default JSON separators. They are not Git commits.

Only the existing five production-file changes were composed onto accepted 12c:
`081-cc-object.fth`, `123-cc-object-program.fth`, `tools/gcc-direct-cc.py`,
`121-cc-sysv.fth`, and `131-cc-aggregate-abi.fth`. Production hunks applied with
zero fuzz; location offsets preserve the later accepted conditional and K&R
changes. Matching canonical book code fences and candidate tests were applied;
book corpus totals and the word index were regenerated for this composition.

Mechanical publication checks: strict byte-identical tangle; 319 numeric claims,
zero warnings or mismatches; current word index; and local-link check. No new
independent engineering review, behavioral suite, broad suite, or original-unit
replay was run against this combined tree. Original candidate outcomes above
remain specific to their original identities.

The original 1,772-byte seed is unchanged (SHA-256
`697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e`).
Vendor Git links are unchanged. The conditional-source pin metadata uses portable
logical roots `historical-a535/config`, `historical-a535/toolchain`, and
`original-gcc`; every recorded hash is retained. No raw build outputs accompany
this source publication.

## Remaining limits

This publication does not establish a complete cc1 object cohort, same-epoch
configuration/generation, linked or executed GCC, source-closed build tools,
bootstrap, or self-rebuild. Structural object checks and individually tested
components are insufficient to establish those outcomes.
