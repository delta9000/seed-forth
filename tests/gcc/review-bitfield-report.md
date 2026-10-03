# Independent bitfield review

Result: PASS. No compiler defect found in the reviewed bounded contract.

The review used the implementation owner's frozen `build-out/bitfield-work`
compiler. Full compiler hashes are in `review-bitfield-results.json`; no
function-pointer-cast patch or subsequent shared-tree preprocessing/runtime
changes are assumed. `129-cc-bitfield.fth` SHA-256 is
`6b063611400da557cad78d6519e0b6b969c2470c119b85b1f41352f8fb2e3fac`.

## Independent checks

- GCC 14.2.0 at both `-O0` and `-O2` linked only Forth-produced production
  objects. Forty-three deterministic record layouts cover signed/unsigned
  int and long widths 1, 2, 7, 8, 9, 16, 30, 31, and 32; full-width long;
  mixed allocation units; unnamed fields; zero-width boundaries; and
  nested anonymous struct/union members. The 215 object representations
  include zero, one, alternating bits, boundary maxima, signed minima,
  prefilled neighbors and padding. Size and ordinary-member offsets match.
- Forty-six independently evaluated expression results cover integer
  promotion in both operand positions, signed extraction, unsigned wrapping,
  prefix/postfix updates, all compound integer operations, assignment results,
  conditional/logical expressions, and permitted binary64 conversions.
  Separate cases cover union overlap, static/local arrays with unnamed and
  zero-width members, single evaluation of indexed lvalues, and address/sizeof
  of an ordinary field after a bitfield operation.
- Fourteen invalid forms return error 248 with the `bitfield:` prefix.
  Parenthesized address-of, nested sizeof, static field addresses, enum
  typedefs, invalid widths, and unsupported types all leave absent output
  absent and preserve existing output bytes.
- The original GCC 4.0.4 `include/obstack.h`, hash
  `099f6cf0cb38cadf0040b4c0e235026401004104e96349d9211daaa6e3a38aa4`,
  is included unchanged. Its non-GNU `obstack_finish` and
  `obstack_1grow_fast` macros run 256 combinations of object lengths and all
  three flag values. Checks verify returned pointers, alignment, payload,
  ordinary fields and neighboring flags. The same consumer passes a fully
  Forth-built executable and host `-O0`/`-O2` interoperation.
- Disassembly of two volatile bitfield updates shows three 32-bit unit reads
  and two 32-bit unit writes: one preserving RMW for simple assignment, plus
  the separate operand read and preserving RMW for compound assignment.
  There is no lock prefix or atomic guarantee.
- Four ordinary default/native fixtures are byte-identical to the exact
  pre-bitfield baseline and execute with the same expected status. Emitted
  sizes are 690, 975, 4,952 and 3,678 bytes. Baseline reconstruction restores
  060/115 from commit `f6777bf6b657cbd10601f52d482891959da3a05f`, restores
  100/118/123 from the scalar checkpoint, and omits 129. Every baseline and
  reviewed layer is hashed in `review-bitfield-identity-results.json`.
- The shared repository's `tools/tangle.sh verify --strict` passed after
  review. No compiler, canonical book, vendor source or Git state was edited.

## Reproduce

```sh
python3 tests/gcc/review-bitfield-check.py \
  --compiler-root build-out/bitfield-work \
  --work build-out/review-bitfield-checkpoint \
  --report tests/gcc/review-bitfield-results.json
python3 tests/gcc/review-bitfield-identity.py
```

The first script defaults to the current repository compiler when
`--compiler-root` is omitted, so the ABI/consumer gate can be rerun after
integration. The identity script deliberately defaults to the isolated
bitfield snapshot to avoid attributing unrelated simultaneous changes to this
feature. Generated inputs are retained and hashed in the ABI result report.

## Boundaries

This is measured AMD64/GCC ABI compatibility, not a portable C padding-byte
promise. No signed-overflow, atomicity, or inter-thread synchronization claim
is made. Enum/char/short bitfields, packed attributes, and long widths 33–63
remain outside the stated implementation contract. The obstack evidence is
for the unchanged header and its exercised macros, not the complete
`obstack.c` translation unit. This review does not claim a complete GCC
bootstrap or replace the owner's independent original-fibheap proof.
