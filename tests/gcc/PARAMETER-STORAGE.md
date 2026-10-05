# C90 parameter declaration specifiers

`parameter-storage-check.py` compiles its production fixture with seed Forth,
links that object to independent C90 host callers at `-O0` and `-O2`, and runs
both sides again using only the Forth compiler/linker/runtime. The host C
compiler also checks that the positive fixtures are valid C90.

The gate covers the unchanged Flex declaration
`extern char *copy_string(register const char *);`, named and abstract
parameters, qualifiers around scalar/typedef/aggregate/enum bases, unsigned
and signed narrow values, LP64 values, array typedef adjustment, recursive
callback signatures, callback casts, and identifier-list definitions. All
24 permutations of `register const unsigned long` execute with a value
larger than 32 bits. An aggregate declared inside a parameter tests nested
member/signature contexts and restoration of the enclosing storage state.

Rejected cases cover invalid parameter storage classes, repeated register,
invalid storage inside callback casts, unchanged signature conflicts, void
parameters and storage after a pointer star. Function-declared parameter
adjustment is covered positively by `function-parameter-check.py`. Every rejection checks both preservation of an existing
output file and absence of a newly published output.

Run the focused gate from the repository root:

```sh
python3 tests/gcc/parameter-storage-check.py
```

A prepared original Flex 2.5.11 source directory can additionally exercise
the complete original `ccl.c` translation unit with its measured `config.h`:

```sh
python3 tests/gcc/parameter-storage-check.py --flex-source /path/to/flex/source
```

That check requires the original registered prototype in `flexdef.h`,
compiles through `tools/gcc-direct-cc.py`, and records SHA256 hashes of
`ccl.c`, `flexdef.h`, `config.h` and the resulting object. It verifies that
the input files did not change. It does not regenerate configuration or
claim that all of Flex linked or ran.

The compiler change applies only while parsing a System V parameter base.
It admits one `register` mixed with existing qualifiers and type keywords;
other storage classes reject with error 233. The default native parser
hook is a no-op. Register remains a code-generation hint, and qualifiers
keep this compiler's established representation: no new const/volatile
semantic enforcement is claimed. Base type, width, signedness, pointer
depth, aggregate identity and callback signatures remain fully represented
and checked within the existing target contract.
