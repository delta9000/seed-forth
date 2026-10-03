# Independent original genmodes review

Accepted within the bounded direct-Forth milestone. The independent gate is
`python3 tests/gcc/review-genmodes-check.py build-out/genmodes-splice-configured build-out/libiberty-splice-configured`.
The retained acceptance report is `build-out/review-genmodes-r6dxzgkx/report.json`;
`tests/gcc/review-genmodes-results.json` freezes the source and evidence hashes.

This establishes the unchanged original GCC 4.0.4 `genmodes.c` and `errors.c`,
the original common and i386 mode definitions, a selected five-member original
libiberty archive with one explicit target-guarded C_alloca adaptation, and the
bounded source-built seed runtime. It does not establish the full default
75-member libiberty build, complete GCC configuration, a GCC compiler, a GCC
fixed point, or general C/runtime conformance.

## Source and build closure

- Upstream commit: `944765863eec87a9f37e297994fd2af960397138`
- Original archive: `091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67`
- Final preprocessor: `465c694b4dda8da81485c5b91cf3537672abb0585f9244aa5d2a6607ed7ea8af`
- Exact i386 definitions: `0141dec67f7141c1f2bb4096ad18fb2a7628f4a7ea5258acd9dc736491c6330d`

The review checks all 25,654 original files/symlinks against the pinned archive,
including the absence of extra source files. The original and adapted source
views differ only in the recorded C_alloca file. Both retained configure runs
use exactly the same frozen compiler source manifest. Generated headers and
compiler inputs are checked again after replay.

The relevant configured GCC object/link rules and all five libiberty object
rules plus its archive rule match the original Makefile.in text exactly.
Their actual retained compilation arguments are replayed, including
`-DIN_GCC -DHAVE_CONFIG_H -DGENERATOR_FILE` for the generator objects and
`-DHAVE_CONFIG_H` for library objects. `CFLAGS= LDFLAGS=` selects supported
flags. The library invocation explicitly overrides REQUIRED_OFILES with
alloca, hashtab, xmalloc, xstrdup and xexit, and clears EXTRA_OFILES/LIBOBJS.
The generator overrides BUILD_LIBIBERTY with that selected archive. The
unmodified configured default lists 75 object inputs; those were not built by
this milestone.

The reviewer copies only frozen toolchain sources into a new directory with no
runtime cache. Forth recompiles all seven original C objects and independently
builds all 11 runtime objects. A fresh Forth archive, index and final link
reproduce the production bytes exactly. Python independently decodes the ELF
symbols and archive members; all required symbols have a source-built provider,
with no unresolved symbols or duplicate providers in this artifact set. An
independent dependency scan selects all five archive members. The final output
uses the actual source-built qsort, allocator, stdio and frame helper.

- genmodes object: `718eac770620b3e59a18c0c7dc8a60a8ba69fa6e5f8033b99bbd5b1317c7c036`
- selected archive: `22faba56ccbe05524d89011ec44c97f95a41b4298c80cc923193a936c7b19388`
- executable: `958451cb28b46c47fd2377ecd2cd84debcf34254cf18538723c9249a19e15cf8`

## Complete output oracle

The independently replayed preprocessor output contains the actual common
machmode.def and computed EXTRA_MODES_FILE input, including XF/TF formats,
all six i386 condition-code modes and target adjustment expressions. No count
or plausible subset substitutes for acceptance.

A separately compiled host GCC 14.2/C90 oracle uses the unchanged pinned
original generator and library C, the same generated configuration facts, and
host libc. Its C_alloca uses the original local-address branch. Host objects,
executables and outputs remain under the private review's host-oracle directory;
none enters the Forth compilation or linking path. All three complete outputs
match byte for byte, including source filenames/line numbers and adjustments.

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| insn-modes.h | 3,522 | `38e7064c77150f337e2504b55992a48c909e002a59adac5367fb8ac6ec2ad813` |
| min-insn-modes.c | 4,589 | `7ea1ddac7e4e7c27c610c4ad8335b122fad1973cc94652c7b14a7c1e18bf633f` |
| insn-modes.c | 16,715 | `bae3d7b8cd9e3794b195bf2d8ac433f31187d683b0109142109decd84c559731` |

All executions return zero with empty stderr. This is exact output evidence for
these original generator modes, not an exhaustive compiler or libc test.

## C_alloca and configuration facts

The exact patch is independently applied with fuzz disabled and checked against
its before/after hashes. Only `__SEED_FORTH__` selects the private saved-parent-RBP
helper. The helper is a frameless `mov rax,[rbp]; ret` leaf; its private ABI
requires the Forth caller and parent to preserve their RBP frame chain. The
upstream allocation list, sizes, deeper-frame reclamation, C_alloca(0), stack
direction discovery and non-seed branch remain intact.

A replay using the actual allocator verifies same-frame, nested-argument,
callback and recursive lifetimes. A separately linked observation allocator
checks exactly 13 allocations and 13 frees, poisons freed storage, and rejects
premature, duplicate and unknown frees. The observer never enters production.

The review verifies and reexecutes the original native endian probe, checks the
successful original ANSI/mkdir probes, and reexecutes all five original size
binaries: pointer 8, short 2, int 4, long 8, long long 8. BYTEORDER is 1234;
WORDS_BIGENDIAN, HOST_WORDS_BIG_ENDIAN and MKDIR_TAKES_ONE_ARG are absent. The
six conservative HAVE_DECL results for malloc/realloc/calloc/free/strstr/snprintf
remain zero after the unsupported declaration-probe form fails. Their original
fallback and actual runtime declarations have identical return/parameter types.
Missing runtime interfaces and other configure limitations remain outside this
bounded acceptance; configure exit zero alone is not an acceptance claim.

## Rejected earlier output

The earlier corrected-computed-include composition with preprocessor hash
`4510f0499c350533a1d8c8059616f8a9b270c2b6ee863db5599a61fe1d3ccfb4`
passed source/link closure but failed every whole-output comparison because
backslash-newline inside string literals emitted extra newline bytes. That
failure is preserved at `build-out/review-genmodes-q970wdi3/report.json`, together
with complete diffs and the exact review script snapshot. No earlier output is
accepted by this report. The final splice-fixed run above passes the same gate.
The still earlier object which silently omitted the computed i386 definitions
is also outside this acceptance.
