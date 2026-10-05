# Measured bounded direct-GCC translation workspaces

This policy extends the direct-GCC driver only. The 1,772-byte seed and its
16 MiB ELF mapping are unchanged. Ordinary and native/TinyCC entry points keep
all original capacities and dictionary-backed buffers; TinyCC still requests
an 8 MiB arena. Selection uses stack-effect-compatible address/capacity words.
No source is rewritten, no check is disabled, and no exhausted workspace grows
or causes a larger retry. Host Python records bytes and orchestrates tests;
Forth performs preprocessing, C compilation, object construction and linking.

## Fixed policy and measured maxima

The measurement cohort is the complete unchanged original `c-typeck.c`,
`expr.c`, generated `insn-recog.c`, generated `insn-attrtab.c`, the later complete
`c-common.c`, and generated `insn-output.c`/`insn-emit.c`. Raw,
expanded, text, output and arena byte bounds round the observed maximum up to
whole MiB. Table bounds round observed counts up to 512 entries; symbol strings round up
to 4 KiB pages. The raw reader
also needs its historical one-byte EOF reserve. All cap-derived arrays select
and allocate together; every other bound is left unchanged.

| Workspace | Existing default | Measured requirement | Direct-GCC bound |
|---|---:|---:|---:|
| Raw source | 1 MiB | 2,782,995 bytes plus EOF reserve | 3 MiB |
| Expanded source | 2 MiB | 2,747,955 bytes | 3 MiB |
| Text payload | 512 KiB | 3,328,178 bytes | 4 MiB |
| Output staging / complete ELF | 1 MiB | 3,901,856 bytes | 4 MiB |
| Macro rows, six columns | 4,096 physical; legacy enforces 1,024 | 4,120 | 4,608 |
| Stable object records, 128 bytes each | 4,096 | 10,559 | 10,752 |
| ELF symbols, 64 bytes each, excluding reserved null | 2,048 | 7,772 | 8,192 |
| ELF symbol strings, including NULs | 65,536 bytes | 77,487 bytes | 77,824 bytes |
| Per-function labels, five columns | 64 | 739 | 1,024 |
| Global fixups, two columns | 16,384 | 17,502 | 17,920 |
| ELF relocations, 40 bytes each | 4,096 | 20,568 | 20,992 |
| Parser arena | 32 KiB slab; former GCC driver 16 MiB | 21,103,808 bytes | 21 MiB |

Text and output remain independent bounds. A future unit can exhaust output
while its text still fits, because serialized symbols, relocations, strings,
section bytes and headers also need output space. Failures remain explicit.
The unchanged 256 KiB direct macro pool suffices: its cohort maximum is
241,747 bytes. Non-text sections, macro/include/scratch
pools, globals-data and bss capacities are not increased.

One IO mapping contains raw, expanded and output slices. Separate mappings
hold macros, stable records, labels, object payload plus relocations, symbols and
strings, global
fixups, and the arena. The new selectors cache their mappings once per process.
They preserve cursors/counts and must run before normal subsystem initialization;
selection does not migrate live pointers. Default selection restores every
original address and capacity. Existing translation/function initialization
resets logical state, and creation overwrites every reused macro/label/record row.
`cc-workspace-round` validates positivity and addition overflow before page
rounding; `cc-workspace-map` checks one mmap result before publishing active
pointers. There is no user-supplied growth knob or retry loop.

## What changed the diagnosis

The original current-baseline `c-typeck.c` error245 was stable object record
4,097 against 4,096, before serialization; its text was not full. With mapped
records it exposed a 16 MiB arena limit. A diagnostic-only 32 MiB arena measured
its complete 16,988,648-byte demand, then production was bounded at 17 MiB.
The final original `c-typeck.c` text is only 349,952 bytes.

`expr.c` now preprocesses through its 4,120 macros. Its next blocker is the
separate unsupported multidimensional field in original `gcc/optabs.h:60`,
`handlers[NUM_MACHINE_MODES][NUM_MACHINE_MODES]`, diagnosed213. This workspace
change does not claim to implement that language feature.

`insn-recog.c` required the 65th function label. A read-only census of its
48 unchanged generated functions found a maximum 739 labels in `recog_20`;
compiler-observed high-water confirmed 739. Every census goto was defined and
labels were unique within each function. Its complete object is 2,460,736 bytes,
with 7,800 relocations and 9,642,064 arena bytes.

`insn-attrtab.c` first filled 1 MiB raw input, then 1 MiB output, then 16,384 global
fixups. Complete bounded diagnostic compilation established all maxima above.
Its complete object is 3,901,856 bytes, with 20,568 relocations and 14,140,608
arena bytes. Diagnostic-only generous guards are distinct from the smaller
final production limits; final replay must use production bytes without overrides.

## Provenance and scope

Original GCC source commit:
`944765863eec87a9f37e297994fd2af960397138`

Original archive SHA256:
`091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67`

Frozen workspace baseline compiler identity:
`f273a43237a8c124ab119bc4c5af6dc0aba40aad6b7dd4fdd2af24db4ec7eb4c`

Configuration/generation epoch:
`8b2978dab520d69d3aa260fcf9337272e1c7a9795da06fe810d6d34c90796113`

Source-built generator frontends use the earlier `2721caab` epoch. These
producer epochs precede this consumer. A complete selected translation unit
is not a same-epoch GCC bootstrap, full 220-unit census, cc1 link/execution, or
self-rebuild. Those remain separate work.

Original input SHA256 values:

- c-typeck.c: `4361fbbd6a5f3f2dda5bce49b3a1cac996cc34e4dd300465b96f7e053c011fc7`
- expr.c: `42ead9d5900f96d31b1e7febc26dd1763adb1a4b855226d283b3c97f480e25c6`
- insn-recog.c: `741be9a33e53626eca11800b5a833bbb5892435536e4de374464839ecf9336de`
- insn-attrtab.c: `0122eeb3f069b9f197fb5cc35453de5133e630b74120b06f06db103b62186781`

## Executable checks

- `workspace-capacity-check.py`: serial exact/one-past cases for each selected
  buffer/table, six macro and five label columns, record ID bounds, page-rounding
  edge cases, mmap errors, selection/default/reset behavior, disjoint slices,
  and actual full dictionary HERE including linker and archive against the seed map
- `workspace-label-check.py`: forward/backward gotos, per-function reuse,
  duplicate/undefined diagnostics, and 65/1,024/1,025-label C functions
- `workspace-preservation-check.py --baseline PATH`: byte comparisons against an
  explicitly frozen pre-workspace tree for legacy/native/direct output, runtime
  cache identities, and executable results
- `arena-capacity-check.py`: legacy/native and old/new direct arena boundaries,
  rounding, exhaustion/mmap-failure publication preservation and cache identity
- Existing object-writer/publication tests retain their independent ELF oracles
- The original raw TinyCC route retains its executable/object fixed-point pins

The earlier frozen workspace compiler libraries plus linker/archive loaded with HERE at
17,270,537 (`0x1078709`), leaving 3,700,983 bytes below the seed mapping end
20,971,520. The test obtains this from the actual seed rather than summing
nominal allocations. All compiler processes are serial within each runner and
bounded below 1 GiB.
Final acceptance additionally requires strict tangle, plain numeric/index/link
checks, unchanged seed and legacy/native/TinyCC artifacts, actual-source replay,
and an independent review of the frozen candidate. Read the retained report for
which checks were run; listing a check here is not a claim that it passed.

The later [c-common object-table proof](object-capacity-README.md) documents
the independently measured stable-record and ELF-symbol additions. Its strings
and relocation limits remain unchanged. Earlier cohort counts above retain
their original provenance and do not substitute for the newer production replay.

The [remaining cc1 capacity proof](remaining-cc1-capacity-README.md) separately
identifies the later a535 historical configuration inputs. Its complete
`insn-output.c` measurement sets current records/symbols/strings, and complete
`insn-emit.c` sets the 21 MiB arena. The former 17 MiB policy came from
`c-typeck.c`; the preserved earlier cohort measurements above are not new-epoch
validation. Default/native limits and the seed remain unchanged.
