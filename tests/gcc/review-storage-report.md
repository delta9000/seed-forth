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
that all six positive probes pass both host and Forth executable routes. It also
asserts the six rejection exit codes and exact diagnostics below and requires
that rejected translation units publish no object file.

## Fix confirmation

After the source owner's bounded fixes, an independent rerun confirmed that
all six positive groups still pass both executable routes. All six negative
cases now reject without publishing an object, with these exit codes and
`cc: line 1: error N` diagnostics:

- Explicit zero and negative bounds: 238
- Overflowing positive bound: 245
- Array typedef use: 238
- Scalar/array redeclaration in either order: 237

Current confirmed source pins:

- `115-cc-native.fth`: `69787408ed145f244dc443f177c121be574ee04656fea9a6c745778b1663d6fb`
- `121-cc-sysv.fth`: `2c247160bcc5510f7b9e9b59841b53f655d1adda189be7764bb6b416a95635d2`
- `123-cc-object-program.fth`: `f54ebd7f2c2eed2068e3e68b78425c497f254efad3a9aa3860d21f40d24e38fc`
- `125-cc-consteval.fth`: unchanged from the original pin

The current regression deliberately requires fail-closed rejection of array
typedef use; it does not claim that array typedef semantics are implemented.

## Passing evidence

`tests/gcc/sysv-storage-check.sh` passed all three reported gates: the host
storage/ABI oracle, serialized field and multidimensional-array addends, and
cross-translation-unit storage with the Forth linker.

Six additional probes compile and execute successfully through both routes:

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

## Original fail-closed defects, now rejected

Each minimal example below compiled successfully at the original finding pins.
The observations in the table document the original defects, not current
behavior. The fix-confirmation section above records current behavior.

| Repro | Observed output | Correct behavior |
| --- | --- | --- |
| `int zero[0];` | A 4-byte BSS object | Reject an explicit zero bound under the current supported subset |
| `int negative[-2];` | A 4-byte BSS object | Reject the negative bound |
| `long overflow[2305843009213693953UL];` | An 8-byte BSS object | Reject before multiplication wraps or exceeds the object-size limit |
| `typedef int A[3]; A a;` | A 4-byte BSS object, with `sizeof(a) != 12` | Preserve the array typedef shape, or reject unsupported array typedef use |
| `int a; extern int a[3];` | A 12-byte BSS object | Reject incompatible scalar/array redeclaration, preferably diagnostic 237 |
| `int a[3]={1,2,3}; extern int a;` | The initialized symbol shrinks to 4 bytes | Reject incompatible array/scalar redeclaration, preferably diagnostic 237 |

The original bound holes originated before the object writer: `cc-ndeclarator` uses zero
for scalar and negative for incomplete array state without separating explicit
bounds, and `cc-nobject-size` multiplies unchecked. The writer therefore saw
already reduced or wrapped sizes. `cc-nbase` returned a typedef's base type and
aggregate descriptor without restoring its array shape. Original object
compatibility compared lengths only when both lengths were positive and did
not reject a scalar/array shape mismatch.

Bare `&array`, unindexed multidimensional decay, block-scope function
declarations, and narrow address relocations are outside this review's positive
scope because the current route deliberately rejects them.
