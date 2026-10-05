# Measured c-common object capacities

This records the preceding c-common capacity stage and its frozen evidence.
The later [remaining cc1 proof](remaining-cc1-capacity-README.md) raises current
direct bounds to 10,752 records, 8,192 non-null symbols and 77,824 string bytes;
the historical numbers and object hashes below retain their original scope.

The complete unchanged GCC 4.0.4 `gcc/c-common.c` needs 9,866 stable parser
records and 6,282 emitted ELF symbols, excluding the mandatory null symbol.
That stage rounded these independent row counts up to 512-row quanta: 10,240
stable records and 6,656 ELF symbols. This is a fixed opt-in policy. It does
not grow, retry, rewrite source, change the seed, or change native/default
compiler entry points. Default capacities remain 4,096 records and 2,048
ELF symbols. The record mapping and all record accessors are unchanged except
for their direct bound. The symbol mapping uses the existing object workspace,
after payload and relocation slices, with a separate 64-byte reserved row zero.

`cc-obj-symbol-cap` and `cc-obj-symbols` retain their stack effects while
selecting active limits and addresses. Both selectors cache one mapping per
process, preserve logical counts, and run before ordinary initialization.
Default selection restores every original pointer and bound. Symbol access
rejects negative, overflowing and one-past IDs before multiplying by 64;
zero is reserved storage, and public symbol-definition/relocation APIs still
reject it. Serialized symbol zero is independently emitted as 24 zero bytes.
Local-first indexes and relocation IDs are unchanged.

## Measurement before policy

The frozen preceding compiler identity is
`d459389c0c0cfe9d531bfd99dfb0d1448f5836d09a8d514a6a0494f76c5311ee`.
Its original-source replay first requested stable record 5,121 against 5,120.
A diagnostic-only 16,384-record mapping completed parsing at 9,866 records,
then failed requesting writer symbol 2,049 against 2,048. At that failure the
string count was 22,002 and relocation count zero; neither justified an increase.
A second diagnostic-only run raised the writer symbol guard/table to 16,384
without changing any other writer limit. It completed serialization:

| Quantity | Complete observed requirement | Production direct bound |
|---|---:|---:|
| Stable records | 9,866 | 10,240 |
| ELF symbols, excluding null | 6,282 | 6,656 |
| Symbol strings, including NULs | 60,259 bytes | unchanged 65,536 bytes |
| Relocations | 13,556 | unchanged 20,992 |
| Complete object | 1,653,208 bytes | unchanged 4 MiB staging |

Every other production bound is unchanged. Diagnostic overrides are confined
to in-memory compiler snapshots used by the measurement script; none enter
the production compiler. The production replay recompiles full raw original
source with its original includes and definitions, without any overrides or
stubs. Its object exactly matches the diagnostic object's bytes:
`d965b3ae73a01ffeff2b745ad0cd28d434542cf130e9619948c2458eb2df931b`.

## Reproducibility and scope

Original source commit: `944765863eec87a9f37e297994fd2af960397138`.
Original `gcc/c-common.c` SHA256:
`0ac139bcacc0eca1713d610023a1739f589f4699d755d62b24e5d4e5dada092b`.
The source archive SHA256 is
`091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67`.
The complete retained Forth-preprocessed input is 1,914,224 bytes with SHA256
`15225891c78456bfd1415be509aabe09433947e64798d7b9b6b574ed4731e77a`.
The historical configuration/generation input is the separately identified
`a5356f3b73523539aeb0a6581d1df054493d7690986d7b0c47aa973ee44e5fb0`
epoch. This candidate consumes that historical configuration. It does not
claim a same-epoch configure replay, cc1 link/execution, or a GCC bootstrap.
No host compiler supplies target object bytes. Readelf, GNU ld and independent
Python ELF decoding are test oracles only.

`tests/gcc/object-capacity-check.py` serially checks mapped/default selection,
cache/reset behavior, all final symbol/record cells, null row reservation,
negative/high-bit/overflow/exact/one-past IDs, both unchanged string limits,
mmap failure before pointer publication, output preservation and a genuine
6,656-symbol object. Independent ELF decoding checks local-first indexes and
a relocation to the last symbol. Both GNU ld and the Forth linker consume that
object and execute it with exit 42. Existing writer/publication/workspace and
legacy/native/direct preservation gates remain required. Tests use a 1 GiB
address-space ceiling and bounded subprocess groups. Original replay evidence
retains the exact invocation, source/config manifests, compiler identity,
logs, diagnostic instrumentation and final object. Check the retained result
manifest for actually passed gates; this list is not a broader bootstrap claim.
