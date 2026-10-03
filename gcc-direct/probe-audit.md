# Original GCC configure and gencheck audit

The first original `gcc/configure` run completed, but its generated configuration
is **not accepted as faithful**. It records big-endian words on this little-endian
AMD64 target because the compiler rejected an undeclared call to `exit`.
`MKDIR_TAKES_ONE_ARG` has the same kind of unsafe success-on-failure fallback.
The independently reproduced original `gencheck` output is a useful, narrower
result; it does not validate these configuration answers or the GCC build.

## Frozen evidence and reproduction

Audited on 2026-10-03, in `build-out/direct-configure-imvvopu0`:

- GCC release commit: `944765863eec87a9f37e297994fd2af960397138`
- Archive SHA-256: `091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67`
- Source manifest: 25,654 original source entries, verified against the retained
  `gcc-source-inputs.json`; archive bytes verified separately
- Frozen toolchain manifest SHA-256:
  `1d23162bb65cfcb4e2feabe03c00fa47b66950819678674a82c44f72bdb8af9b`
- Configure invocation inventory SHA-256:
  `fc776c59c044100c56c5d3f19c1cafb8716a6bf6b7f40f6bc5867e31ab3704f9`
- Original `auto-host.h` SHA-256:
  `0dc4ea80d5b287662386940cbe43e71208102de8312e453a453e868f1c84f0e2`

Configure returned 0. Its terminal inventory contains 177 invocations: 32 with
status 0, 145 nonzero. Exact status counts are 0:32, 2:17, 30:36, 93:8, 143:39,
144:1, 205:2, 238:1, 253:41. Subsequent generator invocations share the `probes/`
directory; they must not be added to the configure count.

The repeatable audit commands are:

```sh
python3 tests/gcc/configure-audit-check.py build-out/direct-configure-imvvopu0
python3 tests/gcc/configure-audit-gencheck.py build-out/direct-configure-imvvopu0
```

Retained independent evidence:

- `build-out/configure-audit-k79ms3z9/report.json`: full input/artifact hashes,
  exact compiler/program statuses, size-program replays, target layout/macros,
  diagnostic variants, and actual defined runtime ELF symbols
- `build-out/configure-audit-k79ms3z9/verified-probes.json`: every captured
  configure source body, arguments, status, diagnostic, and input/output hash
- `build-out/configure-audit-gencheck-9qoxolfo/report.json`: independent original
  generator replay, generated-header snapshots, source definitions, and output

The audit never edits original GCC sources, generated configuration, probe
inputs, compiler layers, driver, or runtime. Diagnostic variants live only in
the audit output directory and are not configure answers. All tested target
code is produced by the frozen Forth toolchain and bounded runtime; no host
compiler, assembler, linker, or libc supplies target code.

## Unsafe answers and conservative failures

Line references below refer to the pinned original GCC source tree, not a
regenerated configure script.

| Answer | Captured evidence and original branch | Assessment and impact |
|---|---|---|
| `WORDS_BIGENDIAN=1`, `HOST_WORDS_BIG_ENDIAN=1`, `BYTEORDER=4321` | Trace `1791043168952662067-g_zmsyy0`, compile status 93; `gcc/configure:8436` runs the native union test, and `:8475` assigns `yes` after *any* compile/link/run failure; `:8516` emits the macros | False positive. The original probe has no `exit` declaration. Prepending only `void exit(int);` makes the same program compile and exit 0. The independent layout fixture reads bytes `1 ... 0`. Anonymous local union support is not the fault. Correct the language implementation and rerun original configure; do not patch the generated endian answers |
| `MKDIR_TAKES_ONE_ARG=1` | Trace `1791043227183731165-2ah5lcme`, compile status 93; `gcc/configure:11773` compiles `mkdir("foo",0)`, then `:11830` selects `yes` after failure | Unsupported ABI claim. Frozen runtime has neither declaration nor symbol for `mkdir`; adding a diagnostic two-argument prototype makes compile-only status 0. `gcc/system.h:506` rewrites `mkdir(a,b)` to `mkdir(a)`, so this answer is unsafe when such calls become reachable. Compiling the two-argument probe will not establish runtime symbol availability |
| ANSI C option: `none needed` | Base ANSI probe `1791043142164451132-2zpwja98` fails 144; five alternative flag invocations fail 2. `ac_cv_prog_cc_stdc=no`; `gcc/configure:2607` prints `none needed` for both the empty string and `no` | Misleading progress text from original configure, not a successful ANSI compilation probe or an ISO conformance result. The abstract unnamed function-pointer parameter is the recorded blocker |
| `GETGROUPS_T=int` | Trace `1791043189048860638-p0hm0rft`, compile status 93; native probe at `gcc/configure:9294`, failure assignment at `:9339` | Fallback, not measured getgroups argument ABI. Runtime has no `getgroups`; `gid_t` is actually unsigned 32-bit. `gcc/configure:9372` propagates this native result to `TARGET_GETGROUPS_T`; `gcc/Makefile.in:2897` substitutes it into `sys-protos.h` for fixproto. It is not a `gencheck` input. A later consumer must establish the actual interface or remain unavailable |
| `HAVE_DECL_STRSTR`, `SNPRINTF`, `MALLOC`, `REALLOC`, `CALLOC`, `FREE` = 0 | The six original declaration probes fail 143 at the grouped pointer declaration/cast `char *(*pfn) = (char *(*)) name;`; all six names are declared by the frozen runtime headers and defined in the actual ELF objects | Conservative false negatives. The grouped declarator is valid pointer-to-pointer syntax; the function-to-object-pointer conversion is a target extension, not required ISO C90 behavior. `gcc/system.h:363,391,399,403,407,442` supplies signature-equivalent fallback declarations. These six values do not force an ABI mismatch and need not block `gencheck` or compel implementation of that optional conversion |
| `HAVE_DECL_ABORT=1` | Trace `1791043195603919679-7vc3ceed`, compile status 0. `gcc/system.h:579` defines `abort()` as `fancy_abort(...)`, so the probe's `#ifndef abort` body is skipped | Correct as a macro-presence answer, not evidence for libc `abort`. The runtime has no `abort` symbol. `fancy_abort` is a separate GCC support requirement |
| `HAVE_DECL_ERRNO=1` | Trace `1791043200130845882-1agu_0lp`, compile status 0; the runtime header defines the errno macro and the object defines `__errno_location` | A macro-backed interface. It does not establish a plain global `errno` symbol |
| `HAVE_PRINTF_PTR` undefined | Trace `1791043189527777628-9vdrlnbh`, compile status 93, from original `%p` sprintf/sscanf round trip | The runtime formats `%p`, but lacks `sscanf`. The negative answer conservatively declines the complete probe contract. `gcc/system.h:511` selects `%lx` because pointer and long are both 8 bytes |

The remaining 33 declaration syntax failures cannot establish declaration
absence; they also name symbols missing from this frozen runtime. No positive
feature answer is manufactured from them. `rlim_t=long` is an explicit source
fallback after the absent resource type fails; it supplies an internal spelling
without promising `getrlimit`/`setrlimit`, both unavailable. `vfork=fork` is
another original fallback; neither symbol is supplied.

## Facts independently observed

The five retained original size executables all exit 0 and recreate their
`conftest.val` files: pointer 8, short 2, int 4, long 8, long long 8. A separate
Forth-built executable, using the same frozen toolchain and headers, produces:

```text
sizes 1 2 4 8 8 8
alignments 2 4 8 8 8
bytes 8 1 1 0
stat 144 8 24 48 72
types 4 0 8 1 4 1
```

These are, in order: char/short/int/long/long-long/pointer sizes; member
alignment offsets for short/int/long/long-long/pointer; `CHAR_BIT`, signed plain
char, first/last byte of unsigned long 1; `struct stat` size/alignment and
st_mode/st_size/st_atime offsets; gid_t/ssize_t/pid_t size and signedness.
The narrower audit supplements the existing real-file/stat and process-exit
runtime tests; it does not replace their syscall behavior evidence.

Target policy is also exercised: `__STDC__=1`, `__STDC_HOSTED__=0`,
`__SEED_FORTH__=1`, `__linux__=1`, `__x86_64__=1`, `__LP64__=1`, and no
`__GNUC__`, `__STDC_VERSION__`, or `__cplusplus`. This is the compiler's selected
C90-style target mode and freestanding boundary, not a claim that the entire
C90 language or a hosted ISO library has passed a conformance suite. The
original configure failures are retained as limitations.

The reported sys/types.h, sys/stat.h, stdlib.h, string.h, limits.h, and stddef.h
are actual frozen headers and their respective original probes succeeded.
The audit fixture also compiles the actual stdio/stdarg include chain. Missing
headers, including float.h, features.h, unistd.h, time.h and sys/mman.h, remain
missing; `STDC_HEADERS` is correctly left undefined. `inline` and `long long`
success means those original forms were accepted, with long-long layout also
measured; it is not a broad C99 claim.

All 41 status-253 function/link probes name symbols absent from the independently
parsed, hash-verified runtime ELF symbol tables. This includes ldopen, exc_resume,
ldexp, times, clock, dup2, kill, getrlimit, setrlimit, atoll, atoq, sysconf,
strsignal, getrusage, nl_langinfo, scandir, alphasort, gettimeofday, mbstowcs,
wcswidth, mmap, mincore, setlocale, the unlocked stdio family, fork and vfork.
These are genuine unavailable link interfaces in this bounded runtime, not
successful stubs. Unsupported compiler/library options fail status 2. Header
absence normally fails 30. Assembler and external linker capabilities remain
unavailable under the explicit guards; GCC's target configuration selection
and assertion defaults are source-selected settings, not measured tool support.

## Original gencheck result and its boundary

The original C-only `gencheck.h` is correctly empty. `gcc/configure:6945` selects
language directories through their `config-lang.in` language names; none is
named `c`. At `:15151`, only `.` remains and there is no `.-tree.def`.
`gcc/Makefile.in:1521` consequently loops over an empty language-tree list and
creates an empty header. This does not omit the C definitions: original
`gencheck.c:30` directly includes both `tree.def` and `c-common.def`.

The independent audit replays the captured original Makefile object rule with
`-DIN_GCC -DHAVE_CONFIG_H -DGENERATOR_FILE` and its actual include paths. Empty
make `CFLAGS` and `LDFLAGS` are explicit because original `Makefile.in:144`
otherwise supplies unsupported `-g` even after configure receives empty flags.
Generated headers were copied and hash-checked before and after the replay;
all original source files and frozen compiler/runtime sources were verified.

- Object SHA-256:
  `eed194c7d8e7ba473130836b5bcccb2dd02e649bd496dde72830f2e36d595980`
- Executable SHA-256:
  `8575f1ad8768b672e3129490073eb86de13231bef05bce05992d4a96161641f1`
- Output: 164 unique tree-code macros, 9,675 bytes, SHA-256
  `911a211b76f293fb5c7863cfb6bd82ad71da3956d130fdf56fe9487387e062f3`
- Normal execution: status 0, empty stderr; unexpected argument: status 1,
  empty stdout, stderr `Usage: gencheck\n`

The output matches independent parsing of every original DEFTREECODE entry in
both unconditional .def files, including order and duplicate suppression.
The focused link resolves the original object against the real bounded runtime.
It deliberately omits `BUILD_LIBIBERTY`, which the original full link rule at
`Makefile.in:1513` requires. Therefore this establishes original generator
compilation, linking needs and exact output, **not** libiberty/archive extraction,
the full Makefile link rule, a trustworthy complete configuration, a GCC compiler,
or a bootstrap fixed point. The next accepted configuration must arise from
rerunning the unchanged probes with repaired implementation behavior.
