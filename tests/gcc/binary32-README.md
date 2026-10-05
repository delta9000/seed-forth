# Bounded scalar binary32

The original GCC 4.0.4 `gcc/ggc-page.c` function `ggc_collect` uses two float
locals to compute an allocation threshold. Real IEEE binary32 arithmetic,
conversion and four-byte storage are required; aliasing float to double or
merely permitting its type would miscompile this consumer.

Run the numerical and ABI gate:

```sh
python3 tests/gcc/binary32-values-check.py --work /tmp/binary32-values
```

It compiles the production-side fixture with Forth, and builds a renamed,
independent host oracle at both O0 and O2. Exact deterministic input bit
patterns cover integer/float boundaries, integer cases vulnerable to double
rounding, float/double halfway ties, subnormal transitions, infinities,
signed zeros, quiet NaNs, and reproducible xorshift vectors. Arithmetic NaNs
are compared by classification because C does not promise their payload;
identity, negation and memory operations compare payload bits. Float-to-integer
tests exclude nonfinite and unrepresentable truncated values. Both oracles
run without fast math or contraction, under normal nearest-even SSE state.

The fixture also covers named and outgoing fixed/unspecified/variadic calls,
callbacks, independent GP/XMM exhaustion, stack arguments, float-to-double
argument promotion, local arrays and scalar fields, volatile accesses,
compound assignment rounding and global/local initialization. These operations
retain the existing bounded qualifier contract: `const`, `volatile` and
`restrict` are parsed without general qualifier enforcement (Appendix A6).
Const-write diagnostics and a broader optimizer-level volatile model are not
claimed; the memory probes verify the emitted ordinary four-byte accesses. A separate
Forth-only link/run verifies representative behavior without host object
providers. Rejected cases test both absent and preserved existing outputs.

Still unsupported: K&R float parameter definitions, decimal f/F and hexadecimal floating literals, long-double
values, static floating initializers, float/double increment or decrement,
and records with floating members passed by
value. `va_arg(ap,float)` remains invalid; unnamed float arguments arrive as
double. Old native/TinyCC modes retain their prior semantics and bytes.

The source replay uses the full untouched translation unit and records its
source, compiler and generated-header hashes. It deliberately distinguishes
the earlier configuration-producing compiler from the tested candidate:

```sh
python3 tests/gcc/binary32-source-check.py \
  --source-root /path/to/original/gcc-source \
  --build-root /path/to/configured/build/gcc \
  --configuration-compiler-identity 8b2978dab520d69d3aa260fcf9337272e1c7a9795da06fe810d6d34c90796113 \
  --work /tmp/binary32-ggc-page
```

Original source revision: `944765863eec87a9f37e297994fd2af960397138`.
`ggc-page.c` SHA256:
`8612279163b9823b5832e12231384cd6cea9b74df0f6f96a054c54d17b769738`.
A successful object is not a GCC executable or a same-epoch full bootstrap.

Mixed floating conditional arms now use selected-arm conversions; see
[conditional-values-README.md](conditional-values-README.md) for the bounded
conditional-expression contract and executable host/ABI proofs.
