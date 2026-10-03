# Corrected original configure and gencheck audit

The frozen rerun `build-out/direct-configure-l0h5udxy` repairs the three original
probe failures relevant to the first generator: the original ANSI compilation
probe succeeds, the original native endian program compiles and exits 0, and
the original two-argument mkdir compilation probe succeeds. GCC now generates
`BYTEORDER=1234` without `WORDS_BIGENDIAN`, `HOST_WORDS_BIG_ENDIAN`, or
`MKDIR_TAKES_ONE_ARG`. No configure answer or original probe was rewritten.

The exact original C-only `gencheck` is independently reproduced again. This
accepts those bounded probe/generator facts. It does not claim complete GCC
configuration, libiberty/archive closure, a GCC compiler or a fixed point.
The source-location implementation review is separate; this audit does not
infer its outcome. The first-run failure report remains preserved in
`gcc-direct/probe-audit.md` and its immutable diagnostic snapshot.

## Frozen inputs and exact outcomes

- GCC commit: `944765863eec87a9f37e297994fd2af960397138`
- Original archive SHA-256:
  `091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67`
- Frozen toolchain manifest SHA-256:
  `7ef79af64b40defe44950837ea13ed080b7ec870acc88a3b14b532b84a9ec05a`
- Original configure report SHA-256:
  `b4129aade544e4331340a440961ee77f041a949ba61d13ccadfd326fdae8c762`
- Generated `auto-host.h` SHA-256:
  `988e1395e3b75944ed53a0425fb3080272f02c8c43d231fec89d81548f0b7fef`

Original configure exits 0. Its retained inventory contains 172 invocations:
35 successful and 137 nonzero. Exact statuses: 0:35, 2:12, 30:36, 93:4,
143:39, 205:2, 238:1, 253:43. Later generator traces are not counted.

| Original probe | Retained trace | Actual result |
|---|---|---|
| Complete ANSI compilation test, including abstract callback parameter | `1791044199985880699-s_qdj5f5` | Compile 0; `ac_cv_prog_cc_stdc` is genuinely empty, rather than `no`; the five failed alternate-option attempts disappear |
| Native endian test with undeclared `exit` | `1791044225653192537-9b3z1sk0` | Compile/link 0; independent execution of the exact retained executable exits 0 with empty stdout/stderr |
| Two-argument mkdir compilation test | `1791044285484578074-chvdeym_` | Compile 0; GCC declines its one-argument rewrite; the compile-only probe does not promise a runtime mkdir implementation |
| Native getgroups argument test | `1791044246081882810-zm_cfpcs` | Link 253; `getgroups` is absent from actual runtime object symbols; `GETGROUPS_T=int` remains an unmeasured fallback for a later fixproto consumer |
| `%p` sprintf/sscanf round trip | `1791044246518145890-d5h9xu9i` | Link 253; `sscanf` is genuinely unavailable; GCC retains its supported long-integer formatting fallback |

All 25,654 original source entries, archive bytes, frozen compiler/runtime
sources and captured probe input/output/stdout/stderr hashes are checked.
The five original size binaries are reexecuted and reproduce pointer 8,
short 2, int 4, long 8 and long long 8. The independent frozen-toolchain fixture
again establishes little-endian bytes, signed eight-bit char, LP64 scalar
alignment, the bounded stat structure, and the declared target macros:

```text
sizes 1 2 4 8 8 8
alignments 2 4 8 8 8
bytes 8 1 1 0
stat 144 8 24 48 72
types 4 0 8 1 4 1
```

The compiler continues to expose its C90-style target mode without `__GNUC__`,
`__STDC_VERSION__`, or hosted-libc claims. Passing the exact original ANSI
compilation probe is not represented as general ISO conformance.

## Conservative declaration results

All six present interfaces `malloc`, `realloc`, `calloc`, `free`, `strstr`, and
`snprintf` still fail the original grouped-pointer/function-to-object-pointer
declaration test with status 143. Their `HAVE_DECL_*` values remain 0. The
audit checks the actual frozen runtime declarations against the fallback
declarations in original `gcc/system.h`; their return and parameter types
are identical, differing only in parameter names and whitespace.

These conservative fallbacks do not introduce an ABI mismatch and are not a
blocker for this generator. The optional target extension used by those probes
need not be implemented solely to turn the answers positive. The other missing
function and header answers are still bounded runtime limitations; runtime ELF
symbols are enumerated from hash-verified objects rather than inferred from
headers or success stubs. The corrected getgroups and sscanf cases now reach
real missing-symbol link failures instead of the prior undeclared-call errors.

## Exact original generator

The audit verifies unchanged original source/archive inputs, snapshots generated
headers before replay, reexecutes the original Makefile object arguments with
the frozen driver, links through the actual bounded runtime, and verifies the
headers again afterward. C-only `lang_tree_files` is empty and the original
Makefile correctly generates empty `gencheck.h`; original `gencheck.c` itself
includes both `tree.def` and `c-common.def`.

- Original object SHA-256, unchanged from the first run:
  `eed194c7d8e7ba473130836b5bcccb2dd02e649bd496dde72830f2e36d595980`
- Corrected executable SHA-256:
  `031ed79fb660bad03df3c168f821bdf71a1702e7cfb10357c28a670d14552e77`
- Output: 164 unique tree-code checks, 9,675 bytes, SHA-256
  `911a211b76f293fb5c7863cfb6bd82ad71da3956d130fdf56fe9487387e062f3`
- Normal execution status 0; usage status 1 with `Usage: gencheck\n` on stderr

Every output byte matches an independent extraction of the original .def
entries in order. The focused link deliberately omits the original full
Makefile rule's `BUILD_LIBIBERTY`; no full archive/link closure is inferred.
No host compiler, assembler, linker or libc contributes target code.

## Reproduction and evidence

```sh
python3 tests/gcc/configure-audit-corrected-check.py build-out/direct-configure-l0h5udxy
```

- Combined independent report:
  `build-out/configure-audit-corrected-vetkv2hs/report.json`
- All configure sources/statuses, runtime symbols and layout evidence:
  `build-out/configure-audit-7ikptj_g/report.json` and `verified-probes.json`
- Independent original generator replay and generated-header copies:
  `build-out/configure-audit-gencheck-2rd8is78/report.json`
- Publication handoff source/evidence manifest:
  `tests/gcc/configure-audit-corrected-run.json`

These evidence directories and the original frozen toolchain are retained.
The source/evidence manifest records exact SHA-256 values; none of the
provisional first-run artifacts has been replaced by the corrected run.
