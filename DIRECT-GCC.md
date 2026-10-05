# Direct Forth to GCC: work in progress

This branch develops an optional direct route from the repository's Forth C
compiler to GCC 4.0.4. The starting point is the merged, tested TinyCC route at
`550a0c58013de600f2bc2a7347baf16cd5d7b536` (PR #9). This branch does not yet build
GCC. Work below is a reconstruction; the earlier unpublished implementation is
not present in this checkout.

## Goal and boundary

A reader should be able to follow each step from the annotated seed and a bag
of pinned source archives to a working GCC, then use the existing kernel ladder.
The machine boundary remains AMD64 Linux and the existing 229-byte hex0
assembler plus the 1,772-byte Forth seed. The new route will implement C parsing,
code generation, object emission, and linking in Forth. Host C compilers may
provide independent test oracles; they must not provide bootstrap artifacts.

The first GCC source target is the original 4.0.4 tree at
`944765863eec87a9f37e297994fd2af960397138`. Original source provenance, licenses,
configuration probes, generated-file ancestry, and failure limits belong with
each executable proof. Successful compilation of selected source files is not
a complete compiler bootstrap or a self-rebuild.

The present development recipes still use host Python, a POSIX shell, Make,
and text utilities for orchestration and source-driven configuration/header
rules. Their commands and generated inputs belong to the retained evidence.
The focused proofs establish Forth C compilation, object construction,
archives, and linking; they do not yet establish a bootstrap of those build
tools. Closing that dependency chain is part of the source-only route.

## Stages

1. Add an isolated AMD64 System V ABI and ELF relocatable-object mode, with a
   small Forth linker. Preserve the existing native/TinyCC route.
2. Define the supported C dialect and implement shared type, layout, expression,
   call, aggregate, floating-point, and variadic semantics as measured sources
   require them. Unsupported cases must diagnose rather than silently degrade.
3. Supply a bounded, source-built runtime with true headers and implementations.
   Compile original GCC generators and regenerate their inputs from sources.
4. Execute genuine configuration probes and original build recipes. Compile the
   complete cc1 translation-unit cohort under one compiler/runtime epoch,
   inspect unresolved symbols, link, and execute real compiler tests.
5. Close the assembler, linker, runtime, and driver dependencies, rebuild GCC,
   and run integration and bootstrap comparisons. Document the later handoff.

Each stage needs an executable proof and an explanation of its invariants.
A small explicit internal representation may help later retargeting; this work
currently targets one native ABI and does not implement a virtual machine.

## Checkpoints and verification

The reconstructed Forth object writer, static linker, scalar System V mode,
relocatable storage, typed integer constants, and source-built runtime have
focused executable proofs. Separate C units share globals, string and function
addresses, genuine array typedefs, and variadic argument lists. The unchanged
GCC libiberty `ffs.c` and `hex.c` execute through the Forth object/linker path;
`hex.c` uses the original GCC headers. Host tools supply independent behavioral
and ABI comparisons only.

The runtime currently supplies allocation, memory/string operations, unbuffered
streams, and integer/pointer/string formatting. Historical ANSI headers use an
explicit bounded C90-oriented target profile. Binary64 literals, expressions,
storage, returns and named/outgoing scalar arguments have executable proofs. Integer/pointer record values
now cross the System V INTEGER/MEMORY boundary with checked identities,
register rollback, independent copies and hidden result pointers. GP and XMM
banks share an explicit call plan with independent exhaustion and one stack
argument order. Long-double arguments, floating-member record values
and aggregate variadic calls remain
unsupported; accepting declarations or taking `sizeof` does not implement those
value operations. The original GCC configure
probes now support a bounded, independently audited generator configuration.
Original `gencheck.c`, `gengenrtl.c`, and `errors.c` compile through actual
Makefile object rules and run with the Forth-built runtime. `gencheck` emits
all 164 source-defined checks; both complete `gengenrtl` outputs match an
independently host-built original generator. Those first two focused links
omit unused `BUILD_LIBIBERTY`. The subsequent `genmodes` proof builds seven
original C units, selects five original libiberty members into a real Forth
archive, and links with the Forth runtime. It consumes the complete i386 mode
definitions; all three outputs match the independently host-built original
generator byte-for-byte. Its source-closure review and later integration replay
identify their exact compiler and configuration inputs. This selected archive
does not claim the full 75-member library. A complete GCC build and self-rebuild
remain unfinished.

`tests/gcc/baseline-20261003/` records a fresh independent replay of the
surviving baseline, including the actual raw-input direct TinyCC fixed point.
Those results apply to its named source commit. New component tests are in
`tests/gcc/`; run `bash tests/gcc/check.sh` for their current combined gate.
Passing component tests alone does not prove all supported C semantics or
complete source/bootstrap closure.

Commit source, tests, and this status on this branch in small increments before
lengthy validation, then commit the measured results. Verify the remote commit
before considering a checkpoint durable. Preserve additional reviewed work
manifests in the private checkpoint repository. Local build directories are
scratch space, not backups.

## Runtime and parser-generator recovery at 2026-10-03 20:53 UTC

The original 13-unit oyacc 6.6 parser generator now compiles and links with
the Forth compiler and source-built runtime. Its real configure probes select
the provided declarations and upstream fallbacks. Parser C, token header and
automaton report match an independent build of the unchanged original source.
Real signal delivery removes its temporary files and preserves inherited
ignored signals. Generated-parser execution is a separate preprocessor gate.

The subsequent composed gate also executes the generated parser: its unchanged
`#line` directives are handled by the Forth preprocessor, and ten arithmetic
and error cases agree with an independent host build. Logical source locations
remain separate from physical include lookup. A systematic independent sweep
checks supported directive forms against host tokens and locations, while
unsupported splice/comment forms fail explicitly and preserve previous output.

Runtime entry initializes the program name before `main`; the raw startup
object remains available independently. The bounded runtime now implements
descriptor-backed streams, exclusive temporary files, unlink and immediate
exit. Independent tests cover failed allocation/syscalls, partial entropy,
collisions, descriptor ownership and flags, and entry ABI. The driver places
startup first and a Forth-built runtime archive last, allowing an original
package to supply its own complete `getopt` object. Strong duplicate symbols
still fail. These changes passed focused owner and independent composition
checks; the expanded combined component gate is pending on this checkpoint.

The restored baseline at `14a09df78d02da8f12afca98609239848f001b71` passed a
fresh component replay after seed recovery. Two explicit skips were the absent
historical preprocessor byte fixture and the optional original `vasprintf`
test requiring a separately retained configuration. The later runtime changes
are identified separately; previous hashes do not validate modified sources.

The reviewed aggregate stage also closes inherited record-to-scalar initializer,
unevaluated unary-plus, and void-return constraint gaps. Its independent
bidirectional tests cover byte sizes 1–33 and 264 argument layouts, including
callbacks, protected-page tails, nested result lifetimes and the hidden result
pointer returned in RAX. These are ABI and language-subset proofs. Selected
original GCC record-return wrapper bodies run with explicit test shims; the
complete GCC `real.c` unit and compiler bootstrap are not established by them.

## Verification scope at 2026-10-03 16:43 UTC

The accepted frozen compiler/runtime composition through implicit calls and
reviewed source-location macros passed the expanded direct-GCC component gate
and all sixteen `check-all.sh` steps. This includes both architecture handoffs,
book examples and consistency checks, the original default bootstrap, native
regressions, and the actual raw-input TinyCC executable/object fixed points.
The seed and TinyCC hashes remain unchanged. All 941 source files and 2,373
copied vendor files were rehashed after the final run; the exact source map
and test limits are in `tests/gcc/checkpoints/accepted-20261003T1643.json`.

The first full replay found a missing loader helper in the book-example
sandbox and missing vendor Git metadata in the isolated validation copy.
The helper-copy repair passed all 54 examples; adding the already pinned Git
metadata restored the handoff provenance queries. The repeated full aggregate
then passed. Neither repair supplied target compiler artifacts.

The newer archives, qsort, binary64, bitfields, declarator repairs and
preprocessor continuations are outside that full-pass composition. Their
focused owner and independent checks identify their own source hashes;
integration gates must cover them before a broader claim.
Configuration audit reports preserve the initial false endian/mkdir answers
as failed evidence, followed by the corrected original-probe replay. Full
GCC compilation, self-rebuild, `verify.sh`, and QEMU execution remain unclaimed
for this direct-GCC branch.

Run the repository's applicable aggregate checks against the final composed
source state. Report passed, failed, skipped, and never-run checks distinctly.
No prior unpublished hash or historical test observation validates reconstructed
source bytes. A remote commit that is not reachable from a branch is temporary
preservation only and may be garbage-collected; verify the branch reference
before describing any checkpoint as published.

## Initial direct compiler arena bound

The initial direct-GCC Python driver requested a fixed 16 MiB anonymous compiler
arena per translation unit. The original generated GCC 4.0.4 `c-parse.c` consumed
10,802,584 bytes in a diagnostic-only measurement; 16 MiB is the next power-of-two
bound above that measured 10.3 MiB requirement. The old 8 MiB request failed at
8,388,760 requested bytes. This does not raise other compiler limits or add
automatic growth, retries, an environment override, or a runtime heap.
The legacy 32 KiB arena, TinyCC's 8 MiB request, and original seed are unchanged.
The later complete `c-typeck.c` measurement raised the direct arena to 17 MiB;
the remaining original `insn-emit.c` measurement raises it to 21 MiB. The
other mapped tables and unchanged default bounds are listed in
[the workspace proof](tests/gcc/workspace-capacity-README.md).
Allocation exhaustion and mapping failure still diagnose error 10 before the
driver publishes output. The driver source participates in the runtime-cache
identity, so this policy change selects a new source cache.

`tests/gcc/arena-capacity-check.py` checks the bound, alignment, overflow,
mapping failure, publication, cache identity, and small legacy/native outputs
serially. The original-source replay and input provenance are described in
`tests/gcc/arena-capacity-README.md`; a successful parser object is not evidence
of a linked GCC compiler or a full same-epoch bootstrap.

## Public Linux mapping boundary

The bounded runtime now declares and implements private `mmap` and `munmap`
in `sys/mman.h` and supplies the existing signed-long `SSIZE_MAX`. This closes
the measured missing-header surface in complete original GCC `host-linux.c`.
Its original configuration remains a distinct historical input; supplying a
new header does not silently flip its recorded configure answers. See
`runtime/gcc-seed/MAPPING.md` and `tests/gcc/mapping-check.py` for the supported
flags, real syscall ownership, complete kernel-error interval, source pins,
and separate Forth production/host oracle proof. This does not establish a
linked GCC PCH implementation or a full compiler bootstrap.

## Two-dimensional inline record fields

The explicit direct target now retains both fixed dimensions of scalar and
record array fields, as required by the original `convert_optab.handlers`
declaration in GCC 4.0.4 `optabs.h`. Member expressions, row strides, padded
record layout, initialization, `sizeof`, and static relocatable addresses use
the complete shape. The existing one-GiB object bound covers array products,
enclosing record sums and final padding, including trailing bitfields. Treating
an entire matrix as a record, or further subscripting a scalar element, now
diagnoses.
Legacy/native field layouts and the original seed remain unchanged.

The focused [matrix gate](tests/gcc/multidimensional-record-README.md) includes
Forth-only execution, independent O0/O2 layout and bidirectional ABI tests,
rejected shapes and initializer bounds, and optional exact original-declaration
and legacy/native byte-preservation proofs. Qualified array-pointer formation
and dimensions beyond two remain unsupported; full qualifier enforcement and
floating-value support are not introduced here. General pointer constraints
remain incomplete, including the inherited unary-plus-on-pointer gap.
A declaration proof does not establish successful compilation or linking of
the complete GCC translation
unit. Final composed component and bootstrap gates remain separate checks.

## Scalar binary32 value stage

The direct SysV target now carries binary32 scalar values with their actual
four-byte storage and SSE single-precision arithmetic. Integer conversions,
float/double conversions, usual arithmetic types, scalar parameters/returns,
and outgoing default argument promotion are implemented. The independent
O0/O2 gate is `tests/gcc/binary32-values-check.py`. Decimal f/F literals,
long double computation (see "Long double data movement" below), K&R float
parameter definitions, static floating initializers,
floating ++/-- and floating-member record ABI values remain checked boundaries.
Mixed-floating conditionals use the later selected-arm stage described below.
The unchanged full GCC 4.0.4 `ggc-page.c` translation unit compiles with this
stage using the separately identified earlier configuration. This removes
one source-measured blocker; it does not establish a GCC executable, a
same-epoch configure replay, or a full bootstrap. Native/TinyCC defaults and
the 1,772-byte seed are unchanged.

## Continued macro parameter lists

The explicit SysV preprocessor now reads LF/CRLF continuations inside bounded
macro parameter lists, including joined parameter names, without rewriting
physical source or losing newline provenance. This repairs original GCC
`c-common.c:3237`'s `DEF_BUILTIN` failure; malformed and duplicate names diagnose
47, the existing 16-name limit diagnoses 48, and temporary logical-name storage
is bounded at 64 KiB. Native and default readers remain on their prior path.
See [the focused proof](tests/gcc/macro-parameter-splices-README.md) for exact
source pins, independent host comparisons, and remaining lexical boundaries.
A replay against an earlier configuration is a distinct compiler/config pair,
not a same-epoch cohort or a complete compiler bootstrap.

## Measured c-common object tables

Complete original `c-common.c` now compiles under the separately retained a535
configuration with fixed direct-only mappings for 10,240 stable records and
6,656 ELF symbols plus the reserved null row. Diagnostic serialization measured
9,866 records and 6,282 non-null symbols before those 512-row-rounded policies
were selected. Its 60,259 string bytes and 13,556 relocations fit the unchanged
bounds. Default/native capacities and the seed remain unchanged. See the
[object-capacity proof](tests/gcc/object-capacity-README.md) for measurement,
independent ELF/linker checks and exact source/configuration distinctions.
Successful compilation of this unit does not establish a same-epoch cohort,
linked cc1, compiler execution or self-rebuild.

## Selected-arm conditional values

The direct SysV scalar join computes a common type and converts only the
selected arm. This removes the mixed double/integer MIN blocker measured in
unchanged GCC 4.0.4 `ggc-common.c`. It also preserves the pointer type and record
descriptor of `condition ? (void *)0 : pointer`, in either operand order,
removing the corresponding measured `tree-ssa-loop-im.c` blocker. Runtime
void* values still yield a void* common type; runtime integers and comma-zero
expressions are not null pointer constants.

`tests/gcc/conditional-values-check.py` checks arithmetic common types, both
arm orders, nested binary32 rounding, signed/unsigned boundaries, signed-zero
and quiet-NaN payload preservation, one condition evaluation, lazy branches,
array/record/function pointer descriptors and aggregate copy joins. Host C90
O0/O2, bidirectional mixed-ABI and Forth-only tests are independent checks.
The native/TinyCC path retains its prior join layout and a focused native
expression executable remains byte-identical to the immutable a09 baseline.

Null provenance is deliberately bounded to numeric/character zero literals,
grouping, and integral zero casts optionally ending in unqualified void*. General zero
integer constant-expression folding (such as 1-1) and general scalar const-write
enforcement remain unsupported in the runtime parser. This is a source-driven
component repair, not a claim of full C conditional conformance or a same-epoch
GCC census. See `tests/gcc/conditional-values-README.md` and its source pins.

A subsequent provenance correction excludes qualified void-pointee zero casts
from null-pointer-constant recognition. It passes the saved cast target's
qualifier flag across nested operand parsing. Qualified integer zero casts
remain accepted. Because the qualifier representation is flattened, top-level-
qualified void-pointer zero casts conservatively retain a documented host-valid
rejection boundary. The dedicated qualified-null gate distinguishes those
boundaries from invalid record/array/function-pointer provenance.

## Ranked array repair at 2026-10-04

The unchanged original `tree-ssa-loop-ivopts.c` now compiles through the direct
Forth object path. Its four-dimensional local static `costs` declaration had
reached a two-suffix declarator boundary (205). Checked recursive array element
types retain each dimension, alignment, initializer traversal, static address
and pointer shape without adapting GCC source. The direct profile checks
64 written/typedef-composed dimensions and the existing 1 GiB object limit.
Qualified array-pointer construction and grouped ranked-array declarators fail
closed at their documented boundaries. Inferred nested arrays retain their
existing requirement for braced outer elements.

Focused host O0/O2, mixed caller/provider and Forth-only tests cover ranked
integer/pointer arrays and 3/16/64-byte by-value records; unsupported floating
record leaves remain explicit errors. Independent review found and closed
aggregate-leaf classification, qualified parameter adjustment, inferred-row
counting and grouped function-pointer shape gaps. See
`tests/gcc/ranked-arrays-README.md` for the bounded profile and executable
checks. This is translation-unit compilation and language/ABI evidence, not
a linked or executed GCC compiler, full cohort replay or bootstrap.

## Four measured runtime symbols

The incomplete historical a535 cc1 object inventory identified absent access,
getpid, strpbrk and strspn implementations. The bounded runtime now supplies
real Linux AMD64 permission/PID syscalls and unsigned-byte prefix/search loops,
with exact public types and errno semantics. The focused
[contract and proof](runtime/gcc-seed/MEASURED-INTERFACES.md) separates Forth-only
production from independent host libc/source and bidirectional ABI oracles.
The focused owner gate passed 68,010 string vectors, real permission/PID
contracts, all kernel errno values, and independent O0/O2 bidirectional ABI
checks on source identity 80667d6474e2fd7e0b703ed1f00db2be929e2bf3d4a8bc8cf9600c2d4c38a05c.
Independent review additionally passed dual read-only string guards and real
fork-child PID checks. All 38 prior runtime objects and the ordinary runtime
executable remain byte-identical to frozen07ff. The initial reverse-ABI harness
link failure and test-only stdout correction are retained separately. This does not establish a complete cc1 link, new
configure epoch, GCC execution or bootstrap. setbuf remains a separate
stream-contract decision; compiler layers and the seed are unchanged.

The focused gate's serial supervisor additionally records failing launch and
timeout attempts before propagating errors, including exact limits, timing,
outputs and owned-process-group termination/reaping. Its controlled failure
proof remains separate from runtime successes. This verification-only repair
does not alter the runtime identity or the original seed.

## Measured working-directory and NULL-buffer interfaces

The runtime now implements caller-buffer getcwd with real Linux AMD64 path,
termination and errno behavior, and the measured NULL-buffer setbuf operation
with truly unbuffered streams. GNU allocating getcwd forms and the kernel's
long-path limit are explicit boundaries. Non-NULL setbuf requests terminate
immediately and silently with status 127 rather than pretend to enable buffering. See
[the bounded contract](runtime/gcc-seed/DIRECTORY-BUFFERING.md) and
`tests/gcc/directory-buffering-check.py` for focused production, host and ABI
checks. Genuine configure selection is separate pending work; the historical
fallback is not removed by forced macros. Compiler layers and the seed remain
unchanged. No full cc1 link, execution or bootstrap is claimed.

The final silent-exit implementation passed owner and independent focused
checks on identity c70c6ebcaf673a277880a439fadc04d1bded98b2d62784a4715583b84868336a.
An earlier diagnostic-writing design failed real SIGPIPE/SIGXFSZ tests and
was replaced rather than accepted. Full blocking stderr, exact kernel path
bounds and public-call ABI cases now pass; all 42 previous runtime objects
and the ordinary runtime executable remain byte-identical to frozen 80667.

A fresh genuine libiberty configure run on c70c6e now detects getcwd and removes
its fallback from the effective 72-member selection. The original getpwd and
three allocation/exit support objects compile through their Makefile rules,
link with the runtime, and return the exact cwd with false PWD. The retained
old-configuration fallback comparison still exposes getwd; no forced macro or
original source replacement removes it. The full archive and coherent GCC
pipeline remain separate pending work.

## C90 record-definition entry

Identifier-list definitions now use their refined record types with the existing
INTEGER/MEMORY entry transport. Compatible prior prototypes remain visible;
aggregate calls without a prototype, aggregate variadics, binary32/binary64-member
records, long double computation and K&R float-entry conversion remain unsupported. Empty-list record
result definitions retain their previous rejection. The focused gate is
`tests/gcc/knr-record-check.py`.
The source demand is original libiberty `regex.c`'s `group_in_compile_stack`.
The focused owner and independent gates pass on compiler/runtime identity
12c19135a6fb7d91825762009da56a887f34859fc78b107e68ae7c88758b6100. Owner coverage
includes record byte sizes 1--33, ninety-nine argument layouts, bidirectional
host O0/O2 calls and twelve byte-identical prior object/default/native controls.
The independent fixtures add padded/nested/union records, following prototypes,
register rollback and raw hidden-result address/canary guards.

The complete original `regex.c` compiles unchanged under both the retained
historical and genuine c70 libiberty configurations, yielding identical objects.
Its raw alloca integration remains unresolved. A separate, explicitly configured
upstream `REGEX_MALLOC` build runs thirty bounded behavior cases against host
O0/O2 original-source builds using the same mode; no source/config is rewritten.
The reproducible test is `tests/gcc/knr-regex-check.py`. This closes the measured
raw compilation failure and supplies a separate bounded behavior witness. It
does not establish a complete libiberty archive, cc1 link, GCC execution or
bootstrap; the incomplete cc1 projection does not establish regex criticality.

## Remaining original object-table bounds (unreviewed)

The direct-only profile selects 10,752 stable records, 8,192 non-null ELF
symbol rows, a 77,824-byte symbol-string slice, and a 21 MiB arena. Default
and native limits are unchanged. The original capacity candidate's author
runs compiled raw `insn-output.c`, `insn-emit.c`, and `i386.c` with historical
a535 configuration, with structural object checks. These outcomes belong to
the original candidate identity, not this combined tree. See
[publication status](PUBLICATION-STATUS.md) for identities, test scopes, and
the missing combined behavioral validation.

## Long double data movement

Original binutils 2.30 `bfd/bfd.c` declares `union _bfd_doprnt_args` with a
`long double ld` member and fetches `args[i].ld = va_arg (ap, long double)`
unconditionally; formatting it is under `HAVE_LONG_DOUBLE`, which bfd's
configuration leaves undefined. The System V target now carries `long double`
as an ABI-correct data type without x87 arithmetic: sixteen bytes, sixteen
alignment, GCC's record/union/array layout, copies of whole objects, named
and unnamed arguments in sixteen-aligned stack slots, `va_arg` from the
sixteen-aligned overflow area, and results in `st(0)` (`fld`/`fstp tbyte`).
Records of exactly sixteen bytes holding only long double leaves are X87 and
return in `st(0)`; other records containing long double are MEMORY.
Arithmetic, comparison, conditions, conversions and casts to or from other
types, and static initializers fail with `long-double: cc: line N: error
249`; `L` literals keep error 248. The focused gate is
`tests/gcc/long-double-check.py`: host O0/O2 and Forth-built units call each
other both ways, values made by host arithmetic and explicit bytes (including
signaling NaN) are compared over their ten significant bytes, layouts match
host GCC, and 34 rejected operations preserve outputs. With the stage-B
configured bfd directory and its recorded arguments, `bfd.c` compiles to an
object; later link and behavior remain separate. See book chapter 48 §4.
