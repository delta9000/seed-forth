# Fixed direct-GCC compiler arena

The current direct-GCC driver requests 17 MiB (17,825,792 bytes) per translation
unit. Complete original `c-typeck.c` measured 16,988,648 bytes; production rounds
that requirement to whole MiB rather than retaining the diagnostic 32 MiB guard.
The 32 KiB legacy slab, TinyCC's 8 MiB request and shared allocator are unchanged.
The separately measured mapped workspaces are documented in
[workspace-capacity-README.md](workspace-capacity-README.md).

The historical 8-to-16 MiB evidence below is retained for provenance; its output
claims apply to those named historical inputs. The updated executable test
checks exact 32 KiB, 8 MiB, 16 MiB and 17 MiB boundaries, plus real source
exhaustion, failed mapping, publication and unchanged legacy/native bytes.

## Measurement and input ancestry

The original GCC 4.0.4 source tree is commit
`944765863eec87a9f37e297994fd2af960397138`, supplied by the archive with SHA256
`091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67`.
The unchanged generated `c-parse.c` is 217,900 bytes with SHA256
`f8e1b2f552778b15e9788614d2922dd85f5f44d0a9673912661f1bdfe6730e08`.
It was regenerated through the original Makefile and Forth-built oyacc; the
fresh reconstruction matches the retained original-rule parser exactly.

The consumer baseline compiler identity is
`d350fa1e7e0e5fab306dea1eb5f9d8a0acf3fb0b965c0cf3f52d896a85ac4e40`.
These arena replays consume an explicitly older configuration/producer epoch:
the freshly reconstructed GCC/libiberty configuration is the `8b2978` epoch,
and the source-built generator frontends use the calendar `2721caab` epoch.
Those inputs are not represented as a same-compiler-epoch full GCC build.
Their complete identities, source/header hashes and commands belong to the
private replay evidence, rather than a claim that the current compiler rebuilt
every prerequisite during this focused test.

The 8 MiB driver stops with error 10 while requesting 8,388,760 arena bytes.
A diagnostic-only in-memory override to 16 MiB compiles the entire unchanged
parser using 10,802,584 bytes and a peak of 5,100 live symbols. The arena is a
monotonic bump allocator, so its final used byte count is also its high water.
16 MiB is the next power-of-two bound above that measured requirement, leaving
5,974,632 bytes of headroom. The probe does not modify production source files
or any GCC input. It is separate from the ordinary production-driver replay.
A parser object alone does not demonstrate a linked, executable or self-built
GCC, or guarantee that every remaining source fits other compiler limits.

## Ordinary production-driver replay

Against the exact same original/generated inputs, with no diagnostic hooks:

| Unit | Original 8 MiB policy | Fixed 16 MiB policy | Output proof |
|---|---|---|---|
| `c-parse.c` | Error 10, previous output preserved | Success | 335,208-byte object, SHA256 `8a962ad246fcf8ba921a1a0cb882a688b470b44bdfe6327c1daec33a2cf3b0c1` |
| `c-lang.c` | Error 10, previous output preserved | Success | 31,168-byte object, SHA256 `c288091f71c004a6b98b8372e6582dded2454851782ac3590822bca6ea5705ba` |
| `errors.c` | Success | Success | Identical 5,824-byte objects, SHA256 `8af48196422f2000bfbbe3a4659f0b029a50c97631d75002b813208135da4667` |

The production parser object also matches the diagnostic-only probe's object
byte-for-byte. These six runs use the same copied generated-header directory
and the original GCC source paths. GCC inputs were neither edited nor reduced.

## Focused checks

Run `python3 tests/gcc/arena-capacity-check.py` from the repository. It runs
serially under a 1 GiB address-space ceiling and retains a JSON report under
`build-out/arena-capacity-*`.

- Exact 32 KiB, 8 MiB and 16 MiB boundaries, eight-byte rounding, zero-byte
  allocations at the boundary, and one-byte overflow with error 10
- Real zero-length `mmap` failure and address-space-limited driver mapping
  failure, preserving an existing output and leaving a missing output absent
- Repeated compatible C prototypes exceeding 8 MiB but fitting 16 MiB, then
  exceeding 16 MiB without triggering a symbol-table capacity first
- Real C overflow preserving both existing and absent publication destinations
- Old/new driver source identities selecting separate verified runtime caches,
  with identical runtime object bytes and linked smoke executable bytes
- Seed identity, unchanged TinyCC arena request, and pinned legacy/native
  emitted-byte and execution checks

No host compiler, assembler, linker, preprocessor or binary converter generates
the target artifacts in these checks. Full direct-GCC and repository aggregate
gates, the complete raw TinyCC fixed-point route, and execution of linked GCC
are outside this focused test's claim.
