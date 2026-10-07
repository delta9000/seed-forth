# A program from two files

The compiler can translate a call before it knows where the called function
will live. What does it leave unfinished, and who finishes that work?

We will follow one number through two source files, two objects, a linker,
and the program's real startup. This is a paper prediction from the
[pinned edition](../../EDITION.md). The proposed fixture has not been compiled
or run. You need ordinary arithmetic and the distinction between a stored
program and a running process; no installation or complete compiler audit is
required. We will refresh the address and call rules when they matter.

## Give seven another home

Put the calculation in `answer.c`:

```c
int answer(void) { return 7; }
```

Put its caller in `main.c`:

```c
extern int answer(void);
int main(void) { return answer(); }
```

A **function** is named work that can receive inputs and return a result.
`int` says the result is a C integer. In the definition, `(void)` says there
are no parameters, and braces enclose the body. `return 7;` ends that call
with result seven; the semicolon ends the statement.

The first line of `main.c` has no body. It is a **declaration**: it tells the
compiler that `answer` is a function with no parameters and an `int` result.
`extern` makes the external declaration explicit. The body in `answer.c` is
its **definition**. A declaration supplies the information needed to check a
use; it does not supply the instructions implementing that use.

Inside `main`, `answer()` is a **call expression**. The empty parentheses
here supply zero arguments. Its value is whatever `answer` returns.
`return answer();` therefore calls `answer`, then returns its result from
`main`. Do not replace `(void)` in the declaration with `()`: at this pin,
an empty declaration list leaves the parameter specification unspecified.
The [signature parser](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/121-cc-sysv.fth#L512-L534)
makes that distinction.

Predict two things before going further: what should `main` return, and
which source asks to print it?

`main` should return seven. Neither source requests output. Moving the
calculation to another function changes who supplies the value, not its
destination.

## Stop compilation with one obligation open

The compiler processes these files separately. Each file, after
preprocessing, forms a **translation unit**. While compiling `main.c`, it
knows the declared interface of `answer`, but has not compiled `answer.c`.
It cannot know that function's final address.

It can nevertheless produce `main.o`, a **relocatable object file**. Here
“object” means a file, not a C object, a region storing a C value. This file
contains machine-code bytes and descriptions of work that remains:

- A code **section**, named `.text`, groups instruction bytes
- A **symbol** names something defined here or needed elsewhere. `main` is
  defined here; the referenced `answer` is undefined here
- A **relocation record** identifies a field to fill after placement, the
  symbol it depends on, the calculation to use, and an extra adjustment

Separately, `answer.o` supplies a definition of `answer` in its own `.text`.
An undefined symbol in `main.o` is an honest unfinished obligation, not
necessarily a failed compilation. A **linker** combines such objects and
resolves their obligations.

Neither object is the finished program `seven`. The selected output format
is ELF64 **ET_REL**, the relocatable form. It has no selected process entry
and executable loading layout. ELF is a family of file formats; recognizing
its name does not make an object runnable.

## Make caller and callee agree

Before joining the objects, choose one **profile**, a bundle of explicit
compilation contracts. This route selects three distinct things:

1. **LP64 data layout:** a C `int` occupies four bytes; C `long` and pointers
   occupy eight. A pointer represents an address
2. **AMD64 System V calling convention:** caller and callee agree how to
   transfer arguments and results, preserve required state, and align the
   machine stack
3. **Object output:** compilation writes relocatable objects; linking later
   chooses their placement and builds the executable

LP64 does not tell us which register carries a result. A calling convention
does not tell us whether compilation stops at an object. The driver selects
all three through
[`cc-sysv-object-enable`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L436-L457),
which also enables System V and LP64.

One byte contains eight bits: four bytes are 32 bits, and eight bytes are
64 bits. The compiler is implemented in Forth, whose cells here are eight
bytes. That does not enlarge a C `int`. Nor does holding a C value in a
64-bit machine register make its C storage width eight bytes. Keep the value,
its storage type, and its temporary carrier separate.

If you came from the
[earlier single-file result](../../c-compiler/chapters/19-translation-units-and-process-entry.md),
retain its builder/target distinction and deferred-patch idea. Do not carry
over its scalar sizes, runtime layout, or function-frame assumptions. We
have deliberately selected another profile.

## Follow the unfinished call

A register is named storage inside the CPU. A CALL instruction transfers
control to a function and saves the address at which execution should resume.
RET uses that saved return address. The call used here contains an opcode
byte `E8`, followed by a four-byte signed **displacement**, a distance in
bytes. The CPU adds that distance to the address immediately after the
four-byte field. It does not treat the field as the destination's absolute
address.

While compiling the call to `answer`, the
[selected call provider](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/131-cc-aggregate-abi.fth#L235-L320)
emits `E8` and four zero placeholder bytes. It remembers the field's position
on a list of unfinished calls associated with the declared function. The
[emitter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L414-L422)
returns the field position, one byte after the opcode.

At object finalization,
[`cc-om-function-calls`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/123-cc-object-program.fth#L421-L457)
turns the surviving obligation into a record with these meanings:

| Part | Meaning for our call |
|---|---|
| Target section and offset | Where the four-byte field lies within `main.o`'s `.text` |
| Symbol | The still-needed `answer` |
| Kind | `PLT32`, a signed four-byte relative relocation in this linker |
| Addend | `-4`, the explicit adjustment explained next |

This is a qualitative prediction, not an object dump. We have not assigned
the fixture's actual field offset or function sizes. The implementation
keeps a stable object identity for the symbol, then the writer assigns its
ELF symbol-table index. That index selects a record; it is not the function's
address. The record stores the addend explicitly. The four placeholder zero
bytes are not the addend.

## Let the consumer explain the arithmetic

The linker first chooses definitions and places their sections. It can then
resolve `answer` to a virtual address, meaning an address in the eventual
process. That differs from an offset counted from an object's section start
or its file start. A final executable file offset is another coordinate.
Never subtract positions from different coordinate systems without a stated
conversion.

Here is a small **illustrative placement**, not the output of our fixture.
All addresses are virtual byte addresses, written in hexadecimal; the prefix
`0x` marks base sixteen. Hexadecimal digits A through F represent ten through
fifteen. The pinned linker starts text at base `0x400000` plus 4096 bytes,
which is `0x401000`, so this model uses addresses above that boundary.

| Item | Illustrative address |
|---|---:|
| CALL opcode | `0x401080` |
| First byte of its four-byte field, called `P` | `0x401081` |
| Next instruction, after that field | `0x401085` |
| Resolved `answer` entry, called `S` | `0x401090` |

Ask what the CPU needs before applying a linker formula. It will start the
addition at `0x401085`. To reach `0x401090`, it needs eleven bytes forward:
the shared address prefix cancels, leaving `0x90 - 0x85`.
In decimal, `0x90 = 9 × 16 = 144`, while `0x85 = 8 × 16 + 5 = 133`.
Their difference is `144 - 133 = 11`, written `0x0B` in hexadecimal.

The relocation identifies the field at `P`, whereas the CPU uses `P + 4`.
Its extra adjustment, called **addend `A`**, bridges those two bases:

```text
CPU's needed distance: S - (P + 4)
Same calculation:      S + (-4) - P
Record's rule:         S + A - P, with A = -4
Model:                 0x401090 - 4 - 0x401081 = 11
```

The linker writes `0B 00 00 00`. Two hexadecimal digits describe one byte,
from `00` through `FF`. **Little-endian** storage puts the least significant
byte first. For these nonnegative values, group hexadecimal digits in pairs
from the right, store the rightmost pair first, and pad unused higher bytes
with `00`. The higher bytes of eleven are therefore zero. The linker overwrites
the reserved field rather than appending a second field. As a check, the CPU
would compute `0x401085 + 11 = 0x401090`.

The `-4` is neither a function-header size nor a mysterious penalty for
calling another file. It accounts for the consumer's next-instruction base.
The opcode address is not `P` either.

The
[linker's relocation code](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/140-cc-link.fth#L448-L494)
implements this rule and checks that the result fits a signed four-byte
field. It does not repair an out-of-range displacement by silently discarding
high bits. Here `PLT32` does not imply a dynamic procedure-linkage table:
this static linker applies the same relative arithmetic to PC32 and PLT32.

We have closed one obligation: a use compiled without its destination can
become a call to that destination after placement.

## Bring seven back across the call

Finding the correct address is only half the cooperation. `answer` must put
its result where `main` expects it.

Inside generated integer-expression code, this compiler uses **RDI** as a
value carrier. At a C integer return boundary, the result goes into **RAX**.
**EAX** names its low 32 bits, the width relevant to a C `int`. On the caller
side, the compiler moves the returned value back to RDI and converts it to
the declared result type. For signed `int`, that includes extending the
32-bit signed value to its wider internal carrier. Seven survives each
step unchanged. The
[return hook](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/131-cc-aggregate-abi.fth#L391-L413)
and [scalar carrier operations](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/127-cc-binary64.fth#L166-L173)
connect those stages.

The machine stack has its own rule. **RSP** is its pointer; before this CALL,
RSP must be divisible by 16. CALL stores an eight-byte return address by
moving RSP down eight bytes. Thus the callee's entry RSP is eight bytes away
from a multiple of 16. “Aligned before the call” and “aligned on entry” refer
to different moments.

Zero arguments do not remove this rule. The selected call provider saves
its stack bookkeeping, makes aligned outgoing space, calls, then restores
the saved state. The function provider also preserves its used callee-saved
registers and rounds the fixed frame to a multiple of 16. We supply that
mechanism's contract here; a frame-size reconstruction belongs to G04.

RDI's role in expression evaluation is not a universal claim about where
function results return.

## Find the first caller

Who calls `main`? The default driver supplies an eager startup object and a
runtime library. The actual link input order for our chosen user order is:

```text
start.o, main.o, answer.o, libseed.a
```

The two ordinary user objects are included. The startup object is also
included immediately. An **archive** such as `libseed.a` contains object
members; its members are selected when an unresolved name needs them. This
is **lazy selection**, in contrast to including every ordinary object.

The selected startup builder is
[`cc-sysrt-runtime-start-object`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L103-L133).
It defines `_start`, the process entry explicitly requested by the driver.
It gets the argument count and argument-vector address from Linux's initial
stack, aligns the stack, and preserves those inputs while calling
`__seed_init_runtime`. Only after that call returns does it call `main`.
Our `main(void)` does not consume the prepared arguments.

The initializer comes from
[`runtime/gcc-seed/startup.c`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/startup.c#L1-L25).
It establishes the program basename and the environment-vector pointer,
`environ`. Its object is named **`startup.o`**, distinct from **`start.o`**.
The unresolved initializer in `start.o` causes the archive to supply
`startup.o`. That member's need for `environ` brings in `environment.o`, whose
[source defines that name](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/environment.c#L1-L20);
other uses in the selected object can demand further members.

Selection is at whole-object granularity. A function need not run during
`seven` for references elsewhere in its selected object to need definitions.
The [archive scan](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/141-archive.fth#L384-L413)
repeats until that archive supplies no newly needed member. We can explain why the two-file program has runtime inputs
without pretending to have measured its final member selection.

Now follow the target's control flow, after a successful build and load:

1. Linux starts the process at `_start`
2. Startup calls the runtime initializer, then calls `main`
3. `main` calls `answer`; `answer` returns seven in RAX
4. `main` receives seven and returns seven in RAX to startup
5. Startup moves the value to RDI, places Linux exit syscall number 60 in
   EAX, and executes the syscall instruction

RDI now has a third role: the argument to Linux exit. This startup exits
directly; it does not call the C function `exit` or the runtime's syscall
wrapper. The predicted collected exit status is seven. Nothing in this
path requests a printed `7`.

The source's smaller raw startup builder calls `main` directly. It is a
separate interface, not the default `start.o` we have just followed.

## Change the consumer, then remove the provider

Suppose a supplied data record must hold an **eight-byte absolute pointer**
to `answer`. You do not need new C declaration syntax for this comparison.
Its contract says to store the address itself: an absolute `64` relocation
uses `S + A`, with `A = 0` for the function entry.

In our model, that stores `0x401090`, or bytes
`90 10 40 00 00 00 00 00`. Moving the pointer's storage location alone changes
neither its target nor its stored value. Moving the caller's relative field
alone does change the required call distance. The consumer's interpretation
selects the calculation. Field width alone cannot do that: this linker also
supports four-byte absolute relocations.

Now omit `answer.o`, while keeping the original call and the default runtime.
The declared call can still be compiled into `main.o`. At final link, however,
no input supplies `answer`. This required use, called a **strong reference**
by the linker, fails resolution. “Compilation succeeded” did not mean “an
executable is ready.”
The declaration promised an interface, not that some later input would keep
the promise.

## Command card for a later execution check

The paper story is complete without these commands. This card is
source-checked against the driver's parser, but **unexecuted**.

A future check needs Linux AMD64 execution support, a compatible Python 3,
a complete exact-pin checkout, writable scratch/temporary/cache locations,
and an existing `seed-forth` executable in that checkout. Put the two exact
sources above in a fresh writable directory. Set the shell variable
`SEED_ROOT` to the checkout's absolute path; quoted `"$SEED_ROOT/..."` expands
that path. Run the following from the directory containing the C files:

```sh
python3 "$SEED_ROOT/tools/gcc-direct-cc.py" -nostdinc -c answer.c -o answer.o
python3 "$SEED_ROOT/tools/gcc-direct-cc.py" -nostdinc -c main.c -o main.o
python3 "$SEED_ROOT/tools/gcc-direct-cc.py" main.o answer.o -o seven
```

`-c` stops after object production; `-o` names the output. Without `-c`, the
third command selects linking. `-nostdinc` removes the driver's default
runtime include directory for these user compilations. It does not suppress
preprocessing, target predefines, or runtime production at link time.

Do not add `-nostdlib`: that would remove automatic `start.o` and `libseed.a`,
leaving these two objects without `_start`. This is a bounded driver, not a
promise to accept every GCC option; for example, `-O2` is rejected.

The driver
[checks the existing seed against the annotated seed bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/gcc-direct-cc.py#L155-L205).
It does not build the seed. The
[seed construction entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/build.sh#L14-L29)
requires an identified starting hex0 translator. A supplied matching seed
with that producer record is a valid entrance; repeating the full byte audit
is not required to read this chapter.

For a future run, retain build statuses separately from the produced
program's status: successful compiler/link commands should report zero;
running `seven` should report seven and no printed digit. Also retain the
actual object records and selected archive members before replacing our
model addresses with measured ones.

## Who supplies what

Python handles arguments, snapshots, hashes, subprocess orchestration, and
publishing the completed output. The seed process runs the Forth
preprocessor, C compiler, object writer, archive builder, and linker. A later
execution of `seven` is another process. The phrase “Python driver” does not
make Python the C code generator.

The
[compiler stream](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/gcc-direct-cc.py#L155-L242)
loads the shared frontend and later providers through `131`; it omits the
executing `120-cc-main.fth` and separates linker `140`. A **provider** is an
implementation selected for a shared compiler operation. Later Forth loads
can change that selection, which is why the final binding matters. The
ordinary evaluated call to `answer` uses `cc-ag-call` from the final
`131-cc-aggregate-abi.fth` provider, despite that file's aggregate-oriented
name. Following only the earlier call implementation in `121` would miss
the selected path.

For later argument examples, the supplied ordinary-integer register order
is RDI, RSI, RDX, RCX, R8, and R9; further placement requires the argument
planner. Our zero-argument fixture demonstrates none of that transport.
G04 opens it before asking you to reconstruct an argument-bearing call.

The driver selects a fixed 21 MiB arena and explicit direct workspaces. These
are capacity choices, not ABI choices or unlimited automatic growth.
The linker accepts `081`'s fixed ten-section object contract; another
compiler's `.o` suffix alone does not establish compatibility.

Shared `115` declaration parsing is required on this route. Shared `118`
initializer traversal is also required compiler machinery, even though our
fixture has no C object initializer. The selected object path uses static
bytes/relocations and rejects a leftover executable-initializer queue.
Optional TinyCC study does not make this shared machinery optional.

On a runtime cache miss, the
[driver](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/gcc-direct-cc.py#L244-L320)
compiles its runtime C sources, excluding the separate math path, using its
runtime headers. A **header** is source text that supplies shared
interface information, such as declarations and type definitions.
**Preprocessing**, among its other jobs, makes requested header text part
of the source stream seen by the C parser. These headers are compilation
inputs, not already-compiled library members. The
[preprocessing lessons](../../c-compiler/chapters/03-preprocessing-regions-and-includes.md)
open the complete mechanism.

The driver also has Forth emit seven support objects:
`syscall.o`, `errno.o`, `start.o`, `frame.o`, `sigreturn.o`, `setjmp.o`, and
`longjmp.o`. The archive contains the non-start runtime objects, including
C-built `startup.o`. Lazy inclusion in the final executable does not mean
that archive members had no producers.

A verified cache can supply runtime objects instead. The driver checks
source identities, the expected artifact set, and artifact hashes, then
copies and rechecks the bytes. A cache hit preserves the artifacts'
ancestry; it is not a fresh runtime build.

No GCC, TinyCC, pnut, M2, or external assembler/linker executable produces
this result. `130-asm.fth` is not on this production path either. GCC is a
later destination. Linux, the CPU, Python, filesystem services, acquired
sources, and the existing seed remain real supplied dependencies. Comparison
programs used by a later test have a different role from these producers.

The selected target is C90-oriented with bounded extensions. Its
[predefines](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/124-cc-target.fth#L1-L21)
identify Linux, x86-64, LP64, and `__STDC_HOSTED__=0`; they do not advertise
GNU C identity or general C99/C11 conformance. Successful linking also does
not compare the C signatures in different translation units. Matching
names alone cannot repair incompatible declarations.

## Try the mechanism

Keep [hints and solutions](../practice/01-solutions.md) closed for an
independent attempt. If you get stuck, use one hint, record the help, and
resume from the first step you can explain. Each feedback set includes a
changed prompt with its check kept separate.

### G1-01 — Separate knowing from supplying

In the two original sources, identify each function definition, the external
declaration, and the cross-file use. Explain why `main.c` can compile without
`answer.c`. Predict the value returned by `main` and whether either file
requests output.

### G1-02 — Keep the right address

Use the illustrative placement. Give the CPU's addition base, the required
displacement, and its four stored bytes. Explain why adding that displacement
to `P` gives the wrong destination. Name the actor that patches the field
and the later actor that consumes it.

### G1-03 — Complete the record

A second illustrative call has its field at `P=0x401121` and calls a symbol
placed at `S=0x401150`. Complete its relocation description: kind, width,
addend, numeric field, and little-endian bytes. Check the destination using
the CPU's rule. Do not invent a symbol-table index or object-file offset.

### G1-04 — Move one thing

Compare the original relative call and the supplied absolute pointer to
`answer`. Move only the caller's field forward `0x20` bytes. Which stored
value changes, and why? Then start again from the original placement and
move only `answer` forward `0x30`. Derive both new values; negative-byte
encoding is not required.

### G1-05 — Locate the broken promise

Keep the original sources, successfully produce both objects, but omit
`answer.o` from the link inputs. Identify the first stage that cannot finish
this program and the missing obligation. Would repeating the declaration
in `main.c` supply the missing body?

### G1-06 — Reconstruct the producers

Without copying the source inventory, trace the producers of `main.o`,
`start.o`, `startup.o`, `libseed.a`, and `seven`. Include the existing seed,
Python, the Forth implementations, and runtime headers. Explain what changes
if the runtime cache is reused. Finally trace control from `_start` until
seven is passed to Linux exit.

### G1-07 — Keep contracts separate

Classify these statements as data layout, calling convention, output format,
or compiler-internal representation: “C int uses four bytes”; “the integer
result returns in RAX”; “compilation produces ET_REL”; “Forth cells use eight
bytes.” Explain why none alone establishes all the others. With caller RSP
`0x8000` immediately before CALL, derive RSP on callee entry and identify
which of those moments satisfies the supplied 16-byte call alignment rule.
Here `0x8000` is decimal 32768; you may subtract and test divisibility in
decimal rather than practice hexadecimal borrowing.

## What this entrance opens next

You can now explain an unfinished use, its later patch, and the agreements
that let the result cross independently compiled functions. The following
chapters open those implementation mechanisms; this one trace does not complete them.
Files recur because ownership is by mechanism, not by whole filename.

| Home | Mechanism opened by the continuation |
|---|---|
| [G02](02-objects-symbols-and-relocation-records.md) | `081` writer and `123` stable-record/export bridge: section records, symbol identities, object storage, validation and publication |
| [G03](03-signatures-declarators-and-ranked-arrays.md) | Shared `115`/`118` declarations, signatures, descriptors and initializer structure; `123` signature/implicit-declaration bridge |
| [G04](04-a-shared-scalar-argument-planner.md) and [G15](15-aggregate-values-and-x87-transport.md) | `121`, final `131` providers and `123` function wrapper: argument planning, live values, frames, full alignment cases, aggregate/X87 transport |
| [G05](05-linking-independently-built-objects.md) | `140`: complete resolution and validation, section placement, relocation kinds/ranges, executable headers and publication |
| [G06](06-raw-syscalls-startup-and-runtime-control.md) | `122`: both startup contracts, C/Linux register bridge, errno, frame, signal and nonlocal-return helpers |
| [G07](07-source-built-allocation-and-byte-operations.md) and [G13](13-streams-and-bounded-formatting.md) | Runtime allocation, byte/string services, streams, and their failure contracts |
| [G08](08-target-headers-and-honest-feature-probes.md) and [G09](09-typed-constants-and-symbolic-addresses.md) | Target headers/predefines; `123` static initializer/relocation lowering through shared `118` traversal and the final scalar-leaf provider |
| [G10](10-floating-values-and-conversion.md)–[G12](12-variadic-cursors-and-argument-classes.md) and [G14](14-bitfield-layout-and-preserving-stores.md) | Loaded `127`/`128` floating and literal mechanisms, `126` variadics, and `129` bitfields, none demonstrated by this integer-only fixture |
| [G16](16-indexed-archives-and-lazy-extraction.md) and [G17](17-frozen-driver-configure-and-source-census.md) | `141` archive selection/order, complete runtime/source inventories, cache identity and driver boundaries |

G02–G25 are now paper chapters with separate practice companions; their new
execution and independent review remain pending. The
[main-route map](../../HYBRID-NARRATIVE.md) connects this result to source
generators, GCC output tools, hosted programs, and rebuild evidence.

Our evidence here is inspected exact-pin source plus stated derivations.
Assumptions include matching profile/source inputs, valid supplied objects,
sufficient bounded resources, successful file operations, and the stated
Linux AMD64 loading/execution contract. Actual fixture bytes, cold/cache
runs, failure transcripts, a verified fresh-start setup, and independent
reader attempts remain unverified. Preserve the distinction: explaining why
seven should arrive is an achievement; observing it arrive is another.
