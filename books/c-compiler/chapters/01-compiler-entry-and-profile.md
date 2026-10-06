# 1. Compiler entry and profile

How can a Forth program turn a page of C into a program that draws a triangle? Before tracing the compiler, we need to know what the C asks for, which compiler we mean, and when the triangle is supposed to appear.

By the end of this chapter, you should be able to trace the recurring `tri.c` example, distinguish the process building its executable from the process running it, and follow one piece of source through the compiler's representations. You should also be able to reject a plausible explanation that mixes two compiler profiles.

This is an independent entrance to **A C Compiler in Forth**. You need small Forth stack and memory contracts, not a memorized seed disassembly. C syntax needed here is taught below. The source is pinned to [`7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b); the [edition record](../../EDITION.md) explains that boundary.

**Evidence boundary:** this chapter uses inspected definitions and paper derivations. No compiler build, example execution, learner study, or complete Linux bootstrap is established here. The default-profile trace assumes that compilation and loading succeed and that the program's character writes succeed. Those assumptions are separate from calculating what the program requests.

## Bring four Forth contracts

Try these short questions with data-stack top at the right. All stated addresses refer to valid, separate storage in a paper model.

1. From `[9]`, what does `dup [lit] 2 *` leave?
2. If `count` pushes a cell address A and the cell contains seven, what do `count` and `count @` separately leave? What does `[lit] 4 count !` change?
3. After `: twice dup + ;` is defined, has its body doubled a caller's number? What changes when `[lit] 3 twice` is subsequently interpreted?
4. Does reserving a data area with `create scratch [lit] 16 allot` establish that all sixteen bytes are zero?

Use the [entry-check answers](../practice/01-solutions.md#entry-check) to compare your reasoning. If a step needs repair, take only its refresher:

- Stack effects and explicit literals: [Values and words](../../seed-forth/chapters/01-values-and-words.md#words-describe-changes-to-the-stack)
- Address, value, cell fetch and store: [Four words connect the stack to memory](../../seed-forth/chapters/02-addresses-and-bytes.md#four-words-connect-the-stack-to-memory)
- Definition versus execution: [Defining the calculation](../../seed-forth/chapters/01-values-and-words.md#defining-the-calculation)
- Allocation versus initialization: [Reserve bytes without inventing their contents](../../seed-forth/chapters/10-storage-deferred-words-and-bytes.md#reserve-bytes-without-inventing-their-contents)

The working contracts are small: a Forth cell is eight bytes; `@` fetches a cell; `!` stores a value at the address above it; defining a word and executing its body are different events. Later chapters will reopen control-flow and deferred-word mechanisms when they need them. The first volume's [audit conclusion](../../seed-forth/chapters/19-audit-synthesis-and-capstone.md#state-the-remaining-trust-honestly) supplies the trust boundary without requiring you to repeat its entire byte audit now.

If these contracts are already comfortable, continue directly to the C example. You can pause after its trace with a complete, useful result: an explanation of what the compiler must preserve.

## Read enough C to follow the example

C uses named objects and expressions rather than a visible Forth data stack. An **object** is a region of storage holding a value. A **type** describes how that value is represented and which operations apply. `int` is the integer type used below; its byte width belongs to the selected profile, not to the spelling `int` alone.

Here is the canonical example used throughout this volume:

```c
#define ROWS 4
struct tri { int rows; int stars; };
struct tri t;

void line(int pad, int n) {
    while (pad > 0) { putchar(' '); pad = pad - 1; }
    while (n > 0) { putchar('*'); n = n - 1; }
    putchar('\n');
}

int main() {
    int w[ROWS];
    int r;
    t.rows = ROWS;
    for (r = 0; r < t.rows; r = r + 1) {
        w[r] = 1 + r * 2;
        line(t.rows - 1 - r, w[r]);
        t.stars = t.stars + w[r];
    }
    if (t.stars == ROWS * ROWS) return t.stars;
    return 1;
}
```

Read it in three pieces rather than trying to interpret every punctuation mark at once.

### Names and storage

`#define ROWS 4` directs the **preprocessor**, the source-rewriting part of the compiler, to replace uses of the macro name `ROWS` with the replacement text `4`. It creates no runtime variable. This simple object-like macro is enough here; conditional and function-like macros come later.

`struct tri { int rows; int stars; };` describes a structure type containing two named **members**, both integers. This type declaration does not itself create `t`. The following `struct tri t;` does that. The dot in `t.rows` selects the `rows` member of that object; `t.stars` selects its other member.

Here `t` is declared outside either function. Its members start at zero. For this legacy implementation, the compiler's globals buffer is explicitly cleared, and `t` receives storage in that buffer. That is a concrete initialization mechanism, unlike Forth's bare `allot`. We will track it again when global storage is opened.

Inside `main`, `int w[ROWS];` declares an array of four integers after macro replacement. An **array** is a numbered sequence of elements of one type. Its valid indexes are zero through three: `w[0]` is first and `w[3]` is last. `w[r]` selects the element numbered by the current value of `r`. Square brackets here are C syntax; they do not invoke Forth's `[lit]`.

`int r;` declares one more local integer. These local declarations do not give us initial values to read. The program assigns `r` before testing it and assigns each `w[r]` before reading that element. We do not assume that unused local storage is zero.

### Expressions, assignment, and calls

`w[r] = 1 + r * 2;` computes a value and stores it in the selected element. The single `=` means assignment. The multiplication groups more tightly than addition, so for `r = 2` the value is `1 + (2 * 2) = 5`, not `(1 + 2) * 2 = 6`. A semicolon ends this statement.

The left side identifies a place to store. On a right side, `w[r]` normally supplies the value stored there. A place-identifying expression is called an **lvalue**; later we will see why the compiler must preserve that distinction until it knows whether to load or store. For now, compare Forth's separate address and fetch with C's use of context to make that choice.

`line(t.rows - 1 - r, w[r]);` calls a function with two argument values. The comma separates them. Subtractions of this form group left to right: `(t.rows - 1) - r`. At row two the values passed are one and five.

The definition `void line(int pad, int n)` gives those two incoming values local names. `void` says this function supplies no result value for its caller to use. The parameters are copies: reducing `n` inside `line` does not overwrite `w[r]`. Reducing `pad` does not change `t.rows` or `r` either.

The profile supplies `putchar`, a small output routine. `' '` means the space character, `'*'` the star character, and `'\n'` one newline character. The two-character spelling backslash-plus-`n` represents one output byte here. The calls request one character each; their result values are ignored. This canonical input relies on the legacy compiler's predeclared runtime names. It is not presented as a portable, header-complete program for every C compiler.

### Choosing and repeating work

`while (n > 0) { ... }` tests its condition before each repetition. A nonzero condition runs the body; zero ends the loop. Thus `n = 3` prints three stars, decreasing `n` to two, one, then zero. An initial zero prints none. Braces group statements into one body.

The `for` loop packages three jobs:

```text
r = 0                 once, before any test
r < t.rows            test before each body
r = r + 1             after each completed body
```

For four rows, the body runs with `r` equal to zero, one, two, and three. The test at four is false. That last unsuccessful test is part of the loop's behavior; it prevents an access to `w[4]`.

Finally, `==` compares two values; it does not store one. If `t.stars == ROWS * ROWS` is true, `return t.stars;` ends `main` with that integer result. Otherwise execution reaches `return 1;`. Returning an integer does not print its decimal digits. This program's process-entry code uses the result as its exit status.

## Derive the triangle before opening the compiler

Predict the first row: after `t.rows = ROWS`, `t.rows` is four; `t.stars` is still zero. At `r = 0`, the array assignment stores one, and `line` receives three and one. Its first loop requests three spaces, its second requests one star, then it requests a newline.

For a closer look at the second row, `line(2, 3)` has this sequence:

```text
pad: 2 -> 1 -> 0       request a space on each successful test
n:   3 -> 2 -> 1 -> 0  request a star on each successful test
then                    request one newline
```

The caller's `w[1]` remains three. Consequently the following addition increases `t.stars` by three, not by the callee's final zero.

The full paper trace is:

| `r` in body | `w[r] = 1 + r * 2` | Padding argument | `t.stars` before → after |
|---:|---:|---:|---:|
| 0 | 1 | 3 | 0 → 1 |
| 1 | 3 | 2 | 1 → 4 |
| 2 | 5 | 1 | 4 → 9 |
| 3 | 7 | 0 | 9 → 16 |

At the next test, `r` is four. The body does not run. The final comparison is `16 == 4 * 4`, so `main` returns sixteen. With successful writes, the predicted output is:

```text
   *
  ***
 *****
*******
```

There are six spaces, sixteen stars, and four newlines: twenty-six requested character bytes. This is an output-stream count derived from the loops, not the C source's file size or the executable's size. Those are three different measurements.

All values in this trace are small. We have not taught overflow rules, negative indexing, or arbitrary C expression behavior. The array bound and assignment-before-read properties are part of why this is a useful first example. If the loop condition changes to `r <= t.rows`, those properties must be checked again; the attractive picture alone cannot justify the change.

## Name the compiler profile

A **profile** fixes choices that a language name and processor name leave open: object sizes, function-call rules, available runtime services, preprocessing policy, and output form. An **ABI**, or application binary interface, includes the rules by which compiled code passes arguments and results and lays out data at binary boundaries.

Our first path is the **default legacy direct-ELF profile**. “Direct” here means the Forth compiler emits the executable bytes without a separate assembler or linker. It does not mean the optional direct TinyCC or direct GCC route has been selected.

| Choice | This chapter's legacy path | Optional direct TinyCC path | Explicit System V path |
|---|---|---|---|
| Integer storage relevant here | `int` eight bytes; `char` one; pointers eight | LP64: `int` four, `long` and pointers eight | LP64: `int` four, `long` and pointers eight |
| Calls | Restricted integer/pointer register-call convention; no general ABI promise | Private all-stack convention within the generated image; each argument slot is eight bytes | Explicit System V AMD64 target; additional layers specify supported call classes |
| Runtime and headers | Built-in shim names; legacy header policy | Real prepared headers and portable-libc source, plus emitted Linux primitives | Target-specific runtime and object/link routes need their own contract |
| Selection | `120-cc-main.fth` calls `cc-parse-program` | Dedicated driver sets mode flags and calls `cc-native-program` | Explicit `cc-sysv-enable` and the appropriate driver |

**LP64** names a storage model, not a call convention. In particular, a four-byte `int` object may be passed in an eight-byte argument slot. Neither size tells you by itself where an argument arrives.

The legacy function reader spills the first six integer argument registers into local slots and returns a scalar through `rax`. That resemblance to System V does not give its eight-byte `int` the layout of an ordinary LP64 C `int`, nor establish interoperability with arbitrary host-compiled code. This example needs only two integer arguments.

Loading optional definitions alone does not select their target. `cc-target-lp64` and `cc-target-sysv` start at zero. The TinyCC driver explicitly sets LP64 and direct preprocessing before choosing its program driver. It also enables a restricted bootstrap mode for floating-value bit transport; that is not general floating arithmetic. `cc-sysv-enable` explicitly selects the System V path. The scalar base and subsequent extensions must not be collapsed into a claim that any C program is supported.

One practical consequence is already calculable: four `int` elements have a 32-byte payload in the legacy profile and a 16-byte payload in LP64. That calculation says nothing yet about a complete stack frame or executable. Keep our four-row trace on the legacy path until a later unit deliberately changes its contract.

## Two processes, with a boundary between them

The **builder process** is `seed-forth` with the compiler's Forth words loaded. It consumes C source and accumulates executable bytes. The **generated program** is the separate executable those bytes describe. On this path both are Linux/x86-64 programs, but they run at different times and have different state.

| Event | Actor | Immediate result |
|---|---|---|
| Define `cc-main` | Seed Forth reading Forth | A callable compiler-driver word |
| Execute `cc-main` | Builder process | Consume source, emit an image, attempt to write `/tmp/cc-out` |
| Execute `bye` at the driver's end | Builder process | Exit the builder with zero |
| Later load and run the output | Linux and the generated program | Entry code calls C `main`; triangle computation occurs |
| C `main` returns sixteen | Generated program | Entry code passes sixteen to Linux exit |

The builder does not draw the triangle while it parses `putchar('*')`. It emits instructions that will request that write later. The generated program's `w` and `t` are not live C objects in the builder's Forth data stack.

Even the shared-looking address `0x400000` is not shared mutable storage between these phases. The builder stores bytes in its own output buffer; the ELF describes where the later process should map them. A **file offset** counts bytes from the beginning of the file; a **virtual address** names a location in a process's address space. Their relationship belongs to the image layout, not to the builder buffer's pointer.

### Why the executing main file comes last

The actual driver ends with both a definition and an invocation:

```forth
: cc-main
  cc-load-stdin
  cc-preprocess
  cc-out-init
  cc-globals-init
  cc-emit-elf-header
  cc-parse-program
  cc-finalize-globals
  cc-finalize-elf
  cc-out-path cc-write-output
  bye ;

cc-main
```

That final bare `cc-main` changes who consumes the remaining input. The compiler's source reader now reads the remaining standard-input bytes as C. They are no longer individual Forth words for the outer interpreter.

The loader contract is therefore:

```text
010-lib.fth
numbered *-cc-*.fth library layers in lexical order, except 120
120-cc-main.fth, including its final invocation
the C source bytes
end of input
```

The pinned `tools/compiler-layers.sh` implements the exception: skip `120-cc-main.fth` during its glob loop, then list it last. Optional compiler libraries numbered above 120 must still be loaded before that invocation. `130-asm.fth` is not a `*-cc-*.fth` layer and is outside this pattern.

If a library is put after the invocation, its Forth text is consumed as C input; it has not thereby been loaded. Do not solve this by guessing an error number. Identify the boundary that was crossed. This “main last” rule is about the Forth loader, not a rule that C's `main` function must be the final function in a source file. A specialized driver, such as TinyCC's, replaces the executing default driver and has its own selection steps.

## Follow one representation through the driver

A **token** is a classified piece of source, such as a name, number, or punctuation operator. The **parser** combines tokens according to language structure. **Code generation** emits the instructions implementing that structure. This compiler interleaves parsing and emission; the following map does not imply that it stores a complete syntax tree.

| Representation | Example or responsibility | Source owner |
|---|---|---|
| Raw source bytes | `ROWS` occurs in `int w[ROWS];` | `030`: `cc-in-buf` |
| Preprocessed source bytes | Macro use becomes `4`, so the declaration is effectively `int w[4];` | `040`: `cc-preprocess`, writing `cc-src-buf` |
| Current-token state | Keyword `int`, name `w`, punctuation `[`, number 4, punctuation `]`, punctuation `;` | `050`: lexer; state cells originate in `020` |
| Meaning and compiler records | Record `w`'s type, array count, and storage identity | `060`/`070` plus declaration/expression parsers |
| Executable bytes and deferred repairs | Encode instructions; remember fields whose addresses are not known yet | `080`/`090` plus parser/emitter layers |
| Finalized image, then file | Finish global addresses and ELF sizes; attempt output write | `cc-finalize-globals`, `cc-finalize-elf`, `cc-write-output` |

The token list is a teaching representation, not a dump from a run. Later chapters open the numeric token kinds and metadata. Crucially, the macro replacement belongs before lexing the final source stream; the lexer does not turn an unexpanded `ROWS` into four by a special rule here.

Emission also has an ordering surprise. `cc-emit-elf-header` writes the first 120 bytes **before** parsing the program. ELF is the executable file format understood by the loader. Its header records an entry address of `0x400078`, 120 bytes past the load base `0x400000`. The emitted entry stub subsequently calls C `main`; the header does not directly name the first instruction of `main`.

Some facts become known only later. The final file length is patched into the header after code and globals have been emitted. The memory-size field starts with an 81,920-byte minimum and is increased if the file image plus zero-filled storage needs more. A **patch** overwrites a reserved field with a now-known value. This is a concrete instance of “emit, remember, patch,” not a second compilation of the whole program.

Keep the output promise bounded. The legacy `cc-write-output` checks whether opening the path failed, then makes one write and one close and discards both results. It does not verify a complete write. Thus “the builder exited zero” is weaker evidence than “the intended file was completely written,” which is weaker than “the generated program ran and behaved correctly.” Subsequent chapters will examine ownership and I/O limits before providing stronger execution claims.

## Practice

Use fresh paper states. [Graduated hints, checked solutions, and changed cases](../practice/01-solutions.md) are available without a waiting period. An explanation of the decisive step matters more than reproducing a sentence from the chapter.

### C1-01 — Separate the two executions

A proposed input order ends `119-cc-native-runtime.fth`, `120-cc-main.fth`, `121-cc-sysv.fth`, then `tri.c`. Explain the problem and repair the relative order while preserving all the other required libraries. Does loading `121` then automatically choose System V? Attribute these events to the builder or generated program: reserving the output storage, storing five into `w[2]`, exiting through `bye`, and returning sixteen from C `main`. Explain why “exit zero” alone does not confirm the triangle.

### C1-02 — Complete the row trace

Without the full trace table, derive rows one and three: width, padding, star total before and after, and the values remaining in the selected array element after `line` returns. Then change only the loop test from `<` to `<=`. Identify the first additional body iteration and the first array precondition it violates. Do not invent an output after that violation.

### C1-03 — Change the shape, then the check

Change only the width expression to `2 + r * 2`, keeping `ROWS` four. Derive all widths, the star total, requested character count, and return value. Does a wider triangle necessarily take the successful comparison branch? Separately restore the original width expression and set `ROWS` to three; derive the new padding, widths, total, character count, and return value.

### C1-04 — Separate size from calling convention

Calculate the payload size of four `int` elements under the legacy and LP64 profiles. Compare that with four Forth cells and with four private TinyCC argument slots. Explain why equal numbers do not identify the same storage or ABI. Can those sizes establish the complete C function-frame size, or justify linking an arbitrary host-compiled function into the legacy image?

### C1-05 — Place the work and bound the evidence

Place these jobs in driver order: macro replacement; raw-input storage; final ELF-size repair; initial ELF-header emission; token-directed parsing and instruction emission; output-file write. Say where the symbol `ROWS` becomes `4`, and whether the ELF entry points directly at C `main`. Finally correct this report: “I followed the table and the builder exited zero, so the current compiler printed the triangle and proved the Linux bootstrap.” Name the missing evidence rather than proposing to run anything now.

## Save a useful stopping point

You now have three separable explanations: the C requests a four-row triangle; the legacy compiler constructs a direct ELF image; only a later process executes that image. A mistake in one explanation should send you to that mechanism, not back to the beginning of both volumes.

If the C trace is difficult, revisit one call such as `line(2, 3)` and retry C1-02. If profile questions are difficult, compare object size and argument slot size before retrying C1-04. If all five explanations hold without copying, keep the contracts handy and move on. After intervening work, reconstruct the two-process boundary and attempt one changed case with the answer closed. That checks a different capability from finding this chapter easy to read.

The next planned unit, C02, opens input/output buffers, arena allocation, and who owns a failure. The [coverage map](../../COVERAGE.md#volume-2-a-c-compiler-in-forth) identifies that destination; this entrance has not silently supplied its implementation proof.

## Source and evidence

- Driver and loader: [`120-cc-main.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/120-cc-main.fth), [`tools/compiler-layers.sh`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/compiler-layers.sh), and the pinned [README reading order](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/README.md#reading-order). The excerpt is source-matched; the input-order picture is explanatory.
- Representations and output: [`030-cc-io.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth), [`040-cc-prep.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/040-cc-prep.fth), [`050-cc-lex.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth), and [`080-cc-elf.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/080-cc-elf.fth). These establish inspected stage contracts, not observed file contents.
- Initialization, calls, and program entry: [`090-cc-emit.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth), `cc-globals-init` and `cc-emit-putchar-shim`; [`114-cc-func.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth), `cc-emit-spill-params`; [`116-cc-prog.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth), global declarations, entry stub, and `cc-parse-program`.
- Profile boundary: [`060-cc-types.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/060-cc-types.fth), `ty-size`; [`117-cc-native-program.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/117-cc-native-program.fth); [`119-cc-native-runtime.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/119-cc-native-runtime.fth); [`tools/tcc-compile.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc-compile.fth); and [`121-cc-sysv.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth), `cc-sysv-enable`.

The recurring C input is preserved from [historical Chapter 21](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/21-arena-and-io-buffers.md). Its old source/executable byte counts are not reused as current measurements. [Historical Chapter 32](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/32-main-and-bootstrap-chain.md) provides comparison material; where its prose and the pinned definitions differ, this chapter follows the definitions. The triangle and exercise results are derivations under the stated contracts. They do not validate the later compiler or bootstrap chain.
