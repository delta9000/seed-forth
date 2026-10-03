# Reconstructed baseline validation — 2026-10-03

Fresh replay of commit `0f7ce3cff412dcea8f0571a9984a426c56091ef4`.
This is newly executed evidence, not a reuse of historical pass reports.

The validator used `git archive` at that commit and recursively archived all
22 submodules at their gitlink commits into a private directory. The resulting
3,160-file source snapshot had no shared source symlinks and no later compiler
edits. `source-inputs.sha256` records every archived regular file. The commit,
tree, nested gitlinks, timestamps, commands, exit codes and output hashes are
in `results.json`; full output stays in ignored `build-out/evidence/baseline-20261003`.

| Command | Exit | Result |
| --- | ---: | --- |
| `./build.sh` | 0 | 1,772-byte seed built from pinned hex0 |
| `./test.sh` | 0 | Seed and layers 010–070 smoke checks |
| `tests/tcc/native-check.sh` | 0 | Native regressions, LP64 encoders, preprocessing, initializers, runtime, 17 closure tests |
| `tools/tangle.sh verify --strict` | 0 | Canonical book/source byte identity |
| `tests/tcc/kernel-route-check.sh` | 0 | Raw direct TinyCC fixed point and host ladder helper gate (49.467 s) |

The raw route verified 50 pinned input files, built unpack/patch helpers with
Forth, compiled TinyCC directly, and reproduced the pinned boot2/boot3 executable
and object fixed points. Runtime and both generations of ladder-helper checks
passed. Its inventory gate covered 612 inputs and 49 explicit generated
compiler/test runs. Output logs and downstream stdout/stderr files are hashed
in `results.json`; generated binaries remain local.

The direct TinyCC seed is 870,752 bytes, SHA-256
`7411c326d30ff5a0ebadfe36d6218b6e46d2e8357f76d3a003e74ed9aee2fc3a`.
Boot2 and boot3 are byte-identical at SHA-256
`514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1`;
their object fixed point is
`b3730a49338b042d9a3dd3cde1aa4472841296e36f4b09e6e894f405f2648b61`.
A post-test rehash found no changed or missing archived input files.

New object/SysV extensions, a direct GCC bootstrap, the separate prepared-source
oracle replay, and Linux/QEMU execution are outside this baseline checkpoint.
