# Independent object-storage review, 2026-10-03

This is a reconstruction test record, not a claim about historical validation.
Production C compilation, startup object creation, and the second link route
use Forth. The host C compiler/linker is used only as a separate ABI oracle.
No compiler, book, or shared-source files were edited by this review.

Original finding pins:

- `123-cc-object-program.fth`: `718a180cbaf2cc9566d261f2f02f0a89a4e7dd9978927150cb42813f71ba374c`
- `125-cc-consteval.fth`: `edba2c40d51e8be07feef911950d7cdd89ba7512aa26f9569e335291251b1100`

Reproduce the independent cases with:

```sh
python3 tests/gcc/review-storage-probe.py
```

The script prints the source hashes, keeps each source/object/symbol-table file
and JSON results in a named `/tmp/sf-review-storage-*` directory, and asserts
that all seven positive probes pass both host and Forth executable routes. It also
asserts the eight rejection exit codes and exact diagnostics below and requires
that rejected translation units publish no object file.

## Current array typedef support confirmation

A subsequent source update implements array typedef storage and preserves up
to two dimensions through aliases. The independent suite now requires the
formerly failing `typedef int A[3]; typedef A B; B a;` to compile and run
correctly, with an ELF symbol size of 12 bytes.

The new positive group also checks a composed `A m[2]` array (24 bytes), array
indexing, `sizeof(A)` and `sizeof(B)`, a 12-byte local versus an 8-byte adjusted
parameter, and subsequent declarators after type-name queries. In particular,
`A first={sizeof(Different[5])}, after={7,8,9};` retains the three-element shape
for both objects. The same checks run for local declarations and when the
queried type is another array typedef. Both executable routes pass, and ELF
symbol sizes are independently inspected.

The current eight negative regressions reject without publishing an object,
with exact `cc: line 1: error N` diagnostics and matching process exit codes:

- Explicit zero and negative bounds: 238
- Overflowing positive bound: 245
- Pointer-to-array alias declaration `typedef int A[3]; A *p;`: 238
- Multidimensional array typedef used as a parameter: 238
- A composed third stored dimension: 238
- Scalar/array redeclaration in either order: 237

Current confirmed source pins:

- `115-cc-native.fth`: `c8c3275f251640e0e5ce864e732cf268843c4e9293fc8a210a335365fab2395b`
- `121-cc-sysv.fth`: `cd494e9fb3d3cbb9030bf1d92ec29ac152b5d57f5648e00acbef799760dd799f`
- `123-cc-object-program.fth`: `65924a4b6eb15a12359d74ba9ff4637a63bd263c1d742967f328acc268835d84`
- `125-cc-consteval.fth`: `4c0a19d98c49b22c2ab58f643663db83100d9a1a1d81f125800bcc6a624493d6`

## Earlier bounded-fix checkpoint

The first fixes preserved all six original positive groups and changed all six
original defect cases into diagnostic rejections: zero/negative bounds 238,
overflow 245, array typedef use 238, and scalar/array redeclarations 237.
That checkpoint used `123-cc-object-program.fth` hash
`f54ebd7f2c2eed2068e3e68b78425c497f254efad3a9aa3860d21f40d24e38fc`.
The array typedef rejection was temporary and is superseded by the positive
support checks above. The original finding remains documented below.

## Passing evidence

`tests/gcc/sysv-storage-check.sh` passed all three reported gates: the host
storage/ABI oracle, serialized field and multidimensional-array addends, and
cross-translation-unit storage with the Forth linker.

Seven additional probes compile and execute successfully through both routes:

1. `extern-order`: a function refers to an extern declared before its initialized
   definition; later extern and tentative declarations retain one definition.
2. `array-redecl`: incomplete extern, sized extern, initialized definition,
   incomplete extern, and tentative sized declaration preserve a 12-byte array.
3. `static-collision`: a global, same-named statics in different functions, and
   same-named statics in disjoint blocks keep separate values and lifetimes.
4. `pointer-aggregates`: arrays of pointers, structures containing pointers,
   string-pointer arrays, and nonzero array-element address addends work.
5. `function-pointer-array`: an array of function pointers through a function
   pointer typedef initializes, relocates, indexes, and calls correctly.
6. `static-local-addresses`: separately scoped same-named static arrays and
   pointers to their elements retain independent identity and mutations.
7. `typedef-array`: aliases, composed arrays, local and parameter sizing, and
   initializer type-name queries preserve storage shape as described above.

## Original storage defects, now corrected or rejected

Each minimal example below compiled successfully at the original finding pins.
The observations in the table document the original defects, not current
behavior. The current confirmation section above records the corrected behavior.

| Repro | Observed output | Correct behavior |
| --- | --- | --- |
| `int zero[0];` | A 4-byte BSS object | Reject an explicit zero bound under the current supported subset |
| `int negative[-2];` | A 4-byte BSS object | Reject the negative bound |
| `long overflow[2305843009213693953UL];` | An 8-byte BSS object | Reject before multiplication wraps or exceeds the object-size limit |
| `typedef int A[3]; A a;` | A 4-byte BSS object, with `sizeof(a) != 12` | Preserve the array typedef shape, or reject unsupported array typedef use |
| `int a; extern int a[3];` | A 12-byte BSS object | Reject incompatible scalar/array redeclaration, preferably diagnostic 237 |
| `int a[3]={1,2,3}; extern int a;` | The initialized symbol shrinks to 4 bytes | Reject incompatible array/scalar redeclaration, preferably diagnostic 237 |

The original bound holes originated before the object writer: `cc-ndeclarator` used zero
for scalar and negative for incomplete array state without separating explicit
bounds, and `cc-nobject-size` multiplied unchecked. The writer therefore saw
already reduced or wrapped sizes. `cc-nbase` returned a typedef's base type and
aggregate descriptor without restoring its array shape. Original object
compatibility compared lengths only when both lengths were positive and did
not reject a scalar/array shape mismatch.

Bare `&array`, unindexed multidimensional decay, block-scope function
declarations, and narrow address relocations are outside this review's positive
scope because the current route deliberately rejects them.
