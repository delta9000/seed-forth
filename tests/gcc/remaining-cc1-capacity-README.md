# Remaining original cc1 object capacities

Publication note: this preserves the candidate's early measurement narrative.
Its later author runs passed all three raw production units, 55 object-capacity
cases, 23 arena cases and a separate 16-stage aggregate. Independent acceptance
is absent, and the combined publication tree has not had behavioral validation.
See [publication status](../../PUBLICATION-STATUS.md) for exact identities and scope.

This stage keeps the direct-GCC profile fixed and opt-in. Complete raw original
`insn-output.c` needs 10,559 stable records, 7,772 ELF symbols excluding null,
and 77,487 symbol-string bytes including NULs. Direct policy rounds records and
symbols up to 512-row quanta, giving 10,752 and 8,192; string storage rounds up
to a 4 KiB page, giving 77,824 bytes. The string slice follows the reserved-null
symbol table in the existing object workspace mapping. The total mapped object
workspace request rounds from 6,160,448 to 6,164,480 bytes. The stable-record
mapping is independently 1,376,256 bytes.

Default/native entry points retain 4,096 records, 2,048 symbols, and the original
65,536-byte dictionary string buffer. Address and capacity words keep the same
stack effects. Selection initializes all mapped addresses after mmap succeeds,
caches one mapping, and neither migrates live data nor resets counts. Returning
to default restores every original address and limit. Object initialization
still resets string count to one and writes the leading empty-name NUL. Each
inserted name requires its own trailing NUL, including an empty name.

No capacity grows automatically. Exhaustion diagnoses before publication. Text,
rodata, data, bss, relocations, output, macro and all other capacities are
unchanged by this object-table stage. The seed remains unchanged.

## Measurement chain

The frozen production baseline is
`07ff4f3862cfaa1dcd452eb59f58ec687d564076ad06a8436ddc41cd79237afd`.
Its 94 compiler inputs were independently verified before copying. A raw replay
fails error 245 at expanded line 90544. Diagnostic-only instrumentation confirms
request 10,241 against the direct 10,240-record bound. Raising only the diagnostic
record table to 16,384 lets parsing finish with 10,559 records and 15,850,312 arena
bytes. Serialization then fails with 65,535 string bytes used and an 8-byte name
against zero remaining name capacity, excluding its required NUL.

Diagnostic 128 KiB strings expose symbol request 6,657 against 6,656. A separate
diagnostic 16,384-symbol allowance completes the object: 7,772 symbols, 77,487
string bytes, 12,709 relocations, 131,467 text bytes, 75,386 rodata bytes and
170,344 data bytes. The diagnostic object is 947,040 bytes, SHA256
`ac637ee13860497735823311ba91208367a39909fdd731fa145cfbbc91de878e`.
Independent ELF decoding validates all symbol/relocation indexes and extents.
This object is nonproduction. The smaller production policy requires a separate
unmodified-driver raw replay; equality alone is not behavioral validation.

The baseline also compiles untouched `gcc/config/i386/i386.c`: 1,113,848 bytes,
SHA256 `52571989df6db4cb750596c1fb2fbf548b44641ac3dc22e8f7ffae1dd7bdb26c`.
That previously failed at the historical 5,120 direct-record limit; the default
4,096-row limit was a separate mode. No further repair was needed for i386.
Raw `insn-emit.c` diagnoses arena error 10 at expanded line 53105 under the
17 MiB baseline. A separate diagnostic-only 32 MiB arena replay completes in
488.3 seconds at exactly 21,103,808 used bytes. The 20 MiB budget is 132,288
bytes short; the next whole-MiB policy is 21 MiB (22,020,096 bytes). Only the
direct Python driver changes this arena request. Legacy 32 KiB and TinyCC 8 MiB
arenas are unchanged. There is no retry or automatic growth.

Its diagnostic object is 1,344,424 bytes, SHA256
`6177861f46998546434357a04422900a33bd5b8a1d3f8844acc4d049903fb2e2`,
with 3,808 stable records, 1,279 ELF symbols, 20,148 string bytes and 10,468
relocations. Independent ELF decoding passes. The smaller 21 MiB production
candidate still requires a fresh uninstrumented raw original-source replay.

## Inputs, tests and scope

Original GCC commit: `944765863eec87a9f37e297994fd2af960397138`.
Original generated insn-output source SHA256:
`c15ea7dc2c44294246b009e4ec41489d94aa52a7908014d0d531411717aeb74f`.
Configuration/generation inputs are explicitly historical a535
(`a5356f3b73523539aeb0a6581d1df054493d7690986d7b0c47aa973ee44e5fb0`).
All 25,654 pinned original source files and 455 frozen preparation inputs were
independently rehashed without drift. Per-attempt manifests retain compiler,
source/configuration prerequisites, raw commands, diagnostic snapshots, logs,
600-second/1-GiB supervisors and zero-descendant cleanup results.

`object-capacity-check.py` covers exact/one-past rows, reserved null symbols,
leading/trailing name NULs, exact/one-past selected string capacities, mmap
failure before pointer publication, slice boundaries, cached mode switching,
logical reset and absent/existing-output preservation. It builds the full
8,192-symbol object and checks its ELF indexes and last-symbol relocation;
host and Forth linkers are independent test consumers. `arena-capacity-check.py` covers exact/one-over 17, 20 and 21 MiB budgets,
mapping failure, atomic publication, cache identity and default/native bytes.
Existing writer, publication, workspace, and baseline preservation checks remain
required. An early source checkpoint is not a claim that these checks passed.

These are selected translation-unit and resource-bound proofs. No same-epoch
configuration, complete cc1 cohort, linked/executed GCC, or bootstrap is claimed.
