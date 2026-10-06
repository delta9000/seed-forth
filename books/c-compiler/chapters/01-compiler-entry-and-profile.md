# 1. Compiler entry and profile

Our first C program asks for a triangle: four lines containing one, three, five, and seven stars. The compiler must turn that request into executable instructions. To see what it must preserve, start with something smaller than the whole triangle: one call that draws one line.

This is an independent entrance to **A C Compiler in Forth**. You need a few Forth stack and memory contracts, with a [short refresher](#bring-four-forth-contracts) available below; the C syntax is introduced here. By the end, you should be able to predict the triangle, explain why compiling it does not draw it, and follow one declaration from source text into the compiler's records and output.

**Our working conditions:** we use the default legacy compiler at [`7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b). The following results are paper predictions, assuming successful compilation, loading, and character writes. The [edition record](../../EDITION.md) and [source record](#source-and-evidence) keep those predictions separate from execution evidence.

## Read enough C to follow the example

A **function** is a named piece of work that can be called with input values. This one is named `line`. A call written `line(2, 3)` gives it two integers: two for `pad`, three for `n`. The comma separates the inputs. Here is the part of `tri.c` that says what the function does:

```c
void line(int pad, int n) {
    while (pad > 0) { putchar(' '); pad = pad - 1; }
    while (n > 0) { putchar('*'); n = n - 1; }
    putchar('\n');
}
```

The two names after `int` are **parameters**: local names for the incoming integer values. The outer braces enclose the function's body. `void` says that `line` gives its caller no result value to use; it does its work through the calls inside the body.

`putchar` requests one output character. The quotes in `' '` enclose a space; those in `'*'` enclose a star. `'\n'` denotes one newline character, which ends the line. The backslash and `n` are two characters in the source spelling, but they request one output byte here. Each semicolon ends a statement. The result values of the `putchar` calls are ignored.

Read `while (pad > 0)` as “test whether `pad` is greater than zero; if so, do the braced work, then test again.” The statement `pad = pad - 1` calculates one less than the current value and stores that new value in `pad`. In C, a single `=` is an assignment, not a claim that the expressions on both sides were already equal. The second loop does the same job with `n` and stars.

Before following the trace, predict what `line(2, 3)` requests. In what order do the spaces, stars, and newline appear? Does either loop run its body once more when its count reaches zero?

The first test succeeds with `pad` equal to two. One space is requested, then the assignment changes `pad` to one. The next test succeeds too: another space, then `pad` becomes zero. Now the test fails, so execution moves to the star loop. That loop starts with its own count, three.

```text
pad before a test     2       1       0
space requested?      yes     yes     no

n before a test       3       2       1       0
star requested?       yes     yes     yes     no

both loops finished   request one newline
```

The requested line is two spaces, three stars, and a newline: six character bytes. Both counts end at zero. A `while` loop tests **before** running its body, so the failed test requests nothing. The final `putchar` is outside both loop bodies and still runs.

That last distinction lets you handle a changed case without tracing positive counts again. What would `line(0, 0)` request? Both first tests fail, but the final statement still requests a newline. Zero repetitions of a loop do not mean zero work after the loop.

We now know what one call does. The rest of the program chooses the inputs for four such calls and counts the stars. Here is the complete canonical `tri.c`; find the call to `line` inside `main` before reading on:

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

### Names and storage

The definition of `line` is the one we just traced. The other function, `main`, chooses the rows. A call to `main` will start with its first statement and work through its body; having its definition in the source does not yet run it.

Start with the two lines inside `main` that begin with `int`. C uses named **objects**, regions of storage that hold values. A **type** describes how a value is represented and which operations apply; `int` is the integer type used here. `int r;` reserves one local integer named `r`. Its job will be to identify the current row.

`int w[ROWS];` reserves several integers together: an **array**. The number of elements comes from `#define ROWS 4`. That line tells the **preprocessor**, the compiler's source-rewriting part, to replace uses of the macro name `ROWS` with the text `4`. Thus this declaration means an array of four integers. `ROWS` is not a runtime variable. The more elaborate kinds of macros can wait; this one replaces a name with a number.

The array's elements are numbered from zero: `w[0]`, `w[1]`, `w[2]`, and `w[3]`. Four is the number of elements, not an available element number. `w[r]` selects the element numbered by the current value of `r`.

The names with dots belong to another object, `t`. Above the functions, `struct tri { int rows; int stars; };` describes a **structure type**, a group with two named integer **members**. That line describes a type; the next line, `struct tri t;`, creates the object. `t.rows` selects its `rows` member, and `t.stars` selects its `stars` member. They will hold the row limit and the accumulated star count.

Because `t` is declared outside the functions, its members start at zero. For this legacy compiler, that promise has a concrete mechanism: the compiler clears its globals buffer and places `t` there. Reserving storage alone would not explain the zeros. The local `r` and array `w` have no such initial-value promise; we will check that each value is assigned before it is read.

### Choosing and repeating work

The first assignment, `t.rows = ROWS`, stores four in the row-limit member. `t.stars` remains zero. The `for` statement then controls which row is drawn. Its parentheses package three jobs, separated by semicolons:

```text
r = 0                 once, before any test
r < t.rows            test before each body
r = r + 1             after each completed body
```

The first job gives `r` its initial value, so the test does not read uninitialized local storage. At zero, `r < t.rows` asks whether zero is less than four. It is, so the three statements inside the braces run. Only after those statements finish does `r = r + 1` advance to one and lead back to the test. As with `while`, a nonzero condition runs the body; zero ends the loop.

### Expressions, assignment, and calls

For the first row, `w[r] = 1 + r * 2` calculates `1 + 0 * 2` and stores one in `w[0]`. Multiplication groups more tightly than addition. For example, when `r` later becomes two, the same expression will be `1 + (2 * 2) = 5`, not `(1 + 2) * 2 = 6`.

The next statement is the call we were looking for: `line(t.rows - 1 - r, w[r])`. The first input supplies the number of spaces. These subtractions group left to right, so with four rows and `r` zero it is `(4 - 1) - 0`, or three. The second input reads the one we just stored in `w[0]`. This first call is therefore `line(3, 1)`: three spaces, one star, one newline.

Now there is a possible surprise. Inside `line`, `n` was reduced to zero. Yet the very next statement, `t.stars = t.stars + w[r]`, is supposed to add that row's width to the running total. Has drawing the line used up the width?

Trace the second row, where `r` is one and the stored width is three:

| Moment | `main`'s array element `w[1]` | `line`'s parameter `n` |
|---|---:|---:|
| After `w[1] = 1 + 1 * 2` | 3 | No call yet |
| When `line(2, 3)` begins | 3 | 3 |
| After the first star-loop body, including its assignment | 3 | 2 |
| After the second star-loop body, including its assignment | 3 | 1 |
| After the third star-loop body, including its assignment | 3 | 0 |
| After the call returns | 3 | The call has finished |

The call reads the **value stored in** `w[1]` and initializes `n` with a copy. The parameter is a separate object; it is not another name for the array element. Reducing `n` changes that local copy; it does not erase the saved width. Similarly, reducing `pad` changes neither `t.rows` nor `r`. When execution returns to `main`, the addition can still read three from `w[1]` and add it to the previous total, one, making four.

This is why the array and the parameter cannot be treated as interchangeable names. They briefly hold equal values, but they are different storage. The compiler must preserve that distinction even though the complete function-call machinery comes later.

## Derive the triangle before opening the compiler

The same three statements now explain every row: save its width, draw it using copied inputs, then add the saved width to the total. Try deriving the last row before looking at the completed trace. Remember that the first row was numbered zero.

| `r` in body | Width saved in `w[r]` | Padding argument | `t.stars` before → after |
|---:|---:|---:|---:|
| 0 | 1 | 3 | 0 → 1 |
| 1 | 3 | 2 | 1 → 4 |
| 2 | 5 | 1 | 4 → 9 |
| 3 | 7 | 0 | 9 → 16 |

After the last row, the loop's increment makes `r` four. The next test, `4 < 4`, fails. There is no access to `w[4]`. Every array element used in the trace was assigned before the call and addition read it.

With successful character writes, the predicted output is:

```text
   *
  ***
 *****
*******
```

The program has requested six spaces, sixteen stars, and four newlines: twenty-six character bytes. That counts the output stream, not the number of bytes in the C source file or in the executable.

One decision remains after the loop. `==` compares two values, unlike the assignment operator `=`. `if` runs the following statement only when its condition is true. Here `t.stars == ROWS * ROWS` compares sixteen with `4 * 4`. They are equal, so `return t.stars` ends `main` with result sixteen. If the comparison were false, execution would instead reach `return 1`. Returning an integer does not print its decimal digits; this program's entry code uses it as the process exit status. The visible triangle, the twenty-six character bytes, and the return value sixteen are three different results to keep track of.

All values here are small; no overflow rule is needed to derive them. But the safe array accesses depended on a particular comparison. Change `<` to `<=`, and `r` equal to four would enter the body. The first assignment would try to store a width in the nonexistent fifth element. An extra width of nine is easy to calculate; it does not make `w[4]` a valid destination. Stop at that broken precondition rather than predicting a fifth line or a particular crash. Negative indexing and general C arithmetic need contracts beyond this first trace.

We have reached the result the compiler must preserve. The next question is when any of these writes and additions happen. Does the Forth compiler print a star when it reads `putchar('*')`?

## Two processes, with a boundary between them

The Forth compiler does not draw a line when it reads the C call. It writes instructions that will request those characters later. That separates two processes whose jobs are easy to confuse when both programs run on Linux/x86-64.

The **builder process** is `seed-forth` with the compiler's Forth words (callable operations) loaded. Its work is to read C source, accumulate executable bytes, and attempt to write them to `/tmp/cc-out`. On our default legacy path it emits an ELF executable directly: no separate assembler or linker turns the emitted bytes into a program. ELF is the executable file format that tells Linux how to load that program.

The **generated program** is the separate executable described by those bytes. Only when Linux later loads and runs it does its entry code call C `main`. Then the row loop assigns widths, calls `line`, and counts stars. When `main` returns sixteen, the entry code passes that value to Linux exit. None of those C calls happens merely because the builder has read their source text.

Keep the two kinds of storage separate too. The builder needs buffers in which to hold source and future executable bytes. The generated program needs the array `w`, the object `t`, and each call's local parameters. During compilation, the builder manipulates descriptions and bytes; the live array and parameters belong to the later program. The builder records how that program will use them.

Writing a future instruction and executing it are different events. Here the separation extends all the way to a new executable and a later process. To see how the builder can describe objects that are not yet in use, follow the array declaration through its work.

## Follow one representation through the driver

The builder first reads the C source as bytes. At this point `int w[ROWS];` is text in the input buffer, `cc-in-buf`. There is no four-element array sitting in that text buffer. The letters and punctuation describe storage the generated program will need.

The preprocessor rewrites source into another buffer, `cc-src-buf`. It has seen `#define ROWS 4`, so the use in the array declaration becomes `4`. The declaration reaching the next stage is effectively `int w[4];`. The replacement happens here, before that final source stream is divided into tokens.

A **token** is a classified piece of source: a name, number, keyword, or punctuation operator. The **lexer** supplies these pieces. For this declaration, the useful view is:

```text
keyword int | name w | punctuation [ | number 4 | punctuation ] | punctuation ;
```

That is a teaching view of the sequence, not a captured token dump. Classification matters: `4` is the array's count, while `w` is the name the compiler must later recognize. The **parser** reads the tokens according to C's structure and records that `w` names an array of four integers with a particular storage location. In this legacy profile an `int` occupies eight bytes, so the array's elements require 32 bytes. That is the element payload, not the size of all the storage needed by a call to `main`.

Later, when the parser encounters `w[r]`, that record helps it find the selected element. But finding the element is not enough. In `w[r] = 1 + r * 2`, the element is the **destination** of a store. In `line(..., w[r])`, the program needs the **value** stored there. A place-identifying expression is called an **lvalue**. C's context tells the compiler when to use that place as a destination and when to load its value. Compare Forth's separate address and fetch: an address alone is not the integer saved there. This distinction is what lets the later call receive a value copy while the array keeps its width.

**Code generation** writes machine instructions that implement these operations. This compiler interleaves parsing and instruction emission; it does not need to store a complete syntax tree before writing any instructions. Some addresses will not be known yet, so it also remembers places that need repair. The stages and their source owners are:

| Representation | What happens to our example | Source owner |
|---|---|---|
| Raw source bytes | Hold `int w[ROWS];` as input text | `030`: `cc-in-buf` |
| Preprocessed source bytes | Replace the macro use, giving `int w[4];` | `040`: `cc-preprocess`, writing `cc-src-buf` |
| Current-token state | Classify the keyword, name, count, and punctuation | `050`: lexer; state cells originate in `020` |
| Meaning and compiler records | Record `w`'s type, array count, and storage identity | `060`/`070` plus declaration/expression parsers |
| Executable bytes and deferred repairs | Encode operations on that storage; remember unresolved addresses | `080`/`090` plus parser/emitter layers |
| Finalized image, then file | Finish global addresses and ELF sizes; attempt the output write | `cc-finalize-globals`, `cc-finalize-elf`, `cc-write-output` |

Later chapters open the numeric token kinds, records, and instruction encoders. Here the important change is already visible: source text becomes information the builder can act on, then bytes the generated program can execute. The lexer does not rescue an unexpanded `ROWS` by turning it into four; the preprocessor has already done the replacement.

There is an apparent ordering problem. The executable starts with a header, and that header must describe the completed image. Yet `cc-emit-elf-header` writes the first 120 bytes **before** parsing the C program. How can it know enough?

It writes the known fields and leaves room to repair the others. The entry address is already fixed at `0x400078`, 120 bytes after the load base `0x400000`. At that entry the compiler will place a small **entry stub**, code that calls the separately located C `main` and exits with its result. The header points at that stub, not directly at `main`. Once `main`'s address is known, the compiler repairs the stub's call target.

The final file length is not known at header-emission time. After code and globals have been emitted, finalization writes that length into the reserved header field. The memory-size field begins with an 81,920-byte minimum and increases if the file image plus zero-filled storage needs more. A **patch** overwrites a reserved field with a now-known value. The builder can emit, remember, and patch instead of waiting to know everything or compiling the entire program again.

These addresses describe the later process, not the builder's buffer. A **file offset** counts bytes from the start of the file; a **virtual address** names a location in a process's address space. Here file offset 120 maps to entry address `0x400078`. The builder stores the corresponding bytes at its own output-buffer address. Even an address such as `0x400000` appearing in both programs does not make their storage shared.

The completed image can now be written to a file. This legacy output helper checks whether opening the path failed, then makes one write and one close and discards both results. Reaching the driver's final `bye` therefore requests a zero exit from the **builder** without establishing that every output byte was written. A complete file would still be a separate fact from running it and obtaining the triangle. The distinction between description and execution also tells us which evidence to ask for.

Before opening the driver's source, carry the story through one small change. Suppose `ROWS` were three instead of four. Where would the array length change? In the builder, preprocessing would replace `ROWS` with `3`, and the declaration would describe three integers. When the generated program later ran, its row loop would use indexes zero, one, and two. The compiler would not draw those three rows while discovering their array length. We can change the C request and still keep the two processes distinct.

### Why the executing main file comes last

We can now read the Forth driver as a sequence of the jobs just described. Its actual definition and final invocation are:

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

Defining `cc-main` creates a callable Forth word. The final bare `cc-main` executes it. Its first operation, `cc-load-stdin`, changes who reads the remaining input: the compiler's source reader consumes the remaining standard-input bytes as C. They are no longer individual Forth words for the outer interpreter.

That has a consequence for loading the compiler itself. Imagine placing another Forth library after this invocation. By then the source reader is consuming C; the later library's Forth text would become raw C input. It would never have been loaded as Forth. All the libraries must come before the driver begins consuming the C program:

```text
010-lib.fth
numbered *-cc-*.fth library layers in lexical order, except 120
120-cc-main.fth, including its final invocation
the C source bytes
end of input
```

The pinned `tools/compiler-layers.sh` implements the exception: it skips `120-cc-main.fth` during its glob loop, then lists it last. Optional compiler libraries numbered above 120 still belong before that invocation. `130-asm.fth` is not a `*-cc-*.fth` layer and is outside this pattern.

This “main last” rule concerns the Forth loader, not the position of C's `main` function in a source file. Nor does a misplaced library call for guessing a diagnostic number: the error in the proposed order is that Forth source crossed the boundary into C input. A specialized driver, such as TinyCC's, replaces the executing default driver and has its own selection steps.

Our first complete path is now accounted for: Forth definitions make the compiler available; invoking the driver consumes C and writes an executable; a later invocation of that executable performs the row loop. The remaining reference sections pin down the choices behind this path before the exercises ask you to distinguish it from alternatives.

## Name the compiler profile

A **profile** fixes choices that a language name and processor name leave open: object sizes, function-call rules, available runtime services, preprocessing policy, and output form. An **ABI**, or application binary interface, includes the rules by which compiled code passes arguments and results and lays out data at binary boundaries.

The path we have followed is the **default legacy direct-ELF profile**. “Direct” here means the Forth compiler emits the executable bytes without a separate assembler or linker. It does not mean the optional direct TinyCC or direct GCC route has been selected.

| Choice | This chapter's legacy path | Optional direct TinyCC path | Explicit System V path |
|---|---|---|---|
| Integer storage relevant here | `int` eight bytes; `char` one; pointers eight | LP64: `int` four, `long` and pointers eight | LP64: `int` four, `long` and pointers eight |
| Calls | Restricted integer/pointer register-call convention; no general ABI promise | Private all-stack convention within the generated image; each argument slot is eight bytes | Explicit System V AMD64 target; additional layers specify supported call classes |
| Runtime and headers | Built-in shim names; legacy header policy | Real prepared headers and portable-libc source, plus emitted Linux primitives | Target-specific runtime and object/link routes need their own contract |
| Selection | `120-cc-main.fth` calls `cc-parse-program` | Dedicated driver sets mode flags and calls `cc-native-program` | Explicit `cc-sysv-enable` and the appropriate driver |

**LP64** names a storage model, not a call convention. In particular, a four-byte `int` object may be passed in an eight-byte argument slot. Neither size tells you by itself where an argument arrives.

The legacy function reader spills the first six integer argument registers into local slots and returns a scalar through `rax`. That resemblance to System V does not give its eight-byte `int` the layout of an ordinary LP64 C `int`, nor establish interoperability with arbitrary host-compiled code. This example needs only two integer arguments.

Loading optional definitions alone does not select their target. `cc-target-lp64` and `cc-target-sysv` start at zero. The TinyCC driver explicitly sets LP64 and direct preprocessing before choosing its program driver. It also enables a restricted bootstrap mode for floating-value bit transport; that is not general floating arithmetic. `cc-sysv-enable` explicitly selects the System V path. The scalar base and subsequent extensions must not be collapsed into a claim that any C program is supported.

One practical consequence is the size of our array: four `int` elements have a 32-byte payload in the legacy profile and a 16-byte payload in LP64. A call's **stack frame** is the storage set aside for that active call; it can include other locals, saved state, and padding. The array payload alone therefore gives neither the complete frame size nor the executable size. Keep our four-row trace on the legacy path until a later unit deliberately changes its contract.

The canonical input uses the legacy compiler's predeclared runtime names, including `putchar`. It is not a portable, header-complete program for every C compiler. Conditional and function-like macros, broader language support, and later bootstrap routes each need their own treatment.

## Bring four Forth contracts

For readers returning from the Seed volume, three connections are useful here.
C array brackets are unrelated to Forth's `[lit]` syntax. The compiler's explicit
global-buffer clearing supplies initial zeros; bare `allot` only reserves bytes.
And a Forth word writing another word's body already separates producing
instructions from executing them. The C objects themselves are not live
objects on the builder's Forth data stack. These connections are optional for
the C story above; the following refreshers open the Forth notation when needed.

This is a recovery point for the Forth ideas used above, not a requirement to repeat the first volume. Try the questions you need, with data-stack top at the right. All stated addresses refer to valid, separate storage in a paper model.

1. From `[9]`, what does `dup [lit] 2 *` leave?
2. If `count` pushes a cell address A and the cell contains seven, what do `count` and `count @` separately leave? What does `[lit] 4 count !` change?
3. After `: twice dup + ;` is defined, has its body doubled a caller's number? What changes when `[lit] 3 twice` is subsequently interpreted?
4. Does reserving a data area with `create scratch [lit] 16 allot` establish that all sixteen bytes are zero?

Use the [entry-check answers](../practice/01-solutions.md#entry-check) to compare your reasoning. If a step needs repair, take only its refresher:

- Stack effects and explicit literals: [Values and words](../../seed-forth/chapters/01-values-and-words.md#words-describe-changes-to-the-stack)
- Address, value, cell fetch and store: [Four words connect the stack to memory](../../seed-forth/chapters/02-addresses-and-bytes.md#four-words-connect-the-stack-to-memory)
- Definition versus execution: [Defining the calculation](../../seed-forth/chapters/01-values-and-words.md#defining-the-calculation)
- Allocation versus initialization: [Reserve bytes without inventing their contents](../../seed-forth/chapters/10-storage-deferred-words-and-bytes.md#reserve-bytes-without-inventing-their-contents)

The working contracts are small: a Forth cell is eight bytes; `@` fetches a cell; `!` stores a value at the address above it; defining a word and executing its body are different events. The compiler's calls to buffer-writing words happen in the builder, just as an ordinary defined Forth word does work only when executed. Later chapters reopen control-flow and deferred-word mechanisms when they need them. The first volume's [audit conclusion](../../seed-forth/chapters/19-audit-synthesis-and-capstone.md#state-the-remaining-trust-honestly) gives its trust boundary without requiring the whole byte audit here.

## Practice

Use fresh paper states. [Graduated hints, checked solutions, and changed cases](../practice/01-solutions.md) are available without a waiting period. An explanation of the decisive step matters more than reproducing a sentence from the chapter.

### C1-01 — Separate the two executions

A proposed input order ends `119-cc-native-runtime.fth`, `120-cc-main.fth`, `121-cc-sysv.fth`, then `tri.c`. Explain the problem and repair the relative order while preserving all the other required libraries. Does loading `121` then automatically choose System V? Attribute these events to the builder or generated program: reserving the output storage, storing five into `w[2]`, exiting through `bye`, and returning sixteen from C `main`. Explain why “exit zero” alone does not confirm the triangle.

### C1-02 — Complete the row trace

Without the full trace table, derive the iterations with `r = 1` and `r = 3`: width, padding, star total before and after, and the values remaining in the selected array element after `line` returns. Then change only the loop test from `<` to `<=`. Identify the first additional body iteration and the first array precondition it violates. Do not invent an output after that violation.

### C1-03 — Change the shape, then the check

Change only the width expression to `2 + r * 2`, keeping `ROWS` four. Derive all widths, the star total, requested character count, and return value. Does a wider triangle necessarily take the successful comparison branch? Separately restore the original width expression and set `ROWS` to three; derive the new padding, widths, total, character count, and return value.

### C1-04 — Separate size from calling convention

Calculate the payload size of four `int` elements under the legacy and LP64 profiles. Compare that with four Forth cells and with four private TinyCC argument slots. Explain why equal numbers do not identify the same storage or ABI. Can those sizes establish the complete C function-frame size, or justify linking an arbitrary host-compiled function into the legacy image?

### C1-05 — Place the work and bound the evidence

Place these jobs in driver order: macro replacement; raw-input storage; final ELF-size repair; initial ELF-header emission; token-directed parsing and instruction emission; output-file write. Say where the symbol `ROWS` becomes `4`, and whether the ELF entry points directly at C `main`. Finally correct this report: “I followed the table and the builder exited zero, so the current compiler printed the triangle and proved the Linux bootstrap.” Name the missing evidence rather than proposing to run anything now.

## Save a useful stopping point

You now have three separable explanations: the C requests a four-row triangle; the legacy compiler constructs a direct ELF image; only a later process executes that image. A mistake in one explanation should send you to that mechanism, not back to the beginning of both volumes.

If the C trace is difficult, revisit one call such as `line(2, 3)` and retry C1-02. If profile questions are difficult, compare object size and argument slot size before retrying C1-04. If all five explanations hold without copying, keep the contracts handy and move on. After intervening work, reconstruct the two-process boundary and attempt one changed case with the answer closed. That checks a different capability from finding this chapter easy to read.

The next planned unit, C02, opens the buffers and arena that hold the compiler's data. It asks where that storage comes from, how much fits, and what happens when an operation fails. The [coverage map](../../COVERAGE.md#volume-2-a-c-compiler-in-forth) identifies that next step.

## Source and evidence

- Driver and loader: [`120-cc-main.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/120-cc-main.fth), [`tools/compiler-layers.sh`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/compiler-layers.sh), and the pinned [README reading order](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/README.md#reading-order). The excerpt is source-matched; the input-order picture is explanatory.
- Representations and output: [`030-cc-io.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/030-cc-io.fth), [`040-cc-prep.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/040-cc-prep.fth), [`050-cc-lex.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/050-cc-lex.fth), and [`080-cc-elf.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/080-cc-elf.fth). These establish inspected stage contracts, not observed file contents.
- Initialization, calls, and program entry: [`090-cc-emit.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth), `cc-globals-init` and `cc-emit-putchar-shim`; [`114-cc-func.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/114-cc-func.fth), `cc-emit-spill-params`; [`116-cc-prog.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth), global declarations, entry stub, and `cc-parse-program`.
- Profile boundary: [`060-cc-types.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/060-cc-types.fth), `ty-size`; [`117-cc-native-program.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/117-cc-native-program.fth); [`119-cc-native-runtime.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/119-cc-native-runtime.fth); [`tools/tcc-compile.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc-compile.fth); and [`121-cc-sysv.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth), `cc-sysv-enable`.

The recurring C input is preserved from [historical Chapter 21](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/21-arena-and-io-buffers.md). Its old source/executable byte counts are not reused as current measurements. [Historical Chapter 32](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/32-main-and-bootstrap-chain.md) provides comparison material; where its prose and the pinned definitions differ, this chapter follows the definitions. The triangle and exercise results are derivations under the stated contracts. No compiler build, example execution, or complete Linux bootstrap was performed for this chapter. No learner study is claimed; editorial or model review is not evidence of human learning, retention, or transfer.
