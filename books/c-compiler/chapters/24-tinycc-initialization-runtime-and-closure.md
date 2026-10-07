# 24. TinyCC initialization, runtime and closure

[C23](23-the-direct-tinycc-profile.md) ended with a dispatcher that was a single `ret`. Give it something to do:

```c
int n = 5;
int *p = &n;
int main(void) { return *p + 2; }
```

Compile it with C23's TinyCC profile. The program exits with 7. Before reading on, predict three things. Which byte of the 989-byte file holds the value 5? What is stored in the four file bytes that belong to `n`? Which instructions run between process entry and `main`'s first instruction?

The 5 is not in `n`'s bytes at all. It sits inside an instruction, `n`'s file bytes are zero, and two small routines run before `main`. This chapter follows that choice: why a compiler without a relocation evaluator turns every initialized object into code, what a C initializer may contain under that rule, and how a local initializer differs. It then returns to the kernel bodies C23 counted and explains why they return −1. The last half follows the profile out of the compiler: the [recipe](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc.recipe) that starts from raw archives, writes `tcc-seed`, and reaches a TinyCC executable and object fixed point.

You need C23's image map (stub 120–150, kernel bodies 151–584, refusal bodies 585–833), the field-end rule for rel32, C10's imm64 address fixups, and C07's aggregate layout. C22's notion of a fixed point is useful but is restated where it is used.

**Profile and evidence.** The profile is C23's: `cc-target-lp64`, `cc-prep-direct`, `cc-bootstrap-floatbits=1`, the 8 MiB arena, and files `010` through `119`. The implementation is [`118-cc-native-init.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth) and [`119-cc-native-runtime.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/119-cc-native-runtime.fth), with the guard in [`100-cc-expr.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L49-L55), all at revision `7d7e1996d1753118181d43e1a413960d3a1ec24b`. Image offsets and bytes are source-derived; during drafting, the chapter's small programs were also compiled once with that file list and the bytes agreed. That spot check is not a retained artifact. The route half reads the recipe, its manifests and the repository's own reports. Its hashes are the recipe's pins: this book did not execute the recipe, and every statement that a step passed is attributed to [HOST-TOOLS.md](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/HOST-TOOLS.md#L60-L66) or [Chapter 34](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/34-direct-tinycc.md#L1422-L1466).

## An initialized object is a queued routine

Everything before offset 834 is C23's image, unchanged. From 834 on:

| Offsets | Bytes | Meaning |
|---|---|---|
| 834–838 | `E9 16 00 00 00` | `jmp 861`: skip `n`'s routine |
| 839–848 | `48 BF CD 03 40 00 00 00 00 00` | `movabs rdi, 0x4003CD`: the address of `n` |
| 849 | `57` | `push rdi` |
| 850–856 | `48 C7 C7 05 00 00 00` | `mov rdi, 5`: the value (the `05` is byte 853) |
| 857 | `59` | `pop rcx` |
| 858–859 | `89 39` | `mov [rcx], edi`: a four-byte store |
| 860 | `C3` | `ret` |
| 861–865 | `E9 1A 00 00 00` | `jmp 892`: skip `p`'s routine |
| 866–891 | 26 bytes | `p`'s routine: push `p`'s address `0x4003D5`, load `n`'s address, `mov [rcx], rdi`, `ret` |
| 892–961 | 70 bytes | `main` |
| 962–966 | `E8 80 FF FF FF` | `call 839` |
| 967–971 | `E8 96 FF FF FF` | `call 866` |
| 972 | `C3` | end of the dispatcher |
| 973–988 | sixteen zero bytes | data: `n` at 973, padding, `p` at 981 |

The jump displacements follow C10's rule: the first field ends at 839 and `861−839=22=0x16`; the second ends at 866 and `892−866=26=0x1A`. The dispatcher's calls go backward: `839−967=−128` is `80 FF FF FF`, and `866−972=−106` is `96 FF FF FF`.

The data addresses come from C19's coordinates. With the load base `0x400000`, offset 973 is virtual address `0x4003CD`. `p` needs eight-byte alignment within the data area, so it lands eight bytes after `n`, at 981 or `0x4003D5`. Those sixteen bytes stay zero in the file. When `main` starts, the two routines have already stored 5 into `n` and `n`'s address into `p`.

The entry stub is C23's 31 bytes with two new fields. The dispatcher CALL's field still ends at 125, so it holds `962−125=837=0x345`, written `45 03 00 00`. The `main` CALL's field ends at 141 and holds `892−141=751=0x2EF`, written `EF 02 00 00`.

### Why code instead of data

Writing 5 into `n`'s data bytes would be easy. Writing `&n` into `p`'s would not. An address is not known until the object's final position is known, and an initializer can name an object or function that is declared later, or one whose storage is moved by a later, larger declaration. A compiler that writes initialized data needs a second engine: an evaluator for constant expressions that produces relocations, not values.

This compiler already has a relocation engine. Every `movabs rdi, address` that an *expression* emits for a global is recorded as an address fixup, and every CALL to an undefined function is recorded on that function's list (C10, C23). [`118`'s header](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L1-L7) states the choice: lower the initializer as ordinary expression code, so the existing fixups patch it, and run that code once before `main`. The cost is a few bytes and a few instructions at startup. The gain is that `&n`, `n + 2` with `n` an array, a function address, and a string address are all handled by code that already works.

[`cc-native-initializer`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L290-L307) runs when a declarator is followed by `=`. For a file-scope or `static` object it:

1. Emits a `jmp` placeholder, so straight-line code never falls into the routine
2. Queues the routine's address on a linked list of 16-byte records, in source order
3. Sets `cc-native-static-init`, the guard described next
4. Parses the initializer, emitting address, value and store code for each scalar leaf
5. Clears the guard, emits `ret`, and patches the `jmp` to the next byte

The routine sits where the declaration sits. For `n` and `p` that is between the runtime bodies and `main`; for a `static` local it is inside the function's own code, jumped over on every execution of that function.

[`cc-ni-entry`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L310-L312) is the first thing [`cc-native-entry`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/117-cc-native-program.fth#L76-L86) emits: it empties the queue and leaves a CALL placeholder at 120. After the last declaration, [`cc-ni-finish`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L315-L323) patches that placeholder to the current address and emits one `E8` CALL per queued routine, then `C3`. With nothing queued, the dispatcher is C23's single byte.

A routine runs once, before `main`. A `static int c = 10;` inside a loop body is therefore stored once, not once per iteration: a loop that increments it three times leaves 13.

### The guard: a category, not a value

Running arbitrary code before `main` would quietly extend C. A file-scope `int g = f();` is not C90, and its order of evaluation would be whatever the queue says. The [guard](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L49-L55) keeps the routine to what a constant initializer could express. While `cc-native-static-init` is set and the parser is not inside an unevaluated operand, seven actions fail with **219**:

| Guarded action | Example rejected in a static initializer |
|---|---|
| A load through a pending dereference (materializing a memory value) | `int g = n;`, `int g = *p;` |
| A direct call | `int g = f();` |
| An indirect call | `int g = fp();` |
| A reference to a local | a `static` local initialized from an automatic one |
| `++` or `--` | `int g = n++;` |
| Assignment | `int g = (n = 3);` |
| The comma operator | `int g = (3, 4);` |

Addresses, integer constants and their arithmetic remain: `&n`, `&n + 1`, `(long)&n`, an array name that decays, a function name, a string literal. `sizeof` sets `cc-expr-unevaluated`, so `int a = sizeof(f());` is accepted and stores 4. A struct object used as a whole value in a static initializer fails with 219 from [`cc-ni-scalar`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L157-L175): copying it would read memory.

The guard checks *categories*, never values. `int z = 7 / 0;` compiles: division is ordinary arithmetic and no folding step looks at the divisor. The routine's `idiv` then faults before `main`, and the process dies with `SIGFPE`. That is acceptable for a bootstrap compiler whose inputs are pinned, but it is a real difference from a C compiler that evaluates initializers at compile time.

**Stop/resume point.** Keep four offsets for the opening program: 839 (`n`'s routine), 866 (`p`'s routine), 892 (`main`), 962 (dispatcher). On returning, rebuild them from the rule: a five-byte `jmp`, a routine of address, `push`, value, `pop`, store, `ret`, then `main`, then one CALL per queued routine. If the routines are right but the fields are not, redraw only each field's end. Then try C24-01.

## Local initializers zero first, then store

An automatic object cannot be initialized before `main`. Its storage does not exist until its function's frame does. For a local, `cc-native-initializer` emits the code in place, with no jump, no queue and no guard. One extra step comes first: if the object is an array or a struct, [`cc-ni-zero-object`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L43-L47) clears every byte.

```c
int main(void) { int v[4] = {1, 2}; char s[] = "hi"; return v[1] + sizeof s; }
```

`v` takes two slots at RBP−16 (C23's layout rule), and `s`, three bytes inferred from the string, takes one at RBP−24. The frame is `round16(3×8)=32`.

| Step | Instructions | Why |
|---|---|---|
| Zero `v` | `lea rdi,[rbp-16]`; `mov ecx,16`; `xor rax,rax`; `rep stosb` | C requires omitted elements to be zero; a local's slot holds old stack bytes |
| `v[0]=1` | `lea rdi,[rbp-16]`; `push rdi`; `mov rdi,1`; `pop rcx`; `mov [rcx],edi` | Offset 0 needs no `add` |
| `v[1]=2` | the same, with `add rdi,4` after the `lea` | Element offset is index × element size |
| Zero `s` | `lea rdi,[rbp-24]`; `mov ecx,3`; `xor rax,rax`; `rep stosb` | Every local array is zeroed, even one about to be filled |
| Copy `"hi"` | `jmp` over `68 69 00`; `movabs rdi,` that address; `mov rsi,rdi`; `lea rdi,[rbp-24]`; `mov ecx,3`; `rep movsb` | The string's bytes live in the code, skipped by the jump |

The program exits with 5. A static object needs no zeroing step: its data or BSS bytes start as zero and are never reused. A scalar local such as `int k = 5;` gets only the store. For a `char` array, the copy count is the smaller of the decoded string length plus its NUL and the array's length, so `char s[2] = "hi";` copies two bytes and no NUL. That exactly-full case is allowed. One byte fewer, `char s[1] = "hi";`, fails with **223**.

## Reference: the initializer traversal and its codes

[`cc-ni-value`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L247-L281) visits one destination. It saves eight cells in a fresh 64-byte frame: type, descriptor, outer array count, inner count, byte offset, element index, whether this level opened a brace, and whether it is nested. It keeps the previous frame on the return stack and restores it on exit, so one level's state survives the recursive visit of its children.

- **An array** walks its elements with [`cc-ni-list`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L206-L228). Each child's offset is the base plus index × element size, where a two-dimensional array's element is its whole row. A `char` array goes to [`cc-ni-char-array`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L231-L245) first, which accepts a string with or without one pair of braces
- **A struct** walks its field records in declaration order, adding each field's C07 offset. **A union** has exactly one child, its first member
- **A scalar** emits its address, then the value expression, conversions and a typed store. One pair of braces around a scalar is accepted, so `int x = {4};` stores 4
- **A list** stops after as many children as the destination has. At the outermost level it requires its own `{`; at a nested level it may take its children from the enclosing list (brace elision), so `int m[2][3] = {1,2,3,4,5,6};` fills both rows

Small helpers carry the rest. Eight accessors (`ni-type` through `ni-nested`) name the frame's cells. [`cc-ni-address`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L32-L36) emits the destination address, a global reference for a static object or a `lea` for a local, plus an `add` only for a nonzero offset. `cc-ni-count-rcx`, `cc-ni-mov-rsi-rdi` and `cc-ni-copy-bytes` emit the `mov ecx`, `mov rsi,rdi` and `rep movsb` seen above. [`cc-ni-aggregate?`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L29-L31) asks whether a destination is a struct or union that is not an opaque scalar, and [`cc-ni-child-count`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L182-L184) and [`cc-ni-child`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L190-L204) supply the limit and the next destination.

Five deferred words leave room for later targets, and this profile keeps every default. `cc-opaque-scalar-default` answers false: no type here is an opaque scalar, while the System V file later answers true for `long double`. `cc-value-static-init-default` does nothing; the binary64 file later checks floating values there. `cc-ni-field-default` answers "not handled", so every field is an ordinary leaf; the bitfield file later claims its fields. The scalar and string paths are also deferred, and the object-file program replaces both. None of those files is loaded for TinyCC.

Before an array without a size is allocated, [`cc-ni-infer`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L68-L130) scans ahead with a saved lexer mark, counts the outer elements, and resets the lexer. A string's length is counted as decoded bytes by [`cc-ni-string-size`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/118-cc-native-init.fth#L50-L58), so `"a\n"` contributes two bytes and the NUL makes three. In an inferred array, each nested aggregate element must carry its own braces.

| Code | Raised by | Example |
|---:|---|---|
| 219 | The static guard, or a whole struct value in a static initializer | `int g = n;` at file scope |
| 220 | Inference found nothing usable | `int a[] = {};`, `int a[] = 5;`, a string for a non-`char` array |
| 221 | Inference reached end of input, an empty element, or a closing bracket with no opener | `int a[] = {1,,2};` |
| 222 | Inference found an unbraced nested aggregate | `int m[][2] = {1,2,3,4};` |
| 223 | A string longer than its array, or a braced string not closed | `char s[1] = "hi";` |
| 224 | A struct value of a different struct type | `struct q b = a;` with `a` a `struct r` |
| 225 | A missing comma inside braces, or an array with no brace at the outer level | `int a[2] = {1 2};` |
| 226 | More elements than the destination holds | `int a[2] = {1,2,3};` |
| 227 | A braced scalar with more than one value | `int x = {4 5};` |

Designators are outside the profile. `{[1] = 3}` is not recognized as an initializer form at all, so the `[` reaches [C14's operand parser](14-expressions-and-constant-evaluation.md), whose unrecognized-start case fails with **97**.

Initialization also interacts with C23's [tentative enlargement](23-the-direct-tinycc-profile.md#reference-the-declaration-machinery-this-profile-depends-on). In

```c
int a[1];
int *q = a;
int a[3] = {1, 2, 3};
```

`q`'s routine is emitted when `a` still has one element, so its `movabs` names `a`'s first slot. The third line is larger, so [`cc-nobject`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth#L551-L594) allocates new BSS storage and redirects every recorded address fixup for the old slot, including the one inside `q`'s routine. The new initializer's routine then stores into the new storage. At runtime `q[2]` is 3. The initialized array ends up in BSS rather than data, which costs nothing here: the routine writes it either way. Reversing the first two lines gives **93**, because a use before any declaration is an unknown name.

## Choose a second session

Both opening questions are answered. Choose one for the next session:

- **What may an initializer contain?** Reread the guard table and the traversal reference, then try C24-02 through C24-04
- **Why do the kernel bodies return −1?** Read the next section, then try C24-06 and C24-07
- **How does the compiler leave the book?** Read the route sections, then try C24-08 and C24-09

The first route finishes `118`. The second finishes `119`. The third uses no new compiler source; it reads one recipe.

## The kernel boundary normalizes failure

C23 counted the thirteen kernel bodies by their length, `23+5k`. Their last sixteen bytes decide what a failed system call looks like to C. Linux returns a failure as `−errno` in RAX: a missing file is −2. [`cc-native-syscall`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/119-cc-native-runtime.fth#L28-L44) compares RAX with −4095 as an *unsigned* number and, for exactly the values −4095 through −1, replaces it with −1. Anything else, including a file offset above 4 GiB from `lseek`, is returned unchanged.

The reason is the library that calls these bodies. Portable libc tests `fd == -1`, as POSIX callers do, and [the runtime note](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/tcc/native-runtime.md#L24-L28) records the consequence of not normalizing. The earlier pnut boundary returned raw `−errno`, so `fopen` of a missing file saw −2, passed the test, and allocated a `FILE` holding a negative descriptor. With normalization the same call returns `NULL`, and every caller that tests for −1 sees the failure it was written to handle.

The boundary does not set `errno`. The note states that as part of the contract rather than emulating it, so a caller that needs the reason for a failure gets only the fact of it.

Return types are registered before any header is read, in [`cc-native-primitive`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/119-cc-native-runtime.fth#L46-L51). `read`, `write`, `lseek` and `time` return `long`; the other integer bodies return `int`; `exit` returns `void`. The difference matters for `lseek`: an `int` result would make C's caller sign-extend the low 32 bits of a five-gigabyte offset.

### Three names that fail closed

With floatbits on, [`cc-native-unavailable`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/119-cc-native-runtime.fth#L53-L88) emits three bodies that write `seed-forth bootstrap: unsupported NAME` and a newline to standard error, exit with status 125, and end in `ud2`. The prefix is 34 bytes, so `ldexp`'s message is `34+5+1=40` bytes, C23's 670–709. The [runtime note](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/tcc/native-runtime.md#L30-L67) names when `tcc-seed` would reach each:

| Name | Reached when the compiled source… |
|---|---|
| `ldexp` | contains a hexadecimal floating literal |
| `localtime` | expands `__DATE__` or `__TIME__` |
| `longjmp` | contains a compilation error: TinyCC's error path jumps back to `tcc_compile` |

The list is exact. It came from auditing every direct call in the libc-plus-TinyCC unit: after the C bodies and the thirteen kernel bodies, these three names had no implementation. They are not proven unreachable. A malformed input to `tcc-seed` can reach `longjmp`. The design makes that visible instead of silent: any build step that reaches one exits 125, and the recipe, which requires status 0 from every step, stops.

Two alternatives were rejected, and both are instructive. pnut's recipe let unresolved functions print a diagnostic and *return*; this boundary cannot continue past a missing operation. Portable libc's own `ADD_LIBC_STUB` switch would supply these names, but it brings 24 functions, including an aborting `mprotect` that conflicts with the working kernel body and a `localtime` that aborts on exactly the non-null argument TinyCC passes. The Forth compile of `tcc-seed` therefore leaves the switch off. (The recipe later passes `-D ADD_LIBC_STUB` when *TinyCC* builds its own runtime libraries; that is a different compiler and a different library.)

Without floatbits, none of the three bodies exists. A call to `localtime` or `longjmp` is an undefined function (**206**), and `ldexp`'s prototype fails earlier because `double` is a floating type (**214**).

## The compiler leaves the book

Every image so far has been about a kilobyte. The compiler's real job is one far larger image: `tcc-seed`, 870,752 bytes, SHA-256 `7411c326…ee2fc3a`. Its input is a [25-line file](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc-direct-input.c) of 23 `#define`s followed by two lines:

```c
#include "libc64/libc.c"
#include "tcc-0.9.27/tcc.c"
```

That is C23's private convention made concrete. Every caller and every callee must come from one compiler run, so portable libc and TinyCC become a single translation unit, and with `ONE_SOURCE=1` the file `tcc.c` pulls in TinyCC's other source files. The `PNUT_*` defines select the portable-libc and kit code paths written for that compatibility profile; they do not run pnut. `HAVE_LONG_LONG` is defined and `HAVE_FLOAT` is not. The kit's exact patches guard TinyCC's floating constant folding and number conversion with `HAVE_FLOAT` (for example [kit patch 7](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/patches/amd64/exact/kit-07.after#L1-L5)), so the TinyCC inside `tcc-seed` is built without those paths. `tcc-boot0` is compiled with `-D HAVE_FLOAT=1` and has them.

[`tools/tcc-start.fth`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc-start.fth#L65-L84) concatenates the eighteen Forth files, the [compile driver](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc-compile.fth) and this input, then feeds them to `./seed-forth`. The Forth preprocessor (C05) follows every `#include` in the real headers. No preprocessed file exists at any point.

## Reference: the recipe from raw archives to `tcc-seed`

[`tools/tcc.recipe`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc.recipe) is read by a runner that the seed compiles from [`tools/amd64-runner.c`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/amd64-runner.c). Its language has no shell, no `PATH` search and no globbing. Each line is one operation:

| Operation | Lines | Meaning |
|---|---:|---|
| `run STATUS IN OUT ERR PROG ARGS…` | 49 | Execute with explicit redirections; the exit status must equal `STATUS` |
| `artifact PATH SHA` | 13 | A produced file's SHA-256 must equal the pin |
| `pin PATH SHA` | 1 | A source file's SHA-256 must equal the pin |
| `stage MANIFEST FROM TO` | 5 | Check each listed file's hash, then copy only those files |
| `patches MANIFEST DIR` | 5 | Apply exact replacements, checking each file's hash before and after |
| `same A B` | 7 | The two files must be byte-identical |
| `contains FILE TEXT` | 1 | `TEXT` must occur exactly once |
| `cat`, `copy`, `text`, `mkdir`, `chmod`, `unlink`, `cd`, `set`, `say` | 59 | File and directory plumbing |

The runner's own `unlink` accepts a result of 0 or −2. It was built with a [separate syscall extension](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/HOST-TOOLS.md#L170-L175) that returns raw kernel results, not the normalized ones above, so a missing file is visible to it as −2.

The first 58 lines build `tcc-seed` from nothing but pinned inputs:

1. **Stage raw inputs** (lines 15–16). Thirty-eight files: the kit's `config.h` and `libtcc1.c`, the original `tcc-0.9.27.tar.gz`, and portable libc's sources and headers. Then the twelve archive-tool sources
2. **Build `simple-patch` with Forth** (lines 17–25). The runner pins `tools/simple-patch.c`, concatenates the eighteen compiler files with a driver and a [nine-line C unit](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tools/tcc-bootstrap-patch.c) that includes the raw `libc.c` and `simple-patch.c`, runs the seed, and pins the result
3. **Build `bintools` with Forth** (lines 26–34). The same pattern, after one exact LP64 patch to the archive tool's decompressor
4. **Unpack and patch TinyCC** (lines 35–53). The Forth-built `bintools` decompresses and extracts the archive; the Forth-built `simple-patch` applies the kit, TinyCC and libc manifests
5. **Pin every prepared file** (line 55). The 440 hashes cover the 439 source files and their manifest
6. **Compile `tcc-seed`** (lines 57–58), as described above, and pin it

Nothing in that sequence was compiled by anything other than the seed running the Forth compiler. The C sources that become helpers are the same `libc.c` that later becomes part of `tcc-seed`.

## Reference: four generations and two fixed points

From line 59 the compiler is TinyCC. Each generation first compiles its own runtime library directory (C start-up `crt1.o`, `libc.a`, and `tcc/libtcc1.a`), then compiles `tcc.c` twice: once linked into an executable, once as an object with `-c`.

| Output | Compiled by | Library directory named inside it | Check |
|---|---|---|---|
| `tcc-boot0` | `tcc-seed` | `build/boot0-lib` | pinned `0605…15de` |
| `tcc-boot1` | `tcc-boot0` | `build/boot1-lib` | pinned `c382…a886` |
| `tcc-boot2` | `tcc-boot1` | `build/boot2-lib` | pinned `514b…a5c1` |
| `tcc-boot3` | `tcc-boot2` | `build/boot2-lib` | `same` as `tcc-boot2` |
| `tcc-boot3.o` | `tcc-boot2` | (object) | `same` as `tcc-boot2.o`, pinned `b373…8b61` |

The library directory is not only a place to look. `-D "CONFIG_TCCDIR=\"build/boot2-lib/tcc\""` and its neighbours become string constants inside the compiled TinyCC. Two generations that name different directories cannot be byte-identical, so the recipe pins `boot0`, `boot1` and `boot2` separately and compares nothing among them. The comparison is set up for the last step only. `tcc-boot3` reuses `build/boot2-lib`, after `tcc-boot2` has rebuilt the libraries there, so its source, options and strings all equal `tcc-boot2`'s.

That makes `same build/tcc-boot2 build/tcc-boot3` a **fixed point**: a compiler that, given its own source, reproduces itself. The object comparison isolates the compiler's code generation, because an object contains only what `tcc.c` produced. The executable comparison adds everything linked from the libraries. The three library files are pinned after the equality check (lines 117–119); they are the versions `tcc-boot2` built.

The equality is evidence about TinyCC, not about the Forth compiler directly. `tcc-boot0` was produced by TinyCC's code generator running inside `tcc-seed`, and its code follows TinyCC's System V convention, not the private one (C23's three conventions). If `tcc-seed` had miscompiled TinyCC, the error could show up as a wrong `tcc-boot0`, and through it a wrong `tcc-boot1`. Reaching an unchanged fixed point after two further generations, with every pin matching the independent control, is what makes such an error implausible. It is not a proof that `tcc-seed` is correct on every input.

## Reference: what the recipe tests after the fixed point

| Lines | Test | What passing means |
|---|---|---|
| 122–124 | `t64` compiled by `tcc-boot2` | stdout equals the recorded `t64.out` |
| 125–127 | `hello a b` | exits 7 and prints the recorded output |
| 128–130 | `printf` | stdout equals `printf.out` |
| 131–133 | portable libc's `test-libc` | stdout contains `All tests passed!` exactly once |
| 135–136 | [`rebuilt-features.c`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/tcc/rebuilt-features.c) | exits 0; stdout is not compared |
| 137–138 | `simple-patch` rebuilt by `tcc-boot2` | pinned `efc7…0375` |
| 140–144 | `bintools` rebuilt by `tcc-boot2` | pinned `26f7…67c0` |

`rebuilt-features` is a status-only test. The program returns 1, 2 or 3 if real floating arithmetic, bitfields, or a variable-length array with a local enum fail, and 0 otherwise. Those are exactly the features the Forth profile does not have. Passing shows that the restricted transport in `tcc-seed` did not leak into the final compiler.

The two rebuilt helpers have different pins from the Forth-built ones (`9578…1fc7` for `simple-patch`, `d330…f5b4` for `bintools`). They should: one source compiled by two different compilers gives two different instruction streams. Each pin checks that its own producer is reproducible. Neither claims that the Forth compiler and TinyCC generate the same code.

## Reference: what this evidence establishes

Keep the claims separate, as the repository does:

| Claim | Evidence | Limit |
|---|---|---|
| The Forth compiler accepts the pinned libc and TinyCC | `tcc-seed` is produced and pinned | Not a statement about arbitrary C |
| `tcc-seed` works as a compiler | It builds `tcc-boot0`, whose pin matches | Paths reached by the sources only |
| TinyCC reaches a fixed point | `same` on executable and object | Compares generations 2 and 3 only |
| The raw-input recipe passes end to end | [HOST-TOOLS.md](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/HOST-TOOLS.md#L60-L66) reports it | This book did not execute it |
| No other executable takes part | A prepared-source isolation run in an empty root | Starts after extraction; its syscall-audited gate reports SKIP, not PASS |
| The route works in a guest | A raw-input K0 → K1 run under QEMU | The longer GNU/Linux continuation is not established |

A green recipe run establishes the first three rows on the machine that ran it. The last three rows are results the repository reports, each with its own limits, in [HOST-TOOLS.md](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/HOST-TOOLS.md#L82-L107).

## Practice: follow the value to its store

Use the image tables and references above. Write each answer as a rule followed by its calculation. Feedback is on [C24's solution page](../practice/24-solutions.md).

### C24-01 — Rebuild the image map

Without looking at the opening table, rebuild offsets 834–988 for the opening program from these facts: a five-byte `jmp`, a 22-byte routine for `n`, a 26-byte routine for `p`, a 70-byte `main`, one CALL per queued routine, and sixteen bytes of data with `p` eight-byte aligned. Then compute the four rel32 fields in `jmp` and CALL instructions after 834, and the two stub fields.

### C24-02 — Add a third global

Insert `char c = 65;` after `p` in the opening program. The new routine stores through `mov [rcx], dil` (`40 88 39`). Give the new routine's offsets, `main`'s new start, the dispatcher's three CALL fields, the address of each object, and the file length. Which bytes inside `n`'s routine change, and why?

### C24-03 — Accepted or 219?

Classify each file-scope initializer, given `int n; int arr[4]; int f(void) { return 3; }` earlier in the file: `int *a = &n + 1;`, `int b = n;`, `long c = (long)&n;`, `int d = sizeof(f());`, `int *e = arr + 2;`, `int g = (3, 4);`, `int (*h)(void) = f;`, `int k = 7 / 0;`. For any that compile, say what the routine does at runtime. Then state the one rule that covers every case.

### C24-04 — Name the code

Give the outcome of each: `int a[] = {1, 2, 3};` (give `sizeof a`), `int m[][2] = {{1,2},{3,4},{5,6}};` (give `sizeof m`), `int m[][2] = {1,2,3,4};`, `int m[2][3] = {{1},{4,5}};` (give `m[0][1]` and `m[1][1]`), `char s[2] = "hi";`, `char t[] = "a\n";` (give `sizeof t`), `int a[2] = {1,2,3};`, `int x = {4 5};`, `union u { int x; char c[8]; } w = {258};` (give `w.c[1]`).

### C24-05 — A local array

Trace `int main(void) { long r[3] = {7}; return r[0] + r[2]; }`. Give `r`'s address, the zeroing count, which element stores are emitted, the frame size, and the exit status. Would anything change if `r` were `static`?

### C24-06 — A redirected initializer

For `int a[1]; int *q = a; int a[3] = {1, 2, 3};`, say which instruction in `q`'s routine is patched when the third line is read, what it pointed to before, and what `q[2]` is at runtime. Then predict the outcome if the first line is deleted, and separately if the second and third lines are swapped.

### C24-07 — Through the kernel door

Portable libc's `fopen` calls `open` on a file that does not exist. Give the raw RAX value, the value the body returns, and what `fopen` returns. Then answer the same for the old pnut boundary. Separately: `lseek` on a sparse file returns `5368709120`. What does the body return, and what would a caller see if `lseek` had been registered as returning `int`?

### C24-08 — Which refusal, and what happens?

`tcc-seed` is given each of these sources. Name the refusal body reached, if any, its exact message length in bytes, and the recipe's reaction: (a) a file using `0x1p3`; (b) a file using `__DATE__`; (c) a file with a missing semicolon; (d) the recipe's own compile of `tcc.c` into `tcc-boot0`. Why does the profile not simply define these three names as functions that return zero?

### C24-09 — Who built it?

For each file, name the program that produced it and the check the recipe applies: the runner, `build-out/tcc-bootstrap/simple-patch`, `tcc-0.9.27/tccgen.c` after patching, `tcc-seed`, `build/boot0-lib/libc.a`, `tcc-boot1`, `tcc-boot3`, the final `build/boot2-lib/libc.a`, and the last `bintools`.

### C24-10 — Return without the tables

After working on something else, answer each with its deciding rule first:

- Why are the opening program's data bytes zero, and why is that not a bug?
- Why does `tcc-boot3` reuse `build/boot2-lib` instead of using `build/boot3-lib`?
- A reviewer says the fixed point proves the Forth compiler correct. What does it establish, and what does it not?
- Why must portable libc and TinyCC form one translation unit for `tcc-seed`, but not for `tcc-boot0`?

If the image questions go wrong, rebuild the order: entry, runtime, declarations with their routines, dispatcher, data. If the route questions go wrong, redraw the generation table with one column for the compiler and one for the library directory. Use the feedback to repair that one step, then try an answer-free changed case from the solution page.

## What we can now carry forward

An initialized static object in this profile is code. Its routine is placed where the declaration is, jumped over, queued, and called once by the dispatcher before `main`. That reuses the compiler's single relocation mechanism for initializers, and a category guard keeps the routines within what a constant initializer may say. A local initializer runs in place, after zeroing any array or struct. The kernel boundary turns Linux's error range into −1 for portable libc's tests, and three names that the libc-plus-TinyCC unit lacks fail closed with status 125.

From there the compiler leaves the book. One 25-line translation unit of libc and TinyCC becomes `tcc-seed`; Forth-built helpers have unpacked and patched its sources from raw archives; and TinyCC rebuilds itself through four generations until the executable and the object stop changing. The fixed point and the runtime tests are TinyCC's evidence, attributed to the repository's own runs. Each check proves its own claim and no more.
