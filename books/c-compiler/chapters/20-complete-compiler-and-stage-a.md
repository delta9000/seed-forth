# 20. The complete compiler and Stage-A comparison

In C19, the input was `int main(void) { return 7; }`. We followed the builder to a predicted 556-byte executable, then followed that program to a predicted exit value of seven. Now replace the small C input with the source of another C compiler, M2-Planet.

The Forth builder still produces an executable. But this time, running the result can produce another compilation. What should we compare with a reference: the two compiler executables, or the files those compilers emit?

Keep that choice open while we follow one artifact through its two lives. By the end of this first session, you should be able to name the exact pair Stage A compares and explain what its recorded result establishes. You need C19's distinction between building a program and running it; no shell programming or M1 assembly syntax is assumed.

The historical Stage-A observation predates the added layer 132 and the current
32-file Forth census. Matching recipe blobs do not establish that the newer
compiler inputs produced the same bytes; the result retains its named old head.

## The program we built becomes the next producer

A **producer** is a running program that creates something. An **artifact** is the saved result of a step. The same file can be an artifact now and, when executed later, supply a producer for the next step.

Our first producer is `seed-forth` running the Forth C compiler. Its input contains the compiler definitions followed by prepared M2-Planet C source. The legacy driver from C19 emits a Linux/x86-64 ELF executable. ELF is the executable file envelope we already traced. The Stage-A recipe retains this new file as `cc-out-v1`.

That filename does not mean “the output of compiling every C program.” It names one particular program: M2-Planet, compiled by our Forth compiler. The preparation and saving details have their own reference sessions below. For now, suppose this first build succeeds.

Switch executions, as we did when C19's entry stub called `main`. Instead of returning seven, this target program can now read C files and emit textual assembly. When we run `cc-out-v1`, the former target becomes a compiler producer in its own right.

We need a second producer to compare with it. The script freshly builds the same M2-Planet compiler using a host C compiler and calls the result `m2-ref`. The reference helper defaults to `gcc`; its `CC` setting can override that choice. “GCC-built reference” below means this default recipe, not a property conferred by the filename.

We therefore have two ways to build a program that is supposed to implement M2-Planet:

- The Forth compiler builds `cc-out-v1`
- The host reference compiler builds `m2-ref`

Both artifacts are executable files. They need not contain the same instructions, runtime arrangement, or file layout to implement the same computation. C19 already showed how one compiler chooses a particular entry stub and runtime prefix. Comparing compiler ELF bytes would ask whether the *implementations themselves* were byte-identical. Stage A asks a different, operational question: do these two implementations emit exactly the same output for the chosen input?

Source: [the two producer builds in `stage-a-check.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/stage-a-check.sh#L42-L56) and [the reference compiler selection and build](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/build-gcc-refs.sh#L24-L43).

## Run both programs on the same demanding input

The chosen input is M2-Planet's own source again. This is **self-compilation**: a compiler processes the source of its own implementation. It is a useful workload because it requires the newly built program to do substantial compiler work. The word does not yet promise that the result is an executable copy of that program.

In these invocations, M2-Planet emits **M1 text**, an assembly representation consumed by later tools. We can compare its bytes without knowing what every line means. C21 and C22 will open the assembler side of that boundary.

The script gives both producers the same ordered list of eleven explicit source files and these same choices:

- `--architecture amd64` selects the architecture described by the emitted text
- `--expand-includes` asks M2-Planet to expand included source
- Each `-f` supplies the next source filename, in order
- `-o` supplies that branch's destination filename

These options belong to the M2-Planet executables we just built. They are not new options of the Forth builder. `cc-out-v1` runs as a 64-bit process here; the architecture of a compiler process and the architecture selected for its output are separate facts.

Both invocations also use the M2-Planet checkout as their **working directory**, the directory from which relative filenames are resolved. Holding only the filenames constant would be insufficient if an included filename resolved to different content in the two executions. The full list and include identity appear in the input-reference session.

The following is a reading diagram, not a shell command. Each downward arrow means “run this producer with these inputs to create the named file”:

```text
cc-out-v1 executable                 m2-ref executable
         +                                   +
ordered M2-Planet source             same ordered source
amd64 + expand-includes              same flags and directory
         |                                   |
         v                                   v
self-v1-amd64.M1                     self-ref-amd64.M1
                 \                 /
                  exact byte comparison
```

Text equivalent: the Forth-built M2-Planet and the reference-built M2-Planet separately read the same comparison input. Each writes an M1 text file. The comparison consumes those two text files, not the two executable producers.

There are now four named artifacts to keep apart:

| File | Representation | Role in this comparison |
|---|---|---|
| `cc-out-v1` | Executable ELF | First M1 producer |
| `m2-ref` | Executable ELF | Reference M1 producer |
| `self-v1-amd64.M1` | M1 text | First compared result |
| `self-ref-amd64.M1` | M1 text | Second compared result |

Before continuing, cover the last two rows and reconstruct them. If you put `cc-out-v1` beside `m2-ref` at the final comparison, add the missing invocation between each compiler file and its text output.

## The final question is byte-for-byte

Here is the actual comparison from the script:

```sh
cmp "$BUILDROOT/self-v1-$ARCH.M1" "$BUILDROOT/self-ref-$ARCH.M1" \
    || fail "v1 != reference at $ARCH"
```

A **shell** is the program reading this recipe and launching commands. `BUILDROOT` is its chosen output-directory value; `$BUILDROOT` inserts that value. `ARCH` is set to `amd64`, so `$ARCH` supplies that spelling in both filenames. Quotes keep each expanded path one argument. The backslash at the line end continues this one command across the next displayed line.

`cmp` compares the two files byte by byte. A successful command reports exit status zero to the shell. `|| fail ...` means that if the comparison reports failure, the script runs its failure handler and exits unsuccessfully. A failure can mean different bytes or an inability to compare the files; the underlying diagnostic matters.

No step removes spaces, comments, or differing labels before this comparison. To see what that demands, use two tiny *illustrative* files, not claimed extracts from M1 output:

```text
left bytes:   41 0A        letter A, newline
right bytes:  41 0A        letter A, newline
```

These bytes match. Now insert one ASCII space before the right newline:

```text
left bytes:   41 0A
right bytes:  41 20 0A
```

The second byte differs, and the lengths differ. A reader might regard the space as unimportant, but this comparison rejects it. Conversely, equal file lengths would not establish equal content.

After both self-compilations and `cmp` succeed, the script counts the newly produced v1 text file and prints the equality line and `PASS`. There is no separate nonempty-output check, required byte count, or stored-hash check. Thus even two empty files would satisfy the byte comparator; the observed count tells us the recorded result below was not that case.

Source: [the same input vector, both invocations, comparator, and reporting](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/stage-a-check.sh#L59-L78).

## Read a result without making it larger

We have both a recipe to inspect and a completed execution record to read. They are different kinds of evidence.

The automatic [Check run 37474668625](https://github.com/delta9000/seed-forth/actions/runs/37474668625) completed successfully on 2026-10-06. Its [check-all + verify job](https://github.com/delta9000/seed-forth/actions/runs/37474668625/job/112306844449) records the standalone Stage-A step as OK and reports equality of `self-v1-amd64.M1` and `self-ref-amd64.M1`, with **2,367,260 bytes**. The equality summary is timestamped `14:04:51.7876120Z`.

That is an observed remote run, rather than another source-derived prediction. The Stage-A, chain, and verification source-file contents in that run match this book’s chosen revision. The later source-reference session records the environment and the limits of the surviving log. No new local compiler or teaching example was run for this chapter.

What can we conclude? In that recorded context, the two differently built M2-Planet programs produced equal M1 text for the named self-source input. This adds evidence that the Forth-built program performs this substantial task in agreement with the reference.

It does not establish agreement for every C program. It does not compare `cc-out-v1` with `m2-ref`, assemble either M1 result, or show that all internal computations were correct. An error could be irrelevant to the observed output, or both producers could agree on a wrong result. The check still has value: it demands equality of the actual final representation across two producer routes, rather than accepting a plausible-looking listing.

### Change the question by one step

Suppose both producers return status zero, but the right M1 file contains the extra space from our small example. Does Stage A pass? It fails at `cmp`. Producer success and comparison success are separate conditions.

Now suppose some later assembler ignores that space and emits equal executable bytes from both files. Would this rescue Stage A? No: its chosen acceptance condition remains exact M1 equality. Equal later executables would be a different result, from an additional transformation and comparison. We will return to that distinction after the recipe details.

**Stop/resume point.** Keep this sentence: “v1 and ref are programs; self-v1 and self-ref are text; the comparison comes after both programs run.” To resume, name the two `cmp` operands and one claim their equality does not establish. You can attempt C20-01 now; the remaining sessions explain how the recipe preserves these identities and where it can fail.

## Choose a second session

The first story ended at its observed comparison. Choose the detail that would help you reconstruct or diagnose it:

- **What exactly went in?** Read the three input lists, then try C20-02 and C20-03
- **Which file did the wrapper save?** Read the output and environment sessions, then try C20-04
- **What can a result support?** Read the evidence and wider-chain sessions, then try C20-05 through C20-08

The lists are reference material. Remembering every filename is less useful than knowing which list belongs to which producer and where to find its exact order.

## Reference: the first build needs three different input lists

The two-stage story contains three lists that are easy to mistake for one another: the Forth program loaded into the seed, the C monolith compiled by that program, and the source arguments later passed to both M2-Planet executables. A **monolith** here means one prepared C text made by concatenating several source files. It is not the later list of eleven `-f` arguments.

### First list: load the Forth driver last

`cat` copies input files to its output in the order named. A **pipe**, written `|`, feeds one program's output into another program's input. The monolith helper uses those operations to send the Forth library, compiler layers, and finally the C monolith into `seed-forth`.

The selection rule in [`tools/compiler-layers.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tools/compiler-layers.sh#L1-L10) matches filenames with three initial digits followed by `-cc-` and ending in `.fth`. It lists matching files in the shell's filename-expansion order, omitting `120-cc-main.fth` until the end. Its optional argument selects a root directory, defaulting to `.` (the current directory). The helper lists names; it does not verify source identities or enforce a fixed count. For the pinned tree, the full stream begins with these **32 Forth files**, counting `010`:

```text
010-lib.fth
020-cc-arena.fth
030-cc-io.fth
040-cc-prep.fth
050-cc-lex.fth
060-cc-types.fth
070-cc-sym.fth
080-cc-elf.fth
081-cc-object.fth
090-cc-emit.fth
100-cc-expr.fth
110-cc-decl.fth
112-cc-stmt.fth
114-cc-func.fth
115-cc-native.fth
116-cc-prog.fth
117-cc-native-program.fth
118-cc-native-init.fth
119-cc-native-runtime.fth
121-cc-sysv.fth
122-cc-sysv-runtime.fth
123-cc-object-program.fth
124-cc-target.fth
125-cc-consteval.fth
126-cc-varargs.fth
127-cc-binary64.fth
128-cc-float-literal.fth
129-cc-bitfield.fth
131-cc-aggregate-abi.fth
132-cc-long-double.fth
140-cc-link.fth
120-cc-main.fth
```

The prepared C text follows immediately. The Forth files are copied without removing their comments; the seed's reader handles Forth comments itself. `130-asm.fth` is absent because it does not match the `-cc-` pattern.

Why hold 120 back? Its final bare `cc-main` executes the driver, which reads the remaining input as C, produces its output, and ends the builder. A library placed after that call would arrive during C input, too late to define a Forth dependency. The relevant rule is “all needed definitions before the invocation,” not “smallest filename number first.” C19's [last-file session](19-translation-units-and-process-entry.md#reference-the-last-file-executes-not-merely-defines) supplies that transition.

Loading optional provider definitions does not select their profiles. The [actual driver](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/120-cc-main.fth#L28-L40) calls the legacy `cc-parse-program`; it does not thereby switch to native LP64, System V, or relocatable-object output. Extra matching files in a changed working tree would also change the actual stream, so the list above is an edition-specific input census.

### Second list: construct the C monolith

The [monolith helper's construction loop](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/build-m2planet-monolith.sh#L63-L80) first copies four headers **unchanged**, in this order:

```text
cc.h
cc_globals.h
cc_emit.h
gcc_req.h
```

It then processes these nine C files, in order:

```text
M2libc/bootstrappable.c
cc_globals.c
cc_strings.c
cc_types.c
cc_macro.c
cc_reader.c
cc_emit.c
cc_core.c
cc.c
```

Each C file passes through `sed`, a line-processing tool. For this recipe, three deletion patterns matter:

```text
^#include[[:space:]]*"
^#define TRUE 1
^#define FALSE 0
```

`^` means the start of a line; `[[:space:]]*` means zero or more whitespace characters. A C-file line matching any of these patterns is omitted. These are textual patterns, not parsed C directives. Thus `#include "cc.h"` is removed, while a line beginning with two spaces and then `#include "cc.h"` survives this filter. The define patterns match prefixes: a line beginning `#define TRUE 10` also matches the second pattern.

The filter applies to the nine C files, not to the four-header prefix. This preparation preserves a historical input shape; it is not evidence that the current preprocessor lacks conditional-inclusion support. The helper comment says eight C files, but its executable loop names nine. The loop determines the recipe.

There is also an optional input edit. With `STAGE0_COMPAT=1`, two specified guard expressions are replaced with constant zero and a comment. With the default setting, the extra substitution list is empty. These textual substitutions apply only in the C-file loop, and the helper does not assert how many replacements occurred. This changes the compiled program; it is not cosmetic whitespace cleanup. The wider-chain session explains which comparison that mode targets.

### A retained include makes the working directory an input

Even after the C-file filtering, the unchanged `cc.h` contains `#include "cc_globals.h"`. You can inspect that line in the [pinned upstream header](https://github.com/oriansj/M2-Planet/blob/0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb/cc.h#L181).

The helper runs the legacy Forth compiler from the seed-forth repository root. In this profile, [include loading](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/040-cc-prep.fth#L851-L867) first tries the literal filename. If that fails, it tries `tests/cc/` plus the filename. A clean pinned root has no top-level `cc_globals.h`, so that lookup can reach `tests/cc/cc_globals.h`.

The [repository fixture](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/cc_globals.h) and the [upstream header](https://github.com/oriansj/M2-Planet/blob/0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb/cc_globals.h) have the same Git blob identity, `0633b632d001175429a8217653a0e1b3b89300b7`. That is a checked source-identity fact at these pins. An unexpected root file or a different checkout could change the lookup's result.

The separate `bootstrap.sh` route compiles its monolith with the working directory inside M2-Planet, so the literal include reaches the upstream copy directly. The equal header content connects these particular routes; assuming that relative includes always find the same bytes would hide the dependency.

### Third list: give both M2-Planet programs the same arguments

For the final comparison, the script switches the working directory to the absolute M2-Planet checkout and uses this exact argument order:

```text
--architecture amd64 --expand-includes
-f M2libc/bootstrappable.c
-f cc_reader.c
-f cc_strings.c
-f cc_types.c
-f cc_emit.c
-f cc_core.c
-f cc_macro.c
-f cc.c
-f cc.h
-f cc_globals.c
-f gcc_req.h
```

Each invocation then receives `-o` and its own output path. The eleven explicit files are neither the thirteen-piece monolith recipe nor its ordering. Included files contribute additional source bytes when `--expand-includes` is active. A reproducible input description therefore needs the ordered arguments, source contents, include contents, flags, and working directory.

This is a controlled pair: changing only the output pathname directs the two results into different files. Reordering one branch's input list would change the question before we learned anything about the two compiler implementations.

## Reference: where the compiler file actually lands

C19's driver contains the fixed path `/tmp/cc-out`. Stage A instead wants a file named `cc-out-v1` under its chosen output directory. The bridge is a **wrapper**, a surrounding program that prepares inputs and handles the underlying program's outputs.

Stage A invokes that wrapper with:

```sh
CC_OUT="$BUILDROOT/cc-out-v1" ./tests/cc/build-m2planet-monolith.sh
```

An assignment before a command supplies an **environment variable** to that command: a named setting the program can read. Here `CC_OUT` belongs to the shell wrapper. It does not replace the twelve path bytes inside the Forth driver or add a Forth command-line option.

Before this call, Stage A removes its old `cc-out-v1` and files matching `self-*-amd64.M1`, preventing those retained products from substituting for a failed fresh result.

The [wrapper](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/build-m2planet-monolith.sh#L36-L55) makes the destination parent directory and converts `CC_OUT` to an absolute path. It removes the old destination and `<CC_OUT>.tmp`, then recreates that temporary directory. It chooses these paths:

| Item | With Stage A's `CC_OUT` | Direct call without `CC_OUT` |
|---|---|---|
| Prepared C text | `cc-out-v1.monolith.c` beside the destination | `/tmp/m2planet-monolith.c` |
| Requested retained compiler | `$BUILDROOT/cc-out-v1` | `/tmp/cc-out` |
| Possible private temporary directory | `$BUILDROOT/cc-out-v1.tmp` | None |
| Path the Forth driver opens | `/tmp/cc-out` | `/tmp/cc-out` |

The unchanged last row is the important one. If supported, the wrapper gives the Forth process a private view of `/tmp`: opening `/tmp/cc-out` in that process then writes a file physically stored under `cc-out-v1.tmp`. A Linux **mount namespace** permits this process-specific path view, and a **bind mount** makes the chosen directory appear at `/tmp`. You need only that path contract to read the recipe; no namespace configuration is required here.

The helper probes `unshare -rm` with a bind mount. A successful probe is a preliminary operation; the actual compiler launch performs its own mount in a new invocation and can still fail. If the probe fails, it leaves the output at the real, shared `/tmp/cc-out`. This fallback is part of the implementation, despite a stronger comment in the calling Stage-A script. Separate `BUILDROOT` values do not prevent two fallback executions from colliding at that shared file. Even with private temporary views, two runs sharing one `BUILDROOT` collide on their retained inputs and outputs.

When the private path is used, the [execution branch](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/build-m2planet-monolith.sh#L82-L106) opens the input pipe and seed executable before changing the `/tmp` view. It keeps the seed open as file descriptor 3, an already-open file handle, and executes it through `/proc/self/fd/3`. This preserves access even if the seed's ordinary pathname lies under the directory being covered.

Before preparing the source, the wrapper repeats the two M2 sentinel checks and conditionally calls `build.sh` if root `seed-forth` is not executable. Unlike Stage A, it has no second explicit executable-seed test after that call.

The wrapper removes the selected old output, runs the pipeline, and records its exit status. It rejects a nonzero status or a missing regular output file. On success it moves the file to `CC_OUT`, removes the private temporary directory when used, and marks the compiler executable. Its final `OK` line reports the byte count, path, and recorded compiler status; it enforces no particular size or hash. Stage A additionally tests that the destination is executable.

Those checks are useful but have different strengths. A regular-file test does not validate ELF structure. Executable permission does not show that the program has run. C19's [writer](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/030-cc-io.fth#L171-L195) requests one write and discards its write/close results. Later successful self-compilation and comparison add observations that the output-exists check alone cannot supply.

## Reference: establish the comparison environment

The [Stage-A setup](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/stage-a-check.sh#L20-L47) begins by changing to the repository root. `cd` changes the working directory. It defaults `M2_PLANET` to `vendor/M2-Planet` and `BUILDROOT` to `/tmp/seed-bootstrap`, creates the latter directory, and defines a failure handler that prints a reason and exits with status one.

The shell settings `set -euo pipefail` make many unhandled command errors, unset-variable uses, and pipeline failures terminate the script. They are not a replacement for reading the explicit checks: shell error handling has context-dependent exceptions, and the recipe uses `|| fail` around important operations.

An executable root `seed-forth` is reused. If it is absent or not executable, Stage A calls `build.sh`, which uses the external assembler selected by `HEX0` to assemble `000-seed.hex0`, then sets executable permission. The build script first changes to its own repository root, so a relative `HEX0` is resolved there. Its default assembler path is `vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed`. If the selected `HEX0` is not executable, `build.sh` prints setup/override guidance and exits with status one before assembly. Otherwise its central call supplies `000-seed.hex0` as input and root `seed-forth` as output. It reports the resulting byte count rather than requiring a particular count. Stage A tests executability again afterward. Neither that test nor [`build.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/build.sh#L14-L29) verifies the seed's hash. In particular, an executable leftover seed is not silently given a fresh provenance check.

Next the script checks that M2-Planet's `cc.c` and nested `M2libc/bootstrappable.c` exist. These **sentinels** are representative required files, not a verification of every source byte. It converts the M2 and build directories to absolute paths so that later `cd` operations do not redirect their meanings.

### The reference helper builds more than Stage A consumes

The helper requires exactly one argument: the destination directory. Any other argument count prints usage and exits with status two. After prerequisite checks it recursively removes that entire destination, recreates it, and obtains its absolute path as `D`. Making `D` absolute preserves the output location while the builds change working directory. The helper rebuilds its destination afresh; it does not call `make` or reuse a submodule's old compiler binary. It defaults `CC` to `gcc` and `MESCC_TOOLS` to `vendor/mescc-tools`, checks that the selected C compiler is available, and requires source sentinels in both M2-Planet and mescc-tools.

Here are the three [actual reference builds](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/build-gcc-refs.sh#L24-L50):

| Working directory | Compiler flags | Source order | Output below `gcc-ref/` |
|---|---|---|---|
| M2-Planet | `-D_GNU_SOURCE -O0 -std=c99` | `M2libc/bootstrappable.c cc_reader.c cc_strings.c cc_types.c cc_emit.c cc_core.c cc_macro.c cc.c cc.h cc_globals.c gcc_req.h` | `m2-ref` |
| mescc-tools | `-D_GNU_SOURCE -std=c99 -fno-common` | `M1-macro.c stringify.c M2libc/bootstrappable.c` | `M1-ref` |
| mescc-tools | `-D_GNU_SOURCE -std=c99 -fno-common` | `hex2.c hex2_linker.c hex2_word.c M2libc/bootstrappable.c` | `hex2-ref` |

These host-compiler flags are part of the recorded recipe: they define `_GNU_SOURCE`, select C99, select no optimization for `m2-ref`, and request non-common global handling for the two tools. None is an option supplied to the Forth compiler.

Stage A copies `gcc-ref/m2-ref` to `$BUILDROOT/m2-ref`. It does not use `M1-ref` or `hex2-ref` in its final comparison. Nevertheless, their sources and builds are dependencies of the helper it calls. If mescc-tools is missing, Stage A can stop before either M1 comparison file exists, even though its own final operation needs no assembler.

The helper reports the selected compiler's version, but Stage A discards the helper's standard output. A **standard output** stream is a program's ordinary output channel, separate from its error-reporting stream. A retained top-level Stage-A success message therefore need not contain the reference compiler's version. Record that identity separately when reproducing a result.

## Reference: diagnose the first failed boundary

Treat each step as a question that must be answered before the next question becomes meaningful:

| First failed boundary | What has not yet been established | Useful next evidence |
|---|---|---|
| Seed or source prerequisite | The selected recipe can begin | Seed path/identity; missing sentinel and source checkout |
| Reference helper | A usable reference producer was built | Selected `CC`; M2 and mescc-tools inputs; helper diagnostic |
| Monolith wrapper | A usable v1 file was retained | Prepared input; pipeline status; selected physical output path |
| v1 self-compilation | v1 produced this branch's M1 successfully | v1 diagnostic, arguments, directory, output file |
| Reference self-compilation | Reference produced its M1 successfully | Reference diagnostic and the same context |
| Final `cmp` | Exact equality was established | Both files, comparator status, and its original diagnostic |

The final Stage-A handler says `v1 != reference at amd64` for any nonzero `cmp` result. If one file cannot be read, that message is not itself evidence of two different byte sequences. Preserve the underlying diagnostic rather than diagnosing a compiler bug from the summary.

As a worked example, suppose a log says `gcc reference build failed`, the M2 sentinels exist, and `vendor/mescc-tools/M2libc/bootstrappable.c` is absent. The reference helper checks that missing file before compiling its three outputs. The observed failure is consistent with a missing prerequisite. We have no final M1 parity result, and changing the Forth expression parser would not address the first failed boundary.

A different case reaches both successful self-compilations and then reports a first differing byte. That is a genuine comparison failure worth investigating. It still leaves several candidates: changed inputs, mismatched flags or include lookup, an inherited compatibility mode, a different reference compiler, or a translation fault. The test detects disagreement; it does not locate the cause by itself.

## Reference: source identity and recorded evidence

A source revision identifies the recipe we are reading. A run identifies an occasion on which some recipe was executed. Connecting them requires more than finding the same script name.

### The input identities for this edition

The seed-forth implementation revision is `bbcc1732152af2d884737272eed870d2410ffe8e`. Its recorded submodule identities include:

| Source checkout | Commit |
|---|---|
| M2-Planet | `0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb` |
| M2-Planet's M2libc | `eee5091e7a1af90b7b87389153647be9a24a8cdd` |
| mescc-tools | `9b1375115f9175d876c360dbbfd7e231dd9f2a2f` |
| mescc-tools' M2libc | `5a7c12a7be39cbce113c5459d77467b829a1ecc5` |
| stage0-posix | `45d90f5955b6907dc6cdea9ebafce558359edcd3` |
| stage0-posix's bootstrap-seeds | `cedec6b8066d1db229b6c77d42d120a23c6980ed` |

A **submodule** is a separately versioned source checkout whose selected commit is recorded by the containing repository. The two M2libc rows are distinct dependencies, even though they share a directory name. The stage0-posix and bootstrap-seeds rows matter to the default seed-assembler route when the root seed needs building; the final Stage-A comparison does not execute a full stage0 chain.

The public [pinned source tree](https://github.com/delta9000/seed-forth/tree/bbcc1732152af2d884737272eed870d2410ffe8e/vendor), [upstream table](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/REPRODUCIBLE.md#L18-L61), and [M2-Planet](https://github.com/oriansj/M2-Planet/tree/0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb), [mescc-tools](https://github.com/oriansj/mescc-tools/tree/9b1375115f9175d876c360dbbfd7e231dd9f2a2f), and [stage0-posix](https://github.com/oriansj/stage0-posix/tree/45d90f5955b6907dc6cdea9ebafce558359edcd3) trees locate those dependencies. Stage A itself checks file presence, not these commit values or a clean checkout.

### A recorded hash is not a performed hash check

A **hash** is a compact digest of file content. Recording a digest helps identify a particular artifact; merely printing a known digest beside an unexamined file would not establish its identity.

The pinned [`REPRODUCIBLE.md` Stage-A record](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/REPRODUCIBLE.md#L301-L323) reports a 202,405-byte `cc-out-v1`, a 2,367,260-byte `self-v1-amd64.M1`, and these SHA-256 values:

```text
seed-forth
697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e

cc-out-v1
025208db31342c4070dbcd3b72f56ddfdde7d38c582c96ea9fdc59bcc6ef7d1e

self-v1-amd64.M1
22465aa1b4943b830263928f79bb150bbfcbbc1642cfc287b0ed3d873a583d37
```

These are attributed historical output records. The Stage-A script does not enforce them, and they are not hashes observed from downloadable artifacts of the later CI run. The Git blob identity used for the header earlier identifies a source object by a different mechanism; it is not one of these executable/output SHA-256 values.

Likewise, the original book's triangle transcript reports 1,241 bytes and an artifact hash. It is not a newly verified expectation for this edition's examples. C19's 556-byte result is instead a derivation for its explicitly stated `return 7` profile. Keep the input and evidence kind attached to each number.

### What the completed CI run preserves

The [public check job](https://github.com/delta9000/seed-forth/actions/runs/37474668625/job/112306844449) supplies an execution observation at head `764bdc4f4902d613145f361da6a7f33010dd37b4`. The workflow, `check-all.sh`, `verify.sh`, Stage-A script, and chain script have identical blobs at that head and the teaching pin. The checkout records the dependency commits listed above.

Its host report names Ubuntu 24.04.5 LTS, Linux `6.17.0-1022-azure` on x86-64, GCC 13.3.0, and Bash 5.2.21. It reports a preliminary successful namespace-availability test; it does not preserve a mount trace for every inner invocation.

For the standalone verification step, the outer build root is:

```text
/home/runner/work/seed-forth/seed-forth/build-out/verify
```

The [verification caller](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/verify.sh#L143-L149) passes its `stage-a` child directory as `BUILDROOT`. Thus the exact compared pair has that outer path followed respectively by:

```text
/stage-a/self-v1-amd64.M1
/stage-a/self-ref-amd64.M1
```

The job reports standalone Stage A OK and the 2,367,260-byte equality at `14:04:51.7876120Z`. It also reports the separate wider-chain results discussed next. The available job log contains selected child summaries, not the complete inner transcripts. The run has no downloadable output artifacts and no printed Stage-A SHA-256. We can read its reported successful comparison but cannot inspect those actual M1 bytes from an attached artifact here.

The same run's [mdBook job](https://github.com/delta9000/seed-forth/actions/runs/37474668625/job/112306845085) passed for the original `book/` source selected by the repository's [root configuration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/book.toml). That is not an execution record for the new `books/c-compiler/` teaching examples. A green overall run also does not erase skipped work: the optional gcc64 verification was explicitly skipped.

### Keep a result's perimeter visible

For a future reproduction, preserve enough information to answer four questions:

1. **Which inputs?** Project and dependency commits, modifications, the prepared monolith, residual include identity, ordered arguments, flags, and working directory
2. **Which producers?** Reused or rebuilt seed identity, external `HEX0` when used, actual `CC` path/version, effective overrides, host profile, and namespace/fallback outcome
3. **Which artifacts and predicate?** Both compiler identities, both M1 files or durable artifact locations, sizes/digests, statuses, exact `cmp` operands, and diagnostics
4. **Which observation?** Run identifier and time, retained logs, failed or skipped steps, and missing evidence

The existing CI observation answers some of these more strongly than others. Missing artifacts are a limit on later inspection, not a reason to pretend its printed comparison never ran.

Stage A also has a trust perimeter: it depends on the chosen seed and Forth/C sources, source preparation tools, host services, reference compiler, and comparator behaving as assumed. Freshly rebuilding the reference avoids certain stale-file mistakes; it does not make that compiler infallible. Byte equality is a precise finite observation, not a trust-free proof or a demonstration that all possible exercised internal paths were correct.

## Reference: follow the wider chain without changing the comparison

Only after the two-text-file story is clear should we add another generation. The larger [`bootstrap-chain.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/bootstrap-chain.sh#L117-L149) first runs `bootstrap.sh` freshly. It obtains its v1 compiler and its M1/hex2 assembly tools from that route, rather than obtaining v1 from the standalone monolith helper. Its default output architectures are `x86` and `amd64`.

An **assembler** translates the textual instruction representation into machine bytes. For the next table, treat the M1/hex2 pair as a named transformation with additional architecture definitions, runtime text, ELF envelope, and options. The implementation of that transformation belongs to C21/C22. M1 text alone is not its entire input.

For one selected architecture, the wider chain has these steps:

| Label | Operation or comparison | Representation that matters |
|---|---|---|
| A | v1 and reference each compile the self-source; compare `self-v1-$ARCH.M1` with `self-ref-$ARCH.M1` | M1 text, as in standalone Stage A |
| B | Assemble v1's self-output into `cc-out-v2-$ARCH` | Text becomes a target-architecture executable |
| C | v1 and v2 compile `int main() { return 42; }`; compare `tiny-v1-$ARCH.M1` with `tiny-v2-$ARCH.M1` | A separate small-input text comparison |
| D | v2 compiles the self-source into `self-v2-$ARCH.M1`; report whether it equals v1's text | Self-compilation must succeed; a text difference is allowed |
| E | Assemble v2's self-output into `cc-out-v3-$ARCH` | Another producer executable |
| F | v3 compiles the self-source; compare `self-v2-$ARCH.M1` with `self-v3-$ARCH.M1` | Successive producers' M1 text |
| G | v3 compiles a hello program; assemble it, run it, and check captured text and zero exit | A generated program's behavior |

Source: [the actual A–G operations](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/bootstrap-chain.sh#L169-L270). G checks a shell-captured string; shell command substitution removes trailing newlines. Its string test is not a raw stdout-file byte comparison.

At F, the exact comparator is:

```sh
cmp "$BUILDROOT/self-v2-$ARCH.M1" "$BUILDROOT/self-v3-$ARCH.M1"
```

A **fixed point** here means that those two generations emit the same self-source text under the controlled recipe. The shortened log wording `self-v2 == self-v3` must retain that `.M1` meaning. It does not say the compiler ELFs `cc-out-v2` and `cc-out-v3` are equal.

### Why default v1 and v2 need not emit the same text

The recipe documents a specific compiler-family difference. In the relevant guard, a nonzero architecture-family value is combined with a true register test using `&&`. The Forth-built and GCC-built producers use C's logical meaning. For supplied values 8 and 1, `8 && 1` is one. The M2-Planet-family behavior described by the chain uses bitwise AND at this point, so `8 & 1` is zero: binary `1000` and `0001` share no set bit. For the x86 family value four, `4 & 1` is also zero.

That changes whether certain short add/sub-immediate forms are selected. The wider chain therefore permits D's v1/v2 text difference while requiring F's v2/v3 text equality. Permitting the difference does not permit the v2 self-compilation itself to fail.

The monolith helper's optional `STAGE0_COMPAT=1` edits these exact guard spellings:

```text
(Architecture & ARCH_FAMILY_X86) && (reg == REGISTER_STACK || reg == REGISTER_ZERO)
(Architecture & ARCH_FAMILY_X86) && (reg == REGISTER_ZERO)
```

It replaces each matched expression with `0 /* STAGE0_COMPAT: see REPRODUCIBLE.md */`. This deliberately suppresses the choice in v1. Stage A does not clear an inherited `STAGE0_COMPAT`, while its reference build uses the original sources. The pinned [compatibility record](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/REPRODUCIBLE.md#L431-L440) and [mode explanation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/REPRODUCIBLE.md#L516-L524) report that this mode changes the expected Stage-A relationship and makes that default-reference comparison fail by design. It targets agreement with a later M2-built producer, rather than repairing the default reference check.

We are using the documented recipe distinction to interpret these tests. It is not a claim that arbitrary logical expressions or all generated programs are equivalent across the two compiler families.

### Keep the genuine ELF comparisons separate

There are nearby checks of executable bytes, but their operands answer different questions:

- The [chain's cross-route checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/bootstrap-chain.sh#L280-L284) compare its `cc-out-v2-amd64` with `bootstrap.sh`'s `cc-out-v2`, and separately its v3 with that route's v3. They compare **the same generation across routes**, not v2 with v3
- [`verify.sh`'s monolith check](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/verify.sh#L149) compares standalone Stage A's v1 ELF with `chain/bootstrap/out/cc-out-v1`. Neither side is `m2-ref`
- [`bootstrap.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/bootstrap.sh#L230-L262) compares v2 produced through M1/hex2 with v2 produced through the Forth assembler. It also compares rebuilt M1 and hex2 executables with their preceding tool artifacts

The observed CI job reports chain A equality for x86 at 2,326,006 text bytes and amd64 at 2,367,260. It reports F equality for x86 at 2,358,665 text bytes and amd64 at 2,400,072. The F counts are M1 sizes. The same-generation cross-route ELF summary and the separate monolith check also passed. No compiler-ELF sizes or hashes accompany those particular summary comparisons.

### A wider test count still has a selection rule

After its architecture chains, the script selects the first `.c` file listed in each `test/test*` directory, not every C file in every directory. From the M2-Planet working directory, it runs v1 and the reference with `--architecture x86 --expand-includes`, one selected source, and a 30-second timeout.

Its [classification rule](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/tests/cc/bootstrap-chain.sh#L286-L316) is:

1. Both statuses zero: compare their emitted files with `cmp -s`; a successful comparison increments `identical`, while any nonzero comparison result increments `differ`
2. Statuses different: increment `differ`
3. Same nonzero status: increment `both-fail`

The `-s` option suppresses comparator messages. Thus a missing or unreadable output can also increment `differ`; that counter alone does not establish two unequal byte sequences. Only nonzero `differ` fails this part of the harness. A matching timeout can therefore count as `both-fail`; that label does not establish a common syntax rejection. The observed job reports `identical=36`, `both-fail=0`, `differ=0`, of 36. Those are comparisons of emitted text, not executions of all 36 generated programs, and the summary does not enumerate the selected filenames.

### Equality through a later transformation goes one way

Suppose two M1 files are equal. If we also hold the assembler implementation, all extra inputs, all options, and relevant environment constant, and that complete transformation is deterministic, their later executable outputs must be equal. **Deterministic** means the same complete input yields the same output.

The converse need not hold. An assembler might ignore comments, so two different texts could map to the same bytes. Exact text equality is not interchangeable with exact ELF equality. Stage A performs the text comparison directly; no assumption about an unperformed assembly step is needed to state its result.

C21/C22 own assembly mechanisms. C23/C24 own the later native/private-stack and TinyCC contracts. The G volumes' downstream toolchain work and the K volumes' loading and Linux work have their own inputs, acceptance tests, and evidence. Stage A runs on Linux; it does not build or boot Linux. Neither an optional later route nor an overall green CI summary can supply a missing result for those separate tasks.

## Optional retrieval: the prologue program

Set the compiler-building story aside briefly and retrieve the builder/target distinction with the [original prologue's Fibonacci source](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/book/00-prologue.md#L9-L17):

```c
int fib(int n) { if (n < 2) return n; return fib(n - 1) + fib(n - 2); }
void print(int n) { if (n > 9) print(n / 10); putchar('0' + n % 10); }
int main(void) {
    int i;
    print(0);
    for (i = 1; i < 12; i = i + 1) { putchar(' '); print(fib(i)); }
    putchar('\n');
    return fib(10);
}
```

Before reading the next paragraph, predict the requested character count and return value. They need not be the same number.

Under the chapter's admitted-compilation, sufficient-resource, and successful target-write assumptions, the source predicts `0 1 1 2 3 5 8 13 21 34 55 89` followed by a newline. Seven one-digit values and five two-digit values request seventeen digit characters; eleven spaces and one newline bring the total to **29 requested character bytes**. The return expression is `fib(10)`, so it predicts **55**. These are source-derived results, not an observed run or a Stage-A input. The Forth builder finishes before any of those target calls print a digit.

For an answer-free change, make the loop condition `i < 10` and the return expression `fib(8)`. Recompute both quantities without borrowing the original count. If you want a smaller repair step, first list the values selected by the changed loop; only then count digits and separators.

## Optional operator recipe

The paper path above is complete without executing a build. This section describes a deliberate future standalone Stage-A run; it is not an execution report for the displayed command.

Use a Linux/x86-64 environment with Bash and the helper's standard file/text utilities, a suitable host C compiler, the pinned project and recursively initialized upstream sources, and a known root seed or the selected external `HEX0` assembler. Use the default legacy producer profile and record all overrides. This standalone amd64 check does not need the wider chain's x86 executable support.

From the repository root, an invocation with an explicitly selected reference compiler and default compatibility behavior is:

```sh
BUILDROOT="$PWD/build-out/c20-stage-a" CC=gcc STAGE0_COMPAT=0 \
    tests/cc/stage-a-check.sh
```

Here `$PWD` is the shell's current-directory value. **Before choosing that directory, make sure it is new or disposable. Reusing output directories is destructive.** The helper removes and recreates the entire `gcc-ref` subdirectory. Stage A removes its previous v1 and matching `self-*-amd64.M1` files; the monolith wrapper removes its destination and temporary directory. A shared-`/tmp` fallback also removes and reuses `/tmp/cc-out`. Do not run concurrent producers that can share any of these paths; choosing different `BUILDROOT`s alone is not sufficient isolation.

Preserve the evidence listed in the previous session alongside the actual exit status. If the script fails, stop at the first failed boundary rather than reclassifying a missing prerequisite as a byte mismatch. If it succeeds, use its actual count and retained files; do not paste the historical hashes into your record as though you measured them.

## Practice: identify the artifact before judging the result

These are paper tasks. Use the recipe lists as references; no build, mount, compiler, or generated-program execution is requested. The [graduated hints and worked solutions](../practice/20-solutions.md) are separate so you can choose how much support to use. For each answer, state the artifact type and the assumption that makes your conclusion valid.

### C20-01 — Recover the missing invocation

A diagram contains the four names `cc-out-v1`, `m2-ref`, `self-v1-amd64.M1`, and `self-ref-amd64.M1`, but its arrows have been erased. Reconstruct the producers, their inputs, and the exact final compared pair. Which two files are executable programs? Which command options belong to those programs rather than to the Forth builder?

Then diagnose this proposal: “To strengthen Stage A, replace its two `cmp` operands with `cc-out-v1` and `m2-ref`; they are both compilers, so equal behavior requires equal ELF bytes.” Identify the changed question without predicting a first differing byte.

### C20-02 — Complete the input stream

A partial list is:

```text
010, 020, ... 118, 119, ___, 122, ... 129, 131, 140, ___, prepared C
```

Fill the two numbered positions and explain the event that makes their order necessary. A proposed repair inserts `130-asm.fth` and moves 120 between 119 and 121. Explain both changes against the actual selection rule. Does merely loading native or System V provider files select that profile?

For an independent change, suppose a new library named `135-cc-helper.fth` is added to the working tree. State how it enters the selected input and what additional evidence would be needed before attributing a later result to the original pinned stream.

### C20-03 — Trace the preparation, not an imagined preprocessor

Apply the actual monolith rule to these **illustrative source lines**, preserving the two leading spaces shown on C-file line C2. The labels H1/C1/etc. are annotations, not source characters.

```text
header H1: #include "cc_globals.h"
header H2: #define TRUE 1
C-file C1: #include "cc.h"
C-file C2:   #include "cc.h"
C-file C3: #include <stdio.h>
C-file C4: #define TRUE 10
C-file C5: #define FALSE 0
C-file C6: int flag;
```

List the retained lines in order and give a reason for each deletion. Then explain how the real retained `cc_globals.h` include resolves for the standalone helper under the clean pinned-root assumptions. What changes if a different `cc_globals.h` unexpectedly exists at the repository root? Do not assume the later compiler accepts every illustrative retained line; this task stops at preparation and input identity.

### C20-04 — Diagnose two different missing files

Record A says the Stage-A reference helper failed. M2-Planet and its M2libc sentinels exist; mescc-tools' M2libc sentinel is absent. Has the comparison found a Forth miscompilation? Identify the first blocked boundary and the dependency that explains it.

Record B says the private-`/tmp` probe failed, but all builds then succeeded. Two simultaneous runs used distinct `BUILDROOT` directories. Can those facts alone establish that the runs did not collide? Trace the underlying output path and the wrapper destination separately. Finally, change B so private temporary views work but both runs use the same `BUILDROOT`: identify a remaining collision.

### C20-05 — Attach the right evidence label

Classify each record as a derivation, a limited file/status observation, an attributed historical result, a reported remote execution result, or an unsupported conclusion. Rewrite any claim that is too strong.

1. C19's source trace reaches output cursor 556, so a 556-byte file has been written
2. A wrapper reports compiler status zero and an executable destination file, so its output matches the reference
3. Pinned `REPRODUCIBLE.md` lists the v1 SHA-256, so the later CI job must have measured that same hash
4. The named CI job reports successful exact comparison and 2,367,260 bytes for the two standalone M1 files
5. That job's book step passed, so the new C19 and C20 teaching examples have run

For a changed record, suppose a trustworthy run retains two empty output files, both producer statuses zero, and `cmp` status zero. Does the Stage-A comparator accept them? What conclusion survives, and what expectation needs separate evidence?

### C20-06 — Change one producer's preparation

Use the supplied guard values: `Architecture & ARCH_FAMILY_X86` is eight, and the register test is one. Calculate the result when the conjunction is logical `&&`, when it is bitwise `&`, and when the monolith substitution replaces the guard with zero.

Now set `STAGE0_COMPAT=1` only for the monolith route, keeping the reference build on its original sources. Explain why the documented default-reference Stage-A expectation no longer applies unchanged. Separately name the pair compared at wider-chain F. Does a reported F pass establish either default Stage-A parity or v2/v3 compiler-ELF identity?

### C20-07 — Change the compared representation

A hypothetical assembler accepts lines of text and ignores a trailing comment beginning `;`. Its complete transformation is deterministic. All its other inputs, options, and environment are held equal. File L contains `MOVE 7` plus newline; file R contains `MOVE 7 ;note` plus newline. Suppose the assembler produces equal ELF bytes from L and R.

Which passes: raw `cmp L R`, or comparison of the assembled ELF outputs? Explain why this does not contradict determinism. State the forward implication from equal text to equal executable output with its necessary conditions. Then apply that reasoning to Stage A without assuming this invented comment syntax is M1 syntax.

### C20-08 — Interpret the wider-suite counters

For four separate selected test sources, the harness receives these records:

| Case | v1 status | Reference status | Emitted-file comparison, when reached |
|---|---:|---:|---|
| A | 124, identified as timeout | 124, identified as timeout | Not reached |
| B | 7 | 8 | Not reached |
| C | 0 | 0 | Files differ |
| D | 0 | 0 | Files equal |

Start all counters at zero. Give the final `identical`, `both-fail`, `differ`, and total counts, and decide whether this suite portion passes. Which cases supply no successful-compilation evidence? Why is “both reject invalid syntax” too strong for A? Explain what additional detail you would need to turn the real job's 36-count summary into an exact list of exercised inputs.

## What we can now carry forward

C19 completed a source-to-executable derivation. C20 followed the next physical step: the produced executable runs as a compiler and emits a new representation. A reference-built compiler takes the same ordered self-source input, and Stage A compares the two M1 text files exactly.

You can now reconstruct that artifact path, distinguish a missing prerequisite from a comparison failure, locate the three different input lists, and bound the claim made by a recorded pass. The existing remote run supplies a real finite observation; the recipes explain the predicate behind it. Neither replaces the other.

Next, the assembler chapters open the transformation from M1 text toward executable bytes. Preserve the artifact names as you cross that boundary: a text-output fixed point, an ELF comparison across routes, and execution of a generated program each ask a different question.
